/******************************************************************************
License:
Copyright (c) 2007 Jarrett Billingsley

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

module minid.minid;

public import minid.types;
public import minid.compiler;
public import minid.utils;

import baselib = minid.baselib;
import stringlib = minid.stringlib;
import arraylib = minid.arraylib;
import tablelib = minid.tablelib;
import mathlib = minid.mathlib;
import charlib = minid.charlib;
import iolib = minid.iolib;
import oslib = minid.oslib;
import regexplib = minid.regexplib;

import path = std.path;
import file = std.file;
import utf = std.utf;
import std.string;

/**
This enumeration is used with the MDInitialize function to specify which standard libraries you
want to load when MiniD is initialized.  The base library is always loaded, so there is no
flag for it.  You can choose which libraries you want to load by ORing together multiple
flags.
*/
enum MDStdlib
{
	/// Nothing but the base library will be loaded if you specify this flag.
	None =      0,
	
	/// Array manipulation.
	Array =     1,

	/// Character classification.
	Char =      2,

	/// Stream-based input and output.
	IO =        4,

	/// Standard math functions.
	Math =      8,

	/// String manipulation.
	String =   16,

	/// Table manipulation.
	Table =    32,
	
	/// OS-specific functionality.
	OS =       64,
	
	/// Regular expressions.
	Regexp =  128,
	
	/// This flag is an OR of Array, Char, Math, String, Table, and Regexp.  It represents all
	/// the libraries which are "safe", i.e. malicious scripts would not be able to use the IO
	/// or OS libraries to do bad things.
	Safe = Array | Char | Math | String | Table | Regexp,
	
	/// All available standard libraries.
	All = Safe | IO | OS,
}

/**
Initializes the global MiniD state and loads any specified standard libraries into it.  This also
registers the default module loader (MDFileLoader) with the global state; this is important for
imports to work properly.

Parameters:
	libs = An ORing together of any standard libraries you want to load (see the MDStdlib enum).
	Defaults to MDStdlib.All.
	
Returns:
	The main thread state associated with the global state.
*/
MDState MDInitialize(uint libs = MDStdlib.All)
{
	if(!MDGlobalState.isInitialized())
	{
		MDGlobalState();

		baselib.init();

		if(libs & MDStdlib.Array)
			arraylib.init();

		if(libs & MDStdlib.Char)
			charlib.init();

		if(libs & MDStdlib.IO)
			iolib.init();

		if(libs & MDStdlib.Math)
			mathlib.init();

		if(libs & MDStdlib.String)
			stringlib.init();

		if(libs & MDStdlib.Table)
			tablelib.init();
			
		if(libs & MDStdlib.OS)
			oslib.init();
			
		if(libs & MDStdlib.Regexp)
			regexplib.init();

		MDGlobalState().registerModuleLoader(&MDFileLoader().load);
	}

	return MDGlobalState().mainThread();
}

/**
The default module loader for MiniD.  It will load modules from the filesystem based on their
name and given search paths.
*/
class MDFileLoader
{
	private static MDFileLoader instance;
	private bool[char[]] mPaths;

	/// This class is a singleton, and this static opCall overload will return the instance.
	public static MDFileLoader opCall()
	{
		if(instance is null)
			instance = new MDFileLoader();

		return instance;
	}
	
	private this()
	{

	}
	
	/// Adds a search path to the list of search paths.
	public void addPath(char[] path)
	{
		mPaths[path] = true;
	}

	private bool load(MDState s, dchar[] name, dchar[] fromModule)
	{
		char[][] elements = split(utf.toUTF8(name), ".");

		MDModuleDef def = tryPath(file.getcwd(), elements);

		if(def is null)
		{
			foreach(customPath, dummy; mPaths)
			{
				def = tryPath(customPath, elements);
	
				if(def !is null)
					break;
			}
		}

		if(def is null)
			return false;

		if(def.mName != name)
		{
			if(fromModule.length == 0)
				throw new MDException("Attempting to load module \"%s\"", name, ", but module declaration says \"%s\"", def.name, "");
			else
				throw new MDException("From module \"%s\"", fromModule, ": Attempting to load module \"%s\"", name, ", but module declaration says \"%s\"", def.name);
		}

		MDNamespace ns = MDGlobalState().registerModule(def, s);
		MDGlobalState().staticInitModule(def, ns, s);
		return true;
	}

