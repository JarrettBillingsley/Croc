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

import path = std.path;
import file = std.file;
import utf = std.utf;

enum MDStdlib
{
	None =    0,
	Array =   1,
	Char =    2,
	IO =      4,
	Math =    8,
	String = 16,
	Table =  32,
	OS =     64,
	Safe = Array | Char | Math | String | Table,
	All = Array | Char | IO | Math | String | Table | OS,
}

MDState MDInitialize(MDStdlib libs = MDStdlib.All)
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

		MDGlobalState().registerModuleLoader(&MDFileLoader().load);
	}

	return MDGlobalState().mainThread();
}

class MDFileLoader
{
	private static MDFileLoader instance;
	private bool[char[]] mPaths;
	
	private this()
	{

	}
	
	public static MDFileLoader opCall()
	{
		if(instance is null)
			instance = new MDFileLoader();
			
		return instance;
	}
	
	public void addPath(char[] path)
	{
		mPaths[path] = true;
	}

	private MDModuleDef load(dchar[][] name)
	{
		char[][] elements = new char[][name.length];
		
		foreach(i, elem; name)
			elements[i] = utf.toUTF8(elem);

		MDModuleDef ret = tryPath(file.getcwd(), elements);
		
		if(ret)
			return ret;

		foreach(customPath, dummy; mPaths)
		{
			ret = tryPath(customPath, elements);

			if(ret)
				return ret;
		}

		return null;
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
		
		MDModuleDef ret;

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
					ret = compileModule(sourceName);
				else
					ret = MDModuleDef.loadFromFile(moduleName);
			}
			else
				ret = compileModule(sourceName);
		}
		else
		{
			if(file.exists(moduleName))
				ret = MDModuleDef.loadFromFile(moduleName);
		}
		
		return ret;
	}
}