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

import tango.stdc.stdlib;
import tango.text.convert.Layout;

import minid.alloc;
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
	vm.formatter = new Layout!(dchar)();

	auto mt = vm.mainThread;

	// _G = _G._G = _G._G._G = _G._G._G._G = ...
	pushNamespace(mt, vm.globals);
	newGlobal(mt, "_G");
}