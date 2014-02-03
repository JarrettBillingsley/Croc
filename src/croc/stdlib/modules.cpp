
#include "croc/api.h"
#include "croc/types.hpp"

namespace croc
{
	namespace
	{
		const char* Loading = "modules.loading";
		const char* Prefixes = "modules.prefixes";

		word_t _load(CrocThread* t)       { (void)t; return 0; }
		word_t _reload(CrocThread* t)     { (void)t; return 0; }
		word_t _runMain(CrocThread* t)    { (void)t; return 0; }
		word_t _customLoad(CrocThread* t) { (void)t; return 0; }
		word_t _loadFiles(CrocThread* t)  { (void)t; return 0; }
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