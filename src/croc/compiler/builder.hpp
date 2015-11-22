#ifndef CROC_COMPILER_BUILDER_HPP
#define CROC_COMPILER_BUILDER_HPP

#include <stdio.h>

#include "croc/compiler/ast.hpp"
#include "croc/compiler/types.hpp"
#include "croc/types/base.hpp"

// #define REGPUSHPOP
// #define VARACTIVATE
// #define SHOWME
// #define WRITECODE
#define EXPSTACKCHECK

#if defined(REGPUSHPOP) && !defined(NDEBUG)
#define DEBUG_REGPUSHPOP(x) x
#else
#define DEBUG_REGPUSHPOP(x)
#endif

#if defined(VARACTIVATE) && !defined(NDEBUG)
#define DEBUG_VARACTIVATE(x) x
#else
#define DEBUG_VARACTIVATE(x)
#endif

#if defined(SHOWME) && !defined(NDEBUG)
#define DEBUG_SHOWME(x) x
#else
#define DEBUG_SHOWME(x)
#endif

#if defined(WRITECODE) && !defined(NDEBUG)
#define DEBUG_WRITECODE(x) x
#else
#define DEBUG_WRITECODE(x)
#endif

#if defined(EXPSTACKCHECK) && !defined(NDEBUG)
#define DEBUG_EXPSTACKCHECK(x) x
#else
#define DEBUG_EXPSTACKCHECK(x)
#endif

namespace croc
{
	enum class ExpType
	{
		Const,       // index = const: CTIdx
		Local,       // index = reg: RegIdx
		Temporary = Local, // we use Temporary to mean "temp register" rather than "reference to a local var"
		NewLocal,    // index = reg: RegIdx
		Upval,       // index = uv: UpvalIdx
		Global,      // index = name: CTIdx
		NewGlobal,   // index = name: CTIdx
		Index,       // index = op: RegOrCTIdx, index2 = idx: RegOrCTIdx
		Field,       // index = op: RegOrCTIdx, index2 = fieldName: RegOrCTIdx
		Slice,       // index = base: RegIdx
		Vararg,      // index = inst: InstIdx
		VarargIndex, // index = op: RegOrCTIdx
		Length,      // index = op: RegOrCTIdx
		Call,        // index = inst: InstIdx
		Yield,       // index = inst: InstIdx
		NeedsDest,   // index = inst: InstIdx
		Conflict,    // (no ops)
	};

#ifndef NDEBUG
	const char* expTypeToString(ExpType type);
#endif
	struct Exp
	{
		ExpType type;
		uword index;
		uword index2;
		// Points to first free reg after this exp. When we pop exps, we set the freeReg pointer to the regAfter of the
		// exp on the new stack top
		uword regAfter;

		Exp() :
			type(ExpType::Const),
			index(0),
			index2(0),
			regAfter(0)
		{}

		Exp(ExpType type, uword index) :
			type(type),
			index(index),
			index2(0),
			regAfter(0)
		{}

		inline bool isMultRet()
		{
			return type == ExpType::Call || type == ExpType::Yield || type == ExpType::Vararg;
		}

		inline bool isSource()
		{
			return type == ExpType::Local || type == ExpType::Const;
		}

		inline bool isDest()
		{
			return type == ExpType::Local || type == ExpType::NewLocal || type == ExpType::Upval ||
				type == ExpType::Global || type == ExpType::NewGlobal || type == ExpType::Index ||
				type == ExpType::Field || type == ExpType::Slice || type == ExpType::VarargIndex ||
				type == ExpType::Length;
		}

		inline bool haveIndex2()
		{
			return type == ExpType::Index || type == ExpType::Field;
		}

		inline bool haveRegIndex()
		{
			return type == ExpType::Local || type == ExpType::NewLocal || type == ExpType::Index ||
				type == ExpType::Field || type == ExpType::Slice || type == ExpType::VarargIndex;
		}

#ifndef NDEBUG
		void print()
		{
			printf("%s: %" CROC_SIZE_T_FORMAT ", %" CROC_SIZE_T_FORMAT ", regAfter %" CROC_SIZE_T_FORMAT "\n",
				expTypeToString(type), index, index2, regAfter);
		}
#endif
	};

