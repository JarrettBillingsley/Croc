/** @file */

#ifndef CROC_APIEX_H
#define CROC_APIEX_H

#include <stdarg.h>
#include <stdio.h>

#include "croc/apitypes.h"

#define CROCAPI
#define CROCPRINT(a, b) __attribute__((format(printf, a, b)))

#ifdef __cplusplus
extern "C" {
#endif

/*====================================================================================================================*/
/** @defgroup ExImports Imports
@ingroup Ex
Importing modules. */
/**@{*/

CROCAPI word_t croc_ex_importNS              (CrocThread* t, const char* name);
CROCAPI word_t croc_ex_importNSStk           (CrocThread* t, word_t name);
CROCAPI word_t croc_ex_importFromStringNSStk (CrocThread* t, const char* name, const char* srcName);

/** Imports a module, just like an import statement in Croc.

\param t is the thread. <em>This will be evaluated by this macro more than once.</em>
\param name is the name of the module to import.*/
#define croc_ex_import(t, name)\
	(croc_ex_importNS((t), (name)), croc_pop((t), 1))

/** Like \ref croc_ex_import, but uses a stack slot for the name.

\param t is the thread. <em>This will be evaluated by this macro more than once.</em>
\param name should be a stack index of a string containing the name of the module to import. */
#define croc_ex_importStk(t, name)\
	(croc_ex_importNSStk((t), (name)), croc_pop((t), 1))

/** Imports a module from a string.

\param t is the thread. <em>This will be evaluated by this macro more than once.</em>
\param name is the module name that it will be imported as.
\param src is the source code as a string.
\param srcName is the name of the source that will be used in error messages. */
#define croc_ex_importFromString(t, name, src, srcName)\
	(croc_ex_importFromStringNS((t), (name), (src), (srcName)), croc_pop((t), 1))

/** Like \ref croc_ex_importFromString, but leaves the namespace of the imported module on the stack. */
#define croc_ex_importFromStringNS(t, name, src, srcName)\
	(croc_pushString((t), (src)), croc_ex_importFromStringNSStk((t), (name), (srcName)))

/** Like \ref croc_ex_importFromString, but expects the source on top of the stack instead of as a parameter. */
#define croc_ex_importFromStringStk(t, name, srcName)\
	(croc_ex_importFromStringNSStk((t), (name), (src), (srcName)), croc_pop((t), 1))
/**@}*/
/*====================================================================================================================*/
/** @defgroup ExCompilation Compilation
@ingroup Ex
Simpler functions for compiling Croc code.

There are a bunch of variants of some of these functions, and the variants all work the same way. If they have \c
withEnv in their name, the environment to evaluate the code in should be on top of the stack; otherwise it will use the
currently executing function's environment (or the global namespace if there is none). If they have \c Stk in their
name, the source code should be a string on top of the stack (or under the environment in the \c withEnv versions);
otherwise, they take the source as a parameter. */
/**@{*/
CROCAPI word_t  croc_ex_loadStringWithEnvStk (CrocThread* t, const char* name);
CROCAPI void    croc_ex_runStringWithEnvStk  (CrocThread* t, const char* name);
CROCAPI uword_t croc_ex_evalWithEnvStk       (CrocThread* t, word_t numReturns);
CROCAPI void    croc_ex_runModule            (CrocThread* t, const char* moduleName, uword_t numParams);

/** Like \ref croc_ex_loadStringWithEnvStk but uses the current environment and takes the source as the parameter \c
code. */
#define croc_ex_loadString(t, code, name)\
	(croc_pushString((t), (code)), croc_pushCurEnvironment(t), croc_ex_loadStringWithEnvStk((t), (name)))

/** Like \ref croc_ex_loadString but expects the code on top of the stack. */
#define croc_ex_loadStringStk(t, name)\
	(croc_pushCurEnvironment(t), croc_ex_loadStringWithEnvStk((t), (name)))

/** Like \ref croc_ex_loadString but expects the environment on top of the stack. */
#define croc_ex_loadStringWithEnv(t, code, name)\
	(croc_pushString((t), (code)), croc_swapTop(t), croc_ex_loadStringWithEnvStk((t), (name)))

/** Like \ref croc_ex_runStringWithEnvStk but uses the current environment and takes the source as the parameter \c
code. */
#define croc_ex_runString(t, code, name)\
	(croc_pushString((t), (code)), croc_pushCurEnvironment(t), croc_ex_runStringWithEnvStk((t), (name)))

/** Like \ref croc_ex_runString but expects the code on top of the stack. */
#define croc_ex_runStringStk(t, name)\
	(croc_pushCurEnvironment(t), croc_ex_runStringWithEnvStk((t), (name)))

/** Like croc_ex_runString but expects the environment on top of the stack. */
#define croc_ex_runStringWithEnv(t, code, name)\
	(croc_pushString((t), (code)), croc_swapTop(t), croc_ex_runStringWithEnvStk((t), (name)))

/** Like croc_ex_evalWithEnvStk but uses the current environment and takes the expression as the parameter \c code. */
#define croc_ex_eval(t, code, numReturns)\
	(croc_pushString((t), (code)), croc_pushCurEnvironment(t), croc_ex_evalWithEnvStk((t), (numReturns)))

/** Like croc_ex_eval but expects the code on top fo the stack. */
#define croc_ex_evalStk(t, numReturns)\
	(croc_pushCurEnvironment(t), croc_ex_evalWithEnvStk((t), (numReturns)))

/** Like croc_ex_eval but expects the environment on top of the stack. */
#define croc_ex_evalWithEnv(t, code, numReturns)\
	(croc_pushString((t), (code)), croc_swapTop(t), croc_ex_evalWithEnvStk((t), (numReturns)))
/**@}*/
/*====================================================================================================================*/
/** @defgroup ExCommon Common tasks
@ingroup Ex
Miscellaneous useful stuff. */
/**@{*/
CROCAPI word_t croc_ex_lookup               (CrocThread* t, const char* name);
CROCAPI word_t croc_ex_pushRegistryVar      (CrocThread* t, const char* name);
CROCAPI void   croc_ex_setRegistryVar       (CrocThread* t, const char* name);
CROCAPI word_t croc_ex_throwNamedException  (CrocThread* t, const char* exName, const char* fmt, ...) CROCPRINT(3, 4);
CROCAPI word_t croc_ex_vthrowNamedException (CrocThread* t, const char* exName, const char* fmt, va_list args);
CROCAPI word_t croc_ex_CFileToNativeStream  (CrocThread* t, FILE* f, const char* mode);
CROCAPI int    croc_ex_isHaltException      (CrocThread* t, word_t index);
/**@}*/
/*====================================================================================================================*/
/** @defgroup ExParams Parameter checking
@ingroup Ex
Checking parameters in native functions. */
/**@{*/
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
CROCAPI uword_t     croc_ex_checkIndexParam      (CrocThread* t, word_t index, uword_t length, const char* name);
CROCAPI uword_t     croc_ex_checkLoSliceParam    (CrocThread* t, word_t index, uword_t length, const char* name);
CROCAPI uword_t     croc_ex_checkHiSliceParam    (CrocThread* t, word_t index, uword_t length, const char* name);
CROCAPI uword_t     croc_ex_checkSliceParams     (CrocThread* t, word_t index, uword_t length, const char* name, uword_t* hi);

CROCAPI int         croc_ex_optBoolParam         (CrocThread* t, word_t index, int def);
CROCAPI crocint_t   croc_ex_optIntParam          (CrocThread* t, word_t index, crocint_t def);
CROCAPI crocfloat_t croc_ex_optFloatParam        (CrocThread* t, word_t index, crocfloat_t def);
CROCAPI crocfloat_t croc_ex_optNumParam          (CrocThread* t, word_t index, crocfloat_t def);
CROCAPI const char* croc_ex_optStringParam       (CrocThread* t, word_t index, const char* def);
CROCAPI const char* croc_ex_optStringParamn      (CrocThread* t, word_t index, const char* def, uword_t* len);
CROCAPI crocchar_t  croc_ex_optCharParam         (CrocThread* t, word_t index, crocchar_t def);
CROCAPI int         croc_ex_optParam             (CrocThread* t, word_t index, CrocType type);
CROCAPI uword_t     croc_ex_optIndexParam        (CrocThread* t, word_t index, uword_t length, const char* name, crocint_t def);

CROCAPI word_t      croc_ex_paramTypeError       (CrocThread* t, word_t index, const char* expected);
CROCAPI void        croc_ex_checkValidSlice      (CrocThread* t, crocint_t lo, crocint_t hi, uword_t length, const char* name);
CROCAPI word_t      croc_ex_indexError           (CrocThread* t, crocint_t index, uword_t length, const char* name);
CROCAPI word_t      croc_ex_sliceIndexError      (CrocThread* t, crocint_t lo, crocint_t hi, uword_t length, const char* name);
/**@}*/
/*====================================================================================================================*/
/** @defgroup ExStrBuffer StrBuffer
@ingroup Ex
A way of building up strings piecewise. */
/**@{*/

// TODO: move this to a configuration header
#define CROC_STR_BUFFER_DATA_LENGTH 1024

/** A structure used for building strings up piecewise. Although the members are defined so you can allocate this
structure on the stack, treat it as if it were an opaque type! Only pass it to the buffer functions. */
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
/**@}*/
/*====================================================================================================================*/
/** @defgroup ExLibrary Library helpers
@ingroup Ex
Helpers for making native libraries. */
/**@{*/

/** A structure which holds the description of a native function. */
typedef struct CrocRegisterFunc
{
	const char* name;    /**< The function's name, or NULL to indicate the end of an array of this structure. */
	word_t maxParams;    /**< The maximum number of parameters, or -1 to make it variadic. */
	CrocNativeFunc func; /**< The address of the native function itself. */
} CrocRegisterFunc;

CROCAPI void croc_ex_makeModule       (CrocThread* t, const char* name, CrocNativeFunc loader);
CROCAPI void croc_ex_registerGlobalUV (CrocThread* t, CrocRegisterFunc f, uword_t numUpvals);
CROCAPI void croc_ex_registerFieldUV  (CrocThread* t, CrocRegisterFunc f, uword_t numUpvals);
CROCAPI void croc_ex_registerMethodUV (CrocThread* t, CrocRegisterFunc f, uword_t numUpvals);
CROCAPI void croc_ex_registerGlobals  (CrocThread* t, const CrocRegisterFunc* funcs);
CROCAPI void croc_ex_registerFields   (CrocThread* t, const CrocRegisterFunc* funcs);
CROCAPI void croc_ex_registerMethods  (CrocThread* t, const CrocRegisterFunc* funcs);

/** Makes a closure from \c f and sets it as a new global in the current environment. */
#define croc_ex_registerGlobal(t, f) croc_ex_registerGlobalUV((t), (f), 0)

/** Makes a closure from \c f and field-assigns it into the value on top of the stack. */
#define croc_ex_registerField(t, f) croc_ex_registerFieldUV((t), (f), 0)

/** Makes a closure from \c f and adds it as a method into the class on top of the stack. */
#define croc_ex_registerMethod(t, f) croc_ex_registerMethodUV((t), (f), 0)
/**@}*/
/*====================================================================================================================*/
/** @defgroup ExDocs Documentation helpers
@ingroup Ex
These make it easier to write Croc documentation for native libraries.

You are encouraged to define aliases to the \c CROC_DOC_XXX macros to make your code shorter, as they can be very
verbose otherwise.*/
/**@{*/

/** A structure used to keep track of doctables that are currently being built up. Although the members are defined so
you can allocate this structure on the stack, treat it as if it were an opaque type! Only pass it to the doc
functions. */
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
CROCAPI void croc_ex_docGlobal           (CrocDoc* d, const char* docString);
CROCAPI void croc_ex_docField            (CrocDoc* d, const char* docString);
CROCAPI void croc_ex_docGlobals          (CrocDoc* d, const char** docStrings);
CROCAPI void croc_ex_docFields           (CrocDoc* d, const char** docStrings);

/** Like croc_ex_doc_popNamed, but passes "children" as the name of the parent field. */
#define croc_ex_doc_pop(d, idx) (croc_ex_doc_popNamed((d), (idx), "children"))

#define STRINGIFY2(X) #X
#define STRINGIFY(X) STRINGIFY2(X)
#define CROC_DOC_HEADER(type, name) "!" STRINGIFY(__LINE__) " " type " " name

/** Makes a module docstring header. */
#define CROC_DOC_MODULE(name)      CROC_DOC_HEADER("module",    name) "\n"
/** Makes a function docstring header. After this, you can use the parameter macros to list params. */
#define CROC_DOC_FUNC(name)        CROC_DOC_HEADER("function",  name) "\n"
/** Makes a class docstring header. Can be followed by zero or more base directives (\ref CROC_DOC_BASE). */
#define CROC_DOC_CLASS(name)       CROC_DOC_HEADER("class",     name) "\n"
/** Makes a namespace docstring header. Can be followed by zero or one base directives (\ref CROC_DOC_BASE). */
#define CROC_DOC_NS(name)          CROC_DOC_HEADER("namespace", name) "\n"
/** Makes a field docstring header. */
#define CROC_DOC_FIELD(name)       CROC_DOC_HEADER("field",     name) "\n"
/** Makes a field docstring header with an initializer value. */
#define CROC_DOC_FIELDV(name, val) CROC_DOC_HEADER("field",     name) "=" val "\n"
/** Makes a global variable docstring header. */
#define CROC_DOC_VAR(name)         CROC_DOC_HEADER("global",    name) "\n"
/** Makes a global variable docstring header with an initializer value. */
#define CROC_DOC_VARV(name, val)   CROC_DOC_HEADER("global",    name) "=" val "\n"

/** Used for listing the base class(es) and base namespace in class and namespace docstrings. */
#define CROC_DOC_BASE(name)              "!base " name "\n"

/** Defines a parameter which can accept any type. */
#define CROC_DOC_PARAMANY(name)          "!param " name ":any\n"
/** Defines a parameter which can accept any type and has a default value. */
#define CROC_DOC_PARAMANYD(name, def)    "!param " name ":any=" def "\n"
/** Defines a parameter which accepts values of type \c type. */
#define CROC_DOC_PARAM(name, type)       "!param " name ":" type "\n"
/** Defines a parameter which accepts values of type \c type and has a default value. */
#define CROC_DOC_PARAMD(name, type, def) "!param " name ":" type "=" def "\n"
/** Should come as the last parameter, and indicates the function is variadic. */
#define CROC_DOC_VARARG                  CROC_DOC_PARAM("vararg", "vararg")
/**@}*/
#ifdef __cplusplus
} /* extern "C" */
#endif

#undef CROCAPI

#endif