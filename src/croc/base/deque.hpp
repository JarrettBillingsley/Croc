#ifndef CROC_BASE_DEQUE_HPP
#define CROC_BASE_DEQUE_HPP

#include "croc/base/alloc.hpp"
#include "croc/base/darray.hpp"
#include "croc/base/sanity.hpp"

namespace croc
{
	struct Allocator;
	struct GCObject;

	struct Deque
	{
	private:
		DArray<GCObject*> mData;
		size_t mStart;
		size_t mEnd;
		size_t mSize;

	public:
		Deque();
		void prealloc(Allocator& alloc, size_t size);
		void add(Allocator& alloc, GCObject* t);
		GCObject* remove();
		void append(Allocator& alloc, DArray<GCObject*> ts);
		void append(Allocator& alloc, Deque& other);

		inline bool   isEmpty()  const { return mSize == 0; }
		inline bool   isFull()   const { return mSize == mData.length; }
		inline size_t length()   const { return mSize; }
		inline size_t capacity() const { return mData.length; }

		void reset();
		void clear(Allocator& alloc);
		void minimize(Allocator& alloc);

		struct Iterator
		{
			friend class Deque;

		private:
			Deque* mDeque;
			size_t mIdx;
			bool mDead;
#ifndef NDEBUG
			size_t mStartSize, mStartLength;
#endif
			Iterator(Deque* d);

		public:
			inline bool hasNext() const { return !mDead; }

			GCObject* next();
			void removeCurrent();
		};

		Iterator iterator();

	private:
		void enlargeArray(Allocator& alloc);
		void resizeArray(Allocator& alloc, size_t newSize);
	};
}

#endif
