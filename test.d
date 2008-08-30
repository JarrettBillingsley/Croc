module test;

import tango.io.Stdout;
debug import tango.stdc.stdarg; // To make tango-user-base-debug.lib link correctly

import minid.api;

// TODO: Object finalizers...

void main()
{
	scope(exit) Stdout.flush;

	MDVM vm;
	auto t = openVM(&vm);
	loadStdlibs(t);

	try
	{
		importModule(t, "samples.simple");
		pop(t);
	}
	catch(MDException e)
	{
		auto ex = catchException(t);
		Stdout.formatln("Error: {}", e);
	}
	catch(Exception e)
	{
		Stdout.formatln("Bad error ({}, {}): {}", e.file, e.line, e);
		return;
	}

	Stdout.newline.format("MiniD using {} bytes before GC, ", bytesAllocated(&vm)).flush;
	gc(&vm);
	Stdout.formatln("{} bytes after.", bytesAllocated(&vm)).flush;

	closeVM(&vm);
}