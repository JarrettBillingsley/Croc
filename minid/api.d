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

module minid.api;

public
{
	import minid.alloc;
	import minid.ex;
	import minid.gc;
	import minid.types;
	import minid.utils;
	import minid.vm;
	import minid.interpreter;
}

debug
{
	import tango.text.convert.Format;
	import tango.io.Stdout;
}

import minid.baselib;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

/**
The default memory-allocation function, which uses the C allocator.
*/
public void* DefaultMemFunc(void* ctx, void* p, size_t oldSize, size_t newSize)
{
	if(newSize == 0)
	{
		tango.stdc.stdlib.free(p);
		return null;
	}
	else
	{
		auto ret = tango.stdc.stdlib.realloc(p, newSize);
		
		if(ret is null)
			throw new Exception("OH SHIT OUT OF MEMORY");
			
		return ret;
	}
}

/**
Initialize a VM instance.  This is independent from all other VM instances.  It performs its
own garbage collection, and as far as I know, multiple OS threads can each have their own
VM and manipulate them at the same time without consequence.  (The library has not, however,
been designed with multithreading in mind, so you will have to synchronize access to a single
VM from multiple threads.)

This call also allocates an instance of tango.text.convert.Layout on the D heap, so that the
library can perform formatting without allocating memory later.

Params:
	vm = The VM object to initialize.  $(B This object must have been allocated somewhere in D
		memory) (either on the stack or with 'new').
	memFunc = The memory allocation function to use to allocate this VM.  The VM's allocation
		function will be set to this after creation.  Defaults to DefaultMemFunc, which uses
		the C allocator.
	ctx = An opaque context pointer that will be passed to the memory function at each call.
		The MiniD library does not do anything with this pointer other than store it.

Returns:
	The passed-in pointer.
*/
public MDThread* openVM(MDVM* vm, MemFunc memFunc = &DefaultMemFunc, void* ctx = null)
{
	openVMImpl(vm, memFunc, ctx);

	BaseLib.init(vm.mainThread);

	return mainThread(vm);
}

/**
Closes a VM object and deallocates all memory associated with it.

Normally you won't have to call this since, when the host program exits, all memory associated with
its process will be freed.  However if you need to get rid of a context for some reason (i.e. a daemon
process which spawns and frees contexts as necessary), you must call this to free any data associated
with the VM.

Params:
	vm = The VM to free.  After all memory has been freed, the memory at this pointer will be initialized
		to an "empty" or "dead" VM which can then be passed into openVM.
*/
public void closeVM(MDVM* vm)
{
	assert(vm.mainThread !is null, "Attempting to close an already-closed VM");

	freeAll(vm);

	debug if(vm.alloc.gcCount != 0)
	{
		debug(LEAK_DETECTOR)
		{
			for(auto obj = vm.alloc.gcHead; obj !is null; obj = obj.next)
			{
				auto block = vm.alloc._memBlocks[obj];
				Stdout.formatln("Unfreed object: address 0x{:X}, length {} bytes, type {}", obj, block.len, block.ti);
			}

			foreach(ptr, block; vm.alloc._memBlocks)
				Stdout.formatln("Unfreed block of memory: address 0x{:X}, length {} bytes, type {}", ptr, block.len, block.ti);
		}

		throw new Exception(Format("There are {} uncollected objects!", vm.alloc.gcCount));
	}

	vm.alloc.freeArray(vm.metaTabs);
	vm.alloc.freeArray(vm.metaStrings);
	vm.stringTab.clear(vm.alloc); // can't hurt.
	vm.alloc.freeArray(vm.traceback);

	debug if(vm.alloc.totalBytes != 0)
	{
		debug(LEAK_DETECTOR)
		{
			foreach(ptr, block; vm.alloc._memBlocks)
				Stdout.formatln("Unfreed block of memory: address 0x{:X}, length {} bytes, type {}", ptr, block.len, block.ti);
		}

		throw new Exception(Format("There are {} unfreed bytes!", vm.alloc.totalBytes));
	}

	delete vm.formatter;

	*vm = MDVM.init;
}

align(1) struct FileHeader
{
	uint magic = FOURCC!("MinD");
	uint _version = MiniDVersion;

	version(X86_64)
		ubyte platformBits = 64;
	else
		ubyte platformBits = 32;

	version(BigEndian)
		ubyte endianness = 1;
	else
		ubyte endianness = 0;

	ubyte[6] _padding;

	static const bool SerializeAsChunk = true;
}

static assert(FileHeader.sizeof == 16);

import minid.misc;
import minid.func;
import minid.funcdef;
import tango.io.FileConduit;
import tango.io.protocol.Reader;
import tango.io.Stdout;
import tango.stdc.stdlib;
import tango.stdc.stringz;
public nint loadFunc(MDThread* t, char[] filename)
{
	if(system(toStringz("minidc " ~ filename)) != 0)
		throw new Exception("failcopter");
	scope f = new FileConduit(filename ~ "m", FileConduit.ReadExisting);
	scope r = new Reader(f);
	FileHeader header;
	Deserialize(r, header);
	dchar[] name;
	Deserialize(r, name);
	auto fd = funcdef.deserialize(t.vm, r);
	return pushFunction(t, func.create(t.vm.alloc, t.vm.globals, fd));
}