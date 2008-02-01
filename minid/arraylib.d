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

import minid.types;
import minid.utils;
import tango.core.Array;
import tango.core.Tuple;
import tango.math.Math;

final class ArrayLib
{
	private static ArrayLib lib;
	
	private this()
	{

	}
	
	static this()
	{
		lib = new ArrayLib();
	}

	public static void init(MDContext context)
	{
		MDNamespace namespace = new MDNamespace("array"d, context.globals.ns);

		namespace.addList
		(
			"sort"d,     new MDClosure(namespace, &lib.sort,     "array.sort"),
			"reverse"d,  new MDClosure(namespace, &lib.reverse,  "array.reverse"),
			"dup"d,      new MDClosure(namespace, &lib.dup,      "array.dup"),
			"length"d,   new MDClosure(namespace, &lib.length,   "array.length"),
			"opApply"d,  new MDClosure(namespace, &lib.opApply,  "array.opApply",
			[
				MDValue(new MDClosure(namespace, &lib.iterator,        "array.iterator")),
				MDValue(new MDClosure(namespace, &lib.iteratorReverse, "array.iteratorReverse"))
			]),
			"expand"d,   new MDClosure(namespace, &lib.expand,   "array.expand"),
			"toString"d, new MDClosure(namespace, &lib.toString, "array.toString"),
			"apply"d,    new MDClosure(namespace, &lib.apply,    "array.apply"),
			"map"d,      new MDClosure(namespace, &lib.map,      "array.map"),
			"reduce"d,   new MDClosure(namespace, &lib.reduce,   "array.reduce"),
			"each"d,     new MDClosure(namespace, &lib.each,     "array.each"),
			"filter"d,   new MDClosure(namespace, &lib.filter,   "array.filter"),
			"find"d,     new MDClosure(namespace, &lib.find,     "array.find"),
			"bsearch"d,  new MDClosure(namespace, &lib.bsearch,  "array.bsearch"),
			"pop"d,      new MDClosure(namespace, &lib.pop,      "array.pop"),
			"set"d,      new MDClosure(namespace, &lib.set,      "array.set"),
			"min"d,      new MDClosure(namespace, &lib.min,      "array.min"),
			"max"d,      new MDClosure(namespace, &lib.max,      "array.max"),
			"extreme"d,  new MDClosure(namespace, &lib.extreme,  "array.extreme"),
			"any"d,      new MDClosure(namespace, &lib.any,      "array.any"),
			"all"d,      new MDClosure(namespace, &lib.all,      "array.all"),
			"fill"d,     new MDClosure(namespace, &lib.fill,     "array.fill"),
			"append"d,   new MDClosure(namespace, &lib.append,   "array.append"),
			"flatten"d,  new MDClosure(namespace, &lib.flatten,  "array.flatten"),
			"makeHeap"d, new MDClosure(namespace, &lib.makeHeap, "array.makeHeap"),
			"pushHeap"d, new MDClosure(namespace, &lib.pushHeap, "array.pushHeap"),
			"popHeap"d,  new MDClosure(namespace, &lib.popHeap,  "array.popHeap"),
			"sortHeap"d, new MDClosure(namespace, &lib.sortHeap, "array.sortHeap")
		);

		context.globals["array"d] = MDNamespace.create
		(
			"array"d,    context.globals.ns,
			"new"d,      new MDClosure(context.globals.ns, &lib.newArray, "array.new"),
			"range"d,    new MDClosure(context.globals.ns, &lib.range,    "array.range")
		);

		context.setMetatable(MDValue.Type.Array, namespace);
	}

	int newArray(MDState s, uint numParams)
	{
		int length = s.getParam!(int)(0);
		
		if(length < 0)
			s.throwRuntimeException("Invalid length: {}", length);
			
		if(numParams == 1)
			s.push(new MDArray(length));
		else
		{
			MDArray arr = new MDArray(length);
			arr[] = s.getParam(1u);
			s.push(arr);
		}

		return 1;
	}
	
	int range(MDState s, uint numParams)
	{
		int v1 = s.getParam!(int)(0);
		int v2;
		int step = 1;

		if(numParams == 1)
		{
			v2 = v1;
			v1 = 0;
		}
		else if(numParams == 2)
			v2 = s.getParam!(int)(1);
		else
		{
			v2 = s.getParam!(int)(1);
			step = s.getParam!(int)(2);
		}

		if(step <= 0)
			s.throwRuntimeException("Step may not be negative or 0");
		
		int range = abs(v2 - v1);
		int size = range / step;

		if((range % step) != 0)
			size++;

		MDArray ret = new MDArray(size);
		
		int val = v1;

		if(v2 < v1)
		{
			for(int i = 0; val > v2; i++, val -= step)
				*ret[i] = val;
		}
		else
		{
			for(int i = 0; val < v2; i++, val += step)
				*ret[i] = val;
		}

		s.push(ret);
		return 1;
	}

