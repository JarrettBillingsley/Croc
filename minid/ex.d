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
import Utf = tango.text.convert.Utf;

import minid.compiler;
import minid.interpreter;
import minid.types;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

/**
WHAT

You didn't see this.  Move along.  $(LT)__$(LT)
*/
public struct CreateClass
{
	private MDThread* t;
	private char[] name;
	private word idx;

	public static void opCall(MDThread* t, char[] name, void delegate(CreateClass*) dg)
	{
		CreateClass co;
		co.t = t;
		co.name = name;
		co.idx = newClass(t, name);

		dg(&co);

		if(co.idx >= stackSize(t))
			throwException(t, "You popped the class {} before it could be finished!", name);

		if(stackSize(t) > co.idx + 1)
			setStackSize(t, co.idx + 1);
	}
	
	public static void opCall(MDThread* t, char[] name, char[] base, void delegate(CreateClass*) dg)
	{
		CreateClass co;
		co.t = t;
		co.name = name;

		co.idx = lookup(t, base);
		newClass(t, -1, name);
		swap(t);
		pop(t);

		dg(&co);

		if(co.idx >= stackSize(t))
			throwException(t, "You popped the class {} before it could be finished!", name);

		if(stackSize(t) > co.idx + 1)
			setStackSize(t, co.idx + 1);
	}

	public void method(char[] name, NativeFunc f, uword numUpvals = 0)
	{
		newFunction(t, f, this.name ~ '.' ~ name, numUpvals);
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
auto buf = StrBuffer(t);
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
	private uword numPieces;
	private uword pos;
	private char[512] data;

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
		char[4] outbuf = void;
		uint ate = 0;
		auto s = Utf.toString((&c)[0 .. 1], outbuf, &ate);

		if(pos + s.length - 1 >= data.length)
			flush();

		data[pos .. pos + s.length] = s[];
		pos += s.length;
	}

