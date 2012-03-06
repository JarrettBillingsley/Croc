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
import croc.stdlib_utils;
import croc.types;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initModulesLib(CrocThread* t)
{
	newTable(t); setRegistryVar(t, Loading);
	newTable(t); setRegistryVar(t, Prefixes);

	auto ns = newNamespace(t, "modules");

	// doing this stuff manually because we haven't created the module system yet, duh
	pushString(t, "."); fielda(t, ns, "path");
	newTable(t);        fielda(t, ns, "customLoaders");
	dup(t, ns); newFunctionWithEnv(t, 1, &_load,       "load");       fielda(t, ns, "load");
	dup(t, ns); newFunctionWithEnv(t, 1, &_reload,     "reload");     fielda(t, ns, "reload");
	dup(t, ns); newFunctionWithEnv(t, 2, &_initModule, "initModule"); fielda(t, ns, "initModule");
	dup(t, ns); newFunctionWithEnv(t,    &_runMain,    "runMain");    fielda(t, ns, "runMain");

	newTable(t);
		// integrate 'modules' itself into the module loading system
		dup(t, ns);
		fielda(t, -2, "modules");
	fielda(t, ns, "loaded");

	pushString(t, "loaders");
		dup(t, ns); newFunctionWithEnv(t, 1, &_customLoad,    "customLoad");
		dup(t, ns); newFunctionWithEnv(t, 1, &_loadFiles,     "loadFiles");
		newArrayFromStack(t, 2);
	fielda(t, ns);

	newGlobal(t, "modules");
}

