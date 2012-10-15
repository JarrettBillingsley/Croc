/******************************************************************************
This module contains the "extension" API, which is a bunch of useful
functionality built on top of the "raw" API.

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

module croc.ex;

import tango.core.Tuple;
import tango.io.device.File;
import tango.stdc.ctype;
import tango.text.convert.Utf;
import tango.text.Util;

alias tango.text.convert.Utf.toString Utf_toString;

import croc.api_checks;
import croc.api_debug;
import croc.api_interpreter;
import croc.api_stack;
import croc.compiler;
import croc.serialization;
import croc.types;
import croc.utils;
import croc.vm;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

// ================================================================================================================================================
// Simplifying very common tasks

/**

*/
void throwNamedException(CrocThread* t, char[] exName, char[] fmt, ...)
{
	lookup(t, exName);
	pushNull(t);
	pushVFormat(t, fmt, _arguments, _argptr);
	rawCall(t, -3, 1);
	throwException(t);
}

/**
Import a module with the given name. Works just like the import statement in Croc. Pushes the
module's namespace onto the stack.

Params:
	name = The name of the module to be imported.

Returns:
	The stack index of the imported module's namespace.
*/
word importModule(CrocThread* t, char[] name)
{
	pushString(t, name);
	importModule(t, -1);
	insertAndPop(t, -2);
	return stackSize(t) - 1;
}

/**
Same as above, but uses a name on the stack rather than one provided as a parameter.

Params:
	name = The stack index of the string holding the name of the module to be imported.

Returns:
	The stack index of the imported module's namespace.
*/
word importModule(CrocThread* t, word name)
{
	mixin(FuncNameMix);

	name = absIndex(t, name);

	if(!isString(t, name))
	{
		pushTypeString(t, name);
		throwStdException(t, "TypeException", __FUNCTION__ ~ " - name must be a 'string', not a '{}'", getString(t, -1));
	}

	lookup(t, "modules.load");
	pushNull(t);
	dup(t, name);
	rawCall(t, -3, 1);

	assert(t.stack[t.stackIndex - 1].type == CrocValue.Type.Namespace);
	return stackSize(t) - 1;
}

/**
Same as importModule, but doesn't leave the module namespace on the stack.

Params:
	name = The name of the module to be imported.
*/
void importModuleNoNS(CrocThread* t, char[] name)
{
	pushString(t, name);
	importModule(t, -1);
	pop(t, 2);
}

/**
Same as above, but uses a name on the stack rather than one provided as a parameter.

Params:
	name = The stack index of the string holding the name of the module to be imported.
*/
void importModuleNoNS(CrocThread* t, word name)
{
	importModule(t, name);
	pop(t);
}

/**
*/
word importModuleFromString(CrocThread* t, char[] name, char[] src, char[] srcName = null)
{
	if(srcName is null)
		srcName = name;

	scope c = new Compiler(t);
	auto f = lookup(t, "modules.initModule");
	pushNull(t);
	char[] modName;
	c.compileModule(src, srcName, modName);

	if(name != modName)
		throwStdException(t, "ImportException", "Import name ({}) does not match name given in module statement ({})", name, modName);

	pushString(t, name);
	rawCall(t, f, 0);
	return importModule(t, name);
}

/**
*/
void importModuleFromStringNoNS(CrocThread* t, char[] name, char[] src, char[] srcName = null)
{
	importModuleFromString(t, name, src, srcName);
	pop(t);
}

