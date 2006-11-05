module minid.tablelib;

import minid.state;
import minid.types;

class TableLib
{
	int dup(MDState s)
	{
		MDTable tab = s.getTableParam(0);
		s.push(tab.dup);
		return 1;
	}
	
	int keys(MDState s)
	{
		MDTable tab = s.getTableParam(0);
		s.push(tab.keys);
		return 1;
	}
	
	int values(MDState s)
	{
		MDTable tab = s.getTableParam(0);
		s.push(tab.values);
		return 1;
	}
	
	int remove(MDState s)
	{
		MDValue key = s.getParam(1);
		s.getTableParam(0).remove(&key);
		return 0;
	}
	
	int contains(MDState s)
	{
		MDValue key = s.getParam(1);
		MDValue* val = s.getTableParam(0)[&key];
		
		s.push(!val.isNull());
		return 1;
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
		s.push(table[keys[index]]);

		return 2;
	}
	
	int apply(MDState s)
	{
		MDValue[3] upvalues;

		upvalues[0].value = s.getTableParam(0);
		upvalues[1].value = upvalues[0].asTable.keys;
		upvalues[2].value = -1;

		s.push(new MDClosure(s, &iterator, "table.iterator", upvalues));
		
		return 1;
	}
}

public void init(MDState s)
{
	TableLib lib = new TableLib();
	
	MDTable tableLib = MDTable.create
	(
		"dup",       new MDClosure(s, &lib.dup,      "table.dup"),
		"keys",      new MDClosure(s, &lib.keys,     "table.keys"),
		"values",    new MDClosure(s, &lib.values,   "table.values"),
		"remove",    new MDClosure(s, &lib.remove,   "table.remove"),
		"contains",  new MDClosure(s, &lib.contains, "table.contains"),
		"opApply",   new MDClosure(s, &lib.apply,    "table.opApply")
	);

	s.setGlobal("table"d, tableLib);
	MDGlobalState().setMetatable(MDValue.Type.Table, tableLib);
}