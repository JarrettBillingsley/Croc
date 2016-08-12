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

bool LuaOutput::isTopLevelBlock()
{
	return mLoneBlock.length() == 0;
}

void LuaOutput::beginBraceBlock()
{
	mLoneBlock.add(true);
}

void LuaOutput::beginControlBlock()
{
	mLoneBlock.add(false);
}

void LuaOutput::endCodeBlock()
{
	mLoneBlock.pop();
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

void LuaOutput::beginBlock(CompileLoc& loc)
{
	if(isLoneBlock())
		outputWord(loc, "do");

	if(!isTopLevelBlock())
		indent();

	beginBraceBlock();
}

void LuaOutput::endBlock(CompileLoc& loc)
{
	endCodeBlock();

	if(!isTopLevelBlock())
		dedent();

	if(isLoneBlock())
		outputWord(loc, "end");
}

void LuaOutput::funcName(CompileLoc& loc, Identifier* name)
{
	outputWord(loc, "function");
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
	endCodeBlock();
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