/**
A utility structure for building up strings out of several pieces more efficiently than by just pushing
all the bits and concatenating. This struct keeps an internal buffer so that strings are built up in
large chunks.

This struct uses the stack of a thread to hold its intermediate results, so if you perform any stack
manipulation to calls to this struct's functions, make sure your stack operations are balanced, or you
will mess up the string building. Also, negative stack indices may change where they reference during
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
struct StrBuffer
{
private:
	CrocThread* t;
	uword numPieces;
	uword pos;
	char[512] data;

public:
	/**
	Create an instance of this struct. The struct is bound to a single thread.
	*/
	static StrBuffer opCall(CrocThread* t)
	{
		StrBuffer ret;
		ret.t = t;
		return ret;
	}

	/**
	Add a character to the internal buffer.
	*/
	void addChar(dchar c)
	{
		char[4] outbuf = void;
		uint ate = 0;
		auto s = Utf_toString((&c)[0 .. 1], outbuf, &ate);

		if(pos + s.length - 1 >= data.length)
			flush();

		data[pos .. pos + s.length] = s[];
		pos += s.length;
	}

	/**
	Add a string to the internal buffer.
	*/
	void addString(char[] s)
	{
		// this code doesn't validate the data, but it'll get validated eventually
		if(s.length <= (data.length - pos))
		{
			data[pos .. pos + s.length] = s[];
			pos += s.length;
		}
		else
		{
			if(pos != 0)
				flush();

			pushString(t, s);
			incPieces();
		}
	}

	/**
	Add the value on top of the stack to the buffer. This is the only function that breaks the
	rule of leaving the stack balanced. For this function to work, you must have exactly one
	value on top of the stack, and it must be a string or a char.
	*/
	void addTop()
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
			throwStdException(t, "TypeException", "Trying to add a '{}' to a StrBuffer", getString(t, -1));
		}
	}

	/**
	A convenience function for hooking up to the Tango IO and formatting facilities. You can pass
	"&buf._sink" to many Tango functions that expect a _sink function for string data.
	*/
	uint sink(char[] s)
	{
		addString(s);
		return s.length;
	}

	/**
	Indicate that the string building is complete. This function will leave just the finished string
	on top of the stack. The StrBuffer will also be in a state to build a new string if you so desire.
	*/
	word finish()
	{
		flush();

		auto num = numPieces;
		numPieces = 0;

		if(num == 0)
			return pushString(t, "");
		else
			return cat(t, num);
	}

private:
	void flush()
	{
		if(pos == 0)
			return;

		pushString(t, data[0 .. pos]);
		pos = 0;

		incPieces();
	}

	void incPieces()
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
Look up some value using a name that looks like a chain of dot-separated identifiers (like a Croc expression).
The _name must follow the regular expression "\w[\w\d]*(\.\w[\w\d]*)*". No spaces are allowed. The looked-up
value is left at the top of the stack.

This functions behaves just as though you were evaluating this expression in Croc. Global _lookup and opField
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
word lookup(CrocThread* t, char[] name)
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
at compile time and of being faster. The name is validated and translated directly into a series of API calls, meaning
this function will be likely to be inlined. The usage is exactly the same as lookup, except the name is now a template
parameter instead of a normal parameter.

Returns:
	The stack index of the looked-up value.
*/
word lookupCT(char[] name)(CrocThread* t)
{
	mixin(NameToAPICalls!(name));
	return idx;
}

/**
Pushes the variable that is stored in the registry with the given name onto the stack. An error will be thrown if the variable
does not exist in the registry.

Returns:
	The stack index of the newly-pushed value.
*/
word getRegistryVar(CrocThread* t, char[] name)
{
	getRegistry(t);
	field(t, -1, name);
	insertAndPop(t, -2);
	return stackSize(t) - 1;
}

/**
Pops the value off the top of the stack and sets it into the given registry variable.
*/
void setRegistryVar(CrocThread* t, char[] name)
{
	getRegistry(t);
	swap(t);
	fielda(t, -2, name);
	pop(t);
}

