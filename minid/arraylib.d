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
			lo = 0;
			hi = arr.length;
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
}

public void init(MDState s)
{
	ArrayLib lib = new ArrayLib();

	MDTable arrayTable = MDTable.create
	(
		"new",       new MDClosure(s, &lib.newArray, "array.new"),
		"sort",      new MDClosure(s, &lib.sort,     "array.sort"),
		"reverse",   new MDClosure(s, &lib.reverse,  "array.reverse"),
		"dup",       new MDClosure(s, &lib.dup,      "array.dup"),
		"length",    new MDClosure(s, &lib.length,   "array.length"),
		"slice",     new MDClosure(s, &lib.slice,    "array.slice")
	);

	s.setGlobal("array", arrayTable);
	MDGlobalState().setMetatable(MDValue.Type.Array, arrayTable);
}