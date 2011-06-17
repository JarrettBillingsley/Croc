/******************************************************************************
This module holds some useful API functions that don't fit anywhere else.  This
also holds the important NewContext function, which is how you create a MiniD
interpreter to use in your app.

License:
Copyright (c) 2007 Jarrett Billingsley

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

module minid.minid;

version(MDDynLibs)
{
	pragma(msg, "MiniD's dynamic library support is not implemented.\nPlease compile without the MDDynLibs version set.");
	static assert(false);
}

import minid.types;
import minid.compiler;
import minid.misc;

import minid.arraylib;
import minid.baselib;
import minid.charlib;
import minid.iolib;
import minid.mathlib;
import minid.oslib;
import minid.regexplib;
import minid.stringlib;
import minid.tablelib;

import tango.io.FilePath;
import tango.io.Print;
import tango.io.Stdout;
import tango.io.FileSystem;
import tango.text.convert.Layout;

/**
This enumeration is used with the NewContext function to specify which standard libraries you
want to load into the new context.  The base library is always loaded, so there is no
flag for it.  You can choose which libraries you want to load by ORing together multiple
flags.
*/
enum MDStdlib
{
	/**
	Nothing but the base library will be loaded if you specify this flag.
	*/
	None =      0,

	/**
	Array manipulation.
	*/
	Array =     1,

	/**
	Character classification.
	*/
	Char =      2,

	/**
	Stream-based input and output.
	*/
	IO =        4,

	/**
	Standard math functions.
	*/
	Math =      8,

	/**
	String manipulation.
	*/
	String =   16,

	/**
	Table manipulation.
	*/
	Table =    32,

	/**
	OS-specific functionality.
	*/
	OS =       64,

	/**
	Regular expressions.
	*/
	Regexp =  128,

	/**
	This flag is an OR of Array, Char, Math, String, Table, and Regexp.  It represents all
	the libraries which are "safe", i.e. malicious scripts would not be able to use the IO
	or OS libraries to do bad things.
	*/
	Safe = Array | Char | Math | String | Table | Regexp,

	/**
	All available standard libraries.
	*/
	All = Safe | IO | OS,
}

/**
Initializes a new MiniD context and loads any specified standard libraries into it.  Each new
context is also given a new MDState as its main thread.

Params:
	libs = An ORing together of any standard libraries you want to load (see the MDStdlib enum).
	Defaults to MDStdlib.All.

Returns:
	The newly-created context, into which you can import code and from which you can get the main
	thread to run code.
*/
MDContext NewContext(uint libs = MDStdlib.All)
{
	MDContext ret = new MDContext();

	BaseLib.init(ret);

	if(libs & MDStdlib.Array)
		ArrayLib.init(ret);

	if(libs & MDStdlib.Char)
		CharLib.init(ret);

	if(libs & MDStdlib.IO)
		IOLib.init(ret);

	if(libs & MDStdlib.Math)
		MathLib.init(ret);

	if(libs & MDStdlib.OS)
		OSLib.init(ret);

	if(libs & MDStdlib.Regexp)
		RegexpLib.init(ret);

	if(libs & MDStdlib.String)
		StringLib.init(ret);

	if(libs & MDStdlib.Table)
		TableLib.init(ret);

	return ret;
}

/**
Compiles and initializes a module from a string, rather than loading one from a file.

Params:
	s = The state that will be used to initialize the module after it has been compiled.
		The module will be loaded into the global namespace of this state's context as well.
	source = The source code of the module, exactly as it would appear in a file.
	params = An optional list of parameters.  These are passed as the variadic parameters
		to the top-level module function.  Defaults to null (no parameters).
	name = The name which takes the place of the filename, used by the compiler to report
		error messages.  Defaults to "&lt;module string&gt;".

Returns:
	The top-level namespace of the module.
*/
public MDNamespace loadModuleString(MDState s, dchar[] source, MDValue[] params = null, char[] name = "<module string>")
{
	return s.context.initializeModule(s, compileModule(source, name), params);
}

/**
Compiles a string containing a list of statements into a variadic function, calls it, and
returns the number of results that the function returned (which can be popped off the provided
state's stack).  This is equivalent to the "loadString" baselib function in MiniD.

Params:
	s = The state that will be used to execute the resulting function.
	source = The source code to be compiled.
	ns = The namespace which will be used as the context in which the statements will be evaluated.
		Defaults to the global namespace of the state's owning context.
	params = An optional list of parameters.  These are passed as the variadic parameters
		to the compiled function.  Defaults to null (no parameters).
	name = The name which takes the place of the filename, used by the compiler to report
		error messages.  Also used as the name of the function, used when reporting runtime
		errors.  Defaults to "&lt;statement string&gt;".

Returns:
	The number of return values which the compiled function has returned.  These can then be
	popped off the execution stack of the state that was passed in as the first parameter.
*/
public uint loadStatementString(MDState s, dchar[] source, MDNamespace ns = null, MDValue[] params = null, char[] name = "<statement string>")
{
	if(ns is null)
		ns = s.context.globals.ns;

	MDFuncDef def = compileStatements(source, name);
	MDClosure cl = new MDClosure(ns, def);

	uint funcReg = s.push(cl);
	s.push(ns);

	foreach(ref param; params)
		s.push(param);

	return s.call(funcReg, params.length + 1, -1);
}

