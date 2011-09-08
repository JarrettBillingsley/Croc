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

	{"Error", "Throwable"},
		{"AssertError",    "Error"},
		{"ApiError",       "Error"},
		{"FinalizerError", "Error"},
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