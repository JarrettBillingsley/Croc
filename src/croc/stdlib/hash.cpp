
#include <stdlib.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
#include "croc/stdlib/hash_weaktables.croc.hpp"

	word_t _dup(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Table);
		auto t_ = Thread::from(t);
		push(t_, Value::from(getTable(t_, 1)->dup(t_->vm->mem)));
		return 1;
	}

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

	word_t _keys(CrocThread* t)
	{
		croc_ex_checkAnyParam(t, 1);
		return _keysImpl(t, 1);
	}

	word_t _values(CrocThread* t)
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

	word_t _apply(CrocThread* t)
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

	word_t _map(CrocThread* t)
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

	word_t _reduce(CrocThread* t)
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

	word_t _filter(CrocThread* t)
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

	word_t _clear(CrocThread* t)
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

	word_t _remove(CrocThread* t)
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

	word_t _tableOpApply(CrocThread* t)
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

	word_t _namespaceOpApply(CrocThread* t)
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

	const CrocRegisterFunc _globalFuncs[] =
	{
		{"dup",    1, &_dup            },
		{"keys",   1, &_keys           },
		{"values", 1, &_values         },
		{"apply",  2, &_apply          },
		{"map",    2, &_map            },
		{"reduce", 3, &_reduce         },
		{"filter", 2, &_filter         },
		{"take",   1, &_takeImpl<false>},
		{"pop",    1, &_takeImpl<true> },
		{"clear",  1, &_clear          },
		{"remove", 2, &_remove         },
		{nullptr, 0, nullptr}
	};

	const CrocRegisterFunc _tableMetamethods[] =
	{
		{"opApply", 1, &_tableOpApply},
		{nullptr, 0, nullptr}
	};

	const CrocRegisterFunc _namespaceMetamethods[] =
	{
		{"opApply", 1, &_namespaceOpApply},
		{nullptr, 0, nullptr}
	};

	word loader(CrocThread* t)
	{
		croc_ex_registerGlobals(t, _globalFuncs);

		croc_namespace_new(t, "table");
			croc_ex_registerFields(t, _tableMetamethods);
		croc_vm_setTypeMT(t, CrocType_Table);

		croc_namespace_new(t, "namespace");
			croc_ex_registerFields(t, _namespaceMetamethods);
		croc_vm_setTypeMT(t, CrocType_Namespace);

		// TODO:doc
		// version(CrocBuiltinDocs)
		// 	scope c = new Compiler(t, Compiler.getDefaultFlags(t) | Compiler.DocTable);
		// else
		// 	scope c = new Compiler(t);

		croc_pushStringn(t, hash_weaktables_croc_text, hash_weaktables_croc_length);
		croc_compiler_compileStmtsEx(t, "hash_weaktables.croc");

		croc_function_newScript(t, -1);
		croc_pushNull(t);
		croc_call(t, -2, 0);
		croc_popTop(t);

		// TODO:doc
		// version(CrocBuiltinDocs)
		// 	newGlobal(t, "_subdocs"); // store the sub-doctable in a global temporarily

		return 0;
	}
	}

	void initHashLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "hash", &loader);
		croc_ex_import(t, "hash");
	}
}