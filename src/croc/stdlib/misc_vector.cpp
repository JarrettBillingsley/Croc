
#include <cmath>
#include <limits>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"
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
			case TypeCode_i8:  (cast(int8_t*)  m.data->data.ptr)[idx] = cast(int8_t)val.mInt;                                                   return;
			case TypeCode_i16: (cast(int16_t*) m.data->data.ptr)[idx] = cast(int16_t)val.mInt;                                                  return;
			case TypeCode_i32: (cast(int32_t*) m.data->data.ptr)[idx] = cast(int32_t)val.mInt;                                                  return;
			case TypeCode_i64: (cast(int64_t*) m.data->data.ptr)[idx] = cast(int64_t)val.mInt;                                                  return;
			case TypeCode_u8:  (cast(uint8_t*) m.data->data.ptr)[idx] = cast(uint8_t)val.mInt;                                                  return;
			case TypeCode_u16: (cast(uint16_t*)m.data->data.ptr)[idx] = cast(uint16_t)val.mInt;                                                 return;
			case TypeCode_u32: (cast(uint32_t*)m.data->data.ptr)[idx] = cast(uint32_t)val.mInt;                                                 return;
			case TypeCode_u64: (cast(uint64_t*)m.data->data.ptr)[idx] = cast(uint64_t)val.mInt;                                                 return;
			case TypeCode_f32: (cast(float*) m.data->data.ptr)[idx] = val.type == CrocType_Int ? cast(float)val.mInt  : cast(float)val.mFloat;  return;
			case TypeCode_f64: (cast(double*)m.data->data.ptr)[idx] = val.type == CrocType_Int ? cast(double)val.mInt : cast(double)val.mFloat; return;
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
				if(strcmp(cast(const char*)typeCode.ptr, "i8")  == 0) return &_typeStructs[TypeCode_i8];
				if(strcmp(cast(const char*)typeCode.ptr, "i16") == 0) return &_typeStructs[TypeCode_i16];
				if(strcmp(cast(const char*)typeCode.ptr, "i32") == 0) return &_typeStructs[TypeCode_i32];
				if(strcmp(cast(const char*)typeCode.ptr, "i64") == 0) return &_typeStructs[TypeCode_i64];
			}
			else if(typeCode[0] == 'u')
			{
				if(strcmp(cast(const char*)typeCode.ptr, "u8")  == 0) return &_typeStructs[TypeCode_u8];
				if(strcmp(cast(const char*)typeCode.ptr, "u16") == 0) return &_typeStructs[TypeCode_u16];
				if(strcmp(cast(const char*)typeCode.ptr, "u32") == 0) return &_typeStructs[TypeCode_u32];
				if(strcmp(cast(const char*)typeCode.ptr, "u64") == 0) return &_typeStructs[TypeCode_u64];
			}
			else if(typeCode[0] == 'f')
			{
				if(strcmp(cast(const char*)typeCode.ptr, "f32") == 0) return &_typeStructs[TypeCode_f32];
				if(strcmp(cast(const char*)typeCode.ptr, "f64") == 0) return &_typeStructs[TypeCode_f64];
			}
		}

		return nullptr;
	}

	word_t _constructor(CrocThread* t)
	{
		croc_hfield(t, 0, Data);

		if(!croc_isNull(t, -1))
			croc_eh_throwStd(t, "StateError", "Attempting to call constructor on an already-initialized Vector");

		croc_popTop(t);

		croc_ex_checkStringParam(t, 1);

		auto kind = _typeCodeToKind(getCrocstr(Thread::from(t), 1));

		if(kind == nullptr)
			croc_eh_throwStd(t, "ValueError", "Invalid type code '%s'", croc_getString(t, 1));

		croc_pushInt(t, cast(crocint)kind);
		croc_hfielda(t, 0, Kind);

		auto size = croc_ex_checkIntParam(t, 2);

		if(size < 0 || size > std::numeric_limits<uword>::max())
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

	word_t _fromArray(CrocThread* t)
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
		if(size > std::numeric_limits<uword>::max())\
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

	word_t _range(CrocThread* t)
	{
		uword typeLen;
		auto type = croc_ex_checkStringParamn(t, 1, &typeLen);

		if(typeLen >= 2 && typeLen <= 3)
		{
			if(
				(type[0] == 'i' &&
					(strcmp(type, "i8") == 0 ||
					strcmp(type, "i16") == 0 ||
					strcmp(type, "i32") == 0 ||
					strcmp(type, "i64") == 0)
				) ||
				(type[0] == 'u' &&
					(strcmp(type, "u8") == 0 ||
					strcmp(type, "u16") == 0 ||
					strcmp(type, "u32") == 0 ||
					strcmp(type, "u64") == 0)
				))
			{
				_intRangeImpl(t, crocstr::n(cast(const uchar*)type, typeLen));
				return 1;
			}
			else if(type[0] == 'f' && (strcmp(type, "f32") == 0 || strcmp(type, "f64") == 0))
			{
				_floatRangeImpl(t, crocstr::n(cast(const uchar*)type, typeLen));
				return 1;
			}
		}

		return croc_eh_throwStd(t, "ValueError", "Invalid type code '%s'", type);
	}

	word_t _type(CrocThread* t)
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
			auto ts = _typeCodeToKind(getCrocstr(Thread::from(t), 1));

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

	word_t _itemSize(CrocThread* t)
	{
		auto m = _getMembers(t);
		croc_pushInt(t, m.kind->itemSize);
		return 1;
	}

	word_t _toArray(CrocThread* t)
	{
		auto m = _getMembers(t);
		auto lo = croc_ex_optIntParam(t, 1, 0);
		auto hi = croc_ex_optIntParam(t, 2, m.itemLength);

		if(lo < 0)
			lo += m.itemLength;

		if(hi < 0)
			hi += m.itemLength;

		if(lo < 0 || lo > hi || hi > m.itemLength)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid slice indices: %" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT
				" (length: %u)",
				lo, hi, m.itemLength);

		auto ret = croc_array_new(t, cast(uword)(hi - lo));
		auto t_ = Thread::from(t);

		for(uword i = cast(uword)lo, j = 0; i < cast(uword)hi; i++, j++)
		{
			push(t_, _rawIndex(m, i));
			croc_idxai(t, ret, j);
		}

		return 1;
	}

	word_t _toString(CrocThread* t)
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

	word_t _getMemblock(CrocThread* t)
	{
		auto m = _getMembers(t);
		push(Thread::from(t), Value::from(m.data));
		return 1;
	}

	word_t _dup(CrocThread* t)
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

	word_t _reverse(CrocThread* t)
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

	word_t _sort(CrocThread* t)
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

	word_t _apply(CrocThread* t)
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

	word_t _map(CrocThread* t)
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

	word_t _min(CrocThread* t)
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

	word_t _max(CrocThread* t)
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

	word_t _insert(CrocThread* t)
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
		if(idx < 0 || idx > len)
			croc_eh_throwStd(t, "BoundsError", "Invalid index: %" CROC_INTEGER_FORMAT " (length: %u)", idx, len);

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

			if(idx < oldLen)
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

	word_t _remove(CrocThread* t)
	{
		auto m = _getMembers(t);

		if(!m.data->ownData)
			croc_eh_throwStd(t, "ValueError", "Attempting to remove from a Vector which does not own its data");

		if(m.itemLength == 0)
			croc_eh_throwStd(t, "ValueError", "Vector is empty");

		auto lo = croc_ex_checkIntParam(t, 1);
		auto hi = croc_ex_optIntParam(t, 2, lo + 1);

		if(lo < 0)
			lo += m.itemLength;

		if(hi < 0)
			hi += m.itemLength;

		if(lo < 0 || lo > hi || hi > m.itemLength)
			croc_eh_throwStd(t, "BoundsError", "Invalid indices: %" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT
				" (length: %u)",
				lo, hi, m.itemLength);

		if(lo != hi)
		{
			auto isize = m.kind->itemSize;

			if(hi < m.itemLength)
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

	word_t _pop(CrocThread* t)
	{
		auto m = _getMembers(t);

		if(!m.data->ownData)
			croc_eh_throwStd(t, "ValueError", "Attempting to pop from a Vector which does not own its data");

		if(m.itemLength == 0)
			croc_eh_throwStd(t, "ValueError", "Vector is empty");

		auto index = croc_ex_optIntParam(t, 1, -1);

		if(index < 0)
			index += m.itemLength;

		if(index < 0 || index >= m.itemLength)
			croc_eh_throwStd(t, "BoundsError", "Invalid index: %" CROC_INTEGER_FORMAT, index);

		push(Thread::from(t), _rawIndex(m, cast(uword)index));

		auto isize = m.kind->itemSize;

		if(index < m.itemLength - 1)
			memmove(&m.data->data[cast(uword)index * isize], &m.data->data[(cast(uword)index + 1) * isize],
				cast(uword)((m.itemLength - index - 1) * isize));

		push(Thread::from(t), Value::from(m.data));
		croc_lenai(t, -1, (m.itemLength - 1) * isize);
		croc_popTop(t);

		return 1;
	}

	word_t _sum(CrocThread* t)
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

	word_t _product(CrocThread* t)
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

	word_t _copyRange(CrocThread* t)
	{
		auto m = _getMembers(t);
		auto lo = croc_ex_optIntParam(t, 1, 0);
		auto hi = croc_ex_optIntParam(t, 2, m.itemLength);

		if(lo < 0)
			lo += m.itemLength;

		if(hi < 0)
			hi += m.itemLength;

		if(lo < 0 || lo > hi || hi > m.itemLength)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid destination slice indices: %" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT " (length: %u)",
				lo, hi, m.itemLength);

		auto other = _getMembers(t, 3);

		if(m.kind != other.kind)
			croc_eh_throwStd(t, "ValueError", "Attempting to copy a Vector of type '%s' into a Vector of type '%s'",
				other.kind->name, m.kind->name);

		auto lo2 = croc_ex_optIntParam(t, 4, 0);
		auto hi2 = croc_ex_optIntParam(t, 5, lo2 + (hi - lo));

		if(lo2 < 0)
			lo2 += other.itemLength;

		if(hi2 < 0)
			hi2 += other.itemLength;

		if(lo2 < 0 || lo2 > hi2 || hi2 > other.itemLength)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid source slice indices: %" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT " (length: %u)",
				lo2, hi2, other.itemLength);

		if((hi - lo) != (hi2 - lo2))
			croc_eh_throwStd(t, "ValueError", "Destination length (%u) and source length(%u) do not match",
				cast(uword)(hi - lo), cast(uword)(hi2 - lo2));

		auto isize = m.kind->itemSize;

		if(croc_is(t, 0, 3))
			memmove(&m.data->data[cast(uword)lo * isize], &other.data->data[cast(uword)lo2 * isize],
				cast(uword)(hi - lo) * isize);
		else
			memcpy(&m.data->data[cast(uword)lo * isize], &other.data->data[cast(uword)lo2 * isize],
				cast(uword)(hi - lo) * isize);

		croc_dup(t, 0);
		return 1;
	}

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
				croc_eh_throwStd(t, "ValueError", "Length of destination (%u) and length of source (%u) do not match",
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
			if(croc_len(t, filler) != (hi - lo))
				croc_eh_throwStd(t, "ValueError",
					"Length of destination (%u) and length of array (%" CROC_INTEGER_FORMAT ") do not match",
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
						croc_eh_throwStd(t, "ValueError", "array element %u expected to be 'int', not '%s'",
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
						croc_eh_throwStd(t, "ValueError", "array element %u expected to be 'int' or 'float', not '%s'",
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

	word_t _fill(CrocThread* t)
	{
		auto m = _getMembers(t);
		croc_ex_checkAnyParam(t, 1);
		_fillImpl(t, m, 1, 0, m.itemLength);
		croc_dup(t, 0);
		return 1;
	}

	word_t _fillRange(CrocThread* t)
	{
		auto m = _getMembers(t);
		auto lo = croc_ex_optIntParam(t, 1, 0);
		auto hi = croc_ex_optIntParam(t, 2, m.itemLength);
		croc_ex_checkAnyParam(t, 3);

		if(lo < 0)
			lo += m.itemLength;

		if(hi < 0)
			hi += m.itemLength;

		if(lo < 0 || lo > hi || hi > m.itemLength)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid range indices (%" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT ")", lo, hi);

		_fillImpl(t, m, 3, cast(uword)lo, cast(uword)hi);
		croc_dup(t, 0);
		return 1;
	}

	word_t _opEquals(CrocThread* t)
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

	word_t _opCmp(CrocThread* t)
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
				case TypeCode_i8:  cmp = m.data->data.template as<int8_t>  ().cmp(other.data->data.template as<int8_t>  ()); break;
				case TypeCode_i16: cmp = m.data->data.template as<int16_t> ().cmp(other.data->data.template as<int16_t> ()); break;
				case TypeCode_i32: cmp = m.data->data.template as<int32_t> ().cmp(other.data->data.template as<int32_t> ()); break;
				case TypeCode_i64: cmp = m.data->data.template as<int64_t> ().cmp(other.data->data.template as<int64_t> ()); break;
				case TypeCode_u8:  cmp = m.data->data.template as<uint8_t> ().cmp(other.data->data.template as<uint8_t> ()); break;
				case TypeCode_u16: cmp = m.data->data.template as<uint16_t>().cmp(other.data->data.template as<uint16_t>()); break;
				case TypeCode_u32: cmp = m.data->data.template as<uint32_t>().cmp(other.data->data.template as<uint32_t>()); break;
				case TypeCode_u64: cmp = m.data->data.template as<uint64_t>().cmp(other.data->data.template as<uint64_t>()); break;
				case TypeCode_f32: cmp = m.data->data.template as<float>   ().cmp(other.data->data.template as<float>   ()); break;
				case TypeCode_f64: cmp = m.data->data.template as<double>  ().cmp(other.data->data.template as<double>  ()); break;
				default: assert(false); cmp = 0; // dummy;
			}

			croc_pushInt(t, cmp);
		}

		return 1;
	}

	word_t _opLength(CrocThread* t)
	{
		auto m = _getMembers(t);
		croc_pushInt(t, m.itemLength);
		return 1;
	}

	word_t _opLengthAssign(CrocThread* t)
	{
		auto m = _getMembers(t);
		auto len = croc_ex_checkIntParam(t, 1);

		if(!m.data->ownData)
			croc_eh_throwStd(t, "ValueError", "Attempting to change the length of a Vector which does not own its data");

		if(len < 0 || len > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid new length: %" CROC_INTEGER_FORMAT, len);

		push(Thread::from(t), Value::from(m.data));
		croc_lenai(t, -1, cast(uword)len * m.kind->itemSize);
		return 0;
	}

	word_t _opIndex(CrocThread* t)
	{
		auto m = _getMembers(t);
		auto idx = croc_ex_checkIntParam(t, 1);

		if(idx < 0)
			idx += m.itemLength;

		if(idx < 0 || idx >= m.itemLength)
			croc_eh_throwStd(t, "BoundsError", "Invalid index %" CROC_INTEGER_FORMAT " for Vector of length %u",
				idx, m.itemLength);

		push(Thread::from(t), _rawIndex(m, cast(uword)idx));
		return 1;
	}

	word_t _opIndexAssign(CrocThread* t)
	{
		auto m = _getMembers(t);
		auto idx = croc_ex_checkIntParam(t, 1);

		if(idx < 0)
			idx += m.itemLength;

		if(idx < 0 || idx >= m.itemLength)
			croc_eh_throwStd(t, "BoundsError", "Invalid index %" CROC_INTEGER_FORMAT " for Vector of length %u",
				idx, m.itemLength);

		if(m.kind->code <= TypeCode_u64)
			croc_ex_checkIntParam(t, 2);
		else
			croc_ex_checkNumParam(t, 2);

		_rawIndexAssign(m, cast(uword)idx, *getValue(Thread::from(t), 2));
		return 0;
	}

	word_t _opSlice(CrocThread* t)
	{
		auto m = _getMembers(t);
		auto lo = croc_ex_optIntParam(t, 1, 0);
		auto hi = croc_ex_optIntParam(t, 2, m.itemLength);

		if(lo < 0)
			lo += m.itemLength;

		if(hi < 0)
			hi += m.itemLength;

		if(lo < 0 || lo > hi || hi > m.itemLength)
			croc_eh_throwStd(t, "BoundsError",
				"Invalid slice indices %" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT " for Vector of length %u",
				lo, hi, m.itemLength);

		croc_pushGlobal(t, "Vector");
		croc_pushNull(t);
		croc_pushString(t, m.kind->name);
		croc_pushInt(t, hi - lo);
		croc_call(t, -4, 1);
		auto n = _getMembers(t, -1);
		auto isize = m.kind->itemSize;

		memcpy(n.data->data.ptr, m.data->data.ptr + (cast(uword)lo * isize), (cast(uword)hi - cast(uword)lo) * isize);

		return 0;
	}

	word_t _opSerialize(CrocThread* t)
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

	word_t _opDeserialize(CrocThread* t)
	{
		croc_dup(t, 2);
		croc_pushNull(t);
		croc_pushString(t, "string");
		croc_call(t, -3, 1);

		auto kind = _typeCodeToKind(getCrocstr(Thread::from(t), -1));
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

	word_t _opCat(CrocThread* t)
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

	word_t _opCat_r(CrocThread* t)
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

	word_t _opCatAssign(CrocThread* t)
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

#define MAKE_OP(funcName, _op)\
	word_t funcName(CrocThread* t)\
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

	MAKE_OP(_add, "add")
	MAKE_OP(_sub, "sub")
	MAKE_OP(_mul, "mul")
	MAKE_OP(_div, "div")
	MAKE_OP(_mod, "mod")

#define MAKE_OP_EQ(funcName, _op, _floatOp)\
	word_t funcName(CrocThread* t)\
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

	MAKE_OP_EQ(_addeq, _vecAdd, _vecAdd)
	MAKE_OP_EQ(_subeq, _vecSub, _vecSub)
	MAKE_OP_EQ(_muleq, _vecMul, _vecMul)
	MAKE_OP_EQ(_diveq, _vecDiv, _vecDiv)
	MAKE_OP_EQ(_modeq, _vecMod, _vecModFloat)

#define MAKE_REV(funcName, _op)\
	word_t funcName(CrocThread* t)\
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

	MAKE_REV(_revsub, "sub")
	MAKE_REV(_revdiv, "div")
	MAKE_REV(_revmod, "mod")

#define MAKE_REV_EQ(funcName, _op, _floatOp, _valOp, _valFloatOp)\
	word_t funcName(CrocThread* t)\
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

	MAKE_REV_EQ(_revsubeq, _vecSub, _vecSub, _revVecSubVal, _revVecSubVal)
	MAKE_REV_EQ(_revdiveq, _vecDiv, _vecDiv, _revVecDivVal, _revVecDivVal)
	MAKE_REV_EQ(_revmodeq, _vecMod, _vecModFloat, _revVecModVal, _revVecModFloatVal)

	word_t _opApply(CrocThread* t)
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

	word_t _iterator(CrocThread* t)
	{
		auto m = _getMembers(t);
		auto index = croc_ex_checkIntParam(t, 1) + 1;

		if(index >= m.itemLength)
			return 0;

		croc_pushInt(t, index);
		push(Thread::from(t), _rawIndex(m, cast(uword)index));
		return 2;
	}

	word_t _iteratorReverse(CrocThread* t)
	{
		auto m = _getMembers(t);
		auto index = croc_ex_checkIntParam(t, 1) - 1;

		if(index < 0)
			return 0;

		croc_pushInt(t, index);
		push(Thread::from(t), _rawIndex(m, cast(uword)index));
		return 2;
	}

	const CrocRegisterFunc _methods[] =
	{
		{"constructor",     3, &_constructor   },
		{"fromArray",       2, &_fromArray     },
		{"range",           4, &_range         },
		{"type",            1, &_type          },
		{"itemSize",        0, &_itemSize      },
		{"toArray",         2, &_toArray       },
		{"toString",        0, &_toString      },
		{"getMemblock",     0, &_getMemblock   },
		{"dup",             0, &_dup           },
		{"reverse",         0, &_reverse       },
		{"sort",            0, &_sort          },
		{"apply",           1, &_apply         },
		{"map",             1, &_map           },
		{"min",             0, &_min           },
		{"max",             0, &_max           },
		{"insert",          2, &_insert        },
		{"remove",          2, &_remove        },
		{"pop",             1, &_pop           },
		{"sum",             0, &_sum           },
		{"product",         0, &_product       },
		{"copyRange",       5, &_copyRange     },
		{"fill",            1, &_fill          },
		{"fillRange",       3, &_fillRange     },
		{"opEquals",        1, &_opEquals      },
		{"opCmp",           1, &_opCmp         },
		{"opLength",        0, &_opLength      },
		{"opLengthAssign",  1, &_opLengthAssign},
		{"opIndex",         1, &_opIndex       },
		{"opIndexAssign",   2, &_opIndexAssign },
		{"opSlice",         2, &_opSlice       },
		{"opSerialize",     2, &_opSerialize   },
		{"opDeserialize",   2, &_opDeserialize },
		{"opCat",           1, &_opCat         },
		{"opCat_r",         1, &_opCat_r       },
		{"opCatAssign",    -1, &_opCatAssign   },
		{"add",             1, &_add           },
		{"sub",             1, &_sub           },
		{"mul",             1, &_mul           },
		{"div",             1, &_div           },
		{"mod",             1, &_mod           },
		{"addeq",           1, &_addeq         },
		{"subeq",           1, &_subeq         },
		{"muleq",           1, &_muleq         },
		{"diveq",           1, &_diveq         },
		{"modeq",           1, &_modeq         },
		{"revsub",          1, &_revsub        },
		{"revdiv",          1, &_revdiv        },
		{"revmod",          1, &_revmod        },
		{"revsubeq",        1, &_revsubeq      },
		{"revdiveq",        1, &_revdiveq      },
		{"revmodeq",        1, &_revmodeq      },
		{nullptr, 0, nullptr}
	};
	}

	void initMiscLib_Vector(CrocThread* t)
	{
		croc_class_new(t, "Vector", 0);
			croc_pushNull(t);   croc_class_addHField(t, -2, Data);
			croc_pushInt(t, 0); croc_class_addHField(t, -2, Kind);

			croc_ex_registerMethods(t, _methods);

				croc_function_new(t, "iterator",        1, &_iterator,        0);
				croc_function_new(t, "iteratorReverse", 1, &_iteratorReverse, 0);
			croc_function_new(t, "opApply", 1, &_opApply, 2);
			croc_class_addMethod(t, -2, "opApply");

			croc_field(t, -1, "fillRange");   croc_class_addMethod(t, -2, "opSliceAssign");
			croc_field(t, -1, "opCatAssign"); croc_class_addMethod(t, -2, "append");
		croc_newGlobal(t, "Vector");
	}
}