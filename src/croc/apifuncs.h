#ifndef CROC_APIFUNCS_H
#define CROC_APIFUNCS_H

#include <stdarg.h>

#include "croc/apitypes.h"

#define CROCAPI(f) croc_##f
#define CROCPRINT(a, b) __attribute__((format(printf, a, b)))

#ifdef __cplusplus
extern "C" {
#endif

// =====================================================================================================================
// VM Initialization and teardown

void*       CROCAPI(DefaultMemFunc)               (void* ctx, void* p, uword_t oldSize, uword_t newSize);
CrocThread* CROCAPI(vm_open)                      (CrocMemFunc memFunc, void* ctx);
void        CROCAPI(vm_close)                     (CrocThread* t);
void        CROCAPI(vm_loadUnsafeLibs)            (CrocThread* t, CrocUnsafeLib libs);
void        CROCAPI(vm_loadAddons)                (CrocThread* t, CrocAddons libs);
void        CROCAPI(vm_loadAvailableAddonsExcept) (CrocThread* t, CrocAddons exclude);

#define croc_vm_loadAllUnsafeLibs(t) (croc_vm_loadUnsafeLibs((t), CrocUnsafeLib_All))
#define croc_vm_loadAllAvailableAddons(t) (croc_vm_loadAllAvailableAddonsExcept((t), CrocAddons_None))

// =====================================================================================================================
// VM other

CrocThread* CROCAPI(vm_getMainThread)      (CrocThread* t);
CrocThread* CROCAPI(vm_getCurrentThread)   (CrocThread* t);
uword_t     CROCAPI(vm_bytesAllocated)     (CrocThread* t);
word_t      CROCAPI(vm_pushTypeMT)         (CrocThread* t, CrocType type);
void        CROCAPI(vm_setTypeMT)          (CrocThread* t, CrocType type);
word_t      CROCAPI(vm_pushRegistry)       (CrocThread* t);

// =====================================================================================================================
// Raw memory management

void* CROCAPI(mem_alloc)  (CrocThread* t, uword_t size);
void  CROCAPI(mem_resize) (CrocThread* t, void** mem, uword_t* memSize, uword_t newSize);
void* CROCAPI(mem_dup)    (CrocThread* t, void* mem, uword_t memSize);
void  CROCAPI(mem_free)   (CrocThread* t, void** mem, uword_t* memSize);

// =====================================================================================================================
// Native references

crocref_t CROCAPI(ref_create) (CrocThread* t, word_t idx);
word_t    CROCAPI(ref_push)   (CrocThread* t, crocref_t r);
void      CROCAPI(ref_remove) (CrocThread* t, crocref_t r);

// =====================================================================================================================
// Debugging

void    CROCAPI(debug_setHookFunc)     (CrocThread* t, uword_t mask, uword_t hookDelay);
word_t  CROCAPI(debug_pushHookFunc)    (CrocThread* t);
uword_t CROCAPI(debug_getHookMask)     (CrocThread* t);
uword_t CROCAPI(debug_getHookDelay)    (CrocThread* t);
void    CROCAPI(debug_printStack)      (CrocThread* t);
void    CROCAPI(debug_printWholeStack) (CrocThread* t);
void    CROCAPI(debug_printCallStack)  (CrocThread* t);

// =====================================================================================================================
// GC

uword_t CROCAPI(gc_maybeCollect) (CrocThread* t);
uword_t CROCAPI(gc_collect)      (CrocThread* t);
uword_t CROCAPI(gc_collectFull)  (CrocThread* t);
uword_t CROCAPI(gc_setLimit)     (CrocThread* t, const char* type, uword_t lim);
uword_t CROCAPI(gc_getLimit)     (CrocThread* t, const char* type);

// =====================================================================================================================
// Exceptions

void   CROCAPI(eh_throw)                 (CrocThread* t);
void   CROCAPI(eh_rethrow)               (CrocThread* t);
word_t CROCAPI(eh_pushStd)               (CrocThread* t, const char* exName);
void   CROCAPI(eh_throwStd)              (CrocThread* t, const char* exName, const char* fmt, ...) CROCPRINT(3, 4);
void   CROCAPI(eh_vthrowStd)             (CrocThread* t, const char* exName, const char* fmt, va_list args);
int    CROCAPI(eh_tryCall)               (CrocThread* t, word_t slot, word_t numReturns);
word_t CROCAPI(eh_pushLocationClass)     (CrocThread* t);
word_t CROCAPI(eh_pushLocationObject)    (CrocThread* t, const char* file, int line, int col);
void   CROCAPI(eh_setUnhandledExHandler) (CrocThread* t);

// =====================================================================================================================
// Stack manipulation

uword_t CROCAPI(getStackSize) (CrocThread* t);
void    CROCAPI(setStackSize) (CrocThread* t, uword_t newSize);
word_t  CROCAPI(absIndex)     (CrocThread* t, word_t idx);
int     CROCAPI(isValidIndex) (CrocThread* t, word_t idx);
word_t  CROCAPI(dup)          (CrocThread* t, word_t slot);
void    CROCAPI(swap)         (CrocThread* t, word_t first, word_t second);
void    CROCAPI(insert)       (CrocThread* t, word_t slot);
void    CROCAPI(insertAndPop) (CrocThread* t, word_t slot);
void    CROCAPI(moveToTop)    (CrocThread* t, word_t slot);
void    CROCAPI(rotate)       (CrocThread* t, uword_t numSlots, uword_t dist);
void    CROCAPI(rotateAll)    (CrocThread* t, uword_t dist);
void    CROCAPI(pop)          (CrocThread* t, uword_t n);
void    CROCAPI(transferVals) (CrocThread* src, CrocThread* dest, uword_t num);

#define croc_dupTop(t) (croc_dup((t), -1))
#define croc_swapTop(t) (croc_swap((t), -2, -1))
#define croc_swapTopWith(t, n) (croc_swap((t), (n), -1))
#define croc_popTop(t) (croc_pop((t), 1))

// =====================================================================================================================
// Type queries

CrocType CROCAPI(type)           (CrocThread* t, word_t slot);
word_t   CROCAPI(pushTypeString) (CrocThread* t, word_t slot);
int      CROCAPI(isTrue)         (CrocThread* t, word_t slot);
int      CROCAPI(isNum)          (CrocThread* t, word_t slot);
int      CROCAPI(isChar)         (CrocThread* t, word_t slot);

#define croc_isNull(t, slot)      (croc_type((t), (slot)) == CrocType_Null)
#define croc_isBool(t, slot)      (croc_type((t), (slot)) == CrocType_Bool)
#define croc_isInt(t, slot)       (croc_type((t), (slot)) == CrocType_Int)
#define croc_isFloat(t, slot)     (croc_type((t), (slot)) == CrocType_Float)
#define croc_isNativeobj(t, slot) (croc_type((t), (slot)) == CrocType_Nativeobj)
#define croc_isString(t, slot)    (croc_type((t), (slot)) == CrocType_String)
#define croc_isWeakRef(t, slot)   (croc_type((t), (slot)) == CrocType_WeakRef)
#define croc_isTable(t, slot)     (croc_type((t), (slot)) == CrocType_Table)
#define croc_isNamespace(t, slot) (croc_type((t), (slot)) == CrocType_Namespace)
#define croc_isArray(t, slot)     (croc_type((t), (slot)) == CrocType_Array)
#define croc_isMemblock(t, slot)  (croc_type((t), (slot)) == CrocType_Memblock)
#define croc_isFunction(t, slot)  (croc_type((t), (slot)) == CrocType_Function)
#define croc_isFuncDef(t, slot)   (croc_type((t), (slot)) == CrocType_FuncDef)
#define croc_isClass(t, slot)     (croc_type((t), (slot)) == CrocType_Class)
#define croc_isInstance(t, slot)  (croc_type((t), (slot)) == CrocType_Instance)
#define croc_isThread(t, slot)    (croc_type((t), (slot)) == CrocType_Thread)

// =====================================================================================================================
// Variables

word_t CROCAPI(pushEnvironment) (CrocThread* t, uword_t depth);
void   CROCAPI(setUpval)        (CrocThread* t, uword_t idx);
word_t CROCAPI(pushUpval)       (CrocThread* t, uword_t idx);
void   CROCAPI(newGlobal)       (CrocThread* t, const char* name);
void   CROCAPI(newGlobalStk)    (CrocThread* t);
word_t CROCAPI(pushGlobal)      (CrocThread* t, const char* name);
word_t CROCAPI(pushGlobalStk)   (CrocThread* t);
void   CROCAPI(setGlobal)       (CrocThread* t, const char* name);
void   CROCAPI(setGlobalStk)    (CrocThread* t);

#define croc_pushCurEnvironment(t) (croc_pushEnvironment((t), 0))

// =====================================================================================================================
// Function calling

uword_t CROCAPI(call)          (CrocThread* t, word_t slot, word_t numReturns);
uword_t CROCAPI(methodCall)    (CrocThread* t, word_t slot, const char* name, word_t numReturns);
uword_t CROCAPI(methodCallStk) (CrocThread* t, word_t slot, word_t numReturns);

// =====================================================================================================================
// Reflection
const char* CROCAPI(getNameOf)    (CrocThread* t, word_t obj);
const char* CROCAPI(getNameOfn)   (CrocThread* t, word_t obj, uword_t* len);
int         CROCAPI(hasField)     (CrocThread* t, word_t obj, const char* fieldName);
int         CROCAPI(hasFieldStk)  (CrocThread* t, word_t obj, word_t name);
int         CROCAPI(hasMethod)    (CrocThread* t, word_t obj, const char* methodName);
int         CROCAPI(hasMethodStk) (CrocThread* t, word_t obj, word_t name);
int         CROCAPI(isInstanceOf) (CrocThread* t, word_t obj, word_t base);
word_t      CROCAPI(superOf)      (CrocThread* t, word_t slot);

// =====================================================================================================================
// Value types

word_t      CROCAPI(pushNull)      (CrocThread* t);
word_t      CROCAPI(pushBool)      (CrocThread* t, int v);
word_t      CROCAPI(pushInt)       (CrocThread* t, crocint_t v);
word_t      CROCAPI(pushFloat)     (CrocThread* t, crocfloat_t v);
word_t      CROCAPI(pushString)    (CrocThread* t, const char* v);
word_t      CROCAPI(pushStringn)   (CrocThread* t, const char* v, uword_t len);
word_t      CROCAPI(pushChar)      (CrocThread* t, crocchar_t c);
word_t      CROCAPI(pushFormat)    (CrocThread* t, const char* fmt, ...) CROCPRINT(2, 3);
word_t      CROCAPI(vpushFormat)   (CrocThread* t, const char* fmt, va_list args);
word_t      CROCAPI(pushNativeobj) (CrocThread* t, void* o);
word_t      CROCAPI(pushThread)    (CrocThread* t, CrocThread* o);
int         CROCAPI(getBool)       (CrocThread* t, word_t slot);
crocint_t   CROCAPI(getInt)        (CrocThread* t, word_t slot);
crocfloat_t CROCAPI(getFloat)      (CrocThread* t, word_t slot);
crocfloat_t CROCAPI(getNum)        (CrocThread* t, word_t slot);
crocchar_t  CROCAPI(getChar)       (CrocThread* t, word_t slot);
const char* CROCAPI(getString)     (CrocThread* t, word_t slot);
const char* CROCAPI(getStringn)    (CrocThread* t, word_t slot, uword_t* len);
void*       CROCAPI(getNativeobj)  (CrocThread* t, word_t slot);
CrocThread* CROCAPI(getThread)     (CrocThread* t, word_t slot);

// =====================================================================================================================
// Weakrefs

word_t CROCAPI(weakref_push)  (CrocThread* t, word_t idx);
word_t CROCAPI(weakref_deref) (CrocThread* t, word_t idx);

// =====================================================================================================================
// Table

word_t CROCAPI(table_new)   (CrocThread* t, uword_t size);
void   CROCAPI(table_clear) (CrocThread* t, word_t tab);

// =====================================================================================================================
// Namespace

word_t      CROCAPI(namespace_new)           (CrocThread* t, const char* name);
word_t      CROCAPI(namespace_newWithParent) (CrocThread* t, word_t parent, const char* name);
word_t      CROCAPI(namespace_newNoParent)   (CrocThread* t, const char* name);
void        CROCAPI(namespace_clear)         (CrocThread* t, word_t ns);
const char* CROCAPI(namespace_getName)       (CrocThread* t, word_t ns);
const char* CROCAPI(namespace_getNamen)      (CrocThread* t, word_t ns, uword_t* len);
word_t      CROCAPI(namespace_pushFullName)  (CrocThread* t, word_t ns);

// =====================================================================================================================
// Array

word_t CROCAPI(array_new)          (CrocThread* t, uword_t len);
word_t CROCAPI(array_newFromStack) (CrocThread* t, uword_t len);
void   CROCAPI(array_fill)         (CrocThread* t, word_t arr);

// =====================================================================================================================
// Memblock

word_t CROCAPI(memblock_new)               (CrocThread* t, uword_t len);
word_t CROCAPI(memblock_fromNativeArray)   (CrocThread* t, void* arr, uword_t arrLen);
word_t CROCAPI(memblock_viewNativeArray)   (CrocThread* t, void* arr, uword_t arrLen);
void   CROCAPI(memblock_reviewNativeArray) (CrocThread* t, word_t slot, void* arr, uword_t arrLen);
char*  CROCAPI(memblock_getData)           (CrocThread* t, word_t slot);
char*  CROCAPI(memblock_getDatan)          (CrocThread* t, word_t slot, uword_t* len);

// =====================================================================================================================
// Function

word_t      CROCAPI(function_newWithEnv)       (CrocThread* t, const char* name, word_t maxParams, CrocNativeFunc func, uword_t numUpvals);
word_t      CROCAPI(function_newScriptWithEnv) (CrocThread* t, word_t funcDef);
word_t      CROCAPI(function_pushEnv)          (CrocThread* t, word_t func);
void        CROCAPI(function_setEnv)           (CrocThread* t, word_t func);
word_t      CROCAPI(function_pushDef)          (CrocThread* t, word_t func);
const char* CROCAPI(function_getName)          (CrocThread* t, word_t func);
const char* CROCAPI(function_getNamen)         (CrocThread* t, word_t func, uword_t* len);
uword_t     CROCAPI(function_getNumParams)     (CrocThread* t, word_t func);
uword_t     CROCAPI(function_getMaxParams)     (CrocThread* t, word_t func);
int         CROCAPI(function_isVararg)         (CrocThread* t, word_t func);
int         CROCAPI(function_isNative)         (CrocThread* t, word_t func);

#define croc_function_new(t, name, maxParams, func, numUpvals)\
	(croc_pushCurEnvironment(t), croc_function_newWithEnv((t), (name), (maxParams), (func), (numUpvals)))

#define croc_function_newScript(t, funcDef)\
	(croc_pushCurEnvironment(t), croc_function_newScriptWithEnv((t), (funcDef)))

// =====================================================================================================================
// Funcdef

const char* CROCAPI(funcdef_getName)  (CrocThread* t, word_t funcdef);
const char* CROCAPI(funcdef_getNamen) (CrocThread* t, word_t funcdef, uword_t* len);

// =====================================================================================================================
// Class

word_t      CROCAPI(class_new)             (CrocThread* t, const char* name, uword_t numBases);
const char* CROCAPI(class_getName)         (CrocThread* t, word_t cls);
const char* CROCAPI(class_getNamen)        (CrocThread* t, word_t cls, uword_t* len);
void        CROCAPI(class_addField)        (CrocThread* t, word_t cls, const char* name);
void        CROCAPI(class_addFieldStk)     (CrocThread* t, word_t cls);
void        CROCAPI(class_addMethod)       (CrocThread* t, word_t cls, const char* name);
void        CROCAPI(class_addMethodStk)    (CrocThread* t, word_t cls);
void        CROCAPI(class_addFieldO)       (CrocThread* t, word_t cls, const char* name);
void        CROCAPI(class_addFieldOStk)    (CrocThread* t, word_t cls);
void        CROCAPI(class_addMethodO)      (CrocThread* t, word_t cls, const char* name);
void        CROCAPI(class_addMethodOStk)   (CrocThread* t, word_t cls);
void        CROCAPI(class_removeMember)    (CrocThread* t, word_t cls, const char* name);
void        CROCAPI(class_removeMemberStk) (CrocThread* t, word_t cls);
void        CROCAPI(class_addHField)       (CrocThread* t, word_t cls, const char* name);
void        CROCAPI(class_addHFieldStk)    (CrocThread* t, word_t cls);
void        CROCAPI(class_removeHField)    (CrocThread* t, word_t cls, const char* name);
void        CROCAPI(class_removeHFieldStk) (CrocThread* t, word_t cls);
void        CROCAPI(class_freeze)          (CrocThread* t, word_t cls);
int         CROCAPI(class_isFrozen)        (CrocThread* t, word_t cls);

// =====================================================================================================================
// Thread

word_t          CROCAPI(thread_new)            (CrocThread* t, word_t func);
CrocThreadState CROCAPI(thread_getState)       (CrocThread* t);
const char*     CROCAPI(thread_getStateString) (CrocThread* t);
uword_t         CROCAPI(thread_getCallDepth)   (CrocThread* t);
void            CROCAPI(thread_reset)          (CrocThread* t, word_t slot);
void            CROCAPI(thread_resetWithFunc)  (CrocThread* t, word_t slot);
void            CROCAPI(thread_halt)           (CrocThread* t);
void            CROCAPI(thread_pendingHalt)    (CrocThread* t);
int             CROCAPI(thread_hasPendingHalt) (CrocThread* t);

// =====================================================================================================================
// Basic Croc operations

void      CROCAPI(foreachBegin)    (CrocThread* t, uword_t numContainerVals);
int       CROCAPI(foreachNext)     (CrocThread* t, uword_t numIndices);
void      CROCAPI(foreachEnd)      (CrocThread* t);
void      CROCAPI(removeKey)       (CrocThread* t, word_t obj);
word_t    CROCAPI(pushToString)    (CrocThread* t, word_t slot);
word_t    CROCAPI(pushToStringRaw) (CrocThread* t, word_t slot);
int       CROCAPI(in)              (CrocThread* t, word_t item, word_t container);
crocint_t CROCAPI(cmp)             (CrocThread* t, word_t a, word_t b);
int       CROCAPI(equals)          (CrocThread* t, word_t a, word_t b);
int       CROCAPI(is)              (CrocThread* t, word_t a, word_t b);
word_t    CROCAPI(idx)             (CrocThread* t, word_t container);
void      CROCAPI(idxa)            (CrocThread* t, word_t container);
word_t    CROCAPI(idxi)            (CrocThread* t, word_t container, crocint_t idx);
void      CROCAPI(idxai)           (CrocThread* t, word_t container, crocint_t idx);
word_t    CROCAPI(slice)           (CrocThread* t, word_t container);
void      CROCAPI(slicea)          (CrocThread* t, word_t container);
word_t    CROCAPI(field)           (CrocThread* t, word_t container, const char* name);
word_t    CROCAPI(fieldStk)        (CrocThread* t, word_t container);
void      CROCAPI(fielda)          (CrocThread* t, word_t container, const char* name);
void      CROCAPI(fieldaStk)       (CrocThread* t, word_t container);
word_t    CROCAPI(rawField)        (CrocThread* t, word_t container, const char* name);
word_t    CROCAPI(rawFieldStk)     (CrocThread* t, word_t container);
void      CROCAPI(rawFielda)       (CrocThread* t, word_t container, const char* name);
void      CROCAPI(rawFieldaStk)    (CrocThread* t, word_t container);
word_t    CROCAPI(hfield)          (CrocThread* t, word_t container, const char* name);
word_t    CROCAPI(hfieldStk)       (CrocThread* t, word_t container);
void      CROCAPI(hfielda)         (CrocThread* t, word_t container, const char* name);
void      CROCAPI(hfieldaStk)      (CrocThread* t, word_t container);
word_t    CROCAPI(pushLen)         (CrocThread* t, word_t slot);
crocint_t CROCAPI(len)             (CrocThread* t, word_t slot);
void      CROCAPI(lena)            (CrocThread* t, word_t slot);
void      CROCAPI(lenai)           (CrocThread* t, word_t slot, crocint_t length);
word_t    CROCAPI(cat)             (CrocThread* t, uword_t num);
void      CROCAPI(cateq)           (CrocThread* t, word_t dest, uword_t num);

// =====================================================================================================================
// Compiler interface

void               CROCAPI(compiler_setFlags)      (CrocThread* t, uword_t flags);
uword_t            CROCAPI(compiler_getFlags)      (CrocThread* t);
CrocCompilerReturn CROCAPI(compiler_compileModule) (CrocThread* t, const char* name, const char** modName);
CrocCompilerReturn CROCAPI(compiler_compileStmts)  (CrocThread* t, const char* name);
CrocCompilerReturn CROCAPI(compiler_compileExpr)   (CrocThread* t, const char* name);

#define croc_compiler_compileModuleEx(t, name, modName)\
	do {\
		CrocThread* _compilerThread_ = (t);\
		CrocCompilerReturn _compilerReturn_ = croc_compiler_compileModule(_compilerThread_, (name), (modName));\
		if(_compilerReturn_ != CrocCompilerReturn_OK)\
			croc_eh_throw(_compilerThread_);\
	} while(0)

#define croc_compiler_compileStmtsEx(t, name)\
	do {\
		CrocThread* _compilerThread_ = (t);\
		CrocCompilerReturn _compilerReturn_ = croc_compiler_compileStmts(_compilerThread_, (name));\
		if(_compilerReturn_ != CrocCompilerReturn_OK)\
			croc_eh_throw(_compilerThread_);\
	} while(0)

#define croc_compiler_compileExprEx(t, name)\
	do {\
		CrocThread* _compilerThread_ = (t);\
		CrocCompilerReturn _compilerReturn_ = croc_compiler_compileExpr(_compilerThread_, (name));\
		if(_compilerReturn_ != CrocCompilerReturn_OK)\
			croc_eh_throw(_compilerThread_);\
	} while(0)

#ifdef __cplusplus
} /* extern "C" */
#endif

#undef CROCAPI

#endif