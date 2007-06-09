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

version(MDDynLibs)
{
	pragma(msg, "MiniD's dynamic library support is not implemented.\nPlease compile without the MDDynLibs version set.");
	static assert(false);
}

public import minid.compiler;
public import minid.types;
public import minid.utils;

import arraylib = minid.arraylib;
import baselib = minid.baselib;
import charlib = minid.charlib;
import iolib = minid.iolib;
import mathlib = minid.mathlib;
import oslib = minid.oslib;
import regexplib = minid.regexplib;
import stringlib = minid.stringlib;
import tablelib = minid.tablelib;

import tango.io.FilePath;

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
		MDGlobalState().tryPath = &tryPath;
		version(MDDynLibs) MDGlobalState().tryDynLibPath = &tryDynLibPath;

		baselib.init();

		if(libs & MDStdlib.Array)
			arraylib.init();

		if(libs & MDStdlib.Char)
			charlib.init();

		if(libs & MDStdlib.IO)
			iolib.init();

		if(libs & MDStdlib.Math)
			mathlib.init();
			
		if(libs & MDStdlib.OS)
			oslib.init();
			
		if(libs & MDStdlib.Regexp)
			regexplib.init();

		if(libs & MDStdlib.String)
			stringlib.init();

		if(libs & MDStdlib.Table)
			tablelib.init();
	}

	return MDGlobalState().mainThread();
}

private MDModuleDef tryPath(FilePath path, char[][] elems)
{
	if(!path.exists())
		return null;

	foreach(elem; elems[0 .. $ - 1])
	{
		path.set(FilePath.join(path.toUtf8(), elem), true);

		if(!path.exists())
			return null;
	}

	scope sourceName = new FilePath(FilePath.join(path.toUtf8(), elems[$ - 1] ~ ".md"));
	scope binaryName = new FilePath(FilePath.join(path.toUtf8(), elems[$ - 1] ~ ".mdm"));

	MDModuleDef def = null;

	if(sourceName.exists())
	{
		if(binaryName.exists())
		{
			if(sourceName.modified() > binaryName.modified())
				def = compileModule(sourceName.toUtf8());
			else
				def = MDModuleDef.loadFromFile(binaryName.toUtf8());
		}
		else
			def = compileModule(sourceName.toUtf8());
	}
	else
	{
		if(binaryName.exists())
			def = MDModuleDef.loadFromFile(binaryName.toUtf8());
	}

	return def;
}

version(MDDynLibs)
{
	private char[] tryDynLibPath(char[] path, char[][] elems)
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
		
		char[] fileName = path ~ ".dll";
		
		if(file.exists(fileName))
			return fileName;
			
		return null;
	} 
}