/**
Similar to the _loadString function in the Croc base library, this compiles some statements
into a function that takes variadic arguments and pushes that function onto the stack.

Params:
	code = The source _code of the function. This should be one or more statements.
	customEnv = If true, expects the value on top of the stack to be a namespace which will be
		set as the environment of the new function. The namespace will be replaced. Defaults
		to false, in which case the current function's environment will be used.
	name = The _name to give the function. Defaults to "<loaded by loadString>".

Returns:
	The stack index of the newly-compiled function.
*/
word loadString(CrocThread* t, char[] code, bool customEnv = false, char[] name = "<loaded by loadString>")
{
	if(customEnv)
	{
		if(!isNamespace(t, -1))
		{
			pushTypeString(t, -1);
			throwStdException(t, "TypeException", "loadString - Expected 'namespace' on the top of the stack for an environment, not '{}'", getString(t, -1));
		}
	}
	else
		pushEnvironment(t);

	{
		scope c = new Compiler(t);
		c.compileStatements(code, name);
	}

	swap(t);
	newFunctionWithEnv(t, -2);
	insertAndPop(t, -2);

	return stackSize(t) - 1;
}

/**
This is a quick way to run some Croc code. Basically this just calls loadString and then runs
the resulting function with no parameters. This function's parameters are the same as loadString's.
*/
void runString(CrocThread* t, char[] code, bool customEnv = false, char[] name = "<loaded by runString>")
{
	loadString(t, code, customEnv, name);
	pushNull(t);
	rawCall(t, -2, 0);
}

/**
Similar to the _eval function in the Croc base library, this compiles an expression, evaluates it,
and leaves the result(s) on the stack.

Params:
	code = The source _code of the expression.
	numReturns = How many return values you want from the expression. Defaults to 1. Works just like
		the _numReturns parameter of the call functions; -1 gets all return values.
	customEnv = If true, expects the value on top of the stack to be a namespace which will be
		used as the environment of the expression. The namespace will be replaced. Defaults
		to false, in which case the current function's environment will be used.

Returns:
	If numReturns >= 0, returns numReturns. If numReturns == -1, returns how many values the expression
	returned.
*/
uword eval(CrocThread* t, char[] code, word numReturns = 1, bool customEnv = false)
{
	if(customEnv)
	{
		if(!isNamespace(t, -1))
		{
			pushTypeString(t, -1);
			throwStdException(t, "TypeException", "loadString - Expected 'namespace' on the top of the stack for an environment, not '{}'", getString(t, -1));
		}
	}
	else
		pushEnvironment(t);

	{
		scope c = new Compiler(t);
		c.compileExpression(code, "<loaded by eval>");
	}

	swap(t);
	newFunctionWithEnv(t, -2);
	insertAndPop(t, -2);

	pushNull(t);
	return rawCall(t, -2, numReturns);
}

/**
Imports a module or file and runs any main() function in it.

Params:
	filename = The name of the file or module to load. If it's a path to a file, it must end in .croc or .croco.
		It will be compiled or deserialized as necessary. If it's a module name, it must be in dotted form and
		not end in croc or croco. It will be imported as normal.

	numParams = How many arguments you have to pass to the main() function. If you want to pass params, they
		must be on top of the stack when you call this function.

Example:
-----
// We want to load "foo.bar.baz" and pass it "a" and "b" as params.
// Push the params first.
pushString(t, "a");
pushString(t, "b");
// Run the file and tell it we have two params.
runFile(t, "foo.bar.baz", 2);
-----

-----
// Just showing how you'd execute a module by filename instead of module name.
runFile(t, "foo/bar/baz.croc");
-----
*/
void runFile(CrocThread* t, char[] filename, uword numParams = 0)
{
	mixin(apiCheckNumParams!("numParams"));

	char[] modName;

	if(filename.endsWith(".croc"))
	{
		scope c = new Compiler(t);
		c.compileModule(filename, modName);
	}
	else
	{
		scope f = safeCode(t, "exceptions.IOException", new File(filename, File.ReadExisting));
		deserializeModule(t, modName, f);
	}

	lookup(t, "modules.initModule");
	pushNull(t);
	moveToTop(t, -3);
	pushString(t, modName);
	rawCall(t, -4, 1);
	commonRun(t, numParams, modName);
}

/**
*/
void runModule(CrocThread* t, char[] moduleName, uword numParams = 0)
{
	mixin(apiCheckNumParams!("numParams"));

	importModule(t, moduleName);
	commonRun(t, numParams, moduleName);
}

