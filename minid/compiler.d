/******************************************************************************
This module contains the public interface to the MiniD compiler.

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

module minid.compiler;

import tango.core.Vararg;

import tango.io.FilePath;
import tango.io.UnicodeFile;

import minid.alloc;
import minid.astvisitor;
import minid.codegen;
import minid.compilertypes;
import minid.interpreter;
import minid.lexer;
import minid.parser;
import minid.semantic;
import minid.stackmanip;
import minid.string;
import minid.types;

import minid.interp:
	createString;

/**
This class encapsulates all the functionality needed for compiling MiniD code.
*/
scope class Compiler : ICompiler
{
	mixin ICompilerMixin;

	/**
	An enumeration of flags that can be passed to the compiler to change its behavior.
	*/
	enum
	{
		/**
		Do not generate code for any optional features.
		*/
		None = 0,
		
		/**
		Generate code to check parameter type constraints.
		*/
		TypeConstraints = 1,
		
		/**
		Generate code for assert statements.
		*/
		Asserts = 2,

		/**
		Generate debug info.  Currently always on.
		*/
		Debug = 4,

		/**
		Generate code for all optional features.
		*/
		All = TypeConstraints | Asserts | Debug
	}

	private MDThread* t;
	private	uint mFlags;
	private bool mIsEof;
	private bool mIsLoneStmt;
	private Lexer mLexer;
	private Parser mParser;
	private word mStringTab;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

	/**
	Constructs a compiler.  The given thread will be used to hold temporary data structures,
	to throw exceptions, and to return the functions that result from compilation.

	Params:
		t = The thread with which this compiler will be associated.
		flags = A bitwise or of any code-generation flags you want to use for this compiler.
			Defaults to All.
	*/
	public this(MDThread* t, uint flags = All)
	{
		this.t = t;
		mFlags = flags;
		mLexer = Lexer(this);
		mParser = Parser(this, &mLexer);
	}

	~this()
	{
		for(auto n = mHead; n !is null; )
		{
			auto next = n.next;

			n.cleanup(t.vm.alloc);
			auto arr = n.toVoidArray();
			t.vm.alloc.freeArray(arr);

			n = next;
		}
	}

	/**
	Set the compiler's code-generation flags.
	*/
	public void setFlags(uint flags)
	{
		mFlags = flags;
	}

	/**
	Returns whether or not code for asserts should be generated.
	*/
	public override bool asserts()
	{
		return (mFlags & Asserts) != 0;
	}

	/**
	Returns whether or not code for parameter type constraint checking should be generated.
	*/
	public override bool typeConstraints()
	{
		return (mFlags & TypeConstraints) != 0;
	}

	/**
	Returns whether or not the most recently-thrown exception was thrown due to an unexpected end-of-file.
	As an example, this is used by MDCL (that is, minid.commandline) to detect when more code must be entered
	to complete a code segment.  A simple example of use:
	
-----
scope c = new Compiler(t);

try
	c.compileExpression(someCode, "test");
catch(MDException e)
{
	auto ex = catchException(t);
	
	if(c.isEof())
	{
		// error was caused by an unexpected end-of-file
	}
}
-----
	*/
	public override bool isEof()
	{
		return mIsEof;
	}
	
	/**
	Returns whether or not the most recently-thrown exception was thrown due to a no-effect expression being used
	as a statement (yes, this method has a horrible name).  Its use is identical to isEof().
	*/
	public override bool isLoneStmt()
	{
		return mIsLoneStmt;
	}

	public override void exception(CompileLoc loc, char[] msg, ...)
	{
		vexception(loc, msg, _arguments, _argptr);
	}

	public override void eofException(CompileLoc loc, char[] msg, ...)
	{
		mIsEof = true;
		vexception(loc, msg, _arguments, _argptr);
	}

	public override void loneStmtException(CompileLoc loc, char[] msg, ...)
	{
		mIsLoneStmt = true;
		vexception(loc, msg, _arguments, _argptr);
	}

	public override MDThread* thread()
	{
		return t;
	}

	public override Allocator* alloc()
	{
		return &t.vm.alloc;
	}

	public override char[] newString(char[] data)
	{
		auto s = createString(t, data);
		push(t, MDValue(s));
		pushBool(t, true);
		idxa(t, mStringTab);
		return s.toString();
	}

	/**
	Compile a source code file into a function closure.  Takes the path to the source file, compiles
	that file, and pushes the top-level closure onto the stack.  The environment of the closure is
	just set to the global namespace of the compiler's thread; you must create and set a namespace
	for the module function before calling it.

	You shouldn't have to deal with this function that much.  Most of the time the compilation of
	modules should be handled for you by the import system.

	Params:
		filename = The filename of the source file to compile.

	Returns:
		The stack index of the newly-pushed function closure that represents the top-level function
		of the module.
	*/
	public word compileModule(char[] filename)
	{
		scope file = new UnicodeFile!(char)(filename, Encoding.Unknown);
		auto src = file.read();

		scope(exit)
			delete src;

		return compileModule(src, filename);
	}

	/**
	Same as above, but compiles from a string holding the source rather than from a file.

	Params:
		source = The source code as a string.
		name = The name which should be used as the source name in compiler error message.  Takes the
			place of the filename when compiling from a source file.

	Returns:
		The stack index of the newly-pushed function closure that represents the top-level function
		of the module.
	*/
	public word compileModule(char[] source, char[] name)
	{
		return commonCompile(
		{
			mLexer.begin(name, source);
			auto mod = mParser.parseModule();

			scope sem = new Semantic(this);
			mod = sem.visit(mod);

			scope cg = new Codegen(this);
			cg.visit(mod);
		});
	}

	/**
	Compile a list of statements into a function which takes a variadic number of arguments.  The environment
	of the compiled function closure is set to the globals of the compiler's thread.

	Params:
		source = The source code as a string.
		name = The name to use as the source name for compilation errors.

	Returns:
		The stack index of the newly-pushed function closure.
	*/
	public word compileStatements(char[] source, char[] name)
	{
		return commonCompile(
		{
			mLexer.begin(name, source);
			auto fd = mParser.parseStatements(name);

			scope sem = new Semantic(this);
			fd = sem.visitStatements(fd);

			scope cg = new Codegen(this);
			cg.codegenStatements(fd);
		});
	}

	/**
	Compile a single expression into a function which returns the value of that expression when called.

	Params:
		source = The source code as a string.
		name = The name to use as the source name for compilation errors.

	Returns:
		The stack index of the newly-pushed function closure.
	*/
	public word compileExpression(char[] source, char[] name)
	{
		return commonCompile(
		{
			mLexer.begin(name, source);
			auto fd = mParser.parseExpressionFunc(name);

			scope sem = new Semantic(this);
			fd = sem.visit(fd);

			scope cg = new Codegen(this);
			cg.codegenStatements(fd);
		});
	}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

	private void vexception(ref CompileLoc loc, char[] msg, TypeInfo[] arguments, va_list argptr)
	{
		pushVFormat(t, msg, arguments, argptr);
		pushFormat(t, "{}({}:{}): ", loc.file, loc.line, loc.col);
		insert(t, -2);
		cat(t, 2);
		throwException(t);
	}

	private word commonCompile(void delegate() dg)
	{
		mStringTab = newTable(t);

		scope(failure)
			setStackSize(t, mStringTab);

		dg();
		insertAndPop(t, -2);
		return stackSize(t) - 1;
	}
}