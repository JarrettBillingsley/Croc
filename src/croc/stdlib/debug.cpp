
#include <limits>

#include "croc/api.h"
#include "croc/internal/debug.hpp"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"
#include "croc/util/str.hpp"

namespace croc
{
	namespace
	{
	uint8_t strToMask(crocstr str)
	{
		uint8_t mask = 0;

		if(strLocateChar(str, 'c') != str.length) mask |= CrocThreadHook_Call;
		if(strLocateChar(str, 'r') != str.length) mask |= CrocThreadHook_Ret;
		if(strLocateChar(str, 'l') != str.length) mask |= CrocThreadHook_Line;

		return mask;
	}

	crocstr maskToStr(mcrocstr buf, uint8_t mask)
	{
		uword i = 0;

		if(mask & CrocThreadHook_Call)  buf[i++] = 'c';
		if(mask & CrocThreadHook_Ret)   buf[i++] = 'r';
		if(mask & CrocThreadHook_Line)  buf[i++] = 'l';
		if(mask & CrocThreadHook_Delay) buf[i++] = 'd';

		return buf.slice(0, i);
	}

	CrocThread* getThreadParam(CrocThread* t, word& arg)
	{
		if(croc_isValidIndex(t, 1) && croc_isThread(t, 1))
		{
			arg = 1;
			return croc_getThread(t, 1);
		}
		else
		{
			arg = 0;
			return t;
		}
	}

	ActRecord* getAR(CrocThread* t, CrocThread* thread, crocint depth)
	{
		auto maxDepth = croc_thread_getCallDepth(thread);

		if(t == thread)
		{
			// ignore call to whatever this function is
			if(depth < 0 || depth >= maxDepth - 1)
				croc_eh_throwStd(t, "RangeError", "invalid call depth %" CROC_INTEGER_FORMAT, depth);

			return getActRec(Thread::from(thread), cast(uword)depth + 1);
		}
		else
		{
			if(depth < 0 || depth >= maxDepth)
				croc_eh_throwStd(t, "RangeError", "invalid call depth %" CROC_INTEGER_FORMAT, depth);

			return getActRec(Thread::from(thread), cast(uword)depth);
		}
	}

	Function* getFuncParam(CrocThread* t, CrocThread* thread, word arg)
	{
		if(croc_isInt(t, arg))
			return getAR(t, thread, croc_getInt(t, arg))->func;
		else if(croc_isFunction(t, arg))
			return getFunction(Thread::from(t), arg);
		else
			croc_ex_paramTypeError(t, arg, "int|function");

		assert(false);
		return nullptr; // dummy
	}

	Value* findLocal(CrocThread* t, CrocThread* thread, word arg, ActRecord* ar)
	{
		crocint idx = 1;
		String* name;

		if(croc_isInt(t, arg + 2))
			idx = croc_getInt(t, arg + 2);
		else if(croc_isString(t, arg + 2))
			name = getStringObj(Thread::from(t), arg + 2);
		else
			croc_ex_paramTypeError(t, arg + 2, "int|string");

		if(idx < 0 || ar->func == nullptr || ar->func->isNative)
			croc_eh_throwStd(t, "BoundsError", "invalid local index '%" CROC_INTEGER_FORMAT "'", idx);

		auto originalIdx = idx;
		auto pc = cast(uword)(ar->pc - ar->func->scriptFunc->code.ptr);

		for(auto &var: ar->func->scriptFunc->locVarDescs)
		{
			if(pc >= var.pcStart && pc < var.pcEnd)
			{
				if(name == nullptr)
				{
					if(idx == 0)
						return &Thread::from(thread)->stack[ar->base + var.reg];

					idx--;
				}
				else if(var.name == name)
					return &Thread::from(thread)->stack[ar->base + var.reg];
			}
		}

		if(name == nullptr)
			croc_eh_throwStd(t, "BoundsError", "invalid local index '%" CROC_INTEGER_FORMAT "'", originalIdx);
		else
			croc_eh_throwStd(t, "NameError", "invalid local name '%s'", name->toCString());

		return nullptr; // dummy
	}

