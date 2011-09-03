/******************************************************************************
This module contains the implementation of a templated hash table. This uses
a form of coalesced hashing, which is a cross between separate chaining and
linear probing. It has the advantages of only requiring a single block of
memory (instead of one block for each collided key), as well as being able
to have a 100% load factor without a large speed penalty. It's also very
easy to iterate over.

This object is used in the implementation of tables and namespaces, as well
as being used as a general-purpose hash in other places.

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

module croc.base_hash;

import tango.text.Util;

import croc.base_alloc;
import croc.utils;

// ================================================================================================================================================
// Package
// ================================================================================================================================================

struct Hash(K, V)
{
	template HashMethod(char[] expr)
	{
		static if(isStringType!(K))
			const HashMethod = "jhash(" ~ expr ~ ")";
		else static if(is(typeof(K.toHash)))
			const HashMethod = expr ~ ".toHash";
		else
			const HashMethod = "typeid(K).getHash(&" ~ expr ~ ")";
	}

	private const UseHash = isStringType!(K);

	struct Node
	{
		static if(UseHash)
			uint hash;

		K key;
		V value;
		Node* next;
		bool used;
	}

	private Node[] mNodes;
	private uint mHashMask;
	private Node* mColBucket;
	private size_t mSize;

	package void prealloc(ref Allocator alloc, size_t size)
	{
		if(size <= mNodes.length)
			return;

		size_t newSize = 4;
		for(; newSize < size; newSize <<= 1) {}
		resizeArray(alloc, newSize);
	}

	package V* insert(ref Allocator alloc, K key)
	{
		uint hash = mixin(HashMethod!("key"));

		if(auto val = lookup(key, hash))
			return val;

		auto colBucket = getColBucket();

		if(colBucket is null)
		{
			rehash(alloc);
			colBucket = getColBucket();
			assert(colBucket !is null);
		}

		auto mainPosNode = &mNodes[hash & mHashMask];

		if(mainPosNode.used)
		{
			auto otherNode = &mNodes[mixin(HashMethod!("mainPosNode.key")) & mHashMask];

			if(otherNode is mainPosNode)
			{
				// other node is the head of its list, defer to it.
				colBucket.next = mainPosNode.next;
				mainPosNode.next = colBucket;
				mainPosNode = colBucket;
			}
			else
			{
				// other node is in the middle of a list, push it out.
				while(otherNode.next !is mainPosNode)
					otherNode = otherNode.next;

				otherNode.next = colBucket;
				*colBucket = *mainPosNode;
				mainPosNode.next = null;
			}
		}
		else
			mainPosNode.next = null;

		static if(UseHash)
			mainPosNode.hash = hash;

		mainPosNode.key = key;
		mainPosNode.used = true;
		mSize++;

		return &mainPosNode.value;
	}

	package bool remove(K key)
	{
		uint hash = mixin(HashMethod!("key"));
		auto n = &mNodes[hash & mHashMask];

		if(!n.used)
			return false;

		if(mixin(UseHash ? "n.hash == hash && n.key == key" : "n.key == key"))
		{
			// Removing head of list.
			if(n.next is null)
				// Only item in the list.
				markUnused(n);
			else
			{
				// Other items. Have to move the next item into where the head used to be.
				auto next = n.next;
				*n = *next;
				markUnused(next);
			}

			return true;
		}
		else
		{
			for(; n.next !is null && n.next.used; n = n.next)
			{
				if(mixin(UseHash ? "n.next.hash == hash && n.next.key == key" : "n.next.key == key"))
				{
					// Removing from the middle or end of the list.
					markUnused(n.next);
					n.next = n.next.next;
					return true;
				}
			}

			// Nonexistent key.
			return false;
		}
	}

	package V* lookup(K key)
	{
		if(mNodes.length == 0)
			return null;

		return lookup(key, mixin(HashMethod!("key")));
	}

	package V* lookup(K key, uint hash)
	{
		if(mNodes.length == 0)
			return null;

		for(auto n = &mNodes[hash & mHashMask]; n !is null && n.used; n = n.next)
			if(mixin(UseHash ? "n.hash == hash && n.key == key" : "n.key == key"))
				return &n.value;

		return null;
	}

	package bool next(ref size_t idx, ref K* key, ref V* val)
	{
		for(; idx < mNodes.length; idx++)
		{
			if(mNodes[idx].used)
			{
				key = &mNodes[idx].key;
				val = &mNodes[idx].value;
				idx++;
				return true;
			}
		}

		return false;
	}

	package int opApply(int delegate(ref K, ref V) dg)
	{
		foreach(ref node; mNodes)
		{
			if(node.used)
				if(auto result = dg(node.key, node.value))
					return result;
		}
		
		return 0;
	}
	
	package int opApply(int delegate(ref V) dg)
	{
		foreach(ref node; mNodes)
		{
			if(node.used)
				if(auto result = dg(node.value))
					return result;
		}

		return 0;
	}

	package size_t length()
	{
		return mSize;
	}

	package void minimize(ref Allocator alloc)
	{
		if(mSize == 0)
			clear(alloc);
		else
		{
			size_t newSize = 4;
			for(; newSize < mSize; newSize <<= 1) {}
			resizeArray(alloc, newSize);
		}
	}
	
	package void clear(ref Allocator alloc)
	{
		alloc.freeArray(mNodes);
		mNodes = null;
		mHashMask = 0;
		mColBucket = null;
		mSize = 0;
	}

	private void markUnused(Node* n)
	{
		assert(n >= mNodes.ptr && n < mNodes.ptr + mNodes.length);

		n.used = false;

		if(n < mColBucket)
			mColBucket = n;
			
		mSize--;
	}

	private void rehash(ref Allocator alloc)
	{
		if(mNodes.length != 0)
			resizeArray(alloc, mNodes.length * 2);
		else
			resizeArray(alloc, 4);
	}

	private void resizeArray(ref Allocator alloc, size_t newSize)
	{
		auto oldNodes = mNodes;

		mNodes = alloc.allocArray!(Node)(newSize);
		mHashMask = mNodes.length - 1;
		mColBucket = mNodes.ptr;
		mSize = 0;

		foreach(ref node; oldNodes)
			if(node.used)
				*insert(alloc, node.key) = node.value;

		alloc.freeArray(oldNodes);
	}

	private Node* getColBucket()
	{
		for(auto end = mNodes.ptr + mNodes.length; mColBucket < end; mColBucket++)
			if(mColBucket.used == false)
				return mColBucket;

		return null;
	}
}