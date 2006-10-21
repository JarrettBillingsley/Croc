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
}

public void init(MDState s)
{
	TableLib lib = new TableLib();
	
	MDTable tableLib = MDTable.create
	(
		"dup",       new MDClosure(s, &lib.dup,      "table.dup")
	);

	s.setGlobal("table"d, tableLib);
	MDGlobalState().setMetatable(MDValue.Type.Table, tableLib);
}