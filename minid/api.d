/******************************************************************************
This should be the module you import to use MiniD.  This module publicly
imports the following modules: minid.alloc, minid.ex, minid.interpreter,
minid.serialization, minid.types, minid.utils, and minid.vm.

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

import tango.core.Exception;
import tango.stdc.stdlib;

public
{
	import minid.base_alloc;
	import minid.ex;
	import minid.interpreter;
	import minid.stackmanip;
	import minid.types;
	import minid.utils;
	import minid.vm;
}

import minid.stdlib_array;
import minid.stdlib_base;
import minid.stdlib_char;
import minid.stdlib_compiler;
import minid.stdlib_debug;
import minid.stdlib_gc;
import minid.stdlib_hash;
import minid.stdlib_io;
import minid.stdlib_json;
import minid.stdlib_math;
import minid.stdlib_modules;
import minid.stdlib_os;
import minid.stdlib_regexp;
import minid.stdlib_serialization;
import minid.stdlib_stream;
import minid.stdlib_string;
import minid.stdlib_thread;
import minid.stdlib_time;

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
		the D GC of its existence, or else D will blindly collect objects that the MiniD VM
		references.
	memFunc = The memory allocation function to use to allocate this VM.  The VM's allocation
		function will be set to this after creation.  Defaults to DefaultMemFunc, which uses
		the C allocator.
	ctx = An opaque context pointer that will be passed to the memory function at each call.
		The MiniD library does not do anything with this pointer other than store it.

Returns:
	The passed-in pointer.
*/
MDThread* openVM(MDVM* vm, MemFunc memFunc = &DefaultMemFunc, void* ctx = null)
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
enum MDStdlib
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
	Dynamic compilation of MiniD code.
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
	libs = An ORing together of any standard libraries you want to load (see the MDStdlib enum).
		Defaults to MDStdlib.All.
*/
void loadStdlibs(MDThread* t, uint libs = MDStdlib.All)
{
	if(libs & MDStdlib.Array)         ArrayLib.init(t);
	if(libs & MDStdlib.Char)          CharLib.init(t);
	if(libs & MDStdlib.Stream)        StreamLib.init(t);
	if(libs & MDStdlib.IO)            IOLib.init(t);
	if(libs & MDStdlib.Math)          MathLib.init(t);
	if(libs & MDStdlib.OS)            OSLib.init(t);
	if(libs & MDStdlib.Regexp)        RegexpLib.init(t);
	if(libs & MDStdlib.String)        StringLib.init(t);
	if(libs & MDStdlib.Hash)          HashLib.init(t);
	if(libs & MDStdlib.Time)          TimeLib.init(t);
	if(libs & MDStdlib.Debug)         DebugLib.init(t);
	if(libs & MDStdlib.Serialization) SerializationLib.init(t);
	if(libs & MDStdlib.JSON)          JSONLib.init(t);
	if(libs & MDStdlib.Compiler)      CompilerLib.init(t);
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
void closeVM(MDVM* vm)
{
	closeVMImpl(vm);
}