
#include <cstdio>
#include <stdlib.h>

#include "croc/api.h"
#include "croc/internal/eh.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"
#include "croc/util/str.hpp"

namespace croc
{
	namespace
	{
	const char* Loading = "modules.loading";
	const char* Prefixes = "modules.prefixes";

	// =================================================================================================================
	// Internal funcs

	bool isLoading(CrocThread* t, crocstr name)
	{
		auto loading = croc_ex_pushRegistryVar(t, Loading);
		croc_pushStringn(t, cast(const char*)name.ptr, name.length);
		auto ret = croc_hasFieldStk(t, loading, -1);
		croc_pop(t, 2);
		return ret;
	}

	void setLoading(CrocThread* t, crocstr name, bool loading)
	{
		auto loadingTab = croc_ex_pushRegistryVar(t, Loading);
		croc_pushStringn(t, cast(const char*)name.ptr, name.length);

		if(loading)
			croc_pushBool(t, true);
		else
			croc_pushNull(t);

		croc_fieldaStk(t, loadingTab);
		croc_popTop(t);
	}

	void setLoaded(CrocThread* t, crocstr name, word reg)
	{
		auto loaded = croc_pushGlobal(t, "loaded");
		croc_pushStringn(t, cast(const char*)name.ptr, name.length);
		croc_dup(t, reg);
		croc_fieldaStk(t, loaded);
		croc_popTop(t);

		auto idx = strLocateChar(name, '.');

		if(idx != name.length)
		{
			auto prefixes = croc_ex_pushRegistryVar(t, Prefixes);

			for(; idx != name.length; idx = strLocateChar(name, '.', idx + 1))
			{
				croc_pushStringn(t, cast(const char*)name.ptr, idx);
				croc_pushBool(t, true);
				croc_fieldaStk(t, prefixes);
			}

			croc_popTop(t);
		}
	}

	void checkNameConflicts(CrocThread* t, crocstr name)
	{
		auto loaded = croc_pushGlobal(t, "loaded");

		for(auto idx = strLocateChar(name, '.'); idx != name.length; idx = strLocateChar(name, '.', idx + 1))
		{
			croc_pushStringn(t, cast(const char*)name.ptr, idx);

			if(croc_hasFieldStk(t, loaded, -1))
				croc_eh_throwStd(t, "ImportException",
					"Attempting to import module '%.*s', but there is already a module '%.*s'",
					cast(int)name.length, name.ptr, cast(int)idx, name.ptr);

			croc_popTop(t);
		}

		croc_ex_pushRegistryVar(t, Prefixes);
		croc_pushStringn(t, cast(const char*)name.ptr, name.length);

		if(croc_hasFieldStk(t, -2, -1))
			croc_eh_throwStd(t, "ImportException",
				"Attempting to import module '%.*s', but other modules use that name as a prefix",
				cast(int)name.length, cast(const char*)name.ptr);

		croc_pop(t, 3);
	}

