module test;

import minid.minid;
import tango.io.Stdout;

void main()
{
	try
	{
		MDState s = MDInitialize();
		MDGlobalState().addImportPath(`samples`);

		MDGlobalState().importModule("simple");
	}
	catch(MDException e)
	{
		Stdout.formatln("Error: {}", e.toUtf8());
		Stdout.formatln("{}", MDState.getTracebackString());
	}
	catch(Exception e)
	{
		Stdout.formatln("Bad error: {}", e.toUtf8());
		Stdout.formatln("{}", MDState.getTracebackString());
	}
}