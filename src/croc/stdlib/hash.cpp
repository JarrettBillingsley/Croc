
#include <stdlib.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
#include "croc/stdlib/hash_weaktables.croc.hpp"

	word_t _keysImpl(CrocThread* t, word_t slot)
	{
		auto t_ = Thread::from(t);

		if(croc_isTable(t, slot))
		{
			auto tab = getTable(t_, slot);
			croc_array_new(t, tab->length());
			word idx = 0;

			for(auto node: tab->data)
			{
				push(t_, node->key);
				croc_idxai(t, -2, idx++);
			}
		}
		else if(croc_isNamespace(t, slot))
		{
			auto ns = getNamespace(t_, slot);

			croc_array_new(t, ns->length());
			word idx = 0;

			for(auto node: ns->data)
			{
				push(t_, Value::from(node->key));
				croc_idxai(t, -2, idx++);
			}
		}
		else
			croc_ex_paramTypeError(t, slot, "table|namespace");

		return 1;
	}

	template<bool remove>
	word_t _takeImpl(CrocThread* t)
	{
		uword idx = 0;
		Value* v;
		auto t_ = Thread::from(t);

		croc_ex_checkAnyParam(t, 1);

		if(croc_isTable(t, 1))
		{
			auto tab = getTable(t_, 1);
			Value* k;

			if(tab->next(idx, k, v))
			{
				push(t_, *k);
				push(t_, *v);

				if(remove)
					tab->idxa(t_->vm->mem, *k, Value::nullValue);
			}
			else
				croc_eh_throwStd(t, "ValueError", "Attempting to take from an empty table");
		}
		else if(croc_isNamespace(t, 1))
		{
			auto ns = getNamespace(t_, 1);
			String** s;

			if(ns->data.next(idx, s, v))
			{
				push(t_, Value::from(*s));
				push(t_, *v);

				if(remove)
					ns->remove(t_->vm->mem, *s);
			}
			else
				croc_eh_throwStd(t, "ValueError", "Attempting to take from an empty namespace");
		}
		else
			croc_ex_paramTypeError(t, 1, "table|namespace");

		return 2;
	}

DBeginList(_globalFuncs)
	Docstr(DFunc("dup") DParam("t", "table")
	R"(Makes a shallow duplicate of a table.

	\returns a new table that has the same key-value pairs as \tt{t}.)"),

	"dup", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_Table);
		auto t_ = Thread::from(t);
		push(t_, Value::from(getTable(t_, 1)->dup(t_->vm->mem)));
		return 1;
	}

DListSep()
	Docstr(DFunc("keys") DParam("h", "table|namespace")
	R"(\returns an array containing all the keys of the given table or namespace. The order of the keys is arbitrary.

	\notes This function is nontrivial, involving a memory allocation and a traversal of the given hashtable.)"),

	"keys", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);
		return _keysImpl(t, 1);
	}

DListSep()
	Docstr(DFunc("values") DParam("h", "table|namespace")
	R"(\returns an array containing all the values of the given table or namespace. The order of the values is
	arbitrary.

	\notes This function is nontrivial, involving a memory allocation and a traversal of the given hashtable.)"),

	"values", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);

		auto t_ = Thread::from(t);

		if(croc_isTable(t, 1))
		{
			auto tab = getTable(t_, 1);
			croc_array_new(t, tab->length());
			word idx = 0;

			for(auto node: tab->data)
			{
				push(t_, node->value);
				croc_idxai(t, -2, idx++);
			}
		}
		else if(croc_isNamespace(t, 1))
		{
			auto ns = getNamespace(t_, 1);

			croc_array_new(t, ns->length());
			word idx = 0;

			for(auto node: ns->data)
			{
				push(t_, node->value);
				croc_idxai(t, -2, idx++);
			}
		}
		else
			croc_ex_paramTypeError(t, 1, "table|namespace");

		return 1;
	}