	void initModule(CrocThread* t, crocstr name, word reg)
	{
		if(croc_isFunction(t, reg) && !croc_function_isNative(t, reg))
			croc_eh_throwStd(t, "ValueError",
				"Error loading module '%.*s': top-level module function must be a native function",
				cast(int)name.length, name.ptr);

		// Make the namespace
		auto ns = croc_pushGlobal(t, "_G");
		word firstParent, firstChild;
		crocstr childName;
		bool foundSplit = false;

		delimiters(name, ATODA("."), [&](crocstr segment)
		{
			if(foundSplit)
			{
				croc_pushStringn(t, cast(const char*)segment.ptr, segment.length);
				croc_namespace_newWithParent(t, ns, croc_getString(t, -1));
				croc_swapTop(t);
				croc_dup(t, -2);
				croc_fieldaStk(t, ns);
				croc_insertAndPop(t, ns);
			}
			else
			{
				croc_pushStringn(t, cast(const char*)segment.ptr, segment.length);

				if(croc_hasFieldStk(t, ns, -1))
				{
					croc_fieldStk(t, ns);

					if(!croc_isNamespace(t, -1))
						croc_eh_throwStd(t, "ImportException",
							"Error loading module '%.*s': conflicts with existing global",
							cast(int)name.length, cast(const char*)name.ptr);

					croc_insertAndPop(t, ns);
				}
				else
				{
					foundSplit = true;
					firstParent = ns;
					childName = segment;
					firstChild = croc_namespace_newWithParent(t, firstParent, croc_getString(t, -1)) - 1;
					croc_insertAndPop(t, -2);
					ns = croc_dup(t, firstChild);
				}
			}
		});

		// at this point foundSplit is only true if we had to create new namespaces -- that is, upon first loading,
		// and not during reloading
		if(croc_len(t, ns) > 0)
			croc_namespace_clear(t, ns);

		// Set up the function
		word funcSlot;
		croc_dup(t, ns);

		if(croc_isFunction(t, reg))
		{
			croc_function_setEnv(t, reg);
			funcSlot = croc_dup(t, reg);
		}
		else
			funcSlot = croc_function_newScriptWithEnv(t, reg);

		croc_dup(t, ns);

		// Call the top-level function
		auto failed = tryCode(Thread::from(t), funcSlot, [&]()
		{
			croc_call(t, funcSlot, 0);
		});

		if(failed)
		{
			auto slot = croc_eh_pushStd(t, "ImportException");
			croc_pushNull(t);
			croc_pushFormat(t, "Error loading module '%.*s': exception thrown from module's top-level function",
				cast(int)name.length, name.ptr);
			croc_dup(t, funcSlot);
			croc_call(t, slot, 1);
			croc_eh_throw(t);
		}

		// Add it to the loaded table
		setLoaded(t, name, ns);

		// Add it to the globals
		if(foundSplit)
		{
			croc_pushStringn(t, cast(const char*)childName.ptr, childName.length);
			croc_dup(t, firstChild);
			croc_fieldaStk(t, firstParent);
		}

		croc_dup(t, ns);
	}

	uword commonLoad(CrocThread* t, crocstr name)
	{
		// Check to see if we're circularly importing
		if(isLoading(t, name))
			croc_eh_throwStd(t, "ImportException", "Module '%.*s' is being circularly imported",
				cast(int)name.length, name.ptr);

		setLoading(t, name, true);

		auto failed = tryCode(Thread::from(t), croc_getStackSize(t) - 1, [&]()
		{
			// Check for name conflicts
			checkNameConflicts(t, name);

			// Run through the loaders
			auto loaders = croc_pushGlobal(t, "loaders");
			auto num = cast(uword)croc_len(t, -1);

			for(uword i = 0; i < num; i++)
			{
				auto reg = croc_idxi(t, loaders, i);
				croc_pushNull(t);
				croc_pushStringn(t, cast(const char*)name.ptr, name.length);
				croc_call(t, reg, 1);

				if(croc_isFuncdef(t, reg) || croc_isFunction(t, reg))
				{
					initModule(t, name, reg);
					return;
				}
				else if(croc_isNamespace(t, reg))
				{
					setLoaded(t, name, reg);
					return;
				}
				else if(!croc_isNull(t, reg))
				{
					croc_pushTypeString(t, reg);
					croc_eh_throwStd(t, "TypeError",
						"modules.loaders[%" CROC_SIZE_T_FORMAT
							"] expected to return a function, funcdef, namespace, or null, not '%s'",
						i, croc_getString(t, -1));
				}

				croc_popTop(t);
			}

			// Nothing worked :C
			croc_eh_throwStd(t, "ImportException", "Error loading module '%.*s': could not find anything to load",
				cast(int)name.length, name.ptr);
		});

		setLoading(t, name, false);

		if(failed)
			croc_eh_rethrow(t);

		return 1;
	}

