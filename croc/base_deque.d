/******************************************************************************
This module contains the implementation of an array double-ended queue, used
internally by the garbage collector.

License:
Copyright (c) 2011 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module croc.base_deque;

import croc.base_alloc;
import croc.utils;

alias size_t uword;

// ================================================================================================================================================
// Package
// ================================================================================================================================================

struct Deque(T)
{
private:
	T[] mData;
	uword mStart;
	uword mEnd;
	uword mSize;

package:
	void prealloc(ref Allocator alloc, uword size)
	{
		if(size <= mData.length)
			return;
		else if(size > 4)
			resizeArray(alloc, largerPow2(size));
	}
	
	void add(ref Allocator alloc, T t)
	{
		if(isFull())
			enlargeArray(alloc);

		mData[mEnd++] = t;

		if(mEnd == mData.length)
			mEnd = 0;
		
		mSize++;
	}
	
	T remove()
	{
		debug assert(!isEmpty());

		auto ret = mData[mStart++];

		if(mStart == mData.length)
			mStart = 0;

		mSize--;

		return ret;
	}

	void append(ref Allocator alloc, T[] ts)
	{
		if(mData.length < (mSize + ts.length))
			resizeArray(alloc, largerPow2(mSize + ts.length));

		if(mStart <= mEnd)
		{
			// empty space may be split over the end
			uword endSize = mData.length - mEnd;

			if(endSize >= ts.length)
			{
				mData[mEnd .. mEnd + ts.length] = ts[];
				mEnd += ts.length;
			}
			else
			{
				mData[mEnd .. $] = ts[0 .. endSize];
				mData[0 .. ts.length - endSize] = ts[endSize .. $];
				mEnd = ts.length - endSize;
			}
		}
		else
		{
			mData[mEnd .. mEnd + ts.length] = ts[];
			mEnd += ts.length;
		}

		if(mEnd == mData.length)
			mEnd = 0;

		mSize += ts.length;
	}
	
	void append(ref Allocator alloc, ref Deque!(T) other)
	{
		if(other.length == 0)
			return;

		if(mData.length < (mSize + other.length))
			resizeArray(alloc, largerPow2(mSize + other.length));
			
		if(other.mStart >= other.mEnd)
		{
			append(alloc, other.mData[other.mStart .. $]);
			append(alloc, other.mData[0 .. other.mEnd]);
		}
		else
			append(alloc, other.mData[other.mStart .. other.mEnd]);
	}

	bool isEmpty()
	{
		return mSize == 0;
	}

	bool isFull()
	{
		return mSize == mData.length;
	}

	uword length()
	{
		return mSize;
	}

	uword capacity()
	{
		return mData.length;
	}
	
	void reset()
	{
		mStart = mEnd = mSize = 0;
	}

	void clear(ref Allocator alloc)
	{
		alloc.freeArray(mData);
		reset();
	}

	void minimize(ref Allocator alloc)
	{
		if(mSize == 0)
			clear(alloc);
		else
		{
			auto size = largerPow2(mSize);
			resizeArray(alloc, size < 4 ? 4 : size);
		}
	}

	int opApply(int delegate(ref T v) dg)
	{
		if(mSize == 0)
			return 0;

		if(mStart >= mEnd)
		{
			foreach(v; mData[mStart .. $])
				if(auto ret = dg(v))
					return ret;
			
			foreach(v; mData[0 .. mEnd])
				if(auto ret = dg(v))
					return ret;
		}
		else
		{
			foreach(v; mData[mStart .. mEnd])
				if(auto ret = dg(v))
					return ret;
		}

		return 0;
	}

	struct Iterator
	{
	private:
		Deque!(T)* mDeque;
		uword mIdx;
		bool mDead = false;
		debug uword mStartSize, mStartLength;

		static Iterator opCall(Deque!(T)* d)
		{
			Iterator ret;
			ret.mDeque = d;
			ret.mIdx = d.mStart;

			if(d.mSize == 0)
				ret.mDead = true;

			debug ret.mStartSize = d.mSize;
			debug ret.mStartLength = d.mData.length;

			return ret;
		}

	public:
		bool hasNext()
		{
			return !mDead;
		}

		T next()
		{
			debug assert(!mDead);
			debug assert(mDeque.mSize <= mStartSize);
			debug assert(mDeque.mData.length == mStartLength);

			auto ret = mDeque.mData[mIdx++];

			if(mIdx == mDeque.mData.length)
				mIdx = 0;
			
			if(mIdx == mDeque.mEnd)
				mDead = true;

			return ret;
		}
		
		void removeCurrent()
		{
			debug assert(!mDeque.isEmpty());

			auto idx = mIdx == 0 ? mDeque.mData.length - 1 : mIdx - 1;
			
			if(idx == mDeque.mStart)
				mDeque.remove();
			else
				mDeque.mData[idx] = mDeque.remove();
		}
	}
	
	Iterator iterator()
	{
		return Iterator(this);
	}

private:
	void enlargeArray(ref Allocator alloc)
	{
		if(mData.length != 0)
			resizeArray(alloc, mData.length * 2);
		else
			resizeArray(alloc, 4);
	}
	
	void resizeArray(ref Allocator alloc, uword newSize)
	{
		if(mData.length == newSize)
			return;

		debug assert(newSize >= mSize, "data castration! D:");

		auto newData = alloc.allocArray!(T)(newSize);

		if(mSize > 0)
		{
			if(mEnd > mStart)
				newData[0 .. mSize] = mData[mStart .. mEnd];
			else
			{
				uword endSize = mData.length - mStart;
				newData[0 .. endSize] = mData[mStart .. $];
				newData[endSize .. endSize + mEnd] = mData[0 .. mEnd];
			}
		}
		
		alloc.freeArray(mData);
		mData = newData;
		mStart = 0;
		mEnd = mSize;
	}
}