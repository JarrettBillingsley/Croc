
#include <cmath>
#include <limits>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"
#include "croc/util/array.hpp"

namespace croc
{
	namespace
	{
	enum TypeCode
	{
		TypeCode_i8,
		TypeCode_i16,
		TypeCode_i32,
		TypeCode_i64,
		TypeCode_u8,
		TypeCode_u16,
		TypeCode_u32,
		TypeCode_u64,
		TypeCode_f32,
		TypeCode_f64,
	};

	struct TypeStruct
	{
		uint8_t code;
		uint8_t itemSize;
		uint8_t sizeShift;
		const char* name;
	};

	const TypeStruct _typeStructs[] =
	{
		{TypeCode_i8,  1, 0, "i8" },
		{TypeCode_i16, 2, 1, "i16"},
		{TypeCode_i32, 4, 2, "i32"},
		{TypeCode_i64, 8, 3, "i64"},
		{TypeCode_u8,  1, 0, "u8" },
		{TypeCode_u16, 2, 1, "u16"},
		{TypeCode_u32, 4, 2, "u32"},
		{TypeCode_u64, 8, 3, "u64"},
		{TypeCode_f32, 4, 2, "f32"},
		{TypeCode_f64, 8, 3, "f64"},
	};

	const char* Data = "_data";
	const char* Kind = "_kind";

	struct Members
	{
		Memblock* data;
		const TypeStruct* kind;
		uword itemLength;
	};

	Value _rawIndex(Members& m, uword idx)
	{
		assert(idx < m.itemLength);

		switch(m.kind->code)
		{
			case TypeCode_i8:  return Value::from(cast(crocint)  (cast(int8_t*)  m.data->data.ptr)[idx]);
			case TypeCode_i16: return Value::from(cast(crocint)  (cast(int16_t*) m.data->data.ptr)[idx]);
			case TypeCode_i32: return Value::from(cast(crocint)  (cast(int32_t*) m.data->data.ptr)[idx]);
			case TypeCode_i64: return Value::from(cast(crocint)  (cast(int64_t*) m.data->data.ptr)[idx]);
			case TypeCode_u8:  return Value::from(cast(crocint)  (cast(uint8_t*) m.data->data.ptr)[idx]);
			case TypeCode_u16: return Value::from(cast(crocint)  (cast(uint16_t*)m.data->data.ptr)[idx]);
			case TypeCode_u32: return Value::from(cast(crocint)  (cast(uint32_t*)m.data->data.ptr)[idx]);
			case TypeCode_u64: return Value::from(cast(crocint)  (cast(uint64_t*)m.data->data.ptr)[idx]);
			case TypeCode_f32: return Value::from(cast(crocfloat)(cast(float*)   m.data->data.ptr)[idx]);
			case TypeCode_f64: return Value::from(cast(crocfloat)(cast(double*)  m.data->data.ptr)[idx]);
			default: assert(false); return Value::nullValue; // dummy
		}
	}

	void _rawIndexAssign(Members& m, uword idx, Value val)
	{
		assert(idx < m.itemLength);

		switch(m.kind->code)
		{
			case TypeCode_i8:  (cast(int8_t*)  m.data->data.ptr)[idx] = cast(int8_t)val.mInt;   return;
			case TypeCode_i16: (cast(int16_t*) m.data->data.ptr)[idx] = cast(int16_t)val.mInt;  return;
			case TypeCode_i32: (cast(int32_t*) m.data->data.ptr)[idx] = cast(int32_t)val.mInt;  return;
			case TypeCode_i64: (cast(int64_t*) m.data->data.ptr)[idx] = cast(int64_t)val.mInt;  return;
			case TypeCode_u8:  (cast(uint8_t*) m.data->data.ptr)[idx] = cast(uint8_t)val.mInt;  return;
			case TypeCode_u16: (cast(uint16_t*)m.data->data.ptr)[idx] = cast(uint16_t)val.mInt; return;
			case TypeCode_u32: (cast(uint32_t*)m.data->data.ptr)[idx] = cast(uint32_t)val.mInt; return;
			case TypeCode_u64: (cast(uint64_t*)m.data->data.ptr)[idx] = cast(uint64_t)val.mInt; return;

			case TypeCode_f32:
				(cast(float*) m.data->data.ptr)[idx] = val.type == CrocType_Int ?
					cast(float)val.mInt :
					cast(float)val.mFloat;
				return;

			case TypeCode_f64:
				(cast(double*)m.data->data.ptr)[idx] = val.type == CrocType_Int ?
					cast(double)val.mInt :
					cast(double)val.mFloat;
				return;

			default: assert(false);
		}
	}

	Members _getMembers(CrocThread* t, uword slot = 0)
	{
		Members ret;

		croc_hfield(t, slot, Data);

		if(!croc_isMemblock(t, -1))
			croc_eh_throwStd(t, "ValueError", "Attempting to operate on an uninitialized Vector");

		ret.data = getMemblock(Thread::from(t), -1);
		croc_popTop(t);

		croc_hfield(t, slot, Kind);
		ret.kind = cast(TypeStruct*)croc_getInt(t, -1);
		croc_popTop(t);

		uword len = ret.data->data.length >> ret.kind->sizeShift;

		if(len << ret.kind->sizeShift != ret.data->data.length)
			croc_eh_throwStd(t, "ValueError",
				"Vector's underlying memblock length is not an even multiple of its item size");

		ret.itemLength = len;
		return ret;
	}

	const TypeStruct* _typeCodeToKind(crocstr typeCode)
	{
		if(typeCode.length >= 2 && typeCode.length <= 3)
		{
			if(typeCode[0] == 'i')
			{
				if(typeCode == ATODA("i8"))  return &_typeStructs[TypeCode_i8];
				if(typeCode == ATODA("i16")) return &_typeStructs[TypeCode_i16];
				if(typeCode == ATODA("i32")) return &_typeStructs[TypeCode_i32];
				if(typeCode == ATODA("i64")) return &_typeStructs[TypeCode_i64];
			}
			else if(typeCode[0] == 'u')
			{
				if(typeCode == ATODA("u8"))  return &_typeStructs[TypeCode_u8];
				if(typeCode == ATODA("u16")) return &_typeStructs[TypeCode_u16];
				if(typeCode == ATODA("u32")) return &_typeStructs[TypeCode_u32];
				if(typeCode == ATODA("u64")) return &_typeStructs[TypeCode_u64];
			}
			else if(typeCode[0] == 'f')
			{
				if(typeCode == ATODA("f32")) return &_typeStructs[TypeCode_f32];
				if(typeCode == ATODA("f64")) return &_typeStructs[TypeCode_f64];
			}
		}

		return nullptr;
	}

#define IMOD(a, b) ((a) % (b))
#define FMOD(a, b) (fmod((a), (b)))

#define MAKE_RANGE_IMPL(name, check, mod, T)\
	void name(CrocThread* t, crocstr type)\
	{\
		auto numParams = croc_getStackSize(t) - 1;\
		T v1 = check(t, 2);\
		T v2;\
		T step = 1;\
\
		if(numParams == 2)\
		{\
			v2 = v1;\
			v1 = 0;\
		}\
		else if(numParams == 3)\
			v2 = check(t, 3);\
		else\
		{\
			v2 = check(t, 3);\
			step = abs(check(t, 4));\
\
			if(step == 0)\
				croc_eh_throwStd(t, "RangeError", "Step may not be 0");\
		}\
\
		auto range = abs(v2 - v1);\
		auto size = cast(crocint)(range / step);\
\
		if(mod(range, step) != 0)\
			size++;\
\
		if(cast(uword)size > std::numeric_limits<uword>::max())\
			croc_eh_throwStd(t, "RangeError", "Vector is too big (%" CROC_INTEGER_FORMAT " items)", size);\
\
		croc_pushGlobal(t, "Vector");\
		croc_pushNull(t);\
		croc_pushStringn(t, cast(const char*)type.ptr, type.length);\
		croc_pushInt(t, size);\
		croc_call(t, -4, 1);\
\
		auto m = _getMembers(t, -1);\
		auto val = v1;\
\
		if(v2 < v1)\
		{\
			for(uword i = 0; val > v2; i++, val -= step)\
				_rawIndexAssign(m, i, Value::from(val));\
		}\
		else\
		{\
			for(uword i = 0; val < v2; i++, val += step)\
				_rawIndexAssign(m, i, Value::from(val));\
		}\
	}

	MAKE_RANGE_IMPL(_intRangeImpl, croc_ex_checkIntParam, IMOD, crocint)
	MAKE_RANGE_IMPL(_floatRangeImpl, croc_ex_checkFloatParam, FMOD, crocfloat)

