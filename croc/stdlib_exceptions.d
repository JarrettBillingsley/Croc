/******************************************************************************
This module contains the 'exceptions' part of the standard library.

License:
Copyright (c) 2011 Jarrett Billingsley

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

module croc.stdlib_exceptions;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.types;

/*
+ Exception - Base class for all "generally non-fatal" exceptions.
	+ CompileException - Base class for exceptions that the Croc compiler throws.
		+ LexicalException - Thrown for lexical errors in source code.
		+ SyntaxException - Thrown for syntactic errors in source code.
		+ SemanticException - Thrown for semantic errors in source code.
	+ TypeException - Thrown when an incorrect type is given to an operation (i.e. trying to add strings, or invalid types to function parameters).
	+ ValueException - Generally speaking, indicates that an operation was given a value of the proper type, but the value is invalid
		somehow - not an acceptible value, or incorrectly formed, or in an invalid state.
		+ RangeException - A more specific kind of ValueException indicating that a value is out of a valid range of acceptible values. Typically
			used for mathematical functions, i.e. square root only works on non-negative values.
		+ UnicodeException - Thrown when Croc is given malformed/invalid Unicode data for a string.
	+ IOException - Thrown when an IO operation fails or is given invalid inputs.
	+ OSException - Thrown when the OS is pissy.
	+ ImportException - Thrown when an import fails; may also have a 'cause' exception in case the import failed because of an exception being thrown.
	+ LookupException - Base class for "lookup" errors, which covers several kinda of lookups. Sometimes this base class can be thrown too.
		+ NameException - Thrown on invalid global access (either the name doesn't exist or trying to redefine an existing global). Also for invalid
			local names when using the debug library.
		+ BoundsException - Thrown when trying to access an array-like object out of bounds.
		+ FieldException - Thrown when trying to access an invalid field from a namespace, class, instance etc.
		+ MethodException - Thrown when trying to call an invalid method on an object.
	+ RuntimeException - Kind of a catchall type for other random runtime errors. Other exceptions will probably grow out of this one.
		+ NotImplementedException - A useful exception type that you can throw in methods that are unimplemented (such as in abstrac base class
			methods).
	+ CallException - Thrown for some kinda of invalid function calls, such as invalid supercalls.
		+ ParamException - Thrown for function calls which are invalid because they were nit given the proper number of parameters (not for
			invalid types though).
+ Error - Base class for "generally unrecoverable" errors.
	+ AssertError - Thrown when an assertion fails.
	+ ApiError - Thrown when the native API is given certain kinds of invalid input, generally inputs which mean the host is
		malfunctioning or incorrectly programmed. Not thrown for i.e. incorrect types passed to the native API.
	+ FinalizerError - Thrown when an exception is thrown by a class finalizer. This is typically a big problem as finalizers
		should never fail. The exception that the finalizer threw is set as the 'cause'.
	+ SwitchError - Thrown when a switch without a 'default' is given a value not listed in its cases.
	+ VMError - Thrown for some kinds of internal VM errors.
*/

struct ExDesc
{
	char[] name, derives;
}

private const ExDesc[] ExDescs =
[
	{"Exception", "Throwable"},
		{"CompileException", "Exception"},
			{"LexicalException",  "CompileException"},
			{"SyntaxException",   "CompileException"},
			{"SemanticException", "CompileException"},
		{"TypeException",   "Exception"},
		{"ValueException",  "Exception"},
			{"RangeException",   "ValueException"},
			{"UnicodeException", "ValueException"},
		{"IOException",     "Exception"},
		{"OSException",     "Exception"},
		{"ImportException", "Exception"},
		{"LookupException", "Exception"},
			{"NameException",   "LookupException"},
			{"BoundsException", "LookupException"},
			{"FieldException",  "LookupException"},
			{"MethodException", "LookupException"},
		{"RuntimeException", "Exception"},
			{"NotImplementedException", "RuntimeException"},
		{"CallException",    "Exception"},
			{"ParamException", "CallException"},

	{"Error", "Throwable"},
		{"AssertError",    "Error"},
		{"ApiError",       "Error"},
		{"FinalizerError", "Error"},
		{"SwitchError",    "Error"},
		{"VMError",        "Error"},
];

struct ExceptionsLib
{
static:
	const crocint Unknown = 0;
	const crocint Native = -1;
	const crocint Script = -2;

