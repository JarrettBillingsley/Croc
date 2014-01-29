/******************************************************************************
This module contains the public interface to the Croc compiler.

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

module croc.compiler;

import tango.core.Vararg;
import tango.io.UnicodeFile;
import tango.text.convert.Layout;
import tango.text.Util;

import croc.api_interpreter;
import croc.api_stack;
import croc.base_alloc;
import croc.compiler_codegen;
import croc.compiler_docgen;
import croc.compiler_lexer;
import croc.compiler_parser;
import croc.compiler_semantic;
import croc.compiler_types;
import croc.types;

/**
This class encapsulates all the functionality needed for compiling Croc code.
*/
scope class Compiler : ICompiler
{
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
		Generate debug info. Currently always on.
		*/
		Debug = 4,

		/**
		Extract documentation comments and construct a documentation table that will be
		left on the stack below the compiled function/module/whatever. Does not attach runtime-
		inspectable documentation to definitions in the code, so this is useful for extracting
		docs from the code without having to run it.
		*/
		DocTable = 8,

		/**
		Extract documentation comments and insert decorators on the definitions they're
		for, to create runtime-inspectable documentation through some base library functions.
		*/
		DocDecorators = 16,

		/**
		Turn on all optional features except documentation.
		*/
		All = TypeConstraints | Asserts | Debug,

		/**
		Turn on all optional features including documentation decorators, but does not leave
		the doc table on the stack.
		*/
		AllDocs = All | DocDecorators
	}

private:
	CrocThread* t;
	uint mFlags;
	bool mIsEof;
	bool mIsLoneStmt;
	bool mDanglingDoc;
	Lexer mLexer;
	Parser mParser;
	word mStringTab;

	static const uword PageSize = 8192;

	BumpAllocator!(PageSize) mNodes;
	BumpAllocator!(PageSize) mArrays;
	void[][] mHeapArrays;
	uword mHeapArrayIdx;

// =====================================================================================================================
// Public
// =====================================================================================================================

