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

alias size_t uword;

// ================================================================================================================================================
// Package
// ================================================================================================================================================

const KeyModified = 0b01;
const ValModified = 0b10;

struct Hash(K, V, bool modifiedBit = false)
{
private:
	template HashMethod(char[] expr)
	{
		static if(isStringType!(K))
			const HashMethod = "jhash(" ~ expr ~ ")";
		else static if(is(typeof(K.toHash)))
			const HashMethod = expr ~ ".toHash";
		else
			const HashMethod = "typeid(K).getHash(&" ~ expr ~ ")";
	}

	const UseHash = isStringType!(K);

	struct Node
	{
		K key;
		V value;
		uword next; // index into mNodes, or mNodes.length for "null"

		static if(UseHash)
			uint hash;

		bool used;

		static if(modifiedBit)
			ubyte modified;
	}

	Node[] mNodes;
	uint mHashMask;
	Node* mColBucket;
	uword mSize;

package:
	uword capacity()
	{
		return mNodes.length;
	}

	uword dataSize()
	{
		return mNodes.length * Node.sizeof;
	}

	void dupInto(ref Hash!(K, V, modifiedBit) other)
	{
		other.mNodes[] = mNodes[];
		other.mHashMask = mHashMask;
		other.mColBucket = other.mNodes.ptr + (mColBucket - mNodes.ptr);
		other.mSize = mSize;
	}

	void dupInto(ref Hash!(K, V, modifiedBit) other, Node[] otherNodes)
	{
		otherNodes[] = mNodes[];
		other.mNodes = otherNodes;
		other.mHashMask = mHashMask;
		other.mColBucket = otherNodes.ptr + (mColBucket - mNodes.ptr);
		other.mSize = mSize;
	}

	void prealloc(ref Allocator alloc, uword size)
	{
		if(size <= mNodes.length)
			return;
		else if(size > 4)
			resizeArray(alloc, largerPow2(size));
	}

	V* insert(ref Allocator alloc, K key)
	{
		return &insertNode(alloc, key).value;
	}

	Node* insertNode(ref Allocator alloc, K key)
	{
		uint hash = mixin(HashMethod!("key"));

		if(auto node = lookupNode(key, hash))
			return node;

		auto nodes = mNodes;
		auto colBucket = getColBucket();

		if(colBucket is null)
		{
			rehash(alloc);
			nodes = mNodes;
			colBucket = getColBucket();
			assert(colBucket !is null);
		}

		auto mainPosNodeIdx = hash & mHashMask;
		auto mainPosNode = &nodes[mainPosNodeIdx];

		if(mainPosNode.used)
		{
			auto otherNode = &nodes[mixin(HashMethod!("mainPosNode.key")) & mHashMask];

			if(otherNode is mainPosNode)
			{
				// other node is the head of its list, defer to it.
				colBucket.next = mainPosNode.next;
				mainPosNode.next = colBucket - mNodes.ptr;
				mainPosNode = colBucket;
			}
			else
			{
				// other node is in the middle of a list, push it out.
				while(otherNode.next !is mainPosNodeIdx)
					otherNode = &nodes[otherNode.next];

				otherNode.next = colBucket - mNodes.ptr;
				*colBucket = *mainPosNode;
				mainPosNode.next = nodes.length;
			}
		}
		else
			mainPosNode.next = nodes.length;

		static if(UseHash)
			mainPosNode.hash = hash;

		mainPosNode.key = key;
		mainPosNode.used = true;

		static if(modifiedBit)
			mainPosNode.modified = 0;

		mSize++;
		return mainPosNode;
	}

	bool remove(K key)
	{
		uint hash = mixin(HashMethod!("key"));
		auto nodes = mNodes;
		auto n = &nodes[hash & mHashMask];

		if(!n.used)
			return false;

		if(mixin(UseHash ? "n.hash == hash && n.key == key" : "n.key == key"))
		{
			// Removing head of list.
			if(n.next is nodes.length)
				// Only item in the list.
				markUnused(n);
			else
			{
				// Other items. Have to move the next item into where the head used to be.
				auto next = &nodes[n.next];
				*n = *next;
				markUnused(next);
			}

			return true;
		}
		else
		{
			while(n.next !is nodes.length && nodes[n.next].used)
			{
				auto next = &nodes[n.next];

				if(mixin(UseHash ? "next.hash == hash && next.key == key" : "next.key == key"))
				{
					// Removing from the middle or end of the list.
					markUnused(next);
					n.next = next.next;
					return true;
				}

				n = next;
			}

			// Nonexistent key.
			return false;
		}
	}

