/******************************************************************************
This module defines some types used by the compiler. It also abstracts the
interface to the compiler to avoid circular imports.

License:
Copyright (c) 2008 Jarrett Billingsley

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

module croc.compiler_types;

import croc.base_alloc;
import croc.types;

// Template for generating internal variable names
template InternalName(char[] name)
{
	const InternalName = "$" ~ name;
}

// Location, duh.
struct CompileLoc
{
	char[] file;
	uint line;
	uint col;
}

// Abstract the compiler for other phases to be able to refer to it non-circularly
interface ICompiler
{
	bool asserts();
	bool typeConstraints();
	bool docComments();
	bool docTable();
	bool docDecorators();
	bool isEof();
	bool isLoneStmt();
	bool isDanglingDoc();
	void lexException(CompileLoc loc, char[] msg, ...);
	void synException(CompileLoc loc, char[] msg, ...);
	void semException(CompileLoc loc, char[] msg, ...);
	void eofException(CompileLoc loc, char[] msg, ...);
	void loneStmtException(CompileLoc loc, char[] msg, ...);
	CrocThread* thread();
	Allocator* alloc();
	char[] newString(char[] s);
	void* allocNode(uword size);
	void addArray(void[] arr);
	void[] copyArray(void[] arr);
}

// Dynamically-sized list.
scope class List(T, uword Len = 8)
{
private:
	ICompiler c;
	T[Len] mOwnData;
	T[] mData;
	uword mIndex = 0;

package:
	this(ICompiler c)
	{
		this.c = c;
		mData = mOwnData[];
	}

	~this()
	{
		if(mData.length && mData.ptr !is mOwnData.ptr)
			c.alloc.freeArray(mData);
	}

	void add(T item)
	{
		if(mIndex >= mData.length)
			resize(mData.length * 2);

		mData[mIndex] = item;
		mIndex++;
	}

	void add(T[] items)
	{
		foreach(ref i; items)
			add(i);
	}

	alias add opCatAssign;

	T opIndex(uword index)
	{
		return mData[index];
	}

	T opIndexAssign(T t, uword index)
	{
		return mData[index] = t;
	}

	void length(uword l)
	{
		mIndex = l;

		if(mIndex > mData.length)
			resize(mIndex);
	}

	uword length()
	{
		return mIndex;
	}

	T[] toArray()
	{
		T[] ret = void;

		if(mData.ptr is mOwnData.ptr)
			ret = cast(T[])c.copyArray(mData[0 .. mIndex]);
		else
		{
			c.alloc.resizeArray(mData, mIndex);
			c.addArray(mData);
			ret = mData;
		}

		mData = mOwnData[];
		mIndex = 0;
		return ret;
	}

	T[] toArrayView()
	{
		return mData[0 .. mIndex];
	}

	int opApply(int delegate(ref T) dg)
	{
		foreach(ref v; mData[0 .. mIndex])
			if(auto result = dg(v))
				return result;

		return 0;
	}

	int opApply(int delegate(uword, ref T) dg)
	{
		foreach(i, ref v; mData[0 .. mIndex])
			if(auto result = dg(i, v))
				return result;

		return 0;
	}

	private void resize(uword newSize)
	{
		if(mData.ptr is mOwnData.ptr)
		{
			auto newData = c.alloc.allocArray!(T)(newSize);
			newData[0 .. mData.length] = mData[];
			mData = newData;
		}
		else
			c.alloc.resizeArray(mData, newSize);
	}
}

// Little bump allocator.
struct BumpAllocator(uword PageSize)
{
private:
	Allocator* mAlloc;
	void[][] mData;
	uword mPage;
	uword mOffset;

public:
	void init(Allocator* alloc)
	{
		mAlloc = alloc;
		mData = alloc.allocArray!(void[])(4);
	}

	void free()
	{
		foreach(arr; mData[0 .. mPage + 1])
			mAlloc.freeArray(arr);

		mAlloc.freeArray(mData);
	}

	void* alloc(uword size)
	{
		assert(size <= PageSize, "Allocation too big");

		_again:

		if(mPage >= mData.length)
			mAlloc.resizeArray(mData, mData.length * 2);

		if(mData[mPage].length == 0)
			mData[mPage] = mAlloc.allocArray!(void)(PageSize);

		auto roundedSize = (size + (uword.sizeof - 1)) & ~(uword.sizeof - 1);

		if(roundedSize > (PageSize - mOffset))
		{
			mPage++;
			mOffset = 0;
			goto _again;
		}

		auto ret = cast(void*)mData[mPage].ptr + mOffset;
		mOffset += roundedSize;
		return ret;
	}

	uword size()
	{
		return mOffset + (mPage > 0 ? mPage * PageSize : 0);
	}
}