	template<typename T> void _vecAdd(DArray<T> dst, DArray<T> src1, DArray<T> src2) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = src1.ptr[i] + src2.ptr[i]; }
	template<typename T> void _vecSub(DArray<T> dst, DArray<T> src1, DArray<T> src2) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = src1.ptr[i] - src2.ptr[i]; }
	template<typename T> void _vecMul(DArray<T> dst, DArray<T> src1, DArray<T> src2) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = src1.ptr[i] * src2.ptr[i]; }
	template<typename T> void _vecDiv(DArray<T> dst, DArray<T> src1, DArray<T> src2) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = src1.ptr[i] / src2.ptr[i]; }
	template<typename T> void _vecMod(DArray<T> dst, DArray<T> src1, DArray<T> src2) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = src1.ptr[i] % src2.ptr[i]; }
	template<typename T> void _vecModFloat(DArray<T> dst, DArray<T> src1, DArray<T> src2) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = fmod(src1.ptr[i], src2.ptr[i]); }
	template<typename T, typename U> void _vecAddVal(DArray<T> dst, DArray<T> src, U val) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = src.ptr[i] + val; }
	template<typename T, typename U> void _vecSubVal(DArray<T> dst, DArray<T> src, U val) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = src.ptr[i] - val; }
	template<typename T, typename U> void _vecMulVal(DArray<T> dst, DArray<T> src, U val) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = src.ptr[i] * val; }
	template<typename T, typename U> void _vecDivVal(DArray<T> dst, DArray<T> src, U val) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = src.ptr[i] / val; }
	template<typename T, typename U> void _vecModVal(DArray<T> dst, DArray<T> src, U val) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = src.ptr[i] % val; }
	template<typename T, typename U> void _vecModFloatVal(DArray<T> dst, DArray<T> src, U val) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = fmod(src.ptr[i], val); }
	template<typename T, typename U> void _revVecSubVal(DArray<T> dst, U val, DArray<T> src) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = val - src.ptr[i]; }
	template<typename T, typename U> void _revVecDivVal(DArray<T> dst, U val, DArray<T> src) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = val / src.ptr[i]; }
	template<typename T, typename U> void _revVecModVal(DArray<T> dst, U val, DArray<T> src) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = val % src.ptr[i]; }
	template<typename T, typename U> void _revVecModFloatVal(DArray<T> dst, U val, DArray<T> src) { for(uword i = 0; i < dst.length; i++) dst.ptr[i] = fmod(val, src.ptr[i]); }

	void _fillImpl(CrocThread* t, Members& m, word filler, uword lo, uword hi)
	{
		croc_pushGlobal(t, "Vector");

		if(croc_isInstanceOf(t, filler, -1))
		{
			auto other = _getMembers(t, filler);

			if(m.kind != other.kind)
				croc_eh_throwStd(t, "ValueError",
					"Attempting to fill a Vector of type '%s' using a Vector of type '%s'",
					m.kind->name, other.kind->name);

			if(other.itemLength != (hi - lo))
				croc_eh_throwStd(t, "ValueError",
					"Length of destination (%" CROC_SIZE_T_FORMAT ") and length of source (%" CROC_SIZE_T_FORMAT ") do not match",
					hi - lo, other.itemLength);

			if(m.data == other.data)
				return; // only way this can be is if we're assigning a Vector's entire contents into itself, which is a no-op.

			auto isize = m.kind->itemSize;
			memcpy(&m.data->data[lo * isize], other.data->data.ptr, other.itemLength * isize);
		}
		else if(croc_isFunction(t, filler))
		{
			auto callFunc = [&](uword i)
			{
				croc_dup(t, filler);
				croc_pushNull(t);
				croc_pushInt(t, i);
				croc_call(t, -3, 1);
			};

			auto t_ = Thread::from(t);

			if(m.kind->code <= TypeCode_u64)
			{
				for(uword i = lo; i < hi; i++)
				{
					callFunc(i);

					if(!croc_isInt(t, -1))
					{
						croc_pushTypeString(t, -1);
						croc_eh_throwStd(t, "TypeError", "filler function expected to return an 'int', not '%s'",
							croc_getString(t, -1));
					}

					_rawIndexAssign(m, i, *getValue(t_, -1));
					croc_popTop(t);
				}
			}
			else
			{
				for(uword i = lo; i < hi; i++)
				{
					callFunc(i);

					if(!croc_isNum(t, -1))
					{
						croc_pushTypeString(t, -1);
						croc_eh_throwStd(t, "TypeError",
							"filler function expected to return an 'int' or 'float', not '%s'", croc_getString(t, -1));
					}

					_rawIndexAssign(m, i, *getValue(t_, -1));
					croc_popTop(t);
				}
			}
		}
		else if(croc_isNum(t, filler))
		{
			switch(m.kind->code)
			{
				case TypeCode_i8:  { auto val = croc_ex_checkIntParam(t, filler); m.data->data.template as<int8_t>  ().slice(lo, hi).fill(cast(int8_t)  val); break; }
				case TypeCode_i16: { auto val = croc_ex_checkIntParam(t, filler); m.data->data.template as<int16_t> ().slice(lo, hi).fill(cast(int16_t) val); break; }
				case TypeCode_i32: { auto val = croc_ex_checkIntParam(t, filler); m.data->data.template as<int32_t> ().slice(lo, hi).fill(cast(int32_t) val); break; }
				case TypeCode_i64: { auto val = croc_ex_checkIntParam(t, filler); m.data->data.template as<int64_t> ().slice(lo, hi).fill(cast(int64_t) val); break; }
				case TypeCode_u8:  { auto val = croc_ex_checkIntParam(t, filler); m.data->data.template as<uint8_t> ().slice(lo, hi).fill(cast(uint8_t) val); break; }
				case TypeCode_u16: { auto val = croc_ex_checkIntParam(t, filler); m.data->data.template as<uint16_t>().slice(lo, hi).fill(cast(uint16_t)val); break; }
				case TypeCode_u32: { auto val = croc_ex_checkIntParam(t, filler); m.data->data.template as<uint32_t>().slice(lo, hi).fill(cast(uint32_t)val); break; }
				case TypeCode_u64: { auto val = croc_ex_checkIntParam(t, filler); m.data->data.template as<uint64_t>().slice(lo, hi).fill(cast(uint64_t)val); break; }
				case TypeCode_f32: { auto val = croc_ex_checkNumParam(t, filler); m.data->data.template as<float>   ().slice(lo, hi).fill(cast(float)   val); break; }
				case TypeCode_f64: { auto val = croc_ex_checkNumParam(t, filler); m.data->data.template as<double>  ().slice(lo, hi).fill(cast(double)  val); break; }
				default: assert(false);
			}
		}
		else if(croc_isArray(t, filler))
		{
			if(cast(uword)croc_len(t, filler) != (hi - lo))
				croc_eh_throwStd(t, "ValueError",
					"Length of destination (%" CROC_SIZE_T_FORMAT ") and length of array (%" CROC_INTEGER_FORMAT ") do not match",
					hi - lo, croc_len(t, filler));

			auto t_ = Thread::from(t);

			if(m.kind->code <= TypeCode_u64)
			{
				for(uword i = lo, ai = 0; i < hi; i++, ai++)
				{
					croc_idxi(t, filler, ai);

					if(!croc_isInt(t, -1))
					{
						croc_pushTypeString(t, -1);
						croc_eh_throwStd(t, "ValueError",
							"array element %" CROC_SIZE_T_FORMAT " expected to be 'int', not '%s'",
							ai, croc_getString(t, -1));
					}

					_rawIndexAssign(m, i, *getValue(t_, -1));
					croc_popTop(t);
				}
			}
			else
			{
				for(uword i = lo, ai = 0; i < hi; i++, ai++)
				{
					croc_idxi(t, filler, ai);

					if(!croc_isNum(t, -1))
					{
						croc_pushTypeString(t, -1);
						croc_eh_throwStd(t, "ValueError",
							"array element %" CROC_SIZE_T_FORMAT " expected to be 'int' or 'float', not '%s'",
							ai, croc_getString(t, -1));
					}

					_rawIndexAssign(m, i, *getValue(t_, -1));
					croc_popTop(t);
				}
			}
		}
		else
			croc_ex_paramTypeError(t, filler, "int|float|function|array|Vector");

		croc_popTop(t);
	}

	template<typename T>
	T _minImpl(DArray<T> arr)
	{
		auto m = arr[0];

		for(auto val: arr.slice(1, arr.length))
		{
			if(val < m)
				m = val;
		}

		return m;
	}

	template<typename T>
	T _maxImpl(DArray<T> arr)
	{
		auto m = arr[0];

		for(auto val: arr.slice(1, arr.length))
		{
			if(val > m)
				m = val;
		}

		return m;
	}