/**
An odd sort of protective function. You can use this function to wrap a call to a library function etc. which
could throw an exception, but when you don't want to have to bother with catching the exception yourself. Useful
for writing native Croc libraries.

Say you had a function which opened a file:

-----
File f = OpenFile("filename");
-----

Say this function could throw an exception if it failed. Since the interpreter can only catch (and make meaningful
stack traces about) exceptions which derive from CrocException, any exceptions that this throws would just percolate
up out of the interpreter stack. You could catch the exception yourself, but that's kind of tedious, especially when
you call a lot of native functions.

Instead, you can wrap the call to this unsafe function with a call to safeCode().

-----
File f = safeCode(t, OpenFile("filename"));
-----

What safeCode() does is it tries to execute the code it is passed. If it succeeds, it simply returns any value that
the code returns. If it throws an exception derived from CrocException, it rethrows the exception. And if it throws
an exception that derives from Exception, it throws a new CrocException with the original exception's message as the
message.

If you want to wrap statements, you can use a delegate literal:

-----
safeCode(t,
{
	stmt1;
	stmt2;
	stmt3;
}());
-----

Be sure to include those empty parens after the delegate literal, due to the way D converts the expression to a lazy
parameter. If you don't put the parens there, it will never actually call the delegate.

safeCode() is templated to allow any return value.

Params:
	code = The code to be executed. This is a lazy parameter, so it's not actually executed until inside the call to
		safeCode.

Returns:
	Whatever the code parameter returns.
*/
T safeCode(T)(CrocThread* t, lazy T code)
{
	try
		return code;
	catch(CrocException e)
		throw e;
	catch(Exception e)
		throwStdException(t, "Exception", "{}", e);

	assert(false);
}

/**
ditto
*/
T safeCode(T)(CrocThread* t, char[] exName, lazy T code)
{
	try
		return code;
	catch(CrocException e)
		throw e;
	catch(Exception e)
		throwNamedException(t, exName, "{}", e);

	assert(false);
}

/**
This function abstracts away some of the boilerplate code that is usually associated with try-catch blocks
that handle Croc exceptions in D code.

This function will store the stack size of the given thread when it is called, before the try code is executed.
If an exception occurs, the stack will be restored to that size, the Croc exception will be caught (with
catchException), and the catch code will be called with the D exception object and the Croc exception object's
stack index as parameters. The catch block is expected to leave the stack balanced, that is, it should be the
same size upon exit as it was upon entry (an error will be thrown if this is not the case). Lastly, the given
finally code, if any, will be executed as a finally block usually is.

This function is best used with anonymous delegates, like so:

-----
croctry(t,
// try block
{
	// foo bar baz
},
// catch block
(CrocException e, word crocEx)
{
	// deal with exception here
},
// finally block
{
	// cleanup, whatever
});
-----

It can be easy to forget that those blocks are actually delegates, and returning from them just returns from
the delegate instead of from the enclosing function. Hey, don't look at me; it's D's fault for not having
AST macros ;$(RPAREN)

If you just need a try-finally block, you don't need this function, and please don't call it with a null
catch_ parameter. Just use a normal try-finally block in that case (or better yet, a scope(exit) block).

Params:
	try_ = The try code.
	catch_ = The catch code. It takes two parameters - the D exception object and the stack index of the caught
		Croc exception object.
	finally_ = The optional finally code.
*/
void croctry(CrocThread* t, void delegate() try_, void delegate(CrocException, word) catch_, void delegate() finally_ = null)
{
	auto size = stackSize(t);

	try
		try_();
	catch(CrocException e)
	{
		setStackSize(t, size);
		auto crocEx = catchException(t);
		catch_(e, crocEx);

		if(crocEx != stackSize(t) - 1)
			throwStdException(t, "ApiError", "croctry - catch block is supposed to leave stack as it was before it was entered");

		pop(t);
	}
	finally
	{
		if(finally_)
			finally_();
	}
}