	struct InstRef
	{
		word trueList;
		word falseList;
#ifndef NDEBUG
		bool inverted;
#endif
		InstRef() :
			trueList(INST_NO_JUMP),
			falseList(INST_NO_JUMP)
#ifndef NDEBUG
			, inverted(false)
#endif
		{}
	};

	struct Scope
	{
		Scope* enclosing;
		Scope* breakScope;
		Scope* continueScope;
		uword breaks;
		uword continues;
		crocstr name;
		uword varStart;
		uword regStart;
		uword firstFreeReg;
		bool hasUpval;
		uword ehlevel;

		Scope() :
			enclosing(),
			breakScope(),
			continueScope(),
			breaks(INST_NO_JUMP),
			continues(INST_NO_JUMP),
			name(),
			varStart(),
			regStart(),
			firstFreeReg(),
			hasUpval(false),
			ehlevel()
		{}
	};

	struct NamespaceDesc
	{
		uword prevReg;

		NamespaceDesc(uword prevReg) :
			prevReg(prevReg)
		{}
	};

	struct SwitchDesc
	{
		Funcdef::SwitchTable::OffsetsType offsets;
		int defaultOffset;
		uword switchPC;

		SwitchDesc() :
			offsets(),
			defaultOffset(-1),
			switchPC()
		{}
	};

	struct ForDesc
	{
		uword baseReg;
		uword beginJump;
		uword beginLoop;

		ForDesc() :
			baseReg(),
			beginJump(),
			beginLoop()
		{}
	};

	struct MethodCallDesc
	{
		uword baseReg;
		uword baseExp;

		MethodCallDesc() :
			baseReg(),
			baseExp()
		{}
	};

	struct UpvalDesc
	{
		bool isUpvalue;
		uword index;
		crocstr name;

		UpvalDesc() :
			isUpvalue(),
			index(),
			name()
		{}
	};

	struct LocVarDesc
	{
		crocstr name;
		uword pcStart;
		uword pcEnd;
		uword reg;

		CompileLoc location;
		bool isActive;

		LocVarDesc():
			name(),
			pcStart(),
			pcEnd(),
			reg(),
			location(),
			isActive()
		{}
	};

	class FuncBuilder
	{
		Compiler& c;
		Thread* t;
		FuncBuilder* mParent;
		Scope* mScope;
		uword mFreeReg = 0;
		DArray<Exp> mExpStack;
		uword mExpSP = 0;
		uword mTryCatchDepth = 0;

		FuncDef* mDef;
		CompileLoc mLocation;
		bool mIsVararg;
		crocstr mName;
		uword mNumParams;
		List<uword> mParamMasks;
		bool mIsVarret;
		List<uword> mReturnMasks;

		List<UpvalDesc> mUpvals;
		uword mStackSize;
		List<Funcdef*> mInnerFuncs;
		List<Value> mConstants;
		List<Instruction, 64> mCode;

		uword mNamespaceReg = 0;

		DArray<SwitchDesc> mInProgressSwitches;
		uword mSwitchIdx;
		List<SwitchDesc, 2> mSwitchTables;
		List<uword, 64> mLineInfo;
		List<LocVarDesc, 16> mLocVars;

		uword mDummyNameCounter = 0;

	public:
		FuncBuilder(Compiler& c, CompileLoc location, crocstr name, FuncBuilder* parent = nullptr) :
			c(c),
			t(c.thread()),
			mParent(parent),
			mScope(nullptr),
			mFreeReg(0),
			mExpStack(),
			mExpSP(0),
			mTryCatchDepth(0),
			mDef(nullptr),
			mLocation(location),
			mIsVararg(false),
			mName(name),
			mNumParams(0),
			mParamMasks(c),
			mIsVarret(true),
			mReturnMasks(c),
			mUpvals(c),
			mStackSize(0),
			mInnerFuncs(c),
			mConstants(c),
			mCode(c),
			mNamespaceReg(0),
			mInProgressSwitches(),
			mSwitchIdx(0),
			mSwitchTables(c),
			mLineInfo(c),
			mLocVars(c),
			mDummyNameCounter(0)
		{
			// let's just always make null const 0
			addNullConst();
		}

