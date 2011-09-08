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

struct ExceptionsLib
{
static:
	public void init(CrocThread* t)
	{
		importModuleFromString(t, "exceptions", srcCode, srcName);
		
		field(t, -1, "Location");
		t.vm.location = getClass(t, -1);
		pop(t);

		foreach(desc; ExDescs)
		{
			field(t, -1, desc.name);
			*t.vm.stdExceptions.insert(t.vm.alloc, createString(t, desc.name)) = getClass(t, -1);
			pop(t);
		}

		pop(t);
	}
}

struct ExDesc
{
	char[] name, derives;
}

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
		{"CallException",    "Exception"},
			{"ParamException", "CallException"},

	{"Error", "Throwable"},
		{"AssertError",    "Error"},
		{"ApiError",       "Error"},
		{"FinalizerError", "Error"},
		{"SwitchError",    "Error"},
		{"VMError",        "Error"},
];

char[] makeExceptionClasses()
{
	char[] ret;

	foreach(desc; ExDescs)
		ret ~= "\nclass " ~ desc.name ~ " : " ~ desc.derives ~ "{}";

	return ret;
}

private const char[] srcName = "exceptions.croc";
private const char[] srcCode =
`module exceptions

class Location
{
	Unknown = 0
	Native = -1
	Script = -2

	file = ""
	line = 0
	col = Location.Unknown

	this(file: string|null, line: int = -1, col: int = Location.Script)
	{
		if(file is null)
			return

		:file = file
		:line = line
		:col = col
	}

	function toString()
	{
		switch(:col)
		{
			case Location.Unknown: return "<unknown location>"
			case Location.Native:  return :file ~ "(native)"
			case Location.Script:  return :file ~ '(' ~ (:line < 1 ? "?" : toString(:line)) ~ ')'
			default:               return :file ~ '(' ~ (:line < 1 ? "?" : toString(:line)) ~ ':' ~ toString(:col) ~ ')'
		}
	}
}

Throwable.cause = null
Throwable.msg = ""
Throwable.location = Location()
Throwable.traceback = []

Throwable.constructor = function constructor(msg: string = "", cause: Throwable = null)
{
	:msg = msg
	:cause = cause
}

Throwable.toString = function toString()
{
	if(#:msg > 0)
		return nameOf(:super) ~ " at " ~ :location.toString() ~ ": " ~ :msg
	else
		return nameOf(:super) ~ " at " ~ :location.toString()
}

Throwable.setLocation = function setLocation(l: Location)
{
	:location = l
	return this
}

Throwable.tracebackString = function tracebackString()
{
	if(#:traceback == 0)
		return ""

	local s = string.StringBuffer()

	s ~= "Traceback: " ~ :traceback[0]

	for(i: 1 .. #:traceback)
		s ~= "\n       at: " ~ :traceback[i]

	return s.toString()
}` ~ makeExceptionClasses();