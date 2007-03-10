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

import std.math;

class ArrayLib
{
	this(MDNamespace namespace)
	{
		iteratorClosure = new MDClosure(namespace, &iterator, "array.iterator");
		iteratorReverseClosure = new MDClosure(namespace, &iteratorReverse, "array.iteratorReverse");

		namespace.addList
		(
			"sort"d,     new MDClosure(namespace, &sort,     "array.sort"),
			"reverse"d,  new MDClosure(namespace, &reverse,  "array.reverse"),
			"dup"d,      new MDClosure(namespace, &dup,      "array.dup"),
			"length"d,   new MDClosure(namespace, &length,   "array.length"),
			"opApply"d,  new MDClosure(namespace, &apply,    "array.opApply"),
			"expand"d,   new MDClosure(namespace, &expand,   "array.expand"),
			"toString"d, new MDClosure(namespace, &ToString, "array.toString")
		);

		MDGlobalState().setGlobal("array"d, MDNamespace.create
		(
			"array"d,    MDGlobalState().globals,
			"new"d,      new MDClosure(namespace, &newArray, "array.new"),
			"range"d,    new MDClosure(namespace, &range,    "array.range")
		));
	}

	int newArray(MDState s)
	{
		int length = s.getIntParam(0);
		
		if(length < 0)
			s.throwRuntimeException("Invalid length: ", length);
			
		if(s.numParams() == 1)
			s.push(new MDArray(length));
		else
		{
			MDArray arr = new MDArray(length);
			arr[] = s.getParam(1);
			s.push(arr);
		}

		return 1;
	}
	
	int range(MDState s)
	{
		int v1 = s.getIntParam(0);
		int v2;
		int step = 1;

		if(s.numParams() == 1)
		{
			v2 = v1;
			v1 = 0;
		}
		else if(s.numParams() == 2)
			v2 = s.getIntParam(1);
		else
		{
			v2 = s.getIntParam(1);
			step = s.getIntParam(2);
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
				ret[i].value = val;
		}
		else
		{
			for(int i = 0; val < v2; i++, val += step)
				ret[i].value = val;
		}

		s.push(ret);
		return 1;
	}

	int sort(MDState s)
	{
		MDArray arr = s.getContext().asArray();
		arr.sort();
		s.push(arr);

		return 1;
	}
	
	int reverse(MDState s)
	{
		MDArray arr = s.getContext().asArray();
		arr.reverse();
		s.push(arr);
		
		return 1;
	}
	
	int dup(MDState s)
	{
		s.push(s.getContext().asArray().dup);
		return 1;
	}
	
	int length(MDState s)
	{
		MDArray arr = s.getContext().asArray();
		int length = s.getIntParam(0);

		if(length < 0)
			s.throwRuntimeException("Invalid length: ", length);

		arr.length = length;

		s.push(arr);
		return 1;
	}

	int iterator(MDState s)
	{
		MDArray array = s.getContext().asArray();
		int index = s.getIntParam(0);

		index++;
		
		if(index >= array.length)
			return 0;
			
		s.push(index);
		s.push(array[index]);
		
		return 2;
	}

	int iteratorReverse(MDState s)
	{
		MDArray array = s.getContext().asArray();
		int index = s.getIntParam(0);
		
		index--;

		if(index < 0)
			return 0;
			
		s.push(index);
		s.push(array[index]);
		
		return 2;
	}
	
	MDClosure iteratorClosure;
	MDClosure iteratorReverseClosure;
	
	int apply(MDState s)
	{
		MDArray array = s.getContext().asArray();

		if(s.numParams() > 0 && s.isParam!("string")(0) && s.getStringParam(0) == "reverse"d)
		{
			s.push(iteratorReverseClosure);
			s.push(array);
			s.push(cast(int)array.length);
		}
		else
		{
			s.push(iteratorClosure);
			s.push(array);
			s.push(-1);
		}

		return 3;
	}
	
	int expand(MDState s)
	{
		MDArray array = s.getContext().asArray();
		
		for(int i = 0; i < array.length; i++)
			s.push(array[i]);
			
		return array.length;
	}
	
	int ToString(MDState s)
	{
		MDArray array = s.getContext().asArray();
		
		char[] str = "[";

		for(int i = 0; i < array.length; i++)
		{
			if(array[i].isString())
				str ~= '"' ~ array[i].toString() ~ '"';
			else
				str ~= array[i].toString();
			
			if(i < array.length - 1)
				str ~= ", ";
		}

		s.push(str ~ "]");
		
		return 1;
	}
}

public void init()
{
	MDNamespace namespace = new MDNamespace("array"d, MDGlobalState().globals);
	new ArrayLib(namespace);
	MDGlobalState().setMetatable(MDValue.Type.Array, namespace);
}