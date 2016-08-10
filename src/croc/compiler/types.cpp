
#include <stdio.h>

#include "croc/compiler/ast.hpp"
#include "croc/compiler/lexer.hpp"
#include "croc/compiler/parser.hpp"
#include "croc/compiler/types.hpp"
#include "croc/util/misc.hpp"

Compiler::Compiler():
	mIsEof(false),
	mIsLoneStmt(false),
	mDanglingDoc(false),
	mStringTab(0),
	mNodes(),
	mArrays(),
	mHeapArrays(),
	mHeapArrayIdx(0),
	mTempArrays(),
	mTempArrayIdx(0)
{
	mNodes.init();
	mArrays.init();
	mHeapArrays = DArray<DArray<uint8_t> >::alloc(32);
	mTempArrays = DArray<DArray<uint8_t> >::alloc(8);
}

Compiler::~Compiler()
{
	mNodes.free();
	mArrays.free();

	for(auto &arr: mHeapArrays.slice(0, mHeapArrayIdx))
		arr.free();

	mHeapArrays.free();

	for(auto &arr: mTempArrays.slice(0, mTempArrayIdx))
		arr.free();

	mTempArrays.free();
}

void Compiler::lexException(CompileLoc loc, const char* msg, ...)
{
	va_list args;
	va_start(args, msg);
	vexception(loc, "LexicalException", msg, args);
	va_end(args);
}

void Compiler::synException(CompileLoc loc, const char* msg, ...)
{
	va_list args;
	va_start(args, msg);
	vexception(loc, "SyntaxException", msg, args);
	va_end(args);
}

void Compiler::semException(CompileLoc loc, const char* msg, ...)
{
	va_list args;
	va_start(args, msg);
	vexception(loc, "SemanticException", msg, args);
	va_end(args);
}

void Compiler::eofException(CompileLoc loc, const char* msg, ...)
{
	va_list args;
	va_start(args, msg);
	mIsEof = true;
	vexception(loc, "LexicalException", msg, args);
	va_end(args);
}

void Compiler::loneStmtException(CompileLoc loc, const char* msg, ...)
{
	va_list args;
	va_start(args, msg);
	mIsLoneStmt = true;
	vexception(loc, "SemanticException", msg, args);
	va_end(args);
}

void Compiler::danglingDocException(CompileLoc loc, const char* msg, ...)
{
	va_list args;
	va_start(args, msg);
	mDanglingDoc = true;
	vexception(loc, "LexicalException", msg, args);
	va_end(args);
}

void Compiler::vexception(CompileLoc loc, const char* exType, const char* msg, va_list args)
{
	(void)exType;
	char buf[512];
	vsnprintf(buf, 512, msg, args);
	throw CompileEx(buf, loc);
}

crocstr Compiler::newString(crocstr data)
{
	auto s = mcrocstr::alloc(data.length);
	s.slicea(data);
	return s.as<const unsigned char>();
}

crocstr Compiler::newString(const char* data)
{
	return newString(atoda(data));
}

void* Compiler::allocNode(uword size)
{
	return mNodes.alloc(size);
}

void Compiler::addArray(DArray<uint8_t> arr, DArray<uint8_t> old)
{
	removeTempArray(old);

	if(mHeapArrayIdx >= mHeapArrays.length)
		mHeapArrays.resize(mHeapArrays.length * 2);

	mHeapArrays[mHeapArrayIdx++] = arr;
}

void Compiler::addTempArray(DArray<uint8_t> arr)
{
	if(mTempArrayIdx >= mTempArrays.length)
		mTempArrays.resize(mTempArrays.length * 2);

	mTempArrays[mTempArrayIdx++] = arr;
}

void Compiler::updateTempArray(DArray<uint8_t> old, DArray<uint8_t> new_)
{
	for(auto& tmp: mTempArrays.slice(0, mTempArrayIdx))
	{
		if(tmp.ptr == old.ptr && tmp.length == old.length)
		{
			tmp = new_;
			return;
		}
	}
}

void Compiler::removeTempArray(DArray<uint8_t> arr)
{
	for(uword i = 0; i < mTempArrayIdx; i++)
	{
		auto tmp = mTempArrays[i];

		if(arr.ptr == tmp.ptr && arr.length == tmp.length)
		{
			mTempArrays[i] = mTempArrays[mTempArrayIdx - 1];
			mTempArrayIdx--;
			break;
		}
	}
}

DArray<uint8_t> Compiler::copyArray(DArray<uint8_t> arr)
{
	auto ret = DArray<uint8_t>::n(cast(uint8_t*)mArrays.alloc(arr.length), arr.length);
	ret.slicea(arr);
	return ret;
}

int Compiler::compileModule(crocstr src, crocstr name)
{
	Lexer lexer(*this);
	lexer.begin(name, src);
	Parser parser(*this, lexer);
	auto mod = parser.parseModule();
	(void)mod;
	return 0;
}

int Compiler::compileStmts(crocstr src, crocstr name)
{
	(void)src;
	(void)name;
	return 0;
}

int Compiler::compileExpr(crocstr src, crocstr name)
{
	(void)src;
	(void)name;
	return 0;
}

word Compiler::commonCompile(std::function<void()> dg)
{
	(void)dg;
	return 0;
}