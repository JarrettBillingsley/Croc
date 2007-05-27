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

module minid.tablelib;

import minid.types;

class TableLib
{
	this(MDNamespace namespace)
	{
		namespace.addList
		(
			"dup"d,     new MDClosure(namespace, &dup,    "table.dup"),
			"keys"d,    new MDClosure(namespace, &keys,   "table.keys"),
			"values"d,  new MDClosure(namespace, &values, "table.values"),
			"opApply"d, new MDClosure(namespace, &apply,  "table.opApply"),
			"each"d,    new MDClosure(namespace, &each,   "table.each")
		);
		
		MDNamespace table = new MDNamespace("table"d, MDGlobalState().globals.ns);
		table.addList
		(
			"dup"d,    new MDClosure(table, &staticDup,    "table.dup"),
			"keys"d,   new MDClosure(table, &staticKeys,   "table.keys"),
			"values"d, new MDClosure(table, &staticValues, "table.values"),
			"apply"d,  new MDClosure(table, &staticApply,  "table.apply"),
			"each"d,   new MDClosure(table, &staticEach,   "table.each"),
			"set"d,    new MDClosure(table, &set,          "table.set"),
			"get"d,    new MDClosure(table, &get,          "table.get")
		);

		MDGlobalState().globals["table"d] = table;
	}
	
	int dupImpl(MDState s, MDTable t)
	{
		s.push(t.dup);
		return 1;
	}
	
	int keysImpl(MDState s, MDTable t)
	{
		s.push(t.keys);
		return 1;
	}
	
	int valuesImpl(MDState s, MDTable t)
	{
		s.push(t.values);
		return 1;
	}
	
	int iterator(MDState s, uint numParams)
	{
		MDTable table = s.getUpvalue!(MDTable)(0);
		MDArray keys = s.getUpvalue!(MDArray)(1);
		int index = s.getUpvalue!(int)(2);

		index++;
		s.setUpvalue(2u, index);

		if(index >= keys.length)
			return 0;

		s.push(keys[index]);
		s.push(table[*keys[index]]);

		return 2;
	}
	
	int applyImpl(MDState s, MDTable t)
	{
		MDValue[3] upvalues;

		upvalues[0] = t;
		upvalues[1] = t.keys;
		upvalues[2] = -1;

		s.push(MDGlobalState().newClosure(&iterator, "table.iterator", upvalues));
		return 1;
	}
	
	int eachImpl(MDState s, MDTable t, MDClosure func)
	{
		MDValue tableVal = MDValue(t);

		foreach(k, v; t)
		{
			s.easyCall(func, 1, tableVal, k, v);
			
			MDValue ret = s.pop();
		
			if(ret.isBool() && ret.as!(bool) == false)
				break;
		}
		
		s.push(t);
		return 1;
	}

	int dup(MDState s, uint numParams)
	{
		return dupImpl(s, s.getContext!(MDTable));
	}

	int keys(MDState s, uint numParams)
	{
		return keysImpl(s, s.getContext!(MDTable));
	}
	
	int values(MDState s, uint numParams)
	{
		return valuesImpl(s, s.getContext!(MDTable));
	}

	int apply(MDState s, uint numParams)
	{
		return applyImpl(s, s.getContext!(MDTable));
	}

	int each(MDState s, uint numParams)
	{
		return eachImpl(s, s.getContext!(MDTable), s.getParam!(MDClosure)(0));
	}
	
	int staticDup(MDState s, uint numParams)
	{
		return dupImpl(s, s.getParam!(MDTable)(0));
	}

	int staticKeys(MDState s, uint numParams)
	{
		return keysImpl(s, s.getParam!(MDTable)(0));
	}

	int staticValues(MDState s, uint numParams)
	{
		return valuesImpl(s, s.getParam!(MDTable)(0));
	}
	
	int staticApply(MDState s, uint numParams)
	{
		return applyImpl(s, s.getParam!(MDTable)(0));
	}
	
	int staticEach(MDState s, uint numParams)
	{
		return eachImpl(s, s.getParam!(MDTable)(0), s.getParam!(MDClosure)(1));
	}
	
	int set(MDState s, uint numParams)
	{
		s.getParam!(MDTable)(0)[s.getParam(1u)] = s.getParam(2u);
		return 0;
	}
	
	int get(MDState s, uint numParams)
	{
		s.push(s.getParam!(MDTable)(0)[s.getParam(1u)]);
		return 1;
	}
}

public void init()
{
	MDNamespace namespace = new MDNamespace("table"d, MDGlobalState().globals.ns);
	new TableLib(namespace);
	MDGlobalState().setMetatable(MDValue.Type.Table, namespace);
}