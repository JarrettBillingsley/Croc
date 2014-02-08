
#include <functional>
#include <iostream>
#include <fstream>
#include "croc/base/opcodes.hpp"



#include <stdlib.h>

#include "croc/api.h"
#include "croc/types.hpp"
#include "croc/base/gc.hpp"
#include "croc/internal/apichecks.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/gc.hpp"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/all.hpp"

namespace croc
{
	namespace
	{
		const size_t FinalizeLoopLimit = 1000;

		void freeAll(VM* vm)
		{
			vm->globals->clear(vm->mem);
			vm->registry->clear(vm->mem);
			vm->refTab.clear(vm->mem);

			for(auto t = vm->allThreads; t != nullptr; t = t->next)
			{
				if(t->state == CrocThreadState_Dead)
					t->reset();
			}

			gcCycle(vm, GCCycleType_Full);

			size_t limit = 0;

			do
			{
				if(limit > FinalizeLoopLimit)
					assert(false); // TODO:
					// throw new Exception("Failed to clean up - you've got an awful lot of finalizable trash or something's broken.");

				runFinalizers(vm->mainThread);
				gcCycle(vm, GCCycleType_Full);
				limit++;
			} while(!vm->toFinalize.isEmpty());

			gcCycle(vm, GCCycleType_NoRoots);

			if(!vm->toFinalize.isEmpty())
				assert(false); // TODO:
				// throw new Exception("Did you stick a finalizable object in a global metatable or something? I think you did. Stop doing that.");
		}