/**
A useful wrapper for code where you want to ensure that the stack is balanced, that is, it is the same size after
some set of operations as before it. Having a balanced stack is more than just good practice - it prevents stack
overflows and underflows.

You can also use this function when your code requires that the stack be a certain number of slots larger or smaller
after some stack operations - for instance, a function which always returns two values, regardless of multiple
execution paths.

If the stack size is not correct after running the code, an exception will be thrown in the passed-in thread.

Params:
	diff = How many more (or fewer) items there should be on the stack after running the code. If 0, it means that
		the stack size after running the code should be exactly as it was before (there is an overload for this common
		case below). Positive numbers mean the stack should be bigger, and negative numbers mean it should be smaller.
	dg = The code to run.

Examples:

-----
// check that the stack is two bigger after the code than before
stackCheck(t, 2,
{
	pushNull(t);
	pushInt(t, 5);
}); // it is indeed 2 slots bigger, so it succeeds.

// check that the stack shrinks by 1 slot
stackCheck(t, -1,
{
	pushString(t, "foobar");
}); // oh noes, it's 1 slot bigger instead - throws an exception.
-----
*/
void stackCheck(CrocThread* t, word diff, void delegate() dg)
{
	auto s = stackSize(t);
	dg();

	if((stackSize(t) - s) != diff)
		throwStdException(t, "ApiError", "Stack is not balanced! Expected it to change by {}, changed by {} instead", diff, stackSize(t) - s);
}

/**
An overload of the above which simply calls it with a difference of 0 (i.e. the stack is completely balanced).
This is the most common case.
*/
void stackCheck(CrocThread* t, void delegate() dg)
{
	stackCheck(t, 0, dg);
}

/**
Wraps the allocMem API. Allocates an array of the given type with the given length.
You'll have to explicitly specify the type of the array.

-----
auto arr = allocArray!(int)(t, 10); // arr is an int[] of length 10
-----

The array returned by this function should not have its length set or be appended to (~=).

Params:
	length = The length, in items, of the array to allocate.

Returns:
	The new array.
*/
T[] allocArray(T)(CrocThread* t, uword length)
{
	return cast(T[])allocMem(t, length * T.sizeof);
}

/**
Wraps the resizeMem API. Resizes an array to the new length. Use this instead of using .length on
the array. $(B Only call this on arrays which have been allocated by the Croc allocator.)

Calling this function on a 0-length array is legal and will allocate a new array. Resizing an existing array to 0
is legal and will deallocate the array.

The array returned by this function through the arr parameter should not have its length set or be appended to (~=).

-----
resizeArray(t, arr, 4); // arr.length is now 4
-----

Params:
	arr = A reference to the array you want to resize. This is a reference so that the original array
		reference that you pass in is updated. This can be a 0-length array.

	length = The length, in items, of the new size of the array.
*/
void resizeArray(T)(CrocThread* t, ref T[] arr, uword length)
{
	auto tmp = cast(void[])arr;
	resizeMem(t, tmp, length * T.sizeof);
	arr = cast(T[])tmp;
}

/**
Wraps the dupMem API. Duplicates an array. This is safe to call on arrays that were not allocated by the Croc
allocator. The new array will be the same length and contain the same data as the old array.

The array returned by this function should not have its length set or be appended to (~=).

-----
auto newArr = dupArray(t, arr); // newArr has the same data as arr
-----

Params:
	arr = The array to duplicate. This is not required to have been allocated by the Croc allocator.
*/
T[] dupArray(T)(CrocThread* t, T[] arr)
{
	return cast(T[])dupMem(t, arr);
}

/**
Wraps the freeMem API. Frees an array. $(B Only call this on arrays which have been allocated by the Croc allocator.)
Freeing a 0-length array is legal.

-----
freeArray(t, arr);
freeArray(t, newArr);
-----

Params:
	arr = A reference to the array you want to free. This is a reference so that the original array
		reference that you pass in is updated. This can be a 0-length array.
*/
void freeArray(T)(CrocThread* t, ref T[] arr)
{
	auto tmp = cast(void[])arr;
	freeMem(t, tmp);
	arr = null;
}