DBeginList(_methods)
	Docstr(DFunc("constructor") DParam("type", "string") DParam("size", "int") DParamD("filler", "any", "null")
	R"(Constructor.

	\param[type] is a string containing one of the type codes listed above.
	\param[size] is the length of the new Vector, measured in the number of elements.

	\param[filler] is optional. If it is not given, the Vector is filled with 0s. If it is given, the instance will have
	the \link{fill} method called on it with \tt{filler} as the argument. As such, if the \tt{filler} is invalid, any
	exceptions that \link{fill} can throw, the constructor can throw as well.

	\throws[ValueError] if \tt{type} is not a valid type code.
	\throws[RangeError] if \tt{size} is invalid (negative or too large).)"),

	"constructor", 3, [](CrocThread* t) -> word_t
	{
		croc_hfield(t, 0, Data);

		if(!croc_isNull(t, -1))
			croc_eh_throwStd(t, "StateError", "Attempting to call constructor on an already-initialized Vector");

		croc_popTop(t);

		croc_ex_checkStringParam(t, 1);

		auto kind = _typeCodeToKind(getCrocstr(t, 1));

		if(kind == nullptr)
			croc_eh_throwStd(t, "ValueError", "Invalid type code '%s'", croc_getString(t, 1));

		croc_pushInt(t, cast(crocint)kind);
		croc_hfielda(t, 0, Kind);

		auto size = croc_ex_checkIntParam(t, 2);

		if(size < 0 || cast(uword)size > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid size (%" CROC_INTEGER_FORMAT ")", size);

		croc_memblock_new(t, cast(uword)size * kind->itemSize);
		croc_hfielda(t, 0, Data);

		if(croc_isValidIndex(t, 3))
		{
			croc_dup(t, 0);
			croc_pushNull(t);
			croc_dup(t, 3);
			croc_methodCall(t, -3, "fill", 0);
		}

		return 0;
	}

DListSep()
	Docstr(DFunc("fromArray") DParam("type", "string") DParam("arr", "array")
	R"(A convenience function to convert an \tt{array} into a Vector.

	Calling \tt{Vector.fromArray(type, arr)} is basically the same as calling \tt{Vector(type, #arr, arr)}; that is, the
	length of the Vector will be the length of the array, and the array will be passed as the \tt{filler} to the
	constructor.

	\param[type] is a string containing one of the type codes.
	\param[arr] is an array (single-dimensional, containing only numbers that can be converted to the Vector's element
	type) that will be used to fill the Vector with data.

	\returns the new Vector.)"),

	"fromArray", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkStringParam(t, 1);
		croc_ex_checkParam(t, 2, CrocType_Array);
		croc_pushGlobal(t, "Vector");
		croc_pushNull(t);
		croc_dup(t, 1);
		croc_pushInt(t, croc_len(t, 2));
		croc_dup(t, 2);
		return croc_call(t, -5, 1);
	}

DListSep()
	Docstr(DFunc("range") DParam("type", "string") DParam("val1", "int|float") DParamD("val2", "int|float", "null")
		DParamD("step", "int|float", "1")
	R"(Creates a Vector whose values are a range of ascending or numbers, much like the \link{array.range} function.

	If the \tt{type} parameter is one of the integral types, the next three parameters must be ints; otherwise, they can
	be ints or floats.

	If called with just \tt{val1}, it specifies a noninclusive end index, with a start index of 0 and a step of 1. So
	\tt{Vector.range("i32", 5)} gives \tt{"Vector(i32)[0, 1, 2, 3, 4]"}, and \tt{Vector.range("i32", -5)} gives
	\tt{"Vector(i32)[0, -1, -2, -3, -4]"}.

	If called with \tt{val1} and \tt{val2}, \tt{val1} will be the inclusive start index, and \tt{val2} will be the
	noninclusive end index. The step will be 1.

	The \tt{step}, if specified, specifies how much each successive element should differ by. The sign is ignored, but
	the step may not be 0.

	\param[type] is a string containing one of the type codes.
	\param[val1] is either the end index or the start index as explained above.
	\param[val2] is the optional end index; if specified, makes \tt{val1} the start index.
	\param[step] is the optional step size.

	\returns the new Vector.
	\throws[RangeError] if \tt{step} is 0.
	\throws[RangeError] if the resulting Vector would have too many elements to be represented.)"),

	"range", 4, [](CrocThread* t) -> word_t
	{
		crocstr type;
		type.ptr = cast(const uchar*)croc_ex_checkStringParamn(t, 1, &type.length);

		if(type.length >= 2 && type.length <= 3)
		{
			if(
				(type[0] == 'i' &&
					(type == ATODA("i8") ||
					type == ATODA("i16") ||
					type == ATODA("i32") ||
					type == ATODA("i64"))
				) ||
				(type[0] == 'u' &&
					(type == ATODA("u8") ||
					type == ATODA("u16") ||
					type == ATODA("u32") ||
					type == ATODA("u64"))
				))
			{
				_intRangeImpl(t, type);
				return 1;
			}
			else if(type[0] == 'f' && (type == ATODA("f32") || type == ATODA("f64")))
			{
				_floatRangeImpl(t, type);
				return 1;
			}
		}

		return croc_eh_throwStd(t, "ValueError", "Invalid type code '%.*s'", cast(int)type.length, type.ptr);
	}

DListSep()
	Docstr(DFunc("type") DParamD("type", "string", "null")
	R"(Gets or sets the type of this Vector.

	If called with no parameters, gets the type and returns it as a string.

	If called with a parameter, it must be one of the type codes given above. The Vector's type will be set to the
	new type, but only if the Vector's byte length is an multiple of the new type's item size. That is, if you had
	a \tt{"u8" Vector} of length 7, and tried to change its type to \tt{"u16"}, it would fail because 7 is not an even
	multiple of the size of a \tt{"u16"} element, 2 bytes.

	When the type is changed, the data is not affected at all. The existing bit patterns will simply be interpreted
	according to the new type.

	\param[type] is the new type if changing this Vector's type, or \tt{null} if not.
	\returns the current type of the Vector if \tt{type} is \tt{null}, or nothing otherwise.
	\throws[ValueError] if \tt{type} is not a valid type code.
	\throws[ValueError] if the byte size is not an even multiple of the new type's item size.)"),

	"type", 1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		auto numParams = croc_getStackSize(t) - 1;

		if(numParams == 0)
		{
			croc_dup(t, 0);
			croc_pushString(t, m.kind->name);
			return 1;
		}
		else
		{
			croc_ex_checkStringParam(t, 1);
			auto ts = _typeCodeToKind(getCrocstr(t, 1));

			if(ts == nullptr)
				croc_eh_throwStd(t, "ValueError", "Invalid type code '%s'", croc_getString(t, 1));

			if(m.kind != ts)
			{
				auto byteSize = m.itemLength * m.kind->itemSize;

				if(byteSize % ts->itemSize != 0)
					croc_eh_throwStd(t, "ValueError",
						"Vector's byte size is not an even multiple of new type's item size");

				croc_pushInt(t, cast(crocint)ts);
				croc_hfielda(t, 0, Kind);
			}

			return 0;
		}
	}

DListSep()
	Docstr(DFunc("itemSize")
	R"(\returns the size of one item of this Vector in bytes.)"),

	"itemSize", 0, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		croc_pushInt(t, m.kind->itemSize);
		return 1;
	}

DListSep()
	Docstr(DFunc("toArray") DParamD("lo", "int", "0") DParamD("hi", "int", "#this")
	R"(Converts this Vector or a slice of it into an \tt{array}.

	Simply creates a new array and fills it with the values held in the Vector, or just a slice of it if the parameters
	are given.

	\param[lo] the low slice index.
	\param[hi] the high slice index.
	\returns an array holding the values from the given slice.)"),

	"toArray", 2, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		uword_t lo, hi;
		lo = croc_ex_checkSliceParams(t, 1, m.itemLength, "slice", &hi);
		auto ret = croc_array_new(t, hi - lo);
		auto t_ = Thread::from(t);

		for(uword i = lo, j = 0; i < hi; i++, j++)
		{
			push(t_, _rawIndex(m, i));
			croc_idxai(t, ret, j);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("toString")
	R"(\returns a string representation of this Vector.

	The format will be \tt{"Vector(<type>)[<elements>]"}; that is, \tt{Vector.fromArray("i32", [1, 2, 3]).toString()}
	will yield the string \tt{"Vector(i32)[1, 2, 3]"}.)"),

	"toString", 0, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);

		CrocStrBuffer b;
		croc_ex_buffer_init(t, &b);
		croc_pushFormat(t, "Vector(%s)[", m.kind->name);
		croc_ex_buffer_addTop(&b);

		if(m.kind->code == TypeCode_u64)
		{
			for(uword i = 0; i < m.itemLength; i++)
			{
				if(i > 0)
					croc_ex_buffer_addStringn(&b, ", ", 2);

				auto v = _rawIndex(m, i);
				croc_pushFormat(t, "%" CROC_UINTEGER_FORMAT, cast(uint64_t)v.mInt);
				croc_ex_buffer_addTop(&b);
			}
		}
		else
		{
			auto t_ = Thread::from(t);

			for(uword i = 0; i < m.itemLength; i++)
			{
				if(i > 0)
					croc_ex_buffer_addStringn(&b, ", ", 2);

				push(t_, _rawIndex(m, i));
				croc_pushToStringRaw(t, -1);
				croc_insertAndPop(t, -2);
				croc_ex_buffer_addTop(&b);
			}
		}

		croc_ex_buffer_addChar(&b, ']');
		croc_ex_buffer_finish(&b);
		return 1;
	}

DListSep()
	Docstr(DFunc("getMemblock")
	R"(\returns the underlying \tt{memblock} in which this Vector stores its data.

	Note that which memblock a Vector uses to store its data cannot be changed, but you can change the data and size of
	the memblock returned from this method. As explained in the class's documentation, though, setting the underlying
	memblock's length to something that is not an even multiple of the Vector's item size will result in an exception
	being thrown the next time a method is called on the Vector.)"),

	"getMemblock", 0, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		push(Thread::from(t), Value::from(m.data));
		return 1;
	}

DListSep()
	Docstr(DFunc("dup")
	R"(Duplicates this Vector.

	Creates a new Vector with the same type and a copy of this Vector's data.

	\returns the new Vector.)"),

	"dup", 0, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);

		croc_pushGlobal(t, "Vector");
		croc_pushNull(t);
		croc_pushString(t, m.kind->name);
		croc_pushInt(t, m.itemLength);
		croc_call(t, -4, 1);

		auto n = _getMembers(t, -1);
		n.data->data.slicea(m.data->data);
		return 1;
	}

DListSep()
	Docstr(DFunc("reverse")
	R"(Reverses the elements of this Vector.

	This method operates in-place.)"),

	"reverse", 0, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);

		switch(m.kind->itemSize)
		{
			case 1: arrReverse(DArray<uint8_t> ::n(cast(uint8_t*) m.data->data.ptr, m.itemLength)); break;
			case 2: arrReverse(DArray<uint16_t>::n(cast(uint16_t*)m.data->data.ptr, m.itemLength)); break;
			case 4: arrReverse(DArray<uint32_t>::n(cast(uint32_t*)m.data->data.ptr, m.itemLength)); break;
			case 8: arrReverse(DArray<uint64_t>::n(cast(uint64_t*)m.data->data.ptr, m.itemLength)); break;
			default: assert(false);
		}

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("sort")
	R"(Sorts the elements of this Vector in ascending order.

	This method operates in-place.)"),

	"sort", 0, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);

		switch(m.kind->code)
		{
			case TypeCode_i8:  arrSort(DArray<int8_t>  ::n(cast(int8_t*)  m.data->data.ptr, m.itemLength)); break;
			case TypeCode_i16: arrSort(DArray<int16_t> ::n(cast(int16_t*) m.data->data.ptr, m.itemLength)); break;
			case TypeCode_i32: arrSort(DArray<int32_t> ::n(cast(int32_t*) m.data->data.ptr, m.itemLength)); break;
			case TypeCode_i64: arrSort(DArray<int64_t> ::n(cast(int64_t*) m.data->data.ptr, m.itemLength)); break;
			case TypeCode_u8:  arrSort(DArray<uint8_t> ::n(cast(uint8_t*) m.data->data.ptr, m.itemLength)); break;
			case TypeCode_u16: arrSort(DArray<uint16_t>::n(cast(uint16_t*)m.data->data.ptr, m.itemLength)); break;
			case TypeCode_u32: arrSort(DArray<uint32_t>::n(cast(uint32_t*)m.data->data.ptr, m.itemLength)); break;
			case TypeCode_u64: arrSort(DArray<uint64_t>::n(cast(uint64_t*)m.data->data.ptr, m.itemLength)); break;
			case TypeCode_f32: arrSort(DArray<float>   ::n(cast(float*)   m.data->data.ptr, m.itemLength)); break;
			case TypeCode_f64: arrSort(DArray<double>  ::n(cast(double*)  m.data->data.ptr, m.itemLength)); break;
			default: assert(false);
		}

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("apply") DParam("func", "function")
	R"(Like \link{array.apply}, calls a function on each element of this Vector and assigns the results back into it.

	\param[func] should be a function which takes one value (an int for integral Vectors or a float for floating-point
	ones), and should return one value of the same type that was passed in (though it's okay to return ints for
	floating-point Vectors.

	\throws[TypeError] if \tt{func} returns a value of an invalid type.)"),

	"apply", 1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		croc_ex_checkParam(t, 1, CrocType_Function);

