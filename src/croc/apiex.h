#ifndef CROC_APIEX_H
#define CROC_APIEX_H

#include <stdarg.h>

#include "croc/apitypes.h"

#define CROCAPI(f) croc_ex_##f
#define CROCPRINT(a, b) __attribute__((format(printf, a, b)))

#ifdef __cplusplus
extern "C" {
#endif

// =====================================================================================================================
// Imports

word_t CROCAPI(importModule)           (CrocThread* t, const char* name);
word_t CROCAPI(importModuleStk)        (CrocThread* t, word_t name);
word_t CROCAPI(importModuleFromString) (CrocThread* t, const char* name, const char* src, const char* srcName);

#define croc_ex_importModuleNoNS(t, name)\
	(croc_ex_importModule((t), (name)), croc_pop(t, 1))

#define croc_ex_importModuleNoNSStk(t, name)\
	(croc_ex_importModuleStk((t), (name)), croc_pop(t, 1))

#define croc_ex_importModuleFromStringNoNS(t, name, src, srcName)\
	(croc_ex_importModuleFromString((t), (name), (src), (srcName)), croc_pop(t, 1))

// =====================================================================================================================
// Compilation

word_t  CROCAPI(loadStringNamed)        (CrocThread* t, const char* code, const char* name);
word_t  CROCAPI(loadStringWithEnvNamed) (CrocThread* t, const char* code, const char* name);
void    CROCAPI(runStringNamed)         (CrocThread* t, const char* code, const char* name);
void    CROCAPI(runStringWithEnvNamed)  (CrocThread* t, const char* code, const char* name);
uword_t CROCAPI(eval)                   (CrocThread* t, const char* code, word_t numReturns);
uword_t CROCAPI(evalWithEnv)            (CrocThread* t, const char* code, word_t numReturns);
void    CROCAPI(runFile)                (CrocThread* t, const char* filename, uword_t numParams);
void    CROCAPI(runModule)              (CrocThread* t, const char* moduleName, uword_t numParams);

#define croc_ex_loadString(t, code)\
	(croc_ex_loadStringNamed((t), (code), "<loaded from string>"))

#define croc_ex_loadStringWithEnv(t, code)\
	(croc_ex_loadStringWithEnvNamed((t), (code), "<loaded from string>"))

#define croc_ex_runString(t, code)\
	(croc_ex_runStringNamed((t), (code), "<loaded from string>"))

#define croc_ex_runStringWithEnv(t, code)\
	(croc_ex_runStringWithEnvNamed((t), (code), "<loaded from string>"))

// =====================================================================================================================
// Common tasks

word_t CROCAPI(lookup)          (CrocThread* t, const char* name);
word_t CROCAPI(pushRegistryVar) (CrocThread* t, const char* name);
void   CROCAPI(setRegistryVar)  (CrocThread* t, const char* name);

// =====================================================================================================================
// Parameter checking

void        CROCAPI(checkAnyParam)        (CrocThread* t, word_t index);
int         CROCAPI(checkBoolParam)       (CrocThread* t, word_t index);
crocint_t   CROCAPI(checkIntParam)        (CrocThread* t, word_t index);
crocfloat_t CROCAPI(checkFloatParam)      (CrocThread* t, word_t index);
crocfloat_t CROCAPI(checkNumParam)        (CrocThread* t, word_t index);
const char* CROCAPI(checkStringParam)     (CrocThread* t, word_t index);
const char* CROCAPI(checkStringParamn)    (CrocThread* t, word_t index, uword_t* len);
crocchar_t  CROCAPI(checkCharParam)       (CrocThread* t, word_t index);
void        CROCAPI(checkInstParam)       (CrocThread* t, word_t index, const char* name);
void        CROCAPI(checkInstParamSlot)   (CrocThread* t, word_t index, word_t classIndex);
void        CROCAPI(checkParam)           (CrocThread* t, word_t index, CrocType type);

int         CROCAPI(optBoolParam)         (CrocThread* t, word_t index, int def);
crocint_t   CROCAPI(optIntParam)          (CrocThread* t, word_t index, crocint_t def);
crocfloat_t CROCAPI(optFloatParam)        (CrocThread* t, word_t index, crocfloat_t def);
crocfloat_t CROCAPI(optNumParam)          (CrocThread* t, word_t index, crocfloat_t def);
const char* CROCAPI(optStringParam)       (CrocThread* t, word_t index, const char* def);
const char* CROCAPI(optStringParamn)      (CrocThread* t, word_t index, const char* def, uword_t* len);
crocchar_t  CROCAPI(optCharParam)         (CrocThread* t, word_t index, crocchar_t def);
int         CROCAPI(optParam)             (CrocThread* t, word_t index, CrocType type);

word_t      CROCAPI(paramTypeError)       (CrocThread* t, word_t index, const char* expected);

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
	char data[CROC_STR_BUFFER_DATA_LENGTH];
} CrocStrBuffer;

