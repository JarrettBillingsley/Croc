/******************************************************************************
This should be the module you import to use Croc.  This module publicly
imports the following modules: croc.base_alloc, croc.ex croc.interpreter,
croc.stackmanip, croc.types, croc.utils and croc.vm.

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

module croc.api;

import tango.core.Exception;
import tango.stdc.stdlib;

public
{
	import croc.api_interpreter;
	import croc.api_stack;
	import croc.base_alloc;
	import croc.ex;
	import croc.types;
	import croc.utils;
	import croc.vm;
}

import croc.stdlib_array;
import croc.stdlib_base;
import croc.stdlib_char;
import croc.stdlib_compiler;
import croc.stdlib_debug;
import croc.stdlib_gc;
import croc.stdlib_hash;
import croc.stdlib_io;
import croc.stdlib_json;
import croc.stdlib_math;
import croc.stdlib_modules;
import croc.stdlib_os;
import croc.stdlib_regexp;
import croc.stdlib_serialization;
import croc.stdlib_stream;
import croc.stdlib_string;
import croc.stdlib_thread;
import croc.stdlib_time;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

/**
The default memory-allocation function, which uses the C allocator.
*/
void* DefaultMemFunc(void* ctx, void* p, uword oldSize, uword newSize)
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
			onOutOfMemoryError();
			
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
		memory) (either on the stack or with 'new').  If it's not in D's memory, you must inform
		the D GC of its existence, or else D will blindly collect objects that the Croc VM
		references.
	memFunc = The memory allocation function to use to allocate this VM.  The VM's allocation
		function will be set to this after creation.  Defaults to DefaultMemFunc, which uses
		the C allocator.
	ctx = An opaque context pointer that will be passed to the memory function at each call.
		The Croc library does not do anything with this pointer other than store it.

Returns:
	The passed-in pointer.
*/
CrocThread* openVM(CrocVM* vm, MemFunc memFunc = &DefaultMemFunc, void* ctx = null)
{
	openVMImpl(vm, memFunc, ctx);
	auto t = mainThread(vm);

	// Set up the modules module.  This has to be done before any other modules
	// are initialized for obvious reasons.
	ModulesLib.init(t);
	BaseLib.init(t);
	GCLib.init(t);
	ThreadLib.init(t);
	vm.alloc.gcLimit = vm.alloc.totalBytes;
	return t;
}

/**
This enumeration is used with the NewContext function to specify which standard libraries you
want to load into the new context.  The base library is always loaded, so there is no
flag for it.  You can choose which libraries you want to load by ORing together multiple
flags.
*/
enum CrocStdlib
{
	/**
	Nothing but the base library will be loaded if you specify this flag.
	*/
	None =      0,

	/**
	_Array manipulation.
	*/
	Array =     1,

	/**
	Character classification.
	*/
	Char =      2,

	/**
	File system manipulation and file access.  Requires the stream lib.
	*/
	IO =        4,

	/**
	Standard math functions.
	*/
	Math =      8,

	/**
	_String manipulation.
	*/
	String =   16,

	/**
	_Hash (table and namespace) manipulation.
	*/
	Hash =    32,

	/**
	_OS-specific functionality.  Requires the stream lib.
	*/
	OS =       64,

	/**
	Regular expressions.
	*/
	Regexp =  128,

	/**
	_Time functions.
	*/
	Time = 256,

	/**
	Streamed IO classes.
	*/
	Stream = 512,

	/**
	Debugging introspection and hooks.
	*/
	Debug = 1024,
	
	/**
	(De)serialization of complex object graphs.
	*/
	Serialization = 2048,
	
	/**
	JSON reading and writing.
	*/
	JSON = 4096,
	
	/**
	Dynamic compilation of Croc code.
	*/
	Compiler = 8192,

	/**
	This flag is an OR of all the libraries which are "safe", which is everything except the IO, OS,
	and Debug libraries.
	*/
	Safe = Array | Char | Math | String | Hash | Regexp | Stream | Time | Serialization | JSON | Compiler,

	/**
	_All available standard libraries except the debug library.
	*/
	All = Safe | IO | OS,

	/**
	All available standard libraries including the debug library.
	*/
	ReallyAll = All | Debug
}

/**
Load the standard libraries into the context of the given thread.

Params:
	libs = An ORing together of any standard libraries you want to load (see the CrocStdlib enum).
		Defaults to CrocStdlib.All.
*/
void loadStdlibs(CrocThread* t, uint libs = CrocStdlib.All)
{
	if(libs & CrocStdlib.Array)         ArrayLib.init(t);
	if(libs & CrocStdlib.Char)          CharLib.init(t);
	if(libs & CrocStdlib.Stream)        StreamLib.init(t);
	if(libs & CrocStdlib.IO)            IOLib.init(t);
	if(libs & CrocStdlib.Math)          MathLib.init(t);
	if(libs & CrocStdlib.OS)            OSLib.init(t);
	if(libs & CrocStdlib.Regexp)        RegexpLib.init(t);
	if(libs & CrocStdlib.String)        StringLib.init(t);
	if(libs & CrocStdlib.Hash)          HashLib.init(t);
	if(libs & CrocStdlib.Time)          TimeLib.init(t);
	if(libs & CrocStdlib.Debug)         DebugLib.init(t);
	if(libs & CrocStdlib.Serialization) SerializationLib.init(t);
	if(libs & CrocStdlib.JSON)          JSONLib.init(t);
	if(libs & CrocStdlib.Compiler)      CompilerLib.init(t);
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
void closeVM(CrocVM* vm)
{
	closeVMImpl(vm);
}