DListSep()
	Docstr(DFunc("apply") DParam("t", "table") DParam("f", "function")
	R"(Similar to the \link{array.apply} function, this iterates over the values of the table, calling the function
	\tt{f} on each value, and storing the value it returns back into the same key. This works in-place on the table.

	\examples If you have a table \tt{t = \{x = 1, y = 2, z = 3\}} and call \tt{hash.apply(t, \\x -> x + 5)}, \tt{t}
	will now contain \tt{\{x = 6, y = 7, z = 8\}}.

	\returns \tt{t}.

	\throws[TypeError] if \tt{f} returns \tt{null}.)"),

	"apply", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_Table);
		croc_ex_checkParam(t, 2, CrocType_Function);

		auto t_ = Thread::from(t);
		auto tab = getTable(t_, 1);

		for(auto node: tab->data)
		{
			croc_dup(t, 2);
			croc_pushNull(t);
			push(t_, node->value);
			croc_call(t, -3, 1);

			if(croc_isNull(t, -1))
				croc_eh_throwStd(t, "TypeError", "Callback function returned null");

			tab->idxa(t_->vm->mem, node->key, *getValue(t_, -1));
			croc_popTop(t);
		}

		croc_dup(t, 1);
		return 1;
	}

DListSep()
	Docstr(DFunc("map") DParam("t", "table") DParam("f", "function")
	R"(Like \link{apply}, but instead of operating in-place, creates a new table which holds the transformed key-value
	pairs, leaving \tt{t} unmodified.

	\returns the new table.

	throws[TypeError] if \tt{f} returns \tt{null}.)"),

	"map", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_Table);
		croc_ex_checkParam(t, 2, CrocType_Function);

		auto t_ = Thread::from(t);
		auto oldTab = getTable(t_, 1);
		croc_table_new(t, oldTab->length());
		auto newTab = getTable(t_, -1);

		for(auto node: oldTab->data)
		{
			croc_dup(t, 2);
			croc_pushNull(t);
			push(t_, node->value);
			croc_call(t, -3, 1);
			newTab->idxa(t_->vm->mem, node->key, *getValue(t_, -1));
			croc_popTop(t);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("reduce") DParam("t", "table") DParam("f", "function") DParamD("initial", "any", "null")
	R"(Works just like the \link{array.reduce} function, but the order of the values is arbitrary. \tt{f} will be called
	with two parameters, the current value of the accumulator and a new value from the table, and is expected to return
	the new value of the accumulator.

	Just like \link{array.reduce}, the \tt{initial} parameter can be given to set the accumulator to an initial value.

	\throws[ParamError] if you call this function on an empty table and \em{don't} pass an \tt{initial} parameter.)"),

	"reduce", 3, [](CrocThread* t) -> word_t
	{
		auto numParams = croc_getStackSize(t) - 1;
		croc_ex_checkParam(t, 1, CrocType_Table);
		croc_ex_checkParam(t, 2, CrocType_Function);

		auto length = cast(uword)croc_len(t, 1);

		if(length == 0)
		{
			if(numParams == 2)
				croc_eh_throwStd(t, "ParamError", "Attempting to reduce an empty table without an initial value");
			else
			{
				croc_dup(t, 3);
				return 1;
			}
		}

		bool haveInitial = numParams > 2;
		auto t_ = Thread::from(t);

		for(auto node: getTable(t_, 1)->data)
		{
			if(!haveInitial)
			{
				push(t_, node->value);
				haveInitial = true;
			}
			else
			{
				croc_dup(t, 2);
				croc_pushNull(t);
				croc_dup(t, -3);
				push(t_, node->value);
				croc_call(t, -4, 1);
				croc_insertAndPop(t, -2);
			}
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("filter") DParam("t", "table") DParam("f", "function")
	R"(Similar to the \link{array.filter} function, this creates a new table which holds only those key-value pairs for
	which the given filter function \tt{f} returns \tt{true}. \tt{f} is given two arguments, the key and the value, and
	must return a boolean value. \tt{true} means the key-value pair will be included in the result.

	\examples \tt{hash.filter(\{a = 1, b = 2, c = "hi", d = 4.5, e = 6\}, \\k, v -> isInt(v))} will give a table
	containing only those key-value pairs from the original where the values were integers, so you will get
	\tt{\{a = 1, b = 2, e = 6\}}.

	\returns the new table.

	\throws[TypeError] if \tt{f} returns anything other than a boolean value.)"),

	"filter", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 1, CrocType_Table);
		croc_ex_checkParam(t, 2, CrocType_Function);

		auto t_ = Thread::from(t);
		auto oldTab = getTable(t_, 1);
		croc_table_new(t, oldTab->length() / 4); // just an estimate
		auto newTab = getTable(t_, -1);

		for(auto node: oldTab->data)
		{
			croc_dup(t, 2);
			croc_pushNull(t);
			push(t_, node->key);
			push(t_, node->value);
			croc_call(t, -4, 1);

			if(!croc_isBool(t, -1))
			{
				croc_pushTypeString(t, -1);
				croc_eh_throwStd(t, "TypeError", "Callback function did not return a bool, it returned '%s'",
					croc_getString(t, -1));
			}

			if(croc_getBool(t, -1))
				newTab->idxa(t_->vm->mem, node->key, node->value);

			croc_popTop(t);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("take") DParam("h", "table|namespace")
	R"(\returns an arbitrary key-value pair as two values (first the key, then the value). The key-value pair is not
	removed. This is often useful when using a hashtable as a set.

	\throws[ValueError] if \tt{#h == 0}.)"),

	"take", 1, &_takeImpl<false>

DListSep()
	Docstr(DFunc("pop") DParam("h", "table|namespace")
	R"(Similar to \link{take}, but it \b{does} remove the key-value pair that is returned.

	\returns the arbitrary key-value pair as two values (first the key, then the value).

	\throws[ValueError] if \tt{#h == 0}.)"),

	"pop", 1, &_takeImpl<true>

DListSep()
	Docstr(DFunc("clear") DParam("h", "table|namespace")
	R"(Removes all key-value pairs from \tt{h}.)"),

	"clear", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);

		if(croc_isTable(t, 1))
			croc_table_clear(t, 1);
		else if(croc_isNamespace(t, 1))
			croc_namespace_clear(t, 1);
		else
			croc_ex_paramTypeError(t, 1, "table|namespace");

		return 0;
	}

DListSep()
	Docstr(DFunc("remove") DParam("h", "table|namespace") DParamAny("key")
	R"(Removes from \tt{h} the key-value pair with key \tt{key}, if any exists. For tables, you can also do this by
	assigning a \tt{null} value to a key-value pair, but this function is the only way to remove key-value pairs from
	namespaces.)"),

	"remove", 2, [](CrocThread* t) -> word_t
	{
		croc_ex_checkAnyParam(t, 1);

		if(croc_isTable(t, 1))
			croc_ex_checkAnyParam(t, 2);
		else if(croc_isNamespace(t, 1))
			croc_ex_checkStringParam(t, 2);
		else
			croc_ex_paramTypeError(t, 1, "table|namespace");

		croc_removeKey(t, 1);
		return 0;
	}

DListSep()
	Docstr(DFunc("newNamespace") DParam("name", "string") DParam("parent", "namespace|null")
	R"(Create a new namespace.

	This is useful for when you need to create a namespace with a programmatically-generated name, something that the
	language grammar doesn't allow.

	This function behaves a little strangely with regards to its parameters, in order to mirror the behavior of actual
	namespace declarations.

	\param[name] is the name of the new namespace.
	\param[parent] is the optional parent. There is a difference between passing \tt{null} and passing nothing to this
	parameter, which goes against the usual behavior of optional parameters, but it's like this to mirror the behavior
	of real namespace declarations. See the examples for details.
	\returns the new namespace.

	\examples
\code
hash.newNamespace("A") // the same as "namespace A {}"; the parent is set to the current function's environment.
hash.newNamespace("B", null) // the same as "namespace B : null {}"; B has no parent.
hash.newNamespace("C", _G) // the same as "namespace C : _G {}"; C's parent is the global namespace.
\endcode
	)"),

	"newNamespace", 2, [](CrocThread* t) -> word_t	{
		auto name = croc_ex_checkStringParam(t, 1);

		if(croc_isValidIndex(t, 2))
		{
			if(croc_ex_optParam(t, 2, CrocType_Namespace))
				croc_namespace_newWithParent(t, 2, name);
			else
				croc_namespace_newNoParent(t, name);
		}
		else
		{
			croc_pushEnvironment(t, 1);
			croc_namespace_newWithParent(t, -1, name);
		}

		return 1;
	}
DEndList()

	word_t _tableIterator(CrocThread* t)
	{
		auto t_ = Thread::from(t);
		croc_pushUpval(t, 0);
		auto tab = getTable(t_, -1);
		croc_pushUpval(t, 1);
		auto idx = cast(uword)croc_getInt(t, -1);

		Value* k, *v;

		if(tab->next(idx, k, v))
		{
			croc_pushInt(t, idx);
			croc_setUpval(t, 1);
			push(t_, *k);
			push(t_, *v);
			return 2;
		}

		return 0;
	}

	word_t _modTableIterator(CrocThread* t)
	{
		auto t_ = Thread::from(t);
		croc_pushUpval(t, 0);
		auto tab = getTable(t_, -1);
		croc_pushUpval(t, 1);
		auto keys = getArray(t_, -1)->toDArray();
		croc_pushUpval(t, 2);
		auto idx = cast(uword)croc_getInt(t, -1) + 1;

		croc_pop(t, 3);

		for(; idx < keys.length; idx++)
		{
			if(auto v = tab->get(keys[idx].value))
			{
				croc_pushInt(t, idx);
				croc_setUpval(t, 2);
				push(t_, keys[idx].value);
				push(t_, *v);
				return 2;
			}
		}

		return 0;
	}

DBeginList(_tableMetamethods)
	Docstr(DFunc("opApply") DParamD("mode", "string", "null")
	R"(Iterate over the key-value pairs of a table.

	\param[mode] is the optional iteration mode. If you don't pass anything for this, attempting to insert or remove
	key-value pairs in the table while inside the foreach loop can cause strange behavior. If you want to insert or
	remove key-value pairs during iteration, pass the string "modify" for this parameter; this will iterate over the
	keys which existed at the time the loop started (as long as they still exist by the time iteration gets to
	them). Note that the "modify" iteration mode requires allocating an array at the beginning of iteration to hold the
	keys.)"),

	"opApply", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Table);
		auto mode = croc_ex_optStringParam(t, 1, "");

		croc_dup(t, 0);

		if(strcmp(mode, "modify") == 0)
		{
			_keysImpl(t, 0);
			croc_pushInt(t, -1);
			croc_function_new(t, "iterator", 1, &_modTableIterator, 3);
		}
		else
		{
			croc_pushInt(t, 0);
			croc_function_new(t, "iterator", 1, &_tableIterator, 2);
		}

		return 1;
	}
DEndList()

	word_t _namespaceIterator(CrocThread* t)
	{
		auto t_ = Thread::from(t);
		croc_pushUpval(t, 0);
		auto ns = getNamespace(t_, -1);
		croc_pushUpval(t, 1);
		auto idx = cast(uword)croc_getInt(t, -1);
		String** k;
		Value* v;

		if(ns->data.next(idx, k, v))
		{
			croc_pushInt(t, idx);
			croc_setUpval(t, 1);
			push(t_, Value::from(*k));
			push(t_, *v);
			return 2;
		}

		return 0;
	}

	word_t _modNamespaceIterator(CrocThread* t)
	{
		auto t_ = Thread::from(t);
		croc_pushUpval(t, 0);
		auto ns = getNamespace(t_, -1);
		croc_pushUpval(t, 1);
		auto keys = getArray(t_, -1)->toDArray();
		croc_pushUpval(t, 2);
		auto idx = cast(uword)croc_getInt(t, -1) + 1;

		croc_pop(t, 3);

		for(; idx < keys.length; idx++)
		{
			if(auto v = ns->get(keys[idx].value.mString))
			{
				croc_pushInt(t, idx);
				croc_setUpval(t, 2);
				push(t_, keys[idx].value);
				push(t_, *v);
				return 2;
			}
		}

		return 0;
	}

DBeginList(_namespaceMetamethods)
	Docstr(DFunc("opApply") DParamD("mode", "string", "null")
	R"(Iterate over the key-value pairs of a namespace.

	\param[mode] is the optional iteration mode. If you don't pass anything for this, attempting to insert or remove
	key-value pairs in the namespace while inside the foreach loop can cause strange behavior. If you want to insert or
	remove key-value pairs during iteration, pass the string "modify" for this parameter; this will iterate over the
	keys which existed at the time the loop started (as long as they still exist by the time iteration gets to
	them). Note that the "modify" iteration mode requires allocating an array at the beginning of iteration to hold the
	keys.)"),

	"opApply", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Namespace);
		auto mode = croc_ex_optStringParam(t, 1, "");

		croc_dup(t, 0);

		if(strcmp(mode, "modify") == 0)
		{
			_keysImpl(t, 0);
			croc_pushInt(t, -1);
			croc_function_new(t, "iterator", 1, &_modNamespaceIterator, 3);
		}
		else
		{
			croc_pushInt(t, 0);
			croc_function_new(t, "iterator", 1, &_namespaceIterator, 2);
		}

		return 1;
	}