	Value* findUpval(CrocThread* t, CrocThread* thread, word arg)
	{
		auto func = getFuncParam(t, thread, arg + 1);

		if(func == nullptr)
			croc_eh_throwStd(t, "ValueError", "invalid function");

		if(croc_isInt(t, arg + 2))
		{
			auto idx = croc_getInt(t, arg + 2);

			if(idx < 0 || idx >= func->numUpvals)
				croc_eh_throwStd(t, "BoundsError", "invalid upvalue index '%" CROC_INTEGER_FORMAT "'", idx);

			if(func->isNative)
				return &func->nativeUpvals()[cast(uword)idx];
			else
				return func->scriptUpvals()[cast(uword)idx]->value;
		}
		else if(croc_isString(t, arg + 2))
		{
			if(func->isNative)
				croc_eh_throwStd(t, "ValueError", "cannot get upvalues by name for native functions");

			auto name = getStringObj(Thread::from(t), arg + 2);
			uword i = 0;

			for(auto n: func->scriptFunc->upvalNames)
			{
				if(n == name)
					return func->scriptUpvals()[i]->value;
			}

			croc_eh_throwStd(t, "NameError", "invalid upvalue name '%s'", name->toCString());
		}

		croc_ex_paramTypeError(t, arg + 2, "int|string");
		return nullptr;
	}

	word_t _classHFieldsOfIter(CrocThread* t)
	{
		croc_pushUpval(t, 0);
		auto c = getClass(Thread::from(t), -1);
		croc_pushUpval(t, 1);
		auto index = cast(uword)croc_getInt(t, -1);
		croc_pop(t, 2);

		String** key;
		Value* value;

		if(c->nextHiddenField(index, key, value))
		{
			croc_pushInt(t, index);
			croc_setUpval(t, 1);

			push(Thread::from(t), Value::from(*key));
			push(Thread::from(t), *value);
			return 2;
		}

		return 0;
	}

	word_t _instanceHFieldsOfIter(CrocThread* t)
	{
		croc_pushUpval(t, 0);
		auto c = getInstance(Thread::from(t), -1);
		croc_pushUpval(t, 1);
		auto index = cast(uword)croc_getInt(t, -1);
		croc_pop(t, 2);

		String** key;
		Value* value;

		if(c->nextHiddenField(index, key, value))
		{
			croc_pushInt(t, index);
			croc_setUpval(t, 1);

			push(Thread::from(t), Value::from(*key));
			push(Thread::from(t), *value);
			return 2;
		}

		return 0;
	}

#ifdef CROC_BUILTIN_DOCS
const char* ModuleDocs =
DModule("debug")
R"(This module gives access to the Croc debugging facilities as well as some "sensitive" operations which are usually
reserved for the host. As a result, this library is \em{extremely} unsafe; it's possible to crash the host very easily
by messing with internals that script code normally can't mess with.

Several functions in this library (all of the ones related to debugging) buck the convention of having optional
parameters after required parameters; all these functions allow an optional thread to operate on as the \em{first}
parameter. If none is given, it defaults to the thread that called the function. These functions will all be marked
in their docs, even though the parameter isn't listed in the function signature.

Some of these functions take a parameter which can be either a function or an integer. If it's a function, they operate
on the function itself; if it's an integer, it is treated as an index into the call stack. 0 means "the currently
executing function", 1 means "the function which called the currently executing function", and so on. This means the
maximum allowable integer is the call stack size minus one (see \link{callDepth}). Note that some call stack entries do
not have a function associated with them. Some of these entries are used to manage thread yields and resumes, and others
are call frames which were overwritten by tailcalls. What happens with such call stack entries is documented in each
function which takes a parameter like this.)";
#endif

DBeginList(_globalFuncs)
	Docstr(DFunc("setHook") DParam("hook", "function|null") DParamD("mask", "string", "\"\"")
		DParamD("delay", "int", "0")
	R"(\b{Takes an optional thread as its first parameter.} Sets or removes the given thread's hook function.

	The hook function is a special function which is called at certain points during program execution, which allows you
	to trace the execution of your program. The hook function can be used to implement a debugger, for example.

	There are four places the hook function can be called:

	\blist
		\li When any function is called, right after its stack frame has been set up, but before the function begins
			execution;
		\li When any function returns, right after the last instruction has executed, but before its stack frame is torn
			down;
		\li At a new line of source code;
		\li After every \em{n} bytecode instructions have been executed.
	\endlist

	There is only one hook function, and it will be called for any combination of these events that you specify; it's up
	to the hook function to see what kind of event it is and respond appropriately.

	This hook function (as well as the mask and delay) is inherited by any new threads which the given thread creates
	after the hook was set.

	While the hook function is being run, no hooks will be called (obviously, or else it would result in infinite
	recursion). When the hook function returns, execution will resume as normal until the hook function is called again.

	You cannot yield from within the hook function.

	\param[hook] is the hook function, or \tt{null} to remove the given thread's hook function. It will be called with
		the thread being hooked as \tt{this} (since you could possibly set the same hook function to multiple threads)
		and the type of hook event as a string as its only parameter. This type can be one of the following values:

		\dlist
			\li{\tt{"call"}} for normal function calls.
			\li{\tt{"tailcall"}} which is the same as \tt{"call"}, except there will not be a corresponding
				\tt{"return"} when this function returns (or more precisely, the \em{previously} called function will
				not have a \tt{"return"} event).
			\li{\tt{"return"}} for when a function is about to return.
			\li{\tt{"line"}} for when execution reaches a new line of source code.
			\li{\tt{"delay"}} for when a certain number of bytecode instructions have been executed.
		\endlist

	\param[mask] controls which of the above events the hook function will be called for. It is a string which may
		contain the following characters:

		\dlist
			\li{\tt{'c'}} for \tt{"call"} and \tt{"tailcall"} events.
			\li{\tt{'r'}} for \tt{"return"} events.
			\li{\tt{'l'}} for \tt{"line"} events.
		\endlist

		There is no flag for \tt{"delay"} events, as they're handled by the next parameter.

		If \tt{mask} contains none of the above characters, and the \tt{delay} parameter is 0, the hook function will be
		removed from the given thread.

	\param[delay] controls whether or not the hook function will be called for \tt{"delay"} events. If this parameter is
		0, it won't be. If it's nonzero, it must be positive, and it indicates how often the \tt{"delay"} hook event
		will occur. A value of 1 means the \tt{"delay"} hook will happen after every instruction; a value of 2 means
		every other instruction, and so on.

	\throws[RangeError] if \tt{delay} is invalid (negative).)"),

