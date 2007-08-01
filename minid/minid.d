/******************************************************************************
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
private import tango.io.Stdout;
private import tango.io.FileSystem;

/**
This enumeration is used with the NewContext function to specify which standard libraries you
want to load into the new context.  The base library is always loaded, so there is no
flag for it.  You can choose which libraries you want to load by ORing together multiple
flags.
*/
enum MDStdlib
{
	/// Nothing but the base library will be loaded if you specify this flag.
	None =      0,
	
	/// Array manipulation.
	Array =     1,

	/// Character classification.
	Char =      2,

	/// Stream-based input and output.
	IO =        4,

	/// Standard math functions.
	Math =      8,

	/// String manipulation.
	String =   16,

	/// Table manipulation.
	Table =    32,
	
	/// OS-specific functionality.
	OS =       64,

	/// Regular expressions.
	Regexp =  128,
	
	/// This flag is an OR of Array, Char, Math, String, Table, and Regexp.  It represents all
	/// the libraries which are "safe", i.e. malicious scripts would not be able to use the IO
	/// or OS libraries to do bad things.
	Safe = Array | Char | Math | String | Table | Regexp,
	
	/// All available standard libraries.
	All = Safe | IO | OS,
}

/**
Initializes a new MiniD context and loads any specified standard libraries into it.  Each new
context is also given a new MDState as its main thread.

Parameters:
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

Parameters:
	s = The state that will be used to initialize the module after it has been compiled.
		The module will be loaded into the global namespace of this state's context as well.
	source = The source code of the module, exactly as it would appear in a file.
	params = An optional list of parameters.  These are passed as the variadic parameters
		to the top-level module function.  Defaults to null (no parameters).
	name = The name which takes the place of the filename, used by the compiler to report
		error messages.  Defaults to "<module string>".

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

Parameters:
	s = The state that will be used to execute the resulting function.
	source = The source code to be compiled.
	params = An optional list of parameters.  These are passed as the variadic parameters
		to the compiled function.  Defaults to null (no parameters).
	name = The name which takes the place of the filename, used by the compiler to report
		error messages.  Also used as the name of the function, used when reporting runtime
		errors.  Defaults to "<statement string>".
		
Returns:
	The number of return values which the compiled function has returned.  These can then be
	popped off the execution stack of the state that was passed in as the first parameter.
*/
public uint loadStatementString(MDState s, dchar[] source, MDValue[] params = null, char[] name = "<statement string>")
{
	MDFuncDef def = compileStatements(source, name);
	MDClosure cl = new MDClosure(s.context.globals.ns, def);

	uint funcReg = s.push(cl);
	s.push(s.context.globals.ns);

	foreach(ref param; params)
		s.push(param);

	return s.call(funcReg, params.length + 1, -1);
}

/**
Compile and evaluate a MiniD expression, and get the result.  This is the equivalent of the "eval"
baselib function in MiniD.

Parameters:
	s = The state that will be used to run the compiled expression.
	source = The string that holds the expression.
	ns = The namespace which will be used as the context in which the expression will be evaluated.
		Defaults to the global namespace of the state's owning context.
*/
public MDValue eval(MDState s, dchar[] source, MDNamespace ns = null)
{
	if(ns is null)
		ns = s.context.globals.ns;

	MDFuncDef def = compileStatements("return " ~ source ~ ";", "<loaded by eval>");
	s.easyCall(new MDClosure(ns, def), 1, MDValue(ns));
	return s.pop();
}

static this()
{
	MDContext.tryPath = &tryPath;
	version(MDDynLibs) MDContext.tryDynLibPath = &tryDynLibPath;
}

private MDModuleDef tryPath(FilePath path, char[][] elems)
{
	if(!path.exists())
		return null;

	scope fp = new FilePath(FilePath.join(path.toUtf8().dup, FilePath.join(elems[0 .. $ - 1])), true);

	if(!fp.exists())
		return null;

	scope sourceName = new FilePath(FilePath.join(fp.toUtf8(), elems[$ - 1] ~ ".md"));
	scope binaryName = new FilePath(FilePath.join(fp.toUtf8(), elems[$ - 1] ~ ".mdm"));

	MDModuleDef def = null;

	if(sourceName.exists())
	{
		if(binaryName.exists())
		{
			if(sourceName.modified() > binaryName.modified())
				def = compileModule(sourceName.toUtf8());
			else
				def = MDModuleDef.loadFromFile(binaryName.toUtf8());
		}
		else
			def = compileModule(sourceName.toUtf8());
	}
	else
	{
		if(binaryName.exists())
			def = MDModuleDef.loadFromFile(binaryName.toUtf8());
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