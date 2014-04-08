/** @file */

#ifndef CROC_APITYPES_H
#define CROC_APITYPES_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

/** @addtogroup APITypes */
/**@{*/

/** The underlying C type used to store the Croc 'int' type, which is equivalent to int64_t. */
typedef int64_t crocint_t;

/** The underlying C type used to store the Croc 'float' type, which is equivalent to 'double'. */
typedef double crocfloat_t;

/** The current version of Croc as a 32-bit integer. The upper 16 bits are the major, and the lower 16 are the minor. */
#define CROC_VERSION ((uint32_t)((0 << 16) | (1)))

/** An opaque type that represents a Croc thread. This type is used in virtually every public API function. */
typedef struct CrocThread CrocThread;

/** A nicer name for size_t. */
typedef size_t uword_t;

/** A nicer name for ptrdiff_t. */
typedef ptrdiff_t word_t;

/** The type of native references, a way for native code to keep a Croc object from being collected. */
typedef uint64_t crocref_t;

/** The type of Croc characters, a type big enough to hold any single Unicode codepoint. */
typedef uint32_t crocchar_t;

/** A typedef for the type signature of a native function.

Native functions receive the thread to operate on as their only parameter. They then do their work through the thread,
and then return an integer indicating how many values it is returning. That many values must be on top of the stack. */
typedef word_t (*CrocNativeFunc)(CrocThread*);

/** The type of the memory allocation function that the Croc library uses to allocate, reallocate, and free memory. You
pass a memory allocation function when you create a VM, and all allocations by the VM go through that function.

The memory function works as follows:

- If a new block is being requested, it will be called with a p of null, an oldSize of 0, and a newSize of the size of
  the requested block.
- If an existing block is to be resized, it will be called with p being the pointer to the block, an oldSize of the
  current block size, and a newSize of the new expected size of the block.
- If an existing block is to be deallocated, it will be called with p being the pointer to the block, an oldSize of the
  current block size, and a newSize of 0.

\param ctx is the context pointer that was associated with the VM upon creation. This pointer is just passed to the
	allocation function on every call; Croc doesn't use it.
\param p is the pointer that is being operated on. If this is null, an allocation is being requested. Otherwise, either
	a reallocation or a deallocation is being requested.
\param oldSize is the current size of the block pointed to by p. If p is null, this will always be 0.
\param newSize is the new size of the block pointed to by p. If p is null, this is the requested size of the new block.
	Otherwise, if this is 0, a deallocation is being requested. Otherwise, a reallocation is being requested.

\returns If a deallocation was requested, should return null. Otherwise, should return a \b non-null pointer. If
	memory cannot be allocated, the memory allocation function should fail somehow (longjump perhaps), not return
	null. */
typedef void* (*CrocMemFunc)(void* ctx, void* p, uword_t oldSize, uword_t newSize);

// IF THIS CHANGES, GREP "ORDER CROCTYPE"

/** An enumeration of all possible types of Croc values. These correspond exactly to Croc's types. */
typedef enum CrocType
{
	/* Value */
	CrocType_Null,       /**< . */ /* 0 */
	CrocType_Bool,       /**< . */ /* 1 */
	CrocType_Int,        /**< . */ /* 2 */
	CrocType_Float,      /**< . */ /* 3 */
	CrocType_Nativeobj,  /**< . */ /* 4 */

	/* Quasi-value (GC'ed but still value) */
	CrocType_String,     /**< . */ /* 5 */
	CrocType_Weakref,    /**< . */ /* 6 */

	/* Ref */
	CrocType_Table,      /**< . */ /* 7 */
	CrocType_Namespace,  /**< . */ /* 8 */
	CrocType_Array,      /**< . */ /* 9 */
	CrocType_Memblock,   /**< . */ /* 10 */
	CrocType_Function,   /**< . */ /* 11 */
	CrocType_Funcdef,    /**< . */ /* 12 */
	CrocType_Class,      /**< . */ /* 13 */
	CrocType_Instance,   /**< . */ /* 14 */
	CrocType_Thread,     /**< . */ /* 15 */

	/* Internal */
	CrocType_Upval,      /* 16 */

	/* Other */
	CrocType_NUMTYPES,

	CrocType_FirstGCType = CrocType_String,
	CrocType_FirstRefType = CrocType_Table,
	CrocType_FirstUserType = CrocType_Null,
	CrocType_LastUserType = CrocType_Thread
} CrocType;

/** An enumeration of the various limits which control the garbage collector's behavior. Read about what they mean in
the \ref croc_gc_setLimit docs. */
typedef enum CrocGCLimit
{
	CrocGCLimit_NurseryLimit,         /**< . */
	CrocGCLimit_MetadataLimit,        /**< . */
	CrocGCLimit_NurserySizeCutoff,    /**< . */
	CrocGCLimit_CycleCollectInterval, /**< . */
	CrocGCLimit_CycleMetadataLimit    /**< . */
} CrocGCLimit;