		void disasm(Instruction*& pc, uword& insOffset, DArray<uint32_t> lineInfo)
		{
			auto nextIns = [&insOffset, &pc]()
			{
				insOffset++;
				return *pc++;
			};

			auto rd =    [](Instruction i) { printf(" r%u", INST_GET_RD(i)); };
			auto rdimm = [](Instruction i) { printf(" %u",  INST_GET_RD(i)); };

			auto rcNoComma = [&nextIns]()
			{
				auto i = nextIns();

				if(i.uimm & INST_CONSTBIT)
					printf(" c%u", i.uimm & ~INST_CONSTBIT);
				else
					printf(" r%u", i.uimm);
			};

			auto rc = [&rcNoComma]()
			{
				printf(",");
				rcNoComma();
			};

			auto imm =  [&nextIns]() { printf(", %d", nextIns().imm);  };
			auto uimm = [&nextIns]() { printf(", %u", nextIns().uimm); };

			printf("\t[%3u:%4u] ", insOffset, lineInfo[insOffset]);
			auto i = nextIns();

			switch(INST_GET_OPCODE(i))
			{
				// (__)
				case Op_PopEH:    printf("popeh"); goto _1;
				case Op_PopEH2:  printf("popeh"); goto _1;
				case Op_EndFinal:    printf("endfinal"); goto _1;
				case Op_Ret:         printf("ret"); goto _1;
				case Op_CheckParams: printf("checkparams"); goto _1;
				_1: break;

				// (rd)
				case Op_Inc:          printf("inc"); goto _2;
				case Op_Dec:          printf("dec"); goto _2;
				case Op_VargLen:      printf("varglen"); goto _2;
				case Op_NewTable:     printf("newtab"); goto _2;
				case Op_Close:        printf("close"); goto _2;
				case Op_ObjParamFail: printf("objparamfail"); goto _2;
				case Op_AssertFail:   printf("assertfail"); goto _2;
				_2: rd(i); break;

				// (rdimm)
				case Op_Unwind: printf("unwind"); goto _3;
				_3: rdimm(i); break;

				// (rd, rs)
				case Op_Neg: printf("neg"); goto _4;
				case Op_Com: printf("com"); goto _4;
				case Op_Not: printf("not"); goto _4;
				case Op_AddEq:  printf("addeq"); goto _4;
				case Op_SubEq:  printf("subeq"); goto _4;
				case Op_MulEq:  printf("muleq"); goto _4;
				case Op_DivEq:  printf("diveq"); goto _4;
				case Op_ModEq:  printf("modeq"); goto _4;
				case Op_AndEq:  printf("andeq"); goto _4;
				case Op_OrEq:   printf("oreq"); goto _4;
				case Op_XorEq:  printf("xoreq"); goto _4;
				case Op_ShlEq:  printf("shleq"); goto _4;
				case Op_ShrEq:  printf("shreq"); goto _4;
				case Op_UShrEq: printf("ushreq"); goto _4;
				case Op_Move:            printf("mov"); goto _4;
				case Op_VargIndex:       printf("vargidx"); goto _4;
				case Op_Length:          printf("len"); goto _4;
				case Op_LengthAssign:    printf("lena"); goto _4;
				case Op_Append:          printf("append"); goto _4;
				case Op_SuperOf:         printf("superof"); goto _4;
				case Op_CustomParamFail: printf("customparamfail"); goto _4;
				case Op_Slice:           printf("slice"); goto _4;
				case Op_SliceAssign:     printf("slicea"); goto _4;
				_4: rd(i); rc(); break;

				// (rd, imm)
				case Op_For:         printf("for"); goto _5;
				case Op_ForLoop:     printf("forloop"); goto _5;
				case Op_Foreach:     printf("foreach"); goto _5;
				case Op_PushCatch:   printf("pushcatch"); goto _5;
				case Op_PushFinally: printf("pushfinal"); goto _5;
				_5: rd(i); imm(); break;

				// (rd, uimm)
				case Op_Vararg: printf("vararg"); goto _6a;
				case Op_SaveRets: printf("saverets"); goto _6a;
				case Op_VargSlice: printf("vargslice"); goto _6a;
				case Op_Closure: printf("closure"); goto _6a;
				case Op_ClosureWithEnv: printf("closurewenv"); goto _6a;
				case Op_GetUpval: printf("getu"); goto _6a;
				case Op_SetUpval: printf("setu"); goto _6a;
				_6a: rd(i); uimm(); break;

				case Op_NewGlobal: printf("newg"); goto _6b;
				case Op_GetGlobal: printf("getg"); goto _6b;
				case Op_SetGlobal: printf("setg"); goto _6b;
				case Op_NewArray: printf("newarr"); goto _6b;
				case Op_NamespaceNP: printf("namespacenp"); goto _6b;
				_6b: rd(i); printf(", c%u", nextIns().uimm); break;

				// (rdimm, rs)
				case Op_Throw: if(INST_GET_RD(i)) { printf("re"); } printf("throw"); rcNoComma(); break;
				case Op_Switch: printf("switch"); goto _7;
				_7: rdimm(i); rc(); break;

				// (rdimm, imm)
				case Op_Jmp: if(INST_GET_RD(i) == 0) { printf("nop"); } else { printf("jmp"); imm(); } break;

				// (rd, rs, rt)
				case Op_Add:  printf("add"); goto _8;
				case Op_Sub:  printf("sub"); goto _8;
				case Op_Mul:  printf("mul"); goto _8;
				case Op_Div:  printf("div"); goto _8;
				case Op_Mod:  printf("mod"); goto _8;
				case Op_Cmp3: printf("cmp3"); goto _8;
				case Op_And:  printf("and"); goto _8;
				case Op_Or:   printf("or"); goto _8;
				case Op_Xor:  printf("xor"); goto _8;
				case Op_Shl:  printf("shl"); goto _8;
				case Op_Shr:  printf("shr"); goto _8;
				case Op_UShr: printf("ushr"); goto _8;
				case Op_Index:       printf("idx"); goto _8;
				case Op_IndexAssign: printf("idxa"); goto _8;
				case Op_Field:       printf("field"); goto _8;
				case Op_FieldAssign: printf("fielda"); goto _8;
				_8: rd(i); rc(); rc(); break;

				// (__, rs, rt)
				case Op_VargIndexAssign: printf("vargidxa"); rcNoComma(); rc(); break;

				// (rd, rs, uimm)
				case Op_Cat:   printf("cat"); goto _9;
				case Op_CatEq: printf("cateq"); goto _9;
				_9: rd(i); rc(); uimm(); break;

				// (rd, rs, imm)
				case Op_CheckObjParam: printf("checkobjparam"); rd(i); rc(); imm(); break;

				// (rd, uimm, imm)
				case Op_ForeachLoop: printf("foreachloop"); rd(i); uimm(); imm(); break;

				// (rd, uimm, uimm)
				case Op_Call:     printf("call"); goto _10;
				case Op_TailCall: printf("tcall"); rd(i); uimm(); nextIns(); break;
				case Op_Yield:    printf("yield"); goto _10;
				case Op_SetArray: printf("setarray"); goto _10;
				_10: rd(i); uimm(); uimm(); break;

				// (rd, uimm, rt)
				case Op_Namespace: printf("namespace"); rd(i); printf(", c%u", nextIns().uimm); rc(); break;

				// (rdimm, rs, imm)
				case Op_IsTrue: if(INST_GET_RD(i)) { printf("istrue"); } else { printf("isfalse"); } rcNoComma(); imm(); break;

				// (rdimm, rs, rt, imm)
				case Op_Cmp:
					switch(cast(Comparison)INST_GET_RD(i))
					{
						case Comparison_LT: printf("jlt"); goto _11;
						case Comparison_LE: printf("jle"); goto _11;
						case Comparison_GT: printf("jgt"); goto _11;
						case Comparison_GE: printf("jge"); goto _11;
						default: assert(false);
					}

				case Op_Equals: if(INST_GET_RD(i)) { printf("je"); } else { printf("jne"); } goto _11;
				case Op_Is: if(INST_GET_RD(i)) { printf("jis"); } else { printf("jnis"); } goto _11;
				case Op_In: if(INST_GET_RD(i)) { printf("jin"); } else { printf("jnin"); } goto _11;
				_11: rcNoComma(); rc(); imm(); break;

				// (__, rs, rt, imm)
				case Op_SwitchCmp: printf("swcmp"); rcNoComma(); rc(); imm(); break;

				// (rd, rs, rt, uimm)
				case Op_AddMember: printf("addmember"); goto _12;
				case Op_Class:     printf("class"); goto _12;
				_12: rd(i); rc(); rc(); uimm(); break;

				// (rd, rs, rt, uimm, uimm)
				case Op_Method:     printf("method"); rd(i); rc(); rc(); uimm(); uimm(); break;
				case Op_TailMethod: printf("tmethod"); rd(i); rc(); rc(); uimm(); nextIns(); break;

				default: assert(false);
			}

			printf("\n");
		}

