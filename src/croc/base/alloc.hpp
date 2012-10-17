#ifndef CROC_BASE_ALLOC_HPP
#define CROC_BASE_ALLOC_HPP

#include <limits>
#include <new>

#include "croc/base/darray.hpp"
#include "croc/base/deque.hpp"
#include "croc/base/sanity.hpp"
#include "croc/apitypes.h"

#ifdef CROC_LEAK_DETECTOR
#  pragma message("Compiling Croc with the leak detector enabled.")
#  include <assert.h>
#  include <stdio.h>
#  include <string.h>
#  include "croc/base/hash.hpp"
#endif

#ifdef CROC_STOMP_MEMORY
#  define STOMPYSTOMP(ptr, len) memset(ptr, 0xCD, len)
#endif

namespace croc
{
	enum GCFlags
	{
		GCFlags_Unlogged =    0x001, // 0b0_00000001
		GCFlags_InRC =        0x002, // 0b0_00000010

		GCFlags_Black =       0x000, // 0b0_00000000
		GCFlags_Grey =        0x004, // 0b0_00000100
		GCFlags_White =       0x008, // 0b0_00001000
		GCFlags_Purple =      0x00C, // 0b0_00001100
		GCFlags_Green =       0x010, // 0b0_00010000
		GCFlags_ColorMask =   0x01C, // 0b0_00011100

		GCFlags_CycleLogged = 0x020, // 0b0_00100000

		GCFlags_Finalizable = 0x040, // 0b0_01000000
		GCFlags_Finalized =   0x080, // 0b0_10000000

		GCFlags_JustMoved =   0x100  // 0b1_00000000
	};

	struct GCObject
	{
		GCObject():
			gcflags(0),
			refCount(1),
			memSize(0)
		{}

		uint32_t gcflags;
		uint32_t refCount;
		size_t memSize;
		CrocType mType;
	};

	struct Allocator
	{
		MemFunc memFunc;
		void* ctx;

		// 0 for enabled, positive for disabled
		size_t gcDisabled;
		size_t totalBytes;

		Deque modBuffer;
		Deque decBuffer;

		Deque nursery;
		size_t nurseryBytes;
		size_t nurseryLimit;
		size_t metadataLimit;
		size_t nurserySizeCutoff;
		size_t cycleCollectCountdown;
		size_t nextCycleCollect;
		size_t cycleMetadataLimit;

#ifdef CROC_LEAK_DETECTOR
		struct LeakMemBlock
		{
			size_t len;
			std::type_info& ti;

			LeakMemBlock(size_t size, std::type_info& t):
				len(size),
				ti(t)
			{}
		};

		Hash<void*, LeakMemBlock> _nurseryBlocks;
		Hash<void*, LeakMemBlock> _rcBlocks;
		Hash<void*, LeakMemBlock> _rawBlocks;

		template<typename T> void insertRawMemBlock(DArray<T> arr)
		{
			*_rawBlocks.insert(*this, arr.ptr) = LeakMemBlock(size * sizeof(T), typeid(T));
		}

		template<> void insertRawMemBlock<LeakMemBlock>(DArray<LeakMemBlock> arr)
		{
			totalBytes -= arr.length * sizeof(LeakMemBlock);
		}

		template<typename T> void removeRawMemBlock(DArray<T> arr)
		{
			if(!_rawBlocks.remove(arr.ptr))
			{
				fprintf(stderr, "AWFUL: You're trying to free an array that wasn't allocated on the Croc Heap, or are performing a double free! It's of type %s", typeid(T).name());
				assert(false);
			}
		}

		template<> void removeRawMemblock<LeakMemBlock>(DArray<LeakMemBlock> arr)
		{
			totalBytes += arr.length * sizeof(LeakMemBlock);
		}
#endif
		Allocator():
			gcDisabled(0),
			totalBytes(0),
			nurseryBytes(0),
			nurseryLimit(512 * 1024),
			metadataLimit(128 * 1024),
			nurserySizeCutoff(256),
			cycleCollectCountdown(0),
			nextCycleCollect(50),
			cycleMetadataLimit(128 * 1024)
		{}