#define DO_LOOP(test, typeMsg)\
		{\
			auto t_ = Thread::from(t);\
\
			for(uword i = 0; i < m.itemLength; i++)\
			{\
				croc_dup(t, 1);\
				croc_pushNull(t);\
				push(t_, _rawIndex(m, i));\
				croc_call(t, -3, 1);\
\
				if(!test(t, -1))\
				{\
					croc_pushTypeString(t, -1);\
					croc_eh_throwStd(t, "TypeError", "application function expected to return '" typeMsg "', not '%s'",\
						croc_getString(t, -1));\
				}\
\
				_rawIndexAssign(m, i, *getValue(t_, -1));\
				croc_popTop(t);\
			}\
		}

		switch(m.kind->code)
		{
			case TypeCode_i8: case TypeCode_i16: case TypeCode_i32: case TypeCode_i64:
			case TypeCode_u8: case TypeCode_u16: case TypeCode_u32: case TypeCode_u64:
				DO_LOOP(croc_isInt, "'int'")
				break;

			case TypeCode_f32: case TypeCode_f64:
				DO_LOOP(croc_isNum, "'int|float'")
				break;
#undef DO_LOOP

			default: assert(false);
		}

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("map") DParam("func", "function")
	R"(Same as \link{apply}, except puts the results into a new Vector instead of operating in-place.

	This is functionally equivalent to writing \tt{this.dup().apply(func)}.

	\param[func] is the same as the \tt{func} parameter for \link{apply}.
	\returns the new Vector.
	\throws[TypeError] if \tt{func} returns a value of an invalid type.)"),

	"map", 1, [](CrocThread* t) -> word_t
	{
		_getMembers(t, 0);
		croc_ex_checkParam(t, 1, CrocType_Function);
		croc_dup(t, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "dup", 1);
		croc_pushNull(t);
		croc_dup(t, 1);
		return croc_methodCall(t, -3, "apply", 1);
	}

DListSep()
	Docstr(DFunc("min")
	R"(Finds the smallest value in this Vector.

	\returns the smallest value.
	\throws[ValueError] if \tt{#this == 0}.)"),

	"min", 0, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);

		if(m.itemLength == 0)
			croc_eh_throwStd(t, "ValueError", "Vector is empty");

		switch(m.kind->code)
		{
			case TypeCode_i8:  croc_pushInt(t, _minImpl(m.data->data.template as<int8_t>()));                break;
			case TypeCode_i16: croc_pushInt(t, _minImpl(m.data->data.template as<int16_t>()));               break;
			case TypeCode_i32: croc_pushInt(t, _minImpl(m.data->data.template as<int32_t>()));               break;
			case TypeCode_i64: croc_pushInt(t, _minImpl(m.data->data.template as<int64_t>()));               break;
			case TypeCode_u8:  croc_pushInt(t, _minImpl(m.data->data.template as<uint8_t>()));               break;
			case TypeCode_u16: croc_pushInt(t, _minImpl(m.data->data.template as<uint16_t>()));              break;
			case TypeCode_u32: croc_pushInt(t, _minImpl(m.data->data.template as<uint32_t>()));              break;
			case TypeCode_u64: croc_pushInt(t, cast(crocint)_minImpl(m.data->data.template as<uint64_t>())); break;
			case TypeCode_f32: croc_pushFloat(t, _minImpl(m.data->data.template as<float>()));               break;
			case TypeCode_f64: croc_pushFloat(t, _minImpl(m.data->data.template as<double>()));              break;
			default: assert(false);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("max")
	R"(Finds the largest value in this Vector.

	\returns the largest value.
	\throws[ValueError] if \tt{#this == 0}.)"),

	"max", 0, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);

		if(m.itemLength == 0)
			croc_eh_throwStd(t, "ValueError", "Vector is empty");

		switch(m.kind->code)
		{
			case TypeCode_i8:  croc_pushInt(t, _maxImpl(m.data->data.template as<int8_t>()));                break;
			case TypeCode_i16: croc_pushInt(t, _maxImpl(m.data->data.template as<int16_t>()));               break;
			case TypeCode_i32: croc_pushInt(t, _maxImpl(m.data->data.template as<int32_t>()));               break;
			case TypeCode_i64: croc_pushInt(t, _maxImpl(m.data->data.template as<int64_t>()));               break;
			case TypeCode_u8:  croc_pushInt(t, _maxImpl(m.data->data.template as<uint8_t>()));               break;
			case TypeCode_u16: croc_pushInt(t, _maxImpl(m.data->data.template as<uint16_t>()));              break;
			case TypeCode_u32: croc_pushInt(t, _maxImpl(m.data->data.template as<uint32_t>()));              break;
			case TypeCode_u64: croc_pushInt(t, cast(crocint)_maxImpl(m.data->data.template as<uint64_t>())); break;
			case TypeCode_f32: croc_pushFloat(t, _maxImpl(m.data->data.template as<float>()));               break;
			case TypeCode_f64: croc_pushFloat(t, _maxImpl(m.data->data.template as<double>()));              break;
			default: assert(false);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("insert") DParam("idx", "int") DParam("val", "int|float|Vector")
	R"(Inserts a single number or another Vector's contents at the given position.

	\param[idx] is the position where \tt{val} should be inserted. All the elements (if any) after \tt{idx} are
	shifted down to make room for the inserted data. \tt{idx} can be \tt{#this}, in which case \tt{val} will be appended
	to the end of \tt{this}. \tt{idx} can be negative to mean an index from the end of this Vector.
	\param[val] is the value to insert. If \tt{val} is a Vector, it must be the same type as \tt{this}. It is legal
	for \tt{val} to be \tt{this}. If \tt{val} isn't a Vector, it must be a valid type for this Vector.

	\throws[ValueError] if this Vector's memblock does not own its data.
	\throws[BoundsError] if \tt{idx} is invalid.
	\throws[ValueError] if \tt{val} is a Vector but its type differs from \tt{this}'s type.
	\throws[RangeError] if inserting would cause this Vector to grow too large.)"),

	"insert", 2, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		auto len = m.itemLength;
		auto idx = croc_ex_checkIntParam(t, 1);
		croc_ex_checkAnyParam(t, 2);

		if(!m.data->ownData)
			croc_eh_throwStd(t, "ValueError", "Attempting to insert into a Vector which does not own its data");

		if(idx < 0)
			idx += len;

		// Yes, > and not >=, because you can insert at "one past" the end of the Vector.
		if(idx < 0 || cast(uword)idx > len)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid index: %" CROC_INTEGER_FORMAT " (length: %" CROC_SIZE_T_FORMAT ")", idx, len);

		auto doResize = [&](uint64_t otherLen)
		{
			uint64_t totalLen = len + otherLen;

			if(totalLen > std::numeric_limits<uword>::max())
				croc_eh_throwStd(t, "RangeError", "Invalid size (%" CROC_UINTEGER_FORMAT ")", totalLen);

			auto oldLen = len;
			auto isize = m.kind->itemSize;

			push(Thread::from(t), Value::from(m.data));
			croc_lenai(t, -1, cast(uword)totalLen * isize);
			croc_popTop(t);

			m.itemLength = cast(uword)totalLen;

			if(cast(uword)idx < oldLen)
			{
				auto end = idx + otherLen;
				auto numLeft = oldLen - idx;
				memmove(&m.data->data[cast(uword)end * isize], &m.data->data[cast(uword)idx * isize], cast(uword)(numLeft * isize));
			}

			return m.data->data.slice(cast(uword)idx * isize, cast(uword)(idx + otherLen) * isize);
		};

		croc_pushGlobal(t, "Vector");

		if(croc_isInstanceOf(t, 2, -1))
		{
			if(croc_is(t, 0, 2))
			{
				// special case for inserting a Vector into itself

				if(m.itemLength != 0)
				{
					auto slice = doResize(len);
					auto data = m.data->data;
					auto isize = m.kind->itemSize;
					slice.slicea(0, cast(uword)idx * isize, data.slice(0, cast(uword)idx * isize));
					slice.slicea(cast(uword)idx * isize, slice.length,
						data.slice(cast(uword)(idx + len) * isize, data.length));
				}
			}
			else
			{
				auto other = _getMembers(t, 2);

				if(m.kind != other.kind)
					croc_eh_throwStd(t, "ValueError",
						"Attempting to insert a Vector of type '%s' into a Vector of type '%s'",
						other.kind->name, m.kind->name);

				if(other.itemLength != 0)
				{
					auto slice = doResize(other.itemLength);
					memcpy(slice.ptr, other.data->data.ptr, other.itemLength * m.kind->itemSize);
				}
			}
		}
		else
		{
			if(m.kind->code <= TypeCode_u64)
				croc_ex_checkIntParam(t, 2);
			else
				croc_ex_checkNumParam(t, 2);

			doResize(1);
			_rawIndexAssign(m, cast(uword)idx, *getValue(Thread::from(t), 2));
		}

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("remove") DParam("lo", "int") DParamD("hi", "int", "lo + 1")
	R"(Removes one or more items from this Vector, shifting the data after the removed data up.

	It is legal for the size of the slice to be removed to be 0, in which case nothing happens.

	\param[lo] is the lower slice index of the items to be removed.
	\param[hi] is the upper slice index of the items to be removed. It defaults to one after \tt{lo}, so that called
	with just one parameter, this method will remove one item.

	\throws[ValueError] if this Vector's memblock does not own its data.
	\throws[ValueError] if this Vector is empty.
	\throws[BoundsError] if \tt{lo} and \tt{hi} are invalid.)"),

	"remove", 2, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);

		if(!m.data->ownData)
			croc_eh_throwStd(t, "ValueError", "Attempting to remove from a Vector which does not own its data");

		if(m.itemLength == 0)
			croc_eh_throwStd(t, "ValueError", "Vector is empty");

		auto lo = croc_ex_checkIntParam(t, 1);
		auto hi = croc_ex_optIntParam(t, 2, lo + 1);
		if(lo < 0) lo += m.itemLength;
		if(hi < 0) hi += m.itemLength;
		croc_ex_checkValidSlice(t, lo, hi, m.itemLength, "element");

		if(lo != hi)
		{
			auto isize = m.kind->itemSize;

			if(cast(uword)hi < m.itemLength)
				memmove(&m.data->data[cast(uword)lo * isize], &m.data->data[cast(uword)hi * isize],
					cast(uword)((m.itemLength - hi) * isize));

			auto diff = hi - lo;
			push(Thread::from(t), Value::from(m.data));
			croc_lenai(t, -1, cast(uword)((m.itemLength - diff) * isize));
			croc_popTop(t);
		}

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("pop") DParamD("idx", "int", "-1")
	R"(Removes one item from anywhere in this Vector (the last item by default) and returns its value, like
	\link{array.pop}.

	\param[idx] is the index of the item to be removed, which defaults to the last item in this Vector.

	\returns the value of the item that was removed.

	\throws[ValueError] if this Vector's memblock does not own its data.
	\throws[ValueError] if this Vector is empty.
	\throws[BoundsError] if \tt{idx} is invalid.)"),

	"pop", 1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);

		if(!m.data->ownData)
			croc_eh_throwStd(t, "ValueError", "Attempting to pop from a Vector which does not own its data");

		if(m.itemLength == 0)
			croc_eh_throwStd(t, "ValueError", "Vector is empty");

		auto index = croc_ex_optIndexParam(t, 1, m.itemLength, "element", m.itemLength - 1);
		push(Thread::from(t), _rawIndex(m, index));

		auto isize = m.kind->itemSize;

		if(index < m.itemLength - 1)
			memmove(&m.data->data[index * isize], &m.data->data[(index + 1) * isize],
				((m.itemLength - index - 1) * isize));

		push(Thread::from(t), Value::from(m.data));
		croc_lenai(t, -1, (m.itemLength - 1) * isize);
		croc_popTop(t);

		return 1;
	}

