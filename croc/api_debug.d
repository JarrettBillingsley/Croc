/******************************************************************************
This module contains public and private debugging APIs.

License:
Copyright (c) 201 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module croc.api_debug;

import croc.api_checks;
import croc.api_interpreter;
import croc.api_stack;
import croc.base_opcodes;
import croc.interpreter;
import croc.types;
import croc.types_thread;
import croc.utils;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

/**
Sets or removes the debugging hook function for the given thread.

The hook function is used to "hook" into various points in the execution of Croc scripts.
When the hook function is called, you can use the other debugging APIs to get information
about the call stack, the local variables and upvalues of functions on the call stack,
line information etc. This way you can write a debugger for Croc scripts.

There are a few different kind of events that you can hook into. You can only have one hook
function on a thread, and that function will respond to all the types of events that you set
it to.

The kinds of events that you can hook into are listed in the CrocThread.Hook enumeration, and
include the following:

$(UL
	$(LI $(B CrocThread.Hook.Call) - This hook occurs when a function is just about to be
		called. The top of the call stack will be the function that is about to be called,
		but the hook occurs before execution begins.)

	$(LI $(B CrocThread.Hook.Ret) - This hook occurs when a function is just about to return.
		The hook is called just before the return actually occurs, so the top of the call stack
		will be the function that is about to return. If you subscribe the hook function to
		this event, you will also get tail return events.)

	$(LI $(B CrocThread.Hook.TailRet) - This hook occurs immediately after "return" hooks if the
		returning function has been tailcalled. One "tail return" hook is called for each tailcall
		that occurred. No real useful information will be available. If you subscribe the
		hook function to this event, you will also get normal return events.)

	$(LI $(B CrocThread.Hook.Delay) - This hook occurs after a given number of Croc instructions
		have executed. You set this delay as a parameter to setHookFunc, and if the delay is set
		to 0, this hook is not called. This hook is also only ever called in Croc script functions.)

	$(LI $(B CrocThread.Hook.Line) - This hook occurs when execution of a script function reaches
		a new source line. This is called before the first instruction associated with the given
		line occurs. It's also called immediately after a function begins executing (before its
		first instruction executes) or if a jump to the beginning of a loop occurs.)
)

This function can be used to set or unset the hook function for the given thread. In either case,
it expects for there to be one value at the top of the stack, which it will pop. The value must
be a function or 'null'. To unset the hook function, either have 'null' on the stack, or pass 0
for the mask parameter.

When the hook function is called, the thread that the hook is being called on is passed as the 'this'
parameter, and one parameter is passed. This parameter is a string containing one of the following:
"call", "ret", "tailret", "delay", or "line", according to what kind of hook this is. The hook function
is not required to return any values.

Params:
	mask = A bitwise OR-ing of the members of the CrocThread.Hook enumeration as described above.
		The Delay value is ignored and will instead be set or unset based on the hookDelay parameter.
		If you have either the Ret or TailRet values, the function will be registered for all
		returns. If this parameter is 0, the hook function will be removed from the thread.

	hookDelay = If this is nonzero, the Delay hook will be called every hookDelay Croc instructions.
		Otherwise, if it's 0, the Delay hook will be disabled.
*/
void setHookFunc(CrocThread* t, ubyte mask, uint hookDelay)
{
	mixin(apiCheckNumParams!("1"));

	auto f = getFunction(t, -1);

	if(f is null && !isNull(t, -1))
		mixin(apiParamTypeError!("-1", "hook function", "function|null"));

	if(f is null || mask == 0)
	{
		t.hookDelay = 0;
		t.hookCounter = 0;
		thread.setHookFunc(t.vm.alloc, t, null);
		t.hooks = 0;
	}
	else
	{
		if(hookDelay == 0)
			mask &= ~CrocThread.Hook.Delay;
		else
			mask |= CrocThread.Hook.Delay;

		if(mask & CrocThread.Hook.TailRet)
		{
			mask |= CrocThread.Hook.Ret;
			mask &= ~CrocThread.Hook.TailRet;
		}

		t.hookDelay = hookDelay;
		t.hookCounter = hookDelay;
		thread.setHookFunc(t.vm.alloc, t, f);
		t.hooks = mask;
	}

	pop(t);
}

/**
Pushes the hook function associated with the given thread, or null if no hook function is set for it.
*/
word getHookFunc(CrocThread* t)
{
	if(t.hookFunc is null)
		return pushNull(t);
	else
		return push(t, CrocValue(t.hookFunc));
}

/**
Gets a bitwise OR-ing of all the hook types set for this thread, as declared in the CrocThread.Hook
enumeration. Note that the CrocThread.Hook.TailRet flag will never be set, as tail return events
are also covered by CrocThread.Hook.Ret.
*/
ubyte getHookMask(CrocThread* t)
{
	return t.hooks;
}

/**
Gets the hook function delay, which is the number of instructions between each "Delay" hook event.
If the hook delay is 0, the delay hook event is disabled.
*/
uint getHookDelay(CrocThread* t)
{
	return t.hookDelay;
}

