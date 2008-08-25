module test;

import tango.io.Stdout;
debug import tango.stdc.stdarg; // To make tango-user-base-debug.lib link correctly

import minid.api;

import minid.ast;
import minid.compiler;
import minid.lexer;

// TODO: Object finalizers...

/*
Import:

1.  See if already loaded.

2.  See if that name is taken.

3.  Look for .md and .mdm.  If found, create closure with new namespace env, call.
	if it succeeds, put that namespace in the owning namespace.

4.  Look for custom loader.  If found, call with name of module to get loader func.
	call that with new namespace as env, and if it succeeds, put ns in owning ns.

5.  [Optional] Look for dynlib, same procedure as 4.
*/

void main()
{
	scope(exit) Stdout.flush;

	auto vm = new MDVM;
	auto t = openVM(vm);
	loadStdlibs(t);

	importModule(t, "samples.simple");

	Stdout.newline.format("MiniD using {} bytes before GC, ", bytesAllocated(vm)).flush;
	gc(vm);
	Stdout.formatln("{} bytes after.", bytesAllocated(vm)).flush;

	closeVM(vm);
	delete vm;
}