DListSep()
	Docstr(DFunc("sum")
	R"(Sums all the elements in this Vector, returning 0 or 0.0 if empty.

	\returns the sum.)"),

	"sum", 0, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);

		if(m.kind->code <= TypeCode_u64)
		{
			crocint res = 0;

			switch(m.kind->code)
			{
				case TypeCode_i8:  for(auto val: m.data->data.template as<int8_t>())   res += val; break;
				case TypeCode_i16: for(auto val: m.data->data.template as<int16_t>())  res += val; break;
				case TypeCode_i32: for(auto val: m.data->data.template as<int32_t>())  res += val; break;
				case TypeCode_i64: for(auto val: m.data->data.template as<int64_t>())  res += val; break;
				case TypeCode_u8:  for(auto val: m.data->data.template as<uint8_t>())  res += val; break;
				case TypeCode_u16: for(auto val: m.data->data.template as<uint16_t>()) res += val; break;
				case TypeCode_u32: for(auto val: m.data->data.template as<uint32_t>()) res += val; break;
				case TypeCode_u64: for(auto val: m.data->data.template as<uint64_t>()) res += val; break;
				default: assert(false);
			}

			croc_pushInt(t, res);
		}
		else
		{
			crocfloat res = 0.0;

			switch(m.kind->code)
			{
				case TypeCode_f32: for(auto val: m.data->data.template as<float>())  res += val; break;
				case TypeCode_f64: for(auto val: m.data->data.template as<double>()) res += val; break;
				default: assert(false);
			}

			croc_pushFloat(t, res);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("product")
	R"(Multiplies all the elements in this Vector together, returning 1 or 1.0 if empty.

	\returns the product.)"),

	"product", 0, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);

		if(m.kind->code <= TypeCode_u64)
		{
			crocint res = 1;

			switch(m.kind->code)
			{
				case TypeCode_i8:  for(auto val: m.data->data.template as<int8_t>())   res *= val; break;
				case TypeCode_i16: for(auto val: m.data->data.template as<int16_t>())  res *= val; break;
				case TypeCode_i32: for(auto val: m.data->data.template as<int32_t>())  res *= val; break;
				case TypeCode_i64: for(auto val: m.data->data.template as<int64_t>())  res *= val; break;
				case TypeCode_u8:  for(auto val: m.data->data.template as<uint8_t>())  res *= val; break;
				case TypeCode_u16: for(auto val: m.data->data.template as<uint16_t>()) res *= val; break;
				case TypeCode_u32: for(auto val: m.data->data.template as<uint32_t>()) res *= val; break;
				case TypeCode_u64: for(auto val: m.data->data.template as<uint64_t>()) res *= val; break;
				default: assert(false);
			}

			croc_pushInt(t, res);
		}
		else
		{
			crocfloat res = 1.0;

			switch(m.kind->code)
			{
				case TypeCode_f32: for(auto val: m.data->data.template as<float>())  res *= val; break;
				case TypeCode_f64: for(auto val: m.data->data.template as<double>()) res *= val; break;
				default: assert(false);
			}

			croc_pushFloat(t, res);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("copyRange") DParamD("lo1", "int", "0") DParamD("hi1", "int", "#this") DParam("other", "Vector")
		DParamD("lo2", "int", "0") DParamD("hi2", "int", "lo2 + (hi - lo)")
	R"(Copies a slice of another Vector into a slice of this one without creating an unnecessary temporary.

	If you try to use slice-assignment to copy a slice of one vector into another (such as \tt{a[x .. y] = b[z .. w]}),
	an unnecessary temporary Vector will be created, as well as performing two memory copies. For better performance,
	you can use this method to copy the data directly without creating an intermediate object and only performing one
	memory copy.

	The lengths of the slices must be identical.

	\param[lo1] is the lower index of the slice into this Vector.
	\param[hi1] is the upper index of the slice into this Vector.
	\param[other] is the Vector from which data will be copied.
	\param[lo2] is the lower index of the slice into \tt{other}.
	\param[hi2] is the upper index of the slice into \tt{other}. Note that its default value means \tt{lo2 + the size of
	the slice into this}.

	\throws[BoundsError] if either pair of slice indices is invalid for its respective Vector.
	\throws[ValueError] if \tt{other}'s type is not the same as this Vector's.
	\throws[ValueError] if the sizes of the slices differ.)"),

	"copyRange", 5, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		auto other = _getMembers(t, 3);

		if(m.kind != other.kind)
			croc_eh_throwStd(t, "ValueError", "Attempting to copy a Vector of type '%s' into a Vector of type '%s'",
				other.kind->name, m.kind->name);

		uword_t lo, hi, lo2, hi2;
		lo = croc_ex_checkSliceParams(t, 1, m.itemLength, "destination", &hi);
		lo2 = croc_ex_checkSliceParams(t, 4, other.itemLength, "source", &hi2);

		if((hi - lo) != (hi2 - lo2))
			croc_eh_throwStd(t, "ValueError",
				"Destination length (%" CROC_SIZE_T_FORMAT ") and source length(%" CROC_SIZE_T_FORMAT ") do not match",
				hi - lo, hi2 - lo2);

		auto isize = m.kind->itemSize;

		if(croc_is(t, 0, 3))
			memmove(&m.data->data[lo * isize], &other.data->data[lo2 * isize], (hi - lo) * isize);
		else
			memcpy(&m.data->data[lo * isize], &other.data->data[lo2 * isize], (hi - lo) * isize);

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("fill") DParam("val", "int|float|function|array|Vector")
	R"(A flexible way to fill a Vector with data.

	This method never changes the Vector's size; it always works in-place, and all data in this Vector is replaced. The
	behavior of this method depends on the type of its \tt{val} parameter.

	\param[val] is the value used to fill this Vector.

	If \tt{this} is an integral Vector, and \tt{val} is an int, all items in this Vector will be set to \tt{val}.

	If \tt{this} is a floating-point Vector, \tt{val} can be an int or float, and all items in this Vector will be set
	to the float representation of \tt{val}.

	If \tt{val} is a function, it should take an integer that is the index of the element, and should return one value
	the appropriate type which will be the value placed in that index. This function is called once for each element
	this Vector.

	If \tt{val} is an array, it should be the same length as this Vector, be single-dimensional, and all elements must
	be valid types for this Vector. The values will be assigned element-for-element into this Vector.

	Lastly, if \tt{val} is a Vector, it must be the same length and type, and the data will be copied from \tt{val} into
	this Vector.)"),

	"fill", 1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		croc_ex_checkAnyParam(t, 1);
		_fillImpl(t, m, 1, 0, m.itemLength);
		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("fillRange") DParamD("lo", "int", "0") DParamD("hi", "int", "#this")
		DParam("val", "int|float|function|array|Vector")
	R"x(Same as \link{fill}, but operates on only a slice of this Vector instead of on the entire length.

	\b{Also aliased to opSliceAssign.} This means that any slice-assignment of the form \tt{"v[x .. y] = b"} can be
	written equivalently as \tt{"v.fillRange(x, y, b)"}, and vice versa.

	\param[lo] is the lower slice index.
	\param[hi] is the upper slice index.
	\param[val] is the same as for \link{fill}.)x"),

	"fillRange", 3, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		uword_t lo, hi;
		lo = croc_ex_checkSliceParams(t, 1, m.itemLength, "range", &hi);
		_fillImpl(t, m, 3, cast(uword)lo, cast(uword)hi);
		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("opEquals") DParam("other", "Vector")
	R"(Checks if two Vectors have the same contents. Both Vectors must be the same type.

	\param[other] is the Vector to compare \tt{this} to.
	\returns \tt{true} if \tt{this} and \tt{other} are the same length and contain the same data, or \tt{false}
	otherwise.

	\throws[ValueError] if \tt{other}'s type differs from \tt{this}'s.)"),

	"opEquals", 1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		auto other = _getMembers(t, 1);

		if(croc_is(t, 0, 1))
			croc_pushBool(t, true);
		else
		{
			if(m.kind != other.kind)
				croc_eh_throwStd(t, "ValueError", "Attempting to compare Vectors of types '%s' and '%s'",
					m.kind->name, other.kind->name);

			if(m.itemLength != other.itemLength)
				croc_pushBool(t, false);
			else
				croc_pushBool(t, m.data->data == other.data->data);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("opCmp") DParam("other", "Vector")
	R"(Compares two Vectors lexicographically. Both Vectors must be the same type.

	\param[other] is the Vector to compare \tt{this} to.
	\returns a negative integer if \tt{this} compares less than \tt{other}, positive if \tt{this} compares greater than
	\tt{other}, and 0 if \tt{this} and \tt{other} have the same length and contents.

	\throws[ValueError] if \tt{other}'s type differs from \tt{this}'s.)"),

	"opCmp", 1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		auto other = _getMembers(t, 1);

		if(croc_is(t, 0, 1))
			croc_pushInt(t, 0);
		else
		{
			if(m.kind != other.kind)
				croc_eh_throwStd(t, "ValueError", "Attempting to compare Vectors of types '%s' and '%s'",
					m.kind->name, other.kind->name);

			int cmp;

			switch(m.kind->code)
			{
				// this macro avoids ugly mis-highlighting in ST2
#define MAKE_CMP(Type) cmp = m.data->data.template as<Type>().cmp(other.data->data.template as<Type>());
				case TypeCode_i8:  MAKE_CMP(int8_t);   break;
				case TypeCode_i16: MAKE_CMP(int16_t);  break;
				case TypeCode_i32: MAKE_CMP(int32_t);  break;
				case TypeCode_i64: MAKE_CMP(int64_t);  break;
				case TypeCode_u8:  MAKE_CMP(uint8_t);  break;
				case TypeCode_u16: MAKE_CMP(uint16_t); break;
				case TypeCode_u32: MAKE_CMP(uint32_t); break;
				case TypeCode_u64: MAKE_CMP(uint64_t); break;
				case TypeCode_f32: MAKE_CMP(float);    break;
				case TypeCode_f64: MAKE_CMP(double);   break;
				default: assert(false); cmp = 0; // dummy;
			}

			croc_pushInt(t, cmp);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("opLength")
	R"(Gets the number of items in this Vector.

	\returns the length as an integer.)"),

	"opLength", 0, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		croc_pushInt(t, m.itemLength);
		return 1;
	}

