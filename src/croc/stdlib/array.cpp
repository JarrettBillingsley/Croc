
#include <functional>
#include <limits>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"
#include "croc/util/array.hpp"

namespace croc
{
	namespace
	{
#define checkArrayParam(t, n) (croc_ex_checkParam((t), (n), CrocType_Array), getArray(Thread::from(t), (n)))

	word_t _new(CrocThread* t)
	{
		auto length = croc_ex_checkIntParam(t, 1);
		auto haveFill = croc_isValidIndex(t, 2);

		if(length < 0 || length > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid length: %" CROC_INTEGER_FORMAT, length);

		croc_array_new(t, cast(uword)length);

		if(haveFill)
		{
			croc_dup(t, 2);
			croc_array_fill(t, -2);
		}

		return 1;
	}

	word_t _new2D(CrocThread* t)
	{
		auto length1 = croc_ex_checkIntParam(t, 1);
		auto length2 = croc_ex_checkIntParam(t, 2);
		auto haveFill = croc_isValidIndex(t, 3);

		if(length1 <= 0 || length1 > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid first dimension length: %" CROC_INTEGER_FORMAT, length1);

		if(length2 < 0 || length2 > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid second dimension length: %" CROC_INTEGER_FORMAT, length2);

		croc_array_new(t, cast(uword)length1);

		if(haveFill)
		{
			for(uword i = 0; i < length1; i++)
			{
				croc_array_new(t, cast(uword)length2);
				croc_dup(t, 3);
				croc_array_fill(t, -2);
				croc_idxai(t, -2, i);
			}
		}
		else
		{
			for(uword i = 0; i < length1; i++)
			{
				croc_array_new(t, cast(uword)length2);
				croc_idxai(t, -2, i);
			}
		}

		return 1;
	}

	word_t _new3D(CrocThread* t)
	{
		auto length1 = croc_ex_checkIntParam(t, 1);
		auto length2 = croc_ex_checkIntParam(t, 2);
		auto length3 = croc_ex_checkIntParam(t, 3);
		auto haveFill = croc_isValidIndex(t, 4);

		if(length1 <= 0 || length1 > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid first dimension length: %" CROC_INTEGER_FORMAT, length1);

		if(length2 <= 0 || length2 > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid second dimension length: %" CROC_INTEGER_FORMAT, length2);

		if(length3 < 0 || length3 > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid third dimension length: %" CROC_INTEGER_FORMAT, length3);

		croc_array_new(t, cast(uword)length1);

		if(haveFill)
		{
			for(uword i = 0; i < length1; i++)
			{
				croc_array_new(t, cast(uword)length2);

				for(uword j = 0; j < length2; j++)
				{
					croc_array_new(t, cast(uword)length3);
					croc_dup(t, 4);
					croc_array_fill(t, -2);
					croc_idxai(t, -2, j);
				}

				croc_idxai(t, -2, i);
			}
		}
		else
		{
			for(uword i = 0; i < length1; i++)
			{
				croc_array_new(t, cast(uword)length2);

				for(uword j = 0; j < length2; j++)
				{
					croc_array_new(t, cast(uword)length3);
					croc_idxai(t, -2, j);
				}

				croc_idxai(t, -2, i);
			}
		}

		return 1;
	}

	word_t _range(CrocThread* t)
	{
		auto v1 = croc_ex_checkIntParam(t, 1);
		crocint v2;
		crocint step = 1;

		switch(croc_getStackSize(t) - 1)
		{
			case 1: v2 = v1; v1 = 0; break;
			case 2: v2 = croc_ex_checkIntParam(t, 2); break;
			default:
				v2 = croc_ex_checkIntParam(t, 2);
				step = croc_ex_checkIntParam(t, 3);
		}

		if(step <= 0)
			croc_eh_throwStd(t, "RangeError", "Step may not be negative or 0");

		crocint range = abs(v2 - v1);
		crocint size = range / step;

		if((range % step) != 0)
			size++;

		if(size > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Array is too big");

		croc_array_new(t, cast(uword)size);
		auto data = getArray(Thread::from(t), -1)->toDArray();
		auto val = v1;

		// no write barrier here. the array is new and we're filling it with scalars.

		if(v2 < v1)
		{
			for(uword i = 0; val > v2; i++, val -= step)
				data[i].value = Value::from(val);
		}
		else
		{
			for(uword i = 0; val < v2; i++, val += step)
				data[i].value = Value::from(val);
		}

		return 1;
	}

	word_t _opEquals(CrocThread* t)
	{
		auto a = checkArrayParam(t, 0)->toDArray();
		auto b = checkArrayParam(t, 1)->toDArray();
		croc_pushBool(t, a == b);
		return 1;
	}

	word_t _sort(CrocThread* t)
	{
		auto arr = checkArrayParam(t, 0);

		std::function<bool(Array::Slot, Array::Slot)> pred;

		auto t_ = Thread::from(t);

		if(croc_isValidIndex(t, 1))
		{
			if(croc_isString(t, 1))
			{
				if(strcmp(croc_getString(t, 1), "reverse") == 0)
				{
					pred = [&](Array::Slot v1, Array::Slot v2)
					{
						push(t_, v1.value);
						push(t_, v2.value);
						auto v = croc_cmp(t, -2, -1);
						croc_pop(t, 2);
						return v < 0;
					};
				}
				else
					croc_eh_throwStd(t, "ValueError", "Unknown array sorting method");
			}
			else
			{
				croc_ex_checkParam(t, 1, CrocType_Function);
				croc_dupTop(t);

				pred = [&](Array::Slot v1, Array::Slot v2)
				{
					auto reg = croc_dupTop(t);
					croc_pushNull(t);
					push(t_, v1.value);
					push(t_, v2.value);
					croc_call(t, reg, 1);

					if(!croc_isInt(t, -1))
					{
						croc_pushTypeString(t, -1);
						croc_eh_throwStd(t, "TypeError", "comparison function expected to return 'int', not '%s'",
							croc_getString(t, -1));
					}

					auto v = croc_getInt(t, -1);
					croc_popTop(t);
					return v >= 0;
				};
			}
		}
		else
		{
			pred = [&](Array::Slot v1, Array::Slot v2)
			{
				push(t_, v1.value);
				push(t_, v2.value);
				auto v = croc_cmp(t, -2, -1);
				croc_pop(t, 2);
				return v >= 0;
			};
		}

		// No write barrier. we're just moving items around, the items themselves don't change.
		arrSort(arr->toDArray(), pred);
		croc_dup(t, 0);
		return 1;
	}

	word_t _reverse(CrocThread* t)
	{
		auto arr = checkArrayParam(t, 0)->toDArray();
		// No write barrier. Just moving items around.
		arrReverse(arr);
		croc_dup(t, 0);
		return 1;
	}

	word_t _dup(CrocThread* t)
	{
		auto src = checkArrayParam(t, 0);
		croc_array_new(t, cast(uword)croc_len(t, 0));
		auto t_ = Thread::from(t);
		auto dest = getArray(t_, -1);
		dest->sliceAssign(t_->vm->mem, 0, dest->length, src);
		return 1;
	}

	word_t _expand(CrocThread* t)
	{
		auto arr = checkArrayParam(t, 0)->toDArray();

		if(arr.length > 50)
			croc_eh_throwStd(t, "ValueError", "Array too large to expand (more than 50 elements)");

		auto t_ = Thread::from(t);

		for(auto &val: arr)
			push(t_, val.value);

		return arr.length;
	}

	word_t _toString(CrocThread* t)
	{
		CrocStrBuffer buf;
		croc_ex_buffer_init(t, &buf);
		croc_ex_buffer_addChar(&buf, '[');
		auto length = croc_len(t, 0);

		for(uword i = 0; i < length; i++)
		{
			croc_idxi(t, 0, i);

			if(croc_isString(t, -1))
			{
				// this is GC-safe since the string is stored in the array
				uword n;
				auto s = croc_getStringn(t, -1, &n);
				croc_popTop(t);
				croc_ex_buffer_addChar(&buf, '"');
				croc_ex_buffer_addStringn(&buf, s, n);
				croc_ex_buffer_addChar(&buf, '"');
			}
			else
			{
				croc_pushToStringRaw(t, -1);
				croc_insertAndPop(t, -2);
				croc_ex_buffer_addTop(&buf);
			}

			if(i < length - 1)
				croc_ex_buffer_addString(&buf, ", ");
		}

		croc_ex_buffer_addChar(&buf, ']');
		croc_ex_buffer_finish(&buf);
		return 1;
	}

	word_t _apply(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);

		auto t_ = Thread::from(t);
		uword i = 0;
		for(auto &v: data)
		{
			auto reg = croc_dup(t, 1);
			croc_dup(t, 0);
			push(t_, v.value);
			croc_call(t, reg, 1);
			croc_idxai(t, 0, i++);
		}

		croc_dup(t, 0);
		return 1;
	}

	word_t _map(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);
		auto newArr = croc_array_new(t, cast(uword)croc_len(t, 0));

		auto t_ = Thread::from(t);
		uword i = 0;
		for(auto &v: data)
		{
			auto reg = croc_dup(t, 1);
			croc_dup(t, 0);
			push(t_, v.value);
			croc_call(t, reg, 1);
			croc_idxai(t, newArr, i);
		}

		return 1;
	}

	word_t _reduce(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);
		auto haveInitial = croc_isValidIndex(t, 2);

		if(data.length == 0)
		{
			if(!haveInitial)
				croc_eh_throwStd(t, "ParamError", "Attempting to reduce an empty array without an initial value");
			else
			{
				croc_dup(t, 2);
				return 1;
			}
		}

		uword start = 0;
		auto t_ = Thread::from(t);

		if(!haveInitial)
		{
			push(t_, data[0].value);
			start = 1;
		}
		else
			croc_dup(t, 2);

		for(auto &v: data.slice(start, data.length))
		{
			croc_dup(t, 1);
			croc_pushNull(t);
			croc_dup(t, -3);
			push(t_, v.value);
			croc_call(t, -4, 1);
			croc_insertAndPop(t, -2);
		}

		return 1;
	}

	word_t _rreduce(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);
		auto haveInitial = croc_isValidIndex(t, 2);

		if(data.length == 0)
		{
			if(!haveInitial)
				croc_eh_throwStd(t, "ParamError", "Attempting to reduce an empty array without an initial value");
			else
			{
				croc_dup(t, 2);
				return 1;
			}
		}

		uword start = data.length;
		auto t_ = Thread::from(t);

		if(!haveInitial)
		{
			start--;
			push(t_, data[start].value);
		}
		else
			croc_dup(t, 2);

		for(auto &v: data.slice(0, start).reverse())
		{
			croc_dup(t, 1);
			croc_pushNull(t);
			push(t_, v.value);
			croc_dup(t, -4);
			croc_call(t, -4, 1);
			croc_insertAndPop(t, -2);
		}

		return 1;
	}

	word_t _filter(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);

		auto newLen = data.length / 2;
		auto retArray = croc_array_new(t, cast(uword)newLen);
		uword retIdx = 0;
		auto t_ = Thread::from(t);
		uword i = 0;

		for(auto &v: data)
		{
			croc_dup(t, 1);
			croc_dup(t, 0);
			croc_pushInt(t, i++);
			push(t_, v.value);
			croc_call(t, -4, 1);

			if(!croc_isBool(t, -1))
			{
				croc_pushTypeString(t, -1);
				croc_eh_throwStd(t, "TypeError", "filter function expected to return 'bool', not '%s'",
					croc_getString(t, -1));
			}

			if(croc_getBool(t, -1))
			{
				if(retIdx >= newLen)
				{
					newLen += 10;
					croc_pushInt(t, newLen);
					croc_lena(t, retArray);
				}

				push(t_, v.value);
				croc_idxai(t, retArray, retIdx++);
			}

			croc_popTop(t);
		}

		croc_pushInt(t, retIdx);
		croc_lena(t, retArray);
		croc_dup(t, retArray);
		return 1;
	}

	word_t _find(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->data;
		croc_ex_checkAnyParam(t, 1);
		auto searchedType = croc_type(t, 1);

		auto t_ = Thread::from(t);
		uword i = 0;

		for(auto &v: data)
		{
			if(searchedType == v.value.type)
			{
				push(t_, v.value);

				if(croc_cmp(t, 1, -1) == 0)
				{
					croc_pushInt(t, i);
					return 1;
				}

				croc_popTop(t);
			}

			i++;
		}

		croc_pushLen(t, 0);
		return 1;
	}

	word_t _findIf(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->data;
		croc_ex_checkParam(t, 1, CrocType_Function);
		auto t_ = Thread::from(t);
		uword i = 0;

		for(auto &v: data)
		{
			auto reg = croc_dup(t, 1);
			croc_pushNull(t);
			push(t_, v.value);
			croc_call(t, reg, 1);

			if(!croc_isBool(t, -1))
			{
				croc_pushTypeString(t, -1);
				croc_eh_throwStd(t, "TypeError", "find function expected to return 'bool', not '%s'",
					croc_getString(t, -1));
			}

			if(croc_getBool(t, -1))
			{
				croc_pushInt(t, i);
				return 1;
			}

			croc_popTop(t);
			i++;
		}

		croc_pushLen(t, 0);
		return 1;
	}

	word_t _bsearch(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->data;
		croc_ex_checkAnyParam(t, 1);

		uword lo = 0;
		uword hi = data.length - 1;
		auto t_ = Thread::from(t);

		while((hi - lo) > 8)
		{
			uword mid = (lo + hi) >> 1;
			push(t_, data[mid].value);
			auto cmp = croc_cmp(t, 1, -1);
			croc_popTop(t);

			if(cmp == 0)
			{
				croc_pushInt(t, mid);
				return 1;
			}
			else if(cmp < 0)
				hi = mid - 1;
			else
				lo = mid + 1;
		}

		for(uword i = lo; i <= hi; i++)
		{
			push(t_, data[i].value);

			if(croc_cmp(t, 1, -1) == 0)
			{
				croc_pushInt(t, i);
				return 1;
			}

			croc_popTop(t);
		}

		croc_pushLen(t, 0);
		return 1;
	}

	word_t _pop(CrocThread* t)
	{
		auto arr = checkArrayParam(t, 0);
		auto data = arr->data;
		crocint index = croc_ex_optIntParam(t, 1, -1);

		if(data.length == 0)
			croc_eh_throwStd(t, "ValueError", "Array is empty");

		if(index < 0)
			index += data.length;

		if(index < 0 || index >= data.length)
			croc_eh_throwStd(t, "BoundsError", "Invalid array index: %" CROC_INTEGER_FORMAT, index);

		auto t_ = Thread::from(t);
		push(t_, data[index].value);
		arr->idxa(t_->vm->mem, index, Value::nullValue); // to trigger write barrier

		for(uword i = cast(uword)index; i < data.length - 1; i++)
			data[i] = data[i + 1];

		data[data.length - 1].value = Value::nullValue; // to NOT trigger write barrier ;P
		arr->resize(t_->vm->mem, data.length - 1);
		return 1;
	}

	word_t _insert(CrocThread* t)
	{
		auto arr = checkArrayParam(t, 0);
		auto data = arr->toDArray();
		crocint index = croc_ex_checkIntParam(t, 1);
		croc_ex_checkAnyParam(t, 2);

		if(index < 0)
			index += data.length;

		if(index < 0 || index > data.length)
			croc_eh_throwStd(t, "BoundsError", "Invalid array index: %" CROC_INTEGER_FORMAT, index);

		arr->resize(Thread::from(t)->vm->mem, data.length + 1);
		data = arr->toDArray(); // might have been invalidated

		for(uword i = data.length - 1; i > index; i--)
			data[i] = data[i - 1];

		croc_dup(t, 2);
		croc_idxai(t, 0, index);
		croc_dup(t, 0);
		return 1;
	}

	word_t _swap(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		crocint idx1 = croc_ex_checkIntParam(t, 1);
		crocint idx2 = croc_ex_checkIntParam(t, 2);

		if(idx1 < 0) idx1 += data.length;
		if(idx2 < 0) idx2 += data.length;

		if(idx1 < 0 || idx1 >= data.length)
			croc_eh_throwStd(t, "BoundsError", "Invalid array index: %" CROC_INTEGER_FORMAT, idx1);

		if(idx2 < 0 || idx2 >= data.length)
			croc_eh_throwStd(t, "BoundsError", "Invalid array index: %" CROC_INTEGER_FORMAT, idx2);

		if(idx1 != idx2)
		{
			auto tmp = data[cast(uword)idx1];
			data[cast(uword)idx1] = data[cast(uword)idx2];
			data[cast(uword)idx2] = tmp;
		}

		croc_dup(t, 0);
		return 1;
	}

	word_t _set(CrocThread* t)
	{
		auto numParams = croc_getStackSize(t) - 1;
		auto arr = checkArrayParam(t, 0);
		auto t_ = Thread::from(t);
		arr->resize(t_->vm->mem, numParams);
		arr->sliceAssign(t_->vm->mem, 0, numParams, t_->stack.slice(t_->stackIndex - numParams, t_->stackIndex));
		croc_dup(t, 0);
		return 1;
	}

	word_t _min(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->toDArray();

		if(data.length == 0)
			croc_eh_throwStd(t, "ValueError", "Array is empty");

		uword extremeIdx = 0;
		auto t_ = Thread::from(t);
		push(t_, data[0].value);

		for(uword i = 1; i < data.length; i++)
		{
			push(t_, data[i].value);

			if(croc_cmp(t, -1, -2) < 0)
			{
				extremeIdx = i;
				croc_insert(t, -2);
			}

			croc_popTop(t);
		}

		croc_pushInt(t, extremeIdx);
		return 2;
	}

	word_t _max(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->toDArray();

		if(data.length == 0)
			croc_eh_throwStd(t, "ValueError", "Array is empty");

		uword extremeIdx = 0;
		auto t_ = Thread::from(t);
		push(t_, data[0].value);

		for(uword i = 1; i < data.length; i++)
		{
			push(t_, data[i].value);

			if(croc_cmp(t, -1, -2) > 0)
			{
				extremeIdx = i;
				croc_insert(t, -2);
			}

			croc_popTop(t);
		}

		croc_pushInt(t, extremeIdx);
		return 2;
	}

	word_t _extreme(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);

		if(data.length == 0)
			croc_eh_throwStd(t, "ValueError", "Array is empty");

		uword extremeIdx = 0;
		auto extreme = data[0].value;
		auto t_ = Thread::from(t);

		for(uword i = 1; i < data.length; i++)
		{
			croc_dup(t, 1);
			croc_pushNull(t);
			push(t_, data[i].value);
			push(t_, extreme);
			croc_call(t, -4, 1);

			if(!croc_isBool(t, -1))
			{
				croc_pushTypeString(t, -1);
				croc_eh_throwStd(t, "TypeError", "extrema function should return 'bool', not '%s'",
					croc_getString(t, -1));
			}

			if(croc_getBool(t, -1))
			{
				extreme = data[i].value;
				extremeIdx = i;
			}

			croc_popTop(t);
		}

		push(t_, extreme);
		croc_pushInt(t, extremeIdx);
		return 2;
	}

	word_t _any(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->toDArray();

		if(croc_ex_optParam(t, 1, CrocType_Function))
		{
			auto t_ = Thread::from(t);

			for(auto &v: data)
			{
				croc_dup(t, 1);
				croc_pushNull(t);
				push(t_, v.value);
				croc_call(t, -3, 1);

				if(croc_isTrue(t, -1))
				{
					croc_pushBool(t, true);
					return 1;
				}

				croc_popTop(t);
			}
		}
		else
		{
			for(auto &v: data)
			{
				if(!v.value.isFalse())
				{
					croc_pushBool(t, true);
					return 1;
				}
			}
		}

		croc_pushBool(t, false);
		return 1;
	}

	word_t _all(CrocThread* t)
	{
		auto data = checkArrayParam(t, 0)->toDArray();

		if(croc_ex_optParam(t, 1, CrocType_Function))
		{
			auto t_ = Thread::from(t);

			for(auto &v: data)
			{
				croc_dup(t, 1);
				croc_pushNull(t);
				push(t_, v.value);
				croc_call(t, -3, 1);

				if(!croc_isTrue(t, -1))
				{
					croc_pushBool(t, false);
					return 1;
				}

				croc_popTop(t);
			}
		}
		else
		{
			for(auto &v: data)
			{
				if(v.value.isFalse())
				{
					croc_pushBool(t, false);
					return 1;
				}
			}
		}

		croc_pushBool(t, true);
		return 1;
	}

	word_t _fill(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Array);
		croc_ex_checkAnyParam(t, 1);
		croc_dup(t, 1);
		croc_array_fill(t, 0);
		return 0;
	}

