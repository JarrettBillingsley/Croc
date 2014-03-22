
#include <limits>
#include <type_traits>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"
#include "croc/util/array.hpp"

#define checkMemblockParam(t, n) (croc_ex_checkParam((t), (n), CrocType_Memblock), getMemblock(Thread::from((t)), (n)))

namespace croc
{
	namespace
	{
DBeginList(_globalFuncs)
	Docstr(DFunc("new") DParam("size", "int") DParamD("fill", "int", "0")
	R"(Creates a new memblock.

	\param[size] is the size of the memblock to create, in bytes. Can be 0.
	\param[fill] is the value to fill each byte of the memblock with. Defaults to 0. The value will be wrapped to the
	range of an unsigned byte.

	\throws[RangeError] if \tt{size} is invalid (negative or too large to be represented).)"),

	"new", 2, [](CrocThread* t) -> word_t
	{
		auto size = croc_ex_checkIntParam(t, 1);

		if(size < 0 || cast(uword)size > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid size (%" CROC_INTEGER_FORMAT ")", size);

		bool haveFill = croc_isValidIndex(t, 2);
		auto fill = haveFill ? croc_ex_checkIntParam(t, 2) : 0;

		croc_memblock_new(t, cast(uword)size);

		if(haveFill)
			getMemblock(Thread::from(t), -1)->data.fill(cast(uint8_t)fill);

		return 1;
	}

DListSep()
	Docstr(DFunc("fromArray") DParam("arr", "array")
	R"(Creates a new memblock using the contents of the array as the data.

	The new memblock will be the same length as the array. The array must hold nothing but integers. They are not
	required to be in the range \tt{[0 .. 255]}; just the lower 8 bits will be used from each integer.

	\param[arr] is the array holding the data from which the memblock will be constructed.
	\returns the new memblock.

	\throws[TypeError] if \tt{arr} has any non-integer elements.)"),

	"fromArray", 1, [](CrocThread* t) -> word_t	{
		croc_ex_checkParam(t, 1, CrocType_Array);
		auto arr = getArray(Thread::from(t), 1)->toDArray();

		croc_memblock_new(t, arr.length);
		auto data = getMemblock(Thread::from(t), -1)->data;

		uword i = 0;
		for(auto &slot: arr)
		{
			if(slot.value.type != CrocType_Int)
				croc_eh_throwStd(t, "TypeError", "Array must be all integers");

			data[i++] = cast(uint8_t)slot.value.mInt;
		}

		return 1;
	}
DEndList()

	template<bool reverse>
	word_t _commonFindByte(CrocThread* t)
	{
		auto src = checkMemblockParam(t, 0)->data;
		auto item = croc_ex_checkIntParam(t, 1);

		if(item < 0 || item > 255)
			croc_eh_throwStd(t, "RangeError", "Invalid search value: %" CROC_INTEGER_FORMAT, item);

		auto start = croc_ex_optIndexParam(t, 2, src.length, "start", reverse ? (src.length - 1) : 0);

		if(reverse)
			croc_pushInt(t, arrFindElemRev(src, cast(uint8_t)item, start));
		else
			croc_pushInt(t, arrFindElem(src, cast(uint8_t)item, start));

		return 1;
	}

	template<bool reverse>
	word_t _commonFind(CrocThread* t)
	{
		auto src = checkMemblockParam(t, 0)->data;
		auto pat = checkMemblockParam(t, 1)->data;
		auto start = croc_ex_optIndexParam(t, 2, src.length, "start", reverse ? (src.length - 1) : 0);

		if(reverse)
			croc_pushInt(t, arrFindSubRev(src, pat, start));
		else
			croc_pushInt(t, arrFindSub(src, pat, start));

		return 1;
	}

	template<typename T>
	word_t _rawRead(CrocThread* t)
	{
		auto data = checkMemblockParam(t, 0)->data;
		word maxIdx = (data.length < sizeof(T)) ? -1 : (data.length - sizeof(T));
		auto idx = croc_ex_checkIntParam(t, 1);

		if(idx < 0)
			idx += data.length;

		if(idx < 0 || idx > maxIdx)
			croc_eh_throwStd(t, "BoundsError", "Invalid index '%" CROC_INTEGER_FORMAT "'", idx);

		if(std::is_integral<T>::value)
			croc_pushInt(t, cast(crocint)*(cast(T*)(data.ptr + idx)));
		else
			croc_pushFloat(t, cast(crocfloat)*(cast(T*)(data.ptr + idx)));

		return 1;
	}

	template<typename T>
	word_t _rawWrite(CrocThread* t)
	{
		auto data = checkMemblockParam(t, 0)->data;
		word maxIdx = (data.length < sizeof(T)) ? -1 : (data.length - sizeof(T));
		auto idx = croc_ex_checkIntParam(t, 1);

		if(idx < 0)
			idx += data.length;

		if(idx < 0 || idx > maxIdx)
			croc_eh_throwStd(t, "BoundsError", "Invalid index '%" CROC_INTEGER_FORMAT "'", idx);

		if(std::is_integral<T>::value)
			*(cast(T*)(data.ptr + idx)) = cast(T)croc_ex_checkIntParam(t, 2);
		else
			*(cast(T*)(data.ptr + idx)) = cast(T)croc_ex_checkNumParam(t, 2);

		return 0;
	}

DBeginList(_methodFuncs)
	Docstr(DFunc("toString")
	R"(\returns a string representation of this memblock in the form \tt{"memblock[contents]"}.

	For example, \tt{memblock.new(3, 10).toString()} would give the string \tt{"memblock[10, 10, 10]"}.

	If the memblock is more than 128 bytes, the contents will be truncated with an ellipsis.)"),

	"toString", 0, [](CrocThread* t) -> word_t
	{
		auto data = checkMemblockParam(t, 0)->data;

		CrocStrBuffer b;
		croc_ex_buffer_init(t, &b);
		croc_ex_buffer_addString(&b, "memblock[");

		bool first = true;

		for(auto val: (data.length > 128 ? data.slice(0, 128) : data))
		{
			if(first)
				first = false;
			else
				croc_ex_buffer_addString(&b, ", ");

			croc_pushFormat(t, "%u", val);
			croc_ex_buffer_addTop(&b);
		}

		if(data.length > 128)
			croc_ex_buffer_addString(&b, ", ...");

		croc_ex_buffer_addChar(&b, ']');
		croc_ex_buffer_finish(&b);
		return 1;
	}

DListSep()
	Docstr(DFunc("dup")
	R"(\returns a duplicate of this memblock.

	The new memblock will have the same length and this memblock's data will be copied into it. The new memblock will
	own its data, regardless of whether or not this memblock does.)"),

	"dup", 0, [](CrocThread* t) -> word_t
	{
		auto mb = checkMemblockParam(t, 0);
		croc_memblock_new(t, mb->data.length);
		getMemblock(Thread::from(t), -1)->data.slicea(mb->data);
		return 1;
	}

DListSep()
	Docstr(DFunc("ownData")
	R"(\returns a bool indicating whether or not this memblock owns its data. If true, it can be resized freely.)"),

	"ownData", 0, [](CrocThread* t) -> word_t
	{
		croc_pushBool(t, checkMemblockParam(t, 0)->ownData);
		return 1;
	}

DListSep()
	Docstr(DFunc("fill") DParam("val", "int")
	R"(Fills every byte of this memblock with the given value (wrapped to the range of an unsigned byte).

	\param[val] is the value to fill the memblock with.)"),

	"fill", 1, [](CrocThread* t) -> word_t
	{
		auto mb = checkMemblockParam(t, 0);
		mb->data.fill(cast(uint8_t)croc_ex_checkIntParam(t, 1));
		return 0;
	}

DListSep()
	Docstr(DFunc("fillSlice") DParamD("lo", "int", "0") DParamD("hi", "int", "#this") DParam("val", "int")
	R"(Fills a slice of this memblock with the given value (wrapped to the range of an unsigned byte). The slice indices
	work exactly like anywhere else.

	\param[val] is the value to fill the slice with.)"),

	"fillSlice", 3, [](CrocThread* t) -> word_t
	{
		auto data = checkMemblockParam(t, 0)->data;
		uword_t lo, hi;
		lo = croc_ex_checkSliceParams(t, 1, data.length, "memblock", &hi);
		auto val = cast(uint8_t)croc_ex_checkIntParam(t, 3);
		data.slice(cast(uword)lo, cast(uword)hi).fill(val);
		return 0;
	}

DListSep()
	Docstr(DFunc("readInt8") DParam("offs", "int")
	R"(These functions all read a numerical value of the given type from the byte offset \tt{offs}.

	The "Int" versions read a signed integer of the given number of bits. The "Uint" versions read an unsigned integer
	of the given number of bits. Note that \tt{readUInt64} will return the same values as \tt{readInt64} as Croc's
	\tt{int} type is a signed 64-bit integer, and thus cannot represent the range of unsigned 64-bit integers. It is
	included for completeness.

	The "Float" versions read an IEEE 754 floating point number. \tt{readFloat32} reads a single-precision float while
	\tt{readFloat64} reads a double-precision float.

	\param[offs] is the byte offset from where the value should be read. Can be negative to mean from the end of the
	memblock. Does not have to be aligned.

	\returns the value read, as either an \tt{int} or a \tt{float}, depending on the function.

	\throws[BoundsError] if \tt{offs < 0 || offs >= #this - (size of value)}.

	\see \link{Vector} for a typed numerical array type which may suit your needs better than raw memblock access.)"),
	"readInt8", 1, &_rawRead<int8_t>
DListSep()
	Docstr(DFunc("readInt16") DParam("offs", "int") R"(ditto)"),
	"readInt16", 1, &_rawRead<int16_t>
DListSep()
	Docstr(DFunc("readInt32") DParam("offs", "int") R"(ditto)"),
	"readInt32", 1, &_rawRead<int32_t>
DListSep()
	Docstr(DFunc("readInt64") DParam("offs", "int") R"(ditto)"),
	"readInt64", 1, &_rawRead<int64_t>
DListSep()
	Docstr(DFunc("readUInt8") DParam("offs", "int") R"(ditto)"),
	"readUInt8", 1, &_rawRead<uint8_t>
DListSep()
	Docstr(DFunc("readUInt16") DParam("offs", "int") R"(ditto)"),
	"readUInt16", 1, &_rawRead<uint16_t>
DListSep()
	Docstr(DFunc("readUInt32") DParam("offs", "int") R"(ditto)"),
	"readUInt32", 1, &_rawRead<uint32_t>
DListSep()
	Docstr(DFunc("readUInt64") DParam("offs", "int") R"(ditto)"),
	"readUInt64", 1, &_rawRead<uint64_t>
DListSep()
	Docstr(DFunc("readFloat32") DParam("offs", "int") R"(ditto)"),
	"readFloat32", 1, &_rawRead<float>
DListSep()
	Docstr(DFunc("readFloat64") DParam("offs", "int") R"(ditto)"),
	"readFloat64", 1, &_rawRead<double>

DListSep()
	Docstr(DFunc("writeInt8") DParam("offs", "int") DParam("val", "int")
	R"(These functions all write the numerical value \tt{val} of the given type to the byte offset \tt{offs}.

	The "Int" versions write a signed integer of the given number of bits. The "Uint" versions write an unsigned integer
	of the given number of bits. Note that \tt{writeUInt64} will in fact write an unsigned 64-bit integer, even though
	Croc's \tt{int} type is a signed 64-bit integer.

	The "Float" versions write an IEEE 754 floating point number. \tt{writeFloat32} writes a single-precision float
	while \tt{writeFloat64} writes a double-precision float.

	\param[offs] the byte offset to which the value should be written. Can be negative to mean from the end of the
	memblock.
	\param[val] the value to write.

	\throws[BoundsError] if \tt{offs < 0 || offs >= #this - (size of value)}.

	\see \link{Vector} for a typed numerical array type which may suit your needs better than raw memblock access.)"),
	"writeInt8", 2, &_rawWrite<int8_t>
DListSep()
	Docstr(DFunc("writeInt16") DParam("offs", "int") DParam("val", "int") R"(ditto)"),
	"writeInt16", 2, &_rawWrite<int16_t>
DListSep()
	Docstr(DFunc("writeInt32") DParam("offs", "int") DParam("val", "int") R"(ditto)"),
	"writeInt32", 2, &_rawWrite<int32_t>
DListSep()
	Docstr(DFunc("writeInt64") DParam("offs", "int") DParam("val", "int") R"(ditto)"),
	"writeInt64", 2, &_rawWrite<int64_t>
DListSep()
	Docstr(DFunc("writeUInt8") DParam("offs", "int") DParam("val", "int") R"(ditto)"),
	"writeUInt8", 2, &_rawWrite<uint8_t>
DListSep()
	Docstr(DFunc("writeUInt16") DParam("offs", "int") DParam("val", "int") R"(ditto)"),
	"writeUInt16", 2, &_rawWrite<uint16_t>
DListSep()
	Docstr(DFunc("writeUInt32") DParam("offs", "int") DParam("val", "int") R"(ditto)"),
	"writeUInt32", 2, &_rawWrite<uint32_t>
DListSep()
	Docstr(DFunc("writeUInt64") DParam("offs", "int") DParam("val", "int") R"(ditto)"),
	"writeUInt64", 2, &_rawWrite<uint64_t>
DListSep()
	Docstr(DFunc("writeFloat32") DParam("offs", "int") DParam("val", "int|float") R"(ditto)"),
	"writeFloat32", 2, &_rawWrite<float>
DListSep()
	Docstr(DFunc("writeFloat64") DParam("offs", "int") DParam("val", "int|float") R"(ditto)"),
	"writeFloat64", 2, &_rawWrite<double>

DListSep()
	Docstr(DFunc("findByte") DParam("val", "int") DParamD("start", "int", "0")
	R"(Find a byte equal to \tt{val} in this memblock starting at byte offset \tt{start} and going right.

	\param[val] is the byte to search for.
	\param[start] is the byte offset to start at, which defaults to 0.

	\returns the byte offset of the first byte equal to \tt{val} found, or \tt{#this} if not found.

	\throws[RangeError] if \tt{val < 0 || val > 255}.
	\throws[BoundsError] if \tt{start} is invalid.)"),
	"findByte", 2, &_commonFindByte<false>

DListSep()
	Docstr(DFunc("rfindByte") DParam("val", "int") DParamD("start", "int", "#this - 1")
	R"(Find a byte equal to \tt{val} in this memblock starting at byte offset \tt{start} and going left.

	\param[val] is the byte to search for.
	\param[start] is the byte offset to start at, which defaults to the last byte.

	\returns the byte offset of the first byte equal to \tt{val} found, or \tt{#this} if not found.

	\throws[RangeError] if \tt{val < 0 || val > 255}.
	\throws[BoundsError] if \tt{start} is invalid.)"),
	"rfindByte", 2, &_commonFindByte<true>

DListSep()
	Docstr(DFunc("findBytes") DParam("sub", "memblock") DParamD("start", "int", "0")
	R"(Same as \link{findByte}, except searches for a sequence of bytes identical to the memblock \tt{sub}.)"),
	"findBytes", 2, &_commonFind<false>

DListSep()
	Docstr(DFunc("rfindBytes")
	R"(Same as \link{rfindByte}, except searches for a sequence of bytes identical to the memblock \tt{sub}.)"),
	"rfindBytes", 2, &_commonFind<true>

DListSep()
	Docstr(DFunc("copy") DParam("dstOffs", "int") DParam("src", "memblock") DParam("srcOffs", "int")
		DParam("size", "int")
	R"(Copies a block of memory from one memblock to another, or within the same memblock. Also handles overlapping
	copies. Croc's version of memcpy/memmove!

	\param[dstOffs] is the byte offset in this memblock to where the data should be copied. May \b{not} be negative.
	\param[src] is the memblock from which the data should be copied. Can be the same memblock as \tt{this}.
	\param[srcOffs] is the byte offset in the source memblock from which the data should be copied. May \b{not} be
		negative.
	\param[size] is the number of bytes to copy. 0 is an acceptable value.

	\throws[RangeError] if the \tt{size} parameter is invalid.
	\throws[BoundsError] if \tt{dstOffs} or \tt{srcOffs} are invalid indices into their respective memblocks, or if
		either the source or destination ranges extend past the ends of their respective memblocks.)"),

	"copy", 4, [](CrocThread* t) -> word_t
	{
		auto dst = checkMemblockParam(t, 0)->data;
		auto dstOffs = croc_ex_checkIntParam(t, 1);
		auto src = checkMemblockParam(t, 2)->data;
		auto srcOffs = croc_ex_checkIntParam(t, 3);
		auto size = croc_ex_checkIntParam(t, 4);

		if(size < 0 || cast(uword)size > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid size: %" CROC_INTEGER_FORMAT, size);
		else if(dstOffs < 0 || cast(uword)dstOffs > dst.length)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid destination offset %" CROC_INTEGER_FORMAT " (memblock length: %" CROC_SIZE_T_FORMAT ")",
				dstOffs, dst.length);
		else if(srcOffs < 0 || cast(uword)srcOffs > src.length)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid source offset %" CROC_INTEGER_FORMAT " (memblock length: %" CROC_SIZE_T_FORMAT ")",
				srcOffs, src.length);
		else if(cast(uword)(dstOffs + size) > dst.length)
			croc_eh_throwStd(t, "BoundsError", "Copy size exceeds size of destination memblock");
		else if(cast(uword)(srcOffs + size) > src.length)
			croc_eh_throwStd(t, "BoundsError", "Copy size exceeds size of source memblock");

		auto srcPtr = src.ptr + srcOffs;
		auto dstPtr = dst.ptr + dstOffs;
		auto dist = dstPtr - srcPtr;
		if(dist < 0) dist = -dist;

		if(dist < size)
			memmove(dstPtr, srcPtr, cast(uword)size);
		else
			memcpy(dstPtr, srcPtr, cast(uword)size);

		return 0;
	}

DListSep()
	Docstr(DFunc("compare") DParam("lhsOffs", "int") DParam("rhs", "memblock") DParam("rhsOffs", "int")
		DParam("size", "int")
	R"(Compares slices of two memblocks (or two slices into the same memblock) lexicographically and returns a
	comparison result. Croc's version of memcmp!

	\param[lhsOffs] is the byte offset of the beginning of the slice in this memblock. May \b{not} be negative.
	\param[rhs] is the memblock to which this one will be compared. Can be the same memblock as \tt{this}.
	\param[rhsOffs] is the byte offset of the beginning of the slice in \tt{rhs}. May \b{not} be negative.
	\param[size] is the number of bytes to compare. 0 is an acceptable value.

	\returns a negative integer if the slice from this memblock is less than the slice from \tt{rhs}, a positive integer
		if greater, and 0 if they are byte-for-byte equal.

	\throws[RangeError] if the \tt{size} parameter is invalid.
	\throws[BoundsError] if \tt{lhsOffs} or \tt{rhsOffs} are invalid indices into their respective memblocks, or if
		either the lhs or rhs ranges extend past the ends of their respective memblocks.)"),

	"compare", 4, [](CrocThread* t) -> word_t
	{
		auto lhs = checkMemblockParam(t, 0)->data;
		auto lhsOffs = croc_ex_checkIntParam(t, 1);
		auto rhs = checkMemblockParam(t, 2)->data;
		auto rhsOffs = croc_ex_checkIntParam(t, 3);
		auto size = croc_ex_checkIntParam(t, 4);

		if(size < 0 || cast(uword)size > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid size: %" CROC_INTEGER_FORMAT, size);
		else if(lhsOffs < 0 || cast(uword)lhsOffs > lhs.length)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid lhs offset %" CROC_INTEGER_FORMAT " (memblock length: %" CROC_SIZE_T_FORMAT ")",
				lhsOffs, lhs.length);
		else if(rhsOffs < 0 || cast(uword)rhsOffs > rhs.length)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid rhs offset %" CROC_INTEGER_FORMAT " (memblock length: %" CROC_SIZE_T_FORMAT ")",
				rhsOffs, rhs.length);
		else if(cast(uword)(lhsOffs + size) > lhs.length)
			croc_eh_throwStd(t, "BoundsError", "Size exceeds size of lhs memblock");
		else if(cast(uword)(rhsOffs + size) > rhs.length)
			croc_eh_throwStd(t, "BoundsError", "Size exceeds size of rhs memblock");

		croc_pushInt(t, lhs.slice(lhsOffs, lhsOffs + size).cmp(rhs.slice(rhsOffs, rhsOffs + size)));
		return 1;
	}

DListSep()
	Docstr(DFunc("opEquals") DParam("other", "memblock")
	R"(Compares two memblocks for exact data equality.

	\returns \tt{true} if both memblocks are the same length and contain the exact same data. Returns \tt{false}
	otherwise.)"),

	"opEquals", 1, [](CrocThread* t) -> word_t
	{
		auto mb = checkMemblockParam(t, 0);
		auto other = checkMemblockParam(t, 1);

		if(croc_is(t, 0, 1))
			croc_pushBool(t, true);
		else
			croc_pushBool(t, mb->data == other->data);

		return 1;
	}

DListSep()
	Docstr(DFunc("opCmp") DParam("other", "memblock")
	R"(Compares the contents of two memblocks lexicographically.

	\returns a negative integer if \tt{this} compares before \tt{other}, a positive integer if \tt{this} compares after
	\tt{other}, and 0 if \tt{this} and \tt{other} have identical contents.)"),

	"opCmp", 1, [](CrocThread* t) -> word_t
	{
		auto mb = checkMemblockParam(t, 0);
		auto other = checkMemblockParam(t, 1);

		if(croc_is(t, 0, 1))
			croc_pushInt(t, 0);
		else
			croc_pushInt(t, mb->data.cmp(other->data));

		return 1;
	}

DListSep()
	Docstr(DFunc("opCat") DParam("other", "memblock")
	R"(Concatenates two memblocks, returning a new memblock whose contents are a concatenation of the two sources.

	\param[other] the second memblock in the concatenation.
	\returns a new memblock whose contents are a concatenation of \tt{this} followed by \tt{other}.)"),

	"opCat", 1, [](CrocThread* t) -> word_t
	{
		auto mb = checkMemblockParam(t, 0);
		auto other = checkMemblockParam(t, 1);
		push(Thread::from(t), Value::from(mb->cat(Thread::from(t)->vm->mem, other)));
		return 1;
	}

DListSep()
	Docstr(DFunc("opCatAssign") DVararg
	R"(Appends memblocks to the end of this memblock, resizing this memblock to hold all the contents and copying the
	contents from the source memblocks.

	\param[vararg] the memblocks to be appended.
	\throws[ValueError] if \tt{this} does not own its data (and therefore cannot be resized).
	\throws[RangeError] if the total length of \tt{this} after appending would be too large to be represented.)"),

	"opCatAssign", -1, [](CrocThread* t) -> word_t
	{
		auto mb = checkMemblockParam(t, 0);
		auto data = mb->data;

		if(!mb->ownData)
			croc_eh_throwStd(t, "ValueError", "Attempting to append to a memblock which does not own its data");

		croc_ex_checkAnyParam(t, 1);
		auto numParams = croc_getStackSize(t) - 1;
		uint64_t totalLen = data.length;

		for(uword i = 1; i <= numParams; i++)
			totalLen += checkMemblockParam(t, i)->data.length;

		if(totalLen > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid size (%" CROC_UINTEGER_FORMAT ")", totalLen);

		auto oldLen = data.length;
		auto t_ = Thread::from(t);
		mb->resize(t_->vm->mem, cast(uword)totalLen);
		uword j = oldLen;

		for(uword i = 1; i <= numParams; i++)
		{
			if(croc_is(t, 0, i))
			{
				// special case for when we're appending a memblock to itself; use the old length
				memcpy(&data[j], data.ptr, oldLen);
				j += oldLen;
			}
			else
			{
				auto other = getMemblock(t_, i)->data;
				memcpy(&data[j], other.ptr, other.length);
				j += other.length;
			}
		}

		return 0;
	}
DEndList()

DBeginList(_opApply)
	nullptr,

	"iterator", 1, [](CrocThread* t) -> word_t
	{
		auto mb = checkMemblockParam(t, 0);
		auto index = croc_ex_checkIntParam(t, 1) + 1;

		if(cast(uword)index >= mb->data.length)
			return 0;

		croc_pushInt(t, index);
		croc_pushInt(t, mb->data[cast(uword)index]);
		return 2;
	}

DListSep()
	nullptr,

	"iteratorReverse", 1, [](CrocThread* t) -> word_t
	{
		auto mb = checkMemblockParam(t, 0);
		auto index = croc_ex_checkIntParam(t, 1) - 1;

		if(index < 0)
			return 0;

		croc_pushInt(t, index);
		croc_pushInt(t, mb->data[cast(uword)index]);
		return 2;
	}

DListSep()
	Docstr(DFunc("opApply") DParamD("mode", "string", "null")
	R"(Allows you to iterate over the contents of a memblock with \tt{foreach} loops.

	You can iterate forwards (the default) or backwards:

\code
local m = memblock.fromArray([1 2 3])

foreach(val; m)
	writeln(val) // prints 1 through 3

foreach(val; m, "reverse")
	writeln(val) // prints 3 through 1
\endcode

	\param[mode] is the iteration mode. Defaults to null, which means forwards; if passed "reverse", iterates
	backwards.)"),

	"opApply", 1, [](CrocThread* t) -> word_t
	{
		auto mb = checkMemblockParam(t, 0);

		if(croc_ex_optParam(t, 1, CrocType_String) && getCrocstr(t, 1) == ATODA("reverse"))
		{
			croc_pushUpval(t, 1);
			croc_dup(t, 0);
			croc_pushInt(t, mb->data.length);
		}
		else
		{
			croc_pushUpval(t, 0);
			croc_dup(t, 0);
			croc_pushInt(t, -1);
		}

		return 3;
	}
DEndList()

	word loader(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);

		croc_namespace_new(t, "memblock");
			registerFields(t, _methodFuncs);
			registerFieldUV(t, _opApply);
			croc_field(t, -1, "opCatAssign"); croc_fielda(t, -2, "append");
		croc_vm_setTypeMT(t, CrocType_Memblock);
		return 0;
	}
	}

	void initMemblockLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "memblock", &loader);
		croc_ex_importNS(t, "memblock");
#ifdef CROC_BUILTIN_DOCS
		CrocDoc doc;
		croc_ex_doc_init(t, &doc, __FILE__);
		croc_ex_doc_push(&doc,
		DModule("memblock")
		R"(The memblock library provides built-in methods for the \tt{memblock} type, as well as the only means to
		actually create memblocks.)");
			docFields(&doc, _globalFuncs);

			croc_vm_pushTypeMT(t, CrocType_Memblock);
				croc_ex_doc_push(&doc,
				DNs("memblock")
				R"(This is the method namespace for memblock objects.)");
				docFields(&doc, _methodFuncs);
				docFieldUV(&doc, _opApply);
				croc_ex_doc_pop(&doc, -1);
			croc_popTop(t);
		croc_ex_doc_pop(&doc, -1);
		croc_ex_doc_finish(&doc);
#endif
		croc_popTop(t);
	}
}