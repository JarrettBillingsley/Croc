/******************************************************************************
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

module minid.hashlib;

import minid.ex;
import minid.interpreter;
import minid.namespace;
import minid.table;
import minid.types;

struct HashLib
{
static:
	public void init(MDThread* t)
	{
		pushGlobal(t, "modules");
		field(t, -1, "customLoaders");

		newFunction(t, function uword(MDThread* t, uword numParams)
		{
			newFunction(t, &staticDup,    "dup");    newGlobal(t, "dup");
			newFunction(t, &staticKeys,   "keys");   newGlobal(t, "keys");
			newFunction(t, &staticValues, "values"); newGlobal(t, "values");
			newFunction(t, &staticApply,  "apply");  newGlobal(t, "apply");
			newFunction(t, &staticEach,   "each");   newGlobal(t, "each");
			newFunction(t, &remove,       "remove"); newGlobal(t, "remove");
			newFunction(t, &set,          "set");    newGlobal(t, "set");
			newFunction(t, &get,          "get");    newGlobal(t, "get");

			newNamespace(t, "table");
				newFunction(t, &tableDup,     "dup");     fielda(t, -2, "dup");
				newFunction(t, &tableKeys,    "keys");    fielda(t, -2, "keys");
				newFunction(t, &tableValues,  "values");  fielda(t, -2, "values");
				newFunction(t, &tableOpApply, "opApply"); fielda(t, -2, "opApply");
				newFunction(t, &tableEach,    "each");    fielda(t, -2, "each");
			setTypeMT(t, MDValue.Type.Table);
			
			newNamespace(t, "namespace");
				newFunction(t, &namespaceOpApply, "opApply"); fielda(t, -2, "opApply");
			setTypeMT(t, MDValue.Type.Namespace);

			return 0;
		}, "hash");

		fielda(t, -2, "hash");
		importModule(t, "hash");
		pop(t, 3);
	}

	uword dupImpl(MDThread* t, word slot)
	{
		auto tab = getTable(t, slot);

		newTable(t, table.length(tab));

		foreach(ref k, ref v; tab.data)
		{
			push(t, k);
			push(t, v);
			idxa(t, -3);
		}
		
		return 1;
	}
	
	uword keysImpl(MDThread* t, word slot)
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
		else
		{
			auto ns = getNamespace(t, slot);

			newArray(t, namespace.length(ns));
			word idx = 0;

			foreach(ref k, ref _; ns.data)
			{
				pushStringObj(t, k);
				idxai(t, -2, idx++);
			}
		}
		
		return 1;
	}
	
	uword valuesImpl(MDThread* t, word slot)
	{
		if(isTable(t, slot))
		{
			auto tab = getTable(t, slot);

			newArray(t, table.length(tab));
			word idx = 0;
	
			foreach(ref _, ref v; tab.data)
			{
				push(t, v);
				idxai(t, -2, idx++);
			}
		}
		else
		{
			auto ns = getNamespace(t, slot);

			newArray(t, namespace.length(ns));
			word idx = 0;

			foreach(ref _, ref v; ns.data)
			{
				push(t, v);
				idxai(t, -2, idx++);
			}
		}
		
		return 1;
	}
	
	uword tableIterator(MDThread* t, uword numParams)
	{
		getUpval(t, 0);
		auto tab = getTable(t, -1);

		getUpval(t, 1);
		uword idx = cast(uword)getInt(t, -1);

		MDValue* k = void, v = void;

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

	uword namespaceIterator(MDThread* t, uword numParams)
	{
		getUpval(t, 0);
		auto ns = getNamespace(t, -1);

		getUpval(t, 1);
		uword idx = cast(uword)getInt(t, -1);

		MDString** k = void;
		MDValue* v = void;

		if(ns.data.next(idx, k, v))
		{
			pushInt(t, idx);
			setUpval(t, 1);
			pushStringObj(t, *k);
			push(t, *v);
			return 2;
		}

		return 0;
	}

	uword opApplyImpl(MDThread* t, word slot)
	{
		if(isTable(t, slot))
		{
			dup(t, slot);
			pushInt(t, 0);
			newFunction(t, &tableIterator, "iterator", 2);
		}
		else
		{
			dup(t, slot);
			pushInt(t, 0);
			newFunction(t, &namespaceIterator, "iterator", 2);
		}

		return 1;
	}
	
	uword eachImpl(MDThread* t, word slot, word func)
	{
		MDValue* k = void, v = void;

		bool guts()
		{
			auto reg = dup(t, func);
			dup(t, slot);
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

		if(isTable(t, slot))
		{
			auto tab = getTable(t, slot);
			uword idx = 0;

			while(table.next(tab, idx, k, v))
				if(!guts())
					break;
		}
		else
		{
			auto ns = getNamespace(t, slot);
			uword idx = 0;
			
			MDString** s = void;
			MDValue val = void;
			v = &val;

			while(ns.data.next(idx, s, v))
			{
				val = *s;

				if(!guts())
					break;
			}
		}

		dup(t, slot);
		return 1;
	}

	uword tableDup(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Table);
		return dupImpl(t, 0);
	}

	uword tableKeys(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Table);
		return keysImpl(t, 0);
	}

	uword tableValues(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Table);
		return valuesImpl(t, 0);
	}

	uword tableOpApply(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Table);
		return opApplyImpl(t, 0);
	}

	uword tableEach(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Table);
		checkParam(t, 1, MDValue.Type.Function);
		return eachImpl(t, 0, 1);
	}

	uword namespaceOpApply(MDThread* t, uword numParams)
	{
		checkParam(t, 0, MDValue.Type.Namespace);
		return opApplyImpl(t, 0);
	}

	uword staticDup(MDThread* t, uword numParams)
	{
		checkParam(t, 1, MDValue.Type.Table);
		return dupImpl(t, 1);
	}

	uword staticKeys(MDThread* t, uword numParams)
	{
		if(!isTable(t, 1))
			checkParam(t, 1, MDValue.Type.Namespace);

		return keysImpl(t, 1);
	}

	uword staticValues(MDThread* t, uword numParams)
	{
		if(!isTable(t, 1))
			checkParam(t, 1, MDValue.Type.Namespace);

		return valuesImpl(t, 1);
	}

	uword staticApply(MDThread* t, uword numParams)
	{
		if(!isTable(t, 1))
			checkParam(t, 1, MDValue.Type.Namespace);

		return opApplyImpl(t, 1);
	}

	uword staticEach(MDThread* t, uword numParams)
	{
		if(!isTable(t, 1))
			checkParam(t, 1, MDValue.Type.Namespace);

		checkParam(t, 2, MDValue.Type.Function);
		return eachImpl(t, 1, 2);
	}

	uword remove(MDThread* t, uword numParams)
	{
		if(isTable(t, 1))
			checkAnyParam(t, 2);
		else if(isNamespace(t, 1))
			checkStringParam(t, 2);
		else
			paramTypeError(t, 1, "table|namespace");

		dup(t, 2);
		removeKey(t, 1);
		return 0;
	}

	uword set(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 3);

		if(isTable(t, 1))
		{
			checkAnyParam(t, 2);
			checkAnyParam(t, 3);
			dup(t, 2);
			dup(t, 3);
			idxa(t, 1, true);
		}
		else if(isNamespace(t, 1))
		{
			checkStringParam(t, 2);
			checkAnyParam(t, 3);
			dup(t, 2);
			dup(t, 3);
			fielda(t, 1, true);
		}
		else
			paramTypeError(t, 1, "table|namespace");

		return 0;
	}

	uword get(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 2);

		if(isTable(t, 1))
		{
			checkAnyParam(t, 2);
			dup(t, 2);
			idx(t, 1, true);
		}
		else if(isNamespace(t, 1))
		{
			checkStringParam(t, 2);
			dup(t, 2);
			field(t, 1, true);
		}
		else
			paramTypeError(t, 1, "table|namespace");

		return 1;
	}
}