	word_t _append(CrocThread* t)
	{
		auto arr = checkArrayParam(t, 0);
		auto numParams = croc_getStackSize(t) - 1;

		if(numParams == 0)
			return 0;

		auto oldlen = arr->length;
		auto t_ = Thread::from(t);
		arr->resize(t_->vm->mem, arr->length + numParams);
		arr->sliceAssign(t_->vm->mem, oldlen, oldlen + numParams,
			t_->stack.slice(t_->stackIndex - numParams, t_->stackIndex));

		return 0;
	}

	word_t _count(CrocThread* t)
	{
		auto arr = checkArrayParam(t, 0)->data;
		croc_ex_checkAnyParam(t, 1);
		auto t_ = Thread::from(t);
		auto searched = *getValue(t_, 1);
		uword count = 0;

		if(croc_ex_optParam(t, 2, CrocType_Function))
		{
			for(auto &val: arr)
			{
				auto reg = croc_dup(t, 2);
				croc_pushNull(t);
				push(t_, val.value);
				push(t_, searched);
				croc_call(t, reg, 1);

				if(!croc_isBool(t, -1))
				{
					croc_pushTypeString(t, -1);
					croc_eh_throwStd(t, "TypeError", "count predicate expected to return 'bool', not '%s'",
						croc_getString(t, -1));
				}

				if(croc_getBool(t, -1))
					count++;

				croc_popTop(t);
			}
		}
		else
		{
			for(auto &val: arr)
			{
				push(t_, val.value);
				push(t_, searched);

				if(croc_cmp(t, -2, -1) == 0)
					count++;

				croc_pop(t, 2);
			}
		}

		croc_pushInt(t, count);
		return 1;
	}

