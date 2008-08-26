/******************************************************************************
License:
Copyright (c) 2008 Jarrett Billingsley

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

module minid.vm;

import tango.io.FilePath;
import tango.stdc.stdlib;
import tango.text.convert.Layout;
import tango.text.convert.Utf;
import tango.text.Util;

import minid.alloc;
import minid.compiler;
import minid.ex;
import minid.gc;
import minid.namespace;
import minid.string;
import minid.interpreter;
import minid.thread;
import minid.types;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

/**
Gets the main thread object of the VM.
*/
public MDThread* mainThread(MDVM* vm)
{
	return vm.mainThread;
}

// ================================================================================================================================================
// Package
// ================================================================================================================================================

package void openVMImpl(MDVM* vm, MemFunc memFunc, void* ctx = null)
{
	assert(vm.mainThread is null, "Attempting to reopen an already-open VM");

	vm.alloc.memFunc = memFunc;
	vm.alloc.ctx = ctx;

	vm.metaTabs = vm.alloc.allocArray!(MDNamespace*)(MDValue.Type.max + 1);
	vm.metaStrings = vm.alloc.allocArray!(MDString*)(MetaNames.length);

	foreach(i, str; MetaNames)
		vm.metaStrings[i] = string.create(vm, str);

	vm.mainThread = thread.create(vm);
	vm.globals = namespace.create(vm.alloc, string.create(vm, ""));
	vm.formatter = new Layout!(char)();

	auto t = vm.mainThread;

	// _G = _G._G = _G._G._G = _G._G._G._G = ...
	pushNamespace(t, vm.globals);
	newGlobal(t, "_G");

	// Set up the modules module
	auto ns = newNamespace(t, "modules");
		pushString(t, "."); fielda(t, ns, "path");
		newTable(t);        fielda(t, ns, "loading");
		newTable(t);        fielda(t, ns, "customLoaders");

		newTable(t);
			// integrate 'modules' itself into the module loading system
			dup(t, ns);
			fielda(t, -2, "modules");
		fielda(t, ns, "loaded");

		pushString(t, "loaders");
			dup(t, ns); newFunctionWithEnv(t, &checkLoaded, "checkLoaded");
			dup(t, ns); newFunctionWithEnv(t, &checkCircular, "checkCircular");
			dup(t, ns); newFunctionWithEnv(t, &customLoad, "customLoad");
			dup(t, ns); newFunctionWithEnv(t, &checkTaken, "checkTaken");
			dup(t, ns); newFunctionWithEnv(t, &loadFiles, "loadFiles");

			version(MDDynLibs)
			{
				dup(t, ns); newFunctionWithEnv(t, &loadDynlib, "loadDynlib");
				newArrayFromStack(t, 6);
			}
			else
				newArrayFromStack(t, 5);
		fielda(t, ns);
	newGlobal(t, "modules");
}

package uword checkLoaded(MDThread* t, uword numParams)
{
	checkStringParam(t, 1);
	pushGlobal(t, "loaded");
	dup(t, 1);
	idx(t, -2);
	return 1;
}

package uword checkCircular(MDThread* t, uword numParams)
{
	checkStringParam(t, 1);
	pushGlobal(t, "loading");
	dup(t, 1);
	idx(t, -2);

	if(!isNull(t, -1))
		throwException(t, "Attempting to import module \"{}\" while it's in the process of being imported; is it being circularly imported?", getString(t, 1));

	return 0;
}

package uword customLoad(MDThread* t, uword numParams)
{
	checkStringParam(t, 1);
	pushGlobal(t, "customLoaders");
	dup(t, 1);
	idx(t, -2);
	
	if(isFunction(t, -1) || isNamespace(t, -1))
		return 1;
		
	return 0;
}

package uword checkTaken(MDThread* t, uword numParams)
{
	auto name = checkStringParam(t, 1);
	
	pushGlobal(t, "_G");

	foreach(segment; name.delimiters("."))
	{
		pushString(t, segment);
		
		if(opin(t, -1, -2))
		{
			field(t, -2);
			
			// TODO: Better error message here
			if(!isNamespace(t, -1))
				throwException(t, "Error loading module \"{}\": conflicts with existing global", name);
				
			insertAndPop(t, -2);
		}
		else
			return 0;
	}

	return 0;
}

// TODO: try to make this not allocate memory?
package uword loadFiles(MDThread* t, uword numParams)
{
	auto name = checkStringParam(t, 1);
	auto pos = name.locatePrior('.');
	char[] packages;
	char[] modName;

	if(pos == name.length)
	{
		packages = "";
		modName = name;
	}
	else
	{
		packages = name[0 .. pos];
		modName = name[pos + 1 .. $];
	}

	// safe since this string is held in the modules namespace
	pushGlobal(t, "path");
	auto paths = getString(t, -1);
	pop(t);

	outerLoop: foreach(path; paths.delimiters(";"))
	{
		scope p = new FilePath(path);

		if(!p.exists())
			continue;

		foreach(piece; packages.delimiters("."))
		{
			p.append(piece);

			if(!p.exists())
				continue outerLoop;
		}

		scope src = new FilePath(FilePath.join(p.toString(), modName ~ ".md"));
		scope bin = new FilePath(FilePath.join(p.toString(), modName ~ ".mdm"));
		
		if(src.exists())
		{
			if(bin.exists())
			{
				if(src.modified() > bin.modified())
				{
					scope c = new Compiler(t);
					c.compileModule(src.toString());
					return 1;
				}
				else
				{
					assert(false, "unimplemented");
				}
			}
			else
			{
				scope c = new Compiler(t);
				c.compileModule(src.toString());
				return 1;
			}
		}
		else if(bin.exists())
		{
			assert(false, "unimplemented");
		}
	}

	return 0;
}