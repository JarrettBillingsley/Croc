/******************************************************************************
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
import minid.string;
import minid.types;

scope class Compiler : ICompiler
{
	mixin ICompilerMixin;

	enum
	{
		None = 0,
		TypeConstraints = 1,
		Asserts = 2,

		All = TypeConstraints | Asserts
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

	public void setFlags(uint flags)
	{
		mFlags = flags;
	}

	public override bool asserts()
	{
		return (mFlags & Asserts) != 0;
	}

	public override bool typeConstraints()
	{
		return (mFlags & TypeConstraints) != 0;
	}

	public override bool isEof()
	{
		return mIsEof;
	}
	
	public override bool isLoneStmt()
	{
		return mIsLoneStmt;
	}

	public override void exception(ref CompileLoc loc, char[] msg, ...)
	{
		vexception(loc, msg, _arguments, _argptr);
	}

	public override void eofException(ref CompileLoc loc, char[] msg, ...)
	{
		mIsEof = true;
		vexception(loc, msg, _arguments, _argptr);
	}

	public override void loneStmtException(ref CompileLoc loc, char[] msg, ...)
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
		auto s = string.create(t.vm, data);
		pushStringObj(t, s);
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
		scope path = new FilePath(filename);
		scope file = new UnicodeFile!(char)(path, Encoding.Unknown);
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
			fd = sem.visit(fd);

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
		{
			if(stackSize(t) >= mStringTab + 1)
				pop(t, stackSize(t) - mStringTab);
		}

		dg();
		insertAndPop(t, -2);
		return stackSize(t) - 1;
	}

/+
	/**
	Parses a JSON string into a MiniD value and returns that value.  Just like the MiniD baselib
	function.
	*/
	public MDValue loadJSON(char[] source)
	{
		scope lexer = new Lexer("JSON", source, true);
	
		if(lexer.type == Token.LBrace)
			return parseTableCtorExpJSON(lexer);
		else
			return parseArrayCtorExpJSON(lexer);
	}
+/
}