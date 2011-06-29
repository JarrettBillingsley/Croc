/******************************************************************************
This module contains the 'modules' standard library, which is part of the
base library.

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

module croc.stdlib_modules;

import tango.io.device.File;
import tango.io.FilePath;
import tango.text.Util;

import croc.api_interpreter;
import croc.api_stack;
import croc.compiler;
import croc.ex;
import croc.serialization_simple;
import croc.types;

struct ModulesLib
{
static:
	public void init(CrocThread* t)
	{
		newTable(t); setRegistryVar(t, "modules.loading");

		auto ns = newNamespace(t, "modules");
			pushString(t, "."); fielda(t, ns, "path");
			newTable(t);        fielda(t, ns, "customLoaders");
			dup(t, ns); newFunctionWithEnv(t, 1, &load,       "load");       fielda(t, ns, "load");
			dup(t, ns); newFunctionWithEnv(t, 1, &reload,     "reload");     fielda(t, ns, "reload");
			dup(t, ns); newFunctionWithEnv(t, 2, &initModule, "initModule"); fielda(t, ns, "initModule");
			dup(t, ns); newFunctionWithEnv(t,    &runMain,    "runMain");    fielda(t, ns, "runMain");

			newTable(t);
				// integrate 'modules' itself into the module loading system
				dup(t, ns);
				fielda(t, -2, "modules");
			fielda(t, ns, "loaded");

			pushString(t, "loaders");
				dup(t, ns); newFunctionWithEnv(t, 1, &customLoad,    "customLoad");
				dup(t, ns); newFunctionWithEnv(t, 1, &checkTaken,    "checkTaken");
				dup(t, ns); newFunctionWithEnv(t, 1, &loadFiles,     "loadFiles");

				version(CrocDynLibs)
				{
					dup(t, ns); newFunctionWithEnv(t, 1, &loadDynlib, "loadDynlib");
					newArrayFromStack(t, 4);
				}
				else
					newArrayFromStack(t, 3);
			fielda(t, ns);
		newGlobal(t, "modules");
	}

	package uword load(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);

		pushGlobal(t, "loaded");
		dup(t, 1);
		idx(t, -2);

		if(isNamespace(t, -1))
			return 1;

		pop(t, 2);
		return commonLoad(t, name);
	}

	package uword reload(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);

		pushGlobal(t, "loaded");
		dup(t, 1);
		idx(t, -2);

		if(isNull(t, -1))
			throwException(t, "Attempting to reload module '{}' which has not yet been loaded", name);

		pop(t, 2);
		return commonLoad(t, name);
	}

	package uword commonLoad(CrocThread* t, char[] name)
	{
		checkCircular(t, name);

		scope(exit)
		{
			getRegistryVar(t, "modules.loading");
			pushNull(t);
			fielda(t, -2, name);
			pop(t);
		}

		auto loaders = pushGlobal(t, "loaders");
		auto num = len(t, -1);

		for(uword i = 0; i < num; i++)
		{
			auto reg = pushInt(t, i);
			idx(t, loaders);
			pushNull(t);
			pushString(t, name);
			rawCall(t, reg, 1);

			if(isFuncDef(t, -1) || isFunction(t, -1))
			{
				pushGlobal(t, "initModule");
				swap(t);
				pushNull(t);
				swap(t);
				pushString(t, name);
				return rawCall(t, -4, 1);
			}
			else if(isNamespace(t, -1))
			{
				pushGlobal(t, "loaded");
				pushString(t, name);

				if(!opin(t, -1, -2))
				{
					dup(t, -3);
					idxa(t, -3);
					pop(t);
				}
				else
					pop(t, 2);

				return 1;
			}

			pop(t);
		}

		throwException(t, "Error loading module '{}': could not find anything to load", name);
		assert(false);
	}

	package uword initModule(CrocThread* t)
	{
		checkAnyParam(t, 1);

		if(!isFunction(t, 1) && !isFuncDef(t, 1))
			paramTypeError(t, 1, "function|funcdef");

		if(isFunction(t, 1) && !funcIsNative(t, 1))
			throwException(t, "Function must be a native function");

		auto name = checkStringParam(t, 2);

		// Make the namespace
		auto ns = pushGlobal(t, "_G");

		foreach(segment; name.delimiters("."))
		{
			pushString(t, segment);

			if(opin(t, -1, ns))
			{
				field(t, ns);

				if(!isNamespace(t, -1))
					throwException(t, "Error loading module \"{}\": conflicts with existing global", name);
			}
			else
			{
				pop(t);
				newNamespace(t, ns, segment);
				dup(t);
				fielda(t, ns, segment);
			}

			insertAndPop(t, ns);
		}

		if(len(t, ns) > 0)
			clearNamespace(t, ns);

		if(isFunction(t, 1))
		{
			dup(t, ns);
			setFuncEnv(t, 1);
			dup(t, 1);
			dup(t, ns);
			rawCall(t, -2, 0);
		}
		else
		{
			// Create the function and call it with its namespace as 'this'
			dup(t, ns);
			auto func = newFunctionWithEnv(t, 1);
			dup(t, ns);
			rawCall(t, func, 0);
		}

		// Add it to the loaded table
		auto loaded = pushGlobal(t, "loaded");
		pushString(t, name);
		dup(t, ns);
		idxa(t, loaded);
		pop(t);

		return 1;
	}

	uword runMain(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Namespace);

		if(hasField(t, 1, "main"))
		{
			auto main = field(t, 1, "main");

			if(isFunction(t, main))
			{
				insert(t, 1);
				rawCall(t, 1, 0);
			}
		}

		return 0;
	}

	package uword customLoad(CrocThread* t)
	{
		checkStringParam(t, 1);
		pushGlobal(t, "customLoaders");
		dup(t, 1);
		idx(t, -2);

		if(isFunction(t, -1) || isNamespace(t, -1) || isFuncDef(t, -1))
			return 1;

		return 0;
	}

	package uword checkTaken(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);

		pushGlobal(t, "_G");

		foreach(segment; name.delimiters("."))
		{
			pushString(t, segment);

			if(opin(t, -1, -2))
			{
				field(t, -2);

				if(!isNamespace(t, -1))
					throwException(t, "Error loading module \"{}\": conflicts with existing global", name);

				insertAndPop(t, -2);
			}
			else
				return 0;
		}

		return 0;
	}

	package uword loadFiles(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		auto pos = name.locatePrior('.');
		char[] packages;
		char[] modName;

		if(pos == name.length)
		{
			packages = "";
			modName = name;
		}
		else
		{
			packages = name[0 .. pos];
			modName = name[pos + 1 .. $];
		}

		// safe since this string is held in the modules namespace
		pushGlobal(t, "path");
		auto paths = getString(t, -1);
		pop(t);

		outerLoop: foreach(path; paths.delimiters(";"))
		{
			// TODO: try to make this not allocate memory?  Is this possible?
			scope p = new FilePath(path);

			if(!p.exists())
				continue;

			foreach(piece; packages.delimiters("."))
			{
				p.append(piece);

				if(!p.exists())
					continue outerLoop;
			}

			scope src = new FilePath(FilePath.join(p.toString(), modName ~ ".croc"));
			scope bin = new FilePath(FilePath.join(p.toString(), modName ~ ".croco"));

			if(src.exists())
			{
				if(bin.exists())
				{
					if(src.modified() > bin.modified())
					{
						scope c = new Compiler(t);
						c.compileModule(src.toString());
						return 1;
					}
					else
					{
						scope fc = new File(bin.toString(), File.ReadExisting);
						deserializeModule(t, fc);
						return 1;
					}
				}
				else
				{
					scope c = new Compiler(t);
					c.compileModule(src.toString());
					return 1;
				}
			}
			else if(bin.exists())
			{
				scope fc = new File(bin.toString(), File.ReadExisting);
				deserializeModule(t, fc);
				return 1;
			}
		}

		return 0;
	}

	private void checkCircular(CrocThread* t, char[] name)
	{
		getRegistryVar(t, "modules.loading");
		field(t, -1, name);

		if(!isNull(t, -1))
			throwException(t, "Attempting to import module \"{}\" while it's in the process of being imported; is it being circularly imported?", name);

		pop(t);
		pushBool(t, true);
		fielda(t, -2, name);
		pop(t);
	}
}