	private MDModuleDef tryPath(char[] path, char[][] elems)
	{
		if(!file.exists(path))
			return null;

		foreach(elem; elems[0 .. $ - 1])
		{
			path = .path.join(path, elem);
			
			if(!file.exists(path))
				return null;
		}

		path = .path.join(path, elems[$ - 1]);

		char[] sourceName = path ~ ".md";
		char[] moduleName = path ~ ".mdm";
		
		MDModuleDef def = null;

		if(file.exists(sourceName))
		{
			if(file.exists(moduleName))
			{
				long sourceTime;
				long moduleTime;
				long dummy;

				file.getTimes(sourceName, dummy, dummy, sourceTime);
				file.getTimes(moduleName, dummy, dummy, moduleTime);
				
				if(sourceTime > moduleTime)
					def = compileModule(sourceName);
				else
					def = MDModuleDef.loadFromFile(moduleName);
			}
			else
				def = compileModule(sourceName);
		}
		else
		{
			if(file.exists(moduleName))
				def = MDModuleDef.loadFromFile(moduleName);
		}
		
		return def;
	}
}

version(MDNoDynLibs) {} else
{
/*
 * Copyright (c) 2005-2006 Derelict Developers
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 * * Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 *
 * * Neither the names 'Derelict', 'DerelictUtil', nor the names of its contributors
 *   may be used to endorse or promote products derived from this software
 *   without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

version(linux)
	version = Dlfcn;

version(darwin)
	version = Dlfcn;
else version(Unix)
	version = Dlfcn;

class DynLib
{
	private void* mHandle;
	private dchar[] mName;
	private static bool[DynLib] DynLibs;
	private static DynLib[dchar[]] LibsByName;

	static ~this()
	{
		foreach(lib; DynLibs.keys)
			lib.unload();
	}

	private this(void* handle, dchar[] name)
	{
		mHandle = handle;
		mName = name;
		DynLibs[this] = true;
		LibsByName[name] = this;
	}

	public dchar[] name()
	{
		return mName;
	}

	version(Windows)
		import std.c.windows.windows;
	else version(Dlfcn)
	{
		version(linux)
			private import std.c.linux.linux;
		else
		{
			extern(C)
			{
				// From <dlfcn.h>
				// See http://www.opengroup.org/onlinepubs/007908799/xsh/dlsym.html
				const int RTLD_NOW = 2;
				void* dlopen(char* file, int mode);
				int dlclose(void* handle);
				void *dlsym(void* handle, char* name);
				char* dlerror();
			}
		}
	}
	else
		static assert(false, "MiniD cannot use dynamic libraries -- unsupported platform");
		
	public static DynLib load(dchar[] libName)
	{
		if(auto l = libName in LibsByName)
			return *l;

		version(Windows)
			HMODULE hlib = LoadLibraryA(toStringz(utf.toUTF8(libName)));
		else version(Dlfcn)
			void* hlib = dlopen(toStringz(utf.toUTF8(libName)), RTLD_NOW);

		if(hlib is null)
			throw new MDException("Could not load dynamic library '%s'", libName);

		return new DynLib(hlib, libName);
	}

	public void unload()
	{
		version(Windows)
			FreeLibrary(cast(HMODULE)mHandle);
		else version(Dlfcn)
			dlclose(mHandle);

		mHandle = null;
		LibsByName.remove(mName);
		DynLibs.remove(this);
	}

	public void* getProc(char[] procName)
	{
		version(Windows)
			void* proc = GetProcAddress(cast(HMODULE)mHandle, toStringz(procName));
		else version(Dlfcn)
			void* proc = dlsym(mHandle, toStringz(procName));

		if(proc is null)
			throw new MDException("Could not get function '%s' from dynamic library '%s'", procName, mName);

		return proc;
	}
}

class MDDynLibLoader
{
	private static MDDynLibLoader instance;

	public static MDDynLibLoader opCall()
	{
		if(instance is null)
			instance = new MDDynLibLoader();

		return instance;
	}

	private this()
	{

	}
}

}