	word_t _countIf(CrocThread* t)
	{
		auto arr = checkArrayParam(t, 0)->data;
		croc_ex_checkParam(t, 1, CrocType_Function);
		uword count = 0;
		auto t_ = Thread::from(t);

		for(auto &val: arr)
		{
			auto reg = croc_dup(t, 1);
			croc_pushNull(t);
			push(t_, val.value);
			croc_call(t, reg, 1);

			if(!croc_isBool(t, -1))
			{
				croc_pushTypeString(t, -1);
				croc_eh_throwStd(t, "TypeError", "count predicate expected to return 'bool', not '%s'",
					croc_getString(t, -1));
			}

			if(croc_getBool(t, -1))
				count++;

			croc_popTop(t);
		}

		croc_pushInt(t, count);
		return 1;
	}

	word_t _iterator(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Array);
		auto index = croc_ex_checkIntParam(t, 1) + 1;

		if(index >= croc_len(t, 0))
			return 0;

		croc_pushInt(t, index);
		croc_dupTop(t);
		croc_idx(t, 0);
		return 2;
	}

	word_t _iteratorReverse(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Array);
		auto index = croc_ex_checkIntParam(t, 1) - 1;

		if(index < 0)
			return 0;

		croc_pushInt(t, index);
		croc_dupTop(t);
		croc_idx(t, 0);
		return 2;
	}

	word_t _opApply(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Array);

		if(strcmp(croc_ex_optStringParam(t, 1, ""), "reverse") == 0)
		{
			croc_pushUpval(t, 1);
			croc_dup(t, 0);
			croc_pushLen(t, 0);
		}
		else
		{
			croc_pushUpval(t, 0);
			croc_dup(t, 0);
			croc_pushInt(t, -1);
		}

		return 3;
	}

	word_t _flatten(CrocThread* t)
	{
		croc_ex_checkParam(t, 0, CrocType_Array);
		auto flattening = croc_pushUpval(t, 0);
		auto ret = croc_array_new(t, 0);

		std::function<void(word)> flatten = [&](word arr)
		{
			auto a = croc_absIndex(t, arr);

			if(croc_in(t, a, flattening))
			{
				croc_table_clear(t, flattening);
				croc_eh_throwStd(t, "ValueError", "Attempting to flatten a self-referencing array");
			}

			croc_dup(t, a);
			croc_pushBool(t, true);
			croc_idxa(t, flattening);
			auto t_ = Thread::from(t);

			for(auto &val: getArray(t_, a)->toDArray())
			{
				if(val.value.type == CrocType_Array)
					flatten(push(t_, Value::from(val.value.mArray)));
				else
				{
					push(t_, val.value);
					croc_cateq(t, ret, 1);
				}
			}

			croc_dup(t, a);
			croc_pushNull(t);
			croc_idxa(t, flattening);
		};

		croc_table_clear(t, flattening);
		flatten(0);
		croc_dup(t, ret);
		return 1;
	}

	const CrocRegisterFunc _globalFuncs[] =
	{
		{"new",   2, &_new  },
		{"new2D", 3, &_new2D},
		{"new3D", 4, &_new3D},
		{"range", 3, &_range},
		{nullptr, 0, nullptr}
	};

	const CrocRegisterFunc _methodFuncs[] =
	{
		{"opEquals",  1, &_opEquals},
		{"sort",      1, &_sort    },
		{"reverse",   0, &_reverse },
		{"dup",       0, &_dup     },
		{"expand",    0, &_expand  },
		{"toString",  0, &_toString},
		{"apply",     1, &_apply   },
		{"map",       1, &_map     },
		{"reduce",    2, &_reduce  },
		{"rreduce",   2, &_rreduce },
		{"filter",    1, &_filter  },
		{"find",      1, &_find    },
		{"findIf",    1, &_findIf  },
		{"bsearch",   1, &_bsearch },
		{"pop",       1, &_pop     },
		{"insert",    2, &_insert  },
		{"swap",      2, &_swap    },
		{"set",      -1, &_set     },
		{"min",       0, &_min     },
		{"max",       0, &_max     },
		{"extreme",   1, &_extreme },
		{"any",       1, &_any     },
		{"all",       1, &_all     },
		{"fill",      1, &_fill    },
		{"append",   -1, &_append  },
		{"count",     2, &_count   },
		{"countIf",   1, &_countIf },
		{nullptr, 0, nullptr}
	};

	word loader(CrocThread* t)
	{
		croc_ex_registerGlobals(t, _globalFuncs);

		croc_namespace_new(t, "array");
			croc_ex_registerFields(t, _methodFuncs);

				croc_function_new(t, "iterator", 1, &_iterator, 0);
				croc_function_new(t, "iteratorReverse", 1, &_iteratorReverse, 0);
			croc_function_new(t, "opApply", 1, &_opApply, 2);
			croc_fielda(t, -2, "opApply");

				croc_table_new(t, 0);
			croc_function_new(t, "flatten", 0, &_flatten, 1);
			croc_fielda(t, -2, "flatten");
		croc_vm_setTypeMT(t, CrocType_Array);
		return 0;
	}
	}

	void initArrayLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "array", &loader);
		croc_ex_importNoNS(t, "array");
	}
}