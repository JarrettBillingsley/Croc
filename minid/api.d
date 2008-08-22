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
import minid.charlib;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

/**
The default memory-allocation function, which uses the C allocator.
*/
public void* DefaultMemFunc(void* ctx, void* p, uword oldSize, uword newSize)
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
	vm.alloc.gcLimit = vm.alloc.totalBytes;
	return mainThread(vm);
}

/**
This enumeration is used with the NewContext function to specify which standard libraries you
want to load into the new context.  The base library is always loaded, so there is no
flag for it.  You can choose which libraries you want to load by ORing together multiple
flags.
*/
public enum MDStdlib
{
	/**
	Nothing but the base library will be loaded if you specify this flag.
	*/
	None =      0,

	/**
	Array manipulation.
	*/
	Array =     1,

	/**
	Character classification.
	*/
	Char =      2,

	/**
	Stream-based input and output.
	*/
	IO =        4,

	/**
	Standard math functions.
	*/
	Math =      8,

	/**
	String manipulation.
	*/
	String =   16,

	/**
	Table manipulation.
	*/
	Table =    32,

	/**
	OS-specific functionality.
	*/
	OS =       64,

	/**
	Regular expressions.
	*/
	Regexp =  128,

	/**
	This flag is an OR of Array, Char, Math, String, Table, and Regexp.  It represents all
	the libraries which are "safe", i.e. malicious scripts would not be able to use the IO
	or OS libraries to do bad things.
	*/
	Safe = Array | Char | Math | String | Table | Regexp,

	/**
	All available standard libraries.
	*/
	All = Safe | IO | OS,
}

/**
Load the standard libraries into the context of the given thread.  

Params:
	libs = An ORing together of any standard libraries you want to load (see the MDStdlib enum).
		Defaults to MDStdlib.All.
*/
public void loadStdlibs(MDThread* t, uint libs = MDStdlib.All)
{
// 	if(libs & MDStdlib.Array)
// 		ArrayLib.init(ret);

	if(libs & MDStdlib.Char)
		CharLib.init(t);

// 	if(libs & MDStdlib.IO)
// 		IOLib.init(ret);
// 
// 	if(libs & MDStdlib.Math)
// 		MathLib.init(ret);
// 
// 	if(libs & MDStdlib.OS)
// 		OSLib.init(ret);
// 
// 	if(libs & MDStdlib.Regexp)
// 		RegexpLib.init(ret);
// 
// 	if(libs & MDStdlib.String)
// 		StringLib.init(ret);
// 
// 	if(libs & MDStdlib.Table)
// 		TableLib.init(ret);
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
	vm.alloc.freeArray(vm.metaTabs);
	vm.alloc.freeArray(vm.metaStrings);
	vm.stringTab.clear(vm.alloc);
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
	
	debug(LEAK_DETECTOR)
		vm.alloc._memBlocks.clear(vm.alloc);

	delete vm.formatter;
	*vm = MDVM.init;
}