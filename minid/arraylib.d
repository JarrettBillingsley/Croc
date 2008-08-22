/******************************************************************************
License:
Copyright (c) 2007 Jarrett Billingsley

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

module minid.arraylib;

import tango.core.Array;
import tango.core.Tuple;
import tango.math.Math;

import minid.ex;
import minid.interpreter;
import minid.types;

struct ArrayLib
{
static:
	public void init(MDThread* t)
	{
		pushGlobal(t, "modules");
		field(t, -1, "customLoaders");

		newFunction(t, function uword(MDThread* t, uword numParams)
		{
			newFunction(t, &array_new, "new");
			newGlobal(t, "new");
			newFunction(t, &range, "range");
			newGlobal(t, "range");

			newNamespace(t, "array");
				newFunction(t, &sort, "sort"); fielda(t, -2, "sort");
				newFunction(t, &reverse, "reverse"); fielda(t, -2, "reverse");
				newFunction(t, &array_dup, "dup"); fielda(t, -2, "dup");

					newFunction(t, &iterator, "iterator");
					newFunction(t, &iteratorReverse, "iteratorReverse");
				newFunction(t, &opApply, "opApply", 2);
				fielda(t, -2, "opApply");

				newFunction(t, &expand, "expand"); fielda(t, -2, "expand");
				newFunction(t, &toString, "toString"); fielda(t, -2, "toString");
// 				newFunction(t, &apply, "apply"); fielda(t, -2, "apply");
// 				newFunction(t, &map, "map"); fielda(t, -2, "map");
// 				newFunction(t, &reduce, "reduce"); fielda(t, -2, "reduce");
// 				newFunction(t, &each, "each"); fielda(t, -2, "each");
// 				newFunction(t, &filter, "filter"); fielda(t, -2, "filter");
// 				newFunction(t, &find, "find"); fielda(t, -2, "find");
// 				newFunction(t, &findIf, "findIf"); fielda(t, -2, "findIf");
// 				newFunction(t, &bsearch, "bsearch"); fielda(t, -2, "bsearch");
// 				newFunction(t, &pop, "pop"); fielda(t, -2, "pop");
// 				newFunction(t, &set, "set"); fielda(t, -2, "set");
// 				newFunction(t, &min, "min"); fielda(t, -2, "min");
// 				newFunction(t, &max, "max"); fielda(t, -2, "max");
// 				newFunction(t, &extreme, "extreme"); fielda(t, -2, "extreme");
// 				newFunction(t, &any, "any"); fielda(t, -2, "any");
// 				newFunction(t, &all, "all"); fielda(t, -2, "all");
// 				newFunction(t, &fill, "fill"); fielda(t, -2, "fill");
// 				newFunction(t, &append, "append"); fielda(t, -2, "append");
// 				newFunction(t, &flatten, "flatten"); fielda(t, -2, "flatten");
// 				newFunction(t, &makeHeap, "makeHeap"); fielda(t, -2, "makeHeap");
// 				newFunction(t, &pushHeap, "pushHeap"); fielda(t, -2, "pushHeap");
// 				newFunction(t, &popHeap, "popHeap"); fielda(t, -2, "popHeap");
// 				newFunction(t, &sortHeap, "sortHeap"); fielda(t, -2, "sortHeap");
// 				newFunction(t, &count, "count"); fielda(t, -2, "count");
// 				newFunction(t, &countIf, "countIf"); fielda(t, -2, "countIf");
			setTypeMT(t, MDValue.Type.Array);

			return 0;
		}, "array");
		
		fielda(t, -2, "array");

		importModule(t, "array");
	}

	uword array_new(MDThread* t, uword numParams)
	{
		auto length = checkIntParam(t, 1);

		if(length < 0)
			throwException(t, "Invalid length: {}", length);

		newArray(t, length);

		if(numParams > 1)
		{
			dup(t, 2);
			fillArray(t, -2);
		}

		return 1;
	}

	uword range(MDThread* t, uword numParams)
	{
		auto v1 = checkIntParam(t, 1);
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

		newArray(t, size);
		auto a = getArray(t, -1);

		auto val = v1;

		if(v2 < v1)
		{
			for(mdint i = 0; val > v2; i++, val -= step)
				a.slice[i] = val;
		}
		else
		{
			for(mdint i = 0; val < v2; i++, val += step)
				a.slice[i] = val;
		}

		return 1;
	}

	uword sort(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Array);

		bool delegate(MDValue, MDValue) pred;

		if(numParams > 0)
		{
			if(isString(t, 1) && getString(t, 1) == "reverse"d)
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
		
		.sort(getArray(t, 0).slice, pred);
		dup(t, 0);
		return 1;
	}

	uword reverse(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Array);
		getArray(t, 0).slice.reverse;
		dup(t, 0);
		return 1;
	}

	uword array_dup(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Array);
		newArray(t, len(t, 0));
		getArray(t, -1).slice[] = getArray(t, 0).slice[];
		return 1;
	}

	uword iterator(MDThread* t, uword numParams)
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

	uword iteratorReverse(MDThread* t, uword numParams)
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

	uword opApply(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Array);

		if(isString(t, 1) && getString(t, 1) == "reverse")
		{
			getUpval(t, 1);
			dup(t, 0);
			pushInt(t, len(t, 0));
		}
		else
		{
			getUpval(t, 0);
			dup(t, 0);
			pushInt(t, -1);
		}

		return 3;
	}

	uword expand(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Array);
		auto a = getArray(t, 0);

		foreach(ref val; a.slice)
			push(t, val);

		return a.slice.length;
	}

	uword toString(MDThread* t, uword numParams)
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
				insert(t, -2);
				pop(t);
				buf.addTop();
			}
	
			if(i < length - 1)
				buf.addString(", ");
		}
	
		buf.addChar(']');
		buf.finish();
	
		return 1;
	}
/+
	uword apply(MDThread* t, uword numParams)
	{
		MDArray array = s.getContext!(MDArray);
		MDClosure func = s.getParam!(MDClosure)(0);
		MDValue arrayVal = array;

		foreach(i, v; array)
		{
			s.callWith(func, 1, arrayVal, v);
			array[i] = s.pop();
		}

		s.push(array);
		return 1;
	}
	
	uword map(MDThread* t, uword numParams)
	{
		MDArray array = s.getContext!(MDArray);
		MDClosure func = s.getParam!(MDClosure)(0);
		MDValue arrayVal = array;
		
		MDArray ret = new MDArray(array.length);

		foreach(i, v; array)
		{
			s.callWith(func, 1, arrayVal, v);
			ret[i] = s.pop();
		}

		s.push(ret);
		return 1;
	}
	
	uword reduce(MDThread* t, uword numParams)
	{
		MDArray array = s.getContext!(MDArray);
		MDClosure func = s.getParam!(MDClosure)(0);
		MDValue arrayVal = array;

		if(array.length == 0)
		{
			s.pushNull();
			return 1;
		}

		MDValue ret = array[0];
		
		for(int i = 1; i < array.length; i++)
		{
			s.callWith(func, 1, arrayVal, ret, array[i]);
			ret = s.pop();
		}
		
		s.push(ret);
		return 1;
	}
	
	uword each(MDThread* t, uword numParams)
	{
		MDArray array = s.getContext!(MDArray);
		MDClosure func = s.getParam!(MDClosure)(0);
		MDValue arrayVal = array;

		foreach(i, v; array)
		{
			s.callWith(func, 1, arrayVal, i, v);

			MDValue ret = s.pop();
		
			if(ret.isBool() && ret.as!(bool)() == false)
				break;
		}

		s.push(array);
		return 1;
	}
	
	uword filter(MDThread* t, uword numParams)
	{
		MDArray array = s.getContext!(MDArray);
		MDClosure func = s.getParam!(MDClosure)(0);
		MDValue arrayVal = array;
		
		MDArray retArray = new MDArray(array.length / 2);
		uint retIdx = 0;

		foreach(i, v; array)
		{
			s.callWith(func, 1, arrayVal, i, v);

			if(s.pop!(bool)() == true)
			{
				if(retIdx >= retArray.length)
					retArray.length = retArray.length + 10;

				retArray[retIdx] = v;
				retIdx++;
			}
		}
		
		retArray.length = retIdx;
		s.push(retArray);
		return 1;
	}
	
	uword find(MDThread* t, uword numParams)
	{
		MDArray array = s.getContext!(MDArray);
		MDValue val = s.getParam(0u);
		
		foreach(i, v; array)
		{
			if(val.type == v.type && s.cmp(val, v) == 0)
			{
				s.push(i);
				return 1;
			}
		}
		
		s.push(array.length);
		return 1;
	}
	
	uword findIf(MDThread* t, uword numParams)
	{
		auto self = s.getContext!(MDArray);
		auto cl = s.getParam!(MDClosure)(0);
		
		foreach(i, v; self)
		{
			s.call(cl, 1, v);

			if(s.pop!(bool))
			{
				s.push(i);
				return 1;
			}
		}

		s.push(self.length);
		return 1;
	}
	
	uword bsearch(MDThread* t, uword numParams)
	{
		MDArray array = s.getContext!(MDArray);
		MDValue val = s.getParam(0u);

		uint lo = 0;
		uint hi = array.length - 1;
		uint mid = (lo + hi) >> 1;

		while((hi - lo) > 8)
		{
			int cmp = s.cmp(val, *array[mid]);
			
			if(cmp == 0)
			{
				s.push(mid);
				return 1;
			}
			else if(cmp < 0)
				hi = mid;
			else
				lo = mid;
				
			mid = (lo + hi) >> 1;
		}

		for(int i = lo; i <= hi; i++)
		{
			if(val.compare(array[i]) == 0)
			{
				s.push(i);
				return 1;
			}
		}

		s.push(array.length);
		return 1;
	}
	
	uword pop(MDThread* t, uword numParams)
	{
		MDArray array = s.getContext!(MDArray);
		int index = -1;

		if(array.length == 0)
			s.throwRuntimeException("Array is empty");

		if(numParams > 0)
			index = s.getParam!(int)(0);

		if(index < 0)
			index += array.length;

		if(index < 0 || index >= array.length)
			s.throwRuntimeException("Invalid array index: {}", index);

		s.push(array[index]);

		for(int i = index; i < array.length - 1; i++)
			array[i] = *array[i + 1];

		array.length = array.length - 1;

		return 1;
	}
	
	uword set(MDThread* t, uword numParams)
	{
		auto array = s.getContext!(MDArray);

		array.length = numParams;
		
		for(uint i = 0; i < numParams; i++)
			array[i] = s.getParam(i);

		s.push(array);
		return 1;
	}
	
	int minMaxImpl(MDState s, uint numParams, bool max)
	{
		auto self = s.getContext!(MDArray);
		
		if(self.length == 0)
			s.throwRuntimeException("Array is empty");

		auto extreme = self[0];

		if(numParams > 0)
		{
			auto compare = s.getParam!(MDClosure)(0);

			for(int i = 1; i < self.length; i++)
			{
				s.call(compare, 1, self[i], extreme);

				if(s.pop!(bool))
					extreme = self[i];
			}
		}
		else
		{
			if(max)
			{
				for(int i = 1; i < self.length; i++)
					if(s.cmp(*self[i], *extreme) > 0)
						extreme = self[i];
			}
			else
			{
				for(int i = 1; i < self.length; i++)
					if(s.cmp(*self[i], *extreme) < 0)
						extreme = self[i];
			}
		}

		s.push(extreme);
		return 1;
	}

	uword min(MDThread* t, uword numParams)
	{
		return minMaxImpl(s, 0, false);
	}

	uword max(MDThread* t, uword numParams)
	{
		return minMaxImpl(s, 0, true);
	}
	
	uword extreme(MDThread* t, uword numParams)
	{
		s.getParam!(MDClosure)(0);
		return minMaxImpl(s, numParams, false);
	}
	
	uword all(MDThread* t, uword numParams)
	{
		auto self = s.getContext!(MDArray);

		if(numParams > 0)
		{
			auto pred = s.getParam!(MDClosure)(0);
			
			foreach(ref v; self)
			{
				s.call(pred, 1, v);
				
				if(s.pop().isFalse)
				{
					s.push(false);
					return 1;
				}
			}
		}
		else
		{
			foreach(ref v; self)
			{
				if(v.isFalse)
				{
					s.push(false);
					return 1;
				}
			}
		}

		s.push(true);
		return 1;
	}
	
	uword any(MDThread* t, uword numParams)
	{
		auto self = s.getContext!(MDArray);

		if(numParams > 0)
		{
			auto pred = s.getParam!(MDClosure)(0);
			
			foreach(ref v; self)
			{
				s.call(pred, 1, v);
				
				if(s.pop().isTrue)
				{
					s.push(true);
					return 1;
				}
			}
		}
		else
		{
			foreach(ref v; self)
			{
				if(v.isTrue)
				{
					s.push(true);
					return 1;
				}
			}
		}

		s.push(false);
		return 1;
	}
	
	uword fill(MDThread* t, uword numParams)
	{
		s.getContext!(MDArray)()[] = s.getParam(0u);
		return 0;
	}

	uword append(MDThread* t, uword numParams)
	{
		auto self = s.getContext!(MDArray)();

		for(uint i = 0; i < numParams; i++)
			self ~= s.getParam(i);

		return 0;
	}
	
	uword flatten(MDThread* t, uword numParams)
	{
		bool[MDArray] flattening;
		auto ret = new MDArray(0);

		void flatten(MDArray a)
		{
			if(a in flattening)
				s.throwRuntimeException("Attempting to flatten a self-referencing array");

			flattening[a] = true;
			
			foreach(ref val; a)
			{
				if(val.isArray)
					flatten(val.as!(MDArray));
				else
					ret ~= val;
			}

			flattening.remove(a);
		}
		
		flatten(s.getContext!(MDArray)());
		s.push(ret);
		return 1;
	}
	
	uword makeHeap(MDThread* t, uword numParams)
	{
		auto self = s.getContext!(MDArray)();
		.makeHeap(self.mData, (ref MDValue a, ref MDValue b) { return s.cmp(a, b) < 0; });
		s.push(self);
		return 1;
	}

	uword pushHeap(MDThread* t, uword numParams)
	{
		auto self = s.getContext!(MDArray)();
		auto val = s.getParam(0u);
		.pushHeap(self.mData, val, (ref MDValue a, ref MDValue b) { return s.cmp(a, b) < 0; });
		s.push(self);
		return 1;
	}

	uword popHeap(MDThread* t, uword numParams)
	{
		auto self = s.getContext!(MDArray)();

		if(self.length == 0)
			s.throwRuntimeException("Array is empty");

		s.push(self[0]);
		.popHeap(self.mData, (ref MDValue a, ref MDValue b) { return s.cmp(a, b) < 0; });
		return 1;
	}

	uword sortHeap(MDThread* t, uword numParams)
	{
		auto self = s.getContext!(MDArray)();
		.sortHeap(self.mData, (ref MDValue a, ref MDValue b) { return s.cmp(a, b) < 0; });
		s.push(self);
		return 1;
	}
	
	uword count(MDThread* t, uword numParams)
	{
		auto self = s.getContext!(MDArray)();
		auto val = s.getParam(0u);

		bool delegate(MDValue, MDValue) pred;

		if(numParams > 1)
		{
			auto cl = s.getParam!(MDClosure)(1);
			pred = (MDValue a, MDValue b)
			{
				s.call(cl, 1, a, b);
				return s.pop!(bool)();
			};
		}
		else
			pred = (MDValue a, MDValue b) { return s.cmp(a, b) == 0; };

		s.push(.count(self.mData, val, pred));
		return 1;
	}

	uword countIf(MDThread* t, uword numParams)
	{
		auto self = s.getContext!(MDArray)();
		auto cl = s.getParam!(MDClosure)(0);

		s.push(.countIf(self.mData, (MDValue a)
		{
			s.call(cl, 1, a);
			return s.pop!(bool)();
		}));
		
		return 1;
	}
+/
}