	int sort(MDState s, uint numParams)
	{
		MDArray arr = s.getContext!(MDArray);

		bool delegate(MDValue, MDValue) pred;

		MDClosure sortFunc;

		if(numParams > 0)
		{
			if(s.isParam!("string")(0) && s.getParam!(MDString)(0) == "reverse"d)
			{
				pred = (MDValue v1, MDValue v2)
				{
					return s.cmp(v1, v2) > 0;
				};
			}
			else
			{
				sortFunc = s.getParam!(MDClosure)(0);

				pred = (MDValue v1, MDValue v2)
				{
					s.call(sortFunc, 1, v1, v2);
					return s.pop!(int)() < 0;
				};
			}
		}
		else
		{
			pred = (MDValue v1, MDValue v2)
			{
				return s.cmp(v1, v2) < 0;
			};
		}

		arr.sort(pred);
		s.push(arr);
		return 1;
	}

	int reverse(MDState s, uint numParams)
	{
		MDArray arr = s.getContext!(MDArray);
		arr.reverse();
		s.push(arr);
		return 1;
	}
	
	int dup(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDArray).dup);
		return 1;
	}
	
	int length(MDState s, uint numParams)
	{
		MDArray arr = s.getContext!(MDArray);
		int length = s.getParam!(int)(0);

		if(length < 0)
			s.throwRuntimeException("Invalid length: {}", length);

		arr.length = length;

		s.push(arr);
		return 1;
	}

	int iterator(MDState s, uint numParams)
	{
		MDArray array = s.getContext!(MDArray);
		int index = s.getParam!(int)(0);

		index++;
		
		if(index >= array.length)
			return 0;
			
		s.push(index);
		s.push(array[index]);
		
		return 2;
	}

	int iteratorReverse(MDState s, uint numParams)
	{
		MDArray array = s.getContext!(MDArray);
		int index = s.getParam!(int)(0);
		
		index--;

		if(index < 0)
			return 0;
			
		s.push(index);
		s.push(array[index]);
		
		return 2;
	}

	int opApply(MDState s, uint numParams)
	{
		MDArray array = s.getContext!(MDArray);

		if(s.isParam!("string")(0) && s.getParam!(MDString)(0) == "reverse"d)
		{
			s.push(s.getUpvalue(1u));
			s.push(array);
			s.push(cast(int)array.length);
		}
		else
		{
			s.push(s.getUpvalue(0u));
			s.push(array);
			s.push(-1);
		}

		return 3;
	}
	
	int expand(MDState s, uint numParams)
	{
		MDArray array = s.getContext!(MDArray);
		
		for(int i = 0; i < array.length; i++)
			s.push(array[i]);
			
		return array.length;
	}
	
	int toString(MDState s, uint numParams)
	{
		MDArray array = s.getContext!(MDArray);
		
		char[] str = "[";

		for(int i = 0; i < array.length; i++)
		{
			if(array[i].isString())
				str ~= '"' ~ array[i].as!(MDString).asUTF8() ~ '"';
			else
				str ~= array[i].toString();
			
			if(i < array.length - 1)
				str ~= ", ";
		}

		s.push(str ~ "]");
		
		return 1;
	}
	
	int apply(MDState s, uint numParams)
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
	
	int map(MDState s, uint numParams)
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
	
	int reduce(MDState s, uint numParams)
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
	
	int each(MDState s, uint numParams)
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
	
	int filter(MDState s, uint numParams)
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
	
	int find(MDState s, uint numParams)
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
	
	int bsearch(MDState s, uint numParams)
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
	
	int pop(MDState s, uint numParams)
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
	
	int set(MDState s, uint numParams)
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

	int min(MDState s, uint numParams)
	{
		return minMaxImpl(s, 0, false);
	}

	int max(MDState s, uint numParams)
	{
		return minMaxImpl(s, 0, true);
	}
	
	int extreme(MDState s, uint numParams)
	{
		s.getParam!(MDClosure)(0);
		return minMaxImpl(s, numParams, false);
	}
	
	int all(MDState s, uint numParams)
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
	
	int any(MDState s, uint numParams)
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
	
	int fill(MDState s, uint numParams)
	{
		s.getContext!(MDArray)()[] = s.getParam(0u);
		return 0;
	}

	int append(MDState s, uint numParams)
	{
		auto self = s.getContext!(MDArray)();

		for(uint i = 0; i < numParams; i++)
			self ~= s.getParam(i);

		return 0;
	}
	
	int flatten(MDState s, uint numParams)
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
	
	int makeHeap(MDState s, uint numParams)
	{
		auto self = s.getContext!(MDArray)();
		.makeHeap(self.mData, (ref MDValue a, ref MDValue b) { return s.cmp(a, b) < 0; });
		s.push(self);
		return 1;
	}

	int pushHeap(MDState s, uint numParams)
	{
		auto self = s.getContext!(MDArray)();
		auto val = s.getParam(0u);
		.pushHeap(self.mData, val, (ref MDValue a, ref MDValue b) { return s.cmp(a, b) < 0; });
		s.push(self);
		return 1;
	}

	int popHeap(MDState s, uint numParams)
	{
		auto self = s.getContext!(MDArray)();

		if(self.length == 0)
			s.throwRuntimeException("Array is empty");

		s.push(self[0]);
		.popHeap(self.mData, (ref MDValue a, ref MDValue b) { return s.cmp(a, b) < 0; });
		return 1;
	}

	int sortHeap(MDState s, uint numParams)
	{
		auto self = s.getContext!(MDArray)();
		.sortHeap(self.mData, (ref MDValue a, ref MDValue b) { return s.cmp(a, b) < 0; });
		s.push(self);
		return 1;
	}
}