	public void init(CrocThread* t)
	{
		makeModule(t, "exceptions", function uword(CrocThread* t)
		{
			CreateClass(t, "Location", (CreateClass* c)
			{
				pushInt(t, Unknown); c.field("Unknown");
				pushInt(t, Native);  c.field("Native");
				pushInt(t, Script);  c.field("Script");

				pushString(t, "");   c.field("file");
				pushInt(t, 0);       c.field("line");
				pushInt(t, Unknown); c.field("col");

				c.method("constructor", 3, &locationConstructor);
				c.method("toString",    0, &locationToString);
			});

			t.vm.location = getClass(t, -1);
			newGlobal(t, "Location");

			pushGlobal(t, "Throwable");
				pushNull(t); fielda(t, -2, "cause");
				pushString(t, ""); fielda(t, -2, "msg");
				newArray(t, 0); fielda(t, -2, "traceback");

				pushGlobal(t, "Location");
				pushNull(t);
				rawCall(t, -2, 1);
				fielda(t, -2, "location");

				newFunction(t, 2, &throwableConstructor,     "Throwable.constructor");     fielda(t, -2, "constructor");
				newFunction(t, 0, &throwableToString,        "Throwable.toString");        fielda(t, -2, "toString");
				newFunction(t, 1, &throwableSetLocation,     "Throwable.setLocation");     fielda(t, -2, "setLocation");
				newFunction(t, 0, &throwableTracebackString, "Throwable.tracebackString"); fielda(t, -2, "tracebackString");
			pop(t);

			foreach(desc; ExDescs)
			{
				pushGlobal(t, desc.derives);
				newClass(t, -1, desc.name);
				*t.vm.stdExceptions.insert(t.vm.alloc, createString(t, desc.name)) = getClass(t, -1);
				newGlobal(t, desc.name);
				pop(t);
			}

			newFunction(t, 1, &stdException, "stdException"); newGlobal(t, "stdException");
			return 0;
		});

		importModuleNoNS(t, "exceptions");

	}

	uword locationConstructor(CrocThread* t)
	{
		auto file = optStringParam(t, 1, null);

		if(file is null)
			return 0;

		auto line = optIntParam(t, 2, -1);
		auto col = optIntParam(t, 3, Script);

		pushString(t, file); fielda(t, 0, "file");
		pushInt(t, line);    fielda(t, 0, "line");
		pushInt(t, col);     fielda(t, 0, "col");
		return 0;
	}

	uword locationToString(CrocThread* t)
	{
		field(t, 0, "col");

		switch(getInt(t, -1))
		{
			case Unknown:
				pushString(t, "<unknown location>");
				break;

			case Native:
				field(t, 0, "file");
				pushString(t, "(native)");
				cat(t, 2);
				break;

			case Script:
				auto first = field(t, 0, "file");
				pushChar(t, '(');

				field(t, 0, "line");

				if(getInt(t, -1) < 1)
					pushChar(t, '?');
				else
					pushToString(t, -1, true);

				insertAndPop(t, -2);

				pushChar(t, ')');
				cat(t, stackSize(t) - first);
				break;

			default:
				auto first = field(t, 0, "file");
				pushChar(t, '(');

				field(t, 0, "line");

				if(getInt(t, -1) < 1)
					pushChar(t, '?');
				else
					pushToString(t, -1, true);

				insertAndPop(t, -2);

				pushChar(t, ':');

				field(t, 0, "col");
				pushToString(t, -1, true);
				insertAndPop(t, -2);

				pushChar(t, ')');
				cat(t, stackSize(t) - first);
				break;
		}

		return 1;
	}

	uword throwableConstructor(CrocThread* t)
	{
		auto msg = optStringParam(t, 1, "");

		if(isValidIndex(t, 2))
		{
			pushThrowableClass(t);
			if(!as(t, 2, -1))
				paramTypeError(t, 2, "instance of Throwable");
			pop(t);

			dup(t, 2);
			fielda(t, 0, "cause");
		}
		else
		{
			pushNull(t);
			fielda(t, 0, "cause");
		}

		pushString(t, msg);
		fielda(t, 0, "msg");
		return 0;
	}

	uword throwableToString(CrocThread* t)
	{
		auto first = superOf(t, 0);
		pushString(t, className(t, -1));
		insertAndPop(t, -2);
		pushString(t, " at ");
		field(t, 0, "location");
		pushNull(t);
		methodCall(t, -2, "toString", 1);

		field(t, 0, "msg");

		if(len(t, -1) > 0)
		{
			pushString(t, ": ");
			insert(t, -2);
		}
		else
			pop(t);

		first = cat(t, stackSize(t) - first);

		field(t, 0, "cause");

		if(isNull(t, -1))
			pop(t);
		else
		{
			pushString(t, "\nCaused by:\n");
			insertAndPop(t, -2);
			pushNull(t);
			methodCall(t, -2, "toString", 1);
			cat(t, stackSize(t) - first);
		}

		return 1;
	}

	uword throwableSetLocation(CrocThread* t)
	{
		checkInstParam(t, 1);
		
		pushLocationClass(t);
		if(!as(t, 1, -1))
			paramTypeError(t, 1, "instance of Location");
		pop(t);
		
		dup(t, 1);
		fielda(t, 0, "location");
		dup(t, 0);
		return 1;
	}

	uword throwableTracebackString(CrocThread* t)
	{
		auto traceback = field(t, 0, "traceback");
		auto tblen = len(t, traceback);

		if(tblen == 0)
		{
			pushString(t, "");
			return 1;
		}

		auto s = StrBuffer(t);
		s.addString("Traceback: ");

		idxi(t, traceback, 0);
		pushNull(t);
		methodCall(t, -2, "toString", 1);
		s.addTop();

		for(crocint i = 1; i < tblen; i++)
		{
			s.addString("\n       at: ");
			idxi(t, traceback, i);
			pushNull(t);
			methodCall(t, -2, "toString", 1);
			s.addTop();
		}

		s.finish();
		return 1;
	}

	uword stdException(CrocThread* t)
	{
		getStdException(t, checkStringParam(t, 1));
		return 1;
	}
}