void   CROCAPI(buffer_init)        (CrocThread* t, CrocStrBuffer* b);
void   CROCAPI(buffer_addChar)     (CrocStrBuffer* b, crocchar_t c);
void   CROCAPI(buffer_addString)   (CrocStrBuffer* b, const char* s);
void   CROCAPI(buffer_addStringn)  (CrocStrBuffer* b, const char* s, uword_t len);
void   CROCAPI(buffer_addTop)      (CrocStrBuffer* b);
word_t CROCAPI(buffer_finish)      (CrocStrBuffer* b);
void   CROCAPI(buffer_start)       (CrocStrBuffer* b);
char*  CROCAPI(buffer_prepare)     (CrocStrBuffer* b, uword_t size);
void   CROCAPI(buffer_addPrepared) (CrocStrBuffer* b);

// =====================================================================================================================
// Exception handling

void CROCAPI(throwNamedException)  (CrocThread* t, const char* exName, const char* fmt, ...) CROCPRINT(3, 4);
void CROCAPI(vthrowNamedException) (CrocThread* t, const char* exName, const char* fmt, va_list args);

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
// Doc comments

void   CROCAPI(processDocComment)    (CrocThread* t, const char* comment);
void   CROCAPI(processDocCommentn)   (CrocThread* t, const char* comment, uword_t len);
word_t CROCAPI(parseDocCommentText)  (CrocThread* t, const char* comment);
word_t CROCAPI(parseDocCommentTextn) (CrocThread* t, const char* comment, uword_t len);

// =====================================================================================================================
// JSON

word_t CROCAPI(fromJSON)  (CrocThread* t, const char* source);
word_t CROCAPI(fromJSONn) (CrocThread* t, const char* source, uword_t len);
void   CROCAPI(toJSON)    (CrocThread* t, word_t root, int pretty, void(*output)(const char*, uword_t), void(*nl)());

// =====================================================================================================================
// Library helpers

#define CROC_LINE_PRAGMA(n) "//#line " #n "\n"
#define CROC_LINE_PRAGMA_FILE(n, file) "//#line " #n " \"" file "\"\n"

typedef struct CrocRegisterFunc
{
	const char* name;
	word_t maxParams;
	CrocNativeFunc func;
	uword_t numUpvals;
} CrocRegisterFunc;

typedef struct CrocDocParam
{
	const char* name;
	const char* type;
	const char* value;
} CrocDocParam;

typedef struct CrocDocExtra
{
	const char* name;
	const char* value;
} CrocDocExtra;

typedef struct CrocDocTable
{
	const char* kind;
	const char* name;
	const char* docs;

	uword_t line;

	CrocDocParam* params;
	CrocDocExtra* extra;
} CrocDocTable;

typedef struct CrocDoc
{
	CrocThread* t;
	const char* mFile;
	crocint_t mStartIdx;
	uword_t mDittoDepth;
} CrocDoc;

void CROCAPI(makeModule)      (CrocThread* t, const char* name, CrocNativeFunc loader);
void CROCAPI(registerGlobal)  (CrocThread* t, CrocRegisterFunc f);
void CROCAPI(registerField)   (CrocThread* t, CrocRegisterFunc f);
void CROCAPI(registerMethod)  (CrocThread* t, CrocRegisterFunc f);
void CROCAPI(registerGlobals) (CrocThread* t, const CrocRegisterFunc* funcs);
void CROCAPI(registerFields)  (CrocThread* t, const CrocRegisterFunc* funcs);
void CROCAPI(registerMethods) (CrocThread* t, const CrocRegisterFunc* funcs);

void CROCAPI(doc_init)            (CrocThread* t, CrocDoc* d, const char* file);
void CROCAPI(doc_push)            (CrocDoc* d, CrocDocTable* docs);
void CROCAPI(doc_popNamed)        (CrocDoc* d, word_t idx, const char* parentField);
void CROCAPI(doc_mergeModuleDocs) (CrocDoc* d);

#define croc_ex_doc_pop(d, idx) (croc_ex_doc_popNamed((d), (idx), "children"))
#define croc_ex_doc_pushPopNamed(d, docs, parentField)\
	(croc_ex_doc_push((d), (docs)), croc_ex_doc_popNamed((d), -1, (parentField)))
#define croc_ex_doc_pushPop(d, docs)\
	(croc_ex_doc_push((d), (docs)), croc_ex_doc_pop((d), -1))

void CROCAPI(docGlobals) (CrocThread* t, CrocDoc* doc, CrocDocTable* docs);
void CROCAPI(docFields)  (CrocThread* t, CrocDoc* doc, CrocDocTable* docs);

// =====================================================================================================================
// Serialization

// TODO: these should take parameters which can be wrapped by stream.NativeStream, whatever that type may be.
// void   CROCAPI(serializeGraph)     (CrocThread* t, word_t idx, word_t trans, OutputStream output);
// word_t CROCAPI(deserializeGraph)   (CrocThread* t, word_t trans, InputStream input);
// void   CROCAPI(serializeModule)    (CrocThread* t, word_t idx, const char* name, OutputStream output);
// void   CROCAPI(serializeModulen)   (CrocThread* t, word_t idx, const char* name, uword_t len, OutputStream output);
// word_t CROCAPI(deserializeModule)  (CrocThread* t, const char** name, InputStream input);
// word_t CROCAPI(deserializeModulen) (CrocThread* t, const char** name, uword_t* len, InputStream input);

#ifdef __cplusplus
} /* extern "C" */
#endif

#undef CROCAPI

#endif