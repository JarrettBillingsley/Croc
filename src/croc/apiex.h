#ifndef CROC_APIEX_H
#define CROC_APIEX_H

#include <stdarg.h>

#include "croc/apitypes.h"

#define CROCAPI
#define CROCPRINT(a, b) __attribute__((format(printf, a, b)))

#ifdef __cplusplus
extern "C" {
#endif

// =====================================================================================================================
// Imports

CROCAPI word_t croc_ex_importNS              (CrocThread* t, const char* name);
CROCAPI word_t croc_ex_importNSStk           (CrocThread* t, word_t name);
CROCAPI word_t croc_ex_importFromStringNSStk (CrocThread* t, const char* name, const char* srcName);

#define croc_ex_importFromStringNS(t, name, src, srcName)\
	(croc_pushString((t), (src)), croc_ex_importFromStringNSStk((t), (name), (srcName)))

#define croc_ex_import(t, name)\
	(croc_ex_importNS((t), (name)), croc_pop((t), 1))

#define croc_ex_importStk(t, name)\
	(croc_ex_importNSStk((t), (name)), croc_pop((t), 1))

#define croc_ex_importFromString(t, name, src, srcName)\
	(croc_ex_importFromStringNS((t), (name), (src), (srcName)), croc_pop((t), 1))

#define croc_ex_importFromStringStk(t, name, srcName)\
	(croc_ex_importFromStringNSStk((t), (name), (src), (srcName)), croc_pop((t), 1))

// =====================================================================================================================
// Compilation

CROCAPI word_t  croc_ex_loadStringWithEnvStk (CrocThread* t, const char* name);
CROCAPI void    croc_ex_runStringWithEnvStk  (CrocThread* t, const char* name);
CROCAPI uword_t croc_ex_evalWithEnvStk       (CrocThread* t, word_t numReturns);
CROCAPI void    croc_ex_runModule            (CrocThread* t, const char* moduleName, uword_t numParams);

#define croc_ex_loadString(t, code, name)\
	(croc_pushString((t), (code)), croc_pushCurEnvironment(t), croc_ex_loadStringWithEnvStk((t), (name)))

#define croc_ex_loadStringStk(t, name)\
	(croc_pushCurEnvironment(t), croc_ex_loadStringWithEnvStk((t), (name)))

#define croc_ex_loadStringWithEnv(t, code, name)\
	(croc_pushString((t), (code)), croc_swapTop(t), croc_ex_loadStringWithEnvStk((t), (name)))

#define croc_ex_runString(t, code, name)\
	(croc_pushString((t), (code)), croc_pushCurEnvironment(t), croc_ex_runStringWithEnvStk((t), (name)))

#define croc_ex_runStringStk(t, name)\
	(croc_pushCurEnvironment(t), croc_ex_runStringWithEnvStk((t), (name)))

#define croc_ex_runStringWithEnv(t, code, name)\
	(croc_pushString((t), (code)), croc_swapTop(t), croc_ex_runStringWithEnvStk((t), (name)))

#define croc_ex_eval(t, code, numReturns)\
	(croc_pushString((t), (code)), croc_pushCurEnvironment(t), croc_ex_evalWithEnvStk((t), (numReturns)))

#define croc_ex_evalStk(t, numReturns)\
	(croc_pushCurEnvironment(t), croc_ex_evalWithEnvStk((t), (numReturns)))

#define croc_ex_evalWithEnv(t, code, numReturns)\
	(croc_pushString((t), (code)), croc_swapTop(t), croc_ex_evalWithEnvStk((t), (numReturns)))

// =====================================================================================================================
// Common tasks

CROCAPI word_t croc_ex_lookup          (CrocThread* t, const char* name);
CROCAPI word_t croc_ex_pushRegistryVar (CrocThread* t, const char* name);
CROCAPI void   croc_ex_setRegistryVar  (CrocThread* t, const char* name);

// =====================================================================================================================
// Parameter checking

CROCAPI void        croc_ex_checkAnyParam        (CrocThread* t, word_t index);
CROCAPI int         croc_ex_checkBoolParam       (CrocThread* t, word_t index);
CROCAPI crocint_t   croc_ex_checkIntParam        (CrocThread* t, word_t index);
CROCAPI crocfloat_t croc_ex_checkFloatParam      (CrocThread* t, word_t index);
CROCAPI crocfloat_t croc_ex_checkNumParam        (CrocThread* t, word_t index);
CROCAPI const char* croc_ex_checkStringParam     (CrocThread* t, word_t index);
CROCAPI const char* croc_ex_checkStringParamn    (CrocThread* t, word_t index, uword_t* len);
CROCAPI crocchar_t  croc_ex_checkCharParam       (CrocThread* t, word_t index);
CROCAPI void        croc_ex_checkInstParam       (CrocThread* t, word_t index, const char* name);
CROCAPI void        croc_ex_checkInstParamSlot   (CrocThread* t, word_t index, word_t classIndex);
CROCAPI void        croc_ex_checkParam           (CrocThread* t, word_t index, CrocType type);

CROCAPI int         croc_ex_optBoolParam         (CrocThread* t, word_t index, int def);
CROCAPI crocint_t   croc_ex_optIntParam          (CrocThread* t, word_t index, crocint_t def);
CROCAPI crocfloat_t croc_ex_optFloatParam        (CrocThread* t, word_t index, crocfloat_t def);
CROCAPI crocfloat_t croc_ex_optNumParam          (CrocThread* t, word_t index, crocfloat_t def);
CROCAPI const char* croc_ex_optStringParam       (CrocThread* t, word_t index, const char* def);
CROCAPI const char* croc_ex_optStringParamn      (CrocThread* t, word_t index, const char* def, uword_t* len);
CROCAPI crocchar_t  croc_ex_optCharParam         (CrocThread* t, word_t index, crocchar_t def);
CROCAPI int         croc_ex_optParam             (CrocThread* t, word_t index, CrocType type);

CROCAPI word_t      croc_ex_paramTypeError       (CrocThread* t, word_t index, const char* expected);

// =====================================================================================================================
// StrBuffer

// TODO: move this to a configuration header
#define CROC_STR_BUFFER_DATA_LENGTH 1024

typedef struct CrocStrBuffer
{
	CrocThread* t;
	word_t slot;
	word_t buffer;
	uword_t pos;
	unsigned char data[CROC_STR_BUFFER_DATA_LENGTH];
} CrocStrBuffer;

CROCAPI void   croc_ex_buffer_init        (CrocThread* t, CrocStrBuffer* b);
CROCAPI void   croc_ex_buffer_addChar     (CrocStrBuffer* b, crocchar_t c);
CROCAPI void   croc_ex_buffer_addString   (CrocStrBuffer* b, const char* s);
CROCAPI void   croc_ex_buffer_addStringn  (CrocStrBuffer* b, const char* s, uword_t len);
CROCAPI void   croc_ex_buffer_addTop      (CrocStrBuffer* b);
CROCAPI word_t croc_ex_buffer_finish      (CrocStrBuffer* b);
CROCAPI void   croc_ex_buffer_start       (CrocStrBuffer* b);
CROCAPI char*  croc_ex_buffer_prepare     (CrocStrBuffer* b, uword_t size);
CROCAPI void   croc_ex_buffer_addPrepared (CrocStrBuffer* b);

// =====================================================================================================================
// Exception handling

CROCAPI void croc_ex_throwNamedException  (CrocThread* t, const char* exName, const char* fmt, ...) CROCPRINT(3, 4);
CROCAPI void croc_ex_vthrowNamedException (CrocThread* t, const char* exName, const char* fmt, va_list args);

// TODO: come up with something for this? macros?
// void croctry(CrocThread* t, void delegate() try_, void delegate(CrocException, word_t) catch_, void delegate() finally_ = null)
// {
// 	auto size = stackSize(t);

// 	try
// 		try_();
// 	catch(CrocException e)
// 	{
// 		setStackSize(t, size);
// 		auto crocEx = catchException(t);
// 		catch_(e, crocEx);

// 		if(crocEx != stackSize(t) - 1)
// 			croc_eh_throwStd(t, "ApiError", "croctry - catch block is supposed to leave stack as it was before it was entered");

// 		pop(t);
// 	}
// 	finally
// 	{
// 		if(finally_)
// 			finally_();
// 	}
// }

// =====================================================================================================================
// JSON

CROCAPI word_t croc_ex_fromJSON  (CrocThread* t, const char* source);
CROCAPI word_t croc_ex_fromJSONn (CrocThread* t, const char* source, uword_t len);
CROCAPI void   croc_ex_toJSON    (CrocThread* t, word_t root, int pretty, void(*output)(const char*, uword_t), void(*nl)());

// =====================================================================================================================
// Library helpers

typedef struct CrocRegisterFunc
{
	const char* name;
	word_t maxParams;
	CrocNativeFunc func;
} CrocRegisterFunc;

CROCAPI void croc_ex_makeModule      (CrocThread* t, const char* name, CrocNativeFunc loader);
CROCAPI void croc_ex_registerGlobal  (CrocThread* t, CrocRegisterFunc f);
CROCAPI void croc_ex_registerField   (CrocThread* t, CrocRegisterFunc f);
CROCAPI void croc_ex_registerMethod  (CrocThread* t, CrocRegisterFunc f);
CROCAPI void croc_ex_registerGlobals (CrocThread* t, const CrocRegisterFunc* funcs);
CROCAPI void croc_ex_registerFields  (CrocThread* t, const CrocRegisterFunc* funcs);
CROCAPI void croc_ex_registerMethods (CrocThread* t, const CrocRegisterFunc* funcs);

typedef struct CrocDoc
{
	CrocThread* t;
	const char* file;
	crocint_t startIdx;
	uword_t dittoDepth;
} CrocDoc;

CROCAPI void croc_ex_doc_init            (CrocThread* t, CrocDoc* d, const char* file);
CROCAPI void croc_ex_doc_finish          (CrocDoc* d);
CROCAPI void croc_ex_doc_push            (CrocDoc* d, const char* docString);
CROCAPI void croc_ex_doc_popNamed        (CrocDoc* d, word_t idx, const char* parentField);
CROCAPI void croc_ex_doc_mergeModuleDocs (CrocDoc* d);
CROCAPI void croc_ex_docGlobals          (CrocDoc* d, const char** docStrings);
CROCAPI void croc_ex_docFields           (CrocDoc* d, const char** docStrings);

#define croc_ex_doc_pop(d, idx) (croc_ex_doc_popNamed((d), (idx), "children"))

#define STRINGIFY2(X) #X
#define STRINGIFY(X) STRINGIFY2(X)
#define CROC_DOC_HEADER(type, name) "!" STRINGIFY(__LINE__) " " type " " name

#define CROC_DOC_MODULE(name)      CROC_DOC_HEADER("module",    name) "\n"
#define CROC_DOC_FUNC(name)        CROC_DOC_HEADER("function",  name) "\n"
#define CROC_DOC_CLASS(name)       CROC_DOC_HEADER("class",     name) "\n"
#define CROC_DOC_NS(name)          CROC_DOC_HEADER("namespace", name) "\n"
#define CROC_DOC_FIELD(name)       CROC_DOC_HEADER("field",     name) "\n"
#define CROC_DOC_FIELDV(name, val) CROC_DOC_HEADER("field",     name) "=" val "\n"
#define CROC_DOC_VAR(name)         CROC_DOC_HEADER("global",    name) "\n"
#define CROC_DOC_VARV(name, val)   CROC_DOC_HEADER("global",    name) "=" val "\n"

#define CROC_DOC_BASE(name)              "!base " name "\n"
#define CROC_DOC_PARAMANY(name)          "!param " name ":any\n"
#define CROC_DOC_PARAMANYD(name, def)    "!param " name ":any=" def "\n"
#define CROC_DOC_PARAM(name, type)       "!param " name ":" type "\n"
#define CROC_DOC_PARAMD(name, type, def) "!param " name ":" type "=" def "\n"
#define CROC_DOC_VARARG                  CROC_DOC_PARAM("vararg", "vararg")

// =====================================================================================================================
// Serialization

// TODO: these should take parameters which can be wrapped by stream.NativeStream, whatever that type may be.
// CROCAPI void   croc_ex_serializeGraph     (CrocThread* t, word_t idx, word_t trans, OutputStream output);
// CROCAPI word_t croc_ex_deserializeGraph   (CrocThread* t, word_t trans, InputStream input);
// CROCAPI void   croc_ex_serializeModule    (CrocThread* t, word_t idx, const char* name, OutputStream output);
// CROCAPI void   croc_ex_serializeModulen   (CrocThread* t, word_t idx, const char* name, uword_t len, OutputStream output);
// CROCAPI word_t croc_ex_deserializeModule  (CrocThread* t, const char** name, InputStream input);
// CROCAPI word_t croc_ex_deserializeModulen (CrocThread* t, const char** name, uword_t* len, InputStream input);

#ifdef __cplusplus
} /* extern "C" */
#endif

#undef CROCAPI

#endif