	// =================================================================================================================
	// Funcs

const char* _load_docs = Docstr(DFunc("load") DParam("name", "string")
	R"(Loads a module of the given name and, if successful, returns that module's namespace. If the module is already
	loaded (i.e. it has an entry in the \link{modules.loaded} table), just returns the preexisting namespace.

	This is the function that the built-in import statement calls. So in fact, "\tt{import foo.bar}" and
	"\tt{modules.load("foo.bar")}" do exactly the same thing, at least from the module-loading point of view. Import
	statements also give you some syntactic advantages with selective and renamed imports.

	The process of loading a module goes something like this:

	\nlist
		\li It looks in \link{modules.loaded} to see if the module of the given name has already been imported. If it
			has (i.e. there is a namespace in that table), it returns whatever namespace is stored there.
		\li It makes sure we are not circularly importing this module. If we are, it throws an error.
		\li It makes sure there are no module name conflicts. No module name may be the prefix of any other module's
			name; for example, if you have a module "foo.bar", you may not have a module "foo" as it's a prefix of
			"foo.bar". If there are any conflicts, it throws an error.
		\li It iterates through the \link{modules.loaders} array, calling each successive loader with the module's name.
			If a loader returns null, it continues on to the next loader. If a loader returns a namespace, it puts it in
			the \link{modules.loaded} table and returns that namespace. If a loader returns a function (native only) or
			funcdef, it is assumed to be the modules's top-level function, and the following occurs:

			\nlist
				\li The dotted module name is used to create the namespace for the module in the global namespace
					hierarchy if it doesn't already exist. If the namespace already exists (such as when a module is
					being reloaded), it is cleared at this point.
				\li If the loader returned a funcdef, a closure is created here using that funcdef and the new namespace
					as its environment. If the loader returned a (native) function, its environment is changed to the
					new namespace.
				\li The top-level function is called, with the module's namespace as the 'this' parameter.
				\li If the top-level function succeeds, the module's namespace will be inserted into the global
					namespace hierarchy and into the \link{modules.loaded} table, at which point \tt{modules.load}
					returns that namespace.
				\li Otherwise, if the top-level function fails, no change will be made to the global namespace hierarchy
					(unless the namespace was cleared during a module reload), and an exception will be thrown.
			\endlist
		\li If it gets through the entire array without getting a function or namespace from any loaders, an error is
			thrown saying that the module could not be loaded.
	\endlist

	\param[name] The name of the module to load, in dotted form (such as "foo.bar").
	\returns The namespace of the module after it has been imported.
	\throws[ImportException] if no means of loading the module could be found, or if a module loader was
	found but failed when run. In the latter case, the exception that was thrown during module loading will be set as
	the cause of the exception.)");

	word_t _load(CrocThread* t)
	{
		uword_t nameLen;
		auto name = croc_ex_checkStringParamn(t, 1, &nameLen);

		croc_pushGlobal(t, "loaded");
		croc_dup(t, 1);
		croc_idx(t, -2);

		if(croc_isNamespace(t, -1))
			return 1;

		croc_pop(t, 2);
		return commonLoad(t, crocstr::n(cast(const uchar*)name, nameLen));
	}

const char* _reload_docs = Docstr(DFunc("reload") DParam("name", "string")
	R"(Very similar to \link{modules.load}, but reloads an already-loaded module. This function replaces step 1 of
	\link{modules.load}'s process with a check to see if the module has already been loaded; if it has, it continues
	on with the process. If it hasn't been loaded, throws an error.)");

	word_t _reload(CrocThread* t)
	{
		uword_t nameLen;
		auto name = croc_ex_checkStringParamn(t, 1, &nameLen);

		croc_pushGlobal(t, "loaded");
		croc_dup(t, 1);
		croc_idx(t, -2);

		if(croc_isNull(t, -1))
			croc_eh_throwStd(t, "ImportException","Attempting to reload module '%.*s' which has not yet been loaded",
				cast(int)nameLen, name);

		croc_pop(t, 2);
		return commonLoad(t, crocstr::n(cast(uchar*)name, nameLen));
	}

const char* _runMain_docs = Docstr(DFunc("runMain") DParam("ns", "namespace") DVararg
	R"(Runs a function named "main" (if any) in the given namespace with the given arguments.

	This will look in the given namespace for a field named \tt{main}. If one exists, and that field is a function, that
	function will be called with the namespace as 'this' and any variadic arguments to \tt{runMain} as the arguments.
	Otherwise, this function does nothing.

	\param[ns] The namespace in which to look.
	\param[vararg] The arguments that will be passed to the "main" function.)");

	word_t _runMain(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Namespace);

		if(croc_hasField(t, 1, "main"))
		{
			auto main = croc_field(t, 1, "main");

			if(croc_isFunction(t, main))
			{
				croc_insert(t, 1);
				croc_call(t, 1, 0);
			}
		}

		return 0;
	}