alias void delegate(Object) DisposeEvt;
static extern(C) void rt_attachDisposeEvent(Object obj, DisposeEvt evt);
static extern(C) void rt_detachDisposeEvent(Object obj, DisposeEvt evt);

/**
A class that makes it possible to automatically remove references to Croc objects. You should create a $(B SCOPE) instance
of this class, which you can then use to create references to Croc objects. This class is not itself marked scope so that
you can pass references to it around, but you should still $(B ALWAYS) create instances of it as scope.

By using the reference objects that this manager creates, you can be sure that any Croc objects you reference using it
will be dereferenced by the time the instance of RefManager goes out of scope.
*/
class RefManager
{
	/**
	An actual reference object. This is basically an object-oriented wrapper around a Croc reference identifier. You
	don't create instances of this directly; see $(D RefManager.create).
	*/
	static class Ref
	{
	private:
		CrocVM* vm;
		ulong r;

		this(CrocVM* vm, ulong r)
		{
			this.vm = vm;
			this.r = r;
		}

		~this()
		{
			remove();
		}

	public:

		/**
		Removes the reference using $(D croc.interpreter.removeRef). You can call this manually, or it will be called
		automatically when this object is collected or when its owning manager leaves scope.
		*/
		void remove()
		{
			if(r == ulong.max)
				return;

			removeRef(currentThread(vm), r);
			r = ulong.max;
		}

		/**
		Push the reference using $(D croc.interpreter.pushRef). It is pushed onto the current thread of the VM in which
		it was created.

		Returns:
			The stack index of the object that was pushed.
		*/
		word push()
		{
			return pushRef(currentThread(vm), r);
		}
 	}

private:
	const uword Mask = cast(uword)0xDEADBEEF_DEADBEEF;
	bool[uword] mRefs;

	~this()
	{
		foreach(rx, _; mRefs)
		{
			auto r = cast(Ref)cast(void*)(rx ^ Mask);
			rt_detachDisposeEvent(r, &removeHook);
			r.remove();
		}
	}

public:
	/**
	Create a reference object to refer to the object at slot idx in thread t using $(D croc.interpreter.createRef). The
	given thread's VM is associated with the reference object.

	Returns:
		A new reference object.
	*/
	Ref create(CrocThread* t, word idx)
	{
		auto ret = new Ref(getVM(t), createRef(t, idx));
		mRefs[(cast(uword)cast(void*)ret) ^ Mask] = true;
		rt_attachDisposeEvent(ret, &removeHook);
		return ret;
	}

private:
	void removeHook(Object o)
	{
		auto r = cast(Ref)o;
		assert(r !is null);
		rt_detachDisposeEvent(r, &removeHook);
		mRefs.remove((cast(uword)cast(void*)r) ^ Mask);
	}
}

// ================================================================================================================================================
// Parameter checking

/**
Check that there is any parameter at the given index. You can use this to ensure that a minimum number
of parameters were passed to your function.
*/
void checkAnyParam(CrocThread* t, word index)
{
	if(!isValidIndex(t, index))
		throwStdException(t, "ParamException", "Too few parameters (expected at least {}, got {})", index, stackSize(t) - 1);
}

/**
These all check that a parameter of the given type was passed at the given index, and return the value
of that parameter. Very simple.
*/
bool checkBoolParam(CrocThread* t, word index)
{
	checkAnyParam(t, index);

	if(!isBool(t, index))
		paramTypeError(t, index, "bool");

	return getBool(t, index);
}

/// ditto
crocint checkIntParam(CrocThread* t, word index)
{
	checkAnyParam(t, index);

	if(!isInt(t, index))
		paramTypeError(t, index, "int");

	return getInt(t, index);
}

