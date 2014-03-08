#ifndef CROC_APITYPES_H
#define CROC_APITYPES_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

/**
The underlying C type used to store the Croc 'int' type, which is equivalent to int64_t.
*/
typedef int64_t crocint_t;

/**
The underlying C type used to store the Croc 'float' type, which is equivalent to 'double'.
*/
typedef double crocfloat_t;

/**
The current version of Croc as a 32-bit integer. The upper 16 bits are the major, and the lower 16 are the minor.
*/
#define CROC_VERSION ((uint32_t)((0 << 16) | (1)))

/**
An opaque type that represents a Croc thread. This type is used in virtually every public API function.
*/
typedef struct CrocThread CrocThread;

/**
A nicer name for size_t.
*/
typedef size_t uword_t;

/**
A nicer name for ptrdiff_t.
*/
typedef ptrdiff_t word_t;

/**
The type of native references, a way for native code to keep a Croc object from being collected.
*/
typedef uint64_t crocref_t;

/**
The type of Croc characters, a type big enough to hold any single Unicode codepoint.
*/
typedef uint32_t crocchar_t;

/**
A typedef for the type signature of a native function.
*/
typedef ptrdiff_t(*CrocNativeFunc)(CrocThread*);

/**
The type of the memory allocation function that the Croc library uses to allocate, reallocate, and free memory. You pass
a memory allocation function when you create a VM, and all allocations by the VM go through that function.

The memory function works as follows:

If a new block is being requested, it will be called with a p of null, an oldSize of 0, and a newSize of the size of the
requested block.

If an existing block is to be resized, it will be called with p being the pointer to the block, an oldSize of the
current block size, and a newSize of the new expected size of the block.

If an existing block is to be deallocated, it will be called with p being the pointer to the block, an oldSize of the
current block size, and a newSize of 0.

Params:

ctx = The context pointer that was associated with the VM upon creation.  This pointer is just passed to the allocation
function on every call; Croc doesn't use it.

p = The pointer that is being operated on.  If this is null, an allocation is being requested.  Otherwise, either a
reallocation or a deallocation is being requested.

oldSize = The current size of the block pointed to by p.  If p is null, this will always be 0.

newSize = The new size of the block pointed to by p.  If p is null, this is the requested size of the new block.
Otherwise, if this is 0, a deallocation is being requested.  Otherwise, a reallocation is being requested.

Returns:

If a deallocation was requested, should return null.  Otherwise, should return a $(B non-null) pointer.  If memory
cannot be allocated, the memory allocation function should fail somehow (longjump perhaps), not return null.
*/
typedef void* (*CrocMemFunc)(void* ctx, void* p, size_t oldSize, size_t newSize);

// IF THIS CHANGES, GREP "ORDER CROCTYPE"

/**
An enumeration of all possible object types in Croc. Some types are internal to the implementation.
*/
typedef enum CrocType
{
	/* Value */
	CrocType_Null,       /* 0 */
	CrocType_Bool,       /* 1 */
	CrocType_Int,        /* 2 */
	CrocType_Float,      /* 3 */
	CrocType_Nativeobj,  /* 4 */

	/* Quasi-value (GC'ed but still value) */
	CrocType_String,     /* 5 */
	CrocType_Weakref,    /* 6 */

	/* Ref */
	CrocType_Table,      /* 7 */
	CrocType_Namespace,  /* 8 */
	CrocType_Array,      /* 9 */
	CrocType_Memblock,   /* 10 */
	CrocType_Function,   /* 11 */
	CrocType_Funcdef,    /* 12 */
	CrocType_Class,      /* 13 */
	CrocType_Instance,   /* 14 */
	CrocType_Thread,     /* 15 */

	/* Internal */
	CrocType_Upval,      /* 16 */

	/* Other */
	CrocType_NUMTYPES,

	CrocType_FirstGCType = CrocType_String,
	CrocType_FirstRefType = CrocType_Table,
	CrocType_FirstUserType = CrocType_Null,
	CrocType_LastUserType = CrocType_Thread
} CrocType;

/* */
typedef enum CrocThreadState
{
	CrocThreadState_Initial,
	CrocThreadState_Waiting,
	CrocThreadState_Running,
	CrocThreadState_Suspended,
	CrocThreadState_Dead
} CrocThreadState;

/* */
typedef enum CrocThreadHook
{
	CrocThreadHook_Call = 1,
	CrocThreadHook_TailCall = 2,
	CrocThreadHook_Ret = 4,
	CrocThreadHook_Delay = 8,
	CrocThreadHook_Line = 16
} CrocThreadHook;

/* */
typedef enum CrocCallRet
{
	CrocCallRet_Error = -1,
} CrocCallRet;

/* */
typedef enum CrocUnsafeLib
{
	CrocUnsafeLib_None =  0,
	CrocUnsafeLib_File =  1,
	CrocUnsafeLib_OS =    2,
	CrocUnsafeLib_Debug = 4,
	CrocUnsafeLib_All = CrocUnsafeLib_File | CrocUnsafeLib_OS,
	CrocUnsafeLib_ReallyAll = CrocUnsafeLib_All | CrocUnsafeLib_Debug
} CrocUnsafeLib;

/* */
typedef enum CrocAddons
{
	CrocAddons_None =  0,
	CrocAddons_Pcre =  1,
	CrocAddons_Sdl =   2,
	CrocAddons_Devil = 4,
	CrocAddons_Gl =    8,
	CrocAddons_Net =   16,
	CrocAddons_Safe = CrocAddons_Pcre | CrocAddons_Sdl,
	CrocAddons_Unsafe = CrocAddons_Devil | CrocAddons_Gl | CrocAddons_Net,
	CrocAddons_All = CrocAddons_Safe | CrocAddons_Unsafe
} CrocAddons;

/* */
typedef enum CrocCompilerFlags
{
	CrocCompilerFlags_None = 0,
	CrocCompilerFlags_TypeConstraints = 1,
	CrocCompilerFlags_Asserts = 2,
	CrocCompilerFlags_Debug = 4,
	CrocCompilerFlags_Docs = 8,
	CrocCompilerFlags_All = CrocCompilerFlags_TypeConstraints | CrocCompilerFlags_Asserts | CrocCompilerFlags_Debug,
	CrocCompilerFlags_AllDocs = CrocCompilerFlags_All | CrocCompilerFlags_Docs
} CrocCompilerFlags;

/* */
typedef enum CrocCompilerReturn
{
	CrocCompilerReturn_UnexpectedEOF = -1,
	CrocCompilerReturn_LoneStatement = -2,
	CrocCompilerReturn_DanglingDoc = -3,
	CrocCompilerReturn_Error = -4,
} CrocCompilerReturn;

#ifdef __cplusplus
} /* extern "C" */
#endif
#endif