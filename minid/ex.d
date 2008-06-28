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

module minid.ex;

import tango.core.Tuple;
import tango.stdc.ctype;
import tango.text.Util;

import minid.api;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public struct CreateObject
{
	private MDThread* t;
	private dchar[] name;
	private nint idx;

	public static void opCall(MDThread* t, dchar[] name, void delegate(CreateObject*) dg)
	{
		CreateObject co;
		co.t = t;
		co.name = name;
		co.idx = newObject(t, name);

		dg(&co);

		if(co.idx >= stackSize(t))
			throwException(t, "You popped the object {} before it could be finished!", name);

		if(stackSize(t) > co.idx + 1)
			pop(t, stackSize(t) - co.idx - 1);

		newGlobal(t, name);
	}

	public void method(dchar[] name, NativeFunc f)
	{
		newFunction(t, f, this.name ~ cast(dchar)'.' ~ name);
		fielda(t, idx, name);
	}
}

/**
A utility structure for building up strings out of several pieces more efficiently than by just pushing
all the bits and concatenating.  This struct keeps an internal buffer so that strings are built up in
large chunks.

This struct uses the stack of a thread to hold its intermediate results, so if you perform any stack
manipulation to calls to this struct's functions, make sure your stack operations are balanced, or you
will mess up the string building.  Also, negative stack indices may change where they reference during
string building since the stack may grow, so be sure to use absolute (positive) indices where necessary.

A typical use looks something like this:

-----
auto buf = ex.StrBuffer(t);
buf.addString(someString);
buf.addChar(someChar);
// ...
auto strIdx = buf.finish();
// The stack is how it was before we created the buffer, except with the result string is on top.
-----
*/
public struct StrBuffer
{
	private MDThread* t;
	private size_t numPieces;
	private size_t pos;
	private dchar[512] data;

	/**
	Create an instance of this struct.  The struct is bound to a single thread.
	*/
	public static StrBuffer opCall(MDThread* t)
	{
		StrBuffer ret;
		ret.t = t;
		return ret;
	}

	/**
	Add a character to the internal buffer.
	*/
	public void addChar(dchar c)
	{
		if(pos >= data.length)
			flush();

		data[pos] = c;
		pos++;
	}

	/**
	Add a string to the internal buffer.
	*/
	public void addString(dchar[] s)
	{
		foreach(c; s)
			addChar(c);
	}

	/**
	Add the value on top of the stack to the buffer.  This is the only function that breaks the
	rule of leaving the stack balanced.  For this function to work, you must have exactly one
	value on top of the stack, and it must be a string or a char.
	*/
	public void addTop()
	{
		if(isString(t, -1))
		{
			auto s = getString(t, -1);

			if(s.length <= (data.length - pos))
			{
				data[pos .. pos + s.length] = s[];
				pos += s.length;
				pop(t);
			}
			else
			{
				if(pos != 0)
				{
					flush();
					insert(t, -2);
				}

				incPieces();
			}
		}
		else if(isChar(t, -1))
		{
			auto c = getChar(t, -1);
			pop(t);
			addChar(c);
		}
		else
		{
			pushTypeString(t, -1);
			throwException(t, "Trying to add a '{}' to a StrBuffer", getString(t, -1));
		}
	}

	/**
	A convenience function for hooking up to the Tango IO and formatting facilities.  You can pass
	"&buf._sink" to many Tango functions that expect a _sink function for string data.
	*/
	public uint sink(dchar[] s)
	{
		addString(s);
		return s.length;
	}

	/**
	Indicate that the string building is complete.  This function will leave just the finished string
	on top of the stack.  The StrBuffer will also be in a state to build a new string if you so desire.
	*/
	public nint finish()
	{
		flush();

		auto num = numPieces;
		numPieces = 0;
		return cat(t, num);
	}

	private void flush()
	{
		if(pos == 0)
			return;

		pushString(t, data[0 .. pos]);
		pos = 0;

		incPieces();
	}

	private void incPieces()
	{
		numPieces++;

		if(numPieces > 50)
		{
			cat(t, numPieces);
			numPieces = 1;
		}
	}
}

public void checkAnyParam(MDThread* t, nint index)
{
	
}

public T* checkObjParam(T, bool strict = true)(MDThread* t, nint index, dchar[] name)
{
	checkObjParam!(strict)(t, index, name);
	return getMembers!(T)(t, index);
}

public void checkObjParam(bool strict = true)(MDThread* t, nint index, dchar[] name)
{
	if(index < 0)
		index = stackSize(t) + index;

	if(!isObject(t, index))
	{
		if(index == 0)
			throwException(t, "'this' is not an object");
		else
			throwException(t, "Parameter {} is not an object", index);
	}

	lookup(t, name);

	if(!as(t, index, -1) || (strict ? opis(t, index, -1) : false))
	{
		if(index == 0)
			throwException(t, "'this' is not an instance of {}", name);
		else
			throwException(t, "Parameter {} is not an instance of {}", name);
	}

	pop(t);
}

