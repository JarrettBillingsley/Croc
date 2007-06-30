module test;

import minid.minid;
import minid.bind;
import tango.io.Stdout;

void foo(int x, int y = 10)
{
	Stdout.formatln("{}, {}", x, y);
}

int average(int[] values...)
{
	int sum = 0;
	
	foreach(val; values)
		sum += val;
		
	return sum / values.length;
}

void something(MDValue val)
{
	Stdout.formatln("val's type is {} and its value is {}", val.typeString(), val.toUtf8());
}

void* blah()
{
	return null;
}

void main()
{
	try
	{
		MDState s = MDInitialize();
		MDGlobalState().addImportPath(`samples`);

		// uncomment this to bind those D functions up above automatically.
		/*WrapModule!
		(
			"bar",
			WrapFunc!(foo),
			WrapFunc!(average),
			WrapFunc!(something),
			WrapFunc!(blah)
		);*/

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