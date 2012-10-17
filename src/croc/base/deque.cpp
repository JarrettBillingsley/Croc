#include "croc/base/alloc.hpp"
#include "croc/base/darray.hpp"
#include "croc/base/deque.hpp"
#include "croc/base/sanity.hpp"
#include "croc/utils.hpp"

namespace croc
{
	Deque::Deque():
		mData(),
		mStart(0),
		mEnd(0),
		mSize(0)
	{}

	void Deque::prealloc(Allocator& alloc, size_t size)
	{
		if(size <= mData.length)
			return;
		else if(size > 4)
			resizeArray(alloc, largerPow2(size));
	}

	void Deque::add(Allocator& alloc, GCObject* t)
	{
		if(isFull())
			enlargeArray(alloc);

		mData[mEnd++] = t;

		if(mEnd == mData.length)
			mEnd = 0;

		mSize++;
	}

	GCObject* Deque::remove()
	{
		assert(!isEmpty());

		GCObject* ret = mData[mStart++];

		if(mStart == mData.length)
			mStart = 0;

		mSize--;

		return ret;
	}

	void Deque::append(Allocator& alloc, DArray<GCObject*> ts)
	{
		if(mData.length < (mSize + ts.length))
			resizeArray(alloc, largerPow2(mSize + ts.length));

		if(mStart <= mEnd)
		{
			// empty space may be split over the end
			size_t endSize = mData.length - mEnd;

			if(endSize >= ts.length)
			{
				mData.slicea(mEnd, mEnd + ts.length, ts);
				mEnd += ts.length;
			}
			else
			{
				mData.slicea(mEnd, mData.length, ts.slice(0, endSize));
				mData.slicea(0, ts.length - endSize, ts.slice(endSize, ts.length));
				mEnd = ts.length - endSize;
			}
		}
		else
		{
			mData.slicea(mEnd, mEnd + ts.length, ts);
			mEnd += ts.length;
		}

		if(mEnd == mData.length)
			mEnd = 0;

		mSize += ts.length;
	}

	void Deque::append(Allocator& alloc, Deque& other)
	{
		if(other.length() == 0)
			return;

		if(mData.length < (mSize + other.length()))
			resizeArray(alloc, largerPow2(mSize + other.length()));

		if(other.mStart >= other.mEnd)
		{
			append(alloc, other.mData.slice(other.mStart, other.length()));
			append(alloc, other.mData.slice(0, other.mEnd));
		}
		else
			append(alloc, other.mData.slice(other.mStart, other.mEnd));
	}

	void Deque::reset()
	{
		mStart = mEnd = mSize = 0;
	}

	void Deque::clear(Allocator& alloc)
	{
		alloc.freeArray(mData);
		reset();
	}

	void Deque::minimize(Allocator& alloc)
	{
		if(mSize == 0)
			clear(alloc);
		else
		{
			size_t size = largerPow2(mSize);
			resizeArray(alloc, size < 4 ? 4 : size);
		}
	}

	Deque::Iterator::Iterator(Deque* d):
		mDeque(d),
		mIdx(d->mStart),
		mDead(d->mSize == 0)
#ifndef NDEBUG
		,mStartSize(d->mSize)
		,mStartLength(d->mData.length)
#endif
	{}

	GCObject* Deque::Iterator::next()
	{
		assert(!mDead);
		assert(mDeque->mSize <= mStartSize);
		assert(mDeque->mData.length == mStartLength);

		GCObject* ret = mDeque->mData[mIdx++];

		if(mIdx == mDeque->mData.length)
			mIdx = 0;

		if(mIdx == mDeque->mEnd)
			mDead = true;

		return ret;
	}

	void Deque::Iterator::removeCurrent()
	{
		assert(!mDeque->isEmpty());

		size_t idx = mIdx == 0 ? mDeque->mData.length - 1 : mIdx - 1;

		if(idx == mDeque->mStart)
			mDeque->remove();
		else
			mDeque->mData[idx] = mDeque->remove();
	}

	Deque::Iterator Deque::iterator()
	{
		return Deque::Iterator(this);
	}

	void Deque::enlargeArray(Allocator& alloc)
	{
		if(mData.length != 0)
			resizeArray(alloc, mData.length * 2);
		else
			resizeArray(alloc, 4);
	}

	void Deque::resizeArray(Allocator& alloc, size_t newSize)
	{
		if(mData.length == newSize)
			return;

		assert(newSize >= mSize);

		DArray<GCObject*> newData = alloc.allocArray<GCObject*>(newSize);

		if(mSize > 0)
		{
			if(mEnd > mStart)
				newData.slicea(0, mSize, mData.slice(mStart, mEnd));
			else
			{
				size_t endSize = mData.length - mStart;
				newData.slicea(0, endSize, mData.slice(mStart, mData.length));
				newData.slicea(endSize, endSize + mEnd, mData.slice(0, mEnd));
			}
		}

		alloc.freeArray(mData);
		mData = newData;
		mStart = 0;
		mEnd = mSize;
	}
}