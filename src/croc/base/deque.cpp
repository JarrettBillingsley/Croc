#include "croc/base/deque.hpp"
#include "croc/base/gcobject.hpp"
#include "croc/base/memory.hpp"
#include "croc/base/sanity.hpp"
#include "croc/util/misc.hpp"

#ifdef CROC_LEAK_DETECTOR
#  define MEMBERTYPEID ,typeid(GCObject**)
#else
#  define MEMBERTYPEID
#endif

namespace croc
{
	void Deque::init()
	{
		mDataPtr = nullptr;
		mDataLen = 0;
		mStart = 0;
		mEnd = 0;
		mSize = 0;
	}

	void Deque::prealloc(Memory& mem, size_t size)
	{
		if(size <= mDataLen)
			return;
		else if(size > 4)
			resizeArray(mem, largerPow2(size));
	}

	void Deque::add(Memory& mem, GCObject* t)
	{
		if(isFull())
			enlargeArray(mem);

		mDataPtr[mEnd++] = t;

		if(mEnd == mDataLen)
			mEnd = 0;

		mSize++;
	}

	GCObject* Deque::remove()
	{
		assert(!isEmpty());

		GCObject* ret = mDataPtr[mStart++];

		if(mStart == mDataLen)
			mStart = 0;

		mSize--;

		return ret;
	}

	void Deque::append(Memory& mem, GCObject** srcPtr, size_t srcLen)
	{
		if(mDataLen < (mSize + srcLen))
			resizeArray(mem, largerPow2(mSize + srcLen));

		if(mStart <= mEnd)
		{
			// empty space may be split over the end
			size_t endLen = mDataLen - mEnd;

			if(endLen >= srcLen)
			{
				memcpy(mDataPtr + mEnd, srcPtr, srcLen * sizeof(GCObject*));
				mEnd += srcLen;
			}
			else
			{
				memcpy(mDataPtr + mEnd, srcPtr, endLen * sizeof(GCObject*));
				size_t beginLen = srcLen - endLen;
				memcpy(mDataPtr, srcPtr + endLen, beginLen * sizeof(GCObject*));
				mEnd = beginLen;
			}
		}
		else
		{
			memcpy(mDataPtr + mEnd, srcPtr, srcLen * sizeof(GCObject*));
			mEnd += srcLen;
		}

		if(mEnd == mDataLen)
			mEnd = 0;

		mSize += srcLen;
	}

	void Deque::append(Memory& mem, Deque& other)
	{
		if(other.length() == 0)
			return;

		if(mDataLen < (mSize + other.length()))
			resizeArray(mem, largerPow2(mSize + other.length()));

		GCObject** startPtr = other.mDataPtr + other.mStart;

		if(other.mStart >= other.mEnd)
		{
			size_t startLen = (other.mDataPtr + other.mDataLen) - startPtr;
			size_t restLen = other.length() - startLen;
			append(mem, startPtr, startLen);
			append(mem, other.mDataPtr, restLen);
		}
		else
			append(mem, startPtr, other.length());
	}

	void Deque::reset()
	{
		mStart = mEnd = mSize = 0;
	}

	void Deque::clear(Memory& mem)
	{
		void* p = mDataPtr;
		auto sz = mDataLen * sizeof(GCObject*);
		mem.freeRaw(p, sz MEMBERTYPEID);
		mDataPtr = nullptr;
		mDataLen = 0;
		reset();
	}

	void Deque::minimize(Memory& mem)
	{
		if(mSize == 0)
			clear(mem);
		else
		{
			size_t size = largerPow2(mSize);
			resizeArray(mem, size < 4 ? 4 : size);
		}
	}

	void Deque::foreach(std::function<void(GCObject*)> dg)
	{
		if(mSize == 0)
			return;

		if(mStart >= mEnd)
		{
			for(size_t i = mStart; i < mDataLen; i++)
				dg(mDataPtr[i]);

			for(size_t i = 0; i < mEnd; i++)
				dg(mDataPtr[i]);
		}
		else
		{
			for(size_t i = mStart; i < mEnd; i++)
				dg(mDataPtr[i]);
		}
	}

	Deque::Iterator::Iterator(Deque* d):
		mDeque(d),
		mIdx(d->mStart),
		mDead(d->mSize == 0)
#ifndef NDEBUG
		,mStartSize(d->mSize)
		,mStartLength(d->mDataLen)
#endif
	{}

	GCObject* Deque::Iterator::next()
	{
		assert(!mDead);
		assert(mDeque->mSize <= mStartSize);
		assert(mDeque->mDataLen == mStartLength);

		GCObject* ret = mDeque->mDataPtr[mIdx++];

		if(mIdx == mDeque->mDataLen)
			mIdx = 0;

		if(mIdx == mDeque->mEnd)
			mDead = true;

		return ret;
	}

	void Deque::Iterator::removeCurrent()
	{
		assert(!mDeque->isEmpty());

		size_t idx = mIdx == 0 ? mDeque->mDataLen - 1 : mIdx - 1;

		if(idx == mDeque->mStart)
			mDeque->remove();
		else
			mDeque->mDataPtr[idx] = mDeque->remove();
	}

	Deque::Iterator Deque::iterator()
	{
		return Deque::Iterator(this);
	}

	void Deque::enlargeArray(Memory& mem)
	{
		if(mDataLen != 0)
			resizeArray(mem, mDataLen * 2);
		else
			resizeArray(mem, 4);
	}

	void Deque::resizeArray(Memory& mem, size_t newSize)
	{
		if(mDataLen == newSize)
			return;

		assert(newSize > mSize);

		GCObject** newData = cast(GCObject**)mem.allocRaw(newSize * sizeof(GCObject*) MEMBERTYPEID);

		if(mSize > 0)
		{
			if(mEnd > mStart)
				memcpy(newData, mDataPtr + mStart, (mEnd - mStart) * sizeof(GCObject*));
			else
			{
				size_t endLen = mDataLen - mStart;
				memcpy(newData, mDataPtr + mStart, endLen * sizeof(GCObject*));
				memcpy(newData + endLen, mDataPtr, mEnd * sizeof(GCObject*));
			}
		}

		void* p = mDataPtr;
		auto sz = mDataLen * sizeof(GCObject*);
		mem.freeRaw(p, sz MEMBERTYPEID);
		mDataPtr = newData;
		mDataLen = newSize;
		mStart = 0;
		mEnd = mSize;
	}
}