#ifndef CROC_COMPILER_LUAOUTPUT_HPP
#define CROC_COMPILER_LUAOUTPUT_HPP

#include "croc/compiler/ast.hpp"
#include "croc/compiler/types.hpp"
#include "croc/util/misc.hpp"
#include "croc/util/utf.hpp"

class LuaOutput
{
private:
	Compiler& mCompiler;
	uword mCurLine;
	uword mIndentLevel;
	List<uchar, 256> mOutput;
	bool mOnWordBoundary;
	List<bool> mLoneBlock;

public:
	LuaOutput(Compiler& compiler):
		mCompiler(compiler),
		mCurLine(1),
		mIndentLevel(0),
		mOutput(compiler),
		mOnWordBoundary(false),
		mLoneBlock(compiler)
	{}

	// Whitespace
	void wordBoundary();
	void nonWordBoundary();
	void separateWords();
	void indent();
	void dedent();
	void outputIndent();
	void outputNewline();
	void outputBlankLinesUntil(CompileLoc& loc);

	// Block control
	bool isLoneBlock();
	void beginBraceBlock(CompileLoc& loc);
	void endBraceBlock(CompileLoc& loc);
	void beginControlBlock();
	void endControlBlock();

	// Public API
	const char* getOutput();

	void output(DArray<const uchar> s);
	void output(const char* s) { output(atoda(s)); }

	void outputWord(Identifier* id);
	void outputWord(CompileLoc& loc, DArray<const uchar> s);
	void outputWord(CompileLoc& loc, const char* s) { outputWord(loc, atoda(s)); }
	void outputSymbol(CompileLoc& loc, DArray<const uchar> s);
	void outputSymbol(CompileLoc& loc, const char* s) { outputSymbol(loc, atoda(s)); }

	void funcName(CompileLoc& loc, DArray<Identifier*> owner, Identifier* name);
	void beginFunction(CompileLoc& loc, DArray<FuncParam> params, bool isVararg);
	void endFunction(CompileLoc& loc);

	void beginArgs(CompileLoc& loc);
	void nextArg(CompileLoc& loc);
	void endArgs(CompileLoc& loc);
};

#endif