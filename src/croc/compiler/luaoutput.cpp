#include "croc/compiler/luaoutput.hpp"

void LuaOutput::output(DArray<const uchar> s)
{
	mOutput.add(s);
}

//======================================================================================================================
// Whitespace
//======================================================================================================================

void LuaOutput::wordBoundary()
{
	mOnWordBoundary = true;
}

void LuaOutput::nonWordBoundary()
{
	mOnWordBoundary = false;
}

void LuaOutput::separateWords()
{
	if(mOnWordBoundary)
	{
		output(" ");
		nonWordBoundary();
	}
}

void LuaOutput::indent()
{
	mIndentLevel++;
}

void LuaOutput::dedent()
{
	assert(mIndentLevel > 0);
	mIndentLevel--;
}

void LuaOutput::outputIndent()
{
	for(uword i = 0; i < mIndentLevel; i++)
		output("\t");
}

void LuaOutput::outputNewline()
{
	output("\n");
	outputIndent();
	mCurLine++;
	nonWordBoundary();
}

void LuaOutput::outputBlankLinesUntil(CompileLoc& loc)
{
	while(mCurLine < loc.line)
		outputNewline();
}

//======================================================================================================================
// Block control
//======================================================================================================================

bool LuaOutput::isLoneBlock()
{
	return mLoneBlock.length() > 0 && mLoneBlock.last() == true;
}

void LuaOutput::beginBraceBlock(CompileLoc& loc)
{
	if(isLoneBlock())
	{
		outputWord(loc, "do");
		indent();
	}

	mLoneBlock.add(true);
}

void LuaOutput::endBraceBlock(CompileLoc& loc)
{
	mLoneBlock.pop();

	if(isLoneBlock())
	{
		dedent();
		outputWord(loc, "end");
	}
}

void LuaOutput::beginControlBlock()
{
	mLoneBlock.add(false);
	indent();
}

void LuaOutput::endControlBlock()
{
	mLoneBlock.pop();
	dedent();
}

//======================================================================================================================
// Public API
//======================================================================================================================

const char* LuaOutput::getOutput()
{
	output("\0");
	return cast(const char*)mOutput.toArray().ptr;
}

void LuaOutput::outputWord(CompileLoc& loc, DArray<const uchar> s)
{
	outputBlankLinesUntil(loc);
	separateWords();
	output(s);
	wordBoundary();
}

void LuaOutput::outputWord(Identifier* id)
{
	outputWord(id->location, id->name);
}

void LuaOutput::outputSymbol(CompileLoc& loc, DArray<const uchar> s)
{
	outputBlankLinesUntil(loc);
	output(s);
	nonWordBoundary();
}

void LuaOutput::funcName(CompileLoc& loc, DArray<Identifier*> owner, Identifier* name)
{
	outputWord(loc, "function");

	for(uword i = 0; i < owner.length; i++)
	{
		outputWord(owner[i]);
		outputSymbol(owner[i]->endLocation, ".");
	}

	outputWord(name);
}

void LuaOutput::beginFunction(CompileLoc& loc, DArray<FuncParam> params, bool isVararg)
{
	outputSymbol(loc, "(");

	params = params.sliceToEnd(1); // slice off 'this'
	uword i = 0;

	for(auto& param: params)
	{
		if(i != 0)
			outputSymbol(params[i - 1].name->location, ", ");

		outputWord(param.name);
		i++;
	}

	if(isVararg)
	{
		if(params.length > 0)
			outputSymbol(params.last().name->location, ", ");

		outputSymbol(loc, "...");
	}

	outputSymbol(loc, ")");
	beginControlBlock();
}

void LuaOutput::endFunction(CompileLoc& loc)
{
	endControlBlock();
	outputWord(loc, "end");
}

void LuaOutput::beginArgs(CompileLoc& loc)
{
	outputSymbol(loc, "(");
}

void LuaOutput::nextArg(CompileLoc& loc)
{
	outputSymbol(loc, ", ");
}

void LuaOutput::endArgs(CompileLoc& loc)
{
	outputSymbol(loc, ")");
}