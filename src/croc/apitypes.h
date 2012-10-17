#ifndef CROC_APITYPES_H
#define CROC_APITYPES_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

/**
The underlying C type used to store the Croc 'int' type. Defaults to int64_t. If you change it, you will end
up with a (probably?) functional but nonstandard implementation.
*/
typedef int64_t crocint_t;

/* TODO: */
/* static assert((cast(crocint)-1) < (cast(crocint)0), "crocint must be signed"); */

/**
The underlying C type used to store the Croc 'float' type. Defaults to 'double'. If you change it, you will end
up with a (probably?) functional but nonstandard implementation.
*/
typedef double crocfloat_t;

/**
The underlying C type used to store the Croc 'char' type. Defaults to uint32_t. If you change it, all hell will
break loose.
*/
typedef uint32_t crocchar_t;

/**
The current version of Croc as a 32-bit integer. The upper 16 bits are the major, and the lower 16 are
the minor.
*/
#define CROC_VERSION ((uint32_t)((0 << 16) | (1)))

/**
An opaque type that represents a Croc VM instance. A Croc VM is a structure that holds all global state for
one Croc virtual machine. Each VM can have multiple Croc threads associated with it. You can have multiple
Croc VMs, each with their own environment and each running different code simultaneously.
*/
typedef struct CrocVM CrocVM;

/**
An opaque type that represents a Croc thread. This type is used in virtually every public API function.
*/
typedef struct CrocThread CrocThread;

/**
A typedef for the type signature of a native function.
*/
typedef size_t(*CrocNativeFunc)(CrocThread*);

/**
The type of the memory allocation function that the Croc library uses to allocate, reallocate, and free memory.
You pass a memory allocation function when you create a VM, and all allocations by the VM go through that function.

The memory function works as follows:

If a new block is being requested, it will be called with a p of null, an oldSize of 0, and a newSize of the size of
the requested block.

If an existing block is to be resized, it will be called with p being the pointer to the block, an oldSize of the current
block size, and a newSize of the new expected size of the block.

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
If a deallocation was requested, should return null.  Otherwise, should return a $(B non-null) pointer.  If memory cannot
be allocated, the memory allocation function should fail somehow (longjump perhaps), not return null.
*/
typedef void* (*MemFunc)(void* ctx, void* p, size_t oldSize, size_t newSize);

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
	CrocType_Char,       /* 4 */
	CrocType_NativeObj,  /* 5 */

	/* Quasi-value (GC'ed but still value) */
	CrocType_String,     /* 6 */
	CrocType_WeakRef,    /* 7 */

	/* Ref */
	CrocType_Table,      /* 8 */
	CrocType_Namespace,  /* 9 */
	CrocType_Array,      /* 10 */
	CrocType_Memblock,   /* 11 */
	CrocType_Function,   /* 12 */
	CrocType_FuncDef,    /* 13 */
	CrocType_Class,      /* 14 */
	CrocType_Instance,   /* 15 */
	CrocType_Thread,     /* 16 */

	/* Internal */
	CrocType_Upvalue,    /* 17 */

	/* Other */
	CrocType_FirstGCType = CrocType_String,
	CrocType_FirstRefType = CrocType_Table,
	CrocType_FirstUserType = CrocType_Null,
	CrocType_LastUserType = CrocType_Thread
} CrocType;

/** A function to get a human-readable string from a Croc type. */
const char* croc_typeToString(CrocType t);

#ifdef __cplusplus
} /* extern "C" */
#endif
#endif