	word_t _customLoad(CrocThread* t)
	{
		croc_ex_checkStringParam(t, 1);
		croc_pushGlobal(t, "customLoaders");
		croc_dup(t, 1);
		croc_idx(t, -2);

		if(croc_isFunction(t, -1) || croc_isNamespace(t, -1) || croc_isFuncdef(t, -1))
			return 1;

		return 0;
	}

	word_t _loadFiles(CrocThread* t)
	{
		uword nameLen;
		auto name = croc_ex_checkStringParamn(t, 1, &nameLen);
		auto maxNameLen = nameLen + 6; // 6 chars for ".croco"

		// safe since this string is held in the modules namespace
		croc_pushGlobal(t, "path");
		auto paths = croc_getString(t, -1);
		croc_popTop(t);

		word_t ret = 0;

		delimitersBreak(atoda(paths), ATODA(";"), [&](crocstr path) -> bool
		{
			char filenameBuf[FILENAME_MAX + 1];

			// +1 for /
			if(path.length + 1 + maxNameLen >= FILENAME_MAX)
				croc_eh_throwStd(t, "ApiError", "Filename for '%s' is too long", name);

			uword idx = 0;
			memcpy(filenameBuf + idx, path.ptr, path.length); idx += path.length;
			filenameBuf[idx++] = '/';
			memcpy(filenameBuf + idx, name, nameLen);
			filenameBuf[idx + nameLen] = 0;

			for(auto pos = strchr(filenameBuf + idx, '.'); pos != nullptr; pos = strchr(pos + 1, '.'))
				*pos = '/';

			idx += nameLen;
			memcpy(filenameBuf + idx, ".croc", 5); idx += 5;
			filenameBuf[idx] = 0;

			// TODO: load .croco files.

			auto f = fopen(filenameBuf, "rb");

			if(!f)
				return true; // continue

			// TODO: load this more elegantly? :P
			fseek(f, 0, SEEK_END);
			auto size = ftell(f);
			fseek(f, 0, SEEK_SET);
			auto data = (char*)malloc(size + 1);
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-result"
			fread(data, 1, size, f);
#pragma GCC diagnostic pop
			data[size] = 0;
			fclose(f);

			auto slot = croc_pushNull(t);
			auto failed = tryCode(Thread::from(t), slot, [&] { croc_pushString(t, data); });
			free(data);

			if(failed)
				croc_eh_rethrow(t);

			croc_insertAndPop(t, slot);

			const char* loadedName;
			croc_compiler_compileModuleEx(t, filenameBuf, &loadedName);

			if(strcmp(name, loadedName) != 0)
			{
				croc_eh_throwStd(t,
					"ImportException", "Import name (%s) does not match name given in module statement (%s)",
					name, loadedName);
			}

			ret = 1;
			return false; // break
		});

		return ret;
	}

const char* _docstrings[] =
{
	Docstr(DVarV("path", "\".\"")
	R"(This is just a variable that holds a string. This string contains the paths that are used when searching for
	modules. The paths are specified using forward slashes to separate path components regardless of the underlying
	OS, and semicolons to separate paths.

	By default, this variable holds the string ".", which just means "the current directory". If you changed it to
	something like ".;imports/current", when you tried to load a module "foo.bar", it would look for "./foo/bar.croc"
	and "imports/current/foo/bar.croc" in that order.)"),

	Docstr(DVar("customLoaders")
	R"(This is a table which you are free to use. It maps from module names (strings) to functions, funcdefs, or
	namespaces. This table is used by the \tt{customLoad} step in \link{modules.loaders}; see it for more
	information.)"),

	Docstr(DVar("loaders")
	R"(This is an important variable. This holds the array of \em{module loaders}, which are functions which take the
	name of a module that's being loaded, and return one of four things: nothing or null, to indicate that the next
	loader should be tried; a namespace, which is assumed to be the module's namespace; a native function, which is
	assumed to be a native module's \em{loader}; or a funcdef, which is assumed to be the function definition of the
	top-level function of a Croc module.

	By default, two loaders are in this array, in the following order:
	\blist
		\li \b{\tt{customLoad}}: This looks in the \link{modules.customLoaders} table for a loader function, funcdef, or
			namespace. If one exists, it just returns that; otherwise, returns null. You can use this behavior to set up
			custom loaders for your own modules: just put the loader in the \link{modules.customLoaders} table, and when
			it's imported, it'll have the loader function, funcdef, or namespace used for it. This is exactly how the
			standard library loaders work.

		\li \b{\tt{loadFiles}}: This looks for files to load and loads them. As explained in \link{modules.path}, the
			paths in that variable will be tried one by one until a file is found or they are all exhausted. This looks
			for both script files (\tt{.croc}) and compiled modules (\tt{.croco}). If it finds just a script file, it
			will compile it and return the resulting top-level funcdef. If it finds just a compiled module, it will load
			it and return the top-level funcdef. If it finds both in the same path, it will load whichever is newer. If
			it gets through all the paths and finds no files, it returns nothing.
	\endlist)"),

	_load_docs,
	_reload_docs,
	_runMain_docs,
	nullptr
};
	}

	void initModulesLib(CrocThread* t)
	{
		croc_table_new(t, 0); croc_ex_setRegistryVar(t, Loading);
		croc_table_new(t, 0); croc_ex_setRegistryVar(t, Prefixes);

		auto ns = croc_namespace_new(t, "modules");

		// doing this stuff manually because we haven't created the module system yet, duh
		croc_pushString(t, "."); croc_fielda(t, ns, "path");
		croc_table_new(t, 0);    croc_fielda(t, ns, "customLoaders");

		croc_dup(t, ns); croc_function_newWithEnv(t, "load",     1, &_load, 0);    croc_fielda(t, ns, "load");
		croc_dup(t, ns); croc_function_newWithEnv(t, "reload",   1, &_reload, 0);  croc_fielda(t, ns, "reload");
		croc_dup(t, ns); croc_function_newWithEnv(t, "runMain", -1, &_runMain, 0); croc_fielda(t, ns, "runMain");

		croc_table_new(t, 0);
			// integrate 'modules' itself into the module loading system
			croc_dup(t, ns);
			croc_fielda(t, -2, "modules");
		croc_fielda(t, ns, "loaded");

		croc_pushString(t, "loaders");
			croc_dup(t, ns); croc_function_newWithEnv(t, "customLoad", 1, &_customLoad, 0);
			croc_dup(t, ns); croc_function_newWithEnv(t, "loadFiles",  1, &_loadFiles, 0);
			croc_array_newFromStack(t, 2);
		croc_fieldaStk(t, ns);

		croc_newGlobal(t, "modules");
	}

#ifdef CROC_BUILTIN_DOCS
	void docModulesLib(CrocThread* t)
	{
		CrocDoc doc;
		croc_ex_doc_init(t, &doc, __FILE__);
		croc_ex_doc_push(&doc,
		DModule("modules")
		R"(This library forms the core of the Croc module system. When you use an import statement in Croc, it's simply
		syntactic sugar for a call to \tt{modules.load}. All of the semantics of imports and such are handled by the
		functions and data structures in here. At a high level, the module system is just a mechanism that maps from
		strings (module names) to namespaces. The default behavior of this library is just that -- a default. You
		can customize the behavior of module importing to your specific needs.)");
		croc_pushGlobal(t, "modules");
		croc_ex_docFields(&doc, _docstrings);
		croc_ex_doc_pop(&doc, -1);
		croc_ex_doc_finish(&doc);
		croc_popTop(t);
	}
#endif
}