	V* lookup(K key)
	{
		if(auto ret = lookupNode(key, mixin(HashMethod!("key"))))
			return &ret.value;
		else
			return null;
	}

	V* lookup(K key, uint hash)
	{
		if(auto ret = lookupNode(key, hash))
			return &ret.value;
		else
			return null;
	}

	Node* lookupNode(K key)
	{
		return lookupNode(key, mixin(HashMethod!("key")));
	}

	Node* lookupNode(K key, uint hash)
	{
		if(mNodes.length == 0)
			return null;

		auto nodes = mNodes;

		for(auto n = &nodes[hash & mHashMask]; n.used; n = &nodes[n.next])
		{
			if(mixin(UseHash ? "n.hash == hash && n.key == key" : "n.key == key"))
				return n;

			if(n.next is nodes.length)
				break;
		}

		return null;
	}

	bool next(ref uword idx, ref K* key, ref V* val)
	{
		auto nodes = mNodes;

		for(; idx < nodes.length; idx++)
		{
			if(nodes[idx].used)
			{
				key = &nodes[idx].key;
				val = &nodes[idx].value;
				idx++;
				return true;
			}
		}

		return false;
	}

	int opApply(int delegate(ref K, ref V) dg)
	{
		foreach(ref node; mNodes)
		{
			if(node.used)
				if(auto result = dg(node.key, node.value))
					return result;
		}

		return 0;
	}

	int opApply(int delegate(ref V) dg)
	{
		foreach(ref node; mNodes)
		{
			if(node.used)
				if(auto result = dg(node.value))
					return result;
		}

		return 0;
	}

	static if(modifiedBit)
	{
		int modifiedSlots(int delegate(ref K, ref V) dg)
		{
			foreach(ref node; mNodes)
			{
				if(node.used && node.modified)
				{
					int result = void;

					if(node.modified & KeyModified)
					{
						if(node.modified & ValModified)
							result = dg(node.key, node.value);
						else
							result = dg(node.key, V.init);
					}
					else if(node.modified & ValModified)
					{
						K k;
						result = dg(k, node.value);
					}

					node.modified = 0;

					if(result)
						return result;
				}
			}

			return 0;
		}

		int allNodes(int delegate(ref Node) dg)
		{
			foreach(ref node; mNodes)
			{
				if(node.used)
				{
					if(auto result = dg(node))
						return result;
				}
			}

			return 0;
		}
	}

	uword length()
	{
		return mSize;
	}

	void minimize(ref Allocator alloc)
	{
		if(mSize == 0)
			clear(alloc);
		else
		{
			uword newSize = 4;
			for(; newSize < mSize; newSize <<= 1) {}
			resizeArray(alloc, newSize);
		}
	}

	void clear(ref Allocator alloc)
	{
		alloc.freeArray(mNodes);
		mNodes = null;
		mHashMask = 0;
		mColBucket = null;
		mSize = 0;
	}

private:
	void markUnused(Node* n)
	{
		assert(n >= mNodes.ptr && n < mNodes.ptr + mNodes.length);

		n.used = false;

		if(n < mColBucket)
			mColBucket = n;

		mSize--;
	}

	void rehash(ref Allocator alloc)
	{
		if(mNodes.length != 0)
			resizeArray(alloc, mNodes.length * 2);
		else
			resizeArray(alloc, 4);
	}

	void resizeArray(ref Allocator alloc, uword newSize)
	{
		auto oldNodes = mNodes;

		mNodes = alloc.allocArray!(Node)(newSize);
		mHashMask = mNodes.length - 1;
		mColBucket = mNodes.ptr;
		mSize = 0;

		foreach(ref node; oldNodes)
		{
			if(node.used)
			{
				auto newNode = insertNode(alloc, node.key);
				newNode.value = node.value;

				static if(modifiedBit)
					newNode.modified = node.modified;
			}
		}

		alloc.freeArray(oldNodes);
	}

	Node* getColBucket()
	{
		for(auto end = mNodes.ptr + mNodes.length; mColBucket < end; mColBucket++)
			if(mColBucket.used == false)
				return mColBucket;

		return null;
	}
}