/// ditto
crocfloat checkFloatParam(CrocThread* t, word index)
{
	checkAnyParam(t, index);

	if(!isFloat(t, index))
		paramTypeError(t, index, "float");

	return getFloat(t, index);
}

/// ditto
dchar checkCharParam(CrocThread* t, word index)
{
	checkAnyParam(t, index);

	if(!isChar(t, index))
		paramTypeError(t, index, "char");

	return getChar(t, index);
}

/// ditto
char[] checkStringParam(CrocThread* t, word index)
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
crocfloat checkNumParam(CrocThread* t, word index)
{
	checkAnyParam(t, index);

	if(isInt(t, index))
		return cast(crocfloat)getInt(t, index);
	else if(isFloat(t, index))
		return getFloat(t, index);

	paramTypeError(t, index, "int|float");
	assert(false);
}

/**
Checks that the parameter at the given index is an instance.
*/
void checkInstParam(CrocThread* t, word index)
{
	checkAnyParam(t, index);

	if(!isInstance(t, index))
		paramTypeError(t, index, "instance");
}

/**
Checks that the parameter at the given index is an instance of the class given by name. name must
be a dotted-identifier name suitable for passing into lookup().

Params:
	index = The stack index of the parameter to check.
	name = The name of the class from which the given parameter must be derived.
*/
void checkInstParam(CrocThread* t, word index, char[] name)
{
	index = absIndex(t, index);
	checkInstParam(t, index);

	lookup(t, name);

	if(!as(t, index, -1))
	{
		pushTypeString(t, index);

		if(index == 0)
			throwStdException(t, "TypeException", "Expected instance of class {} for 'this', not {}", name, getString(t, -1));
		else
			throwStdException(t, "TypeException", "Expected instance of class {} for parameter {}, not {}", name, index, getString(t, -1));
	}

	pop(t);
}

/**
Checks that the parameter at the given index is an instance of the class given by the reference.

Params:
	index = The stack index of the parameter to check.
	classRef = Reference to the class object.
*/

void checkInstParamRef(CrocThread* t, word index, ulong classRef)
{
	index = absIndex(t, index);
	checkInstParam(t, index);

	pushRef(t, classRef);

	if(!as(t, index, -1))
	{
		auto name = className(t, -1);
		pushTypeString(t, index);

		if(index == 0)
			throwStdException(t, "TypeException", "Expected instance of class {} for 'this', not {}", name, getString(t, -1));
		else
			throwStdException(t, "TypeException", "Expected instance of class {} for parameter {}, not {}", name, index, getString(t, -1));
	}

	pop(t);
}

/**
Checks that the parameter at the given index is an instance of the class in the second index.

Params:
	index = The stack index of the parameter to check.
	classIndex = The stack index of the class against which the instance should be tested.
*/
void checkInstParamSlot(CrocThread* t, word index, word classIndex)
{
	checkInstParam(t, index);

	if(!as(t, index, classIndex))
	{
		auto name = className(t, classIndex);
		pushTypeString(t, index);

		if(index == 0)
			throwStdException(t, "TypeException", "Expected instance of class {} for 'this', not {}", name, getString(t, -1));
		else
			throwStdException(t, "TypeException", "Expected instance of class {} for parameter {}, not {}", name, index, getString(t, -1));
	}
}

/**
Checks that the parameter at the given index is of the given type.
*/
void checkParam(CrocThread* t, word index, CrocValue.Type type)
{
	// ORDER CROCVALUE TYPE
	assert(type >= CrocValue.Type.FirstUserType && type <= CrocValue.Type.LastUserType, "invalid type");

	checkAnyParam(t, index);

	if(.type(t, index) != type)
		paramTypeError(t, index, CrocValue.typeStrings[type]);
}

/**
Throws an informative exception about the parameter at the given index, telling the parameter index ('this' for
parameter 0), the expected type, and the actual type.
*/
void paramTypeError(CrocThread* t, word index, char[] expected)
{
	pushTypeString(t, index);

	if(index == 0)
		throwStdException(t, "TypeException", "Expected type '{}' for 'this', not '{}'", expected, getString(t, -1));
	else
		throwStdException(t, "TypeException", "Expected type '{}' for parameter {}, not '{}'", expected, absIndex(t, index), getString(t, -1));
}