	"setHook", 4, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);

		croc_ex_checkAnyParam(t, arg + 1);

		if(!croc_isNull(t, arg + 1) && !croc_isFunction(t, arg + 1))
			croc_ex_paramTypeError(t, arg + 1, "null|function");

		auto maskStr = croc_ex_optParam(t, arg + 2, CrocType_String) ? getCrocstr(t, arg + 2) : ATODA("");
		auto delay = croc_ex_optIntParam(t, arg + 3, 0);

		if(delay < 0 || delay > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "invalid delay value (%" CROC_INTEGER_FORMAT ")", delay);

		auto mask = strToMask(maskStr);

		if(delay > 0)
			mask |= CrocThreadHook_Delay;

		croc_dup(t, arg + 1);
		croc_transferVals(t, thread, 1);
		croc_debug_setHookFunc(thread, mask, cast(uword)delay);
		return 0;
	}

DListSep()
	Docstr(DFunc("getHook")
	R"(\b{Takes an optional thread as its first parameter.}

	\returns three values: the hook function, hook mask string, and hook delay value of the given thread, just like the
	parameters to \link{setHook}.

	If there is no hook function set on the thread, the hook function will be \tt{null}, the mask will be the empty
	string, and the delay will be 0.)"),

	"getHook", 1, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);

		croc_debug_pushHookFunc(thread);
		croc_transferVals(thread, t, 1);
		uchar buf[8];
		pushCrocstr(t, maskToStr(mcrocstr::n(buf, sizeof(buf) / sizeof(uchar)), croc_debug_getHookMask(thread)));
		croc_pushInt(t, croc_debug_getHookDelay(thread));
		return 3;
	}

DListSep()
	Docstr(DFunc("callDepth")
	R"(\b{Takes an optional thread as its first parameter.}

	\returns the depth of the call stack of the given thread.)"),

	"callDepth", 1, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);

		if(t == thread)
			croc_pushInt(t, croc_thread_getCallDepth(t) - 1); // - 1 to ignore "callDepth" itself
		else
			croc_pushInt(t, croc_thread_getCallDepth(thread));

		return 1;
	}

DListSep()
	Docstr(DFunc("sourceName") DParam("func", "int|function")
	R"(\b{Takes an optional thread as its first parameter.}

	\param[func] \b{is either a function or call stack index} as described in this module's docs.
	\returns the name of the source in which \tt{func} was defined (the same name that you would see in a traceback). If
		the given function is native, or if there is no function at that call level, returns the empty string.)"),

	"sourceName", 2, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func == nullptr || func->isNative)
			croc_pushString(t, "");
		else
			push(Thread::from(t), Value::from(func->scriptFunc->locFile));

		return 1;
	}