		~FuncBuilder();
		static void searchVar(FuncBuilder* fb, Identifier* name, Exp& e, bool isOriginal = true);

		void setDef(FuncDef* def);
		FuncDef* getDef();
		void setVararg(bool isVararg);
		bool isVararg();
		void setVarret(bool isVarret);
		bool isVarret();
		void setNumParams(uword numParams);
		FuncBuilder* parent();
		void printExpStack();
		void checkExpStackEmpty();
		void pushScope(Scope& s);
		void popScope(CompileLoc loc);
		void setBreakable();
		void setContinuable();
		void setScopeName(crocstr name);
		void closeScopeUpvals(CompileLoc loc);
		void addParam(Identifier* ident, uword typeMask);
		void addReturn(uword typeMask);
		uword insertLocal(Identifier* ident);
		void activateLocals(uword num);
		void beginSwitch(CompileLoc loc);
		void endSwitch();
		void addCase(CompileLoc loc, Expression* v);
		void addDefault();
		ForDesc beginFor(CompileLoc loc, std::function<void()> dg);
		ForDesc beginForeach(CompileLoc loc, std::function<void()> dg, uword containerSize);
		ForDesc beginForImpl(CompileLoc loc, std::function<void()> dg, Op opcode, uword containerSize);
		void endFor(CompileLoc loc, ForDesc desc);
		void endForeach(CompileLoc loc, ForDesc desc, uword indLength);
		void endForImpl(CompileLoc loc, ForDesc desc, Op opcode, uword indLength);
		void pop(uword num = 1);
		void dup();
		void pushNull();
		void pushBool(bool value);
		void pushInt(crocint value);
		void pushFloat(crocfloat value);
		void pushString(crocstr value);
		void pushNewGlobal(Identifier* name);
		void pushThis();
		void addUpval(Identifier* name, Exp& e);
		void pushVar(Identifier* name);
		void pushReturn(CompileLoc loc, uword returnIdx);
		void pushVararg(CompileLoc loc);
		void pushVargLen(CompileLoc loc);
		void pushClosure(FuncBuilder* fb);
		void pushTable(CompileLoc loc);
		void pushArray(CompileLoc loc, uword length);
		void pushNewLocals(uword num);
		void popToNothing();
		void assign(CompileLoc loc, uword numLhs, uword numRhs);
		void arraySet(CompileLoc loc, uword numItems, uword block);
		void arrayAppend(CompileLoc loc);
		void customParamFail(CompileLoc loc, uword paramIdx);
		void customReturnFail(CompileLoc loc, uword returnIdx);
		void assertFail(CompileLoc loc);
		uword checkObjParam(CompileLoc loc, uword paramIdx);
		uword checkObjReturn(CompileLoc loc, uword retIdx);
		uword codeIsTrue(CompileLoc loc, bool isTrue = true);
		uword codeCmp(CompileLoc loc, Comparison type);
		uword codeSwitchCmp(CompileLoc loc);
		uword codeEquals(CompileLoc loc, bool isTrue);
		uword codeIs(CompileLoc loc, bool isTrue);
		uword codeIn(CompileLoc loc, bool isTrue);
		void codeThrow(CompileLoc loc, bool rethrowing);
		void saveRets(CompileLoc loc, uword numRets);
		void addClassField(CompileLoc loc, bool isOverride);
		void addClassMethod(CompileLoc loc, bool isOverride);
		void objParamFail(CompileLoc loc, uword paramIdx);
		void objReturnFail(CompileLoc loc, uword returnIdx);
		void paramCheck(CompileLoc loc);
		void returnCheck(CompileLoc loc);
		void incDec(CompileLoc loc, AstTag type);
		void reflexOp(CompileLoc loc, AstTag type);
		void concatEq(CompileLoc loc, uword operands);
		void resolveAssignmentConflicts(CompileLoc loc, uword numVals);
		void toSource(CompileLoc loc);
		void toTemporary(CompileLoc loc);
		void newClass(CompileLoc loc, uword numBases);
		void newNamespace(CompileLoc loc);
		void newNamespaceNP(CompileLoc loc);
		void field();
		void index();
		void varargIndex();
		void length();
		void slice();
		void binOp(CompileLoc loc, AstTag type);
		void concat(CompileLoc loc, uword numOps);
		void unOp(CompileLoc loc, AstTag type);
		void as(CompileLoc loc, AsExp::Type type);
		void retAsFloat(CompileLoc loc, uword returnIdx);
		MethodCallDesc beginMethodCall();
		void updateMethodCall(MethodCallDesc& desc, uword num);
		void pushMethodCall(CompileLoc loc, MethodCallDesc& desc);
		void pushCall(CompileLoc loc, uword numArgs);
		void pushYield(CompileLoc loc, uword numArgs);
		void makeTailcall();
		NamespaceDesc beginNamespace(CompileLoc loc);
		void endNamespace(NamespaceDesc& desc);
		uword here();
		void patchJumpToHere(uword src);
		void patchContinuesTo(uword dest);
		void patchBreaksToHere();
		void patchContinuesToHere();
		void patchTrueToHere(InstRef& i);
		void patchFalseToHere(InstRef& i);
		void catToTrue(InstRef& i, uword j);
		void catToFalse(InstRef& i, uword j);
		void invertJump(InstRef& i);
		void jumpTo(CompileLoc loc, uword dest);
		uword makeJump(CompileLoc loc);
		uword codeCatch(CompileLoc loc, Scope& s);
		uword popCatch(CompileLoc loc, CompileLoc catchLoc, uword catchBegin);
		uword codeFinally(CompileLoc loc, Scope& s);
		void popFinally(CompileLoc loc, CompileLoc finallyLoc, uword finallyBegin);
		bool inTryCatch();
		void codeContinue(CompileLoc loc, crocstr name);
		void codeBreak(CompileLoc loc, crocstr name);
		void defaultReturn(CompileLoc loc, bool checkRets);
		void codeRet(CompileLoc loc);
		void codeUnwind(CompileLoc loc);
		void codeEndFinal(CompileLoc loc);
		Exp& pushExp(ExpType type = ExpType::Const, uword index = 0, uword index2 = 0);
		Exp& getExp(int idx);
		uword packRegOrConst(Exp& e);
		Exp unpackRegOrConst(uword idx);
		uword pushRegister();
		uword checkRegOK(uword reg);
		uword insertDummyLocal(CompileLoc loc, const char* fmt);
		int searchLocal(crocstr name, uword& reg);
		void deactivateLocals(uword varStart, uword regTo);
		void codeClose(CompileLoc loc, uword reg);
		void pushConst(uword index);
		uword addNullConst();
		uword addBoolConst(bool b);
		uword addIntConst(crocint x);
		uword addFloatConst(crocfloat x);
		uword addStringConst(crocstr s);
		uword addConst(Value v);
		void setMultRetReturns(uword index, uword num);
		void setJumpOffset(uword i, int offs);
		int getJumpOffset(uword i);
		int jumpDiff(uword srcIndex, uword dest);
		void patchJumpTo(uword src, uword dest);
		void patchListTo(word j, uword dest);
		uword prepareArgList(DArray<Exp> items);
		bool prepareAssignment(uword numLhs, uword numRhs, DArray<Exp>& lhs, DArray<Exp>& rhs);
		void multRetToRegs(int num);
		void popMoveTo(CompileLoc loc, Exp& dest);
		void moveToReg(CompileLoc loc, uword reg, Exp& src);
		void codeMove(CompileLoc loc, uword dest, uword src);
		uword commonCmpJump(CompileLoc loc, Op opcode, uword rd);
		uword codeRD(CompileLoc loc, Op opcode, uword dest);
		uword codeRD(CompileLoc loc, Op opcode, Exp& dest);
		void codeImm(int imm);
		void codeUImm(uword uimm);
		void codeRC(Exp& src);
		uword addInst(uword line, Instruction i);
		void addInst(Instruction i);
		void setOpcode(uword index, uword opcode);
		void setRD(uword index, uword val);
		void setImm(uword index, int val);
		void setUImm(uword index, uword val);
		uword getOpcode(uword index);
		uword getRD(uword index);
		int getImm(uword index);
		Funcdef* toFuncDef();
		void showMe();
		void disasm(Instruction*& pc, uword& insOffset, DArray<uint32_t> lineInfo);
	};
}

#endif