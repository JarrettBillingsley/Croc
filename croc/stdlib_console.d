/******************************************************************************
This module contains the 'console' standard library.

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

module croc.stdlib_console;

import tango.io.Console;
import tango.io.Stdout;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_format;
import croc.ex_library;
import croc.types;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initConsoleLib(CrocThread* t)
{
	auto console = importModuleFromString(t, "console", GlobalFuncCode, __FILE__);
		auto stream = importModule(t, "stream");

			field(t, stream, "InStream");
			pushNull(t);
			pushNativeObj(t, cast(Object)Cin.stream);
			pushBool(t, false);
			rawCall(t, -4, 1);
		fielda(t, console, "stdin");

			field(t, stream, "OutStream");
			pushNull(t);
			pushNativeObj(t, cast(Object)Cout.stream);
			pushBool(t, false);
			rawCall(t, -4, 1);
		fielda(t, console, "stdout");

			field(t, stream, "OutStream");
			pushNull(t);
			pushNativeObj(t, cast(Object)Cerr.stream);
			pushBool(t, false);
			rawCall(t, -4, 1);
		fielda(t, console, "stderr");

		pop(t);
	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

const char[] GlobalFuncCode =
 `
/**
The console library provides basic console IO by wrapping the standard input, output, and error streams in
\link{stream.Stream} objects. This is a safe library. It also exports some functions into the global namespace for
convenience.
*/
module console

import stream

/**
These are the \link{stream.Stream} objects that wrap the standard input, output, and error streams. You can, however,
reassign these at will, which makes redirecting Croc's input and output trivial. For instance, if you wanted to
change the standard input stream to use a file instead of the console, you could simply do it like this:

\code
// Good idea to hold onto the old stream in case you want to set it back
local oldStream = console.stdin
console.stdin = file.inFile("somefile.txt")

// Now any use of stdin (including the global readln() function) will read from "somefile.txt" instead.
\endcode
*/
global stdin, stdout, stderr

/**
This is a shortcut for calling \tt{stdout.write} with the given arguments.

Also mirrored in the global namespace so you can access it unqualified.

\see \link{stream.TextStream.write}
*/
function write(vararg)
	stdout.write(vararg)

/**
This is a shortcut for calling \tt{stdout.writeln} with the given arguments.

Also mirrored in the global namespace so you can access it unqualified.

\see \link{stream.TextStream.writeln}
*/
function writeln(vararg)
	stdout.writeln(vararg)

/**
This is a shortcut for calling \tt{stdout.writef} with the given arguments.

Also mirrored in the global namespace so you can access it unqualified.

\see \link{stream.TextStream.writef}
*/
function writef(fmt: string, vararg)
	stdout.writef(fmt, vararg)

/**
This is a shortcut for calling \tt{stdout.writefln} with the given arguments.

Also mirrored in the global namespace so you can access it unqualified.

\see \link{stream.TextStream.writefln}
*/
function writefln(fmt: string, vararg)
	stdout.writefln(fmt, vararg)

/**
This is a shortcut for calling \tt{stdin.readln}.

Also mirrored in the global namespace so you can access it unqualified.

\see \link{stream.TextStream.readln}
*/
function readln() =
	stdin.readln()

// Export write[f][ln] and readln to the global namespace
_G.write = write
_G.writeln = writeln
_G.writef = writef
_G.writefln = writefln
_G.readln = readln
 `;