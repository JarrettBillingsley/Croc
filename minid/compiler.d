/******************************************************************************
The MiniD compiler.  This is, unsurprisingly, the largest part of the implementation,
although it has a very small public interface.

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

	public override void exception(ref CompileLoc loc, dchar[] msg, ...)
	{
		vexception(loc, msg, _arguments, _argptr);
	}

	public override void eofException(ref CompileLoc loc, dchar[] msg, ...)
	{
		mIsEof = true;
		vexception(loc, msg, _arguments, _argptr);
	}

	public override void loneStmtException(ref CompileLoc loc, dchar[] msg, ...)
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
	
	public override dchar[] newString(dchar[] data)
	{
		auto s = string.create(t.vm, data);
		pushStringObj(t, s);
		pushBool(t, true);
		idxa(t, mStringTab);
		return s.toString32();
	}

	public word testParse(char[] filename)
	{
		mStringTab = newTable(t);
		
		scope(failure)
		{
			assert(stackSize(t) - 1 == mStringTab, "OH NO String table is not in the right place!");
			pop(t);
		}

		scope path = new FilePath(filename);
		scope file = new UnicodeFile!(dchar)(path, Encoding.Unknown);
		auto src = file.read();

		scope(exit)
			delete src;

		mLexer.begin(Utf.toString32(filename), src);
		auto mod = mParser.parseModule();

		scope sem = new Semantic(this);
		mod = sem.visit(mod);

		scope cg = new Codegen(this);
		mod = cg.visit(mod);

		insert(t, -2);
		pop(t);
		
		return stackSize(t) - 1;
	}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

	private void vexception(ref CompileLoc loc, dchar[] msg, TypeInfo[] arguments, va_list argptr)
	{
		pushVFormat(t, msg, arguments, argptr);
		pushFormat(t, "{}({}:{}): ", loc.file, loc.line, loc.col);
		insert(t, -2);
		cat(t, 2);
		throwException(t);
	}
/+
	/**
	Compile a source code file into a binary module.  Takes the path to the source file and returns
	the compiled module, which can be loaded into a context.

	You shouldn't have to deal with this function that much.  Most of the time the compilation of
	modules should be handled for you by the import system in MDContext.
	*/
	public OldFuncDef* compileModule(char[] filename)
	{
		scope path = new FilePath(filename);
		scope file = new UnicodeFile!(dchar)(path, Encoding.Unknown);
		return compileModule(file.read(), path.file);
	}

	/**
	Compile a module from a string containing the source code.
	
	Params:
		source = The source code as a string.
		name = The name which should be used as the source name in compiler error message.  Takes the
			place of the filename when compiling from a source file.
	
	Returns:
		The compiled module.
	*/
	public OldFuncDef* compileModule(dchar[] source, char[] name)
	{
		scope lexer = new Lexer(name, source);
		return parseModule(lexer).codeGen(this);
	}
	
	/**
	Compile a list of statements into a function body which takes a variadic number of arguments.  Kind
	of like a module without the module statement.  
	
	Params:
		source = The source code as a string.
		name = The name to use as the source name for compilation errors.
			
	Returns:
		The compiled function.
	*/
	public OldFuncDef* compileStatements(dchar[] source, char[] name)
	{
		scope lexer = new Lexer(name, source);
		List!(Statement) s;
	
		while(lexer.type != Token.EOF)
			s.add(parseStatement(lexer));
	
		lexer.expect(Token.EOF);
	
		Statement[] stmts = s.toArray();
	
		FuncState fs = new FuncState(CompileLoc(utf.toString32(name), 1, 1), utf.toString32(name), null, this);
		fs.mIsVararg = true;
		
		try
		{
			foreach(stmt; stmts)
				visit(stmt).codeGen(fs);
		
			if(stmts.length == 0)
			{
				fs.codeI(1, Op.Ret, 0, 1);
				fs.popScope(1);
			}
			else
			{
				fs.codeI(stmts[$ - 1].endLocation.line, Op.Ret, 0, 1);
				fs.popScope(stmts[$ - 1].endLocation.line);
			}
		}
		finally
		{
			debug(SHOWME)
			{
				fs.showMe(); Stdout.flush;
			}
			
			debug(PRINTEXPSTACK)
				fs.printExpStack();
		}
	
		return fs.toFuncDef();
	}
	
	/**
	Compile a single expression into a function which returns the value of that expression when called.
	
	Params:
		source = The source code as a string.
		name = The name to use as the source name for compilation errors.
		
	Returns:
		The compiled function.
	*/
	public OldFuncDef* compileExpression(dchar[] source, char[] name)
	{
		scope lexer = new Lexer(name, source);
		Expression e = parseExpression(lexer);
	
		if(lexer.type != Token.EOF)
			throw new OldCompileException(lexer.loc, "Extra unexpected code after expression");
			
		FuncState fs = new FuncState(CompileLoc(utf.toString32(name), 1, 1), utf.toString32(name), null, this);
		fs.mIsVararg = true;
	
		auto ret = (new ReturnStmt(e)).fold();
	
		try
		{
			ret.codeGen(fs);
			fs.codeI(ret.endLocation.line, Op.Ret, 0, 1);
			fs.popScope(ret.endLocation.line);
		}
		finally
		{
			debug(SHOWME)
			{
				fs.showMe(); Stdout.flush;
			}
			
			debug(PRINTEXPSTACK)
				fs.printExpStack();
		}
	
		return fs.toFuncDef();
	}
	
	/**
	Parses a JSON string into a MiniD value and returns that value.  Just like the MiniD baselib
	function.
	*/
	public MDValue loadJSON(dchar[] source)
	{
		scope lexer = new Lexer("JSON", source, true);
	
		if(lexer.type == Token.LBrace)
			return parseTableCtorExpJSON(lexer);
		else
			return parseArrayCtorExpJSON(lexer);
	}
+/
}