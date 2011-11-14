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
import croc.serialization;
import croc.types;

struct ModulesLib
{
static:

	const Loading = "modules.loading";
	const Prefixes = "modules.prefixes";

	public void init(CrocThread* t)
	{
		newTable(t); setRegistryVar(t, Loading);
		newTable(t); setRegistryVar(t, Prefixes);

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
				dup(t, ns); newFunctionWithEnv(t, 1, &loadFiles,     "loadFiles");
				newArrayFromStack(t, 2);
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
			throwStdException(t, "ImportException", "Attempting to reload module '{}' which has not yet been loaded", name);

		pop(t, 2);
		return commonLoad(t, name);
	}

	package uword commonLoad(CrocThread* t, char[] name)
	{
		// Check to see if we're circularly importing
		auto loading = getRegistryVar(t, Loading);

		if(hasField(t, loading, name))
			throwStdException(t, "ImportException", "Attempting to import module '{}' while it's in the process of being imported; is it being circularly imported?", name);

		pushBool(t, true);
		fielda(t, loading, name);

		scope(exit)
		{
			getRegistryVar(t, Loading);
			pushNull(t);
			fielda(t, -2, name);
			pop(t);
		}

		// Check for name conflicts
		auto loaded = pushGlobal(t, "loaded");

		for(auto idx = name.locate('.'); idx != name.length; idx = name.locate('.', idx + 1))
		{
			if(hasField(t, loaded, name[0 .. idx]))
				throwStdException(t, "ImportException", "Attempting to import module '{}', but there is already a module '{}'", name, name[0 .. idx]);
		}

		getRegistryVar(t, Prefixes);

		if(hasField(t, -1, name))
			throwStdException(t, "ImportException", "Attempting to import module '{}', but other modules use that name as a prefix", name);

		pop(t, 2);

		// Run through the loaders
		auto loaders = pushGlobal(t, "loaders");
		auto num = len(t, -1);

		for(uword i = 0; i < num; i++)
		{
			auto reg = idxi(t, loaders, i);
			pushNull(t);
			pushString(t, name);
			rawCall(t, reg, 1);

			if(isFuncDef(t, reg) || isFunction(t, reg))
			{
				pushGlobal(t, "initModule");
				pushNull(t);
				moveToTop(t, reg);
				pushString(t, name);
				return rawCall(t, -4, 1);
			}
			else if(isNamespace(t, reg))
			{
				setLoaded(t, name, reg);
				return 1;
			}
			else if(!isNull(t, reg))
			{
				pushTypeString(t, reg);
				throwStdException(t, "TypeException", "modules.loaders[{}] expected to return a function, funcdef, namespace, or null, not '{}'", i, getString(t, -1));
			}

			pop(t);
		}

		// Nothing worked :C
		throwStdException(t, "ImportException", "Error loading module '{}': could not find anything to load", name);
		assert(false);
	}

	package uword initModule(CrocThread* t)
	{
		checkAnyParam(t, 1);

		if(!isFunction(t, 1) && !isFuncDef(t, 1))
			paramTypeError(t, 1, "function|funcdef");

		if(isFunction(t, 1) && !funcIsNative(t, 1))
			throwStdException(t, "ValueException", "Function must be a native function");

		auto name = checkStringParam(t, 2);

		// Make the namespace
		auto ns = pushGlobal(t, "_G");
		word firstParent, firstChild;
		char[] childName;
		bool foundSplit = false;

		foreach(segment; name.delimiters("."))
		{
			if(foundSplit)
			{
				newNamespace(t, ns, segment);
				dup(t);
				fielda(t, ns, segment);
				insertAndPop(t, ns);
			}
			else
			{
				if(hasField(t, ns, segment))
				{
					field(t, ns, segment);

					if(!isNamespace(t, -1))
						throwStdException(t, "ImportException", "Error loading module '{}': conflicts with existing global", name);

					insertAndPop(t, ns);
				}
				else
				{
					foundSplit = true;
					firstParent = ns;
					childName = segment;
					firstChild = newNamespace(t, firstParent, childName);
					ns = dup(t, firstChild);
				}
			}
		}
		
		// at this point foundSplit is only true if we had to create new namespaces -- that is, upon first loading, and not during reloading

		if(len(t, ns) > 0)
			clearNamespace(t, ns);

		// Set up the function
		word funcSlot;
		dup(t, ns);

		if(isFunction(t, 1))
		{
			setFuncEnv(t, 1);
			funcSlot = dup(t, 1);
		}
		else
			funcSlot = newFunctionWithEnv(t, 1);

		dup(t, ns);

		// Call the top-level function
		croctry(t,
		{
			rawCall(t, funcSlot, 0);
		},
		(CrocException e, word exSlot)
		{
			auto slot = getStdException(t, "ImportException");
			pushNull(t);
			pushFormat(t, "Error loading module '{}': exception thrown from module's top-level function", name);
			dup(t, exSlot);
			rawCall(t, slot, 1);
			throwException(t);
		});

		// Add it to the loaded table
		setLoaded(t, name, ns);
		pop(t);

		// Add it to the globals
		if(foundSplit)
		{
			assert(stackSize(t) - 1 == firstChild);
			fielda(t, firstParent, childName);
		}

		return 1;
	}

	void setLoaded(CrocThread* t, char[] name, word reg)
	{
		auto loaded = pushGlobal(t, "loaded");
		dup(t, reg);
		fielda(t, loaded, name);
		pop(t);

		auto idx = name.locate('.');

		if(idx != name.length)
		{
			auto prefixes = getRegistryVar(t, Prefixes);

			for(; idx != name.length; idx = name.locate('.', idx + 1))
			{
				pushBool(t, true);
				fielda(t, prefixes, name[0 .. idx]);
			}

			pop(t);
		}
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

			if(src.exists && (!bin.exists || src.modified > bin.modified))
			{
				char[] loadedName = void;
				scope c = new Compiler(t);
				c.compileModule(src.toString(), loadedName);

				if(loadedName != name)
					throwStdException(t, "ImportException", "Import name ({}) does not match name given in module statement ({})", name, loadedName);

				return 1;
			}
			else if(bin.exists)
			{
				char[] loadedName = void;
				scope fc = new File(bin.toString(), File.ReadExisting);
				deserializeModule(t, loadedName, fc);

				if(loadedName != name)
					throwStdException(t, "ImportException", "Import name ({}) does not match name given in module statement ({})", name, loadedName);

				return 1;
			}
		}

		return 0;
	}
}