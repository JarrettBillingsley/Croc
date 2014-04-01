
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
R"()";
#endif

DBeginList(_globalFuncs)
	Docstr(DFunc("setHook")
	R"()"),

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
	R"()"),

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
	R"()"),

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
	Docstr(DFunc("sourceName")
	R"()"),

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
	Docstr(DFunc("sourceLine")
	R"()"),

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
	Docstr(DFunc("getFunc")
	R"()"),

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
	Docstr(DFunc("numLocals")
	R"()"),

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
	Docstr(DFunc("localName")
	R"()"),

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
	Docstr(DFunc("getLocal")
	R"()"),

	"getLocal", 3, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto ar = getAR(t, thread, croc_ex_checkIntParam(t, arg + 1));
		push(Thread::from(t), *findLocal(t, thread, arg, ar));
		return 1;
	}

DListSep()
	Docstr(DFunc("setLocal")
	R"()"),

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
	Docstr(DFunc("numUpvals")
	R"()"),

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
	Docstr(DFunc("upvalName")
	R"()"),

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
	Docstr(DFunc("getUpval")
	R"()"),

	"getUpval", 3, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		push(Thread::from(t), *findUpval(t, thread, arg));
		return 1;
	}

DListSep()
	Docstr(DFunc("setUpval")
	R"()"),

	"setUpval", 4, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		croc_ex_checkAnyParam(t, arg + 3);
		*findUpval(t, thread, arg) = *getValue(Thread::from(t), arg + 3);
		return 0;
	}

DListSep()
	Docstr(DFunc("getFuncEnv")
	R"()"),

	"getFuncEnv", 2, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func == nullptr)
			croc_eh_throwStd(t, "ValueError", "invalid function");

		push(Thread::from(t), Value::from(func->environment));
		return 1;
	}

DListSep()
	Docstr(DFunc("setFuncEnv")
	R"()"),

	"setFuncEnv", 3, [](CrocThread* t) -> word_t
	{
		word arg;
		auto thread = getThreadParam(t, arg);
		auto func = getFuncParam(t, thread, arg + 1);

		if(func == nullptr)
			croc_eh_throwStd(t, "ValueError", "invalid function");

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
	Docstr(DFunc("currentLine")
	R"()"),

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
	Docstr(DFunc("lineInfo")
	R"()"),

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
	Docstr(DFunc("getMetatable")
	R"()"),

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
	Docstr(DFunc("setMetatable")
	R"()"),

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
	R"()"),

	"getRegistry", 0, [](CrocThread* t) -> word_t
	{
		croc_vm_pushRegistry(t);
		return 1;
	}

DListSep()
	Docstr(DFunc("addHField")
	R"()"),

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
	Docstr(DFunc("removeHField")
	R"()"),

	"removeHField", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_Class);
		croc_ex_checkStringParam(t, 2);
		croc_dup(t, 2);
		croc_class_removeHFieldStk(t, 1);
		return 0;
	}

DListSep()
	Docstr(DFunc("hasHField")
	R"()"),

	"hasHField", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkStringParam(t, 2);

		if(!croc_isInstance(t, 1) && !croc_isClass(t, 1))
			croc_ex_paramTypeError(t, 1, "class|instance");

		croc_pushBool(t, croc_hasHFieldStk(t, 1, 2));
		return 1;
	}

DListSep()
	Docstr(DFunc("getHField")
	R"()"),

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
	Docstr(DFunc("setHField")
	R"()"),

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
	Docstr(DFunc("hfieldsOf")
	R"()"),

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