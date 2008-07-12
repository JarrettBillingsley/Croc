/******************************************************************************
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

module minid.compilertypes;

import minid.alloc;
import minid.types;

struct CompileLoc
{
	dchar[] file;
	uint line;
	uint col;
}

interface ICompiler
{
	bool asserts();
	bool typeConstraints();
	bool isEof();
	bool isLoneStmt();
	void exception(ref CompileLoc loc, dchar[] msg, ...);
	void eofException(ref CompileLoc loc, dchar[] msg, ...);
	void loneStmtException(ref CompileLoc loc, dchar[] msg, ...);
	MDThread* thread();
	Allocator* alloc();
	void addNode(IAstNode node);
}

template ICompilerMixin()
{
	private IAstNode mHead;

	override void addNode(IAstNode node)
	{
		node.next = mHead;
		mHead = node;
	}
}

interface IAstNode
{
	void next(IAstNode n);
	IAstNode next();
}

template IAstNodeMixin()
{
	private IAstNode mNext;

	override void next(IAstNode n)
	{
		mNext = n;
	}

	override IAstNode next()
	{
		return mNext;
	}
}

scope class List(T)
{
	private Allocator* mAlloc;
	private T[] mData;
	private size_t mIndex = 0;

	package this(Allocator* alloc)
	{
		mAlloc = alloc;
	}

	~this()
	{
		mAlloc.freeArray(mData);
	}

	public void add(T item)
	{
		if(mIndex >= mData.length)
		{
			if(mData.length == 0)
				mData = mAlloc.allocArray!(T)(10);
			else
				mAlloc.resizeArray(mData, mData.length * 2);
		}

		mData[mIndex] = item;
		mIndex++;
	}

	alias add opCatAssign;

	public T opIndex(size_t index)
	{
		return mData[index];
	}

	public void length(size_t l)
	{
		mIndex = l;

		if(mIndex > mData.length)
			mAlloc.resizeArray(mData, mIndex);
	}

	public size_t length()
	{
		return mIndex;
	}

	public T[] toArray()
	{
		mAlloc.resizeArray(mData, mIndex);
		return mData;
	}

	public int opApply(int delegate(ref T) dg)
	{
		int result = 0;

		foreach(ref v; mData[0 .. mIndex])
		{
			result = dg(v);
			
			if(result)
				break;
		}
		
		return result;
	}
	
	public int opApply(int delegate(size_t, ref T) dg)
	{
		int result = 0;

		foreach(i, ref v; mData[0 .. mIndex])
		{
			result = dg(i, v);
			
			if(result)
				break;
		}
		
		return result;
	}
}