		// ------------------------------------------------------------
		// Interfacing stuff

		bool couldUseGC() const
		{
			return
				nurseryBytes >= nurseryLimit ||
				(modBuffer.length() + decBuffer.length()) * sizeof(GCObject*) >= metadataLimit;
		}

		void resizeNurserySpace(size_t newSize)
		{
			nurseryLimit = newSize;
		}

		void clearNurserySpace()
		{
			nursery.clear(*this);
			nurseryBytes = 0;

#ifdef CROC_LEAK_DETECTOR
			_nurseryBlocks.clear(*this);
#endif
		}

		void cleanup()
		{
			clearNurserySpace();
			modBuffer.clear(*this);
			decBuffer.clear(*this);
		}

		// ------------------------------------------------------------
		// GC objects

		// ALLOCATION: most objects are allocated in the nursery. If they're too big, or finalizable, they're allocated directly in the RC space. When this
		// happens, we push them onto the modified buffer and the decrement buffer, and initialize their reference count to 1. This way, when the collection
		// cycle happens, if they're referenced, their reference count will be incremented then decremented (no-op); if they're not referenced, their
		// reference count will be decremented to 0, freeing them. Putting them in the modified buffer is, I guess, to prevent memory leaks..? Couldn't hurt.

		template<typename T>
		T* allocate(size_t size = sizeof(T))
		{
			if(size >= nurserySizeCutoff || gcDisabled > 0)
				return allocateRC<T>(size);
			else
				return allocateNursery<T>(size);
		}

		template<typename T>
		T* allocateFinalizable(size_t size = sizeof(T))
		{
			T* ret = allocateRC<T>(size);
			ret->gcflags |= GCFlags_Finalizable;
			return ret;
		}

		void makeRC(GCObject* obj)
		{
			assert((obj->gcflags & GCFlags_InRC) == 0);
			obj->gcflags |= GCFlags_InRC | GCFlags_JustMoved;

#ifdef CROC_LEAK_DETECTOR
			LeakMemBlock* b = _nurseryBlocks.lookup(obj);
			assert(b != NULL);
			*_rcBlocks.insert(*this, obj) = *b;
#endif
		}

		template<typename T>
		void free(T* o)
		{
#ifdef CROC_LEAK_DETECTOR
			if(o->gcflags & GCFlags_InRC)
			{
				if(!_rcBlocks.remove(o))
				{
					fprintf(stderr, "AWFUL: You're trying to free something that wasn't allocated on the Croc Heap, or are performing a double free! It's of type %s", typeid(T).name());
					assert(false);
				}
			}
			else
			{
				if(!_nurseryBlocks.remove(o))
				{
					fprintf(stderr, "AWFUL: You're trying to free something that wasn't allocated on the Croc Heap, or are performing a double free! It's of type %s", typeid(T).name());
					assert(false);
				}
			}
#endif
			size_t sz = o->memSize;

#ifdef CROC_STOMP_MEMORY
			STOMPYSTOMP((cast(uint8_t*)o), sz);
#endif
			realloc(o, sz, 0);
		}

		// ------------------------------------------------------------
		// Arrays

		template<typename T>
		DArray<T> allocArray(size_t size)
		{
			if(size == 0)
				return DArray<T>();

			DArray<T> ret(cast(T*)realloc(NULL, 0, size * sizeof(T)), size);

			ret.fill(T());

#ifdef CROC_LEAK_DETECTOR
			insertRawMemBlock(ret);
#endif
			return ret;
		}