DListSep()
	Docstr(DFunc("sourceLine") DParam("func", "int|function")
	R"(\b{Takes an optional thread as its first parameter.}

	\param[func] \b{is either a function or call stack index} as described in this module's docs.
	\returns the line of the source at which \tt{func} was defined (the same line that you would see in a traceback). If
		the given function is native, or if there is no function at that call level, returns 0.)"),

	"sourceLine", 2, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func == nullptr || func->isNative)
			croc_pushInt(t, 0);
		else
			croc_pushInt(t, func->scriptFunc->locLine);

		return 1;
	}

DListSep()
	Docstr(DFunc("getFunc") DParam("depth", "int")
	R"(\b{Takes an optional thread as its first parameter.}

	\param[depth] is an index into the call stack as described in this module's docs.
	\returns the function at that call level, or \tt{null} if there is none.)"),

	"getFunc", 2, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		croc_ex_checkIntParam(t, arg + 1);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func == nullptr)
			croc_pushNull(t);
		else
			push(Thread::from(t), Value::from(func));

		return 1;
	}

DListSep()
	Docstr(DFunc("numLocals") DParam("depth", "int")
	R"(\b{Takes an optional thread as its first parameter.}

	\param[depth] is an index into the call stack as described in this module's docs.
	\returns the number of \b{active} locals in the function at the given call depth. The active locals are the ones
		that are in scope at the point where the given function is currently executing. This number defines the limit
		to the indexes you can pass to the functions which inspect locals.)"),

	"numLocals", 2, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto ar = getAR(t, thread, croc_ex_checkIntParam(t, arg + 1));

		if(ar->func == nullptr || ar->func->isNative)
			croc_pushInt(t, 0);
		else
		{
			crocint num = 0;
			auto pc = cast(uword)(ar->pc - ar->func->scriptFunc->code.ptr);

			for(auto &var: ar->func->scriptFunc->locVarDescs)
			{
				if(pc >= var.pcStart && pc < var.pcEnd)
					num++;
			}

			croc_pushInt(t, num);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("localName") DParam("depth", "int") DParam("idx", "int")
	R"(\b{Takes an optional thread as its first parameter.}

	\param[depth] is an index into the call stack as described in this module's docs.
	\param[idx] is the numeric index of the local whose name should be retrieved. This index should be less than the
		number given by \link{numLocals}.

	\returns the name of the local at that index.

	While poking around, you may find locals with odd names which start with a dollar sign ('$'). These are locals
	generated by the compiler for some kinds of program structures. It's best not to change the values of these locals,
	as the VM assumes that they hold certain types and ranges of values; changing them may lead to erratic behavior or
	crashes.

	\throws[BoundsError] if \tt{idx} is out of range.)"),

	"localName", 3, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto ar = getAR(t, thread, croc_ex_checkIntParam(t, arg + 1));
		auto idx = croc_ex_checkIntParam(t, arg + 2);

		if(idx < 0 || ar->func == nullptr || ar->func->isNative)
			croc_eh_throwStd(t, "BoundsError", "invalid local index '%" CROC_INTEGER_FORMAT "'", idx);

		auto originalIdx = idx;
		auto pc = cast(uword)(ar->pc - ar->func->scriptFunc->code.ptr);

		for(auto &var: ar->func->scriptFunc->locVarDescs)
		{
			if(pc >= var.pcStart && pc < var.pcEnd)
			{
				if(idx == 0)
				{
					push(Thread::from(t), Value::from(var.name));
					return 1;
				}

				idx--;
			}
		}

		return croc_eh_throwStd(t, "BoundsError", "invalid local index '%" CROC_INTEGER_FORMAT "'", originalIdx);
	}

DListSep()
	Docstr(DFunc("getLocal") DParam("depth", "int") DParam("which", "int|string")
	R"(\b{Takes an optional thread as its first parameter.}

	\param[depth] is an index into the call stack as described in this module's docs.
	\param[which] specifies which local. If it's an int, it's an index of the same kind used by \link{localName}. If
		it's a string, it's the name of the local whose value is to be retrieved.

	\returns the value of the given local.
	\throws[BoundsError] if \tt{which} is an int and is out of range.
	\throws[NameError] if \tt{which} is a string and there is no active local of that name.)"),

	"getLocal", 3, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto ar = getAR(t, thread, croc_ex_checkIntParam(t, arg + 1));
		push(Thread::from(t), *findLocal(t, thread, arg, ar));
		return 1;
	}

