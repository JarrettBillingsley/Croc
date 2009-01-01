/******************************************************************************
This module contains some VM-related functionality, and exists partly to avoid
circular dependencies.

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

import Float = tango.text.convert.Float;
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
	vm.formatter = new CustomLayout();

	auto t = vm.mainThread;

	// _G = _G._G = _G._G._G = _G._G._G._G = ...
	pushNamespace(t, vm.globals);
	newGlobal(t, "_G");

	// Set up the modules module
	ModulesLib.init(t);
}

package class CustomLayout : Layout!(char)
{
	protected override char[] floater(char[] output, real v, char[] format)
	{
		char style = 'f';

		// extract formatting style and decimal-places
		if(format.length)
		{
			uint number;
			auto p = format.ptr;
			auto e = p + format.length;
			style = *p;

			while(++p < e)
			{
				if(*p >= '0' && *p <= '9')
					number = number * 10 + *p - '0';
				else
					break;
			}

			if(p - format.ptr > 1)
				return Float.format(output, v, number, (style == 'e' || style == 'E') ? 0 : 10);
		}

		if(style == 'e' || style == 'E')
			return Float.format(output, v, 2, 0);
		else
		{
			auto str = Float.format(output, v, 6);
			auto tmp = Float.truncate(str);

			if(tmp.locate('.') == tmp.length && str.length >= tmp.length + 2)
				tmp = str[0 .. tmp.length + 2];

			return tmp;
		}
	}
}