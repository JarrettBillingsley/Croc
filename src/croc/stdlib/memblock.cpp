
#include <limits>
#include <type_traits>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"
#include "croc/util/array.hpp"

#define checkMemblockParam(t, n) (croc_ex_checkParam((t), (n), CrocType_Memblock), getMemblock(Thread::from((t)), (n)))

namespace croc
{
	namespace
	{
	word_t _new(CrocThread* t)
	{
		auto size = croc_ex_checkIntParam(t, 1);

		if(size < 0 || size > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid size (%" CROC_INTEGER_FORMAT ")", size);

		bool haveFill = croc_isValidIndex(t, 2);
		auto fill = haveFill ? croc_ex_checkIntParam(t, 2) : 0;

		croc_memblock_new(t, cast(uword)size);

		if(haveFill)
			getMemblock(Thread::from(t), -1)->data.fill(cast(uint8_t)fill);

		return 1;
	}

	word_t _fromArray(CrocThread* t)
	{
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

	word_t _toString(CrocThread* t)
	{
		auto mb = checkMemblockParam(t, 0);

		CrocStrBuffer b;
		croc_ex_buffer_init(t, &b);
		croc_ex_buffer_addString(&b, "memblock[");

		bool first = true;

		for(auto val: mb->data)
		{
			if(first)
				first = false;
			else
				croc_ex_buffer_addString(&b, ", ");

			croc_pushFormat(t, "%u", val);
			croc_ex_buffer_addTop(&b);
		}

		croc_ex_buffer_addChar(&b, ']');
		croc_ex_buffer_finish(&b);
		return 1;
	}

	word_t _dup(CrocThread* t)
	{
		auto mb = checkMemblockParam(t, 0);
		croc_memblock_new(t, mb->data.length);
		getMemblock(Thread::from(t), -1)->data.slicea(mb->data);
		return 1;
	}

	word_t _ownData(CrocThread* t)
	{
		croc_pushBool(t, checkMemblockParam(t, 0)->ownData);
		return 1;
	}

	word_t _fill(CrocThread* t)
	{
		auto mb = checkMemblockParam(t, 0);
		mb->data.fill(cast(uint8_t)croc_ex_checkIntParam(t, 1));
		return 0;
	}

	word_t _fillSlice(CrocThread* t)
	{
		auto data = checkMemblockParam(t, 0)->data;

		auto lo = croc_ex_optIntParam(t, 1, 0);
		auto hi = croc_ex_optIntParam(t, 2, data.length);
		auto val = cast(uint8_t)croc_ex_checkIntParam(t, 3);

		if(lo < 0)
			lo += data.length;

		if(hi < 0)
			hi += data.length;

		if(lo < 0 || hi < lo || hi > data.length)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid slice indices %" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT " (memblock length: %u)",
				lo, hi, data.length);

		data.slice(cast(uword)lo, cast(uword)hi).fill(val);
		return 0;
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

	word_t _copy(CrocThread* t)
	{
		auto dst = checkMemblockParam(t, 0)->data;
		auto dstOffs = croc_ex_checkIntParam(t, 1);
		auto src = checkMemblockParam(t, 2)->data;
		auto srcOffs = croc_ex_checkIntParam(t, 3);
		auto size = croc_ex_checkIntParam(t, 4);

		if(size < 0 || size > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError",  "Invalid size: %" CROC_INTEGER_FORMAT, size);
		else if(dstOffs < 0 || dstOffs > dst.length)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid destination offset %" CROC_INTEGER_FORMAT " (memblock length: %u)", dstOffs, dst.length);
		else if(srcOffs < 0 || srcOffs > src.length)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid source offset %" CROC_INTEGER_FORMAT " (memblock length: %u)", srcOffs, src.length);
		else if(dstOffs + size > dst.length)
			croc_eh_throwStd(t, "BoundsError", "Copy size exceeds size of destination memblock");
		else if(srcOffs + size > src.length)
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

	word_t _compare(CrocThread* t)
	{
		auto lhs = checkMemblockParam(t, 0)->data;
		auto lhsOffs = croc_ex_checkIntParam(t, 1);
		auto rhs = checkMemblockParam(t, 2)->data;
		auto rhsOffs = croc_ex_checkIntParam(t, 3);
		auto size = croc_ex_checkIntParam(t, 4);

		if(size < 0 || size > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError",  "Invalid size: %" CROC_INTEGER_FORMAT, size);
		else if(lhsOffs < 0 || lhsOffs > lhs.length)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid lhs offset %" CROC_INTEGER_FORMAT " (memblock length: %u)", lhsOffs, lhs.length);
		else if(rhsOffs < 0 || rhsOffs > rhs.length)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid rhs offset %" CROC_INTEGER_FORMAT " (memblock length: %u)", rhsOffs, rhs.length);
		else if(lhsOffs + size > lhs.length)
			croc_eh_throwStd(t, "BoundsError", "Size exceeds size of lhs memblock");
		else if(rhsOffs + size > rhs.length)
			croc_eh_throwStd(t, "BoundsError", "Size exceeds size of rhs memblock");

		croc_pushInt(t, lhs.slice(lhsOffs, lhsOffs + size).cmp(rhs.slice(rhsOffs, rhsOffs + size)));
		return 1;
	}

	template<bool reverse>
	word_t _commonFindItem(CrocThread* t)
	{
		// Source (search) memblock
		auto src = checkMemblockParam(t, 0)->data;

		// Item to search for
		auto item = croc_ex_checkIntParam(t, 1);

		if(item < 0 || item > 255)
			croc_eh_throwStd(t, "RangeError", "Invalid search value: %" CROC_INTEGER_FORMAT, item);

		// Start index
		auto start = croc_ex_optIntParam(t, 2, reverse ? (src.length - 1) : 0);

		if(start < 0)
			start += src.length;

		if(start < 0 || start > src.length)
			croc_eh_throwStd(t, "BoundsError", "Invalid start index %" CROC_INTEGER_FORMAT, start);

		// Search
		if(reverse)
			croc_pushInt(t, arrFindElemRev(src, cast(uint8_t)item, start));
		else
			croc_pushInt(t, arrFindElem(src, cast(uint8_t)item, start));

		return 1;
	}

	template<bool reverse>
	word_t _commonFind(CrocThread* t)
	{
		// Source (search) memblock
		auto src = checkMemblockParam(t, 0)->data;

		// Pattern to search for
		auto pat = checkMemblockParam(t, 1)->data;

		// Start index
		auto start = croc_ex_optIntParam(t, 2, reverse ? (src.length - 1) : 0);

		if(start < 0)
			start += src.length;

		if(start < 0 || start > src.length)
			croc_eh_throwStd(t, "BoundsError", "Invalid start index %" CROC_INTEGER_FORMAT, start);

		// Search
		if(reverse)
			croc_pushInt(t, arrFindSubRev(src, pat, start));
		else
			croc_pushInt(t, arrFindSub(src, pat, start));

		return 1;
	}

	word_t _opEquals(CrocThread* t)
	{
		auto mb = checkMemblockParam(t, 0);
		auto other = checkMemblockParam(t, 1);

		if(croc_is(t, 0, 1))
			croc_pushBool(t, true);
		else
			croc_pushBool(t, mb->data == other->data);

		return 1;
	}

	word_t _opCmp(CrocThread* t)
	{
		auto mb = checkMemblockParam(t, 0);
		auto other = checkMemblockParam(t, 1);

		if(croc_is(t, 0, 1))
			croc_pushInt(t, 0);
		else
			croc_pushInt(t, mb->data.cmp(other->data));

		return 1;
	}

	word_t _opCat(CrocThread* t)
	{
		auto mb = checkMemblockParam(t, 0);
		auto other = checkMemblockParam(t, 1);
		push(Thread::from(t), Value::from(mb->cat(Thread::from(t)->vm->mem, other)));
		return 1;
	}

	word_t _opCatAssign(CrocThread* t)
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

	word_t _iterator(CrocThread* t)
	{
		auto mb = checkMemblockParam(t, 0);
		auto index = croc_ex_checkIntParam(t, 1) + 1;

		if(index >= mb->data.length)
			return 0;

		croc_pushInt(t, index);
		croc_pushInt(t, mb->data[cast(uword)index]);
		return 2;
	}

	word_t _iteratorReverse(CrocThread* t)
	{
		auto mb = checkMemblockParam(t, 0);
		auto index = croc_ex_checkIntParam(t, 1) - 1;

		if(index < 0)
			return 0;

		croc_pushInt(t, index);
		croc_pushInt(t, mb->data[cast(uword)index]);
		return 2;
	}

	word_t _opApply(CrocThread* t)
	{
		auto mb = checkMemblockParam(t, 0);

		if(strcmp(croc_ex_optStringParam(t, 1, ""), "reverse") == 0)
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

	const CrocRegisterFunc _globalFuncs[] =
	{
		{"new",       2, &_new      },
		{"fromArray", 1, &_fromArray},
		{nullptr, 0, nullptr}
	};

	const CrocRegisterFunc _methodFuncs[] =
	{
		{"toString",      0, &_toString             },
		{"dup",           0, &_dup                  },
		{"ownData",       0, &_ownData              },
		{"fill",          1, &_fill                 },
		{"fillSlice",     3, &_fillSlice            },
		{"readInt8",      1, &_rawRead<int8_t>      },
		{"readInt16",     1, &_rawRead<int16_t>     },
		{"readInt32",     1, &_rawRead<int32_t>     },
		{"readInt64",     1, &_rawRead<int64_t>     },
		{"readUInt8",     1, &_rawRead<uint8_t>     },
		{"readUInt16",    1, &_rawRead<uint16_t>    },
		{"readUInt32",    1, &_rawRead<uint32_t>    },
		{"readUInt64",    1, &_rawRead<uint64_t>    },
		{"readFloat32",   1, &_rawRead<float>       },
		{"readFloat64",   1, &_rawRead<double>      },
		{"writeInt8",     2, &_rawWrite<int8_t>     },
		{"writeInt16",    2, &_rawWrite<int16_t>    },
		{"writeInt32",    2, &_rawWrite<int32_t>    },
		{"writeInt64",    2, &_rawWrite<int64_t>    },
		{"writeUInt8",    2, &_rawWrite<uint8_t>    },
		{"writeUInt16",   2, &_rawWrite<uint16_t>   },
		{"writeUInt32",   2, &_rawWrite<uint32_t>   },
		{"writeUInt64",   2, &_rawWrite<uint64_t>   },
		{"writeFloat32",  2, &_rawWrite<float>      },
		{"writeFloat64",  2, &_rawWrite<double>     },
		{"copy",          4, &_copy                 },
		{"compare",       4, &_compare              },
		{"findItem",      2, &_commonFindItem<false>},
		{"rfindItem",     2, &_commonFindItem<true> },
		{"find",          2, &_commonFind<false>    },
		{"rfind",         2, &_commonFind<true>     },
		{"opEquals",      1, &_opEquals             },
		{"opCmp",         1, &_opCmp                },
		{"opCat",         1, &_opCat                },
		{"opCatAssign",  -1, &_opCatAssign          },
		{nullptr, 0, nullptr}
	};

	word loader(CrocThread* t)
	{
		croc_ex_registerGlobals(t, _globalFuncs);

		croc_namespace_new(t, "memblock");
			croc_ex_registerFields(t, _methodFuncs);
			croc_field(t, -1, "opCatAssign"); croc_fielda(t, -2, "append");

				croc_function_new(t, "iterator", 1, &_iterator, 0);
				croc_function_new(t, "iteratorReverse", 1, &_iteratorReverse, 0);
			croc_function_new(t, "opApply", 1, &_opApply, 2);
			croc_fielda(t, -2, "opApply");
		croc_vm_setTypeMT(t, CrocType_Memblock);
		return 0;
	}
	}

	void initMemblockLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "memblock", &loader);
		croc_ex_importModuleNoNS(t, "memblock");
	}
}