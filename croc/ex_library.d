/******************************************************************************
This part of the exlib contains helper functions and structures for defining
native Croc libraries. All of the standard libraries are defined using this
interface.

License:
Copyright (c) 2012 Jarrett Billingsley

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

module croc.ex_library;

import tango.text.Util;

import croc.ex;
import croc.ex_doccomments;
import croc.api_interpreter;
import croc.api_stack;
import croc.types;

struct RegisterFunc
{
	char[] name;
	NativeFunc func;
	uword maxParams = uword.max;
	uword numUpvals = 0;
}

private void _pushFunc(CrocThread* t, RegisterFunc f)
{
	if(f.maxParams == uword.max)
		newFunction(t, f.func, f.name, f.numUpvals);
	else
		newFunction(t, f.maxParams, f.func, f.name, f.numUpvals);
}

void registerGlobal(CrocThread* t, RegisterFunc f)
{
	_pushFunc(t, f);
	newGlobal(t, f.name);
}

void registerField(CrocThread* t, RegisterFunc f)
{
	_pushFunc(t, f);
	fielda(t, -2, f.name);
}

void registerGlobals(CrocThread* t, RegisterFunc[] funcs...)
{
	foreach(ref func; funcs)
	{
		if(func.numUpvals > 0)
			throwStdException(t, "Exception", "registerGlobals - can't register function '{}' as it has upvalues. Use registerGlobal instead", func.name);

		registerGlobal(t, func);
	}
}

void registerFields(CrocThread* t, RegisterFunc[] funcs...)
{
	foreach(ref func; funcs)
	{
		if(func.numUpvals > 0)
			throwStdException(t, "Exception", "registerFields - can't register function '{}' as it has upvalues. Use registerField instead", func.name);

		registerField(t, func);
	}
}

void docGlobals(CrocThread* t, CrocDoc doc, CrocDoc.Docs[] docs...)
{
	foreach(ref d; docs)
	{
		auto pos = d.name.locatePrior('.');
		pos = pos == d.name.length ? 0 : pos + 1;

		pushGlobal(t, d.name[pos .. $]);
		doc(-1, d);
		pop(t);
	}
}

void docFields(CrocThread* t, CrocDoc doc, CrocDoc.Docs[] docs...)
{
	foreach(ref d; docs)
	{
		auto pos = d.name.locatePrior('.');
		pos = pos == d.name.length ? 0 : pos + 1;

		field(t, -1, d.name[pos .. $]);
		doc(-1, d);
		pop(t);
	}
}

/**
Simple function that attempts to create a custom loader (by making an entry in modules.customLoaders) for a
module. Throws an exception if a loader for the given module name already exists.

Params:
	name = The name of the module. If it's a nested module, include all name components (like "foo.bar.baz").
	loader = The module's loader function. Serves as the top-level function when the module is imported, and any
		globals defined in it become the module's public symbols.
*/
void makeModule(CrocThread* t, char[] name, NativeFunc loader)
{
	pushGlobal(t, "modules");
	field(t, -1, "customLoaders");

	if(hasField(t, -1, name))
		throwStdException(t, "LookupException", "makeModule - Module '{}' already has a loader set for it in modules.customLoaders", name);

	newFunction(t, 1, loader, name);
	fielda(t, -2, name);
	pop(t, 2);
}

/**
A standard class allocator for when you need to allocate some extra fields/bytes in a class instance.
Allocates the new instance with the given number of extra fields and bytes, then calls the ctor.

Params:
	numFields = The number of extra fields to allocate in the instance.
	Members = Any type. Members.sizeof extra bytes will be allocated in the instance, and those bytes
		will be initialized to Members.init.

Example:

-----
newClass(t, "Foob");
	// ...

	// We need 1 extra field, and SomeStruct will be used as the extra bytes
	newFunction(t, &BasicClassAllocator!(1, SomeStruct), "Foob.allocator");
	setAllocator(t, -2);
newGlobal(t, "Foob");
-----
*/
uword BasicClassAllocator(uword numFields, Members)(CrocThread* t)
{
	newInstance(t, 0, numFields, Members.sizeof);
	*(cast(Members*)getExtraBytes(t, -1).ptr) = Members.init;

	dup(t);
	pushNull(t);
	rotateAll(t, 3);
	methodCall(t, 2, "constructor", 0);
	return 1;
}

/**
Similar to above, but instead of a type for the extra bytes, just takes a number of bytes. In this case
the extra bytes will be uninitialized.
*/
uword BasicClassAllocator(uword numFields, uword numBytes)(CrocThread* t)
{
	newInstance(t, 0, numFields, numBytes);

	dup(t);
	pushNull(t);
	rotateAll(t, 3);
	methodCall(t, 2, "constructor", 0);
	return 1;
}