DListSep()
	Docstr(DFunc("setLocal") DParam("depth", "int") DParam("which", "int|string") DParamAny("val")
	R"(\b{Takes an optional thread as its first parameter.} Sets a local to the value \tt{val}.

	\param[depth] is an index into the call stack as described in this module's docs.
	\param[which] specifies which local. If it's an int, it's an index of the same kind used by \link{localName}. If
		it's a string, it's the name of the local whose value is to be set.
	\param[val] is the value which will be stored in the local.
	\throws[BoundsError] if \tt{which} is an int and is out of range.
	\throws[NameError] if \tt{which} is a string and there is no active local of that name.)"),

	"setLocal", 4, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto ar = getAR(t, thread, croc_ex_checkIntParam(t, arg + 1));
		croc_ex_checkAnyParam(t, arg + 3);
		*findLocal(t, thread, arg, ar) = *getValue(Thread::from(t), arg + 3);
		return 0;
	}

DListSep()
	Docstr(DFunc("numUpvals") DParam("func", "int|function")
	R"(\b{Takes an optional thread as its first parameter.}

	\param[func] \b{is either a function or call stack index} as described in this module's docs.

	\returns the number of upvalues that the given function has.)"),

	"numUpvals", 2, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func == nullptr)
			croc_pushInt(t, 0);
		else
			croc_pushInt(t, func->numUpvals);

		return 1;
	}

DListSep()
	Docstr(DFunc("upvalName") DParam("func", "int|function") DParam("idx", "int")
	R"(\b{Takes an optional thread as its first parameter.}

	\param[func] \b{is either a function or call stack index} as described in this module's docs.
	\param[idx] is the numeric index of the upvalue whose name is to be retrieved. This index should be less than the
		number given by \link{numUpvals}.

	\returns the name of the upvalue at that index, or if \tt{func} is native, returns the empty string.)"),

	"upvalName", 3, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);
		auto idx = croc_ex_checkIntParam(t, arg + 2);

		if(func == nullptr || idx < 0 || idx >= func->numUpvals)
			croc_eh_throwStd(t, "BoundsError", "invalid upvalue index '%" CROC_INTEGER_FORMAT "'", idx);

		// Check is in case there's no debug info
		if(func->isNative || idx >= func->scriptFunc->upvalNames.length)
			croc_pushString(t, "");
		else
			push(Thread::from(t), Value::from(func->scriptFunc->upvalNames[cast(uword)idx]));

		return 1;
	}

DListSep()
	Docstr(DFunc("getUpval") DParam("func", "int|function") DParam("which", "int|string")
	R"(\b{Takes an optional thread as its first parameter.}

	\param[func] \b{is either a function or call stack index} as described in this module's docs.
	\param[which] specifies which upvalue. If it's an int, it's an index of the same kind used by \link{upvalName}. If
		it's a string, it's the name of the upvalue whose value is to be retrieved.

	\returns the value of the given upvalue.
	\throws[BoundsError] if \tt{which} is an int and is out of range.
	\throws[NameError] if \tt{which} is a string and there is no upvalue of that name.)"),

	"getUpval", 3, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		push(Thread::from(t), *findUpval(t, thread, arg));
		return 1;
	}

DListSep()
	Docstr(DFunc("setUpval") DParam("func", "int|function") DParam("which", "int|string") DParamAny("val")
	R"(\b{Takes an optional thread as its first parameter.} Sets an upvalue to the value \tt{val}.

	\param[func] \b{is either a function or call stack index} as described in this module's docs.
	\param[which] specifies which upvalue. If it's an int, it's an index of the same kind used by \link{upvalName}. If
		it's a string, it's the name of the upvalue whose value is to be retrieved.
	\param[val] is the value which will be stored in the upvalue.
	\throws[BoundsError] if \tt{which} is an int and is out of range.
	\throws[NameError] if \tt{which} is a string and there is no upvalue of that name.)"),

	"setUpval", 4, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		croc_ex_checkAnyParam(t, arg + 3);
		*findUpval(t, thread, arg) = *getValue(Thread::from(t), arg + 3);
		return 0;
	}

