/******************************************************************************
This module contains internal implementation of the string object.

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

module croc.types_string;

import tango.text.Util;

import croc.types;
import croc.utils;

struct string
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	package CrocString* lookup(CrocVM* vm, char[] data, ref uword h)
	{
		// We don't have to verify the string if it already exists in the string table,
		// because if it does, it means it's a legal string.
		// Neither hashing nor lookup require the string to be valid UTF-8.
		h = jhash(data);

		if(auto s = vm.stringTab.lookup(data, h))
			return *s;

		return null;
	}
	
	package void dumpTable(CrocVM* vm)
	{
		Stdout.formatln("==== String table ====");
		
		foreach(k, v; vm.stringTab)
			Stdout.formatln("  '{}': {} {:x} {} {}", k, v, v.hash, v.length, v.cpLength);
	}

	// Create a new string object. String objects with the same data are reused. Thus,
	// if two string objects are identical, they are also equal.
	package CrocString* create(CrocVM* vm, char[] data, uword h, uword cpLen)
	{
		Stdout.formatln("enter");
		if(data.length == 5)
		{
			Stdout.formatln("b  {} {} {} {} {}", cast(uint)data[0], cast(uint)data[1], cast(uint)data[2], cast(uint)data[3], cast(uint)data[4]);
			dumpTable(vm);
		}

		auto ret = vm.alloc.allocate!(CrocString)(StringSize(data.length));
		ret.hash = h;
		ret.length = data.length;
		ret.cpLength = cpLen;
		ret.toString()[] = data[];

		*vm.stringTab.insert(vm.alloc, ret.toString()) = ret;

		Stdout.formatln("Just created the string '{} {}'", ret.toString().ptr, ret.toString().length);
		if(ret.toString().length == 5)
		{
			Stdout.formatln("c  {} {} {} {} {}", cast(uint)ret.toString()[0], cast(uint)ret.toString()[1], cast(uint)ret.toString()[2], cast(uint)ret.toString()[3], cast(uint)ret.toString()[4]);
			Stdout.formatln("d  {} {} {} {} {}", cast(uint)data[0], cast(uint)data[1], cast(uint)data[2], cast(uint)data[3], cast(uint)data[4]);
		}

		Stdout.formatln("exit");

		return ret;
	}

	// Finalize a string object.
	package void finalize(CrocVM* vm, CrocString* s)
	{
		Stdout.formatln("Finalizing '{}'", s.toString());
		auto b = vm.stringTab.remove(s.toString());
		assert(b);

// 		dumpTable(vm);
	}
	import tango.io.Stdout;

	// Compare two string objects.
	package crocint compare(CrocString* a, CrocString* b)
	{
		return scmp(a.toString(), b.toString());
	}

	// See if the string contains the given character.
	package bool contains(CrocString* s, dchar c)
	{
		foreach(dchar ch; s.toString())
			if(c == ch)
				return true;

		return false;
	}

	// See if the string contains the given substring.
	package bool contains(CrocString* s, char[] sub)
	{
		if(s.length < sub.length)
			return false;

		return s.toString().locatePattern(sub) != s.length;
	}

	// The slice indices are in codepoints, not byte indices.
	// And these indices better be good.
	package CrocString* slice(CrocVM* vm, CrocString* s, uword lo, uword hi)
	{
		auto str = uniSlice(s.toString(), lo, hi);
		uword h = void;

		if(auto s = lookup(vm, str, h))
			return s;

		// don't have to verify since we're slicing from a string we know is good
		return create(vm, uniSlice(s.toString(), lo, hi), h, hi - lo);
	}

	// Like slice, the index is in codepoints, not byte indices.
	package dchar charAt(CrocString* s, uword idx)
	{
		return uniCharAt(s.toString(), idx);
	}

	// ================================================================================================================================================
	// Private
	// ================================================================================================================================================

	private uword StringSize(uword length)
	{
		return CrocString.sizeof + (char.sizeof * length);
	}
}