/**
A little helper object for making native classes. Just removes some of the boilerplate involved.

You use it like so:

-----
// Make a class named ClassName with no base class
CreateClass(t, "ClassName", (CreateClass* c)
{
	// Some normal methods
	c.method("blah", &blah);
	c.method("forble", &forble);

	// A method with one upval. Push it, then call c.method
	pushInt(t, 0);
	c.method("funcWithUpval", &funcWithUpval, 1);
});

// At this point, the class is sitting on top of the stack, so we have to store it
newGlobal(t, "ClassName");

// Make a class that derives from ClassName
CreateClass(t, "DerivedClass", "ClassName", (CreateClass* c) {});
newGlobal(t, "DerivedClass");
-----

If you pop the class inside the callback delegate accidentally, it'll check for that and
throw an error.

You can, of course, modify the class object after creating it, like if you need to add a finalizer or allocator.
*/
struct CreateClass
{
private:
	CrocThread* t;
	char[] name;
	word idx;

public:
	/** */
	static void opCall(CrocThread* t, char[] name, void delegate(CreateClass*) dg)
	{
		CreateClass co;
		co.t = t;
		co.name = name;
		co.idx = newClass(t, name);

		dg(&co);

		if(co.idx >= stackSize(t))
			throwStdException(t, "ApiError", "You popped the class {} before it could be finished!", name);

		if(stackSize(t) > co.idx + 1)
			setStackSize(t, co.idx + 1);
	}

	/** */
	static void opCall(CrocThread* t, char[] name, char[] base, void delegate(CreateClass*) dg)
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
			throwStdException(t, "ApiError", "You popped the class {} before it could be finished!", name);

		if(stackSize(t) > co.idx + 1)
			setStackSize(t, co.idx + 1);
	}

	/**
	Register a method.

	Params:
		name = Method name. The actual name that the native function closure will be created with is
			the class's name concatenated with a period and then the method name, so that in the example
			code above, the "blah" method would be named "ClassName.blah".
		f = The native function.
		numUpvals = How many upvalues this function needs. There should be this many values sitting on
			the stack.
	*/
	void method(char[] name, NativeFunc f, uword numUpvals = 0)
	{
		newFunction(t, f, this.name ~ '.' ~ name, numUpvals);
		addMethod(t, idx, name);
	}

	/**
	Same as above, but lets you specify a maximum allowable number of parameters. See
	interpreter.newFunction.
	*/
	void method(char[] name, uint numParams, NativeFunc f, uword numUpvals = 0)
	{
		newFunction(t, numParams, f, this.name ~ '.' ~ name, numUpvals);
		addMethod(t, idx, name);
	}

	/**
	Adds a field to the class. Expects the field's value to be on top of the stack.

	Params:
		name = The name of the field.
	*/
	void field(char[] name)
	{
		addField(t, idx, name);
	}

	/**
	Set this class's finalizer function.

	Params:
		name = Function name. This will just be used for the name of the function object, and will be
			prepended with the class's name, just like methods.
		f = The native finalizer function.
		numUpvals = How many upvalues this function needs. There should be this many values sitting on
			the stack.
	*/
	void finalizer(char[] name, NativeFunc f, uword numUpvals = 0)
	{
		newFunction(t, f, this.name ~ '.' ~ name, numUpvals);
		setFinalizer(t, idx);
	}
}

