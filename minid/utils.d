/******************************************************************************
This module holds a variety of utility functions used throughout MiniD.  This
module doesn't (and shouldn't) depend on the rest of the library in any way,
and as such can't hold implementation-specific functionality.  For that, look
in the minid.misc module.

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

module minid.utils;

import tango.core.Array : find;
import tango.core.Traits;
import tango.core.Tuple;
import tango.text.convert.Utf;
import tango.text.Util;

/**
See if a string starts with another string.  Useful.
*/
public bool startsWith(T)(T[] string, T[] pattern)
{
	return string.length >= pattern.length && string[0 .. pattern.length] == pattern[];
}

/**
See if a string ends with another string.  Also useful.
*/
public bool endsWith(T)(T[] string, T[] pattern)
{
	return string.length >= pattern.length && string[$ - pattern.length .. $] == pattern[];
}

/**
See if an array contains an item.
*/
bool contains(T)(T[] arr, T elem)
{
	return arr.find(elem) != arr.length;
}

/**
Compare two values, a and b, using < and >.  Returns -1 if a < b, 1 if a > b, and 0 otherwise.
*/
public int Compare3(T)(T a, T b)
{
	return a < b ? -1 : a > b ? 1 : 0;
}

/**
Compares char[] strings stupidly (just by character value, not lexicographically).
*/
public int scmp(char[] s1, char[] s2)
{
	auto len = s1.length;

	if(s2.length < len)
		len = s2.length;

	auto result = mismatch(s1.ptr, s2.ptr, len);

	if(result == len)
		return Compare3(s1.length, s2.length);
	else
		return Compare3(s1[result], s2[result]);
}

/**
Verifies that the given UTF-8 string is well-formed and returns the length in codepoints.
*/
public size_t verify(char[] s)
{
	size_t ret = 0;

	foreach(dchar c; s)
		ret++;

	return ret;
}

/**
Slice a UTF-8 string using codepoint indices.
*/
public char[] uniSlice(char[] s, size_t lo, size_t hi)
{
	if(lo == hi)
		return null;

	auto tmp = s;
	uint realLo = 0;

	for(size_t i = 0; i < lo; i++)
	{
		uint ate = 0;
		decode(tmp, ate);
		tmp = tmp[ate .. $];
		realLo += ate;
	}

	uint realHi = realLo;

	for(size_t i = lo; i < hi; i++)
	{
		uint ate = 0;
		decode(tmp, ate);
		tmp = tmp[ate .. $];
		realHi += ate;
	}

	return s[realLo .. realHi];
}

/**
Get the character in a UTF-8 string at the given codepoint index.
*/
public dchar uniCharAt(char[] s, size_t idx)
{
	auto tmp = s;
	uint ate = 0;

	for(size_t i = 0; i < idx; i++)
	{
		decode(tmp, ate);
		tmp = tmp[ate .. $];
	}

	return decode(tmp, ate);
}

/**
Convert a codepoint index into a UTF-8 string into a byte index.
*/
public size_t uniCPIdxToByte(char[] s, size_t fake)
{
	auto tmp = s;
	uint ate = 0;

	for(size_t i = 0; i < fake; i++)
	{
		decode(tmp, ate);
		tmp = tmp[ate .. $];
	}

	return tmp.ptr - s.ptr;
}

/**
Metafunction to see if a given type is one of char[], wchar[] or dchar[].
*/
public template isStringType(T)
{
	const bool isStringType = is(T : char[]) || is(T : wchar[]) || is(T : dchar[]);
}

/**
Sees if a type is an array.
*/
public template isArrayType(T)
{
	const bool isArrayType = false;
}

public template isArrayType(T : T[])
{
	const bool isArrayType = true;
}

/**
Sees if a type is an associative array.
*/
public template isAAType(T)
{
	const bool isAAType = is(typeof(T.init.values[0])[typeof(T.init.keys[0])] == T);
}

/**
Get to the bottom of any chain of typedefs!  Returns the first non-typedef'ed type.
*/
public template realType(T)
{
	static if(is(T Base == typedef) || is(T Base == enum))
		alias realType!(Base) realType;
	else
		alias T realType;
}

unittest
{
	assert(isStringType!(char[]));
	assert(isStringType!(wchar[]));
	assert(isStringType!(dchar[]));
	assert(!isStringType!(int));
	assert(!isStringType!(Object));

	assert(isArrayType!(int[]));
	assert(isArrayType!(char[]));
	assert(isArrayType!(int[3][4]));
	assert(!isArrayType!(int[int]));
	assert(!isArrayType!(Object));

	typedef int X;
	typedef X Y;
	
	assert(is(realType!(X) == int));
	assert(is(realType!(Y) == int));
}

/**
Make a FOURCC code out of a four-character string.  This is I guess for little-endian platforms..
*/
public template FOURCC(char[] name)
{
	static assert(name.length == 4, "FOURCC's parameter must be 4 characters");
	const uint FOURCC = (cast(uint)name[3] << 24) | (cast(uint)name[2] << 16) | (cast(uint)name[1] << 8) | cast(uint)name[0];
}

/**
Make a version with the major number in the upper 16 bits and the minor in the lower 16 bits.
*/
public template MakeVersion(uint major, uint minor)
{
	const uint MakeVersion = (major << 16) | minor;
}

/**
Gets the name of a function alias.
*/
public template NameOfFunc(alias f)
{
	version(LDC)
		const char[] NameOfFunc = (&f).stringof[1 .. $];
	else
		const char[] NameOfFunc = (&f).stringof[2 .. $];
}

debug
{
	private void _foo_(){}
	static assert(NameOfFunc!(_foo_) == "_foo_", "Oh noes, NameOfFunc needs to be updated.");
}