DListSep()
	Docstr(DFunc("opLengthAssign") DParam("len", "int")
	R"(Sets the number of items in this Vector.

	\param[len] is the new length.

	\throws[ValueError] if this Vector's memblock does not own its data.
	\throws[RangeError] if \tt{len} is invalid.)"),

	"opLengthAssign", 1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		auto len = croc_ex_checkIntParam(t, 1);

		if(!m.data->ownData)
			croc_eh_throwStd(t, "ValueError", "Attempting to change the length of a Vector which does not own its data");

		if(len < 0 || cast(uword)len > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid new length: %" CROC_INTEGER_FORMAT, len);

		push(Thread::from(t), Value::from(m.data));
		croc_lenai(t, -1, cast(uword)len * m.kind->itemSize);
		return 0;
	}

DListSep()
	Docstr(DFunc("opIndex") DParam("idx", "int")
	R"(Gets a single item from this Vector at the given index.

	\param[idx] is the index of the item to retrieve. Can be negative.

	\throws[BoundsError] if \tt{idx} is invalid.)"),

	"opIndex", 1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		auto idx = croc_ex_checkIndexParam(t, 1, m.itemLength, "element");
		push(Thread::from(t), _rawIndex(m, idx));
		return 1;
	}

DListSep()
	Docstr(DFunc("opIndexAssign") DParam("idx", "int") DParam("val", "int|float")
	R"(Sets a single item in this Vector at the given index to the given value.

	\param[idx] is the index of the item to set. Can be negative.
	\param[val] is the value to be set.

	\throws[BoundsError] if \tt{idx} is invalid.)"),

	"opIndexAssign", 2, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		auto idx = croc_ex_checkIndexParam(t, 1, m.itemLength, "element");

		if(m.kind->code <= TypeCode_u64)
			croc_ex_checkIntParam(t, 2);
		else
			croc_ex_checkNumParam(t, 2);

		_rawIndexAssign(m, idx, *getValue(Thread::from(t), 2));
		return 0;
	}

DListSep()
	Docstr(DFunc("opSlice") DParamD("lo", "int", "0") DParamD("hi", "int", "#this")
	R"(Creates a new Vector whose data is a copy of a slice of this Vector.

	Note that in the case that you want to copy data from a slice of one Vector into a slice of another (or even between
	parts of the same Vector), you can avoid creating unnecessary temporaries by using \link{copyRange} instead.

	\param[lo] is lower slice index into this Vector.
	\param[hi] is upper slice index into this Vector.
	\returns a new Vector with the same type as \tt{this}, whose data is a copy of the given slice.

	\throws[BoundsError] if \tt{lo} and \tt{hi} are invalid.)"),

	"opSlice", 2, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		uword_t lo, hi;
		lo = croc_ex_checkSliceParams(t, 1, m.itemLength, "slice", &hi);
		croc_pushGlobal(t, "Vector");
		croc_pushNull(t);
		croc_pushString(t, m.kind->name);
		croc_pushInt(t, hi - lo);
		croc_call(t, -4, 1);
		auto n = _getMembers(t, -1);
		auto isize = m.kind->itemSize;
		memcpy(n.data->data.ptr, m.data->data.ptr + (lo * isize), (hi - lo) * isize);
		return 0;
	}

DListSep()
	Docstr(DFunc("opSerialize")
	R"(These are methods meant to work with the \tt{serialization} library, allowing instances of \tt{Vector} to be
	serialized and deserialized.)"),

	"opSerialize", 2, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);

		if(!m.data->ownData)
			croc_eh_throwStd(t, "ValueError", "Attempting to serialize a Vector which does not own its data");

		croc_dup(t, 2);
		croc_pushNull(t);
		croc_pushString(t, m.kind->name);
		croc_call(t, -3, 0);
		croc_dup(t, 2);
		croc_pushNull(t);
		push(Thread::from(t), Value::from(m.data));
		croc_call(t, -3, 0);
		return 0;
	}

DListSep()
	Docstr(DFunc("opDeserialize")
	R"(ditto)"),

	"opDeserialize", 2, [](CrocThread* t) -> word_t
	{
		croc_dup(t, 2);
		croc_pushNull(t);
		croc_pushString(t, "string");
		croc_call(t, -3, 1);

		auto kind = _typeCodeToKind(getCrocstr(t, -1));
		croc_popTop(t);

		if(kind == nullptr)
			croc_eh_throwStd(t, "ValueError", "Malformed data (invalid Vector type code '%s')", croc_getString(t, -1));

		croc_pushInt(t, cast(crocint)kind);
		croc_hfielda(t, 0, Kind);
		croc_dup(t, 2);
		croc_pushNull(t);
		croc_pushString(t, "memblock");
		croc_call(t, -3, 1);
		croc_hfielda(t, 0, Data);
		return 0;
	}

DListSep()
	Docstr(DFunc("opCat") DParam("other", "int|float|Vector")
	R"(Concatenates this Vector with a number or another Vector, returning a new Vector that is the concatenation of the
	two.

	\tt{opCat_r} is to allow reverse concatenation, where the value is on the left and the Vector is on the right.

	\param[other] is either a number of the appropriate type, or another Vector. If \tt{other} is a Vector, it must be
	the same type as \tt{this}.
	\returns the new Vector object.
	\throws[ValueError] if \tt{other} is a Vector and its type differs from \tt{this}'s.)"),

	"opCat", 1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		croc_ex_checkAnyParam(t, 1);

		croc_pushGlobal(t, "Vector");

		if(croc_isInstanceOf(t, 1, -1))
		{
			auto other = _getMembers(t, 1);

			if(other.kind != m.kind)
				croc_eh_throwStd(t, "ValueError", "Attempting to concatenate Vectors of types '%s' and '%s'",
					m.kind->name, other.kind->name);

			croc_pushGlobal(t, "Vector");
			croc_pushNull(t);
			croc_pushString(t, m.kind->name);
			croc_pushInt(t, m.itemLength + other.itemLength);
			croc_call(t, -4, 1);

			auto n = _getMembers(t, -1);
			n.data->data.slicea(0, m.data->data.length, m.data->data);
			n.data->data.slicea(m.data->data.length, n.data->data.length, other.data->data);
		}
		else
		{
			if(m.kind->code <= TypeCode_u64)
				croc_ex_checkIntParam(t, 1);
			else
				croc_ex_checkNumParam(t, 1);

			croc_pushGlobal(t, "Vector");
			croc_pushNull(t);
			croc_pushString(t, m.kind->name);
			croc_pushInt(t, m.itemLength + 1);
			croc_call(t, -4, 1);

			auto n = _getMembers(t, -1);
			n.data->data.slicea(0, m.data->data.length, m.data->data);
			_rawIndexAssign(n, n.itemLength - 1, *getValue(Thread::from(t), 1));
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("opCat_r") DParam("other", "int|float")
	R"(ditto)"),

	"opCat_r", 1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		croc_ex_checkAnyParam(t, 1);

		if(m.kind->code <= TypeCode_u64)
			croc_ex_checkIntParam(t, 1);
		else
			croc_ex_checkNumParam(t, 1);

		croc_pushGlobal(t, "Vector");
		croc_pushNull(t);
		croc_pushString(t, m.kind->name);
		croc_pushInt(t, m.itemLength + 1);
		croc_call(t, -4, 1);

		auto n = _getMembers(t, -1);
		_rawIndexAssign(n, 0, *getValue(Thread::from(t), 1));
		n.data->data.slicea(1, n.data->data.length, m.data->data);

		return 1;
	}

