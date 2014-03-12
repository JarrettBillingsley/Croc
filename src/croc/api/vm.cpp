
#include <stdio.h>
#include <stdlib.h>

#include "croc/api.h"
#include "croc/types/base.hpp"
#include "croc/base/gc.hpp"
#include "croc/api/apichecks.hpp"
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

		vm->ctorString = String::create(vm, ATODA("constructor"));
		vm->finalizerString = String::create(vm, ATODA("finalizer"));
		vm->metaStrings[vm->metaStrings.length - 2] = vm->ctorString;
		vm->metaStrings[vm->metaStrings.length - 1] = vm->finalizerString;

		vm->curThread = vm->mainThread;
		vm->globals = Namespace::create(vm->mem, String::create(vm, ATODA("")));
		vm->registry = Namespace::create(vm->mem, String::create(vm, ATODA("<registry>")));
		vm->unhandledEx = Function::create(vm->mem, vm->globals, String::create(vm, ATODA("defaultUnhandledEx")), 1, defaultUnhandledEx, 0);
		vm->ehFrames = DArray<EHFrame>::alloc(vm->mem, 10);
		vm->rng.seed();

		// _G = _G._G = _G._G._G = _G._G._G._G = ...
		push(t, Value::from(vm->globals));
		croc_newGlobal(*t, "_G");

#ifdef CROC_BUILTIN_DOCS
		croc_compiler_setFlags(*t, CrocCompilerFlags_AllDocs);
#endif
		// Core libs
		initModulesLib(*t);
		initExceptionsLib(*t);
		initGCLib(*t);

		// Safe libs
		initMiscLib(*t);
		initStringLib(*t);
		initDocsLib(*t); // implicitly depends on the stringlib because of how ex_doccomments is implemented

#ifdef CROC_BUILTIN_DOCS
		// Go back and document the libs that we loaded before the doc lib (this is easier than partly-loading the doclib and fixing things later.. OR IS IT)
		// docModulesLib(*t);
		// docExceptionsLib(*t);
		// docGCLib(*t);
		docMiscLib(*t);
		// docStringLib(*t);
#endif
		// Finish up the safe libs.
		initHashLib(*t);
		initMathLib(*t);
		initObjectLib(*t);
		initMemblockLib(*t);
		initTextLib(*t); // depends on memblock
		initStreamLib(*t); // depends on math, object, text
		initArrayLib(*t);
		initAsciiLib(*t);
		initCompilerLib(*t);
		initConsoleLib(*t); // depends on stream
		// initEnvLib(*t);
		// JSONLib.init(*t); // depends on stream
		// initPathLib(*t);
		// initSerializationLib(*t); // depends on .. lots of libs :P
		initThreadLib(*t);
		// TimeLib.init(*t);
		initDoctoolsLibs(*t);

#ifdef CROC_BUILTIN_DOCS
		croc_compiler_setFlags(*t, CrocCompilerFlags_All);
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
		vm->ehFrames.free(vm->mem);
		vm->mem.cleanup();

		if(vm->mem.totalBytes != 0)
		{
			LEAK_DETECT(vm->mem.leaks.dumpBlocks());
			fprintf(stderr, "There are %" CROC_SIZE_T_FORMAT " total unfreed bytes!\n", vm->mem.totalBytes);
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