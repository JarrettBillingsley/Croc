#ifndef CROC_BASE_DEQUE_HPP
#define CROC_BASE_DEQUE_HPP

#include <functional>

#include "croc/base/gcobject.hpp"
// #include "croc/base/memory.hpp"
#include "croc/base/sanity.hpp"

namespace croc
{
	struct Memory;

	struct Deque
	{
	private:
		GCObject** mDataPtr;
		size_t mDataLen;
		size_t mStart;
		size_t mEnd;
		size_t mSize;

	public:
		void init();
		void prealloc(Memory& mem, size_t size);
		void add(Memory& mem, GCObject* t);
		GCObject* remove();
		void append(Memory& mem, GCObject** ptr, size_t len);
		void append(Memory& mem, Deque& other);

		inline bool   isEmpty()  const { return mSize == 0; }
		inline bool   isFull()   const { return mSize == mDataLen; }
		inline size_t length()   const { return mSize; }
		inline size_t capacity() const { return mDataLen; }

		void reset();
		void clear(Memory& mem);
		void minimize(Memory& mem);

		void foreach(std::function<void(GCObject*)> dg);

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
		void enlargeArray(Memory& mem);
		void resizeArray(Memory& mem, size_t newSize);
	};
}

#endif