DListSep()
	Docstr(DFunc("opCatAssign") DVararg
	R"(Appends one or more values or Vectors to the end of this Vector, in place.

	\param[vararg] is one or more values, each of which must be either a number of the appropriate type, or a Vector
	whose type is the same as \tt{this}'s. All the arguments will be appended to the end of this Vector in order.

	\throws[ParamError] if no varargs were passed.
	\throws[ValueError] if this Vector's memblock does not own its data.
	\throws[ValueError] if one of the varargs is a Vector whose type differs from \tt{this}'s.
	\throws[RangeError] if this memblock grows too large.)"),

	"opCatAssign", -1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		auto numParams = croc_getStackSize(t) - 1;
		croc_ex_checkAnyParam(t, 1);

		if(!m.data->ownData)
			croc_eh_throwStd(t, "ValueError", "Attempting to append to a Vector which does not own its data");

		uint64_t totalLen = m.itemLength;

		auto Vector = croc_pushGlobal(t, "Vector");

		for(uword i = 1; i <= numParams; i++)
		{
			if(croc_isInstanceOf(t, i, Vector))
			{
				auto other = _getMembers(t, i);

				if(other.kind != m.kind)
					croc_eh_throwStd(t, "ValueError", "Attempting to concatenate Vectors of types '%s' and '%s'",
						m.kind->name, other.kind->name);

				totalLen += other.itemLength;
			}
			else
			{
				if(m.kind->code <= TypeCode_u64)
					croc_ex_checkIntParam(t, i);
				else
					croc_ex_checkNumParam(t, i);

				totalLen++;
			}
		}

		croc_popTop(t);

		if(totalLen > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid size (%" CROC_UINTEGER_FORMAT ")", totalLen);

		auto isize = m.kind->itemSize;
		auto oldLen = m.itemLength;

		croc_dup(t, 0);
		croc_pushNull(t);
		croc_pushInt(t, cast(crocint)totalLen);
		croc_methodCall(t, -3, "opLengthAssign", 0);

		uword j = oldLen * isize;

		Vector = croc_pushGlobal(t, "Vector");
		auto t_ = Thread::from(t);

		for(uword i = 1; i <= numParams; i++)
		{
			if(croc_isInstanceOf(t, i, Vector))
			{
				if(croc_is(t, 0, i))
				{
					// special case for when we're appending a Vector to itself; use the old length
					memcpy(m.data->data.ptr + j, m.data->data.ptr, oldLen * isize);
					j += oldLen;
				}
				else
				{
					auto other = _getMembers(t, i);
					m.data->data.slicea(j, j + other.data->data.length, other.data->data);
					j += other.data->data.length;
				}
			}
			else
			{
				_rawIndexAssign(m, j / isize, *getValue(t_, i));
				j += isize;
			}
		}

		return 0;
	}

#define MAKE_OP(_op)\
	_op, 1, [](CrocThread* t) -> word_t\
	{\
		_getMembers(t);\
		croc_ex_checkAnyParam(t, 1);\
\
		auto ret = croc_dup(t, 0);\
		croc_pushNull(t);\
		croc_methodCall(t, -2, "dup", 1);\
		croc_dup(t, ret);\
		croc_pushNull(t);\
		croc_dup(t, 1);\
		croc_methodCall(t, -3, _op "eq", 0);\
		return 1;\
	}

DListSep()
	Docstr(DFunc("add") DParam("other", "int|float|Vector")
	R"(These all implement binary mathematical operators on Vectors. All return new Vector objects as the results.

	When performing an operation on a Vector and a number, the operation will be performed on each element of the Vector
	using the number as the other operand. When performing an operation on two Vectors, they must be the same type and
	length, and the operation is performed on each pair of elements.

	\param[other] is the second operand in the operation.
	\returns the new Vector whos values are the result of the operation.
	\throws[ValueError] if \tt{other} is a Vector and it is not the same length and type as \tt{this}.)"),
	MAKE_OP("add")

DListSep()
	Docstr(DFunc("sub") DParam("other", "int|float|Vector")
	R"(ditto)"),
	MAKE_OP("sub")

DListSep()
	Docstr(DFunc("mul") DParam("other", "int|float|Vector")
	R"(ditto)"),
	MAKE_OP("mul")

DListSep()
	Docstr(DFunc("div") DParam("other", "int|float|Vector")
	R"(ditto)"),
	MAKE_OP("div")

DListSep()
	Docstr(DFunc("mod") DParam("other", "int|float|Vector")
	R"(ditto)"),
	MAKE_OP("mod")