/**
These all get an optional parameter of the given type at the given index. If no parameter was passed to that
index or if 'null' was passed, 'def' is returned; otherwise, the passed parameter must match the given type
and its value is returned. This is the same behavior as in Croc.
*/
bool optBoolParam(CrocThread* t, word index, bool def)
{
	if(!isValidIndex(t, index) || isNull(t, index))
		return def;

	if(!isBool(t, index))
		paramTypeError(t, index, "bool");

	return getBool(t, index);
}

/// ditto
crocint optIntParam(CrocThread* t, word index, crocint def)
{
	if(!isValidIndex(t, index) || isNull(t, index))
		return def;

	if(!isInt(t, index))
		paramTypeError(t, index, "int");

	return getInt(t, index);
}

/// ditto
crocfloat optFloatParam(CrocThread* t, word index, crocfloat def)
{
	if(!isValidIndex(t, index) || isNull(t, index))
		return def;

	if(!isFloat(t, index))
		paramTypeError(t, index, "float");

	return getFloat(t, index);
}

/// ditto
dchar optCharParam(CrocThread* t, word index, dchar def)
{
	if(!isValidIndex(t, index) || isNull(t, index))
		return def;

	if(!isChar(t, index))
		paramTypeError(t, index, "char");

	return getChar(t, index);
}

/// ditto
char[] optStringParam(CrocThread* t, word index, char[] def)
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
crocfloat optNumParam(CrocThread* t, word index, crocfloat def)
{
	if(!isValidIndex(t, index) || isNull(t, index))
		return def;

	if(!isNum(t, index))
		paramTypeError(t, index, "int|float");

	return getNum(t, index);
}

/**
Similar to above, but works for any type. Returns false to mean that no parameter was passed,
and true to mean that one was.
*/
bool optParam(CrocThread* t, word index, CrocValue.Type type)
{
	if(!isValidIndex(t, index) || isNull(t, index))
		return false;

	if(.type(t, index) != type)
		paramTypeError(t, index, CrocValue.typeStrings[type]);

	return true;
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

void commonRun(CrocThread* t, uword numParams, char[] modName)
{
	pushNull(t);
	lookup(t, "modules.runMain");
	swap(t, -3);
	rotate(t, numParams + 3, 3);
	rawCall(t, -3 - numParams, 0);
}

// Check the format of a name of the form "\w[\w\d]*(\.\w[\w\d]*)*". Could we use an actual regex for this?  I guess,
// but then we'd have to create a regex object, and either it'd have to be static and access to it would have to be
// synchronized, or it'd have to be created in the VM object which is just dumb.
void validateName(CrocThread* t, char[] name)
{
	void wrongFormat()
	{
		throwStdException(t, "ApiError", "The name '{}' is not formatted correctly", name);
	}

	if(name.length == 0)
		throwStdException(t, "ApiError", "Cannot use an empty string for a name");

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

template IsIdentBeginChar(char c)
{
	const IsIdentBeginChar = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

template IsIdentChar(char c)
{
	const IsIdentChar = IsIdentBeginChar!(c) || (c >= '0' && c <= '9');
}

template ValidateNameCTImpl(char[] name, uword start = 0)
{
	template IdentLoop(uword idx)
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

template ValidateNameCT(char[] name)
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

template NameToAPICallsImpl(char[] name)
{
	alias ValidateNameCT!(name) t;
	const ret = "auto idx = pushGlobal(t, \"" ~ t[0] ~ "\");\n" ~ NameToAPICalls_toCalls!(t[1 .. $]) ~ (t.length > 1 ? "insertAndPop(t, idx);\n" : "");
}

template NameToAPICalls(char[] name)
{
	const NameToAPICalls = NameToAPICallsImpl!(name).ret;
}