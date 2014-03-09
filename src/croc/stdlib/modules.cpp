
#include <cstdio>
#include <stdlib.h>

#include "croc/api.h"
#include "croc/internal/eh.hpp"
#include "croc/types/base.hpp"
#include "croc/util/str.hpp"

namespace croc
{
	namespace
	{
	const char* Loading = "modules.loading";
	const char* Prefixes = "modules.prefixes";

	// =========================================================================================================================================
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

		delimiters(name, atoda("."), [&](crocstr segment)
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

		delimitersBreak(atoda(paths), atoda(";"), [&](crocstr path) -> bool
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
			fread(data, 1, size, f);
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
}