/** An enumeration of the possible states Croc threads can be in. */
typedef enum CrocThreadState
{
	CrocThreadState_Initial,   /**< Created, but hasn't been called yet. */
	CrocThreadState_Waiting,   /**< Resumed another thread and is waiting for it to yield. */
	CrocThreadState_Running,   /**< Running. */
	CrocThreadState_Suspended, /**< Yielded. */
	CrocThreadState_Dead       /**< Returned from the thread's main function. */
} CrocThreadState;

/** An enumeration of the different kinds of debug hooks. */
typedef enum CrocThreadHook
{
	CrocThreadHook_Call = 1,     /**< . */
	CrocThreadHook_TailCall = 2, /**< . */
	CrocThreadHook_Ret = 4,      /**< . */
	CrocThreadHook_Delay = 8,    /**< . */
	CrocThreadHook_Line = 16     /**< . */
} CrocThreadHook;

/** An enumeration of possible return values from the \ref croc_tryCall and \ref croc_tryMethodCall functions. These
values will all be negative to distinguish them from the normal return value (how many values the function returned). */
typedef enum CrocCallRet
{
	CrocCallRet_Error = -1, /**< Indicates that an exception was thrown. */
} CrocCallRet;

/** An enumeration of the unsafe standard libraries, to be passed to \ref croc_vm_loadUnsafeLibs. */
typedef enum CrocUnsafeLib
{
	CrocUnsafeLib_None =  0, /**< No unsafe libs. */
	CrocUnsafeLib_File =  1, /**< The \c file lib. */
	CrocUnsafeLib_OS =    2, /**< The \c os lib. */
	CrocUnsafeLib_Debug = 4, /**< The \c debug lib. */
	CrocUnsafeLib_All = CrocUnsafeLib_File | CrocUnsafeLib_OS, /**< All unsafe libs, except the \c debug lib. */
	CrocUnsafeLib_ReallyAll = CrocUnsafeLib_All | CrocUnsafeLib_Debug /**< All unsafe libs plus the \c debug lib. */
} CrocUnsafeLib;

/** An enumeration of the addon libraries. You have to compile addons into the Croc library in order to be able to use
them.*/
typedef enum CrocAddons
{
	CrocAddons_None =  0,  /**< No addon libs. */
	CrocAddons_Pcre =  1,  /**< The \c pcre lib. */
	CrocAddons_Sdl =   2,  /**< The \c sdl lib. */
	CrocAddons_Devil = 4,  /**< The \c devil lib. */
	CrocAddons_Gl =    8,  /**< The \c gl lib. */
	CrocAddons_Net =   16, /**< The \c net lib. */
	CrocAddons_Safe = CrocAddons_Pcre | CrocAddons_Sdl, /**< The safe addons. */
	CrocAddons_Unsafe = CrocAddons_Devil | CrocAddons_Gl | CrocAddons_Net, /**< The unsafe addons. */
	CrocAddons_All = CrocAddons_Safe | CrocAddons_Unsafe /**< All addons, safe or not. */
} CrocAddons;

/** An enumeration of flags which control compiler options, to be passed to \ref croc_compiler_setFlags (and returned
from \ref croc_compiler_getFlags).*/
typedef enum CrocCompilerFlags
{
	CrocCompilerFlags_None = 0,            /**< No optional features. */
	CrocCompilerFlags_TypeConstraints = 1, /**< Enables parameter type constraint check codegen. */
	CrocCompilerFlags_Asserts = 2,         /**< Enables \c assert() codegen. */
	CrocCompilerFlags_Debug = 4,           /**< Enables debug info. Currently can't be disabled. */
	CrocCompilerFlags_Docs = 8,            /**< Enables doc comment parsing and doc decorators. */

	/** All features except doc comments. */
	CrocCompilerFlags_All = CrocCompilerFlags_TypeConstraints | CrocCompilerFlags_Asserts | CrocCompilerFlags_Debug,

	/** All features including doc comments. */
	CrocCompilerFlags_AllDocs = CrocCompilerFlags_All | CrocCompilerFlags_Docs
} CrocCompilerFlags;

/** An enumeration of error values which the various compiler API functions can return. These are useful for getting
more info about why compilation failed, for writing things like command-line interpreters. */
typedef enum CrocCompilerReturn
{
	CrocCompilerReturn_UnexpectedEOF = -1, /**< Unexpected end-of-file (end of source). */
	CrocCompilerReturn_LoneStatement = -2, /**< A statement consisting of an expression which can't stand alone. */
	CrocCompilerReturn_DanglingDoc = -3,   /**< A dangling doc comment at the end of the source. */
	CrocCompilerReturn_Error = -4,         /**< Some other kind of compilation error. */
} CrocCompilerReturn;

/** An enumeration of the kinds of runtime locations which can be passed to \ref croc_eh_pushLocationObject. */
typedef enum CrocLocation
{
	CrocLocation_Unknown = 0, /**< For when location info could not be determined. */
	CrocLocation_Native = -1, /**< For when the location is inside a native function. */
	CrocLocation_Script = -2  /**< For when the location is inside a script function. */
} CrocLocation;

/**@}*/

#ifdef __cplusplus
} /* extern "C" */
#endif
#endif