/**
*/
scope class CrocDoc
{
	static struct Docs
	{
		char[] kind;
		char[] name;
		char[] docs;

		uword line;

		Param[] params;
		Extra[] extra;
	}

	static struct Param
	{
		char[] name;
		char[] type = "any";
		char[] value;
	}

	static struct Extra
	{
		char[] name;
		char[] value;
	}

private:
	static const char[] DocTables = "ex.CrocDoc.docTables";

	CrocThread* t;
	char[] mFile;
	crocint mStartIdx;
	uword mDittoDepth = 0;

public:
	this(CrocThread* t, char[] file)
	{
		this.t = t;
		mFile = file;

		getDocTables();
		mStartIdx = len(t, -1);
		.pop(t);
	}

	~this()
	{
		if(!isThrowing(t))
		{
			getDocTables();
			auto l = len(t, -1);
			if(l != mStartIdx)
			{
				if(l < mStartIdx)
					throwStdException(t, "ApiError", "Mismatched documentation pushes and pops (stack is smaller by {})", mStartIdx - l);
				else
					throwStdException(t, "ApiError", "Mismatched documentation pushes and pops (stack is bigger by {})", l - mStartIdx);
			}
			.pop(t);
		}
	}

	void opCall(word idx, Docs docs, char[] parentField = "children")
	{
		push(docs);
		pop(idx, parentField);
	}

	void push(Docs docs)
	{
		if(mDittoDepth > 0)
		{
			mDittoDepth++;
			return;
		}

		auto dt = getDocTables();
		newTable(t);
		dup(t);
		cateq(t, dt, 1);

		pushString(t, mFile);     fielda(t, -2, "file");
		pushInt(t, docs.line);    fielda(t, -2, "line");
		pushString(t, docs.kind); fielda(t, -2, "kind");
		pushString(t, docs.name); fielda(t, -2, "name");

		if(docs.kind == "function")
		{
			newArray(t, 0);
			fielda(t, -2, "params");

			foreach(param; docs.params)
			{
				Docs pdoc = Docs("parameter", param.name);
				Extra[2] extra = void;
				extra[0] = Extra("type", param.type);

				if(param.value)
				{
					extra[1] = Extra("value", param.value);
					pdoc.extra = extra[];
				}
				else
					pdoc.extra = extra[0 .. 1];

				// dummy object for it to set the docs to
				pushNull(t);
				opCall(-1, pdoc, "params");
				.pop(t);
			}
		}

		if(docs.kind == "module" || docs.kind == "class" || docs.kind == "namespace")
		{
			newArray(t, 0);
			fielda(t, -2, "children");
		}

		foreach(extra; docs.extra)
		{
			pushString(t, extra.value);
			fielda(t, -2, extra.name);
		}

		if(docs.docs == "ditto")
		{
			doDitto(dt, docs);
			.pop(t);
		}
		else
		{
			if(docs.kind != "parameter")
				processComment(t, docs.docs);

			.pop(t, 2);
		}
	}

	void pop(word idx, char[] parentField = "children")
	{
		if(mDittoDepth > 0)
		{
			mDittoDepth--;

			if(mDittoDepth > 0)
				return;

			idx = absIndex(t, idx);

			switch(type(t, idx))
			{
				case CrocValue.Type.Function, CrocValue.Type.Class, CrocValue.Type.Namespace:
					auto dt = getDocTables();
					assert(len(t, dt) > 0);

					auto dittoed = idxi(t, dt, -1);

					if(!hasField(t, dittoed, parentField))
						throwStdException(t, "ApiError", "Something got screwed up... parent decl doesn't have {} anymore.", parentField);

					field(t, dittoed, parentField);

					if(len(t, -1) == 0)
						throwStdException(t, "ApiError", "Corruption! Parent decl's {} array is empty somehow.", parentField);

					idxi(t, -1, -1);
					insertAndPop(t, dittoed);

					pushGlobal(t, "_doc_");
					pushNull(t);
					dup(t, idx);
					dup(t, dittoed);
					rawCall(t, -4, 0);
					.pop(t, 2);
					return;

				default: return;
			}
		}

		idx = absIndex(t, idx);
		auto dt = getDocTables();

		if(len(t, dt) == 0)
			throwStdException(t, "ApiError", "Documentation stack underflow!");

		auto docTab = idxi(t, dt, -1);

		// first call _doc_ on the thing if we should
		switch(type(t, idx))
		{
			case CrocValue.Type.Function, CrocValue.Type.Class, CrocValue.Type.Namespace:
				pushGlobal(t, "_doc_");
				pushNull(t);
				dup(t, idx);
				dup(t, docTab);
				rawCall(t, -4, 1);
				swap(t, -1, idx);
				.pop(t);
				break;

			default:
				break;
		}

		// then put it in the parent
		lenai(t, dt, len(t, dt) - 1);

		if(len(t, dt) > 0)
		{
			auto parent = idxi(t, dt, -1);

			pushString(t, parentField);

			if(!opin(t, -1, -2))
			{
				newArray(t, 0);
				fielda(t, parent, parentField);
			}

			field(t, parent);
			dup(t, docTab);
			cateq(t, -2, 1);
			.pop(t, 2);
		}

		.pop(t, 2);
	}

private:
	word getDocTables()
	{
		auto reg = getRegistry(t);
		pushString(t, DocTables);

		if(!opin(t, -1, reg))
		{
			newArray(t, 0);
			fielda(t, reg, DocTables);
		}

		field(t, reg);
		insertAndPop(t, reg);
		return absIndex(t, -1);
	}

	void doDitto(word dt, Docs docs)
	{
		// At top level?
		if(len(t, dt) == 1)
			throwStdException(t, "ApiError", "Cannot use ditto on the top-level declaration");

		// Get the parent and try to get the last declaration before this one
		idxi(t, dt, -2);

		bool okay = false;

		if(hasField(t, -1, "children"))
		{
			field(t, -1, "children");

			if(len(t, -1) > 0)
			{
				idxi(t, -1, -1);
				insertAndPop(t, -3);
				okay = true;
			}
		}

		if(!okay)
			throwStdException(t, "ApiError", "No previous declaration to ditto from");

		// See if the previous decl's kind is the same
		field(t, -1, "kind");

		if(getString(t, -1) != docs.kind)
		{
			field(t, -2, "name");
			throwStdException(t, "ApiError", "Can't ditto documentation for '{}': it's a {}, but '{}' was a {}", docs.name, docs.kind, getString(t, -1), getString(t, -2));
		}

		.pop(t);

		// Okay, we can ditto.
		mDittoDepth++;
		lenai(t, dt, len(t, dt) - 1);

		if(!hasField(t, -1, "dittos"))
		{
			newArray(t, 0);
			fielda(t, -2, "dittos");
		}

		// Append this doctable to the dittos of the previous decl.
		field(t, -1, "dittos");
		dup(t, -3);
		cateq(t, -2, 1);
		.pop(t, 3);
	}
}