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

import tango.core.Tuple;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_library;
import croc.types;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initExceptionsLib(CrocThread* t)
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
			pushGlobal(t, "Location");
			pushNull(t);
			rawCall(t, -2, 1);
			addField(t, -2, "location");

			pushString(t, ""); addField(t, -2, "msg");
			pushNull(t);       addField(t, -2, "cause");
			newArray(t, 0);    addField(t, -2, "traceback");

			newFunction(t, 2, &throwableConstructor,     "Throwable.constructor");     addMethod(t, -2, "constructor");
			newFunction(t, 0, &throwableToString,        "Throwable.toString");        addMethod(t, -2, "toString");
			newFunction(t, 1, &throwableSetLocation,     "Throwable.setLocation");     addMethod(t, -2, "setLocation");
			newFunction(t, 1, &throwableSetCause,        "Throwable.setCause");        addMethod(t, -2, "setCause");
			newFunction(t, 0, &throwableTracebackString, "Throwable.tracebackString"); addMethod(t, -2, "tracebackString");
		pop(t);

		foreach(desc; ExDescs)
		{
			pushGlobal(t, desc.derives);
			newClass(t, -1, desc.name);
			*t.vm.stdExceptions.insert(t.vm.alloc, createString(t, desc.name)) = getClass(t, -1);

			newGlobal(t, desc.name);
			pop(t);
		}

		pushGlobal(t, "_G");
			pushGlobal(t, "Exception"); fielda(t, -2, "Exception");
			pushGlobal(t, "Error");     fielda(t, -2, "Error");
		pop(t);

		newFunction(t, 1, &stdException, "stdException"); newGlobal(t, "stdException");

		return 0;
	});

	importModuleNoNS(t, "exceptions");
}