DListSep()
	Docstr(DFunc("getFuncEnv") DParam("func", "int|function")
	R"(\b{Takes an optional thread as its first parameter.}

	\param[func] \b{is either a function or call stack index} as described in this module's docs.
	\returns \tt{func}'s environment namespace.
	\throws[ValueError] if \tt{func} is a call stack index and there is no function at that call level.)"),

	"getFuncEnv", 2, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func == nullptr)
			croc_eh_throwStd(t, "ValueError", "no function at that call level");

		push(Thread::from(t), Value::from(func->environment));
		return 1;
	}

DListSep()
	Docstr(DFunc("setFuncEnv") DParam("func", "int|function") DParam("env", "namespace")
	R"(\b{Takes an optional thread as its first parameter.} Sets the native function \tt{func}'s environment to
	the namespace \tt{env}.

	\param[func] \b{is either a function or call stack index} as described in this module's docs.
	\throws[ValueError] if \tt{func} is a call stack index and there is no function at that call level, or if \tt{func}
		is not native.)"),

	"setFuncEnv", 3, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func == nullptr)
			croc_eh_throwStd(t, "ValueError", "no function at that call level");

		if(!func->isNative)
			croc_eh_throwStd(t, "ValueError", "can only set the environment of native functions");

		croc_ex_checkParam(t, arg + 2, CrocType_Namespace);
		push(Thread::from(t), Value::from(func->environment));
		push(Thread::from(t), Value::from(func));
		croc_dup(t, arg + 2);
		croc_function_setEnv(t, -2);
		croc_popTop(t);
		return 1;
	}

DListSep()
	Docstr(DFunc("currentLine") DParam("depth", "int")
	R"(\b{Takes an optional thread as its first parameter.}

	\param[depth] is an index into the call stack as described in this module's docs.
	\returns the line number of the last-executed instruction in the function at the given call level. If there is no
		function at that level or if the function is native, returns 0.)"),

	"currentLine", 2, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto depth = croc_ex_checkIntParam(t, arg + 1);
		auto maxDepth = croc_thread_getCallDepth(thread);

		if(t == thread)
		{
			if(depth < 0 || depth >= maxDepth - 1)
				croc_eh_throwStd(t, "RangeError", "invalid call depth %" CROC_INTEGER_FORMAT, depth);

			croc_pushInt(t, getDebugLine(Thread::from(t), cast(uword)depth + 1));
		}
		else
		{
			if(depth < 0 || depth >= maxDepth)
				croc_eh_throwStd(t, "RangeError", "invalid call depth %" CROC_INTEGER_FORMAT, depth);

			croc_pushInt(t, getDebugLine(Thread::from(t), cast(uword)depth));
		}
		return 1;
	}

DListSep()
	Docstr(DFunc("lineInfo") DParam("func", "int|function")
	R"(\b{Takes an optional thread as its first parameter.}

	\param[func] \b{is either a function or call stack index} as described in this module's docs.
	\returns a (sorted) array of all the source lines which map to at least one bytecode instruction in the given
		function. If there is no function at that level or if the fu nction is native, returns an empty array.)"),

	"lineInfo", 2, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func == nullptr || func->isNative)
			croc_array_new(t, 0);
		else
		{
			auto info = func->scriptFunc->lineInfo;

			croc_table_new(t, info.length);

			for(auto l: info)
			{
				croc_pushBool(t, true);
				croc_idxai(t, -2, l);
			}

			croc_ex_lookup(t, "hash.keys");
			croc_pushNull(t);
			croc_dup(t, -3);
			croc_call(t, -3, 1);
			croc_pushNull(t);
			croc_methodCall(t, -2, "sort", 1);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("getMetatable") DParam("type", "string")
	R"(Gets the global type metatable for a given Croc type.

	\param[type] is the name of the type, which should be one of the strings that \link{typeof} returns.
	\returns the type metatable for that type, or \tt{null} if none has been set.)"),

	"getMetatable", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		auto name = getCrocstr(t, 1);

		if(name == ATODA("null"))      croc_vm_pushTypeMT(t, CrocType_Null);      else
		if(name == ATODA("bool"))      croc_vm_pushTypeMT(t, CrocType_Bool);      else
		if(name == ATODA("int"))       croc_vm_pushTypeMT(t, CrocType_Int);       else
		if(name == ATODA("float"))     croc_vm_pushTypeMT(t, CrocType_Float);     else
		if(name == ATODA("nativeobj")) croc_vm_pushTypeMT(t, CrocType_Nativeobj); else
		if(name == ATODA("string"))    croc_vm_pushTypeMT(t, CrocType_String);    else
		if(name == ATODA("weakref"))   croc_vm_pushTypeMT(t, CrocType_Weakref);   else
		if(name == ATODA("table"))     croc_vm_pushTypeMT(t, CrocType_Table);     else
		if(name == ATODA("namespace")) croc_vm_pushTypeMT(t, CrocType_Namespace); else
		if(name == ATODA("array"))     croc_vm_pushTypeMT(t, CrocType_Array);     else
		if(name == ATODA("memblock"))  croc_vm_pushTypeMT(t, CrocType_Memblock);  else
		if(name == ATODA("function"))  croc_vm_pushTypeMT(t, CrocType_Function);  else
		if(name == ATODA("funcdef"))   croc_vm_pushTypeMT(t, CrocType_Funcdef);   else
		if(name == ATODA("class"))     croc_vm_pushTypeMT(t, CrocType_Class);     else
		if(name == ATODA("instance"))  croc_vm_pushTypeMT(t, CrocType_Instance);  else
		if(name == ATODA("thread"))    croc_vm_pushTypeMT(t, CrocType_Thread);    else
			croc_eh_throwStd(t, "ValueError", "invalid type name '%.*s'", cast(int)name.length, name.ptr);

		return 1;
	}

