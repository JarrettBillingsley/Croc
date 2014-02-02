#ifndef CROC_APIFUNCS_H
#define CROC_APIFUNCS_H

#include <stdarg.h>

#include "croc/apitypes.h"

#define CROCAPI(f) croc_##f

#ifdef __cplusplus
extern "C" {
#define DEFAULTPARAM(p, v) p = v
#else
#define DEFAULTPARAM(p, v) p
#endif

// ================================================================================================================================================
// VM-related functions

void*       CROCAPI(DefaultMemFunc)     (void* ctx, void* p, uword_t oldSize, uword_t newSize);
CrocThread* CROCAPI(openVM)             (CrocMemFunc memFunc, void* DEFAULTPARAM(ctx, nullptr));
void        CROCAPI(closeVM)            (CrocThread* t);
void        CROCAPI(loadUnsafeLibs)     (CrocThread* t, unsigned int DEFAULTPARAM(libs, CrocUnsafeLib_All));
void        CROCAPI(loadAddons)         (CrocThread* t, unsigned int libs);
void        CROCAPI(loadAvailableAddons)(CrocThread* t, unsigned int DEFAULTPARAM(exclude, CrocAddons_None));
CrocThread* CROCAPI(mainThread)         (CrocThread* t);
CrocThread* CROCAPI(currentThread)      (CrocThread* t);
uword_t     CROCAPI(bytesAllocated)     (CrocThread* t);
word_t      CROCAPI(getTypeMT)          (CrocThread* t, CrocType type);
void        CROCAPI(setTypeMT)          (CrocThread* t, CrocType type);
word_t      CROCAPI(getRegistry)        (CrocThread* t);
void*       CROCAPI(allocMem)           (CrocThread* t, uword_t size);
void        CROCAPI(resizeMem)          (CrocThread* t, void** mem, uword_t* memSize, uword_t newSize);
void*       CROCAPI(dupMem)             (CrocThread* t, void* mem, uword_t memSize);
void        CROCAPI(freeMem)            (CrocThread* t, void** mem, uword_t* memSize);
crocref_t   CROCAPI(createRef)          (CrocThread* t, word_t idx);
word_t      CROCAPI(pushRef)            (CrocThread* t, crocref_t r);
void        CROCAPI(removeRef)          (CrocThread* t, crocref_t r);

// ================================================================================================================================================
// Stack manipulation

uword_t     CROCAPI(stackSize)          (CrocThread* t);
void        CROCAPI(setStackSize)       (CrocThread* t, uword_t newSize);
word_t      CROCAPI(absIndex)           (CrocThread* t, word_t idx);
int         CROCAPI(isValidIndex)       (CrocThread* t, word_t idx);
word_t      CROCAPI(dup)                (CrocThread* t, word_t DEFAULTPARAM(slot, -1));
void        CROCAPI(swap)               (CrocThread* t, word_t DEFAULTPARAM(first, -2), word_t DEFAULTPARAM(second, -1));
void        CROCAPI(insert)             (CrocThread* t, word_t slot);
void        CROCAPI(insertAndPop)       (CrocThread* t, word_t slot);
void        CROCAPI(moveToTop)          (CrocThread* t, word_t slot);
void        CROCAPI(rotate)             (CrocThread* t, uword_t numSlots, uword_t dist);
void        CROCAPI(rotateAll)          (CrocThread* t, uword_t dist);
void        CROCAPI(pop)                (CrocThread* t, uword_t DEFAULTPARAM(n, 1));
void        CROCAPI(transferVals)       (CrocThread* src, CrocThread* dest, uword_t num);
CrocType    CROCAPI(type)               (CrocThread* t, word_t slot);
word_t      CROCAPI(pushTypeString)     (CrocThread* t, word_t slot);
int         CROCAPI(isNull)             (CrocThread* t, word_t slot);
int         CROCAPI(isBool)             (CrocThread* t, word_t slot);
int         CROCAPI(isInt)              (CrocThread* t, word_t slot);
int         CROCAPI(isFloat)            (CrocThread* t, word_t slot);
int         CROCAPI(isNum)              (CrocThread* t, word_t slot);
int         CROCAPI(isNativeobj)        (CrocThread* t, word_t slot);
int         CROCAPI(isString)           (CrocThread* t, word_t slot);
int         CROCAPI(isChar)             (CrocThread* t, word_t slot);
int         CROCAPI(isWeakRef)          (CrocThread* t, word_t slot);
int         CROCAPI(isTable)            (CrocThread* t, word_t slot);
int         CROCAPI(isNamespace)        (CrocThread* t, word_t slot);
int         CROCAPI(isArray)            (CrocThread* t, word_t slot);
int         CROCAPI(isMemblock)         (CrocThread* t, word_t slot);
int         CROCAPI(isFunction)         (CrocThread* t, word_t slot);
int         CROCAPI(isFuncDef)          (CrocThread* t, word_t slot);
int         CROCAPI(isClass)            (CrocThread* t, word_t slot);
int         CROCAPI(isInstance)         (CrocThread* t, word_t slot);
int         CROCAPI(isThread)           (CrocThread* t, word_t slot);
int         CROCAPI(isTrue)             (CrocThread* t, word_t slot);
word_t      CROCAPI(pushNull)           (CrocThread* t);
word_t      CROCAPI(pushBool)           (CrocThread* t, int v);
word_t      CROCAPI(pushInt)            (CrocThread* t, crocint_t v);
word_t      CROCAPI(pushFloat)          (CrocThread* t, crocfloat_t v);
word_t      CROCAPI(pushString)         (CrocThread* t, const char* v);
word_t      CROCAPI(pushStringn)        (CrocThread* t, const char* v, uword_t len);
word_t      CROCAPI(pushChar)           (CrocThread* t, crocchar_t c);
word_t      CROCAPI(pushFormat)         (CrocThread* t, const char* fmt, ...);
word_t      CROCAPI(pushVFormat)        (CrocThread* t, const char* fmt, va_list args);
word_t      CROCAPI(pushNativeobj)      (CrocThread* t, void* o);
word_t      CROCAPI(pushThread)         (CrocThread* t, CrocThread* o);
int         CROCAPI(getBool)            (CrocThread* t, word_t slot);
crocint_t   CROCAPI(getInt)             (CrocThread* t, word_t slot);
crocfloat_t CROCAPI(getFloat)           (CrocThread* t, word_t slot);
crocfloat_t CROCAPI(getNum)             (CrocThread* t, word_t slot);
crocchar_t  CROCAPI(getChar)            (CrocThread* t, word_t slot);
const char* CROCAPI(getString)          (CrocThread* t, word_t slot);
const char* CROCAPI(getStringn)         (CrocThread* t, word_t slot, uword_t* len);
void*       CROCAPI(getNativeobj)       (CrocThread* t, word_t slot);
CrocThread* CROCAPI(getThread)          (CrocThread* t, word_t slot);

// ================================================================================================================================================
// Debugging

void        CROCAPI(setHookFunc)        (CrocThread* t, uword_t mask, uword_t hookDelay);
word_t      CROCAPI(getHookFunc)        (CrocThread* t);
uword_t     CROCAPI(getHookMask)        (CrocThread* t);
uword_t     CROCAPI(getHookDelay)       (CrocThread* t);
void        CROCAPI(printStack)         (CrocThread* t, int DEFAULTPARAM(wholeStack, false));
void        CROCAPI(printCallStack)     (CrocThread* t);

// ================================================================================================================================================
// GC-related stuff

uword_t     CROCAPI(gc_maybeCollect)    (CrocThread* t);
uword_t     CROCAPI(gc_collect)         (CrocThread* t);
uword_t     CROCAPI(gc_collectFull)     (CrocThread* t);
uword_t     CROCAPI(gc_setLimit)        (CrocThread* t, const char* type, uword_t lim);
uword_t     CROCAPI(gc_getLimit)        (CrocThread* t, const char* type);

// ================================================================================================================================================
// Exception-related functions

void        CROCAPI(throwException)     (CrocThread* t);
void        CROCAPI(throwStdException)  (CrocThread* t, const char* exName, const char* fmt, ...);
void        CROCAPI(vthrowStdException) (CrocThread* t, const char* exName, const char* fmt, va_list args);
word_t      CROCAPI(getStdException)    (CrocThread* t, const char* exName);
int         CROCAPI(isThrowing)         (CrocThread* t);
word_t      CROCAPI(catchException)     (CrocThread* t);
word_t      CROCAPI(pushLocationClass)  (CrocThread* t);
word_t      CROCAPI(pushLocationObject) (CrocThread* t, const char* file, int line, int col);

// ================================================================================================================================================
// Variable-related functions

void        CROCAPI(setUpval)           (CrocThread* t, uword_t idx);
word_t      CROCAPI(getUpval)           (CrocThread* t, uword_t idx);
word_t      CROCAPI(pushEnvironment)    (CrocThread* t, uword_t DEFAULTPARAM(depth, 0));
void        CROCAPI(newGlobal)          (CrocThread* t, const char* name);
void        CROCAPI(newGlobalStack)     (CrocThread* t);
word_t      CROCAPI(getGlobal)          (CrocThread* t, const char* name);
word_t      CROCAPI(getGlobalStack)     (CrocThread* t);
void        CROCAPI(setGlobal)          (CrocThread* t, const char* name);
void        CROCAPI(setGlobalStack)     (CrocThread* t);
int         CROCAPI(findGlobal)         (CrocThread* t, const char* name, uword_t DEFAULTPARAM(depth, 0));

// ================================================================================================================================================
// Table-related functions

word_t      CROCAPI(table_new)          (CrocThread* t, uword_t DEFAULTPARAM(size, 0));
void        CROCAPI(table_clear)        (CrocThread* t, word_t tab);

// ================================================================================================================================================
// Array-related functions

word_t      CROCAPI(array_new)          (CrocThread* t, uword_t len);
word_t      CROCAPI(array_newFromStack) (CrocThread* t, uword_t len);
void        CROCAPI(array_fill)         (CrocThread* t, word_t arr);

// ================================================================================================================================================
// Memblock-related functions

word_t      CROCAPI(memblock_new)               (CrocThread* t, uword_t len);
word_t      CROCAPI(memblock_fromNativeArray)   (CrocThread* t, void* arr, uword_t arrLen);
word_t      CROCAPI(memblock_viewNativeArray)   (CrocThread* t, void* arr, uword_t arrLen);
void        CROCAPI(memblock_reviewNativeArray) (CrocThread* t, word_t slot, void* arr, uword_t arrLen);
char*       CROCAPI(memblock_getData)           (CrocThread* t, word_t slot);
char*       CROCAPI(memblock_getDatan)          (CrocThread* t, word_t slot, uword_t* len);

// ================================================================================================================================================
// Function-related functions

word_t      CROCAPI(function_new)              (CrocThread* t, uword_t numParams, CrocNativeFunc func, const char* name, uword_t DEFAULTPARAM(numUpvals, 0));
word_t      CROCAPI(function_newWithEnv)       (CrocThread* t, uword_t numParams, CrocNativeFunc func, const char* name, uword_t DEFAULTPARAM(numUpvals, 0));
word_t      CROCAPI(function_newVA)            (CrocThread* t, CrocNativeFunc func, const char* name, uword_t DEFAULTPARAM(numUpvals, 0));
word_t      CROCAPI(function_newVAWithEnv)     (CrocThread* t, CrocNativeFunc func, const char* name, uword_t DEFAULTPARAM(numUpvals, 0));
word_t      CROCAPI(function_newScript)        (CrocThread* t, word_t funcDef);
word_t      CROCAPI(function_newScriptWithEnv) (CrocThread* t, word_t funcDef);
word_t      CROCAPI(function_getEnv)           (CrocThread* t, word_t func);
void        CROCAPI(function_setEnv)           (CrocThread* t, word_t func);
void        CROCAPI(function_def)              (CrocThread* t, word_t func);
const char* CROCAPI(function_name)             (CrocThread* t, word_t func);
const char* CROCAPI(function_namen)            (CrocThread* t, word_t func, uword_t* len);
uword_t     CROCAPI(function_numParams)        (CrocThread* t, word_t func);
uword_t     CROCAPI(function_maxParams)        (CrocThread* t, word_t func);
int         CROCAPI(function_isVararg)         (CrocThread* t, word_t func);
int         CROCAPI(function_isNative)         (CrocThread* t, word_t func);

// ================================================================================================================================================
// Class-related functions

word_t       CROCAPI(class_new)                    (CrocThread* t, const char* name, uword_t numBases);
const char*  CROCAPI(class_name)                   (CrocThread* t, word_t cls);
const char*  CROCAPI(class_namen)                  (CrocThread* t, word_t cls, uword_t* len);
void         CROCAPI(class_addField)               (CrocThread* t, word_t cls, const char* name);
void         CROCAPI(class_addFieldStack)          (CrocThread* t, word_t cls);
void         CROCAPI(class_addMethod)              (CrocThread* t, word_t cls, const char* name);
void         CROCAPI(class_addMethodStack)         (CrocThread* t, word_t cls);
void         CROCAPI(class_addFieldOver)           (CrocThread* t, word_t cls, const char* name);
void         CROCAPI(class_addFieldOverStack)      (CrocThread* t, word_t cls);
void         CROCAPI(class_addMethodOver)          (CrocThread* t, word_t cls, const char* name);
void         CROCAPI(class_addMethodOverStack)     (CrocThread* t, word_t cls);
void         CROCAPI(class_addHiddenField)         (CrocThread* t, word_t cls, const char* name);
void         CROCAPI(class_addHiddenFieldStack)    (CrocThread* t, word_t cls);
void         CROCAPI(class_removeMember)           (CrocThread* t, word_t cls, const char* name);
void         CROCAPI(class_removeMemberStack)      (CrocThread* t, word_t cls);
void         CROCAPI(class_removeHiddenField)      (CrocThread* t, word_t cls, const char* name);
void         CROCAPI(class_removeHiddenFieldStack) (CrocThread* t, word_t cls);
void         CROCAPI(class_freeze)                 (CrocThread* t, word_t cls);
int          CROCAPI(class_isFrozen)               (CrocThread* t, word_t cls);

// ================================================================================================================================================
// Namespace-related functions

word_t       CROCAPI(namespace_new)         (CrocThread* t, const char* name);
word_t       CROCAPI(namespace_newParent)   (CrocThread* t, word_t parent, const char* name);
word_t       CROCAPI(namespace_newNoParent) (CrocThread* t, const char* name);
void         CROCAPI(namespace_clear)       (CrocThread* t, word_t ns);
const char*  CROCAPI(namespace_name)        (CrocThread* t, word_t ns);
const char*  CROCAPI(namespace_namen)       (CrocThread* t, word_t ns, uword_t* len);
word_t       CROCAPI(namespace_fullName)    (CrocThread* t, word_t ns);

// ================================================================================================================================================
// Thread-specific stuff

word_t           CROCAPI(thread_new)            (CrocThread* t, word_t func);
CrocThreadState  CROCAPI(thread_state)          (CrocThread* t);
const char*      CROCAPI(thread_stateString)    (CrocThread* t);
uword_t          CROCAPI(thread_callDepth)      (CrocThread* t);
void             CROCAPI(thread_reset)          (CrocThread* t, word_t slot, int DEFAULTPARAM(newFunction, false));
void             CROCAPI(thread_halt)           (CrocThread* t);
void             CROCAPI(thread_pendingHalt)    (CrocThread* t);
int              CROCAPI(thread_hasPendingHalt) (CrocThread* t);

// ================================================================================================================================================
// Weakref-related functions

word_t CROCAPI(weakref_push)  (CrocThread* t, word_t idx);
word_t CROCAPI(weakref_deref) (CrocThread* t, word_t idx);

// ================================================================================================================================================
// Funcdef-related functions

const char* CROCAPI(funcdef_name)  (CrocThread* t, word_t funcdef);
const char* CROCAPI(funcdef_namen) (CrocThread* t, word_t funcdef, uword_t* len);

// ================================================================================================================================================
// Atomic Croc operations

// struct foreachLoop
void      CROCAPI(removeKey)      (CrocThread* t, word_t obj);
word_t    CROCAPI(pushToString)   (CrocThread* t, word_t slot, int raw = false);
int       CROCAPI(in)             (CrocThread* t, word_t item, word_t container);
crocint_t CROCAPI(cmp)            (CrocThread* t, word_t a, word_t b);
int       CROCAPI(equals)         (CrocThread* t, word_t a, word_t b);
int       CROCAPI(is)             (CrocThread* t, word_t a, word_t b);
word_t    CROCAPI(idx)            (CrocThread* t, word_t container);
void      CROCAPI(idxa)           (CrocThread* t, word_t container);
word_t    CROCAPI(idxi)           (CrocThread* t, word_t container, crocint_t idx);
void      CROCAPI(idxai)          (CrocThread* t, word_t container, crocint_t idx);
word_t    CROCAPI(field)          (CrocThread* t, word_t container, const char* name);
word_t    CROCAPI(fieldStack)     (CrocThread* t, word_t container);
void      CROCAPI(fielda)         (CrocThread* t, word_t container, const char* name);
void      CROCAPI(fieldaStack)    (CrocThread* t, word_t container);
word_t    CROCAPI(rawField)       (CrocThread* t, word_t container, const char* name);
word_t    CROCAPI(rawFieldStack)  (CrocThread* t, word_t container);
void      CROCAPI(rawFielda)      (CrocThread* t, word_t container, const char* name);
void      CROCAPI(rawFieldaStack) (CrocThread* t, word_t container);
word_t    CROCAPI(hfield)         (CrocThread* t, word_t container, const char* name);
word_t    CROCAPI(hfieldStack)    (CrocThread* t, word_t container);
void      CROCAPI(hfielda)        (CrocThread* t, word_t container, const char* name);
void      CROCAPI(hfieldaStack)   (CrocThread* t, word_t container);
word_t    CROCAPI(pushLen)        (CrocThread* t, word_t slot);
crocint_t CROCAPI(len)            (CrocThread* t, word_t slot);
void      CROCAPI(lena)           (CrocThread* t, word_t slot);
void      CROCAPI(lenai)          (CrocThread* t, word_t slot, crocint_t length);
word_t    CROCAPI(slice)          (CrocThread* t, word_t container);
void      CROCAPI(slicea)         (CrocThread* t, word_t container);
word_t    CROCAPI(cat)            (CrocThread* t, uword_t num);
void      CROCAPI(cateq)          (CrocThread* t, word_t dest, uword_t num);
int       CROCAPI(instanceOf)     (CrocThread* t, word_t obj, word_t base);
word_t    CROCAPI(superOf)        (CrocThread* t, word_t slot);

// ================================================================================================================================================
// Function calling

uword_t   CROCAPI(call)            (CrocThread* t, word_t slot, word_t numReturns);
uword_t   CROCAPI(methodCall)      (CrocThread* t, word_t slot, const char* name, word_t numReturns);
uword_t   CROCAPI(methodCallStack) (CrocThread* t, word_t slot, word_t numReturns);

// ================================================================================================================================================
// Reflective functions
const char* CROCAPI(nameOf)         (CrocThread* t, word_t obj);
const char* CROCAPI(nameOfn)        (CrocThread* t, word_t obj, uword_t* len);
int         CROCAPI(hasField)       (CrocThread* t, word_t obj, const char* fieldName);
int         CROCAPI(hasFieldStack)  (CrocThread* t, word_t obj, word_t name);
int         CROCAPI(hasMethod)      (CrocThread* t, word_t obj, const char* methodName);
int         CROCAPI(hasMethodStack) (CrocThread* t, word_t obj, word_t name);

#ifdef __cplusplus
} /* extern "C" */
#endif

#undef CROCAPI

#endif