public T* getMembers(T)(MDThread* t, nint index)
{
	auto ret = getExtraBytes(t, index);
	assert(ret.length == T.sizeof);
	return cast(T*)ret.ptr;
}

/**
Look up some value using a name that looks like a chain of dot-separated identifiers (like a MiniD expression).
The _name must follow the regular expression "\w[\w\d]*(\.\w[\w\d]*)*".  No spaces are allowed.  The looked-up
value is left at the top of the stack.

This functions behaves just as though you were evaluating this expression in MiniD.  Global _lookup and opField
metamethods are respected.

-----
auto slot = ex.lookup(t, "time.Timer");
pushNull(t);
methodCall(t, slot, "clone", 1);
// We now have an instance of time.Timer on top of the stack.
-----

If you want to set a long _name, such as "foo.bar.baz.quux", you just _lookup everything but the last _name and
use 'fielda' to set it:

-----
auto slot = ex.lookup(t, "foo.bar.baz");
pushInt(t, 5);
fielda(t, slot, "quux");
-----

Params:
	name = The dot-separated _name of the value to look up.

Returns:
	The stack index of the looked-up value.
*/
public nint lookup(MDThread* t, dchar[] name)
{
	validateName(t, name);

	bool isFirst = true;
	nint idx = void;

	foreach(n; name.delimiters("."d))
	{
		if(isFirst)
		{
			isFirst = false;
			idx = pushGlobal(t, n);
		}
		else
			field(t, -1, n);
	}

	auto size = stackSize(t);

	if(size > idx + 1)
		insertAndPop(t, idx);

	return idx;
}

/**
Very similar to lookup, this function trades a bit of code bloat for the benefits of checking that the name is valid
at compile time and of being faster.  The name is validated and translated directly into a series of API calls, meaning
this function will be likely to be inlined.  The usage is exactly the same as lookup, except the name is now a template
parameter instead of a normal parameter.

Returns:
	The stack index of the looked-up value.
*/
public nint lookupCT(char[] name)(MDThread* t)
{
	mixin(NameToAPICalls!(name));
	return idx;
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

// Check the format of a name of the form "\w[\w\d]*(\.\w[\w\d]*)*".  Could we use an actual regex for this?  I guess,
// but then we'd have to create a regex object, and either it'd have to be static and access to it would have to be
// synchronized, or it'd have to be created in the VM object which is just dumb.
private void validateName(MDThread* t, dchar[] name)
{
	void wrongFormat()
	{
		throwException(t, "The name '{}' is not formatted correctly", name);
	}

	if(name.length == 0)
		throwException(t, "Cannot use an empty string for a name");

	size_t idx = 0;

	void ident()
	{
		if(idx >= name.length)
			wrongFormat();

		if(!isalpha(name[idx]) && name[idx] != '_')
			wrongFormat();

		idx++;

		while(idx < name.length && (isalnum(name[idx]) || name[idx] == '_'))
			idx++;
	}

	ident();

	while(idx < name.length)
	{
		if(name[idx++] != '.')
			wrongFormat();

		ident();
	}
}

private template IsIdentBeginChar(char c)
{
	const IsIdentBeginChar = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

private template IsIdentChar(char c)
{
	const IsIdentChar = IsIdentBeginChar!(c) || (c >= '0' && c <= '9');
}

private template ValidateNameCTImpl(char[] name, size_t start = 0)
{
	private template IdentLoop(size_t idx)
	{
		static if(idx < name.length && IsIdentChar!(name[idx]))
			const IdentLoop = IdentLoop!(idx + 1);
		else
			const IdentLoop = idx;
	}

	static if(start >= name.length || !IsIdentBeginChar!(name[start]))
		static assert(false, "The name '" ~ name ~ "' is not formatted correctly");

	const idx = IdentLoop!(start);

	static if(idx >= name.length)
		alias Tuple!(name[start .. $]) ret;
	else
	{
		static if(name[idx] != '.')
			static assert(false, "The name '" ~ name ~ "' is not formatted correctly");

		alias Tuple!(name[start .. idx], ValidateNameCTImpl!(name, idx + 1).ret) ret;
	}
}

private template ValidateNameCT(char[] name)
{
	static if(name.length == 0)
		static assert(false, "Cannot use an empty string for a name");

	alias ValidateNameCTImpl!(name).ret ValidateNameCT;
}

template NameToAPICalls_toCalls(Names...)
{
	static if(Names.length == 0)
		const char[] NameToAPICalls_toCalls = "";
	else
		const char[] NameToAPICalls_toCalls = "field(t, -1, \"" ~ Names[0] ~ "\");\n" ~ NameToAPICalls_toCalls!(Names[1 .. $]);
}

private template NameToAPICallsImpl(char[] name)
{
	alias ValidateNameCT!(name) t;
	const ret = "auto idx = pushGlobal(t, \"" ~ t[0] ~ "\");\n" ~ NameToAPICalls_toCalls!(t[1 .. $]) ~ (t.length > 1 ? "insertAndPop(t, idx);\n" : "");
}

private template NameToAPICalls(char[] name)
{
	const NameToAPICalls = NameToAPICallsImpl!(name).ret;
}