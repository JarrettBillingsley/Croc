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

module croc.vm;

import tango.text.convert.Float;
import tango.text.convert.Format;
import tango.text.convert.Layout;
import tango.text.Util;

alias tango.text.convert.Float.format Float_format;
alias tango.text.convert.Float.truncate Float_truncate;

debug import tango.io.Stdout;

import croc.api_interpreter;
import croc.api_stack;
import croc.base_alloc;
import croc.base_metamethods;
import croc.interpreter;
import croc.types;
import croc.types_class;
import croc.types_namespace;
import croc.types_thread;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

/**
Gets the main thread object of the VM.
*/
CrocThread* mainThread(CrocVM* vm)
{
	return vm.mainThread;
}

/**
Gets the current thread object of the VM, that is, which thread is currently in the running state.
If no threads are in the running state, returns the main thread.
*/
CrocThread* currentThread(CrocVM* vm)
{
	return vm.curThread;
}

/**
Find out how many bytes of memory the given VM has allocated.
*/
uword bytesAllocated(CrocVM* vm)
{
	return vm.alloc.totalBytes;
}

// ================================================================================================================================================
// Package
// ================================================================================================================================================

package:

void openVMImpl(CrocVM* vm, MemFunc memFunc, void* ctx = null)
{
	assert(vm.mainThread is null, "Attempting to reopen an already-open VM");

	vm.alloc.memFunc = memFunc;
	vm.alloc.ctx = ctx;

	disableGC(vm);

	vm.metaTabs = vm.alloc.allocArray!(CrocNamespace*)(CrocValue.Type.max + 1);
	vm.mainThread = thread.create(vm);
	auto t = vm.mainThread;

	vm.metaStrings = vm.alloc.allocArray!(CrocString*)(MetaNames.length + 1);

	foreach(i, str; MetaNames)
		vm.metaStrings[i] = createString(t, str);

	vm.ctorString = createString(t, "constructor");
	vm.metaStrings[$ - 1] = vm.ctorString;

	vm.curThread = vm.mainThread;
	vm.globals = namespace.create(vm.alloc, createString(t, ""));
	vm.registry = namespace.create(vm.alloc, createString(t, "<registry>"));
	vm.formatter = new CustomLayout();

	// _G = _G._G = _G._G._G = _G._G._G._G = ...
	push(t, CrocValue(vm.globals));
	newGlobal(t, "_G");

	// Throwable
	vm.throwable = classobj.create(t.vm.alloc, createString(t, "Throwable"), null);
	push(t, CrocValue(vm.throwable));
	newGlobal(t, "Throwable");
}

void closeVMImpl(CrocVM* vm)
{
	assert(vm.mainThread !is null, "Attempting to close an already-closed VM");

	freeAll(vm);
	vm.alloc.freeArray(vm.metaTabs);
	vm.alloc.freeArray(vm.metaStrings);
	vm.stringTab.clear(vm.alloc);
	vm.weakRefTab.clear(vm.alloc);
	vm.allThreads.clear(vm.alloc);
	vm.refTab.clear(vm.alloc);
	vm.stdExceptions.clear(vm.alloc);
	vm.roots[0].clear(vm.alloc);
	vm.roots[1].clear(vm.alloc);
	vm.cycleRoots.clear(vm.alloc);
	vm.toFree.clear(vm.alloc);
	vm.toFinalize.clear(vm.alloc);
	vm.alloc.cleanup();

	if(vm.alloc.totalBytes != 0)
	{
		debug(CROC_LEAK_DETECTOR)
		{
			if(vm.alloc._rcBlocks.length)
			{
				Stdout.formatln("Unfreed RC blocks:");

				foreach(ptr, block; vm.alloc._rcBlocks)
					Stdout.formatln("\taddress {:x8}, refcount {}, flags {:b9}, length {} bytes, type {}", ptr, (cast(GCObject*)ptr).refCount, (cast(GCObject*)ptr).gcflags, block.len, block.ti);
			}

			if(vm.alloc._rawBlocks.length)
			{
				Stdout.formatln("Unfreed raw blocks:");

				foreach(ptr, block; vm.alloc._rawBlocks)
					Stdout.formatln("\taddress {:x8}, length {} bytes, type {}", ptr, block.len, block.ti);
			}
		}

		throw new Exception(Format("There are {} total unfreed bytes!", vm.alloc.totalBytes));
	}

	debug(CROC_LEAK_DETECTOR)
	{
		vm.alloc._rcBlocks.clear(vm.alloc);
		vm.alloc._rawBlocks.clear(vm.alloc);
		vm.alloc._nurseryBlocks.clear(vm.alloc);
	}

	delete vm.formatter;
	*vm = CrocVM.init;
}

void disableGC(CrocVM* vm)
{
	vm.alloc.gcDisabled++;
}

void enableGC(CrocVM* vm)
{
	vm.alloc.gcDisabled--;
	assert(vm.alloc.gcDisabled != -1);
}

class CustomLayout : Layout!(char)
{
	override char[] floater(char[] output, real v, char[] format)
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
				return Float_format(output, v, number, (style == 'e' || style == 'E') ? 0 : 10);
		}

		if(style == 'e' || style == 'E')
			return Float_format(output, v, 2, 0);
		else
		{
			auto str = Float_format(output, v, 6);
			auto tmp = Float_truncate(str);

			if(tmp.locate('.') == tmp.length && str.length >= tmp.length + 2)
				tmp = str[0 .. tmp.length + 2];

			return tmp;
		}
	}
}