DListSep()
	Docstr(DFunc("setMetatable") DParam("type", "string") DParam("mt", "null|namespace")
	R"(Sets or removes the global type metatable for a given Croc type.

	\param[type] is the name of the type, which should be one of the strings that \link{typeof} returns.
	\param[mt] is the metatable namespace, or \tt{null} to unset it.)"),

	"setMetatable", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_String);
		auto name = getCrocstr(t, 1);

		if(!croc_isValidIndex(t, 2) || (!croc_isNull(t, 2) && !croc_isNamespace(t, 2)))
			croc_ex_paramTypeError(t, 2, "null|namespace");

		croc_dup(t, 2);

		if(name == ATODA("null"))      croc_vm_setTypeMT(t, CrocType_Null);      else
		if(name == ATODA("bool"))      croc_vm_setTypeMT(t, CrocType_Bool);      else
		if(name == ATODA("int"))       croc_vm_setTypeMT(t, CrocType_Int);       else
		if(name == ATODA("float"))     croc_vm_setTypeMT(t, CrocType_Float);     else
		if(name == ATODA("nativeobj")) croc_vm_setTypeMT(t, CrocType_Nativeobj); else
		if(name == ATODA("string"))    croc_vm_setTypeMT(t, CrocType_String);    else
		if(name == ATODA("weakref"))   croc_vm_setTypeMT(t, CrocType_Weakref);   else
		if(name == ATODA("table"))     croc_vm_setTypeMT(t, CrocType_Table);     else
		if(name == ATODA("namespace")) croc_vm_setTypeMT(t, CrocType_Namespace); else
		if(name == ATODA("array"))     croc_vm_setTypeMT(t, CrocType_Array);     else
		if(name == ATODA("memblock"))  croc_vm_setTypeMT(t, CrocType_Memblock);  else
		if(name == ATODA("function"))  croc_vm_setTypeMT(t, CrocType_Function);  else
		if(name == ATODA("funcdef"))   croc_vm_setTypeMT(t, CrocType_Funcdef);   else
		if(name == ATODA("class"))     croc_vm_setTypeMT(t, CrocType_Class);     else
		if(name == ATODA("instance"))  croc_vm_setTypeMT(t, CrocType_Instance);  else
		if(name == ATODA("thread"))    croc_vm_setTypeMT(t, CrocType_Thread);    else
			croc_eh_throwStd(t, "ValueError", "invalid type name '%.*s'", cast(int)name.length, name.ptr);

		return 0;
	}

DListSep()
	Docstr(DFunc("getRegistry")
	R"(\returns the registry namespace which is used by the host to hold "hidden" globals.)"),

	"getRegistry", 0, [](CrocThread* t) -> word_t
	{
		croc_vm_pushRegistry(t);
		return 1;
	}