		void disasmFuncdef(Funcdef* fd)
		{
			auto pc = fd->code.ptr;
			auto end = pc + fd->code.length;
			uword insOffset = 0;

			while(pc < end)
				disasm(pc, insOffset, fd->lineInfo);
		}
	}

extern "C"
{
	void* croc_DefaultMemFunc(void* ctx, void* p, uword_t oldSize, uword_t newSize)
	{
		(void)ctx;
		(void)oldSize;

		if(newSize == 0)
		{
			free(p);
			return nullptr;
		}
		else
		{
			void* ret = cast(void*)realloc(p, newSize);
			assert(ret != nullptr);
			return ret;
		}
	}

	void LOAD_FUNCDEF_FROM_FILE(CrocThread* t_, const char* filename)
	{
		auto t = Thread::from(t_);
		std::ifstream ifs;
		ifs.open(filename, std::ifstream::in);

		auto readval = [&t, &ifs]() -> Value
		{
			Value v;
			char buf[256];

			switch(ifs.get())
			{
				case '0': v.type = CrocType_Null;   ifs.getline(buf, 256); break;
				case '1': v.type = CrocType_Bool;   ifs.get(); ifs >> v.mBool; ifs.getline(buf, 256);break;
				case '2': v.type = CrocType_Int;    ifs.get(); ifs >> v.mInt; ifs.getline(buf, 256); break;
				case '3': v.type = CrocType_Float;  ifs.get(); ifs >> v.mFloat; ifs.getline(buf, 256); break;
				case '5': v.type = CrocType_String; ifs.get(); ifs.getline(buf, 256); v.mString = String::create(t->vm, atoda(buf)); break;
				default: assert(false);
			}

			return v;
		};

		std::function<Funcdef*()> readit = [&readit, &t, &readval, &ifs]() -> Funcdef*
		{
			auto v = Funcdef::create(t->vm->mem);
			char buf[256];
			int tmpInt;

			ifs.getline(buf, 256); v->locFile = String::create(t->vm, atoda(buf));
			ifs >> v->locLine; ifs.getline(buf, 256);
			ifs >> v->locCol; ifs.getline(buf, 256);
			ifs >> tmpInt; v->isVararg = cast(bool)tmpInt; ifs.getline(buf, 256);
			ifs.getline(buf, 256); v->name = String::create(t->vm, atoda(buf));

			ifs >> v->numParams;

			ifs >> tmpInt; ifs.getline(buf, 256); v->paramMasks.resize(t->vm->mem, tmpInt);
			for(auto &mask: v->paramMasks) { ifs >> mask; ifs.getline(buf, 256); }

			ifs >> tmpInt; ifs.getline(buf, 256); v->upvals.resize(t->vm->mem, tmpInt);

			for(auto &uv: v->upvals)
			{
				ifs >> tmpInt; ifs.getline(buf, 256); uv.isUpval = cast(bool)tmpInt;
				ifs >> uv.index; ifs.getline(buf, 256);
			}

			ifs >> v->stackSize; ifs.getline(buf, 256);
			ifs >> tmpInt; ifs.getline(buf, 256); v->innerFuncs.resize(t->vm->mem, tmpInt);
			for(auto &inner: v->innerFuncs) { inner = readit(); }
			ifs >> tmpInt; ifs.getline(buf, 256); v->constants.resize(t->vm->mem, tmpInt);
			for(auto &c: v->constants) c = readval();

			ifs >> tmpInt; ifs.getline(buf, 256); v->code.resize(t->vm->mem, tmpInt);

			for(auto &ins: v->code) { ifs >> tmpInt; ifs.getline(buf, 256); *cast(uint16_t*)&ins = tmpInt; }
			v->environment = t->vm->globals;

			ifs >> tmpInt; ifs.getline(buf, 256); v->switchTables.resize(t->vm->mem, tmpInt);

			for(auto &st: v->switchTables)
			{
				int size;
				ifs >> size; ifs.getline(buf, 256);

				for(int i = 0; i < size; i++)
				{
					auto key = readval();
					ifs >> tmpInt; ifs.getline(buf, 256);
					*st.offsets.insert(t->vm->mem, key) = tmpInt;
				}

				ifs >> st.defaultOffset; ifs.getline(buf, 256);
			}

			ifs >> tmpInt; ifs.getline(buf, 256); v->lineInfo.resize(t->vm->mem, tmpInt);
			for(auto &l: v->lineInfo) { ifs >> l; ifs.getline(buf, 256); }
			ifs >> tmpInt; ifs.getline(buf, 256); v->upvalNames.resize(t->vm->mem, tmpInt);
			for(auto &n: v->upvalNames) { ifs.getline(buf, 256); n = String::create(t->vm, atoda(buf)); }

			ifs >> tmpInt; ifs.getline(buf, 256); v->locVarDescs.resize(t->vm->mem, tmpInt);

			for(auto &desc: v->locVarDescs)
			{
				ifs.getline(buf, 256); desc.name = String::create(t->vm, atoda(buf));
				ifs >> desc.pcStart; ifs.getline(buf, 256);
				ifs >> desc.pcEnd; ifs.getline(buf, 256);
				ifs >> desc.reg; ifs.getline(buf, 256);
			}

			return v;
		};

		auto fd = readit();
		// disasmFuncdef(fd);
		push(t, Value::from(fd));
		ifs.close();
	}

	CrocThread* croc_vm_open(CrocMemFunc memFunc, void* ctx)
	{
		auto vm = cast(VM*)memFunc(ctx, nullptr, 0, sizeof(VM));
		memset(vm, 0, sizeof(VM));

		vm->mem.init(memFunc, ctx);
		vm->disableGC();

		vm->metaTabs = DArray<Namespace*>::alloc(vm->mem, CrocType_NUMTYPES);
		vm->mainThread = Thread::create(vm);

		auto t = vm->mainThread;

		vm->metaStrings = DArray<String*>::alloc(vm->mem, MM_NUMMETAMETHODS + 2);

		for(uword i = 0; i < MM_NUMMETAMETHODS; i++)
			vm->metaStrings[i] = String::create(vm, atoda(MetaNames[i]));

		vm->ctorString = String::create(vm, atoda("constructor"));
		vm->finalizerString = String::create(vm, atoda("finalizer"));
		vm->metaStrings[vm->metaStrings.length - 2] = vm->ctorString;
		vm->metaStrings[vm->metaStrings.length - 1] = vm->finalizerString;

		vm->curThread = vm->mainThread;
		vm->globals = Namespace::create(vm->mem, String::create(vm, atoda("")));
		vm->registry = Namespace::create(vm->mem, String::create(vm, atoda("<registry>")));
		vm->unhandledEx = Function::create(vm->mem, vm->globals, String::create(vm, atoda("defaultUnhandledEx")), 1, defaultUnhandledEx, 0);

		// _G = _G._G = _G._G._G = _G._G._G._G = ...
		push(t, Value::from(vm->globals));
		croc_newGlobal(*t, "_G");

#ifdef CROC_BUILTIN_DOCS
		// TODO:docs
		Compiler.setDefaultFlags(t, Compiler.AllDocs);
#endif
		// Core libs
		initModulesLib(*t);
		initExceptionsLib(*t);
		// initGCLib(*t);

		// Safe libs
		// initBaseLib(*t);
		// initStringLib(*t);
		// initDocsLib(*t); // implicitly depends on the stringlib because of how ex_doccomments is implemented

#ifdef CROC_BUILTIN_DOCS
		// TODO:docs
		// Go back and document the libs that we loaded before the doc lib (this is easier than partly-loading the doclib and fixing things later.. OR IS IT)
		docModulesLib(*t);
		docExceptionsLib(*t);
		docGCLib(*t);
		docBaseLib(*t);
		docStringLib(*t);
#endif
		// Finish up the safe libs.
		// initHashLib(*t);
		// initMathLib(*t);
		// initObjectLib(*t);
		// initMemblockLib(*t);
		// initTextLib(*t); // depends on memblock
		// initStreamLib(*t); // depends on math, object, text
		// initArrayLib(*t);
		// initAsciiLib(*t);
		// CompilerLib.init(*t);
		// initConsoleLib(*t); // depends on stream
		// initEnvLib(*t);
		// JSONLib.init(*t); // depends on stream
		// initPathLib(*t);
		// initSerializationLib(*t); // depends on .. lots of libs :P
		// ThreadLib.init(*t);
		// TimeLib.init(*t);
		// initDoctoolsLibs(*t);

#ifdef CROC_BUILTIN_DOCS
		// TODO:docs
		Compiler.setDefaultFlags(t, Compiler.All);
#endif
		// Done, turn the GC back on and clear out any garbage we made.
		vm->enableGC();
		croc_gc_collect(*t);

		assert(t->stackIndex == 1);

		return *t;
	}

	void croc_vm_close(CrocThread* t)
	{
		auto vm = Thread::from(t)->vm;

		freeAll(vm);
		vm->metaTabs.free(vm->mem);
		vm->metaStrings.free(vm->mem);
		vm->stringTab.clear(vm->mem);
		vm->weakrefTab.clear(vm->mem);
		vm->refTab.clear(vm->mem);
		vm->stdExceptions.clear(vm->mem);
		vm->roots[0].clear(vm->mem);
		vm->roots[1].clear(vm->mem);
		vm->cycleRoots.clear(vm->mem);
		vm->toFree.clear(vm->mem);
		vm->toFinalize.clear(vm->mem);
		vm->mem.cleanup();

		if(vm->mem.totalBytes != 0)
		{
			LEAK_DETECT(vm->mem.leaks.dumpBlocks());
			printf("There are %u total unfreed bytes!\n", vm->mem.totalBytes);
		}

		LEAK_DETECT(vm->mem.leaks.cleanup());

		vm->mem.memFunc(vm->mem.ctx, vm, sizeof(VM), 0);
	}

	void croc_vm_loadUnsafeLibs(CrocThread* t, CrocUnsafeLib libs)
	{
		(void)t;
		if(libs & CrocUnsafeLib_File)  {} //FileLib.init(t);
		if(libs & CrocUnsafeLib_OS)    {} //OSLib.init(t);
		if(libs & CrocUnsafeLib_Debug) {} //DebugLib.init(t);
	}

	void croc_vm_loadAddons(CrocThread* t, CrocAddons libs)
	{
		(void)t;
		if(libs & CrocAddons_Pcre)  {} //PcreLib.init(t);
		if(libs & CrocAddons_Sdl)   {} //initSdlLib(t);
		if(libs & CrocAddons_Devil) {} //DevilLib.init(t);
		if(libs & CrocAddons_Gl)    {} //GlLib.init(t);
		if(libs & CrocAddons_Net)   {} //initNetLib(t);
	}

	void croc_vm_loadAvailableAddonsExcept(CrocThread* t, CrocAddons exclude)
	{
		(void)t;
		(void)exclude;
#ifdef CROC_PCRE_ADDON
		if(!(exclude & CrocAddons_Pcre))  {} //PcreLib.init(t);
#endif
#ifdef CROC_SDL_ADDON
		if(!(exclude & CrocAddons_Sdl))   {} //initSdlLib(t);
#endif
#ifdef CROC_DEVIL_ADDON
		if(!(exclude & CrocAddons_Devil)) {} //DevilLib.init(t);
#endif
#ifdef CROC_GL_ADDON
		if(!(exclude & CrocAddons_Gl))    {} //GlLib.init(t);
#endif
#ifdef CROC_NET_ADDON
		if(!(exclude & CrocAddons_Net))   {} //initNetLib(t);
#endif
	}

	CrocThread* croc_vm_getMainThread(CrocThread* t)
	{
		return *Thread::from(t)->vm->mainThread;
	}

	CrocThread* croc_vm_getCurrentThread(CrocThread* t)
	{
		return *Thread::from(t)->vm->curThread;
	}

	uword_t croc_vm_bytesAllocated(CrocThread* t)
	{
		return Thread::from(t)->vm->mem.totalBytes;
	}

	word_t croc_vm_pushTypeMT(CrocThread* t, CrocType type)
	{
		// ORDER CROCTYPE
		if(!(type >= CrocType_FirstUserType && type <= CrocType_LastUserType))
		{
			if(type >= 0 && type < CrocType_NUMTYPES)
				croc_eh_throwStd(t, "TypeError", "%s - Cannot get metatable for type '%s'",
					__FUNCTION__, typeToString(type));
			else
				croc_eh_throwStd(t, "ApiError", "%s - Invalid type '%u'", __FUNCTION__, type);
		}

		if(auto ns = Thread::from(t)->vm->metaTabs[cast(uword)type])
			return push(Thread::from(t), Value::from(ns));
		else
			return croc_pushNull(t);
	}

	void croc_vm_setTypeMT(CrocThread* t_, CrocType type)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);

		// ORDER CROCTYPE
		if(!(type >= CrocType_FirstUserType && type <= CrocType_LastUserType))
		{
			if(type >= 0 && type < CrocType_NUMTYPES)
				croc_eh_throwStd(t_, "TypeError", "%s - Cannot set metatable for type '%s'",
					__FUNCTION__, typeToString(type));
			else
				croc_eh_throwStd(t_, "ApiError", "%s - Invalid type '%u'", __FUNCTION__, type);
		}

		auto v = getValue(t, -1);

		if(v->type == CrocType_Namespace)
			t->vm->metaTabs[cast(uword)type] = v->mNamespace;
		else if(v->type == CrocType_Null)
			t->vm->metaTabs[cast(uword)type] = nullptr;
		else
			API_PARAM_TYPE_ERROR(-1, "metatable", "namespace|null");

		croc_popTop(t_);
	}

	word_t croc_vm_pushRegistry(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		return push(t, Value::from(t->vm->registry));
	}
} // extern "C"
}