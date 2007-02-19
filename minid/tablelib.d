module minid.tablelib;

import minid.types;

class TableLib
{
	this(MDNamespace namespace)
	{
		namespace.addList
		(
			"dup",       new MDClosure(namespace, &dup,      "table.dup"),
			"keys",      new MDClosure(namespace, &keys,     "table.keys"),
			"values",    new MDClosure(namespace, &values,   "table.values"),
			"remove",    new MDClosure(namespace, &remove,   "table.remove"),
			"contains",  new MDClosure(namespace, &contains, "table.contains"),
			"opApply",   new MDClosure(namespace, &apply,    "table.opApply"),
			"each",      new MDClosure(namespace, &each,     "table.each")
		);
	}

	int dup(MDState s)
	{
		s.push(s.getContext().asTable().dup);
		return 1;
	}
	
	int keys(MDState s)
	{
		s.push(s.getContext().asTable().keys);
		return 1;
	}
	
	int values(MDState s)
	{
		s.push(s.getContext().asTable().values);
		return 1;
	}
	
	int remove(MDState s)
	{
		s.getContext().asTable().remove(s.getParam(0));
		return 0;
	}
	
	int contains(MDState s)
	{
		MDValue key = s.getParam(0);
		MDValue* val = (key in s.getContext().asTable());

		if(val is null)
		{
			s.push(false);
			return 1;
		}
		else
		{
			s.push(true);
			s.push(val);
			return 2;
		}
	}

	int iterator(MDState s)
	{
		MDTable table = s.getUpvalue(0).asTable();
		MDArray keys = s.getUpvalue(1).asArray();
		int index = s.getUpvalue(2).asInt();

		index++;
		s.setUpvalue(2u, index);

		if(index >= keys.length)
			return 0;

		s.push(keys[index]);
		s.push(table[*keys[index]]);

		return 2;
	}

	int apply(MDState s)
	{
		MDValue[3] upvalues;

		upvalues[0].value = s.getContext().asTable();
		upvalues[1].value = upvalues[0].asTable.keys;
		upvalues[2].value = -1;

		s.push(MDGlobalState().newClosure(&iterator, "table.iterator", upvalues));

		return 1;
	}

	int each(MDState s)
	{
		MDTable table = s.getContext().asTable();
		MDClosure func = s.getClosureParam(0);
		MDValue tableVal = MDValue(table);

		foreach(k, v; table)
		{
			s.easyCall(func, 1, tableVal, k, v);
			
			MDValue ret = s.pop();
		
			if(ret.isBool() && ret.asBool == false)
				break;
		}
		
		return 0;
	}
}

public void init()
{
	MDNamespace namespace = new MDNamespace("table"d, MDGlobalState().globals);
	new TableLib(namespace);
	MDGlobalState().setMetatable(MDValue.Type.Table, namespace);
}