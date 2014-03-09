
#include "croc/compiler/codegen.hpp"
#include "croc/compiler/ast.hpp"
#include "croc/compiler/lexer.hpp"
#include "croc/compiler/parser.hpp"
#include "croc/compiler/semantic.hpp"
#include "croc/compiler/types.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"

namespace croc
{
	const char* CompilerRegistryFlags = "compiler.defaultFlags";

	Compiler::Compiler(Thread* t):
		t(t),
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
		this->t = t;

		auto reg = croc_vm_pushRegistry(*t);
		croc_pushString(*t, CompilerRegistryFlags);

		if(croc_in(*t, -1, reg))
		{
			croc_fieldStk(*t, reg);
			mFlags = cast(uword)croc_getInt(*t, -1);
		}
		else
			mFlags = CrocCompilerFlags_All;

		croc_pop(*t, 2);

		mNodes.init(t->vm->mem);
		mArrays.init(t->vm->mem);
		mHeapArrays = DArray<DArray<uint8_t> >::alloc(t->vm->mem, 32);
		mTempArrays = DArray<DArray<uint8_t> >::alloc(t->vm->mem, 8);
	}

	Compiler::~Compiler()
	{
		mNodes.free();
		mArrays.free();

		for(auto &arr: mHeapArrays.slice(0, mHeapArrayIdx))
			arr.free(t->vm->mem);

		mHeapArrays.free(t->vm->mem);

		for(auto &arr: mTempArrays.slice(0, mTempArrayIdx))
			arr.free(t->vm->mem);

		mTempArrays.free(t->vm->mem);
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

	Thread* Compiler::thread()
	{
		return t;
	}

	Memory& Compiler::mem()
	{
		return t->vm->mem;
	}

	crocstr Compiler::newString(crocstr data)
	{
		auto s = String::create(t->vm, data);
		push(t, Value::from(s));
		croc_pushBool(*t, true);
		croc_idxa(*t, mStringTab);
		return s->toDArray();
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
			mHeapArrays.resize(t->vm->mem, mHeapArrays.length * 2);

		mHeapArrays[mHeapArrayIdx++] = arr;
	}

	void Compiler::addTempArray(DArray<uint8_t> arr)
	{
		if(mTempArrayIdx >= mTempArrays.length)
			mTempArrays.resize(t->vm->mem, mTempArrays.length * 2);

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

	int Compiler::compileModule(crocstr src, crocstr name, crocstr& modName)
	{
		(void)modName;
		return commonCompile([&]()
		{
			Lexer lexer(*this);
			lexer.begin(name, src);
			Parser parser(*this, lexer);
			auto mod = parser.parseModule();
			modName = mod->name;

			if(docComments())
			{
			// 	DocGen doc(this);
			// 	mod = doc.visit(mod);

				croc_table_new(*t, 0); // temp

				if(!docTable())
					croc_popTop(*t);
			}

			Semantic sem(*this);
			mod = sem.visit(mod);
			Codegen cg(*this);
			cg.visit(mod);
		});
	}

	int Compiler::compileStmts(crocstr src, crocstr name)
	{
		return commonCompile([&]()
		{
			Lexer lexer(*this);
			lexer.begin(name, src);
			Parser parser(*this, lexer);
			auto stmts = parser.parseStatements(name);

			if(docComments())
			{
			// 	DocGen doc(this);
			// 	stmts = doc.visitStatements(stmts);

				croc_table_new(*t, 0); // temp

				if(!docTable())
					croc_popTop(*t);
			}

			Semantic sem(*this);
			stmts = sem.visit(stmts);
			Codegen cg(*this);
			cg.codegenStatements(stmts);
		});
	}

	int Compiler::compileExpr(crocstr src, crocstr name)
	{
		return commonCompile([&]()
		{
			Lexer lexer(*this);
			lexer.begin(name, src);
			Parser parser(*this, lexer);
			auto exp = parser.parseExpressionFunc(name);
			Semantic sem(*this);
			exp = sem.visit(exp);
			Codegen cg(*this);
			cg.codegenStatements(exp);
		});
	}

	void Compiler::vexception(CompileLoc loc, const char* exType, const char* msg, va_list args)
	{
		auto ex = croc_eh_pushStd(*t, exType);
		croc_pushNull(*t);
		croc_vpushFormat(*t, msg, args);
		croc_call(*t, ex, 1);
		croc_dupTop(*t);
		croc_pushNull(*t);
		croc_eh_pushLocationObject(*t, cast(const char*)loc.file.ptr, loc.line, loc.col);
		croc_methodCall(*t, -3, "setLocation", 0);
		croc_eh_throw(*t);
	}

	word Compiler::commonCompile(std::function<void()> dg)
	{
		mStringTab = croc_table_new(*t, 16);

		auto failed = tryCode(t, mStringTab, dg);

		if(failed)
		{
			if(mDanglingDoc)
				return CrocCompilerReturn_DanglingDoc;
			else if(mIsEof)
				return CrocCompilerReturn_UnexpectedEOF;
			else if(mIsLoneStmt)
				return CrocCompilerReturn_LoneStatement;
			else
				return CrocCompilerReturn_Error;
		}

		if(docTable())
		{
			croc_insert(*t, -3);
			croc_insert(*t, -3);
			croc_popTop(*t);
		}
		else
			croc_insertAndPop(*t, -2);

		return croc_getStackSize(*t) - 1;
	}
}