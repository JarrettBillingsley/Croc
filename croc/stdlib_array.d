/******************************************************************************
This module contains the 'array' standard library.

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

module croc.stdlib_array;

import tango.core.Array;
import tango.core.Tuple;
import tango.math.Math;

import croc.api_interpreter;
import croc.api_stack;
import croc.base_alloc;
import croc.base_gc;
import croc.ex;
import croc.ex_library;
import croc.types;
import croc.types_array;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initArrayLib(CrocThread* t)
{
	makeModule(t, "array", function uword(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);

		newNamespace(t, "array");
			registerFields(t, _methodFuncs);

				newFunction(t, 1, &_iterator,        "iterator");
				newFunction(t, 1, &_iteratorReverse, "iteratorReverse");
			newFunction(t, 1, &_opApply, "opApply", 2);
			fielda(t, -2, "opApply");

				newTable(t);
			newFunction(t, 0, &_flatten, "flatten", 1);
			fielda(t, -2, "flatten");
		setTypeMT(t, CrocValue.Type.Array);

		return 0;
	});

	importModule(t, "array");

	version(CrocBuiltinDocs)
	{
		scope doc = new CrocDoc(t, __FILE__);
		doc.push(Docs("module", "Array Library",
		`The array library provides functionality for creating and manipulating arrays. Most of these
		functions are accessed as methods of array objects. There are a few functions which are called
		through the "\tt{array}" namespace.`));

		docFields(t, doc, _globalFuncDocs);

		getTypeMT(t, CrocValue.Type.Array);
			docFields(t, doc, _methodFuncDocs);
		pop(t);

		doc.pop(-1);
	}

	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

// ===================================================================================================================================
// Global functions

const RegisterFunc[] _globalFuncs =
[
	{"new",   &_new,   maxParams: 2},
	{"range", &_range, maxParams: 3}
];

uword _new(CrocThread* t)
{
	auto length = checkIntParam(t, 1);
	auto numParams = stackSize(t) - 1;

	if(length < 0 || length > uword.max)
		throwStdException(t, "RangeError", "Invalid length: {}", length);

	newArray(t, cast(uword)length);

	if(numParams > 1)
	{
		dup(t, 2);
		fillArray(t, -2);
	}

	return 1;
}

uword _range(CrocThread* t)
{
	auto v1 = checkIntParam(t, 1);
	auto numParams = stackSize(t) - 1;
	crocint v2;
	crocint step = 1;

	if(numParams == 1)
	{
		v2 = v1;
		v1 = 0;
	}
	else if(numParams == 2)
		v2 = checkIntParam(t, 2);
	else
	{
		v2 = checkIntParam(t, 2);
		step = checkIntParam(t, 3);
	}

	if(step <= 0)
		throwStdException(t, "RangeError", "Step may not be negative or 0");

	crocint range = abs(v2 - v1);
	crocint size = range / step;

	if((range % step) != 0)
		size++;

	if(size > uword.max)
		throwStdException(t, "RangeError", "Array is too big");

	newArray(t, cast(uword)size);
	auto a = getArray(t, -1);

	auto val = v1;

	// no write barrier here. the array is new and we're filling it with scalars.
	auto data = a.toArray();

	if(v2 < v1)
	{
		for(uword i = 0; val > v2; i++, val -= step)
			data[i].value = val;
	}
	else
	{
		for(uword i = 0; val < v2; i++, val += step)
			data[i].value = val;
	}

	return 1;
}

// ===================================================================================================================================
// Methods

const RegisterFunc[] _methodFuncs =
[
	{"opEquals", &_opEquals, maxParams: 1},
	{"sort",     &_sort,     maxParams: 1},
	{"reverse",  &_reverse,  maxParams: 0},
	{"dup",      &_dup,      maxParams: 0},
	{"expand",   &_expand,   maxParams: 0},
	{"toString", &_toString, maxParams: 0},
	{"apply",    &_apply,    maxParams: 1},
	{"map",      &_map,      maxParams: 1},
	{"reduce",   &_reduce,   maxParams: 2},
	{"rreduce",  &_rreduce,  maxParams: 2},
	{"filter",   &_filter,   maxParams: 1},
	{"find",     &_find,     maxParams: 1},
	{"findIf",   &_findIf,   maxParams: 1},
	{"bsearch",  &_bsearch,  maxParams: 1},
	{"pop",      &_pop,      maxParams: 1},
	{"insert",   &_insert,   maxParams: 2},
	{"swap",     &_swap,     maxParams: 2},
	{"set",      &_set},
	{"min",      &_min,      maxParams: 0},
	{"max",      &_max,      maxParams: 0},
	{"extreme",  &_extreme,  maxParams: 1},
	{"any",      &_any,      maxParams: 1},
	{"all",      &_all,      maxParams: 1},
	{"fill",     &_fill,     maxParams: 1},
	{"append",   &_append},
	{"count",    &_count,    maxParams: 2},
	{"countIf",  &_countIf,  maxParams: 1}
];

uword _opEquals(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	checkParam(t, 1, CrocValue.Type.Array);
	pushBool(t, getArray(t, 0).toArray() == getArray(t, 1).toArray());
	return 1;
}

uword _sort(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	checkParam(t, 0, CrocValue.Type.Array);

	bool delegate(CrocArray.Slot, CrocArray.Slot) pred;

	if(numParams > 0)
	{
		if(isString(t, 1))
		{
			if(getString(t, 1) == "reverse")
			{
				pred = (CrocArray.Slot v1, CrocArray.Slot v2)
				{
					push(t, v1.value);
					push(t, v2.value);
					auto v = cmp(t, -2, -1);
					pop(t, 2);
					return v > 0;
				};
			}
			else
				throwStdException(t, "ValueError", "Unknown array sorting method");
		}
		else
		{
			checkParam(t, 1, CrocValue.Type.Function);
			dup(t);

			pred = (CrocArray.Slot v1, CrocArray.Slot v2)
			{
				auto reg = dup(t);
				pushNull(t);
				push(t, v1.value);
				push(t, v2.value);
				call(t, reg, 1);

				if(!isInt(t, -1))
				{
					pushTypeString(t, -1);
					throwStdException(t, "TypeError", "comparison function expected to return 'int', not '{}'", getString(t, -1));
				}

				auto v = getInt(t, -1);
				pop(t);
				return v < 0;
			};
		}
	}
	else
	{
		pred = (CrocArray.Slot v1, CrocArray.Slot v2)
		{
			push(t, v1.value);
			push(t, v2.value);
			auto v = cmp(t, -2, -1);
			pop(t, 2);
			return v < 0;
		};
	}

	// No write barrier. we're just moving items around, the items themselves don't change.
	.sort(getArray(t, 0).toArray(), pred);
	dup(t, 0);
	return 1;
}

uword _reverse(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	// No write barrier. Just moving items around.
	getArray(t, 0).toArray().reverse;
	dup(t, 0);
	return 1;
}

uword _dup(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	newArray(t, cast(uword)len(t, 0)); // this should be fine?  since arrays can't be longer than uword.max
	auto dest = getArray(t, -1);
	array.sliceAssign(t.vm.alloc, dest, 0, dest.length, getArray(t, 0));
	return 1;
}

uword _iterator(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	auto index = checkIntParam(t, 1) + 1;

	if(index >= len(t, 0))
		return 0;

	pushInt(t, index);
	dup(t);
	idx(t, 0);

	return 2;
}

uword _iteratorReverse(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	auto index = checkIntParam(t, 1) - 1;

	if(index < 0)
		return 0;

	pushInt(t, index);
	dup(t);
	idx(t, 0);

	return 2;
}

uword _opApply(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);

	if(optStringParam(t, 1, "") == "reverse")
	{
		getUpval(t, 1);
		dup(t, 0);
		pushLen(t, 0);
	}
	else
	{
		getUpval(t, 0);
		dup(t, 0);
		pushInt(t, -1);
	}

	return 3;
}

uword _expand(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	auto a = getArray(t, 0);

	foreach(ref val; a.toArray())
		push(t, val.value);

	return a.length;
}

uword _toString(CrocThread* t)
{
	auto buf = StrBuffer(t);
	buf.addChar('[');

	auto length = len(t, 0);

	for(uword i = 0; i < length; i++)
	{
		pushInt(t, i);
		idx(t, 0);

		if(isString(t, -1))
		{
			// this is GC-safe since the string is stored in the array
			auto s = getString(t, -1);
			pop(t);
			buf.addChar('"');
			buf.addString(s);
			buf.addChar('"');
		}
		else
		{
			pushToString(t, -1, true);
			insertAndPop(t, -2);
			buf.addTop();
		}

		if(i < length - 1)
			buf.addString(", ");
	}

	buf.addChar(']');
	buf.finish();

	return 1;
}

uword _apply(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	checkParam(t, 1, CrocValue.Type.Function);

	auto data = getArray(t, 0).toArray();

	foreach(i, ref v; data)
	{
		auto reg = dup(t, 1);
		dup(t, 0);
		push(t, v.value);
		call(t, reg, 1);
		idxai(t, 0, i);
	}

	dup(t, 0);
	return 1;
}

uword _map(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	checkParam(t, 1, CrocValue.Type.Function);
	auto newArr = newArray(t, cast(uword)len(t, 0));

	foreach(i, ref v; getArray(t, 0).toArray())
	{
		auto reg = dup(t, 1);
		dup(t, 0);
		push(t, v.value);
		call(t, reg, 1);
		idxai(t, newArr, i);
	}

	return 1;
}

uword _reduce(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	checkParam(t, 0, CrocValue.Type.Array);
	checkParam(t, 1, CrocValue.Type.Function);

	uword length = cast(uword)len(t, 0);

	if(length == 0)
	{
		if(numParams == 1)
			throwStdException(t, "ParamError", "Attempting to reduce an empty array without an initial value");
		else
		{
			dup(t, 2);
			return 1;
		}
	}

	uword start = 0;

	if(numParams == 1)
	{
		idxi(t, 0, 0);
		start = 1;
	}
	else
		dup(t, 2);

	for(uword i = start; i < length; i++)
	{
		dup(t, 1);
		pushNull(t);
		dup(t, -3);
		idxi(t, 0, i);
		call(t, -4, 1);
		insertAndPop(t, -2);
	}

	return 1;
}

uword _rreduce(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	checkParam(t, 0, CrocValue.Type.Array);
	checkParam(t, 1, CrocValue.Type.Function);

	uword length = cast(uword)len(t, 0);

	if(length == 0)
	{
		if(numParams == 1)
			throwStdException(t, "ParamError", "Attempting to reduce an empty array without an initial value");
		else
		{
			dup(t, 2);
			return 1;
		}
	}

	uword start = length - 1;

	if(numParams == 1)
	{
		idxi(t, 0, length - 1);
		start--;
	}
	else
		dup(t, 2);

	for(uword i = start; ; i--)
	{
		dup(t, 1);
		pushNull(t);
		idxi(t, 0, i);
		dup(t, -4);
		call(t, -4, 1);
		insertAndPop(t, -2);

		if(i == 0)
			break;
	}

	return 1;
}

uword _filter(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	checkParam(t, 1, CrocValue.Type.Function);

	auto newLen = len(t, 0) / 2;
	auto retArray = newArray(t, cast(uword)newLen);
	uword retIdx = 0;

	foreach(i, ref v; getArray(t, 0).toArray())
	{
		dup(t, 1);
		dup(t, 0);
		pushInt(t, i);
		push(t, v.value);
		call(t, -4, 1);

		if(!isBool(t, -1))
		{
			pushTypeString(t, -1);
			throwStdException(t, "TypeError", "filter function expected to return 'bool', not '{}'", getString(t, -1));
		}

		if(getBool(t, -1))
		{
			if(retIdx >= newLen)
			{
				newLen += 10;
				pushInt(t, newLen);
				lena(t, retArray);
			}

			push(t, v.value);
			idxai(t, retArray, retIdx);
			retIdx++;
		}

		pop(t);
	}

	pushInt(t, retIdx);
	lena(t, retArray);
	dup(t, retArray);
	return 1;
}

uword _find(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	checkAnyParam(t, 1);

	foreach(i, ref v; getArray(t, 0).toArray())
	{
		push(t, v.value);

		if(type(t, 1) == v.value.type && cmp(t, 1, -1) == 0)
		{
			pushInt(t, i);
			return 1;
		}
	}

	pushLen(t, 0);
	return 1;
}

uword _findIf(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	checkParam(t, 1, CrocValue.Type.Function);

	foreach(i, ref v; getArray(t, 0).toArray())
	{
		auto reg = dup(t, 1);
		pushNull(t);
		push(t, v.value);
		call(t, reg, 1);

		if(!isBool(t, -1))
		{
			pushTypeString(t, -1);
			throwStdException(t, "TypeError", "find function expected to return 'bool', not '{}'", getString(t, -1));
		}

		if(getBool(t, -1))
		{
			pushInt(t, i);
			return 1;
		}

		pop(t);
	}

	pushLen(t, 0);
	return 1;
}

uword _bsearch(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	checkAnyParam(t, 1);

	uword lo = 0;
	uword hi = cast(uword)len(t, 0) - 1;
	uword mid = (lo + hi) >> 1;

	while((hi - lo) > 8)
	{
		idxi(t, 0, mid);
		auto cmp = cmp(t, 1, -1);
		pop(t);

		if(cmp == 0)
		{
			pushInt(t, mid);
			return 1;
		}
		else if(cmp < 0)
			hi = mid;
		else
			lo = mid;

		mid = (lo + hi) >> 1;
	}

	for(auto i = lo; i <= hi; i++)
	{
		idxi(t, 0, i);

		if(cmp(t, 1, -1) == 0)
		{
			pushInt(t, i);
			return 1;
		}

		pop(t);
	}

	pushLen(t, 0);
	return 1;
}

uword _pop(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	auto a = getArray(t, 0);
	auto data = a.toArray();
	crocint index = optIntParam(t, 1, -1);

	if(data.length == 0)
		throwStdException(t, "ValueError", "Array is empty");

	if(index < 0)
		index += data.length;

	if(index < 0 || index >= data.length)
		throwStdException(t, "BoundsError", "Invalid array index: {}", index);

	idxi(t, 0, index);

	mixin(array.removeRef!("t.vm.alloc", "data[cast(uword)index]"));

	for(uword i = cast(uword)index; i < data.length - 1; i++)
		data[i] = data[i + 1];

	data[$ - 1].value = CrocValue.nullValue;
	array.resize(t.vm.alloc, getArray(t, 0), data.length - 1);
	return 1;
}

uword _insert(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	auto a = getArray(t, 0);
	auto data = a.toArray();
	crocint index = checkIntParam(t, 1);
	checkAnyParam(t, 2);

	if(index < 0)
		index += data.length;

	if(index < 0 || index > data.length)
		throwStdException(t, "BoundsError", "Invalid array index: {}", index);

	array.resize(t.vm.alloc, getArray(t, 0), data.length + 1);
	data = a.toArray();

	for(uword i = data.length - 1; i > index; i--)
		data[i] = data[i - 1];

	dup(t, 2);
	idxai(t, 0, index);
	dup(t, 0);
	return 1;
}

uword _swap(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	auto a = getArray(t, 0);
	auto data = a.toArray();
	crocint idx1 = checkIntParam(t, 1);
	crocint idx2 = checkIntParam(t, 2);

	if(idx1 < 0) idx1 += data.length;
	if(idx2 < 0) idx2 += data.length;

	if(idx1 < 0 || idx1 >= data.length)
		throwStdException(t, "BoundsError", "Invalid array index: {}", idx1);

	if(idx2 < 0 || idx2 >= data.length)
		throwStdException(t, "BoundsError", "Invalid array index: {}", idx2);

	if(idx1 != idx2)
	{
		auto tmp = data[cast(uword)idx1];
		data[cast(uword)idx1] = data[cast(uword)idx2];
		data[cast(uword)idx2] = tmp;
	}

	dup(t, 0);
	return 1;
}

uword _set(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	checkParam(t, 0, CrocValue.Type.Array);
	auto a = getArray(t, 0);

	array.resize(t.vm.alloc, a, numParams);
	array.sliceAssign(t.vm.alloc, a, 0, numParams, t.stack[t.stackIndex - numParams .. t.stackIndex]);

	dup(t, 0);
	return 1;
}

uword _minMaxImpl(CrocThread* t, uword numParams, bool max)
{
	checkParam(t, 0, CrocValue.Type.Array);
	auto data = getArray(t, 0).toArray();

	if(data.length == 0)
		throwStdException(t, "ValueError", "Array is empty");

	auto extreme = data[0].value;
	uword extremeIdx = 0;

	if(numParams > 0)
	{
		for(uword i = 1; i < data.length; i++)
		{
			dup(t, 1);
			pushNull(t);
			idxi(t, 0, i);
			push(t, extreme);
			call(t, -4, 1);

			if(!isBool(t, -1))
			{
				pushTypeString(t, -1);
				throwStdException(t, "TypeError", "extrema function should return 'bool', not '{}'", getString(t, -1));
			}

			if(getBool(t, -1))
			{
				extreme = data[i].value;
				extremeIdx = i;
			}

			pop(t);
		}

		push(t, extreme);
	}
	else
	{
		idxi(t, 0, 0);

		if(max)
		{
			for(uword i = 1; i < data.length; i++)
			{
				idxi(t, 0, i);

				if(cmp(t, -1, -2) > 0)
				{
					extremeIdx = i;
					insert(t, -2);
				}

				pop(t);
			}
		}
		else
		{
			for(uword i = 1; i < data.length; i++)
			{
				idxi(t, 0, i);

				if(cmp(t, -1, -2) < 0)
				{
					extremeIdx = i;
					insert(t, -2);
				}

				pop(t);
			}
		}
	}

	pushInt(t, extremeIdx);
	return 2;
}

uword _min(CrocThread* t)
{
	return _minMaxImpl(t, 0, false);
}

uword _max(CrocThread* t)
{
	return _minMaxImpl(t, 0, true);
}

uword _extreme(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	checkParam(t, 1, CrocValue.Type.Function);
	return _minMaxImpl(t, numParams, false);
}

uword _all(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	checkParam(t, 0, CrocValue.Type.Array);

	if(numParams > 0)
	{
		checkParam(t, 1, CrocValue.Type.Function);

		foreach(ref v; getArray(t, 0).toArray())
		{
			dup(t, 1);
			pushNull(t);
			push(t, v.value);
			call(t, -3, 1);

			if(!isTrue(t, -1))
			{
				pushBool(t, false);
				return 1;
			}

			pop(t);
		}
	}
	else
	{
		foreach(ref v; getArray(t, 0).toArray())
		{
			if(v.value.isFalse())
			{
				pushBool(t, false);
				return 1;
			}
		}
	}

	pushBool(t, true);
	return 1;
}

uword _any(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	checkParam(t, 0, CrocValue.Type.Array);

	if(numParams > 0)
	{
		checkParam(t, 1, CrocValue.Type.Function);

		foreach(ref v; getArray(t, 0).toArray())
		{
			dup(t, 1);
			pushNull(t);
			push(t, v.value);
			call(t, -3, 1);

			if(isTrue(t, -1))
			{
				pushBool(t, true);
				return 1;
			}

			pop(t);
		}
	}
	else
	{
		foreach(ref v; getArray(t, 0).toArray())
		{
			if(!v.value.isFalse())
			{
				pushBool(t, true);
				return 1;
			}
		}
	}

	pushBool(t, false);
	return 1;
}

uword _fill(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	checkAnyParam(t, 1);
	dup(t, 1);
	fillArray(t, 0);
	return 0;
}

uword _append(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	checkParam(t, 0, CrocValue.Type.Array);
	auto a = getArray(t, 0);

	if(numParams == 0)
		return 0;

	auto oldlen = a.length;
	array.resize(t.vm.alloc, a, a.length + numParams);
	array.sliceAssign(t.vm.alloc, a, oldlen, oldlen + numParams, t.stack[t.stackIndex - numParams .. t.stackIndex]);

	return 0;
}

uword _flatten(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	auto flattening = getUpval(t, 0);

	auto ret = newArray(t, 0);

	void flatten(word arr)
	{
		auto a = absIndex(t, arr);

		if(opin(t, a, flattening))
			throwStdException(t, "ValueError", "Attempting to flatten a self-referencing array");

		dup(t, a);
		pushBool(t, true);
		idxa(t, flattening);

		scope(exit)
		{
			dup(t, a);
			pushNull(t);
			idxa(t, flattening);
		}

		foreach(ref val; getArray(t, a).toArray())
		{
			if(val.value.type == CrocValue.Type.Array)
				flatten(push(t, CrocValue(val.value.mArray)));
			else
			{
				push(t, val.value);
				cateq(t, ret, 1);
			}
		}
	}

	flatten(0);
	dup(t, ret);
	return 1;
}

uword _count(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;
	checkParam(t, 0, CrocValue.Type.Array);
	checkAnyParam(t, 1);

	bool delegate(CrocArray.Slot, CrocArray.Slot) pred;

	if(numParams > 1)
	{
		checkParam(t, 2, CrocValue.Type.Function);

		pred = (CrocArray.Slot a, CrocArray.Slot b)
		{
			auto reg = dup(t, 2);
			pushNull(t);
			push(t, a.value);
			push(t, b.value);
			call(t, reg, 1);

			if(!isBool(t, -1))
			{
				pushTypeString(t, -1);
				throwStdException(t, "TypeError", "count predicate expected to return 'bool', not '{}'", getString(t, -1));
			}

			auto ret = getBool(t, -1);
			pop(t);
			return ret;
		};
	}
	else
	{
		pred = (CrocArray.Slot a, CrocArray.Slot b)
		{
			push(t, a.value);
			push(t, b.value);
			auto ret = cmp(t, -2, -1) == 0;
			pop(t, 2);
			return ret;
		};
	}

	auto tmp = CrocArray.Slot(*getValue(t, 1), false);
	pushInt(t, .count(getArray(t, 0).toArray(), tmp, pred));
	return 1;
}

uword _countIf(CrocThread* t)
{
	checkParam(t, 0, CrocValue.Type.Array);
	checkParam(t, 1, CrocValue.Type.Function);

	pushInt(t, .countIf(getArray(t, 0).toArray(), (CrocArray.Slot a)
	{
		auto reg = dup(t, 1);
		pushNull(t);
		push(t, a.value);
		call(t, reg, 1);

		if(!isBool(t, -1))
		{
			pushTypeString(t, -1);
			throwStdException(t, "TypeError", "count predicate expected to return 'bool', not '{}'", getString(t, -1));
		}

		auto ret = getBool(t, -1);
		pop(t);
		return ret;
	}));

	return 1;
}

version(CrocBuiltinDocs)
{
	const Docs[] _globalFuncDocs =
	[
		{kind: "function", name: "array.new",
		params: [Param("size", "int"), Param("fill", "any", "null")],
		extra: [Extra("section", "Functions"), Extra("protection", "global")],
		docs:
		`You can use array literals to create arrays in Croc, but sometimes you just need to be able to
		create an array of arbitrary size. This function will create an array of the given size. If
		you pass a value for the \tt{fill} parameter, the new array will have every element set to it.
		Otherwise, it will be filled with \tt{null}.`},

		{kind: "function", name: "array.range",
		params: [Param("val1", "int"), Param("val2", "int", "null"), Param("step", "int", "null")],
		extra: [Extra("section", "Functions"), Extra("protection", "global")],
		docs:
		`Creates a new array filled with integer values specified by the arguments. This is similar to
		the Python \tt{range()} function, but is a little more intelligent when it comes to the direction
		of the range. Namely, if you give it indices where the ending index is less than the beginning,
		it will automatically use a negative step. In fact, the step value passed to this function must
		always be greater than 0; it simply defines the size of the step regardless of the direction the
		range goes in.

		If only one argument is given, that argument specifies the noninclusive ending index, and the
		beginning index is assumed to be 0 and the step to be 1. This means \tt{array.range(5)} will return
		\tt{[0, 1, 2, 3, 4]} and \tt{array.range(-5)} will return \tt{[0, -1, -2, -3, -4]}.

		If two arguments are given, the first is the beginning inclusive index and the second is the
		ending noninclusive index. The step is again assumed to be 1. Examples: \tt{array.range(3, 8)}
		yields \tt{[3, 4, 5, 6, 7]}; \tt{array.range(2, -2)} yields \tt{[2, 1, 0, -1]}; and \tt{array.range(-10, -7)}
		yields \tt{[-10, -9, -8]}.

		Lastly, if three arguments are given, the first is the beginning inclusive index, the second the
		ending noninclusive index, and the third the step value. The step must be greater than 0; this
		function will automatically figure out that it needs to subtract the step if the ending index is
		less than the beginning index. Example: \tt{array.range(1, 20, 4)} yields \tt{[1, 5, 9, 13, 17]} and
		\tt{array.range(10, 0, 2)} yields \tt{[10, 8, 6, 4, 2]}.`}
	];

	const Docs[] _methodFuncDocs =
	[
		{kind: "function", name: "array.opEquals",
		params: [Param("other", "array")],
		extra: [Extra("section", "Functions"), Extra("protection", "global")],
		docs:
		`Compares two arrays for shallow equality. Shallow equality means two arrays are equal if they
		are the same length, and for each index i, \tt{a[i] is b[i]} is true. This does not call opEquals
		metamethods on any of the arrays' elements.`},

		{kind: "function", name: "sort",
		params: [Param("how", "function|string", "null")],
		extra: [Extra("section", "Methods")],
		docs:
		`Sorts the given array. All the elements must be comparable with one another. Will call any
		\b{\tt{opCmp}} metamethods. Returns the array itself.

		If no parameters are given, sorts the array in ascending order.

		If the optional \tt{how} parameter is given the string \tt{"reverse"}, the array will be sorted
		in descending order.

		If the \tt{how} parameter is a function, it is treated as a sorting predicate. It should take
		two arguments, compare them, and return an ordering integer (i.e. negative if the first is
		less than the second, positive if the first is greater than the second, and 0 if they are
		equal).`},

		{kind: "function", name: "reverse",
		params: [],
		extra: [Extra("section", "Methods")],
		docs:
		`Reverses the elements in the given array in-place.

		\returns the array itself.`},

		{kind: "function", name: "dup",
		params: [],
		extra: [Extra("section", "Methods")],
		docs:
		`Creates a copy of the given array. Only the array elements are copied, not any data that
		they point to.`},

		{kind: "function", name: "opApply",
		params: [Param("mode", "string", "null")],
		extra: [Extra("section", "Methods")],
		docs:
		`This allows you to iterate over arrays using \tt{foreach} loops.
\code
foreach(i, v; a)
// ...

foreach(i, v; a, "reverse")
// iterate backwards
\endcode

		As the second example shows, passing in the string "reverse" as the second parameter will
		cause the iteration to run in reverse.`},

		{kind: "function", name: "expand",
		params: [],
		extra: [Extra("section", "Methods")],
		docs:
		`Returns all the elements of the array in order. In this way, you can "unpack" an array's
		values to pass as separate parameters to a function, or as return values, etc. Note that you
		probably shouldn't use this on really big arrays.`},

		{kind: "function", name: "toString",
		params: [],
		extra: [Extra("section", "Methods")],
		docs:
		`Returns a nice string representation of the array. This will format the array into a string
		that looks like a Croc expression, like "[1, 2, 3]". Note that the elements of the array do
		not have their toString metamethods called, since that could lead to infinite loops if the array
		references itself directly or indirectly. To get a more complete representation of an array,
		look at the baselib \link{dumpVal} function (though that only outputs to the console).`},

		{kind: "function", name: "apply",
		params: [Param("func", "function")],
		extra: [Extra("section", "Methods")],
		docs:
		`Iterates over the array, calling the function with each element of the array, and assigns
		the result of the function back into the corresponding array element. The function should
		take one value and return one value. Returns the array it was called on. This works in-place,
		modifying the array on which it was called. As an example, "\tt{[1, 2, 3, 4, 5].apply(\\x -> x * x)}"
		will replace the values in the array with "\tt{[1, 4, 9, 16, 25]}".`},

		{kind: "function", name: "map",
		params: [Param("func", "function")],
		extra: [Extra("section", "Methods")],
		docs:
		`Like \link{apply}, but creates a new array and puts the output of the function in there,
		rather than modifying the source array. Returns the new array.`},

		{kind: "function", name: "reduce",
		params: [Param("func", "function"), Param("start", "any", "null")],
		extra: [Extra("section", "Methods")],
		docs:
		`Also known as \tt{fold} or \tt{foldl} (left fold) in many functional languages. This function
		takes a function \tt{func} of two arguments which is expected to return a value. It treats the
		array as a list of operands, and uses \tt{func} as if it were a left-associative binary operator
		between each pair of items in the array. This sounds confusing, but it makes sense with a bit
		of illustration: "\tt{[1 2 3 4 5].reduce(\\a, b -> a + b)}" will sum all the elements of the array
		and return 15, since it's like writing \tt{((((1 + 2) + 3) + 4) + 5)}. Notice that the operations
		are always performed left-to-right.

		This function optionally takes a "start value" which will be used as the very first item in
		the sequence. For instance, "\tt{[1 2 3].reduce(\\a, b -> a + b, 10)}" will do the same thing as
		\tt{(((10 + 1) + 2) + 3)}. In the event that the array's length is 0, the start value is simply
		returned as is.

		If no start value is given, and the array's length is 0, an error is thrown.`},

		{kind: "function", name: "rreduce",
		params: [Param("func", "function"), Param("start", "any", "null")],
		extra: [Extra("section", "Methods")],
		docs:
		`Similar to \link{reduce} but goes right-to-left instead of left-to-right. "\tt{[1 2 3 4 5].rreduce(\\a, b -> a + b)}"
		will still sum all the elements, because addition is commutative, but the order in which this
		is done becomes \tt{(1 + (2 + (3 + (4 + 5))))}. Obviously if \tt{func} is not commutative, \tt{reduce}
		and \tt{rreduce} will give different results.`},

		{kind: "function", name: "filter",
		params: [Param("func", "function")],
		extra: [Extra("section", "Methods")],
		docs:
		`Creates a new array which holds only those elements for which the given function returned \tt{true}
		when called with elements from the source array. The function is passed two arguments, the index
		and the value, and should return a boolean value. \tt{true} means the given element should be included
		in the result, and \tt{false} means it should be skipped. "\tt{[1, 2, "hi", 4.5, 6].filter(\\i, v -> isInt(v))}"
		would result in the array "\tt{[1, 2, 6]}", as the filter function only returns true for integral elements.`},

		{kind: "function", name: "find",
		params: [Param("value")],
		extra: [Extra("section", "Methods")],
		docs:
		`Performs a linear search for the value in the array. Returns the length of the array if it wasn't
		found, or its index if it was.

		This only compares items against the searched-for value if they are the same type. This differs from
		"\tt{val in a}" in that 'in' only checks if \tt{val} is identical to any of the values in \tt{a}; it never
		calls \tt{opCmp} metamethods like this function does.`},

		{kind: "function", name: "findIf",
		params: [Param("pred", "function")],
		extra: [Extra("section", "Methods")],
		docs:
		`Similar to \link{find} except that it uses a predicate instead of looking for a value. Performs a
		linear search of the array, calling the predicate on each value. Returns the index of the first value
		for which the predicate returns \tt{true}. Returns the length of the array if no value is found that satisfies
		the predicate.`},

		{kind: "function", name: "bsearch",
		params: [Param("value")],
		extra: [Extra("section", "Methods")],
		docs:
		`Performs a binary search for the value in the array. Because of the way binary search works, the array
		must be sorted for this search to work properly. Additionally, all the elements must be comparable (they
		had to be for the sort to work in the first place).

		\returns the array's length if the value wasn't found, or its index if it was.`},

		{kind: "function", name: "pop",
		params: [Param("index", "int", "-1")],
		extra: [Extra("section", "Methods")],
		docs:
		`This function makes it easy to use an array as a stack. Called with no parameters, it will remove
		the last element of the array and return it. Called with an index (which can be negative to mean from
		the end of the array), it will remove that element and shift all the other elements after it down a
		slot. In either case, if the array's length is 0, an error will be thrown.`},

		{kind: "function", name: "insert",
		params: [Param("index", "int"), Param("value")],
		extra: [Extra("section", "Methods")],
		docs:
		`More or less the inverse of \tt{pop}, this function lets you insert a value into an array, shifting
		down all the values after it. The \tt{index} can be negative to mean from the end of the array. \tt{index}
		can also be the length of the array, in which case the value is appended to the end of the array.`},

		{kind: "function", name: "swap",
		params: [Param("idx1", "int"), Param("idx2", "int")],
		extra: [Extra("section", "Methods")],
		docs:
		`Swaps the values contained in the two given elements.`},

		{kind: "function", name: "set",
		params: [Param("vararg", "vararg")],
		extra: [Extra("section", "Methods")],
		docs:
		`Kind of like the inverse of \link{expand}, this takes a variadic number of parameters, sets the length
		of the array to as many parameters as there are, and fills the array with those parameters. This is very
		similar to using an array constructor, but it reuses an array instead of creating a new one, which can
		save a lot of memory and time if you're doing this a lot.`},

		{kind: "function", name: "min",
		params: [],
		extra: [Extra("section", "Methods")],
		docs:
		`Gets the smallest value in the array. All elements of the array must be comparable to
		each other for this to work. Throws an error if the array is empty. If the array only
		has one value, returns that value.`},

		{kind: "function", name: "max",
		params: [],
		extra: [Extra("section", "Methods")],
		docs:
		`Gets the largest value in the array. All elements of the array must be comparable to
		each other for this to work. Throws an error if the array is empty. If the array only
		has one value, returns that value.`},

		{kind: "function", name: "extreme",
		params: [Param("pred", "function")],
		extra: [Extra("section", "Methods")],
		docs:
		`This is a generic version of \link{min} and \link{max}. Takes a predicate which should
		take two parameters: a new value, and the current extreme. The predicate should return \tt{true}
		if the new value is more extreme than the current extreme, and false otherwise. To illustrate,
		"\tt{[1, 2, 3, 4, 5].extreme(\\new, extreme -> new > extreme)}" will do the same thing as
		\link{max}, since the predicate returns true if the value is bigger than the current extreme.
		(However, the \link{min} and \link{max} functions are optimized and will be faster than if
		you pass your own predicate.)

		If the array only has one value, returns that value.

		\throws[exceptions.ValueError] if the array is empty.`},

		{kind: "function", name: "all",
		params: [Param("pred", "function", "null")],
		extra: [Extra("section", "Methods")],
		docs:
		`This is a generalized boolean "and" (logical conjunction) operation.

		If called with no predicate function, returns \tt{true} if every element in the array has a truth
		value of \tt{true}, and \tt{false} otherwise.

		If called with a predicate, returns \tt{true} if the predicate returned \tt{true} for every element
		in the array, and \tt{false} otherwise.

		Returns \tt{true} if called on an empty array.`},

		{kind: "function", name: "any",
		params: [Param("pred", "function", "null")],
		extra: [Extra("section", "Methods")],
		docs:
		`This is a generalized boolean "or" (logical disjunction) operation.

		If called with no predicate function, returns \tt{true} if any element in the array has a truth
		value of \tt{true}, and \tt{false} otherwise.

		If called with a predicate, returns \tt{true} if the predicate returned \tt{true} for any element
		in the array, and \tt{false} otherwise.

		Returns \tt{false} if called on an empty array.`},

		{kind: "function", name: "fill",
		params: [Param("value")],
		extra: [Extra("section", "Methods")],
		docs:
		`Sets every element in the array to the given value.`},

		{kind: "function", name: "append",
		params: [Param("vararg", "vararg")],
		extra: [Extra("section", "Methods")],
		docs:
		`Appends all the arguments to the end of the array, in order. This is different from the append
		operator (~=), because arrays will be appended as a single value, instead of having their elements
		appended.`},

		{kind: "function", name: "flatten",
		params: [],
		extra: [Extra("section", "Methods")],
		docs:
		`Flattens a multi-dimensional array into a single-dimensional array. The dimensions can be nested
		arbitrarily deep. If an array is directly or indirectly circularly referenced, throws an error. Always
		returns a new array. Can be called on single-dimensional arrays too, in which case it just returns a
		duplicate of the array.`},

		{kind: "function", name: "count",
		params: [Param("value"), Param("pred", "function", "null")],
		extra: [Extra("section", "Methods")],
		docs:
		`Called with just a value, returns the number of elements in the array that are equal to that value
		(according, optionally, to any \b{\tt{opCmp}} overloads). If called with a predicate, the predicate
		should take two parameters. The second parameter will always be the value that is being counted, the
		first parameter will be values from the array. The predicate should return a bool telling whether
		that value of the array should be counted. Returns the number of elements for which the predicate
		returned \tt{true}.`},

		{kind: "function", name: "countIf",
		params: [Param("pred", "function")],
		extra: [Extra("section", "Methods")],
		docs:
		`Similar to \link{count}, takes a predicate that should take a value and return a bool telling
		whether or not to count it. Returns the number of elements for which the predicate returned \tt{true}.`}
	];
}