debug
{
	import tango.io.Stdout;

	/**
	$(B Debug mode only.)  Prints out the contents of the stack to Stdout in the following format:

-----
[xxx:yyyy]: val: type
-----

	Where $(I xxx) is the absolute stack index; $(I yyyy) is the stack index relative to the currently-executing function's
	stack frame (negative numbers for lower slots, 0 is the first slot of the stack frame); $(I val) is a raw string
	representation of the value in that slot; and $(I type) is the type of that value.
	*/
	void printStack(CrocThread* t, bool wholeStack = false)
	{
		Stdout.newline;
		Stdout("-----Stack Dump-----").newline;

		auto tmp = t.stackBase;
		t.stackBase = 0;
		auto top = t.stackIndex;

		for(uword i = wholeStack ? 0 : tmp; i < top; i++)
		{
			// ORDER CROCVALUE TYPE
			if(t.stack[i].type >= CrocValue.Type.FirstUserType && t.stack[i].type <= CrocValue.Type.LastUserType)
			{
				pushToString(t, i, true);
				pushTypeString(t, i);
				Stdout.formatln("[{,3}:{,4}]: '{}': {}", i, cast(word)i - cast(word)tmp, getString(t, -2), getString(t, -1));
				pop(t, 2);
			}
			else
				Stdout.formatln("[{,3}:{,4}]: {:x16}: {:x}", i, cast(word)i - cast(word)tmp, *cast(ulong*)&t.stack[i].mInt, t.stack[i].type);
		}

		t.stackBase = tmp;

		Stdout.newline;
	}

	/**
	$(B Debug mode only.)  Prints out the call stack in reverse, starting from the currently-executing function and
	going back, in the following format (without quotes; I have to put them to keep DDoc happy):

-----
"Record: name"
	"Base: base"
	"Saved Top: top"
	"Vararg Base: vargBase"
	"Returns Slot: retSlot"
	"Num Returns: numRets"
-----

	Where $(I name) is the name of the function at that level; $(I base) is the absolute stack index of where this activation
	record's stack frame begins; $(I top) is the absolute stack index of the end of its stack frame; $(I vargBase) is the
	absolute stack index of where its variadic args (if any) begin; $(I retSlot) is the absolute stack index where return
	values (if any) will started to be copied upon that function returning; and $(I numRets) being the number of returns that
	the calling function expects it to return (-1 meaning "as many as possible").

	This only prints out the current thread's call stack. It does not take coroutine resumes and yields into account (since
	that's pretty much impossible).
	*/
	void printCallStack(CrocThread* t)
	{
		Stdout.newline;
		Stdout("-----Call Stack-----").newline;

		for(word i = t.arIndex - 1; i >= 0; i--)
		{
			with(t.actRecs[i])
			{
				Stdout.formatln("Record {}", func.name.toString());
				Stdout.formatln("\tBase: {}", base);
				Stdout.formatln("\tSaved Top: {}", savedTop);
				Stdout.formatln("\tVararg Base: {}", vargBase);
				Stdout.formatln("\tReturns Slot: {}", returnSlot);
				Stdout.formatln("\tNum Returns: {}", numReturns);
			}
		}

		Stdout.newline;
	}
}

// ================================================================================================================================================
// Package
// ================================================================================================================================================

package:

// don't call this if t.calldepth == 0 or with depth >= t.calldepth
// returns null if the given index is a tailcall or if depth is deeper than the current call depth
ActRecord* getActRec(CrocThread* t, uword depth)
{
	assert(t.arIndex != 0);

	if(depth == 0)
		return t.currentAR;

	for(word idx = t.arIndex - 1; idx >= 0; idx--)
	{
		if(depth == 0)
			return &t.actRecs[cast(uword)idx];
		else if(depth <= t.actRecs[cast(uword)idx].numTailcalls)
			return null;

		depth -= (t.actRecs[cast(uword)idx].numTailcalls + 1);
	}

	return null;
}

int pcToLine(ActRecord* ar, Instruction* pc)
{
	int line = 0;

	auto def = ar.func.scriptFunc;
	uword instructionIndex = pc - def.code.ptr - 1;

	if(instructionIndex < def.lineInfo.length)
		line = def.lineInfo[instructionIndex];

	return line;
}

int getDebugLine(CrocThread* t, uword depth = 0)
{
	if(t.currentAR is null)
		return 0;

	auto ar = getActRec(t, depth);

	if(ar is null || ar.func is null || ar.func.isNative)
		return 0;

	return pcToLine(ar, ar.pc);
}

word pushDebugLoc(CrocThread* t, ActRecord* ar = null)
{
	if(ar is null)
		ar = t.currentAR;

	if(ar is null || ar.func is null)
		return pushLocationObject(t, "<no location available>", 0, CrocLocation.Unknown);
	else
	{
		pushNamespaceNamestring(t, ar.func.environment);

		if(getString(t, -1) == "")
			dup(t);
		else
			pushString(t, ".");

		push(t, CrocValue(ar.func.name));

		auto slot = t.stackIndex - 3;
		catImpl(t, slot, slot, 3);
		auto s = getString(t, -3);
		pop(t, 3);

		if(ar.func.isNative)
			return pushLocationObject(t, s, 0, CrocLocation.Native);
		else
			return pushLocationObject(t, s, pcToLine(ar, ar.pc), CrocLocation.Script);
	}
}