#ifndef CROC_STDLIB_ALL_HPP
#define CROC_STDLIB_ALL_HPP

namespace croc
{
	void initArrayLib(CrocThread* t);
	void initAsciiLib(CrocThread* t);
	void initCompilerLib(CrocThread* t);
	void initConsoleLib(CrocThread* t);
	void initDocsLib(CrocThread* t);
	void initDoctoolsLibs(CrocThread* t);
	void initEnvLib(CrocThread* t);
	void initExceptionsLib(CrocThread* t);
	void initGCLib(CrocThread* t);
	void initHashLib(CrocThread* t);
	void initJSONLib(CrocThread* t);
	void initMathLib(CrocThread* t);
	void initMemblockLib(CrocThread* t);
	void initMiscLib(CrocThread* t);
	void initMiscLib_Vector(CrocThread* t);
	void initModulesLib(CrocThread* t);
	void initObjectLib(CrocThread* t);
	void initPathLib(CrocThread* t);
	void initSerializationLib(CrocThread* t);
	void initStreamLib(CrocThread* t);
	void initStringLib(CrocThread* t);
	void initTextLib(CrocThread* t);
	void initThreadLib(CrocThread* t);
	void initTimeLib(CrocThread* t);

#ifdef CROC_BUILTIN_DOCS
	void docExceptionsLib(CrocThread* t);
	void docGCLib(CrocThread* t);
	void docMiscLib(CrocThread* t);
	void docMiscLib_Vector(CrocThread* t);
	void docModulesLib(CrocThread* t);
	void docStringLib(CrocThread* t);
#endif
}

#endif