DListSep()
	Docstr(DFunc("addHField") DParam("cls", "class") DParam("name", "string") DParamD("val", "any", "null")
	R"(Adds a hidden field to a class.

	\param[cls] is the class to add the hidden field to. It must not be frozen.
	\param[name] is the name of the hidden field to add. Hidden fields are in a separate namespace from regular fields,
		so they can have the same names.
	\param[val] is the value to store in the field, which defaults to \tt{null}.)"),

	"addHField", 3, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_Class);
		croc_ex_checkStringParam(t, 2);

		if(!croc_isValidIndex(t, 3))
			croc_pushNull(t);

		croc_dup(t, 2);
		croc_dup(t, 3);
		croc_class_addHFieldStk(t, 1);
		return 0;
	}

DListSep()
	Docstr(DFunc("removeHField") DParam("cls", "class") DParam("name", "string")
	R"(Removes a hidden field from a class.

	\param[cls] is the class to remove the hidden field from. It must not be frozen.
	\param[name] is the name of the hidden field to remove.)"),

	"removeHField", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_Class);
		croc_ex_checkStringParam(t, 2);
		croc_dup(t, 2);
		croc_class_removeHFieldStk(t, 1);
		return 0;
	}

DListSep()
	Docstr(DFunc("hasHField") DParam("obj", "class|instance") DParam("name", "string")
	R"(\returns a bool saying whether or not the given class or instance has a hidden field named \tt{name}.)"),

	"hasHField", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkStringParam(t, 2);

		if(!croc_isInstance(t, 1) && !croc_isClass(t, 1))
			croc_ex_paramTypeError(t, 1, "class|instance");

		croc_pushBool(t, croc_hasHFieldStk(t, 1, 2));
		return 1;
	}

DListSep()
	Docstr(DFunc("getHField") DParam("obj", "class|instance") DParam("name", "string")
	R"(\returns the value of the hidden field named \tt{name} in the given class or instance.)"),

	"getHField", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkStringParam(t, 2);

		if(!croc_isInstance(t, 1) && !croc_isClass(t, 1))
			croc_ex_paramTypeError(t, 1, "class|instance");

		croc_dup(t, 2);
		croc_hfieldStk(t, 1);
		return 1;
	}

DListSep()
	Docstr(DFunc("setHField") DParam("obj", "class|instance") DParam("name", "string") DParamAny("val")
	R"(Sets the hidden field named \tt{name} in the given class or instance to \tt{val}.)"),

	"setHField", 3, [](CrocThread* t) -> word_t
	{
		croc_ex_checkStringParam(t, 2);
		croc_ex_checkAnyParam(t, 3);

		if(!croc_isInstance(t, 1) && !croc_isClass(t, 1))
			croc_ex_paramTypeError(t, 1, "class|instance");

		croc_dup(t, 2);
		croc_dup(t, 3);
		croc_hfieldaStk(t, 1);
		return 0;
	}

DListSep()
	Docstr(DFunc("hfieldsOf") DParam("obj", "class|instance")
	R"(\returns an iterator function for iterating over the hidden fields of the given class or instance. This works
	just like \link{object.fieldsOf}; the first index is the name of the hidden field, and the second index is the
	value.

\code
// Print the juicy hidden fields of the NativeStream class!
foreach(name, val; debug.hfieldsOf(stream.NativeStream))
	writefln("{}: {}", name, val)
\endcode)"),

	"hfieldsOf", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);
		croc_dup(t, 1);
		croc_pushInt(t, 0);

		if(croc_isClass(t, 1))
			croc_function_new(t, "hfieldsOfClassIter", 1, &_classHFieldsOfIter, 2);
		else if(croc_isInstance(t, 1))
			croc_function_new(t, "hfieldsOfInstanceIter", 1, &_instanceHFieldsOfIter, 2);
		else
			croc_ex_paramTypeError(t, 1, "class|instance");

		return 1;
	}
DEndList()

	word loader(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);
		return 0;
	}
	}

	void initDebugLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "debug", &loader);
		croc_ex_importNS(t, "debug");
#ifdef CROC_BUILTIN_DOCS
		CrocDoc doc;
		croc_ex_doc_init(t, &doc, __FILE__);
		croc_ex_doc_push(&doc, ModuleDocs);
			docFields(&doc, _globalFuncs);
		croc_ex_doc_pop(&doc, -1);
		croc_ex_doc_finish(&doc);
#endif
		croc_popTop(t);
	}
}