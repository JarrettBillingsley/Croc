
#include "croc/api.h"
#include "croc/internal/basic.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/debug.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	// don't call this if t.calldepth == 0 or with depth >= t.calldepth
	// returns null if the given index is a tailcall or if depth is deeper than the current call depth
	ActRecord* getActRec(Thread* t, uword depth)
	{
		assert(t->arIndex != 0);

		if(depth == 0)
			return t->currentAR;

		for(word idx = t->arIndex - 1; idx >= 0; idx--)
		{
			if(depth == 0)
				return &t->actRecs[cast(uword)idx];
			else if(depth <= t->actRecs[cast(uword)idx].numTailcalls)
				return nullptr;

			depth -= (t->actRecs[cast(uword)idx].numTailcalls + 1);
		}

		return nullptr;
	}

	word pcToLine(ActRecord* ar, Instruction* pc)
	{
		int line = 0;

		auto def = ar->func->scriptFunc;
		uword instructionIndex = pc - def->code.ptr - 1;

		if(instructionIndex < def->lineInfo.length)
			line = def->lineInfo[instructionIndex];

		return line;
	}

	word getDebugLine(Thread* t, uword depth)
	{
		if(t->currentAR == nullptr)
			return 0;

		auto ar = getActRec(t, depth);

		if(ar == nullptr || ar->func == nullptr || ar->func->isNative)
			return 0;

		return pcToLine(ar, ar->pc);
	}

	word pushDebugLoc(Thread* t, ActRecord* ar)
	{
		if(ar == nullptr)
			ar = t->currentAR;

		if(ar == nullptr || ar->func == nullptr)
			return croc_eh_pushLocationObject(*t, "<no location available>", 0, CrocLocation_Unknown);
		else
		{
			pushFullNamespaceName(t, ar->func->environment);

			if(croc_len(*t, -1) == 0)
				croc_dupTop(*t);
			else
				croc_pushString(*t, ".");

			push(t, Value::from(ar->func->name));

			auto slot = t->stackIndex - 3;
			catImpl(t, slot, slot, 3);
			auto s = croc_getString(*t, -3);
			croc_pop(*t, 3);

			if(ar->func->isNative)
				return croc_eh_pushLocationObject(*t, s, 0, CrocLocation_Native);
			else
				return croc_eh_pushLocationObject(*t, s, pcToLine(ar, ar->pc), CrocLocation_Script);
		}
	}

	void callHook(Thread* t, CrocThreadHook hook)
	{
		if(!t->hooksEnabled || !t->hookFunc)
			return;

		auto savedTop = t->stackIndex;
		t->hooksEnabled = false;

		auto slot = push(t, Value::from(t->hookFunc)) + t->stackBase;
		push(t, Value::from(t));

		switch(hook)
		{
			case CrocThreadHook_Call:     croc_pushString(*t, "call"); break;
			case CrocThreadHook_TailCall: croc_pushString(*t, "tailcall"); break;
			case CrocThreadHook_Ret:      croc_pushString(*t, "ret"); break;
			case CrocThreadHook_Delay:    croc_pushString(*t, "delay"); break;
			case CrocThreadHook_Line:     croc_pushString(*t, "line"); break;
			default: assert(false);
		}

		auto failed = tryCode(t, slot, [&]
		{
			commonCall(t, slot, 0, callPrologue(t, slot, 0, 1));
		});

		t->hooksEnabled = true;
		t->stackIndex = savedTop;

		if(failed)
			croc_eh_rethrow(*t);
	}
}