DEndList()

	word loader(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);

		croc_namespace_new(t, "table");
			registerFields(t, _tableMetamethods);
		croc_vm_setTypeMT(t, CrocType_Table);

		croc_namespace_new(t, "namespace");
			registerFields(t, _namespaceMetamethods);
		croc_vm_setTypeMT(t, CrocType_Namespace);

		croc_pushStringn(t, hash_weaktables_croc_text, hash_weaktables_croc_length);
#ifdef CROC_BUILTIN_DOCS
		croc_compiler_compileStmtsDTEx(t, "hash_weaktables.croc");
#else
		croc_compiler_compileStmtsEx(t, "hash_weaktables.croc");
#endif
		croc_function_newScript(t, -1);
		croc_pushNull(t);
		croc_call(t, -2, 0);
		croc_popTop(t);
#ifdef CROC_BUILTIN_DOCS
		croc_newGlobal(t, "_subdocs");
#endif
		return 0;
	}
	}

	void initHashLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "hash", &loader);
#ifdef CROC_BUILTIN_DOCS
		auto hash = croc_ex_importNS(t, "hash");
		CrocDoc doc;
		croc_ex_doc_init(t, &doc, __FILE__);
		croc_ex_doc_push(&doc,
		DModule("hash")
		R"(This library contains functionality common to both tables and namespaces, which are two similar kinds of hash
		tables. It also defines the opApply methods for tables and namespaces.)");
			docFields(&doc, _globalFuncs);

			croc_vm_pushTypeMT(t, CrocType_Table);
				croc_ex_doc_push(&doc,
				DNs("table")
				R"()");
				docFields(&doc, _tableMetamethods);
				croc_ex_doc_pop(&doc, -1);
			croc_popTop(t);

			croc_vm_pushTypeMT(t, CrocType_Namespace);
				croc_ex_doc_push(&doc,
				DNs("namespace")
				R"()");
				docFields(&doc, _namespaceMetamethods);
				croc_ex_doc_pop(&doc, -1);
			croc_popTop(t);

			croc_field(t, hash, "_subdocs");
			croc_ex_doc_mergeModuleDocs(&doc);
			croc_popTop(t);
		croc_ex_doc_pop(&doc, -1);

		croc_pushString(t, "_subdocs");
		croc_removeKey(t, hash);
		croc_popTop(t);
#else
		croc_ex_import(t, "hash");
#endif
	}
}