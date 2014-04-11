/** @file */

#ifndef CROC_APIFUNCS_H
#define CROC_APIFUNCS_H

#include <stdarg.h>

#include "croc/apitypes.h"

#define CROCAPI
#define CROCPRINT(a, b) __attribute__((format(printf, a, b)))

#ifdef __cplusplus
extern "C" {
#endif

/*====================================================================================================================*/
/** @defgroup VMinit VM initialization and teardown
@ingroup API
Creating, setting up, and destroying Croc VMs. */
/**@{*/
CROCAPI void*        croc_DefaultMemFunc               (void* ctx, void* p, uword_t oldSize, uword_t newSize);
CROCAPI CrocThread*  croc_vm_open                      (CrocMemFunc memFunc, void* ctx);
CROCAPI const char** croc_vm_includedAddons            ();
CROCAPI void         croc_vm_close                     (CrocThread* t);
CROCAPI void         croc_vm_loadUnsafeLibs            (CrocThread* t, CrocUnsafeLib libs);
CROCAPI void         croc_vm_loadAddons                (CrocThread* t, CrocAddons libs);
CROCAPI void         croc_vm_loadAvailableAddonsExcept (CrocThread* t, CrocAddons exclude);

/** Opens a croc VM using \ref croc_DefaultMemFunc as the allocator. */
#define croc_vm_openDefault() (croc_vm_open(&croc_DefaultMemFunc, 0))

/** Loads all unsafe libraries into the given thread's VM. */
#define croc_vm_loadAllUnsafeLibs(t) (croc_vm_loadUnsafeLibs((t), CrocUnsafeLib_All))

/** Loads all available addons (all which have been compile in) into the given thread's VM. */
#define croc_vm_loadAllAvailableAddons(t) (croc_vm_loadAvailableAddonsExcept((t), CrocAddons_None))
/**@}*/
/*====================================================================================================================*/
/** @defgroup VMother VM other
@ingroup API
Accessing other VM-level objects and features. */
/**@{*/
CROCAPI CrocThread* croc_vm_getMainThread      (CrocThread* t);
CROCAPI CrocThread* croc_vm_getCurrentThread   (CrocThread* t);
CROCAPI uword_t     croc_vm_bytesAllocated     (CrocThread* t);
CROCAPI word_t      croc_vm_pushTypeMT         (CrocThread* t, CrocType type);
CROCAPI void        croc_vm_setTypeMT          (CrocThread* t, CrocType type);
CROCAPI word_t      croc_vm_pushRegistry       (CrocThread* t);
/**@}*/
/*====================================================================================================================*/
/** @defgroup RawMM Raw memory management
@ingroup API
Allocating and freeing arbitrary blocks of memory through a Croc VM. */
/**@{*/
CROCAPI void* croc_mem_alloc  (CrocThread* t, uword_t size);
CROCAPI void  croc_mem_resize (CrocThread* t, void** mem, uword_t* memSize, uword_t newSize);
CROCAPI void* croc_mem_dup    (CrocThread* t, void* mem, uword_t memSize);
CROCAPI void  croc_mem_free   (CrocThread* t, void** mem, uword_t* memSize);
/**@}*/
/*====================================================================================================================*/
/** @defgroup NativeRef Native references
@ingroup API
Pinning Croc objects, letting native code hold on to references to them. */
/**@{*/
CROCAPI crocref_t croc_ref_create (CrocThread* t, word_t idx);
CROCAPI word_t    croc_ref_push   (CrocThread* t, crocref_t r);
CROCAPI void      croc_ref_remove (CrocThread* t, crocref_t r);
/**@}*/
/*====================================================================================================================*/
/** @defgroup Debugging Debugging
@ingroup API
Debugging. */
/**@{*/
CROCAPI void    croc_debug_setHookFunc     (CrocThread* t, uword_t mask, uword_t hookDelay);
CROCAPI word_t  croc_debug_pushHookFunc    (CrocThread* t);
CROCAPI uword_t croc_debug_getHookMask     (CrocThread* t);
CROCAPI uword_t croc_debug_getHookDelay    (CrocThread* t);
CROCAPI void    croc_debug_printStack      (CrocThread* t);
CROCAPI void    croc_debug_printWholeStack (CrocThread* t);
CROCAPI void    croc_debug_printCallStack  (CrocThread* t);
/**@}*/
/*====================================================================================================================*/
/** @defgroup GC GC
@ingroup API
Controlling the garbage collector. */
/**@{*/
CROCAPI uword_t croc_gc_maybeCollect (CrocThread* t);
CROCAPI uword_t croc_gc_collect      (CrocThread* t);
CROCAPI uword_t croc_gc_collectFull  (CrocThread* t);
CROCAPI uword_t croc_gc_setLimit     (CrocThread* t, CrocGCLimit type, uword_t lim);
CROCAPI uword_t croc_gc_getLimit     (CrocThread* t, CrocGCLimit type);
/**@}*/
/*====================================================================================================================*/
/** @defgroup EH Exceptions
@ingroup API
Throwing exceptions, and more. */
/**@{*/
CROCAPI word_t croc_eh_throw                 (CrocThread* t);
CROCAPI word_t croc_eh_rethrow               (CrocThread* t);
CROCAPI word_t croc_eh_pushStd               (CrocThread* t, const char* exName);
CROCAPI word_t croc_eh_throwStd              (CrocThread* t, const char* exName, const char* fmt, ...) CROCPRINT(3, 4);
CROCAPI word_t croc_eh_vthrowStd             (CrocThread* t, const char* exName, const char* fmt, va_list args);
CROCAPI word_t croc_eh_pushLocationClass     (CrocThread* t);
CROCAPI word_t croc_eh_pushLocationObject    (CrocThread* t, const char* file, int line, int col);
CROCAPI void   croc_eh_setUnhandledExHandler (CrocThread* t);
/**@}*/
/*====================================================================================================================*/
/** @defgroup Stack Stack manipulation
@ingroup API
Moving around stack slots. */
/**@{*/
CROCAPI uword_t croc_getStackSize (CrocThread* t);
CROCAPI void    croc_setStackSize (CrocThread* t, uword_t newSize);
CROCAPI word_t  croc_absIndex     (CrocThread* t, word_t idx);
CROCAPI int     croc_isValidIndex (CrocThread* t, word_t idx);
CROCAPI word_t  croc_dup          (CrocThread* t, word_t slot);
CROCAPI void    croc_swap         (CrocThread* t, word_t first, word_t second);
CROCAPI void    croc_copy         (CrocThread* t, word_t src, word_t dest);
CROCAPI void    croc_replace      (CrocThread* t, word_t dest);
CROCAPI void    croc_insert       (CrocThread* t, word_t slot);
CROCAPI void    croc_insertAndPop (CrocThread* t, word_t slot);
CROCAPI void    croc_remove       (CrocThread* t, word_t slot);
CROCAPI void    croc_moveToTop    (CrocThread* t, word_t slot);
CROCAPI void    croc_rotate       (CrocThread* t, uword_t numSlots, uword_t dist);
CROCAPI void    croc_rotateAll    (CrocThread* t, uword_t dist);
CROCAPI void    croc_pop          (CrocThread* t, uword_t n);
CROCAPI void    croc_transferVals (CrocThread* src, CrocThread* dest, uword_t num);

/** Pushes a copy of the top stack slot. */
#define croc_dupTop(t) (croc_dup((t), -1))

/** Swaps the top two stack slots. */
#define croc_swapTop(t) (croc_swap((t), -2, -1))

/** Swaps the top stack slot with slot \c n. */
#define croc_swapTopWith(t, n) (croc_swap((t), (n), -1))

/** Pops the top stack slot. */
#define croc_popTop(t) (croc_pop((t), 1))

/** Copies the top stack slot into slot \c idx. */
#define croc_copyTopTo(t, idx) (croc_copy((t), -1, (idx)))

/** Copies slot \c idx into the top stack slot. */
#define croc_copyToTop(t, idx) (croc_copy((t), (idx), -1))
/**@}*/
/*====================================================================================================================*/
/** @defgroup TypeQ Type queries
@ingroup API
Checking the types of values. */
/**@{*/
CROCAPI CrocType croc_type           (CrocThread* t, word_t slot);
CROCAPI word_t   croc_pushTypeString (CrocThread* t, word_t slot);
CROCAPI int      croc_isTrue         (CrocThread* t, word_t slot);
CROCAPI int      croc_isNum          (CrocThread* t, word_t slot);
CROCAPI int      croc_isChar         (CrocThread* t, word_t slot);

/** These are all convenience macros which evaluate to nonzero if the given slot is the given type. */
#define croc_isNull(t, slot)      (croc_type((t), (slot)) == CrocType_Null)
#define croc_isBool(t, slot)      (croc_type((t), (slot)) == CrocType_Bool)      /**< @copydoc croc_isNull */
#define croc_isInt(t, slot)       (croc_type((t), (slot)) == CrocType_Int)       /**< @copydoc croc_isNull */
#define croc_isFloat(t, slot)     (croc_type((t), (slot)) == CrocType_Float)     /**< @copydoc croc_isNull */
#define croc_isNativeobj(t, slot) (croc_type((t), (slot)) == CrocType_Nativeobj) /**< @copydoc croc_isNull */
#define croc_isString(t, slot)    (croc_type((t), (slot)) == CrocType_String)    /**< @copydoc croc_isNull */
#define croc_isWeakref(t, slot)   (croc_type((t), (slot)) == CrocType_Weakref)   /**< @copydoc croc_isNull */
#define croc_isTable(t, slot)     (croc_type((t), (slot)) == CrocType_Table)     /**< @copydoc croc_isNull */
#define croc_isNamespace(t, slot) (croc_type((t), (slot)) == CrocType_Namespace) /**< @copydoc croc_isNull */
#define croc_isArray(t, slot)     (croc_type((t), (slot)) == CrocType_Array)     /**< @copydoc croc_isNull */
#define croc_isMemblock(t, slot)  (croc_type((t), (slot)) == CrocType_Memblock)  /**< @copydoc croc_isNull */
#define croc_isFunction(t, slot)  (croc_type((t), (slot)) == CrocType_Function)  /**< @copydoc croc_isNull */
#define croc_isFuncdef(t, slot)   (croc_type((t), (slot)) == CrocType_Funcdef)   /**< @copydoc croc_isNull */
#define croc_isClass(t, slot)     (croc_type((t), (slot)) == CrocType_Class)     /**< @copydoc croc_isNull */
#define croc_isInstance(t, slot)  (croc_type((t), (slot)) == CrocType_Instance)  /**< @copydoc croc_isNull */
#define croc_isThread(t, slot)    (croc_type((t), (slot)) == CrocType_Thread)    /**< @copydoc croc_isNull */
/**@}*/
/*====================================================================================================================*/
/** @defgroup Variables Variables
@ingroup API
Globals, upvalues, and environments. */
/**@{*/
CROCAPI word_t croc_pushEnvironment (CrocThread* t, uword_t depth);
CROCAPI void   croc_setUpval        (CrocThread* t, uword_t idx);
CROCAPI word_t croc_pushUpval       (CrocThread* t, uword_t idx);
CROCAPI void   croc_newGlobal       (CrocThread* t, const char* name);
CROCAPI void   croc_newGlobalStk    (CrocThread* t);
CROCAPI word_t croc_pushGlobal      (CrocThread* t, const char* name);
CROCAPI word_t croc_pushGlobalStk   (CrocThread* t);
CROCAPI void   croc_setGlobal       (CrocThread* t, const char* name);
CROCAPI void   croc_setGlobalStk    (CrocThread* t);

/** Pushes the environment namespace of the currently-executing function. */
#define croc_pushCurEnvironment(t) (croc_pushEnvironment((t), 0))
/**@}*/
/*====================================================================================================================*/
/** @defgroup Calls Function calling
@ingroup API
Function calling and the native equivalent of 'try'. */
/**@{*/
CROCAPI uword_t croc_call          (CrocThread* t, word_t slot, word_t numReturns);
CROCAPI uword_t croc_methodCall    (CrocThread* t, word_t slot, const char* name, word_t numReturns);
CROCAPI int     croc_tryCall       (CrocThread* t, word_t slot, word_t numReturns);
CROCAPI int     croc_tryMethodCall (CrocThread* t, word_t slot, const char* name, word_t numReturns);
/**@}*/
/*====================================================================================================================*/
/** @defgroup Reflection Reflection
@ingroup API
Various kinds of introspection. */
/**@{*/
CROCAPI const char* croc_getNameOf    (CrocThread* t, word_t obj);
CROCAPI const char* croc_getNameOfn   (CrocThread* t, word_t obj, uword_t* len);
CROCAPI int         croc_hasField     (CrocThread* t, word_t obj, const char* fieldName);
CROCAPI int         croc_hasFieldStk  (CrocThread* t, word_t obj, word_t name);
CROCAPI int         croc_hasMethod    (CrocThread* t, word_t obj, const char* methodName);
CROCAPI int         croc_hasMethodStk (CrocThread* t, word_t obj, word_t name);
CROCAPI int         croc_hasHField    (CrocThread* t, word_t obj, const char* fieldName);
CROCAPI int         croc_hasHFieldStk (CrocThread* t, word_t obj, word_t name);
CROCAPI int         croc_isInstanceOf (CrocThread* t, word_t obj, word_t base);
CROCAPI word_t      croc_superOf      (CrocThread* t, word_t slot);
/**@}*/
/*====================================================================================================================*/
/** @defgroup ValueTypes Value types
@ingroup API
Pushing and getting the Croc value types. */
/**@{*/
CROCAPI word_t      croc_pushNull      (CrocThread* t);
CROCAPI word_t      croc_pushBool      (CrocThread* t, int v);
CROCAPI word_t      croc_pushInt       (CrocThread* t, crocint_t v);
CROCAPI word_t      croc_pushFloat     (CrocThread* t, crocfloat_t v);
CROCAPI word_t      croc_pushString    (CrocThread* t, const char* v);
CROCAPI word_t      croc_pushStringn   (CrocThread* t, const char* v, uword_t len);
CROCAPI word_t      croc_pushChar      (CrocThread* t, crocchar_t c);
CROCAPI word_t      croc_pushFormat    (CrocThread* t, const char* fmt, ...) CROCPRINT(2, 3);
CROCAPI word_t      croc_vpushFormat   (CrocThread* t, const char* fmt, va_list args);
CROCAPI word_t      croc_pushNativeobj (CrocThread* t, void* o);
CROCAPI word_t      croc_pushThread    (CrocThread* t, CrocThread* o);
CROCAPI int         croc_getBool       (CrocThread* t, word_t slot);
CROCAPI crocint_t   croc_getInt        (CrocThread* t, word_t slot);
CROCAPI crocfloat_t croc_getFloat      (CrocThread* t, word_t slot);
CROCAPI crocfloat_t croc_getNum        (CrocThread* t, word_t slot);
CROCAPI crocchar_t  croc_getChar       (CrocThread* t, word_t slot);
CROCAPI const char* croc_getString     (CrocThread* t, word_t slot);
CROCAPI const char* croc_getStringn    (CrocThread* t, word_t slot, uword_t* len);
CROCAPI void*       croc_getNativeobj  (CrocThread* t, word_t slot);
CROCAPI CrocThread* croc_getThread     (CrocThread* t, word_t slot);
/**@}*/
/*====================================================================================================================*/
/** @defgroup Weakrefs Weakrefs
@ingroup API
Functions which operate on weakrefs. */
/**@{*/
CROCAPI word_t croc_weakref_push  (CrocThread* t, word_t idx);
CROCAPI word_t croc_weakref_deref (CrocThread* t, word_t idx);
/**@}*/
/*====================================================================================================================*/
/** @defgroup Tables Tables
@ingroup API
Functions which operate on tables. */
/**@{*/
CROCAPI word_t croc_table_new   (CrocThread* t, uword_t size);
CROCAPI void   croc_table_clear (CrocThread* t, word_t tab);
/**@}*/
/*====================================================================================================================*/
/** @defgroup Namespaces Namespaces
@ingroup API
Functions which operate on namespaces. */
/**@{*/
CROCAPI word_t      croc_namespace_new           (CrocThread* t, const char* name);
CROCAPI word_t      croc_namespace_newWithParent (CrocThread* t, word_t parent, const char* name);
CROCAPI word_t      croc_namespace_newNoParent   (CrocThread* t, const char* name);
CROCAPI void        croc_namespace_clear         (CrocThread* t, word_t ns);
CROCAPI word_t      croc_namespace_pushFullName  (CrocThread* t, word_t ns);
/**@}*/
/*====================================================================================================================*/
/** @defgroup Arrays Arrays
@ingroup API
Functions which operate on arrays. */
/**@{*/
CROCAPI word_t croc_array_new          (CrocThread* t, uword_t len);
CROCAPI word_t croc_array_newFromStack (CrocThread* t, uword_t len);
CROCAPI void   croc_array_fill         (CrocThread* t, word_t arr);
/**@}*/
/*====================================================================================================================*/
/** @defgroup Memblocks Memblocks
@ingroup API
Functions which operate on memblocks. */
/**@{*/
CROCAPI word_t croc_memblock_new               (CrocThread* t, uword_t len);
CROCAPI word_t croc_memblock_fromNativeArray   (CrocThread* t, void* arr, uword_t arrLen);
CROCAPI word_t croc_memblock_viewNativeArray   (CrocThread* t, void* arr, uword_t arrLen);
CROCAPI void   croc_memblock_reviewNativeArray (CrocThread* t, word_t slot, void* arr, uword_t arrLen);
CROCAPI char*  croc_memblock_getData           (CrocThread* t, word_t slot);
CROCAPI char*  croc_memblock_getDatan          (CrocThread* t, word_t slot, uword_t* len);
CROCAPI int    croc_memblock_ownData           (CrocThread* t, word_t slot);
/**@}*/
/*====================================================================================================================*/
/** @defgroup Functions Functions
@ingroup API
Functions which operate on function closures. */
/**@{*/
CROCAPI word_t      croc_function_newWithEnv       (CrocThread* t, const char* name, word_t maxParams, CrocNativeFunc func, uword_t numUpvals);
CROCAPI word_t      croc_function_newScript        (CrocThread* t, word_t funcdef);
CROCAPI word_t      croc_function_newScriptWithEnv (CrocThread* t, word_t funcdef);
CROCAPI word_t      croc_function_pushEnv          (CrocThread* t, word_t func);
CROCAPI void        croc_function_setEnv           (CrocThread* t, word_t func);
CROCAPI word_t      croc_function_pushDef          (CrocThread* t, word_t func);
CROCAPI uword_t     croc_function_getNumParams     (CrocThread* t, word_t func);
CROCAPI uword_t     croc_function_getMaxParams     (CrocThread* t, word_t func);
CROCAPI int         croc_function_isVararg         (CrocThread* t, word_t func);
CROCAPI int         croc_function_isNative         (CrocThread* t, word_t func);

#define croc_function_new(t, name, maxParams, func, numUpvals)\
	(croc_pushCurEnvironment(t), croc_function_newWithEnv((t), (name), (maxParams), (func), (numUpvals)))
/**@}*/
/*====================================================================================================================*/
/** @defgroup Classes Classes
@ingroup API
Functions which operate on classes. */
/**@{*/
CROCAPI word_t      croc_class_new             (CrocThread* t, const char* name, uword_t numBases);
CROCAPI void        croc_class_addField        (CrocThread* t, word_t cls, const char* name);
CROCAPI void        croc_class_addFieldStk     (CrocThread* t, word_t cls);
CROCAPI void        croc_class_addMethod       (CrocThread* t, word_t cls, const char* name);
CROCAPI void        croc_class_addMethodStk    (CrocThread* t, word_t cls);
CROCAPI void        croc_class_addFieldO       (CrocThread* t, word_t cls, const char* name);
CROCAPI void        croc_class_addFieldOStk    (CrocThread* t, word_t cls);
CROCAPI void        croc_class_addMethodO      (CrocThread* t, word_t cls, const char* name);
CROCAPI void        croc_class_addMethodOStk   (CrocThread* t, word_t cls);
CROCAPI void        croc_class_removeMember    (CrocThread* t, word_t cls, const char* name);
CROCAPI void        croc_class_removeMemberStk (CrocThread* t, word_t cls);
CROCAPI void        croc_class_addHField       (CrocThread* t, word_t cls, const char* name);
CROCAPI void        croc_class_addHFieldStk    (CrocThread* t, word_t cls);
CROCAPI void        croc_class_removeHField    (CrocThread* t, word_t cls, const char* name);
CROCAPI void        croc_class_removeHFieldStk (CrocThread* t, word_t cls);
CROCAPI void        croc_class_freeze          (CrocThread* t, word_t cls);
CROCAPI int         croc_class_isFrozen        (CrocThread* t, word_t cls);
/**@}*/
/*====================================================================================================================*/
/** @defgroup Threads Threads
@ingroup API
Functions which operate on threads. */
/**@{*/
CROCAPI word_t          croc_thread_new            (CrocThread* t, word_t func);
CROCAPI CrocThreadState croc_thread_getState       (CrocThread* t);
CROCAPI const char*     croc_thread_getStateString (CrocThread* t);
CROCAPI uword_t         croc_thread_getCallDepth   (CrocThread* t);
CROCAPI void            croc_thread_reset          (CrocThread* t, word_t slot);
CROCAPI void            croc_thread_resetWithFunc  (CrocThread* t, word_t slot);
CROCAPI void            croc_thread_halt           (CrocThread* t);
CROCAPI void            croc_thread_pendingHalt    (CrocThread* t);
CROCAPI int             croc_thread_hasPendingHalt (CrocThread* t);
/**@}*/
/*====================================================================================================================*/
/** @defgroup Basic Basic operations
@ingroup API
All sorts of simple operations on values of any type. */
/**@{*/
CROCAPI word_t    croc_foreachBegin    (CrocThread* t, uword_t numContainerVals);
CROCAPI int       croc_foreachNext     (CrocThread* t, word_t state, uword_t numIndices);
CROCAPI void      croc_foreachEnd      (CrocThread* t, word_t state);
CROCAPI void      croc_removeKey       (CrocThread* t, word_t obj);
CROCAPI word_t    croc_pushToString    (CrocThread* t, word_t slot);
CROCAPI word_t    croc_pushToStringRaw (CrocThread* t, word_t slot);
CROCAPI int       croc_in              (CrocThread* t, word_t item, word_t container);
CROCAPI crocint_t croc_cmp             (CrocThread* t, word_t a, word_t b);
CROCAPI int       croc_equals          (CrocThread* t, word_t a, word_t b);
CROCAPI int       croc_is              (CrocThread* t, word_t a, word_t b);
CROCAPI word_t    croc_idx             (CrocThread* t, word_t container);
CROCAPI void      croc_idxa            (CrocThread* t, word_t container);
CROCAPI word_t    croc_idxi            (CrocThread* t, word_t container, crocint_t idx);
CROCAPI void      croc_idxai           (CrocThread* t, word_t container, crocint_t idx);
CROCAPI word_t    croc_slice           (CrocThread* t, word_t container);
CROCAPI void      croc_slicea          (CrocThread* t, word_t container);
CROCAPI word_t    croc_field           (CrocThread* t, word_t container, const char* name);
CROCAPI word_t    croc_fieldStk        (CrocThread* t, word_t container);
CROCAPI void      croc_fielda          (CrocThread* t, word_t container, const char* name);
CROCAPI void      croc_fieldaStk       (CrocThread* t, word_t container);
CROCAPI word_t    croc_rawField        (CrocThread* t, word_t container, const char* name);
CROCAPI word_t    croc_rawFieldStk     (CrocThread* t, word_t container);
CROCAPI void      croc_rawFielda       (CrocThread* t, word_t container, const char* name);
CROCAPI void      croc_rawFieldaStk    (CrocThread* t, word_t container);
CROCAPI word_t    croc_hfield          (CrocThread* t, word_t container, const char* name);
CROCAPI word_t    croc_hfieldStk       (CrocThread* t, word_t container);
CROCAPI void      croc_hfielda         (CrocThread* t, word_t container, const char* name);
CROCAPI void      croc_hfieldaStk      (CrocThread* t, word_t container);
CROCAPI word_t    croc_pushLen         (CrocThread* t, word_t slot);
CROCAPI crocint_t croc_len             (CrocThread* t, word_t slot);
CROCAPI void      croc_lena            (CrocThread* t, word_t slot);
CROCAPI void      croc_lenai           (CrocThread* t, word_t slot, crocint_t length);
CROCAPI word_t    croc_cat             (CrocThread* t, uword_t num);
CROCAPI void      croc_cateq           (CrocThread* t, word_t dest, uword_t num);
/**@}*/
/*====================================================================================================================*/
/** @defgroup Compiler Compiler
@ingroup API
The interface to the Croc compiler. */
/**@{*/
CROCAPI uword_t croc_compiler_setFlags             (CrocThread* t, uword_t flags);
CROCAPI uword_t croc_compiler_getFlags             (CrocThread* t);
CROCAPI int     croc_compiler_compileModule        (CrocThread* t, const char* name, const char** modName);
CROCAPI int     croc_compiler_compileStmts         (CrocThread* t, const char* name);
CROCAPI int     croc_compiler_compileExpr          (CrocThread* t, const char* name);
CROCAPI int     croc_compiler_compileModuleDT      (CrocThread* t, const char* name, const char** modName);
CROCAPI int     croc_compiler_compileStmtsDT       (CrocThread* t, const char* name);
CROCAPI word_t  croc_compiler_processDocComment    (CrocThread* t);
CROCAPI word_t  croc_compiler_parseDocCommentText  (CrocThread* t);

/** Like \ref croc_compiler_compileModule, but if compilation failed, rethrows the exception. Also returns nothing. */
#define croc_compiler_compileModuleEx(t, name, modName)\
	do {\
		CrocThread* _compilerThread_ = (t);\
		if(croc_compiler_compileModule(_compilerThread_, (name), (modName)) < 0)\
			croc_eh_throw(_compilerThread_);\
	} while(0)

/** Like \ref croc_compiler_compileStmts, but if compilation failed, rethrows the exception. Also returns nothing. */
#define croc_compiler_compileStmtsEx(t, name)\
	do {\
		CrocThread* _compilerThread_ = (t);\
		if(croc_compiler_compileStmts(_compilerThread_, (name)) < 0)\
			croc_eh_throw(_compilerThread_);\
	} while(0)

/** Like \ref croc_compiler_compileExpr, but if compilation failed, rethrows the exception. Also returns nothing. */
#define croc_compiler_compileExprEx(t, name)\
	do {\
		CrocThread* _compilerThread_ = (t);\
		if(croc_compiler_compileExpr(_compilerThread_, (name)) < 0)\
			croc_eh_throw(_compilerThread_);\
	} while(0)

/** Like \ref croc_compiler_compileModuleDT, but if compilation failed, rethrows the exception. Also returns nothing. */
#define croc_compiler_compileModuleDTEx(t, name, modName)\
	do {\
		CrocThread* _compilerThread_ = (t);\
		if(croc_compiler_compileModuleDT(_compilerThread_, (name), (modName)) < 0)\
			croc_eh_throw(_compilerThread_);\
	} while(0)

/** Like \ref croc_compiler_compileStmtsDT, but if compilation failed, rethrows the exception. Also returns nothing. */
#define croc_compiler_compileStmtsDTEx(t, name)\
	do {\
		CrocThread* _compilerThread_ = (t);\
		if(croc_compiler_compileStmtsDT(_compilerThread_, (name)) < 0)\
			croc_eh_throw(_compilerThread_);\
	} while(0)
/**@}*/

#ifdef __cplusplus
} /* extern "C" */
#endif

#undef CROCAPI

#endif