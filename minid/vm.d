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
import minid.moduleslib;
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

/**
Gets the current thread object of the VM, that is, which thread is currently in the running state.
If no threads are in the running state, returns the main thread.
*/
public MDThread* currentThread(MDVM* vm)
{
	return vm.curThread;
}

/**
Find out how many bytes of memory the given VM has allocated.
*/
public uword bytesAllocated(MDVM* vm)
{
	return vm.alloc.totalBytes;
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
	vm.curThread = vm.mainThread;
	vm.globals = namespace.create(vm.alloc, string.create(vm, ""));
	vm.registry = namespace.create(vm.alloc, string.create(vm, "<registry>"));
	vm.formatter = new Layout!(char)();

	auto t = vm.mainThread;

	// _G = _G._G = _G._G._G = _G._G._G._G = ...
	pushNamespace(t, vm.globals);
	newGlobal(t, "_G");

	// Set up the modules module
	ModulesLib.init(t);
}