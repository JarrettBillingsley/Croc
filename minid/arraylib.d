module minid.arraylib;

import minid.state;
import minid.types;

class ArrayLib
{
	int newArray(MDState s)
	{
		int length = s.getIntParam(0);
		
		if(length < 0)
			throw new MDRuntimeException(s, "Invalid length: ", length);
			
		s.push(new MDArray(length));
		
		return 1;
	}

	int sort(MDState s)
	{
		MDArray arr = s.getArrayParam(0);
		arr.sort();
		s.push(arr);

		return 1;
	}
	
	int reverse(MDState s)
	{
		MDArray arr = s.getArrayParam(0);
		arr.reverse();
		s.push(arr);
		
		return 1;
	}
	
	int dup(MDState s)
	{
		MDArray arr = s.getArrayParam(0);
		s.push(arr.dup);
		return 1;
	}
	
	int length(MDState s)
	{
		MDArray arr = s.getArrayParam(0);
		int length = s.getIntParam(1);

		if(length < 0)
			throw new MDRuntimeException(s, "Invalid length: ", length);

		arr.length = length;

		s.push(arr);
		return 1;
	}
	
	int slice(MDState s)
	{
		MDArray arr = s.getArrayParam(0);
		
		int lo;
		int hi;
		
		if(s.numParams() == 1)
		{
			s.push(arr);
			return 1;
		}
		else if(s.numParams() == 2)
		{
			lo = s.getIntParam(1);
			hi = arr.length;
		}
		else
		{
			lo = s.getIntParam(1);
			hi = s.getIntParam(2);
		}
		
		if(lo < 0)
			lo = arr.length + lo + 1;
			
		if(hi < 0)
			hi = arr.length + hi + 1;
			
		if(lo > hi || lo < 0 || lo > arr.length || hi < 0 || hi > arr.length)
			throw new MDRuntimeException(s, "Invalid slice indices [", lo, " .. ", hi, "] (array length = ", arr.length, ")");

		s.push(arr[lo .. hi]);
		
		return 1;
	}
	
	int iterator(MDState s)
	{
		MDArray array = s.getArrayParam(0);
		int index = s.getIntParam(1);
		
		index++;
		
		if(index >= array.length)
			return 0;
			
		s.push(index);
		s.push(array[index]);
		
		return 2;
	}

	int iteratorReverse(MDState s)
	{
		MDArray array = s.getArrayParam(0);
		int index = s.getIntParam(1);
		
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
		MDArray array = s.getArrayParam(0);

		if(s.numParams() > 1 && s.isParam!("string")(1) && s.getStringParam(1) == "reverse"d)
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
		MDArray array = s.getArrayParam(0);
		
		for(int i = 0; i < array.length; i++)
			s.push(array[i]);
			
		return array.length;
	}
}

public void init(MDState s)
{
	ArrayLib lib = new ArrayLib();
	
	lib.iteratorClosure = new MDClosure(s, &lib.iterator, "array.iterator");
	lib.iteratorReverseClosure = new MDClosure(s, &lib.iteratorReverse, "array.iteratorReverse");

	MDTable arrayTable = MDTable.create
	(
		"new",       new MDClosure(s, &lib.newArray, "array.new"),
		"sort",      new MDClosure(s, &lib.sort,     "array.sort"),
		"reverse",   new MDClosure(s, &lib.reverse,  "array.reverse"),
		"dup",       new MDClosure(s, &lib.dup,      "array.dup"),
		"length",    new MDClosure(s, &lib.length,   "array.length"),
		"slice",     new MDClosure(s, &lib.slice,    "array.slice"),
		"opApply",   new MDClosure(s, &lib.apply,    "array.opApply"),
		"expand",    new MDClosure(s, &lib.expand,   "array.expand")
	);

	s.setGlobal("array"d, arrayTable);
	MDGlobalState().setMetatable(MDValue.Type.Array, arrayTable);
}