#define MAKE_OP_EQ(_name, _op, _floatOp)\
	_name, 1, [](CrocThread* t) -> word_t\
	{\
		auto m = _getMembers(t);\
		croc_ex_checkAnyParam(t, 1);\
\
		croc_pushGlobal(t, "Vector");\
\
		if(croc_isInstanceOf(t, 1, -1))\
		{\
			auto other = _getMembers(t, 1);\
\
			if(other.itemLength != m.itemLength)\
				croc_eh_throwStd(t, "ValueError", "Cannot perform operation on Vectors of different lengths");\
\
			if(other.kind != m.kind)\
				croc_eh_throwStd(t, "ValueError", "Cannot perform operation on Vectors of types '%s' and '%s'",\
					m.kind->name, other.kind->name);\
\
			switch(m.kind->code)\
			{\
				case TypeCode_i8:  { auto dst = m.data->data.template as<int8_t>  (); auto src = other.data->data.template as<int8_t>  (); _op(dst, dst, src); break; }\
				case TypeCode_i16: { auto dst = m.data->data.template as<int16_t> (); auto src = other.data->data.template as<int16_t> (); _op(dst, dst, src); break; }\
				case TypeCode_i32: { auto dst = m.data->data.template as<int32_t> (); auto src = other.data->data.template as<int32_t> (); _op(dst, dst, src); break; }\
				case TypeCode_i64: { auto dst = m.data->data.template as<int64_t> (); auto src = other.data->data.template as<int64_t> (); _op(dst, dst, src); break; }\
				case TypeCode_u8:  { auto dst = m.data->data.template as<uint8_t> (); auto src = other.data->data.template as<uint8_t> (); _op(dst, dst, src); break; }\
				case TypeCode_u16: { auto dst = m.data->data.template as<uint16_t>(); auto src = other.data->data.template as<uint16_t>(); _op(dst, dst, src); break; }\
				case TypeCode_u32: { auto dst = m.data->data.template as<uint32_t>(); auto src = other.data->data.template as<uint32_t>(); _op(dst, dst, src); break; }\
				case TypeCode_u64: { auto dst = m.data->data.template as<uint64_t>(); auto src = other.data->data.template as<uint64_t>(); _op(dst, dst, src); break; }\
				case TypeCode_f32: { auto dst = m.data->data.template as<float>   (); auto src = other.data->data.template as<float>   (); _floatOp(dst, dst, src); break; }\
				case TypeCode_f64: { auto dst = m.data->data.template as<double>  (); auto src = other.data->data.template as<double>  (); _floatOp(dst, dst, src); break; }\
				default: assert(false);\
			}\
		}\
		else\
		{\
			switch(m.kind->code)\
			{\
				case TypeCode_i8:  { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<int8_t>  (); _op##Val(dst, dst, val); break; }\
				case TypeCode_i16: { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<int16_t> (); _op##Val(dst, dst, val); break; }\
				case TypeCode_i32: { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<int32_t> (); _op##Val(dst, dst, val); break; }\
				case TypeCode_i64: { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<int64_t> (); _op##Val(dst, dst, val); break; }\
				case TypeCode_u8:  { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<uint8_t> (); _op##Val(dst, dst, val); break; }\
				case TypeCode_u16: { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<uint16_t>(); _op##Val(dst, dst, val); break; }\
				case TypeCode_u32: { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<uint32_t>(); _op##Val(dst, dst, val); break; }\
				case TypeCode_u64: { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<uint64_t>(); _op##Val(dst, dst, val); break; }\
				case TypeCode_f32: { auto val = croc_ex_checkNumParam(t, 1); auto dst = m.data->data.template as<float>   (); _floatOp##Val(dst, dst, val); break; }\
				case TypeCode_f64: { auto val = croc_ex_checkNumParam(t, 1); auto dst = m.data->data.template as<double>  (); _floatOp##Val(dst, dst, val); break; }\
				default: assert(false);\
			}\
		}\
\
		return 0;\
	}


DListSep()
	Docstr(DFunc("addeq") DParam("other", "int|float|Vector")
	R"(These all implement reflexive mathematical operators on Vectors. All operate in-place on this Vector.

	The behavior is otherwise identical to the binary mathematical operations.

	\param[other] is the right-hand side of the operation.
	\throws[ValueError] if \tt{other} is a Vector and it is not the same length and type as \tt{this}.)"),
	MAKE_OP_EQ("addeq", _vecAdd, _vecAdd)

DListSep()
	Docstr(DFunc("subeq") DParam("other", "int|float|Vector")
	R"(ditto)"),
	MAKE_OP_EQ("subeq", _vecSub, _vecSub)

DListSep()
	Docstr(DFunc("muleq") DParam("other", "int|float|Vector")
	R"(ditto)"),
	MAKE_OP_EQ("muleq", _vecMul, _vecMul)

DListSep()
	Docstr(DFunc("diveq") DParam("other", "int|float|Vector")
	R"(ditto)"),
	MAKE_OP_EQ("diveq", _vecDiv, _vecDiv)

DListSep()
	Docstr(DFunc("modeq") DParam("other", "int|float|Vector")
	R"(ditto)"),
	MAKE_OP_EQ("modeq", _vecMod, _vecModFloat)

#define MAKE_REV(_op)\
	"rev" _op, 1, [](CrocThread* t) -> word_t\
	{\
		_getMembers(t);\
		croc_ex_checkAnyParam(t, 1);\
\
		auto ret = croc_dup(t, 0);\
		croc_pushNull(t);\
		croc_methodCall(t, -2, "dup", 1);\
		croc_dup(t, ret);\
		croc_pushNull(t);\
		croc_dup(t, 1);\
		croc_methodCall(t, -3, "rev" _op "eq", 0);\
\
		return 1;\
	}

DListSep()
	Docstr(DFunc("revsub") DParam("other", "int|float|Vector")
	R"x(These allow you to perform binary mathematical operations where this Vector will be used as the second operand
	instead of the first.

	For example, doing \\tt{"v.sub(5)"} will return a Vector with 5 subtracted from each element in \tt{v}, but doing
	\tt{"v.revsub(5)"} will instead give a Vector with each element in \tt{v} subtracted from 5.

	The behavior is otherwise identical to the regular mathematical operations.

	\param[other] is the left-hand side of the operation.
	\throws[ValueError] if \tt{other} is a Vector and it is not the same length and type as \tt{this}.)x"),
	MAKE_REV("sub")

DListSep()
	Docstr(DFunc("revdiv") DParam("other", "int|float|Vector")
	R"(ditto)"),
	MAKE_REV("div")

DListSep()
	Docstr(DFunc("revmod") DParam("other", "int|float|Vector")
	R"(ditto)"),
	MAKE_REV("mod")

#define MAKE_REV_EQ(funcName, _op, _floatOp, _valOp, _valFloatOp)\
	funcName, 1, [](CrocThread* t) -> word_t\
	{\
		auto m = _getMembers(t);\
		croc_ex_checkAnyParam(t, 1);\
\
		croc_pushGlobal(t, "Vector");\
\
		if(croc_isInstanceOf(t, 1, -1))\
		{\
			auto other = _getMembers(t, 1);\
\
			if(other.itemLength != m.itemLength)\
				croc_eh_throwStd(t, "ValueError", "Cannot perform operation on Vectors of different lengths");\
\
			if(other.kind != m.kind)\
				croc_eh_throwStd(t, "ValueError", "Cannot perform operation on Vectors of types '%s' and '%s'",\
					m.kind->name, other.kind->name);\
\
			switch(m.kind->code)\
			{\
				case TypeCode_i8:  { auto dst = m.data->data.template as<int8_t>  (); auto src = other.data->data.template as<int8_t>  (); _op(dst, src, dst); break; }\
				case TypeCode_i16: { auto dst = m.data->data.template as<int16_t> (); auto src = other.data->data.template as<int16_t> (); _op(dst, src, dst); break; }\
				case TypeCode_i32: { auto dst = m.data->data.template as<int32_t> (); auto src = other.data->data.template as<int32_t> (); _op(dst, src, dst); break; }\
				case TypeCode_i64: { auto dst = m.data->data.template as<int64_t> (); auto src = other.data->data.template as<int64_t> (); _op(dst, src, dst); break; }\
				case TypeCode_u8:  { auto dst = m.data->data.template as<uint8_t> (); auto src = other.data->data.template as<uint8_t> (); _op(dst, src, dst); break; }\
				case TypeCode_u16: { auto dst = m.data->data.template as<uint16_t>(); auto src = other.data->data.template as<uint16_t>(); _op(dst, src, dst); break; }\
				case TypeCode_u32: { auto dst = m.data->data.template as<uint32_t>(); auto src = other.data->data.template as<uint32_t>(); _op(dst, src, dst); break; }\
				case TypeCode_u64: { auto dst = m.data->data.template as<uint64_t>(); auto src = other.data->data.template as<uint64_t>(); _op(dst, src, dst); break; }\
				case TypeCode_f32: { auto dst = m.data->data.template as<float>   (); auto src = other.data->data.template as<float>   (); _floatOp(dst, src, dst); break; }\
				case TypeCode_f64: { auto dst = m.data->data.template as<double>  (); auto src = other.data->data.template as<double>  (); _floatOp(dst, src, dst); break; }\
				default: assert(false);\
			}\
		}\
		else\
		{\
			switch(m.kind->code)\
			{\
				case TypeCode_i8:  { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<int8_t>  (); _valOp(dst, val, dst); break; }\
				case TypeCode_i16: { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<int16_t> (); _valOp(dst, val, dst); break; }\
				case TypeCode_i32: { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<int32_t> (); _valOp(dst, val, dst); break; }\
				case TypeCode_i64: { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<int64_t> (); _valOp(dst, val, dst); break; }\
				case TypeCode_u8:  { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<uint8_t> (); _valOp(dst, val, dst); break; }\
				case TypeCode_u16: { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<uint16_t>(); _valOp(dst, val, dst); break; }\
				case TypeCode_u32: { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<uint32_t>(); _valOp(dst, val, dst); break; }\
				case TypeCode_u64: { auto val = croc_ex_checkIntParam(t, 1); auto dst = m.data->data.template as<uint64_t>(); _valOp(dst, val, dst); break; }\
				case TypeCode_f32: { auto val = croc_ex_checkNumParam(t, 1); auto dst = m.data->data.template as<float>   (); _valFloatOp(dst, val, dst); break; }\
				case TypeCode_f64: { auto val = croc_ex_checkNumParam(t, 1); auto dst = m.data->data.template as<double>  (); _valFloatOp(dst, val, dst); break; }\
				default: assert(false);\
			}\
		}\
\
		croc_dup(t, 0);\
		return 0;\
	}

DListSep()
	Docstr(DFunc("revsubeq") DParam("other", "int|float|Vector")
	R"(These allow you to perform in-place reflexive operations where this Vector will be used as the second operand
	instead of as the first.

	The behavior is otherwise identical to the reflexive mathematical operations.

	\param[other] is the left-hand side of the operation.
	\throws[ValueError] if \tt{other} is a Vector and it is not the same length and type as \tt{this}.)"),
	MAKE_REV_EQ("revsubeq", _vecSub, _vecSub, _revVecSubVal, _revVecSubVal)

DListSep()
	Docstr(DFunc("revdiveq") DParam("other", "int|float|Vector")
	R"(ditto)"),
	MAKE_REV_EQ("revdiveq", _vecDiv, _vecDiv, _revVecDivVal, _revVecDivVal)

DListSep()
	Docstr(DFunc("revmodeq") DParam("other", "int|float|Vector")
	R"(ditto)"),
	MAKE_REV_EQ("revmodeq", _vecMod, _vecModFloat, _revVecModVal, _revVecModFloatVal)
DEndList()

DBeginList(_opApply)
	nullptr,

	"iterator", 1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		auto index = croc_ex_checkIntParam(t, 1) + 1;

		if(cast(uword)index >= m.itemLength)
			return 0;

		croc_pushInt(t, index);
		push(Thread::from(t), _rawIndex(m, cast(uword)index));
		return 2;
	}

DListSep()
	nullptr,

	"iteratorReverse", 1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		auto index = croc_ex_checkIntParam(t, 1) - 1;

		if(index < 0)
			return 0;

		croc_pushInt(t, index);
		push(Thread::from(t), _rawIndex(m, cast(uword)index));
		return 2;
	}

DListSep()
	Docstr(DFunc("opApply") DParamD("mode", "string", "\"\"")
	R"(Allows you to iterate over the contents of a Vector using a \tt{foreach} loop.

	This works just like the \tt{opApply} defined for arrays. The indices in the loop will be the element index followed
	by the element value. You can iterate in reverse by passing the string value \tt{"reverse"} as the \tt{mode}
	argument. For example:

\code
local v = Vector.range("i32", 1, 6)
foreach(i, val; v) write(val) // prints 12345
foreach(i, val; v, "reverse") write(val) // prints 54321
\endcode

	\param[mode] is the iteration mode. The only valid modes are \tt{"reverse"}, which runs iteration backwards,
	and the empty string \{""}, which is normal forward iteration.

	\throws[ValueError] if \tt{mode} is invalid.)"),

	"opApply", 1, [](CrocThread* t) -> word_t
	{
		auto m = _getMembers(t);
		auto dir = croc_ex_optStringParam(t, 1, "");

		if(strcmp(dir, "") == 0)
		{
			croc_pushUpval(t, 0);
			croc_dup(t, 0);
			croc_pushInt(t, -1);
		}
		else if(strcmp(dir, "reverse") == 0)
		{
			croc_pushUpval(t, 1);
			croc_dup(t, 0);
			croc_pushInt(t, m.itemLength);
		}
		else
			croc_eh_throwStd(t, "ValueError", "Invalid iteration mode");

		return 3;
	}
DEndList()
	}

	void initMiscLib_Vector(CrocThread* t)
	{
		croc_class_new(t, "Vector", 0);
			croc_pushNull(t);   croc_class_addHField(t, -2, Data);
			croc_pushInt(t, 0); croc_class_addHField(t, -2, Kind);
			registerMethods(t, _methods);
			registerMethodUV(t, _opApply);
			croc_field(t, -1, "fillRange");   croc_class_addMethod(t, -2, "opSliceAssign");
			croc_field(t, -1, "opCatAssign"); croc_class_addMethod(t, -2, "append");
		croc_newGlobal(t, "Vector");
	}

#ifdef CROC_BUILTIN_DOCS
	void docMiscLib_Vector(CrocThread* t, CrocDoc* doc)
	{
		croc_pushGlobal(t, "Vector");
			croc_ex_doc_push(doc, DClass("Vector")
			R"(Croc's built-in array type is fine for most tasks, but they're not very well-suited to high-speed number
			crunching. Memblocks give you a low-level memory buffer, but don't provide any data structuring. Vectors
			solve both these problems: they are dynamically-resizable strongly-typed single-dimensional arrays of
			numerical values built on top of memblocks.

			There are ten possible types a Vector can hold. Each type has an associated "type code", which is just a
			string. The types and their type codes are as follows:

			\table
				\row \cell \b{Type Code} \cell \b{Definition}
				\row \cell \tt{i8}       \cell Signed 8-bit integer
				\row \cell \tt{i16}      \cell Signed 16-bit integer
				\row \cell \tt{i32}      \cell Signed 32-bit integer
				\row \cell \tt{i64}      \cell Signed 64-bit integer
				\row \cell \tt{u8}       \cell Unsigned 8-bit integer
				\row \cell \tt{u16}      \cell Unsigned 16-bit integer
				\row \cell \tt{u32}      \cell Unsigned 32-bit integer
				\row \cell \tt{u64}      \cell Unsigned 64-bit integer
				\row \cell \tt{f32}      \cell Single-precision IEEE 754 float
				\row \cell \tt{f64}      \cell Double-precision IEEE 754 float
			\endtable

			These type codes are case-sensitive, so for example, passing \tt{"u8"} to the constructor is legal, whereas
			\tt{"U8"} is not.

			A note on the \tt{"u64"} type: Croc's int type is a signed 64-bit integer, which does not have the range to
			represent all possible values that an unsigned 64-bit integer can. So when dealing with \tt{"u64"} Vectors,
			values larger than 2\sup{63} - 1 will be represented as negative Croc integers. However, internally, all the
			operations on these Vectors will be performed according to unsigned integer rules. The \tt{toString} method
			is also aware of this and will print the values correctly, and if you'd like to print out unsigned 64-bit
			integers yourself, you can use \tt{toString(val, 'u')} from the base library.

			A note on all types: for performance reasons, Vectors do not check the ranges of the values that are stored
			in them. For instance, if you assign an integer into a \tt{"u8" Vector}, only the lowest 8 bits will be
			stored. Storing \tt{floats} into \tt{"f32" Vectors} will similarly round the value to the nearest
			representable single-precision value.

			Finally, the underlying memblock can be retrieved and manipulated directly; however, changing its size must
			be done carefully. If the size is set to a byte length that is not an even multiple of the item size of the
			Vector, an exception will be thrown the next time a method is called on the Vector that uses that memblock.

			All methods, unless otherwise documented, return the Vector object on which they were called.)");
			docFields(doc, _methods);
			docFieldUV(doc, _opApply);
			croc_ex_doc_pop(doc, -1);
		croc_popTop(t);
	}
#endif
}