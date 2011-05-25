/******************************************************************************
This module contains the 'array' standard library.

License:
Copyright (c) 2008 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module minid.stdlib_array;

import tango.core.Array;
import tango.core.Tuple;
import tango.math.Math;

import minid.ex;
import minid.interpreter;
import minid.stackmanip;
import minid.types;
import minid.types_array;

struct ArrayLib
{
static:
	public void init(MDThread* t)
	{
		makeModule(t, "array", function uword(MDThread* t)
		{
			newFunction(t, 2, &array_new, "new");     newGlobal(t, "new");
			newFunction(t, 3, &range,     "range");   newGlobal(t, "range");

			newNamespace(t, "array");
				newFunction(t, 1, &sort,      "sort");       fielda(t, -2, "sort");
				newFunction(t, 0, &reverse,   "reverse");    fielda(t, -2, "reverse");
				newFunction(t, 0, &array_dup, "dup");        fielda(t, -2, "dup");

					newFunction(t, 1, &iterator,        "iterator");
					newFunction(t, 1, &iteratorReverse, "iteratorReverse");
				newFunction(t, 1, &opApply,   "opApply", 2); fielda(t, -2, "opApply");

				newFunction(t, 0, &expand,    "expand");     fielda(t, -2, "expand");
				newFunction(t, 0, &toString,  "toString");   fielda(t, -2, "toString");
				newFunction(t, 1, &apply,     "apply");      fielda(t, -2, "apply");
				newFunction(t, 1, &map,       "map");        fielda(t, -2, "map");
				newFunction(t, 2, &reduce,    "reduce");     fielda(t, -2, "reduce");
				newFunction(t, 1, &each,      "each");       fielda(t, -2, "each");
				newFunction(t, 1, &filter,    "filter");     fielda(t, -2, "filter");
				newFunction(t, 1, &find,      "find");       fielda(t, -2, "find");
				newFunction(t, 1, &findIf,    "findIf");     fielda(t, -2, "findIf");
				newFunction(t, 1, &bsearch,   "bsearch");    fielda(t, -2, "bsearch");
				newFunction(t, 1, &array_pop, "pop");        fielda(t, -2, "pop");
				newFunction(t, &set,       "set");        fielda(t, -2, "set");
				newFunction(t, 0, &min,       "min");        fielda(t, -2, "min");
				newFunction(t, 0, &max,       "max");        fielda(t, -2, "max");
				newFunction(t, 1, &extreme,   "extreme");    fielda(t, -2, "extreme");
				newFunction(t, 1, &any,       "any");        fielda(t, -2, "any");
				newFunction(t, 1, &all,       "all");        fielda(t, -2, "all");
				newFunction(t, 1, &fill,      "fill");       fielda(t, -2, "fill");
				newFunction(t, &append,    "append");     fielda(t, -2, "append");

					newTable(t);
				newFunction(t, 0, &flatten,   "flatten", 1); fielda(t, -2, "flatten");

				newFunction(t, 0, &makeHeap,  "makeHeap");   fielda(t, -2, "makeHeap");
// 				newFunction(t, 1, &pushHeap,  "pushHeap");   fielda(t, -2, "pushHeap");
// 				newFunction(t, 0, &popHeap,   "popHeap");    fielda(t, -2, "popHeap");
				newFunction(t, 0, &sortHeap,  "sortHeap");   fielda(t, -2, "sortHeap");
				newFunction(t, 2, &count,     "count");      fielda(t, -2, "count");
				newFunction(t, 1, &countIf,   "countIf");    fielda(t, -2, "countIf");
			setTypeMT(t, MDValue.Type.Array);

			return 0;
		});

		importModuleNoNS(t, "array");
	}

	uword array_new(MDThread* t)
	{
		auto length = checkIntParam(t, 1);
		auto numParams = stackSize(t) - 1;

		if(length < 0 || length > uword.max)
			throwException(t, "Invalid length: {}", length);

		newArray(t, cast(uword)length);

		if(numParams > 1)
		{
			dup(t, 2);
			fillArray(t, -2);
		}

		return 1;
	}

	uword range(MDThread* t)
	{
		auto v1 = checkIntParam(t, 1);
		auto numParams = stackSize(t) - 1;
		mdint v2;
		mdint step = 1;

		if(numParams == 1)
		{
			v2 = v1;
			v1 = 0;
		}
		else if(numParams == 2)
			v2 = checkIntParam(t, 2);
		else
		{
			v2 = checkIntParam(t, 2);
			step = checkIntParam(t, 3);
		}

		if(step <= 0)
			throwException(t, "Step may not be negative or 0");

		mdint range = abs(v2 - v1);
		mdint size = range / step;

		if((range % step) != 0)
			size++;

		if(size > uword.max)
			throwException(t, "Array is too big");

		newArray(t, cast(uword)size);
		auto a = getArray(t, -1);

		auto val = v1;

		if(v2 < v1)
		{
			for(uword i = 0; val > v2; i++, val -= step)
				a.data[i] = val;
		}
		else
		{
			for(uword i = 0; val < v2; i++, val += step)
				a.data[i] = val;
		}

		return 1;
	}

	uword sort(MDThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 0, MDValue.Type.Array);

		bool delegate(MDValue, MDValue) pred;

		if(numParams > 0)
		{
			if(isString(t, 1))
			{
				if(getString(t, 1) == "reverse")
				{
					pred = (MDValue v1, MDValue v2)
					{
						push(t, v1);
						push(t, v2);
						auto v = cmp(t, -2, -1);
						pop(t, 2);
						return v > 0;
					};
				}
				else
					throwException(t, "Unknown array sorting method");
			}
			else
			{
				checkParam(t, 1, MDValue.Type.Function);
				dup(t);

				pred = (MDValue v1, MDValue v2)
				{
					auto reg = dup(t);
					pushNull(t);
					push(t, v1);
					push(t, v2);
					rawCall(t, reg, 1);

					if(!isInt(t, -1))
					{
						pushTypeString(t, -1);
						throwException(t, "comparison function expected to return 'int', not '{}'", getString(t, -1));
					}

					auto v = getInt(t, -1);
					pop(t);
					return v < 0;
				};
			}
		}
		else
		{
			pred = (MDValue v1, MDValue v2)
			{
				push(t, v1);
				push(t, v2);
				auto v = cmp(t, -2, -1);
				pop(t, 2);
				return v < 0;
			};
		}

		.sort(getArray(t, 0).toArray(), pred);
		dup(t, 0);
		return 1;
	}

	uword reverse(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		getArray(t, 0).toArray().reverse;
		dup(t, 0);
		return 1;
	}

	uword array_dup(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		newArray(t, cast(uword)len(t, 0)); // this should be fine?  since arrays can't be longer than uword.max
		getArray(t, -1).toArray()[] = getArray(t, 0).toArray()[];
		return 1;
	}

	uword iterator(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		auto index = checkIntParam(t, 1) + 1;

		if(index >= len(t, 0))
			return 0;

		pushInt(t, index);
		dup(t);
		idx(t, 0);

		return 2;
	}

	uword iteratorReverse(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		auto index = checkIntParam(t, 1) - 1;

		if(index < 0)
			return 0;

		pushInt(t, index);
		dup(t);
		idx(t, 0);

		return 2;
	}

	uword opApply(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);

		if(optStringParam(t, 1, "") == "reverse")
		{
			getUpval(t, 1);
			dup(t, 0);
			pushLen(t, 0);
		}
		else
		{
			getUpval(t, 0);
			dup(t, 0);
			pushInt(t, -1);
		}

		return 3;
	}

	uword expand(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		auto a = getArray(t, 0);

		foreach(ref val; a.toArray())
			push(t, val);

		return a.length;
	}

	uword toString(MDThread* t)
	{
		auto buf = StrBuffer(t);
		buf.addChar('[');

		auto length = len(t, 0);

		for(uword i = 0; i < length; i++)
		{
			pushInt(t, i);
			idx(t, 0);

			if(isString(t, -1))
			{
				// this is GC-safe since the string is stored in the array
				auto s = getString(t, -1);
				pop(t);
				buf.addChar('"');
				buf.addString(s);
				buf.addChar('"');
			}
			else if(isChar(t, -1))
			{
				auto c = getChar(t, -1);
				pop(t);
				buf.addChar('\'');
				buf.addChar(c);
				buf.addChar('\'');
			}
			else
			{
				pushToString(t, -1, true);
				insertAndPop(t, -2);
				buf.addTop();
			}

			if(i < length - 1)
				buf.addString(", ");
		}

		buf.addChar(']');
		buf.finish();

		return 1;
	}

	uword apply(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		checkParam(t, 1, MDValue.Type.Function);

		auto data = getArray(t, 0).toArray();

		foreach(i, ref v; data)
		{
			auto reg = dup(t, 1);
			dup(t, 0);
			push(t, v);
			rawCall(t, reg, 1);
			idxai(t, 0, i);
		}

		dup(t, 0);
		return 1;
	}

	uword map(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		checkParam(t, 1, MDValue.Type.Function);
		auto newArr = newArray(t, cast(uword)len(t, 0));
		auto data = getArray(t, -1).toArray();

		foreach(i, ref v; getArray(t, 0).toArray())
		{
			auto reg = dup(t, 1);
			dup(t, 0);
			push(t, v);
			rawCall(t, reg, 1);
			idxai(t, newArr, i);
		}

		return 1;
	}

	uword reduce(MDThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 0, MDValue.Type.Array);
		checkParam(t, 1, MDValue.Type.Function);

		uword length = cast(uword)len(t, 0);

		if(length == 0)
		{
			if(numParams == 1)
				throwException(t, "Attempting to reduce an empty array without an initial value");
			else
			{
				dup(t, 2);
				return 1;
			}
		}

		uword start = 0;

		if(numParams == 1)
		{
			idxi(t, 0, 0);
			start = 1;
		}
		else
			dup(t, 2);

		for(uword i = start; i < length; i++)
		{
			dup(t, 1);
			swap(t);
			pushNull(t);
			swap(t);
			idxi(t, 0, i);
			rawCall(t, -4, 1);
		}

		return 1;
	}

	uword each(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		checkParam(t, 1, MDValue.Type.Function);

		foreach(i, ref v; getArray(t, 0).toArray())
		{
			dup(t, 1);
			dup(t, 0);
			pushInt(t, i);
			push(t, v);
			rawCall(t, -4, 1);

			if(isBool(t, -1) && getBool(t, -1) == false)
				break;
		}

		dup(t, 0);
		return 1;
	}

	uword filter(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		checkParam(t, 1, MDValue.Type.Function);

		auto newLen = len(t, 0) / 2;
		auto retArray = newArray(t, cast(uword)newLen);
		uword retIdx = 0;

		foreach(i, ref v; getArray(t, 0).toArray())
		{
			dup(t, 1);
			dup(t, 0);
			pushInt(t, i);
			push(t, v);
			rawCall(t, -4, 1);

			if(!isBool(t, -1))
			{
				pushTypeString(t, -1);
				throwException(t, "filter function expected to return 'bool', not '{}'", getString(t, -1));
			}

			if(getBool(t, -1))
			{
				if(retIdx >= newLen)
				{
					newLen += 10;
					pushInt(t, newLen);
					lena(t, retArray);
				}

				push(t, v);
				idxai(t, retArray, retIdx);
				retIdx++;
			}

			pop(t);
		}

		pushInt(t, retIdx);
		lena(t, retArray);
		dup(t, retArray);
		return 1;
	}

	uword find(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		checkAnyParam(t, 1);

		foreach(i, ref v; getArray(t, 0).toArray())
		{
			push(t, v);

			if(type(t, 1) == v.type && cmp(t, 1, -1) == 0)
			{
				pushInt(t, i);
				return 1;
			}
		}

		pushLen(t, 0);
		return 1;
	}

	uword findIf(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		checkParam(t, 1, MDValue.Type.Function);

		foreach(i, ref v; getArray(t, 0).toArray())
		{
			auto reg = dup(t, 1);
			pushNull(t);
			push(t, v);
			rawCall(t, reg, 1);

			if(!isBool(t, -1))
			{
				pushTypeString(t, -1);
				throwException(t, "find function expected to return 'bool', not '{}'", getString(t, -1));
			}

			if(getBool(t, -1))
			{
				pushInt(t, i);
				return 1;
			}

			pop(t);
		}

		pushLen(t, 0);
		return 1;
	}

	uword bsearch(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		checkAnyParam(t, 1);

		uword lo = 0;
		uword hi = cast(uword)len(t, 0) - 1;
		uword mid = (lo + hi) >> 1;

		while((hi - lo) > 8)
		{
			idxi(t, 0, mid);
			auto cmp = cmp(t, 1, -1);
			pop(t);

			if(cmp == 0)
			{
				pushInt(t, mid);
				return 1;
			}
			else if(cmp < 0)
				hi = mid;
			else
				lo = mid;

			mid = (lo + hi) >> 1;
		}

		for(auto i = lo; i <= hi; i++)
		{
			idxi(t, 0, i);

			if(cmp(t, 1, -1) == 0)
			{
				pushInt(t, i);
				return 1;
			}

			pop(t);
		}

		pushLen(t, 0);
		return 1;
	}

	uword array_pop(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		mdint index = -1;
		auto data = getArray(t, 0).toArray();

		if(data.length == 0)
			throwException(t, "Array is empty");

		if(stackSize(t) > 1)
			index = checkIntParam(t, 1);

		if(index < 0)
			index += data.length;

		if(index < 0 || index >= data.length)
			throwException(t, "Invalid array index: {}", index);

		idxi(t, 0, index);

		for(uword i = cast(uword)index; i < data.length - 1; i++)
			data[i] = data[i + 1];

		array.resize(t.vm.alloc, getArray(t, 0), data.length - 1);
		return 1;
	}

	uword set(MDThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 0, MDValue.Type.Array);
		auto a = getArray(t, 0);

		array.resize(t.vm.alloc, a, numParams);

		for(uword i = 0; i < numParams; i++)
			a.data[i] = *getValue(t, i + 1);

		dup(t, 0);
		return 1;
	}

	uword minMaxImpl(MDThread* t, uword numParams, bool max)
	{
		checkParam(t, 0, MDValue.Type.Array);
		auto data = getArray(t, 0).toArray();

		if(data.length == 0)
			throwException(t, "Array is empty");

		auto extreme = data[0];
		uword extremeIdx = 0;

		if(numParams > 0)
		{
			for(uword i = 1; i < data.length; i++)
			{
				dup(t, 1);
				pushNull(t);
				idxi(t, 0, i);
				push(t, extreme);
				rawCall(t, -4, 1);

				if(!isBool(t, -1))
				{
					pushTypeString(t, -1);
					throwException(t, "extrema function should return 'bool', not '{}'", getString(t, -1));
				}

				if(getBool(t, -1))
				{
					extreme = data[i];
					extremeIdx = i;
				}

				pop(t);
			}

			push(t, extreme);
		}
		else
		{
			idxi(t, 0, 0);

			if(max)
			{
				for(uword i = 1; i < data.length; i++)
				{
					idxi(t, 0, i);

					if(cmp(t, -1, -2) > 0)
					{
						extremeIdx = i;
						insert(t, -2);
					}

					pop(t);
				}
			}
			else
			{
				for(uword i = 1; i < data.length; i++)
				{
					idxi(t, 0, i);

					if(cmp(t, -1, -2) < 0)
					{
						extremeIdx = i;
						insert(t, -2);
					}

					pop(t);
				}
			}
		}

		pushInt(t, extremeIdx);
		return 2;
	}

	uword min(MDThread* t)
	{
		return minMaxImpl(t, 0, false);
	}

	uword max(MDThread* t)
	{
		return minMaxImpl(t, 0, true);
	}

	uword extreme(MDThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 1, MDValue.Type.Function);
		return minMaxImpl(t, numParams, false);
	}

	uword all(MDThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 0, MDValue.Type.Array);

		if(numParams > 0)
		{
			checkParam(t, 1, MDValue.Type.Function);

			foreach(ref v; getArray(t, 0).toArray())
			{
				dup(t, 1);
				pushNull(t);
				push(t, v);
				rawCall(t, -3, 1);

				if(!isTrue(t, -1))
				{
					pushBool(t, false);
					return 1;
				}

				pop(t);
			}
		}
		else
		{
			foreach(ref v; getArray(t, 0).toArray())
			{
				if(v.isFalse())
				{
					pushBool(t, false);
					return 1;
				}
			}
		}

		pushBool(t, true);
		return 1;
	}
	
	uword any(MDThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 0, MDValue.Type.Array);

		if(numParams > 0)
		{
			checkParam(t, 1, MDValue.Type.Function);
			
			foreach(ref v; getArray(t, 0).toArray())
			{
				dup(t, 1);
				pushNull(t);
				push(t, v);
				rawCall(t, -3, 1);

				if(isTrue(t, -1))
				{
					pushBool(t, true);
					return 1;
				}

				pop(t);
			}
		}
		else
		{
			foreach(ref v; getArray(t, 0).toArray())
			{
				if(!v.isFalse())
				{
					pushBool(t, true);
					return 1;
				}
			}
		}

		pushBool(t, false);
		return 1;
	}

	uword fill(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		checkAnyParam(t, 1);
		dup(t, 1);
		fillArray(t, 0);
		return 0;
	}

	uword append(MDThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 0, MDValue.Type.Array);
		auto a = getArray(t, 0);

		if(numParams == 0)
			return 0;
			
		auto oldlen = a.length;
		array.resize(t.vm.alloc, a, a.length + numParams);

		for(uword i = oldlen, j = 1; i < a.length; i++, j++)
			a.data[i] = *getValue(t, j);

		return 0;
	}

	uword flatten(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		auto flattening = getUpval(t, 0);

		auto ret = newArray(t, 0);

		void flatten(word arr)
		{
			auto a = absIndex(t, arr);

			if(opin(t, a, flattening))
				throwException(t, "Attempting to flatten a self-referencing array");

			dup(t, a);
			pushBool(t, true);
			idxa(t, flattening);

			scope(exit)
			{
				dup(t, a);
				pushNull(t);
				idxa(t, flattening);
			}

			foreach(ref val; getArray(t, a).toArray())
			{
				if(val.type == MDValue.Type.Array)
					flatten(push(t, MDValue(val.mArray)));
				else
				{
					push(t, val);
					cateq(t, ret, 1);
				}
			}
		}

		flatten(0);
		dup(t, ret);
		return 1;
	}

	uword makeHeap(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		auto a = getArray(t, 0);

		.makeHeap(a.toArray(), (ref MDValue a, ref MDValue b)
		{
			push(t, a);
			push(t, b);
			auto ret = cmp(t, -2, -1) < 0;
			pop(t, 2);
			return ret;
		});

		dup(t, 0);
		return 1;
	}

// 	uword pushHeap(MDThread* t)
// 	{
// 		checkParam(t, 0, MDValue.Type.Array);
// 		checkAnyParam(t, 1);
// 		auto a = getArray(t, 0);
// 
// 		.pushHeap(a.toArray(), *getValue(t, 1), (ref MDValue a, ref MDValue b)
// 		{
// 			push(t, a);
// 			push(t, b);
// 			auto ret = cmp(t, -2, -1) < 0;
// 			pop(t, 2);
// 			return ret;
// 		});
// 
// 		dup(t, 0);
// 		return 1;
// 	}
// 
// 	uword popHeap(MDThread* t)
// 	{
// 		checkParam(t, 0, MDValue.Type.Array);
// 
// 		if(len(t, 0) == 0)
// 			throwException(t, "Array is empty");
// 
// 		idxi(t, 0, 0, true);
// 
// 		.popHeap(getArray(t, 0).toArray(), (ref MDValue a, ref MDValue b)
// 		{
// 			push(t, a);
// 			push(t, b);
// 			auto ret = cmp(t, -2, -1) < 0;
// 			pop(t, 2);
// 			return ret;
// 		});
// 
// 		return 1;
// 	}

	uword sortHeap(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);

		.sortHeap(getArray(t, 0).toArray(), (ref MDValue a, ref MDValue b)
		{
			push(t, a);
			push(t, b);
			auto ret = cmp(t, -2, -1) < 0;
			pop(t, 2);
			return ret;
		});

		dup(t, 0);
		return 1;
	}

	uword count(MDThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 0, MDValue.Type.Array);
		checkAnyParam(t, 1);

		bool delegate(MDValue, MDValue) pred;

		if(numParams > 1)
		{
			checkParam(t, 2, MDValue.Type.Function);

			pred = (MDValue a, MDValue b)
			{
				auto reg = dup(t, 2);
				pushNull(t);
				push(t, a);
				push(t, b);
				rawCall(t, reg, 1);

				if(!isBool(t, -1))
				{
					pushTypeString(t, -1);
					throwException(t, "count predicate expected to return 'bool', not '{}'", getString(t, -1));
				}

				auto ret = getBool(t, -1);
				pop(t);
				return ret;
			};
		}
		else
		{
			pred = (MDValue a, MDValue b)
			{
				push(t, a);
				push(t, b);
				auto ret = cmp(t, -2, -1) == 0;
				pop(t, 2);
				return ret;
			};
		}

		pushInt(t, .count(getArray(t, 0).toArray(), *getValue(t, 1), pred));
		return 1;
	}

	uword countIf(MDThread* t)
	{
		checkParam(t, 0, MDValue.Type.Array);
		checkParam(t, 1, MDValue.Type.Function);

		pushInt(t, .countIf(getArray(t, 0).toArray(), (MDValue a)
		{
			auto reg = dup(t, 1);
			pushNull(t);
			push(t, a);
			rawCall(t, reg, 1);

			if(!isBool(t, -1))
			{
				pushTypeString(t, -1);
				throwException(t, "count predicate expected to return 'bool', not '{}'", getString(t, -1));
			}
	
			auto ret = getBool(t, -1);
			pop(t);
			return ret;
		}));
		
		return 1;
	}
}