/**
Compile and evaluate a MiniD expression, and get the result.  This is the equivalent of the "eval"
baselib function in MiniD.

Params:
	s = The state that will be used to run the compiled expression.
	source = The string that holds the expression.
	ns = The namespace which will be used as the context in which the expression will be evaluated.
		Defaults to the global namespace of the state's owning context.
*/
public MDValue eval(MDState s, dchar[] source, MDNamespace ns = null)
{
	if(ns is null)
		ns = s.context.globals.ns;

	s.easyCall(new MDClosure(ns, compileExpression(source, "<loaded by eval>")), 1, MDValue(ns));
	return s.pop();
}

/**
Convert a table or an array object into JSON format.  This will work with MDTable, MDArray, or any
convertible D array or AA type.  Returns a string containing the JSON data.  If you have the need
for converting lots of things to JSON, or for writing JSON to some kind of output, use the writeJSON
function instead, as it lets you specify a place to put the resulting data, rather than allocating
its own destination.

This function is inside a template which is parameterized on the return type, or rather, the character
type of the return string type.  You can call it either as toJSON!(T)(...) where T is one of char, 
wchar, or dchar, or you can call it using the aliases toJSONc, toJSONw, and toJSONd.

Params:
	r = The root of the data.  Must be an MDTable, MDArray, or any convertible D array or AA type.
	pretty = If true, inserts newlines and indentation in the output to make it more human-readable.
		If false, elides all nonsignificant whitespace to make it as short as possible for transmission.
		Defaults to false.

Returns:
	The converted data as a string.
*/
template toJSON(U)
{
	public U[] toJSON(T)(T r, bool pretty = false)
	{
		MDValue root = r;

		scope cond = new GrowBuffer();
		scope formatter = new Layout!(U);
		scope printer = new Print!(U)(formatter, cond);

		toJSONImpl!(U)(null, root, pretty, printer);

		return cast(U[])cond.slice();
	}
}

/// ditto
alias toJSON!(char) toJSONc;

/// ditto
alias toJSON!(wchar) toJSONw;

/// ditto
alias toJSON!(dchar) toJSONd;

/**
Similar to toJSON, but instead of creating a string for the output and returning that, this allows you
to specify a Print instance that will be used to output the JSON as it's generated.  Note that if there's
an error during conversion, some of the data will have been printed already, so it's up to you to make sure
that any unwanted data is cleaned up.

Just like toJSON, this is parameterized on the character type of the output, and can be called either as
writeJSON!(T)(...) or as one of the aliases.

Params:
	printer = An instance of a Print parameterized on the type of the output.  This is where the JSON will
		be sent as it's being generated.
	r = The root of the data.  Must be an MDTable, MDArray, or any convertible D array or AA type.
	pretty = If true, inserts newlines and indentation in the output to make it more human-readable.
		If false, elides all nonsignificant whitespace to make it as short as possible for transmission.
		Defaults to false.
		
Examples:
-----
import tango.io.Stdout;

...

// Stdout is a Print!(char) instance, so we use the char version of writeJSON.
// We could also write "writeJSON!(char)(...)" here.
writeJSONc(Stdout, ["hi"[]: 3, "bye": 6]);
-----
*/
template writeJSON(U)
{
	public void writeJSON(T)(Print!(U) printer, T r, bool pretty = false)
	{
		toJSONImpl!(U)(null, MDValue(r), pretty, printer);
	}
}

/// ditto
alias writeJSON!(char) writeJSONc;

/// ditto
alias writeJSON!(wchar) writeJSONw;

/// ditto
alias writeJSON!(dchar) writeJSONd;

static this()
{
	// manual dynamic linking to get around circular dependencies.. funtimes.
	MDContext.tryPath = &tryPath;
	version(MDDynLibs) MDContext.tryDynLibPath = &tryDynLibPath;
}

private MDModuleDef tryPath(FilePath path, char[][] elems)
{
	if(!path.exists())
		return null;

	scope fp = new FilePath(FilePath.join(path.toString().dup, FilePath.join(elems[0 .. $ - 1])));

	if(!fp.exists())
		return null;

	scope sourceName = new FilePath(FilePath.join(fp.toString(), elems[$ - 1] ~ ".md"));
	scope binaryName = new FilePath(FilePath.join(fp.toString(), elems[$ - 1] ~ ".mdm"));

	MDModuleDef def = null;

	if(sourceName.exists())
	{
		if(binaryName.exists())
		{
			if(sourceName.modified() > binaryName.modified())
				def = compileModule(sourceName.toString());
			else
				def = MDModuleDef.loadFromFile(binaryName.toString());
		}
		else
			def = compileModule(sourceName.toString());
	}
	else
	{
		if(binaryName.exists())
			def = MDModuleDef.loadFromFile(binaryName.toString());
	}

	return def;
}

version(MDDynLibs)
{
	private char[] tryDynLibPath(char[] path, char[][] elems)
	{
		if(!file.exists(path))
			return null;
			
		foreach(elem; elems[0 .. $ - 1])
		{
			path = .path.join(path, elem);
			
			if(!file.exists(path))
				return null;
		}
	
		path = .path.join(path, elems[$ - 1]);
		
		char[] fileName = path ~ ".dll";
		
		if(file.exists(fileName))
			return fileName;
			
		return null;
	} 
}