		template<typename T>
		void resizeArray(DArray<T>& arr, size_t newLen)
		{
#ifdef CROC_LEAK_DETECTOR
			if(arr.length > 0 && _rawBlocks.lookup(arr.ptr) == NULL)
			{
				fprintf(stderr, "AWFUL: You're trying to resize an array that wasn't allocated on the Croc Heap! It's of type %s", typeid(T).name());
				assert(false);
			}
#endif
			if(newLen == 0)
			{
				freeArray(arr);
				return;
			}
			else if(newLen == arr.length)
				return;

			size_t oldLen = arr.length;

#ifdef CROC_STOMP_MEMORY
			if(newLen < oldLen)
			{
				DArray<T> temp = arr.slice(newLen, oldLen);
				STOMPYSTOMP(temp.ptr, temp.length * sizeof(T));
			}
#endif
			DArray<T> ret(cast(T*)realloc(arr.ptr, oldLen * sizeof(T), newLen * sizeof(T)), newLen);

#ifdef CROC_LEAK_DETECTOR
			if(arr.ptr == ret.ptr)
				_rawBlocks.lookup(ret.ptr).len = newLen * T.sizeof;
			else
			{
				_rawBlocks.remove(arr.ptr);
				*_rawBlocks.insert(*this, ret.ptr) = LeakMemBlock(newLen * T.sizeof, typeid(T));
			}
#endif
			arr = ret;

			arr.slice(oldLen, newLen).fill(T());
		}

		template<typename T>
		DArray<T> dupArray(DArray<T> a)
		{
			if(a.length == 0)
				return DArray<T>();

			DArray<T> ret(cast(T*)realloc(NULL, 0, a.length * sizeof(T)), a.length);
			ret.slicea(0, ret.length, a.slice(0, a.length));

#ifdef CROC_LEAK_DETECTOR
			insertRawMemBlock(ret)
#endif
			return ret;
		}

		template<typename T>
		void freeArray(DArray<T>& a)
		{
			if(a.length == 0)
				return;

#ifdef CROC_LEAK_DETECTOR
			removeRawMemBlock(a);
#endif
#ifdef CROC_STOMP_MEMORY
			STOMPYSTOMP(a.ptr, a.length * sizeof(T));
#endif
			realloc(a.ptr, a.length * sizeof(T), 0);
			a = DArray<T>();
		}

		// ================================================================================================================================================
		// Private
		// ================================================================================================================================================

	private:
		template<typename T>
		T* allocateNursery(size_t size = sizeof(T))
		{
			T* ret = cast(T*)realloc(NULL, 0, size);
			new(ret) T();
			ret->memSize = size;

			if(T::ACYCLIC)
				ret->gcflags |= GCFlags_Green;

			nurseryBytes += size;
			nursery.add(*this, cast(GCObject*)ret);

#ifdef CROC_LEAK_DETECTOR
			*_nurseryBlocks.insert(*this, ret) = LeakMemBlock(size, typeid(T));
#endif
			return ret;
		}

		template<typename T>
		T* allocateRC(size_t size = sizeof(T))
		{
			T* ret = cast(T*)realloc(NULL, 0, size);
			new(ret) T();
			ret->memSize = size;
			ret->gcflags = GCFlags_InRC; // RC space objects start off logged since we put them on the mod buffer (or they're green and don't need to be)

			if(T::ACYCLIC)
				ret->gcflags |= GCFlags_Green;
			else
				modBuffer.add(*this, cast(GCObject*)ret);

			decBuffer.add(*this, cast(GCObject*)ret);
#ifdef CROC_LEAK_DETECTOR
			*_rcBlocks.insert(*this, ret) = LeakMemBlock(size, typeid(T));
#endif
			return ret;
		}

		void* realloc(void* p, size_t oldSize, size_t newSize)
		{
			void* ret = memFunc(ctx, p, oldSize, newSize);
			assert((newSize == 0 || ret != NULL) && "allocation function should never return NULL");
			totalBytes += newSize - oldSize;
			return ret;
		}
	};
}

#endif