version(CrocBuiltinDocs) void docExceptionsLib(CrocThread* t)
{
	pushGlobal(t, "exceptions");

	scope doc = new CrocDoc(t, __FILE__);
	doc.push(Docs("module", "Exceptions Library",
	"This library defines the hierarchy of standard exception types. These types are used by the standard
	libraries and by the VM itself. You are encouraged to use these types as well, or derive them, for
	your own code."));

	field(t, -1, "Location");
	doc.push(Location_docs);
	docFields(t, doc, Location_fields);
	doc.pop(-1);
	pop(t);

	pushGlobal(t, "Throwable");
	doc.push(Throwable_docs);
	docFields(t, doc, Throwable_fields);
	doc.pop(-1);
	pop(t);

	foreach(desc; ExDescs)
	{
		field(t, -1, desc.name);
		doc(-1, desc.docs);
		pop(t);
	}

	doc.pop(-1);
	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

const crocint Unknown = 0;
const crocint Native = -1;
const crocint Script = -2;

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
		insert(t, -2);
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

uword throwableSetCause(CrocThread* t)
{
	checkInstParam(t, 1);

	pushThrowableClass(t);
	if(!as(t, 1, -1))
		paramTypeError(t, 1, "instance of Throwable");
	pop(t);

	dup(t, 1);
	fielda(t, 0, "cause");
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

struct ExDesc
{
	char[] name, derives;

	version(CrocBuiltinDocs)
		Docs docs;
}

template Desc(char[] name, char[] derives, char[] docs)
{
	version(CrocBuiltinDocs)
		const Desc = ExDesc(name, derives, Docs("class", name, docs, 0, null, [Extra("protection", "global"), Extra("base", derives)]));
	else
		const Desc = ExDesc(name, derives);
}

private const ExDesc[] ExDescs =
[
	Desc!("Exception", "Throwable", `Base class for all "generally non-fatal" exceptions. This is exported in the
		global namespace as well, to make it more convenient to access.`),

		Desc!("CompileException", "Exception", `Base class for exceptions that the Croc compiler throws. The
			\tt{location} field is the source location that caused the exception to be thrown.`),
			Desc!("LexicalException", "CompileException", `Thrown for lexical errors in source code.`),
			Desc!("SyntaxException", "CompileException", `Thrown for syntactic errors in source code.`),
			Desc!("SemanticException", "CompileException", `Thrown for semantic errors in source code.`),
		Desc!("TypeException", "Exception", `Thrown when an incorrect type is given to an operation (i.e. trying
			to add strings, or when invalid types are given to function parameters).`),
		Desc!("ValueException", "Exception", `Generally speaking, indicates that an operation was given a value
			of the proper type, but the value is invalid somehow - not an acceptible value, or incorrectly formed, or
			in an invalid state. If possible, try to use one of the more specific classes that derive from this, or
			derive your own.`),
			Desc!("RangeException", "ValueException", `A more specific kind of ValueException indicating that a
				value is out of a valid range of acceptible values. Typically used for mathematical functions, i.e.
				square root only works on non-negative values. Note that if the error is because a value is out of the
				range of valid indices for a container, you should use a \link{exceptions.BoundsException} instead.`),
			Desc!("StateException", "ValueException", `A more specific kind of ValueException indicating that an object
				is in an invalid state.`),
			Desc!("UnicodeException", "ValueException", `Thrown when Croc is given malformed/invalid Unicode data
				for a string, or when invalid Unicode data is encountered during transcoding.`),
		Desc!("IOException", "Exception", `Thrown when an IO operation fails or is given invalid inputs.`),
		Desc!("OSException", "Exception", `Thrown when the OS is angry.`),
		Desc!("ImportException", "Exception", `Thrown when an import fails; may also have a 'cause' exception in
			case the import failed because of an exception being thrown.`),
		Desc!("LookupException", "Exception", `Base class for "lookup" errors, which covers several kinds of
			lookups. Sometimes this base class can be thrown too.`),
			Desc!("NameException", "LookupException", `Thrown on invalid global access (either the name doesn't
				exist or trying to redefine an existing global). Also for invalid local names when using the debug
				library.`),
			Desc!("BoundsException", "LookupException", `Thrown when trying to access an array-like object out of
				bounds. You could also use this for other kinds of containers.`),
			Desc!("FieldException", "LookupException", `Thrown when trying to access an invalid field from a
				namespace, class, instance etc. Unless it's global access, in which case a \link{exceptions.NameException}
				is thrown.`),
			Desc!("MethodException", "LookupException", `Thrown when trying to call an invalid method on an object.`),
		Desc!("RuntimeException", "Exception", `Kind of a catchall type for other random runtime errors. Other
			exceptions will probably grow out of this one.`),
			Desc!("NotImplementedException", "RuntimeException", `An exception type that you can throw in methods
				that are unimplemented (such as in abstract base class methods). This way when an un-overridden method
				is called, you get an error instead of it silently working.`),
		Desc!("CallException", "Exception", `Thrown for some kinds of invalid function calls, such as invalid supercalls.`),
			Desc!("ParamException", "CallException", `Thrown for function calls which are invalid because they
				were given an improper number of parameters. However if a function is given parameters of incorrect
				type, a \link{exceptions.TypeException} is thrown instead.`),

	Desc!("Error", "Throwable", `Base class for all "generally unrecoverable" errors. When an \tt{Error} is thrown,
		it usually means the program can't continue functioning properly unless the bug is fixed. This is also exported
		in the global namespace, like \link{exceptions.Exception}, for convenience.`),
		Desc!("AssertError", "Error", `Thrown when an assertion fails.`),
		Desc!("ApiError", "Error", `Thrown when the native API is given certain kinds of invalid input,
			generally inputs which mean the host is malfunctioning or incorrectly programmed. Not thrown for i.e.
			incorrect types passed to the native API.`),
		Desc!("FinalizerError", "Error", `Thrown when an exception is thrown by a class finalizer. This is typically
			a big problem as finalizers should never fail. The exception that the finalizer threw is set as the 'cause'.`),
		Desc!("SwitchError", "Error", `Thrown when a switch without a 'default' is given a value not listed in its cases.`),
		Desc!("VMError", "Error", `Thrown for some kinds of internal VM errors.`),
];

version(CrocBuiltinDocs)
{
	const Docs Location_docs = {kind: "class", name: "exceptions.Location",
	extra: [Extra("protection", "global")],
	docs:
	`This class holds a source location, which is used in exception tracebacks. There two kinds of locations:
	compile-time and runtime. Compile-time locations have a column number > 0 and indicate the exact location
	within a source file where something went wrong. Runtime locations have a column number <= 0, in which case
	the exact kind of location is encoded in the column number.`};

	const Docs[] Location_fields =
	[
		{kind: "field", name: "Unknown",
		extra: [Extra("value", `""`)],
		docs:
		`This is one of the types of locations that can be put in the \tt{col} field. It means that there isn't enough
		information to determine a location for where an error occurred. In this case the file and line will also
		probably meaningless.`},

		{kind: "field", name: "Native",
		docs:
		`This is another type of location that can be put in the \tt{col} field. It means that the location is within
		a native function, so there isn't enough information to give a line, but at least the file can be determined.`},

		{kind: "field", name: "Script",
		docs:
		`This is the last type of location that can be put in the \tt{col} field. It means that the location is within
		script code, the file and (usually) the line can be determined. The column can never be determined at runtime,
		however.`},

		{kind: "field", name: "file",
		docs:
		`This is a string containing the module and function where the error occurred, in the format "module.name.func".
		If \tt{col} is \tt{Location.Unknown}, this field will be the empty string.`},

		{kind: "field", name: "line",
		extra: [Extra("value", "0")],
		docs:
		`This is the line on which the error occurred. If the location type is \tt{Location.Script}, this field can
		be -1, which means that no line number could be determined.`},

		{kind: "field", name: "col",
	extra: [Extra("protection", "global")],
		docs:
		`This field serves double duty as either a column number for compilation errors or as a location "type".
		If this field is > 0, it is a compilation error and represents the column where the error occurred. Otherwise,
		this field will be one of the three constants above (which are all <= 0).`},

		{kind: "function", name: "constructor",
		params: [Param("file", "string", "null"), Param("line", "int", "-1"), Param("col", "int", "Location.Script")],
		docs:
		`Constructor. All parameters are optional. When passed \tt{null} for \tt{file}, the \tt{line} and \tt{col}
		parameters are ignored, constructing an "Unknown" location.`},

		{kind: "function", name: "toString",
		docs:
		`Gives a string representation of the location, in the following formats:
		\blist
			\li Unknown - \tt{"<unknown location>"}
			\li Native - \tt{"file(native)"}
			\li Script - \tt{"file(line)"} (if \tt{line < 1} then the line will be '?' instead)
			\li otherwise - \tt{"file(line:col)"}
		\endlist`}
	];

	const Docs Throwable_docs = {kind: "class", name: "Throwable",
	docs:
	`This is the base class of the entire exception hierarchy. This class is "blessed" in that it is treated specially by
	the language runtime. Whenever you throw an exception, it must be an instance of a class derived from Throwable. This class
	is actually a global variable like Object, but is documented here for convenience.`};

	const Docs[] Throwable_fields =
	[
		{kind: "field", name: "location",
		extra: [Extra("value", "Location()")],
		docs:
		`The location where this exception was thrown. See the \link{exceptions.Location} class documentation for more info. Defaults to
		an unknown location.`},

		{kind: "field", name: "msg",
		extra: [Extra("value", `""`)],
		docs:
		`The human-readable message associated with the exception. Defaults to the empty string.`},

		{kind: "field", name: "cause",
		extra: [Extra("value", "null")],
		docs:
		`An optional field. Sometimes an exception can cause a cascade of other exceptions; for instance, an exception thrown
		while importing a module will cause the module import to fail and throw an exception of its own. In these cases, the
		\tt{cause} field is used to hold the exception that caused this exception to be thrown. There can be arbitrarily many exceptions
		nested in this linked list of causes. It is up to the user, however, to provide the \tt{cause} exception when throwing a
		second exception; there is no built-in mechanism to ensure that this field is filled in. You can use the \link{setCause} function
		for this purpose.

		The default value is null, which means this exception had no cause.`},

		{kind: "field", name: "traceback",
		extra: [Extra("value", "[]")],
		docs:
		`This is an array of Location instances that shows the call stack as it was when the exception was thrown, allowing you
		to pinpoint the exact codepath that caused the error. This array starts at the location where the exception was thrown; that
		is, element 0 is the same as the \tt{location} field. After that, it gives the function that called the function where the
		exception was thrown and goes up the call stack. Tailcalls are represented as script locations. You can get a string
		representation of this traceback with the \tt{tracebackString} method. This field defaults to an empty array.`},

		{kind: "function", name: "constructor",
		params: [Param("msg", "string", `""`), Param("cause", "Throwable", "null")],
		docs:
		`Constructor. All parameters are optional.

		\param[msg] A descriptive message of the exception being thrown. This is meant to be human-readable, and is not used by the EH
			mechanism in any way. Defaults to the empty string.
		\param[cause] The exception that caused this exception to be thrown. Defaults to none (null).`},

		{kind: "function", name: "toString",
		docs:
		`Gives a string representation of the exception. It is in the format \tt{"<exception type> at <location>: <msg>"}. If the
		message is the empty string, there will be no colon after the location. If \tt{cause} is non-null, this will be followed by
		a newline, \tt{"Caused by:"}, another newline, and the string representation of \tt{cause}. There may therefore be several
		layers of causes in one representation.`},

		{kind: "function", name: "setLocation",
		params: [Param("loc", "Location")],
		docs:
		`Acts as a setter for the \tt{location} field. This is occasionally useful when programmatically building exception objects such
		as in the compiler.`},

		{kind: "function", name: "setCause",
		params: [Param("cause", "Throwable")],
		docs:
		`Acts as a setter for the \tt{cause} field. This can be useful when throwing an exception that is caused by another exception.
		Rather than forcing an exception constructor to take the cause as a parameter, you can simply use \tt{"throw SomeException().setCause(ex)"}
		instead.`},

		{kind: "function", name: "tracebackString",
		docs:
		`Gets a string representation of the \tt{traceback} field. The first entry is preceded by "Traceback: ". Each subsequent entry
		is preceded by a newline, some whitespace, and "at: ".`}
	];
}