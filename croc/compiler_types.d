/******************************************************************************
This module defines some types used by the compiler.  It also abstracts the
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
	void exception(CompileLoc loc, char[] msg, ...);
	void eofException(CompileLoc loc, char[] msg, ...);
	void loneStmtException(CompileLoc loc, char[] msg, ...);
	CrocThread* thread();
	Allocator* alloc();
	void addNode(IAstNode node);
	char[] newString(char[] s);
}

// Common compiler stuff
template ICompilerMixin()
{
	private IAstNode mHead;

	override void addNode(IAstNode node)
	{
		node.next = mHead;
		mHead = node;
	}
}

// Abstract AST nodes for the compiler to be able to deal with them
interface IAstNode
{
	void next(IAstNode n);
	IAstNode next();
	void[] toVoidArray();
	void cleanup(ref Allocator alloc);
}

// Common AST node stuff
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
	
	override void[] toVoidArray()
	{
		return (cast(void*)this)[0 .. this.classinfo.init.length];
	}
}

// Dynamically-sized list.  When you use .toArray(), it hands off the reference to its
// data, meaning that you now own the data and must clean it up.
scope class List(T)
{
	private Allocator* mAlloc;
	private T[] mData;
	private uword mIndex = 0;

	package this(Allocator* alloc)
	{
		mAlloc = alloc;
	}

	~this()
	{
		if(mData.length)
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
	
	public void add(T[] items)
	{
		foreach(ref i; items)
			add(i);
	}

	alias add opCatAssign;

	public T opIndex(uword index)
	{
		return mData[index];
	}
	
	public T opIndexAssign(T t, uword index)
	{
		return mData[index] = t;
	}

	public void length(uword l)
	{
		mIndex = l;

		if(mIndex > mData.length)
			mAlloc.resizeArray(mData, mIndex);
	}

	public uword length()
	{
		return mIndex;
	}

	public T[] toArray()
	{
		mAlloc.resizeArray(mData, mIndex);
		auto ret = mData;
		mData = null;
		mIndex = 0;
		return ret;
	}

	public int opApply(int delegate(ref T) dg)
	{
		foreach(ref v; mData[0 .. mIndex])
			if(auto result = dg(v))
				return result;
		
		return 0;
	}
	
	public int opApply(int delegate(uword, ref T) dg)
	{
		foreach(i, ref v; mData[0 .. mIndex])
			if(auto result = dg(i, v))
				return result;
		
		return 0;
	}
}