public:

	/**
	Constructs a compiler. The given thread will be used to hold temporary data structures,
	to throw exceptions, and to return the functions that result from compilation.

	The compiler is created with either the flags that have been set for this VM with
	setDefaultFlags, or with the "All" flag if not.

	Params:
		t = The thread with which this compiler will be associated.
	*/
	this(CrocThread* t)
	{
		this.t = t;

		auto reg = getRegistry(t);
		pushString(t, "compiler.defaultFlags");

		uint flags;

		if(opin(t, -1, reg))
		{
			field(t, reg);
			flags = cast(uint)getInt(t, -1);
		}
		else
			flags = All;

		pop(t, 2);
		this(t, flags);
	}

	/**
	Same as above, but allows you to set the flags manually.

	Params:
		t = The thread with which this compiler will be associated.
		flags = A bitwise or of any code-generation flags you want to use for this compiler.
			Defaults to All.
	*/
	this(CrocThread* t, uint flags)
	{
		this.t = t;
		mFlags = flags;
		mLexer = Lexer(this);
		mParser = Parser(this, &mLexer);
		mNodes.init(&t.vm.alloc);
		mArrays.init(&t.vm.alloc);
		mHeapArrays = t.vm.alloc.allocArray!(void[])(32);
	}

	~this()
	{
		mNodes.free();
		mArrays.free();

		foreach(arr; mHeapArrays[0 .. mHeapArrayIdx])
			t.vm.alloc.freeArray(arr);

		t.vm.alloc.freeArray(mHeapArrays);
	}

	/**
	This lets you set the default compiler flags that will be used for compilers created in
	the VM that owns the given thread. If this isn't set, compilers will default to using the
	"All" flag.
	*/
	static void setDefaultFlags(CrocThread* t, uint flags)
	{
		auto reg = getRegistry(t);
		pushString(t, "compiler.defaultFlags");
		pushInt(t, flags);
		fielda(t, reg);
		pop(t);
	}

	/**
	This gets the default compiler flags for compilers created in the VM that owns the given thread.
	*/
	static uint getDefaultFlags(CrocThread* t)
	{
		auto reg = getRegistry(t);
		field(t, reg, "compiler.defaultFlags");
		auto ret = getInt(t, -1);
		pop(t, 2);
		return cast(uint)ret;
	}

	/**
	Set the compiler's code-generation flags.
	*/
	void setFlags(uint flags)
	{
		mFlags = flags;
	}

	/**
	Returns whether or not code for asserts should be generated.
	*/
	override bool asserts()
	{
		return (mFlags & Asserts) != 0;
	}

	/**
	Returns whether or not code for parameter type constraint checking should be generated.
	*/
	override bool typeConstraints()
	{
		return (mFlags & TypeConstraints) != 0;
	}

	/**
	Returns whether or not documentation will be extracted from doc comments, but does not
	say what will be done with it.
	*/
	override bool docComments()
	{
		return (mFlags & (DocTable | DocDecorators)) != 0;
	}

	/**
	Returns whether or not a documentation table will be left on the stack after compilation.
	*/
	override bool docTable()
	{
		return (mFlags & DocTable) != 0;
	}

	/**
	Returns whether or not decorators will be inserted into the code containing code documentation.
	*/
	override bool docDecorators()
	{
		return (mFlags & DocDecorators) != 0;
	}

	/**
	Returns whether or not the most recently-thrown exception was thrown due to an unexpected end-of-file.
	As an example, this is used by croc.ex_commandline to detect when more code must be entered
	to complete a code segment. A simple example of use:

-----
scope c = new Compiler(t);

try
	c.compileExpression(someCode, "test");
catch(CrocException e)
{
	auto ex = catchException(t);

	if(c.isEof())
	{
		// error was caused by an unexpected end-of-file
	}
}
-----
	*/
	override bool isEof()
	{
		return mIsEof;
	}

	/**
	Returns whether or not the most recently-thrown exception was thrown due to a no-effect expression being used
	as a statement (yes, this method has a horrible name). Its use is identical to isEof().
	*/
	override bool isLoneStmt()
	{
		return mIsLoneStmt;
	}

	/**
	Returns whether or not there was a dangling documentation comment at the end of the last-compiled item (that is,
	a documentation comment that was not attached to anything).
	*/
	override bool isDanglingDoc()
	{
		return mDanglingDoc;
	}

	override void lexException(CompileLoc loc, char[] msg, ...)
	{
		vexception(loc, "LexicalException", msg, _arguments, _argptr);
	}

	override void synException(CompileLoc loc, char[] msg, ...)
	{
		vexception(loc, "SyntaxException", msg, _arguments, _argptr);
	}

	override void semException(CompileLoc loc, char[] msg, ...)
	{
		vexception(loc, "SemanticException", msg, _arguments, _argptr);
	}

	override void eofException(CompileLoc loc, char[] msg, ...)
	{
		mIsEof = true;
		vexception(loc, "LexicalException", msg, _arguments, _argptr);
	}

	override void loneStmtException(CompileLoc loc, char[] msg, ...)
	{
		mIsLoneStmt = true;
		vexception(loc, "SemanticException", msg, _arguments, _argptr);
	}

	override CrocThread* thread()
	{
		return t;
	}

	override Allocator* alloc()
	{
		return &t.vm.alloc;
	}

	override char[] newString(char[] data)
	{
		auto s = createString(t, data);
		push(t, CrocValue(s));
		pushBool(t, true);
		idxa(t, mStringTab);
		return s.toString();
	}

	override void* allocNode(uword size)
	{
		return mNodes.alloc(size);
	}

	override void[] copyArray(void[] arr)
	{
		auto ret = mArrays.alloc(arr.length)[0 .. arr.length];
		ret[] = arr[];
		return ret;
	}

	override void addArray(void[] arr)
	{
		if(mHeapArrayIdx >= mHeapArrays.length)
			t.vm.alloc.resizeArray(mHeapArrays, mHeapArrays.length * 2);

		mHeapArrays[mHeapArrayIdx++] = arr;
	}

	/**
	Compile a source code file into a function closure. Takes the path to the source file, compiles
	that file, and pushes the top-level closure onto the stack. The environment of the closure is
	just set to the global namespace of the compiler's thread; you must create and set a namespace
	for the module function before calling it.

	You shouldn't have to deal with this function that much. Most of the time the compilation of
	modules should be handled for you by the import system.

	Params:
		filename = The filename of the source file to compile.

	Returns:
		The stack index of the newly-pushed function closure that represents the top-level function
		of the module. The moduleName parameter holds the canonical name of the module given by the
		module statement at the beginning of it.
	*/
	word compileModule(char[] filename, out char[] moduleName)
	{
		scope file = new UnicodeFile!(char)(filename, Encoding.Unknown);
		auto src = file.read();

		scope(exit)
			delete src;

		return compileModule(src, filename, moduleName);
	}

	/**
	Same as above, but compiles from a string holding the source rather than from a file.

	Params:
		source = The source code as a string.
		name = The name which should be used as the source name in compiler error message. Takes the
			place of the filename when compiling from a source file.

	Returns:
		The stack index of the newly-pushed function closure that represents the top-level function
		of the module. The moduleName parameter holds the canonical name of the module given by the
		module statement at the beginning of it.
	*/
	word compileModule(char[] source, char[] name, out char[] moduleName)
	{
		return commonCompile(
		{
			mLexer.begin(name, source);
			auto mod = mParser.parseModule();
			moduleName = mod.names.join(".");
			mDanglingDoc = mParser.danglingDoc();

			if(docComments)
			{
				scope doc = new DocGen(this);
				mod = doc.visit(mod);

				if(!docTable)
					pop(t);
			}

			scope sem = new Semantic(this);
			mod = sem.visit(mod);

			scope cg = new Codegen(this);
			cg.visit(mod);
		});
	}

	/**
	Compile a list of statements into a function which takes a variadic number of arguments. The environment
	of the compiled function closure is set to the globals of the compiler's thread.

	Params:
		source = The source code as a string.
		name = The name to use as the source name for compilation errors.

	Returns:
		The stack index of the newly-pushed function closure.
	*/
	word compileStatements(char[] source, char[] name)
	{
		return commonCompile(
		{
			mLexer.begin(name, source);
			auto fd = mParser.parseStatements(name);
			mDanglingDoc = mParser.danglingDoc();

			if(docComments)
			{
				scope doc = new DocGen(this);
				fd = doc.visitStatements(fd);

				if(!docTable)
					pop(t);
			}

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
	word compileExpression(char[] source, char[] name)
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

// =====================================================================================================================
// Private
// =====================================================================================================================

private:
	void vexception(ref CompileLoc loc, char[] exType, char[] msg, TypeInfo[] arguments, va_list argptr)
	{
		auto ex = getStdException(t, exType);
		pushNull(t);
		pushVFormat(t, msg, arguments, argptr);
		call(t, ex, 1);
		dup(t);
		pushNull(t);
		pushLocationObject(t, loc.file, loc.line, loc.col);
		methodCall(t, -3, "setLocation", 0);
		throwException(t);
	}

	word commonCompile(void delegate() dg)
	{
		mStringTab = newTable(t);

		scope(failure)
			setStackSize(t, mStringTab);

		dg();

		if(docTable)
		{
			insert(t, -3);
			insert(t, -3);
			pop(t);
		}
		else
			insertAndPop(t, -2);

		return stackSize(t) - 1;
	}
}