/**
Given a predicate template and a tuple, sorts the tuple.  I'm not sure how quick it is, but it's probably fast enough
for sorting most tuples, which hopefully won't be that long.  The predicate template should take two parameters of the
same type as the tuple's elements, and return <0 for A < B, 0 for A == B, and >0 for A > B (just like opCmp).
*/
public template QSort(alias Pred, List...)
{
	static if(List.length == 0 || List.length == 1)
		alias List QSort;
	else static if(List.length == 2)
	{
		static if(Pred!(List[0], List[1]) <= 0)
			alias Tuple!(List[0], List[1]) QSort;
		else
			alias Tuple!(List[1], List[0]) QSort;
	}
	else
		alias Tuple!(QSort!(Pred, QSort_less!(Pred, List)), QSort_equal!(Pred, List), List[0], QSort!(Pred, QSort_greater!(Pred, List))) QSort;
}

private template QSort_less(alias Pred, List...)
{
	static if(List.length == 0 || List.length == 1)
		alias Tuple!() QSort_less;
	else static if(Pred!(List[1], List[0]) < 0)
		alias Tuple!(List[1], QSort_less!(Pred, List[0], List[2 .. $])) QSort_less;
	else
		alias QSort_less!(Pred, List[0], List[2 .. $]) QSort_less;
}

private template QSort_equal(alias Pred, List...)
{
	static if(List.length == 0 || List.length == 1)
		alias Tuple!() QSort_equal;
	else static if(Pred!(List[1], List[0]) == 0)
		alias Tuple!(List[1], QSort_equal!(Pred, List[0], List[2 .. $])) QSort_equal;
	else
		alias QSort_equal!(Pred, List[0], List[2 .. $]) QSort_equal;
}

private template QSort_greater(alias Pred, List...)
{
	static if(List.length == 0 || List.length == 1)
		alias Tuple!() QSort_greater;
	else static if(Pred!(List[1], List[0]) > 0)
		alias Tuple!(List[1], QSort_greater!(Pred, List[0], List[2 .. $])) QSort_greater;
	else
		alias QSort_greater!(Pred, List[0], List[2 .. $]) QSort_greater;
}

/**
A useful template that somehow is in Phobos but no Tango.  Sees if a tuple is composed
entirely of expressions or aliases.
*/
public template isExpressionTuple(T...)
{
	static if (is(void function(T)))
		const bool isExpressionTuple = false;
	else
		const bool isExpressionTuple = true;
}

/**
For a given struct, gets a tuple of the names of its fields.

I have absolutely no idea if what I'm doing here is in any way legal.  I more or less discovered
that the compiler gives access to this info in odd cases, and am just exploiting that.  It would
be fantastic if the compiler would just tell us these things, but alas, we have to rely on
seemingly-buggy undefined behavior.  Sigh.
*/
public template FieldNames(S, int idx = 0)
{
	static if(idx >= S.tupleof.length)
		alias Tuple!() FieldNames;
	else
		alias Tuple!(GetLastName!(S.tupleof[idx].stringof), FieldNames!(S, idx + 1)) FieldNames;
}

package template GetLastName(char[] fullName, int idx = fullName.length - 1)
{
	static if(idx < 0)
		const char[] GetLastName = fullName;
	else static if(fullName[idx] == '.')
		const char[] GetLastName = fullName[idx + 1 .. $];
	else
		const char[] GetLastName = GetLastName!(fullName, idx - 1);
}

/**
Given an alias to a function, this will give the minimum legal number of arguments it can be called with.
Even works for aliases to class methods.  Note, however, that this isn't smart enough to detect the difference
between, say, "void foo(int x, int y = 10)" and "void foo(int x) ... void foo(int x, int y)".  There might
be a difference, though, so be cautions.
*/
public template MinArgs(alias func)
{
	const uint MinArgs = MinArgsImpl!(func, 0, InitsOf!(ParameterTupleOf!(typeof(&func))));
}

private template MinArgsImpl(alias func, int index, Args...)
{
	static if(index >= Args.length)
		const uint MinArgsImpl = Args.length;
	else static if(is(typeof(func(Args[0 .. index]))))
		const uint MinArgsImpl = index;
	else
		const uint MinArgsImpl = MinArgsImpl!(func, index + 1, Args);
}

/**
Given a type tuple, this will give an expression tuple of all the .init values for each type.
*/
public template InitsOf(T...)
{
	static if(T.length == 0)
		alias Tuple!() InitsOf;
	else
		alias Tuple!(InitOf!(T[0]), InitsOf!(T[1 .. $])) InitsOf;
}

// BUG 1667
private T InitOf_shim(T)()
{
	T t;
	return t;
}

// This template exists for the sole reason that T.init doesn't work for structs inside templates due
// to a forward declaration error.
private template InitOf(T)
{
	static if(!is(typeof(Tuple!(T.init))))
		alias Tuple!(InitOf_shim!(T)()) InitOf;
	else
		alias Tuple!(T.init) InitOf;
}

/**
Given a class or struct type, gets its name.  This really only exists to mask potential oddities with the
way the compiler reports this info (for example, DMD used to insert a space before struct names, but that
no longer seems to happen..).
*/
public template NameOfType(T)
{
	const char[] NameOfType = T.stringof;
}

debug
{
	private class _Fribble_ {}
	private struct _Frobble_ {}

	static assert(NameOfType!(_Fribble_) == "_Fribble_", "NameOfType doesn't work for classes (got " ~ NameOfType!(_Fribble_) ~ ")");
	static assert(NameOfType!(_Frobble_) == "_Frobble_", "NameOfType doesn't work for structs (got " ~ NameOfType!(_Frobble_) ~ ")");
}