	/**
	Add a string to the internal buffer.
	*/
	public void addString(char[] s)
	{
		foreach(dchar c; s)
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
	public uint sink(char[] s)
	{
		addString(s);
		return s.length;
	}

	/**
	Indicate that the string building is complete.  This function will leave just the finished string
	on top of the stack.  The StrBuffer will also be in a state to build a new string if you so desire.
	*/
	public word finish()
	{
		flush();

		auto num = numPieces;
		numPieces = 0;

		if(num == 0)
			return pushString(t, "");
		else
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

/**
Check that there is any parameter at the given index.  You can use this to ensure that a minimum number
of parameters were passed to your function.
*/
public void checkAnyParam(MDThread* t, word index)
{
	if(!isValidIndex(t, index))
		throwException(t, "Too few parameters (expected at least {}, got {})", index, stackSize(t) - 1);
}

/**
These all check that a parameter of the given type was passed at the given index, and return the value
of that parameter.  Very simple.
*/
public bool checkBoolParam(MDThread* t, word index)
{
	checkAnyParam(t, index);

	if(!isBool(t, index))
		paramTypeError(t, index, "bool");

	return getBool(t, index);
}

/// ditto
public mdint checkIntParam(MDThread* t, word index)
{
	checkAnyParam(t, index);

	if(!isInt(t, index))
		paramTypeError(t, index, "int");

	return getInt(t, index);
}

/// ditto
public mdfloat checkFloatParam(MDThread* t, word index)
{
	checkAnyParam(t, index);

	if(!isFloat(t, index))
		paramTypeError(t, index, "float");

	return getFloat(t, index);
}

/// ditto
public dchar checkCharParam(MDThread* t, word index)
{
	checkAnyParam(t, index);

	if(!isChar(t, index))
		paramTypeError(t, index, "char");

	return getChar(t, index);
}

/// ditto
public char[] checkStringParam(MDThread* t, word index)
{
	checkAnyParam(t, index);

	if(!isString(t, index))
		paramTypeError(t, index, "string");

	return getString(t, index);
}

/**
Checks that the parameter at the given index is an int or a float, and returns the value as a float,
casting ints to floats as necessary.
*/
public mdfloat checkNumParam(MDThread* t, word index)
{
	checkAnyParam(t, index);

	if(isInt(t, index))
		return cast(mdfloat)getInt(t, index);
	else if(isFloat(t, index))
		return getFloat(t, index);

	paramTypeError(t, index, "int|float");
	assert(false);
}

/**
Checks that the parameter at the given index is an instance.
*/
public void checkInstParam()(MDThread* t, word index)
{
	checkAnyParam(t, index);

	if(!isInstance(t, index))
		paramTypeError(t, index, "instance");
}

/**
Checks that the parameter at the given index is an instance of the class given by name.  name must
be a dotted-identifier name suitable for passing into lookup().

Params:
	index = The stack index of the parameter to check.
	name = The name of the class from which the given parameter must be derived.
*/
public void checkInstParam()(MDThread* t, word index, char[] name)
{
	index = absIndex(t, index);
	checkInstParam(t, index);

	lookup(t, name);

	if(!as(t, index, -1))
	{
		pushTypeString(t, index);

		if(index == 0)
			throwException(t, "Expected instance of class {} for 'this', not {}", name, getString(t, -1));
		else
			throwException(t, "Expected instance of class {} for parameter {}, not {}", name, index, getString(t, -1));
	}

	pop(t);
}

/**
Same as above, but also takes a template type parameter that should be a struct the same size as the
given instance's extra bytes.  Returns the extra bytes cast to a pointer to that struct type.
*/
public T* checkInstParam(T)(MDThread* t, word index, char[] name)
{
	checkInstParam(t, index, name);
	return getMembers!(T)(t, index);
}

/**
Checks that the parameter at the given index is of the given type.
*/
public void checkParam(MDThread* t, word index, MDValue.Type type)
{
	assert(type >= MDValue.Type.Null && type <= MDValue.Type.WeakRef, "invalid type");

	checkAnyParam(t, index);

	if(.type(t, index) != type)
		paramTypeError(t, index, MDValue.typeString(type));
}

/**
Throws an informative exception about the parameter at the given index, telling the parameter index ('this' for
parameter 0), the expected type, and the actual type.
*/
public void paramTypeError(MDThread* t, word index, char[] expected)
{
	pushTypeString(t, index);

	if(index == 0)
		throwException(t, "Expected type '{}' for 'this', not '{}'", expected, getString(t, -1));
	else
		throwException(t, "Expected type '{}' for parameter {}, not '{}'", expected, index, getString(t, -1));
}

/**
These all get an optional parameter of the given type at the given index.  If no parameter was passed to that
index or if 'null' was passed, 'def' is returned; otherwise, the passed parameter must match the given type
and its value is returned.  This is the same behavior as in MiniD.
*/
public bool optBoolParam(MDThread* t, word index, bool def)
{
	if(!isValidIndex(t, index) || isNull(t, index))
		return def;

	if(!isBool(t, index))
		paramTypeError(t, index, "bool");

	return getBool(t, index);
}

/// ditto
public mdint optIntParam(MDThread* t, word index, mdint def)
{
	if(!isValidIndex(t, index) || isNull(t, index))
		return def;

	if(!isInt(t, index))
		paramTypeError(t, index, "int");

	return getInt(t, index);
}

/// ditto
public mdfloat optFloatParam(MDThread* t, word index, mdfloat def)
{
	if(!isValidIndex(t, index) || isNull(t, index))
		return def;

	if(!isFloat(t, index))
		paramTypeError(t, index, "float");

	return getFloat(t, index);
}

/// ditto
public dchar optCharParam(MDThread* t, word index, dchar def)
{
	if(!isValidIndex(t, index) || isNull(t, index))
		return def;

	if(!isChar(t, index))
		paramTypeError(t, index, "char");

	return getChar(t, index);
}

/// ditto
public char[] optStringParam(MDThread* t, word index, char[] def)
{
	if(!isValidIndex(t, index) || isNull(t, index))
		return def;

	if(!isString(t, index))
		paramTypeError(t, index, "string");

	return getString(t, index);
}

/**
Just like the above, allowing ints or floats, and returns the value cast to a float, casting ints
to floats as necessary.
*/
public mdfloat optNumParam(MDThread* t, word index, mdfloat def)
{
	if(!isValidIndex(t, index) || isNull(t, index))
		return def;

	if(!isNum(t, index))
		paramTypeError(t, index, "int|float");

	return getNum(t, index);
}

/**
Similar to above, but works for any type.  Returns false to mean that no parameter was passed,
and true to mean that one was.
*/
public bool optParam(MDThread* t, word index, MDValue.Type type)
{
	if(!isValidIndex(t, index) || isNull(t, index))
		return false;

	if(.type(t, index) != type)
		paramTypeError(t, index, MDValue.typeString(type));

	return true;
}

/**
For the instance at the given index, gets the extra bytes and returns them cast to a pointer to the
given type.  Checks that the number of extra bytes is at least the size of the given type, but
this should not be used as a foolproof way of identifying the type of instances.
*/
public T* getMembers(T)(MDThread* t, word index)
{
	auto ret = getExtraBytes(t, index);

	if(ret.length < T.sizeof)
	{
		pushTypeString(t, index);
		throwException(t, "'{}' does not have enough extra bytes (expected at least {}, has {})", getString(t, -1), T.sizeof, ret.length);
	}

	return cast(T*)ret.ptr;
}

/**
Look up some value using a name that looks like a chain of dot-separated identifiers (like a MiniD expression).
The _name must follow the regular expression "\w[\w\d]*(\.\w[\w\d]*)*".  No spaces are allowed.  The looked-up
value is left at the top of the stack.

This functions behaves just as though you were evaluating this expression in MiniD.  Global _lookup and opField
metamethods are respected.

-----
auto slot = lookup(t, "time.Timer");
pushNull(t);
rawCall(t, slot, 1);
// We now have an instance of time.Timer on top of the stack.
-----

If you want to set a long _name, such as "foo.bar.baz.quux", you just _lookup everything but the last _name and
use 'fielda' to set it:

-----
auto slot = lookup(t, "foo.bar.baz");
pushInt(t, 5);
fielda(t, slot, "quux");
-----

Params:
	name = The dot-separated _name of the value to look up.

Returns:
	The stack index of the looked-up value.
*/
public word lookup(MDThread* t, char[] name)
{
	validateName(t, name);

	bool isFirst = true;
	word idx = void;

	foreach(n; name.delimiters("."))
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
public word lookupCT(char[] name)(MDThread* t)
{
	mixin(NameToAPICalls!(name));
	return idx;
}

/**
Pushes the variable that is stored in the registry with the given name onto the stack.  An error will be thrown if the variable
does not exist in the registry.

Returns:
	The stack index of the newly-pushed value.
*/
public word getRegistryVar(MDThread* t, char[] name)
{
	getRegistry(t);
	field(t, -1, name);
	insertAndPop(t, -2);
	return stackSize(t) - 1;
}

/**
Pops the value off the top of the stack and sets it into the given registry variable.
*/
public void setRegistryVar(MDThread* t, char[] name)
{
	getRegistry(t);
	swap(t);
	fielda(t, -2, name);
	pop(t);
}

/**
Similar to the _loadString function in the MiniD base library, this compiles some statements
into a function that takes variadic arguments and pushes that function onto the stack.

Params:
	code = The source _code of the function.  This should be one or more statements.
	customEnv = If true, expects the value on top of the stack to be a namespace which will be
		set as the environment of the new function.  The namespace will be replaced.  Defaults
		to false, in which case the current function's environment will be used.
	name = The _name to give the function.  Defaults to "<loaded by loadString>".
	
Returns:
	The stack index of the newly-compiled function.
*/
public word loadString(MDThread* t, char[] code, bool customEnv = false, char[] name = "<loaded by loadString>")
{
	if(customEnv)
	{
		if(!isNamespace(t, -1))
		{
			pushTypeString(t, -1);
			throwException(t, "loadString - Expected 'namespace' on the top of the stack for an environment, not '{}'", getString(t, -1));
		}
	}
	else
		pushEnvironment(t);

	{
		scope c = new Compiler(t);
		c.compileStatements(code, name);
	}

	swap(t);
	setFuncEnv(t, -2);

	return stackSize(t) - 1;
}

/**
This is a quick way to run some MiniD code.  Basically this just calls loadString and then runs
the resulting function with no parameters.  This function's parameters are the same as loadString's.
*/
public void runString(MDThread* t, char[] code, bool customEnv = false, char[] name = "<loaded by runString>")
{
	loadString(t, code, customEnv, name);
	pushNull(t);
	rawCall(t, -2, 0);
}

/**
Similar to the _eval function in the MiniD base library, this compiles an expression, evaluates it,
and leaves the result(s) on the stack.  

Params:
	code = The source _code of the expression.
	numReturns = How many return values you want from the expression.  Defaults to 1.  Works just like
		the _numReturns parameter of the call functions; -1 gets all return values.
	customEnv = If true, expects the value on top of the stack to be a namespace which will be
		used as the environment of the expression.  The namespace will be replaced.  Defaults
		to false, in which case the current function's environment will be used.
		
Returns:
	If numReturns >= 0, returns numReturns.  If numReturns == -1, returns how many values the expression
	returned.
*/
public uword eval(MDThread* t, char[] code, word numReturns = 1, bool customEnv = false)
{
	if(customEnv)
	{
		if(!isNamespace(t, -1))
		{
			pushTypeString(t, -1);
			throwException(t, "loadString - Expected 'namespace' on the top of the stack for an environment, not '{}'", getString(t, -1));
		}
	}
	else
		pushEnvironment(t);

	{
		scope c = new Compiler(t);
		c.compileExpression(code, "<loaded by eval>");
	}

	swap(t);
	setFuncEnv(t, -2);

	pushNull(t);
	return rawCall(t, -2, numReturns);
}

/**
This function abstracts away some of the boilerplate code that is usually associated with try-catch blocks
that handle MiniD exceptions in D code.  

This function will store the stack size of the given thread when it is called, before the try code is executed.
If an exception occurs, the stack will be restored to that size, the MiniD exception will be caught (with 
catchException), and the catch code will be called with the D exception object and the MiniD exception object's
stack index as parameters.  The catch block is expected to leave the stack balanced, that is, it should be the
same size upon exit as it was upon entry (an error will be thrown if this is not the case).  Lastly, the given
finally code, if any, will be executed as a finally block usually is.

This function is best used with anonymous delegates, like so:

-----
mdtry(t,
// try block
{
	// foo bar baz
},
// catch block
(MDException e, word mdEx)
{
	// deal with exception here
},
// finally block
{
	// cleanup, whatever
});
-----

It can be easy to forget that those blocks are actually delegates, and returning from them just returns from
the delegate instead of from the enclosing function.  Hey, don't look at me; it's D's fault for not having
AST macros ;)

If you just need a try-finally block, you don't need this function, and please don't call it with a null
catch_ parameter.  Just use a normal try-finally block in that case (or better yet, a scope(exit) block).

Params:
	try_ = The try code.
	catch_ The catch code.  It takes two parameters - the D exception object and the stack index of the caught
		MiniD exception object.
	finally_ = The optional finally code.
*/
public void mdtry(MDThread* t, void delegate() try_, void delegate(MDException, word) catch_, void delegate() finally_ = null)
{
	auto size = stackSize(t);

	try
		try_();
	catch(MDException e)
	{
		setStackSize(t, size);
		auto mdEx = catchException(t);
		catch_(e, mdEx);

		if(mdEx != stackSize(t) - 1)
			throwException(t, "mdtry - catch block is supposed to leave stack as it was before it was entered");

		pop(t);
	}
	finally
	{
		if(finally_)
			finally_();
	}
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

// Check the format of a name of the form "\w[\w\d]*(\.\w[\w\d]*)*".  Could we use an actual regex for this?  I guess,
// but then we'd have to create a regex object, and either it'd have to be static and access to it would have to be
// synchronized, or it'd have to be created in the VM object which is just dumb.
private void validateName(MDThread* t, char[] name)
{
	void wrongFormat()
	{
		throwException(t, "The name '{}' is not formatted correctly", name);
	}

	if(name.length == 0)
		throwException(t, "Cannot use an empty string for a name");

	uword idx = 0;

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

private template ValidateNameCTImpl(char[] name, uword start = 0)
{
	private template IdentLoop(uword idx)
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