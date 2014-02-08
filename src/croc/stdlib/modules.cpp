
#include "croc/api.h"
#include "croc/internal/eh.hpp"
#include "croc/types.hpp"

namespace croc
{
	namespace
	{
		const char* Loading = "modules.loading";
		const char* Prefixes = "modules.prefixes";

		// =========================================================================================================================================
		// Internal funcs

		bool isLoading(CrocThread* t, const char* name)
		{
			auto loading = croc_ex_pushRegistryVar(t, Loading);
			auto ret = croc_hasField(t, loading, name);
			croc_popTop(t);
			return ret;
		}

		void setLoading(CrocThread* t, const char* name, bool loading)
		{
			auto loadingTab = croc_ex_pushRegistryVar(t, Loading);

			if(loading)
				croc_pushBool(t, true);
			else
				croc_pushNull(t);

			croc_fielda(t, loadingTab, name);
			croc_popTop(t);
		}

		void setLoaded(CrocThread* t, const char* name, word reg)
		{
			auto loaded = croc_pushGlobal(t, "loaded");
			croc_dup(t, reg);
			croc_fielda(t, loaded, name);
			croc_popTop(t);

			auto idx = strchr(name, '.');

			if(idx != nullptr)
			{
				auto prefixes = croc_ex_pushRegistryVar(t, Prefixes);

				for(; idx != nullptr; idx = strchr(idx + 1, '.'))
				{
					croc_pushStringn(t, name, idx - name);
					croc_pushBool(t, true);
					croc_fieldaStk(t, prefixes);
				}

				croc_popTop(t);
			}
		}

		void checkNameConflicts(CrocThread* t, const char* name)
		{
			auto loaded = croc_pushGlobal(t, "loaded");

			for(auto idx = strchr(name, '.'); idx != nullptr; idx = strchr(idx + 1, '.'))
			{
				croc_pushStringn(t, name, idx - name);

				if(croc_hasFieldStk(t, loaded, -1))
					croc_eh_throwStd(t, "ImportException",
						"Attempting to import module '%s', but there is already a module '%.*s'",
						name, idx - name, name);

				croc_popTop(t);
			}

			croc_ex_pushRegistryVar(t, Prefixes);

			if(croc_hasField(t, -1, name))
				croc_eh_throwStd(t, "ImportException",
					"Attempting to import module '%s', but other modules use that name as a prefix", name);

			croc_pop(t, 2);
		}

		void initModule(CrocThread* t, const char* name, word reg)
		{
			if(croc_isFunction(t, reg) && !croc_function_isNative(t, reg))
				croc_eh_throwStd(t, "ValueError",
					"Error loading module '%s': top-level module function must be a native function", name);

			// Make the namespace
			auto ns = croc_pushGlobal(t, "_G");
			word firstParent, firstChild;
			crocstr childName;
			bool foundSplit = false;

			for(auto segment: delimiters(name, '.'))
			{
				if(foundSplit)
				{
					croc_pushStringn(t, segment.ptr, segment.length);
					croc_namespace_newWithParent(t, ns, croc_getString(t, -1));
					croc_swapTop(t);
					croc_dup(t, -2);
					croc_fieldaStk(t, ns);
					croc_insertAndPop(t, ns);
				}
				else
				{
					croc_pushStringn(t, segment.ptr, segment.length);

					if(croc_hasFieldStk(t, ns, -1))
					{
						croc_fieldStk(t, ns);

						if(!croc_isNamespace(t, -1))
							croc_eh_throwStd(t, "ImportException",
								"Error loading module '%s': conflicts with existing global", name);

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
			}

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
				croc_pushFormat(t, "Error loading module '%s': exception thrown from module's top-level function",
					name);
				croc_dup(t, funcSlot);
				croc_call(t, slot, 1);
				croc_eh_throw(t);
			}

			// Add it to the loaded table
			setLoaded(t, name, ns);

			// Add it to the globals
			if(foundSplit)
			{
				croc_pushStringn(t, childName.ptr, childName.length);
				croc_dup(t, firstChild);
				croc_fieldaStk(t, firstParent);
			}

			croc_dup(t, ns);
		}

		uword commonLoad(CrocThread* t, const char* name)
		{
			// Check to see if we're circularly importing
			if(isLoading(t, name))
				croc_eh_throwStd(t, "ImportException", "Module '%s' is being circularly imported", name);

			setLoading(t, name, true);

			auto failed = tryCode(Thread::from(t), croc_getStackSize(t) - 1, [&]()
			{
				// Check for name conflicts
				checkNameConflicts(t, name);

				// Run through the loaders
				auto loaders = croc_pushGlobal(t, "loaders");
				auto num = croc_len(t, -1);

				for(uword i = 0; i < num; i++)
				{
					auto reg = croc_idxi(t, loaders, i);
					croc_pushNull(t);
					croc_pushString(t, name);
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
							"modules.loaders[%u] expected to return a function, funcdef, namespace, or null, not '%s'",
							i, croc_getString(t, -1));
					}

					croc_popTop(t);
				}

				// Nothing worked :C
				croc_eh_throwStd(t, "ImportException", "Error loading module '%s': could not find anything to load",
					name);
			});

			setLoading(t, name, false);

			if(failed)
				croc_eh_rethrow(t);

			return 1;
		}

		word_t _load(CrocThread* t)
		{
			auto name = croc_ex_checkStringParam(t, 1);

			croc_pushGlobal(t, "loaded");
			croc_dup(t, 1);
			croc_idx(t, -2);

			if(croc_isNamespace(t, -1))
				return 1;

			croc_pop(t, 2);
			return commonLoad(t, name);
		}

		word_t _reload(CrocThread* t)
		{
			auto name = croc_ex_checkStringParam(t, 1);

			croc_pushGlobal(t, "loaded");
			croc_dup(t, 1);
			croc_idx(t, -2);

			if(croc_isNull(t, -1))
				croc_eh_throwStd(t, "ImportException","Attempting to reload module '%s' which has not yet been loaded",
					name);

			croc_pop(t, 2);
			return commonLoad(t, name);
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
			// TODO:stdlib TODO:compiler
			croc_eh_throwStd(t, "Throwable", "I DUNNO LOL");
			return 0;
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