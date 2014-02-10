
#include "croc/compiler/ast.hpp"
#include "croc/compiler/lexer.hpp"
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
		mHeapArrayIdx(0)
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
	}

	Compiler::~Compiler()
	{
		mNodes.free();
		mArrays.free();

		for(auto &arr: mHeapArrays.slice(0, mHeapArrayIdx))
			arr.free(t->vm->mem);

		mHeapArrays.free(t->vm->mem);
	}

	bool Compiler::asserts()
	{
		return (mFlags & CrocCompilerFlags_Asserts) != 0;
	}

	bool Compiler::typeConstraints()
	{
		return (mFlags & CrocCompilerFlags_TypeConstraints) != 0;
	}

	bool Compiler::docComments()
	{
		return (mFlags & (CrocCompilerFlags_DocTable | CrocCompilerFlags_DocDecorators)) != 0;
	}

	bool Compiler::docTable()
	{
		return (mFlags & CrocCompilerFlags_DocTable) != 0;
	}

	bool Compiler::docDecorators()
	{
		return (mFlags & CrocCompilerFlags_DocDecorators) != 0;
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

	Thread* Compiler::thread()
	{
		return t;
	}

	Memory& Compiler::mem()
	{
		return t->vm->mem;
	}

	const char* Compiler::newString(crocstr data)
	{
		auto s = String::create(t->vm, data);
		push(t, Value::from(s));
		croc_pushBool(*t, true);
		croc_idxa(*t, mStringTab);
		return s->toCString();
	}

	void* Compiler::allocNode(uword size)
	{
		return mNodes.alloc(size);
	}

	void Compiler::addArray(DArray<uint8_t> arr)
	{
		if(mHeapArrayIdx >= mHeapArrays.length)
			mHeapArrays.resize(t->vm->mem, mHeapArrays.length * 2);

		mHeapArrays[mHeapArrayIdx++] = arr;
	}

	DArray<uint8_t> Compiler::copyArray(DArray<uint8_t> arr)
	{
		auto ret = DArray<uint8_t>::n(cast(uint8_t*)mArrays.alloc(arr.length), arr.length);
		ret.slicea(arr);
		return ret;
	}

	int Compiler::compileModule(const char* src, const char* name, const char*& modName)
	{
		(void)modName;
		return commonCompile([&]()
		{
			Lexer lexer(*this);
			lexer.begin(name, src);

			while(lexer.type() != Token::EOF_)
			{
				auto loc = lexer.loc();
				printf("[%*s(%3u:%3u)] %s\n", loc.file.length, loc.file.ptr, loc.line, loc.col, lexer.tok().typeString());
				lexer.next();
			}

			// Parser parser(this, lexer);
			// auto mod = parser.parseModule();
			// moduleName = mod.names.join(".");
			// mDanglingDoc = parser.danglingDoc();

			// if(docComments)
			// {
			// 	DocGen doc(this);
			// 	mod = doc.visit(mod);

			// 	if(!docTable)
			// 		croc_popTop(*t);
			// }

			// Semantic sem(this);
			// mod = sem.visit(mod);
			// Codegen cg(this);
			// cg.visit(mod);
		});
	}

	int Compiler::compileStmts(const char* src, const char* name)
	{
		(void)src;
		(void)name;
		return 0;
		// return commonCompile([&]()
		// {
		// 	Lexer lexer(this);
		// 	lexer.begin(name, source);
		// 	Parser parser(this, lexer);
		// 	auto stmts = parser.parseStatements();
		// 	mDanglingDoc = parser.danglingDoc();

		// 	if(docComments)
		// 	{
		// 		DocGen doc(this);
		// 		stmts = doc.visitStatements(stmts);

		// 		if(!docTable)
		// 			croc_popTop(*t);
		// 	}

		// 	Semantic sem(this);
		// 	stmts = sem.visitStatements(stmts);
		// 	Codegen cg(this);
		// 	cg.codegenStatements(stmts);
		// });
	}

	int Compiler::compileExpr(const char* src, const char* name)
	{
		(void)src;
		(void)name;
		return 0;
		// return commonCompile([&]()
		// {
		// 	Lexer lexer(this);
		// 	lexer.begin(name, source);
		// 	Parser parser(this, lexer);
		// 	auto exp = parser.parseExpressionFunc();
		// 	Semantic sem(this);
		// 	exp = sem.visit(exp);
		// 	Codegen cg(this);
		// 	cg.codegenStatements(exp);
		// });
	}

	void Compiler::vexception(CompileLoc loc, const char* exType, const char* msg, va_list args)
	{
		auto ex = croc_eh_pushStd(*t, exType);
		croc_pushNull(*t);
		croc_vpushFormat(*t, msg, args);
		croc_call(*t, ex, 1);
		croc_dupTop(*t);
		croc_pushNull(*t);
		croc_eh_pushLocationObject(*t, loc.file.ptr, loc.line, loc.col);
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