version(CrocBuiltinDocs) void docModulesLib(CrocThread* t)
{
	pushGlobal(t, "modules");

	scope doc = new CrocDoc(t, __FILE__);
	doc.push(Docs("module", "Modules Library",
	"This library forms the core of the Croc module system. When you use an import statement in Croc, it's simply
	syntactic sugar for a call to `modules.load.` All of the semantics of imports and such are handled by the
	functions and data structures in here. At a high level, the module system is just a mechanism that maps from
	strings (module names) to namespaces. The default behavior of this library is just that -- a default. You
	can customize the behavior of module importing to your specific needs."));

	docFields(t, doc, _docTables);
	doc.pop(-1);
	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

const Loading = "modules.loading";
const Prefixes = "modules.prefixes";

uword _load(CrocThread* t)
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

uword _reload(CrocThread* t)
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

uword commonLoad(CrocThread* t, char[] name)
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

uword _initModule(CrocThread* t)
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

	// Add it to the globals
	if(foundSplit)
	{
		dup(t, firstChild);
		fielda(t, firstParent, childName);
	}

	dup(t, ns);
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

uword _runMain(CrocThread* t)
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

uword _customLoad(CrocThread* t)
{
	checkStringParam(t, 1);
	pushGlobal(t, "customLoaders");
	dup(t, 1);
	idx(t, -2);

	if(isFunction(t, -1) || isNamespace(t, -1) || isFuncDef(t, -1))
		return 1;

	return 0;
}

uword _loadFiles(CrocThread* t)
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

version(CrocBuiltinDocs) const Docs[] _docTables =
[
	{kind: "variable", name: "path", docs:
	`This is just a variable that holds a string. This string contains the paths that are used when searching for
	modules. The paths are specified using forward slashes to separate path components regardless of the underlying
	OS, and semicolons to separate paths.

	By default, this variable holds the string ".", which just means "the current directory". If you changed it to
	something like ".;imports/current", when you tried to load a module "foo.bar", it would look for "./foo/bar.croc"
	and "imports/current/foo/bar.croc" in that order.`,
	extra: [Extra("protection", "global"), Extra("value", `"."`)]},

	{kind: "variable", name: "loaded", docs:
	"This is a table that holds all currently-loaded modules. The keys are the module names as strings, and the values
	are the corresponding modules' namespaces. This is the table that `modules.load` will check in first before trying
	to look for a loader.",
	extra: [Extra("protection", "global")]},

	{kind: "variable", name: "customLoaders", docs:
	"This is a table which you are free to use. It maps from module names (strings) to functions or namespaces. This
	table is used by the `customLoad` step in `modules.loaders`; see it for more information.",
	extra: [Extra("protection", "global")]},

	{kind: "variable", name: "loaders", docs:
	"This is an important variable. This holds the array of ''module loaders'', which are functions which take the name
	of a module that's being loaded, and return one of four things: nothing or null, to indicate that the next loader
	should be tried; a namespace, which is assumed to be the module's namespace; a native function, which is assumed to
	be a native module's ''loader''; or a funcdef, which is assumed to be the function definition of the top-level
	function of a Croc module.

	By default, two loaders are in this array, in the following order:
 * '''`customLoad`''': This looks in the `modules.customLoaders` table for a loader function or namespace. If one exists, it just
   returns that; otherwise, returns null. You can use this behavior to set up custom loaders for your own modules: just put the
   loader in the `modules.customLoaders` table, and when it's imported, it'll have the loader function or namespace used for it.
   This is exactly how the standard library loaders work.
 * '''`loadFiles`''': This looks for files to load and loads them. As explained in `modules.path`, the paths in that variable will
   be tried one by one until a file is found or they are all exhausted. This looks for both script files (`.croc`) and compiled
   modules (`.croco`). If it finds just a script file, it will compile it and return the resulting top-level funcdef. If it finds
   just a compiled module, it will load it and return the top-level funcdef. If it finds both in the same path, it will load whichever
   is newer. If it gets through all the paths and finds no files, it returns nothing.",
	extra: [Extra("protection", "global")]},

	{kind: "function", name: "load", docs:
	"Loads a module of the given name and, if successful, returns that module's namespace. If the module is
	already loaded (i.e. it has an entry in the `modules.loaded` table), just returns the preexisting namespace.
	
	This is the function that the built-in import statement calls. So in fact, \"`import foo.bar`\" and
	\"`modules.load(\"foo.bar\")`\" do exactly the same thing, at least from the module-loading point of view.
	Import statements also give you some syntactic advantages with selective and renamed imports.
	
	The process of loading a module goes something like this:

 1. It looks in `modules.loaded` to see if the module of the given name has already been imported. If it has
    (i.e. there is a namespace in that table), it returns whatever namespace is stored there.
 2. It makes sure we are not circularly importing this module. If we are, it throws an error.
 3. It makes sure there are no module name conflicts. No module name may be the prefix of any other module's
    name; for example, if you have a module \"foo.bar\", you may not have a module \"foo\" as it's a prefix of
    \"foo.bar\". If there are any conflicts, it throws an error.
 4. It iterates through the `modules.loaders` array, calling each successive loader with the module's name.
    If a loader returns a namespace, it puts it in the `modules.loaded` table and returns that namespace. If
    a loader returns a function or funcdef, it calls `modules.initModule` with the function/funcdef as the first
    parameter and the name of the module as the second parameter, and returns the result of that function. If
    a loader returns null, it continues on to the next loader.
 5. If it gets through the entire array without getting a function or namespace from any loaders, an error is
    thrown saying that the module could not be loaded.",
	params: [Param("name", "string")],
	extra: [Extra("protection", "global")]},
	
	{kind: "function", name: "reload", docs:
	"Very similar to `modules.load`, but reloads an already-loaded module. This function replaces step 1 of
	`modules.load`'s process with a check to see if the module has already been loaded; if it has, it continues
	on with the process. If it hasn't been loaded, throws an error.",
	params: [Param("name", "string")],
	extra: [Extra("protection", "global")]},
	
	{kind: "function", name: "initModule", docs:
	"Initialize a module with a top-level function/funcdef, and a name. The name is used to create the namespace for
	the module in the global namespace hierarchy if it doesn't already exist. If the module namespace does already exist
	(such as in the case when a module is being reloaded), it is cleared before the top-level is called. Once the namespace
	has been created, the top-level function (or if the first parameter is a funcdef, the result of creating a new closure
	of that funcdef with the new namespace as the environment) is called with the module namespace as the 'this' parameter.
	
	If the top-level function completes successfully, the module's namespace will be inserted into the global namespace
	hierarchy and also be added to the `modules.loaded` table.
	
	If the top-level function fails, no change will be made to the global namespace hierarchy (unless the module's namespace
	was cleared).
	
	Note that if you pass a function as the `topLevel` parameter, it can only be a native function. Script functions'
	environments are fixed and cannot be set to the new module namespace. For that matter, if you pass a funcdef, that funcdef
	must not have had any closures created from it yet, as that would associate a namespace with that funcdef as well.",
	params: [Param("topLevel", "function|funcdef"), Param("name", "string")],
	extra: [Extra("protection", "global")]},
	
	{kind: "function", name: "runMain", docs:
	"This will look in the given namespace for a field named main. If one exists, and that field is a function,
	that function will be called with the namespace as 'this' and any variadic arguments to `runMain` as the
	arguments. Otherwise, this function does nothing.",
	params: [Param("mod", "namespace"), Param("vararg", "vararg")],
	extra: [Extra("protection", "global")]}
];