/******************************************************************************
This module contains the 'hash' standard library.

License:
Copyright (c) 2008 Jarrett Billingsley

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

module croc.stdlib_hash;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.types;
import croc.types_namespace;
import croc.types_table;

struct HashLib
{
static:
	public void init(CrocThread* t)
	{
		makeModule(t, "hash", function uword(CrocThread* t)
		{
			newFunction(t, 1, &_dup,    "dup");    newGlobal(t, "dup");
			newFunction(t, 1, &_keys,   "keys");   newGlobal(t, "keys");
			newFunction(t, 1, &_values, "values"); newGlobal(t, "values");
			newFunction(t, 2, &apply,   "apply");  newGlobal(t, "apply");
			newFunction(t, 2, &each,    "each");   newGlobal(t, "each");
			newFunction(t, 1, &take,    "take");   newGlobal(t, "take");
			newFunction(t, 1, &clear,   "clear");  newGlobal(t, "clear");
			newFunction(t, 2, &remove,  "remove"); newGlobal(t, "remove");

			newNamespace(t, "table");
				newFunction(t, 1, &tableOpApply, "opApply"); fielda(t, -2, "opApply");
			setTypeMT(t, CrocValue.Type.Table);

			newNamespace(t, "namespace");
				newFunction(t, 1, &namespaceOpApply, "opApply"); fielda(t, -2, "opApply");
			setTypeMT(t, CrocValue.Type.Namespace);

			return 0;
		});

		importModuleNoNS(t, "hash");
	}

	uword _dup(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Table);
		auto tab = getTable(t, 1);

		newTable(t, table.length(tab));

		foreach(ref k, ref v; tab.data)
		{
			push(t, k);
			push(t, v);
			idxa(t, -3);
		}

		return 1;
	}

	uword _keys(CrocThread* t)
	{
		checkAnyParam(t, 1);
		return keysImpl(t, 1);
	}

	uword _values(CrocThread* t)
	{
		checkAnyParam(t, 1);

		if(isTable(t, 1))
		{
			auto tab = getTable(t, 1);

			newArray(t, table.length(tab));
			word idx = 0;

			foreach(ref _, ref v; tab.data)
			{
				push(t, v);
				idxai(t, -2, idx++);
			}
		}
		else if(isNamespace(t, 1))
		{
			auto ns = getNamespace(t, 1);

			newArray(t, namespace.length(ns));
			word idx = 0;

			foreach(ref _, ref v; ns.data)
			{
				push(t, v);
				idxai(t, -2, idx++);
			}
		}
		else
			paramTypeError(t, 1, "table|namespace");

		return 1;
	}

	uword apply(CrocThread* t)
	{
		checkAnyParam(t, 1);
		return opApplyImpl(t, 1);
	}

	uword each(CrocThread* t)
	{
		checkParam(t, 2, CrocValue.Type.Function);

		CrocValue* k = void, v = void;

		bool guts()
		{
			auto reg = dup(t, 2);
			dup(t, 1);
			push(t, *k);
			push(t, *v);

			rawCall(t, reg, 1);

			if(!isNull(t, -1))
			{
				if(!isBool(t, -1))
				{
					pushTypeString(t, -1);
					throwException(t, "'each' function expected to return 'bool', not '{}'", getString(t, -1));
				}

				if(getBool(t, -1) == false)
				{
					pop(t);
					return false;
				}
			}

			pop(t);
			return true;
		}

		if(isTable(t, 1))
		{
			auto tab = getTable(t, 1);
			uword idx = 0;

			while(table.next(tab, idx, k, v))
				if(!guts())
					break;
		}
		else if(isNamespace(t, 1))
		{
			auto ns = getNamespace(t, 1);
			uword idx = 0;
			CrocString** s = void;
			CrocValue key = void;
			k = &key;

			while(ns.data.next(idx, s, v))
			{
				key = *s;

				if(!guts())
					break;
			}
		}
		else
			paramTypeError(t, 1, "table|namespace");

		dup(t, 1);
		return 1;
	}

	uword take(CrocThread* t)
	{
		checkAnyParam(t, 1);

		if(isTable(t, 1))
		{
			auto tab = getTable(t, 1);
			uword idx = 0;
			CrocValue* k = void, v = void;

			if(table.next(tab, idx, k, v))
			{
				push(t, *k);
				push(t, *v);
			}
			else
				throwException(t, "Attempting to take from an empty table");
		}
		else if(isNamespace(t, 1))
		{
			auto ns = getNamespace(t, 1);
			uword idx = 0;
			CrocString** s = void;
			CrocValue* v = void;

			if(ns.data.next(idx, s, v))
			{
				push(t, CrocValue(*s));
				push(t, *v);
			}
			else
				throwException(t, "Attempting to take from an empty namespace");
		}
		else
			paramTypeError(t, 1, "table|namespace");

		return 2;
	}

	uword clear(CrocThread* t)
	{
		checkAnyParam(t, 1);

		if(isTable(t, 1))
			clearTable(t, 1);
		else if(isNamespace(t, 1))
			clearNamespace(t, 1);
		else
			paramTypeError(t, 1, "table|namespace");

		return 0;
	}

	uword remove(CrocThread* t)
	{
		checkAnyParam(t, 1);

		if(isTable(t, 1))
			checkAnyParam(t, 2);
		else if(isNamespace(t, 1))
			checkStringParam(t, 2);
		else
			paramTypeError(t, 1, "table|namespace");

		removeKey(t, 1);
		return 0;
	}

	uword keysImpl(CrocThread* t, word slot)
	{
		if(isTable(t, slot))
		{
			auto tab = getTable(t, slot);

			newArray(t, table.length(tab));
			word idx = 0;

			foreach(ref k, ref _; tab.data)
			{
				push(t, k);
				idxai(t, -2, idx++);
			}
		}
		else if(isNamespace(t, slot))
		{
			auto ns = getNamespace(t, slot);

			newArray(t, namespace.length(ns));
			word idx = 0;

			foreach(ref k, ref _; ns.data)
			{
				push(t, CrocValue(k));
				idxai(t, -2, idx++);
			}
		}
		else
			paramTypeError(t, slot, "table|namespace");

		return 1;
	}

	uword tableIterator(CrocThread* t)
	{
		getUpval(t, 0);
		auto tab = getTable(t, -1);
		getUpval(t, 1);
		uword idx = cast(uword)getInt(t, -1);

		CrocValue* k = void, v = void;

		if(table.next(tab, idx, k, v))
		{
			pushInt(t, idx);
			setUpval(t, 1);
			push(t, *k);
			push(t, *v);
			return 2;
		}

		return 0;
	}

	uword modTableIterator(CrocThread* t)
	{
		getUpval(t, 0);
		auto tab = getTable(t, -1);
		getUpval(t, 1);
		auto keys = getArray(t, -1);
		getUpval(t, 2);
		uword idx = cast(uword)getInt(t, -1) + 1;

		pop(t, 3);

		for(; idx < keys.length; idx++)
		{
			if(auto v = table.get(tab, keys.data[idx]))
			{
				pushInt(t, idx);
				setUpval(t, 2);
				push(t, keys.data[idx]);
				push(t, *v);
				return 2;
			}
		}

		return 0;
	}

	uword namespaceIterator(CrocThread* t)
	{
		getUpval(t, 0);
		auto ns = getNamespace(t, -1);
		getUpval(t, 1);
		uword idx = cast(uword)getInt(t, -1);
		CrocString** k = void;
		CrocValue* v = void;

		if(ns.data.next(idx, k, v))
		{
			pushInt(t, idx);
			setUpval(t, 1);
			push(t, CrocValue(*k));
			push(t, *v);
			return 2;
		}

		return 0;
	}

	uword modNamespaceIterator(CrocThread* t)
	{
		getUpval(t, 0);
		auto ns = getNamespace(t, -1);
		getUpval(t, 1);
		auto keys = getArray(t, -1);
		getUpval(t, 2);
		uword idx = cast(uword)getInt(t, -1) + 1;

		pop(t, 3);

		for(; idx < keys.length; idx++)
		{
			if(auto v = namespace.get(ns, keys.data[idx].mString))
			{
				pushInt(t, idx);
				setUpval(t, 2);
				push(t, keys.data[idx]);
				push(t, *v);
				return 2;
			}
		}

		return 0;
	}

	uword opApplyImpl(CrocThread* t, word slot)
	{
		// in case it was called as a method with no params
		setStackSize(t, slot + 2);

		if(isTable(t, slot))
		{
			dup(t, slot);

			if(optStringParam(t, slot + 1, "") == "modify")
			{
				keysImpl(t, slot);
				pushInt(t, -1);
				newFunction(t, &modTableIterator, "iterator", 3);
			}
			else
			{
				pushInt(t, 0);
				newFunction(t, &tableIterator, "iterator", 2);
			}
		}
		else if(isNamespace(t, slot))
		{
			dup(t, slot);

			if(optStringParam(t, slot + 1, "") == "modify")
			{
				keysImpl(t, slot);
				pushInt(t, -1);
				newFunction(t, &modNamespaceIterator, "iterator", 3);
			}
			else
			{
				pushInt(t, 0);
				newFunction(t, &namespaceIterator, "iterator", 2);
			}
		}
		else
			paramTypeError(t, slot, "table|namespace");

		return 1;
	}

	uword tableOpApply(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Table);
		return opApplyImpl(t, 0);
	}

	uword namespaceOpApply(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Namespace);
		return opApplyImpl(t, 0);
	}
}