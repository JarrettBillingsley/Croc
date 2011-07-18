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
import croc.ex;
import croc.stdlib_utils;
import croc.types;
import croc.types_array;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

struct ArrayLib
{
static:
	public void init(CrocThread* t)
	{
		makeModule(t, "array", function uword(CrocThread* t)
		{
			version(CrocBuiltinDocs)
			{
				scope doc = new CrocDoc(t, __FILE__);
				doc.push(Docs("module", "Array Library",
				"The array library provides functionality for creating and manipulating arrays. Most of these
				functions are accessed as methods of array objects. There are a few functions which are called
				through the "`array`" namespace."));
			}

			mixin(Register!(2, "array_new", 0, "new"));
			mixin(Register!(3, "range"));

			newNamespace(t, "array");
				mixin(RegisterField!(1, "sort"));
				mixin(RegisterField!(0, "reverse"));
				mixin(RegisterField!(0, "array_dup", 0, "dup"));

					newFunction(t, 1, &iterator,        "iterator");
					newFunction(t, 1, &iteratorReverse, "iteratorReverse");
				mixin(RegisterField!(1, "opApply", 2));

				mixin(RegisterField!(0, "expand"));
				mixin(RegisterField!(0, "toString"));
				mixin(RegisterField!(1, "apply"));
				mixin(RegisterField!(1, "map"));
				mixin(RegisterField!(2, "reduce"));
				mixin(RegisterField!(2, "rreduce"));
				mixin(RegisterField!(1, "each"));
				mixin(RegisterField!(1, "filter"));
				mixin(RegisterField!(1, "find"));
				mixin(RegisterField!(1, "findIf"));
				mixin(RegisterField!(1, "bsearch"));
				mixin(RegisterField!(1, "array_pop", 0, "pop"));
				mixin(RegisterField!(   "set"));
				mixin(RegisterField!(0, "min"));
				mixin(RegisterField!(0, "max"));
				mixin(RegisterField!(1, "extreme"));
				mixin(RegisterField!(1, "any"));
				mixin(RegisterField!(1, "all"));
				mixin(RegisterField!(1, "fill"));
				mixin(RegisterField!(   "append"));

					newTable(t);
				mixin(RegisterField!(0, "flatten", 1));

				mixin(RegisterField!(2, "count"));
				mixin(RegisterField!(1, "countIf"));
			setTypeMT(t, CrocValue.Type.Array);

			version(CrocBuiltinDocs)
			{
				dup(t, 0);
				doc.pop(-1);
				pop(t);
			}

			return 0;
		});

		importModuleNoNS(t, "array");
	}

	version(CrocBuiltinDocs) Docs array_new_docs = {kind: "function", name: "array.new", docs:
	"You can use array literals to create arrays in Croc, but sometimes you just need to be able to
	create an array of arbitrary size. This function will create an array of the given size. If
	you pass a value for the `fill` parameter, the new array will have every element set to it.
	Otherwise, it will be filled with `null`.",
	params: [Param("size", "int"), Param("fill", "any", "null")],
	extra: [Extra("section", "Functions"), Extra("protection", "global")]};

	uword array_new(CrocThread* t)
	{
		auto length = checkIntParam(t, 1);
		auto numParams = stackSize(t) - 1;

		if(length < 0 || length > uword.max)
			throwException(t, "Invalid length: {}", length);

		newArray(t, cast(uword)length);

		if(numParams > 1)
		{
			dup(t, 2);
			fillArray(t, -2);
		}

		return 1;
	}

	version(CrocBuiltinDocs) Docs range_docs = {kind: "function", name: "array.range", docs:
	"Creates a new array filled with integer values specified by the arguments. This is similar to
	the Python `range()` function, but is a little more intelligent when it comes to the direction
	of the range. Namely, if you give it indices where the ending index is less than the beginning,
	it will automatically use a negative step. In fact, the step value passed to this function must
	always be greater than 0; it simply defines the size of the step regardless of the direction the
	range goes in.

	If only one argument is given, that argument specifies the noninclusive ending index, and the
	beginning index is assumed to be 0 and the step to be 1. This means `array.range(5)` will return
	`[0, 1, 2, 3, 4]` and `array.range(-5)` will return `[0, -1, -2, -3, -4]`.

	If two arguments are given, the first is the beginning inclusive index and the second is the
	ending noninclusive index. The step is again assumed to be 1. Examples: `array.range(3, 8)`
	yields `[3, 4, 5, 6, 7]`; `array.range(2, -2)` yields `[2, 1, 0, -1]`; and `array.range(-10, -7)`
	yields `[-10, -9, -8]`.

	Lastly, if three arguments are given, the first is the beginning inclusive index, the second the
	ending noninclusive index, and the third the step value. The step must be greater than 0; this
	function will automatically figure out that it needs to subtract the step if the ending index is
	less than the beginning index. Example: `array.range(1, 20, 4)` yields `[1, 5, 9, 13, 17]` and
	`array.range(10, 0, 2)` yields `[10, 8, 6, 4, 2]`.",
	params: [Param("val1", "int"), Param("val2", "int", "null"), Param("step", "int", "null")],
	extra: [Extra("section", "Functions"), Extra("protection", "global")]};

	uword range(CrocThread* t)
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
			throwException(t, "Step may not be negative or 0");

		crocint range = abs(v2 - v1);
		crocint size = range / step;

		if((range % step) != 0)
			size++;

		if(size > uword.max)
			throwException(t, "Array is too big");

		newArray(t, cast(uword)size);
		auto a = getArray(t, -1);

		auto val = v1;

		if(v2 < v1)
		{
			for(uword i = 0; val > v2; i++, val -= step)
				a.data[i] = val;
		}
		else
		{
			for(uword i = 0; val < v2; i++, val += step)
				a.data[i] = val;
		}

		return 1;
	}

	version(CrocBuiltinDocs) Docs sort_docs = {kind: "function", name: "sort", docs:
	"Sorts the given array. All the elements must be comparable with one another. Will call any
	'''`opCmp`''' metamethods. Returns the array itself.

	If no parameters are given, sorts the array in ascending order.

	If the optional `how` parameter is given the string `\"reverse\"`, the array will be sorted
	in descending order.

	If the `how` parameter is a function, it is treated as a sorting predicate. It should take
	two arguments, compare them, and return an ordering integer (i.e. negative if the first is
	less than the second, positive if the first is greater than the second, and 0 if they are
	equal).",
	params: [Param("how", "function|string", "null")],
	extra: [Extra("section", "Methods")]};

	uword sort(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 0, CrocValue.Type.Array);

		bool delegate(CrocValue, CrocValue) pred;

		if(numParams > 0)
		{
			if(isString(t, 1))
			{
				if(getString(t, 1) == "reverse")
				{
					pred = (CrocValue v1, CrocValue v2)
					{
						push(t, v1);
						push(t, v2);
						auto v = cmp(t, -2, -1);
						pop(t, 2);
						return v > 0;
					};
				}
				else
					throwException(t, "Unknown array sorting method");
			}
			else
			{
				checkParam(t, 1, CrocValue.Type.Function);
				dup(t);

				pred = (CrocValue v1, CrocValue v2)
				{
					auto reg = dup(t);
					pushNull(t);
					push(t, v1);
					push(t, v2);
					rawCall(t, reg, 1);

					if(!isInt(t, -1))
					{
						pushTypeString(t, -1);
						throwException(t, "comparison function expected to return 'int', not '{}'", getString(t, -1));
					}

					auto v = getInt(t, -1);
					pop(t);
					return v < 0;
				};
			}
		}
		else
		{
			pred = (CrocValue v1, CrocValue v2)
			{
				push(t, v1);
				push(t, v2);
				auto v = cmp(t, -2, -1);
				pop(t, 2);
				return v < 0;
			};
		}

		.sort(getArray(t, 0).toArray(), pred);
		dup(t, 0);
		return 1;
	}

	version(CrocBuiltinDocs) Docs reverse_docs = {kind: "function", name: "reverse", docs:
	"Reverses the elements in the given array in-place. Returns the array itself.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword reverse(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Array);
		getArray(t, 0).toArray().reverse;
		dup(t, 0);
		return 1;
	}

	version(CrocBuiltinDocs) Docs array_dup_docs = {kind: "function", name: "dup", docs:
	"Creates a copy of the given array. Only the array elements are copied, not any data that
	they point to.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword array_dup(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Array);
		newArray(t, cast(uword)len(t, 0)); // this should be fine?  since arrays can't be longer than uword.max
		getArray(t, -1).toArray()[] = getArray(t, 0).toArray()[];
		return 1;
	}

	uword iterator(CrocThread* t)
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

	uword iteratorReverse(CrocThread* t)
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

	version(CrocBuiltinDocs) Docs opApply_docs = {kind: "function", name: "opApply", docs:
	"This allows you to iterate over arrays using `foreach` loops.
{{{
#!croc
foreach(i, v; a)
	// ...

foreach(i, v; a, \"reverse\")
	// iterate backwards
}}}

	As the second example shows, passing in the string \"reverse\" as the second parameter will
	cause the iteration to run in reverse.",
	params: [Param("mode", "string", "null")],
	extra: [Extra("section", "Methods")]};

	uword opApply(CrocThread* t)
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

	version(CrocBuiltinDocs) Docs expand_docs = {kind: "function", name: "expand", docs:
	"Returns all the elements of the array in order. In this way, you can \"unpack\" an array's
	values to pass as separate parameters to a function, or as return values, etc. Note that you
	probably shouldn't use this on really big arrays.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword expand(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Array);
		auto a = getArray(t, 0);

		foreach(ref val; a.toArray())
			push(t, val);

		return a.length;
	}

	version(CrocBuiltinDocs) Docs toString_docs = {kind: "function", name: "toString", docs:
	"Returns a nice string representation of the array. This will format the array into a string
	that looks like a Croc expression, like \"[1, 2, 3]\". Note that the elements of the array do
	not have their toString metamethods called, since that could lead to infinite loops if the array
	references itself directly or indirectly. To get a more complete representation of an array,
	look at the baselib '''`dumpVal`''' function (though that only outputs to the console).",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword toString(CrocThread* t)
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
			else if(isChar(t, -1))
			{
				auto c = getChar(t, -1);
				pop(t);
				buf.addChar('\'');
				buf.addChar(c);
				buf.addChar('\'');
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

	version(CrocBuiltinDocs) Docs apply_docs = {kind: "function", name: "apply", docs:
	"Iterates over the array, calling the function with each element of the array, and assigns
	the result of the function back into the corresponding array element. The function should
	take one value and return one value. Returns the array it was called on. This works in-place,
	modifying the array on which it was called. As an example, \"`[1, 2, 3, 4, 5].apply(\\x -> x * x)`\"
	will replace the values in the array with \"`[1, 4, 9, 16, 25]`\".",
	params: [Param("func", "function")],
	extra: [Extra("section", "Methods")]};

	uword apply(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Array);
		checkParam(t, 1, CrocValue.Type.Function);

		auto data = getArray(t, 0).toArray();

		foreach(i, ref v; data)
		{
			auto reg = dup(t, 1);
			dup(t, 0);
			push(t, v);
			rawCall(t, reg, 1);
			idxai(t, 0, i);
		}

		dup(t, 0);
		return 1;
	}

	version(CrocBuiltinDocs) Docs map_docs = {kind: "function", name: "map", docs:
	"Like '''`apply`''', but creates a new array and puts the output of the function in there,
	rather than modifying the source array. Returns the new array.",
	params: [Param("func", "function")],
	extra: [Extra("section", "Methods")]};

	uword map(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Array);
		checkParam(t, 1, CrocValue.Type.Function);
		auto newArr = newArray(t, cast(uword)len(t, 0));
		auto data = getArray(t, -1).toArray();

		foreach(i, ref v; getArray(t, 0).toArray())
		{
			auto reg = dup(t, 1);
			dup(t, 0);
			push(t, v);
			rawCall(t, reg, 1);
			idxai(t, newArr, i);
		}

		return 1;
	}

	version(CrocBuiltinDocs) Docs reduce_docs = {kind: "function", name: "reduce", docs:
	"Also known as "`fold`" or "`foldl`" (left fold) in many functional languages. This function
	takes a function `func` of two arguments which is expected to return a value. It treats the
	array as a list of operands, and uses `func` as if it were a left-associative binary operator
	between each pair of items in the array. This sounds confusing, but it makes sense with a bit
	of illustration: \"`[1 2 3 4 5].reduce(\\a, b -> a + b)`\" will sum all the elements of the array
	and return 15, since it's like writing `((((1 + 2) + 3) + 4) + 5)`. Notice that the operations
	are always performed left-to-right.

	This function optionally takes a \"start value\" which will be used as the very first item in
	the sequence. For instance, \"`[1 2 3].reduce(\\a, b -> a + b, 10)`\" will do the same thing as
	`(((10 + 1) + 2) + 3)`. In the event that the array's length is 0, the start value is simply
	returned as is.

	If no start value is given, and the array's length is 0, an error is thrown.",
	params: [Param("func", "function"), Param("start", "any", "null")],
	extra: [Extra("section", "Methods")]};

	uword reduce(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 0, CrocValue.Type.Array);
		checkParam(t, 1, CrocValue.Type.Function);

		uword length = cast(uword)len(t, 0);

		if(length == 0)
		{
			if(numParams == 1)
				throwException(t, "Attempting to reduce an empty array without an initial value");
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
			rawCall(t, -4, 1);
			insertAndPop(t, -2);
		}

		return 1;
	}

	version(CrocBuiltinDocs) Docs rreduce_docs = {kind: "function", name: "rreduce", docs:
	"Similar to `reduce` but goes right-to-left instead of left-to-right. \"`[1 2 3 4 5].rreduce(\\a, b -> a + b)`\"
	will still sum all the elements, because addition is commutative, but the order in which this
	is done becomes `(1 + (2 + (3 + (4 + 5))))`. Obviously if `func` is not commutative, `reduce`
	and `rreduce` will give different results.",
	params: [Param("func", "function"), Param("start", "any", "null")],
	extra: [Extra("section", "Methods")]};

	uword rreduce(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 0, CrocValue.Type.Array);
		checkParam(t, 1, CrocValue.Type.Function);

		uword length = cast(uword)len(t, 0);

		if(length == 0)
		{
			if(numParams == 1)
				throwException(t, "Attempting to reduce an empty array without an initial value");
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
			rawCall(t, -4, 1);
			insertAndPop(t, -2);

			if(i == 0)
				break;
		}

		return 1;
	}

	version(CrocBuiltinDocs) Docs each_docs = {kind: "function", name: "each", docs:
	"This is an alternate way of iterating over an array. The function is called once for each
	element, starting at the first element. The parameters to the function are the array as the
	`this` param, then the index, and then the value. If the function returns `false`, iteration will
	stop and this function will return. This function returns the array on which it was called.",
	params: [Param("func", "function")],
	extra: [Extra("section", "Methods")]};

	uword each(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Array);
		checkParam(t, 1, CrocValue.Type.Function);

		foreach(i, ref v; getArray(t, 0).toArray())
		{
			dup(t, 1);
			dup(t, 0);
			pushInt(t, i);
			push(t, v);
			rawCall(t, -4, 1);

			if(isBool(t, -1) && getBool(t, -1) == false)
				break;
		}

		dup(t, 0);
		return 1;
	}

	version(CrocBuiltinDocs) Docs filter_docs = {kind: "function", name: "filter", docs:
	"Creates a new array which holds only those elements for which the given function returned `true`
	when called with elements from the source array. The function is passed two arguments, the index
	and the value, and should return a boolean value. `true` means the given element should be included
	in the result, and `false` means it should be skipped. \"`[1, 2, \"hi\", 4.5, 6].filter(\\i, v -> isInt(v))`\"
	would result in the array \"`[1, 2, 6]`\", as the filter function only returns true for integral elements.",
	params: [Param("func", "function")],
	extra: [Extra("section", "Methods")]};

	uword filter(CrocThread* t)
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
			push(t, v);
			rawCall(t, -4, 1);

			if(!isBool(t, -1))
			{
				pushTypeString(t, -1);
				throwException(t, "filter function expected to return 'bool', not '{}'", getString(t, -1));
			}

			if(getBool(t, -1))
			{
				if(retIdx >= newLen)
				{
					newLen += 10;
					pushInt(t, newLen);
					lena(t, retArray);
				}

				push(t, v);
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

	version(CrocBuiltinDocs) Docs find_docs = {kind: "function", name: "find", docs:
	"Performs a linear search for the value in the array. Returns the length of the array if it wasn't
	found, or its index if it was.

	This only compares items against the searched-for value if they are the same type. This differs from
	\"`val in a`\" in that 'in' only checks if `val` is identical to any of the values in `a`; it never
	calls `opCmp` metamethods like this function does.",
	params: [Param("value")],
	extra: [Extra("section", "Methods")]};

	uword find(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Array);
		checkAnyParam(t, 1);

		foreach(i, ref v; getArray(t, 0).toArray())
		{
			push(t, v);

			if(type(t, 1) == v.type && cmp(t, 1, -1) == 0)
			{
				pushInt(t, i);
				return 1;
			}
		}

		pushLen(t, 0);
		return 1;
	}

	version(CrocBuiltinDocs) Docs findIf_docs = {kind: "function", name: "findIf", docs:
	"Similar to '''`find`''' except that it uses a predicate instead of looking for a value. Performs a
	linear search of the array, calling the predicate on each value. Returns the index of the first value
	for which the predicate returns `true`. Returns the length of the array if no value is found that satisfies
	the predicate.",
	params: [Param("pred", "function")],
	extra: [Extra("section", "Methods")]};

	uword findIf(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Array);
		checkParam(t, 1, CrocValue.Type.Function);

		foreach(i, ref v; getArray(t, 0).toArray())
		{
			auto reg = dup(t, 1);
			pushNull(t);
			push(t, v);
			rawCall(t, reg, 1);

			if(!isBool(t, -1))
			{
				pushTypeString(t, -1);
				throwException(t, "find function expected to return 'bool', not '{}'", getString(t, -1));
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

	version(CrocBuiltinDocs) Docs bsearch_docs = {kind: "function", name: "bsearch", docs:
	"Performs a binary search for the value in the array. Because of the way binary search works, the array
	must be sorted for this search to work properly. Additionally, all the elements must be comparable (they
	had to be for the sort to work in the first place). Returns the array's length if the value wasn't found,
	or its index if it was.",
	params: [Param("value")],
	extra: [Extra("section", "Methods")]};

	uword bsearch(CrocThread* t)
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

	version(CrocBuiltinDocs) Docs array_pop_docs = {kind: "function", name: "pop", docs:
	"This function can make it easy to use an array as a stack. Called with no parameters, it will remove
	the last element of the array and return it. Called with an index (which can be negative to mean from
	the end of the array), it will remove that element and shift all the other elements after it down a
	slot. In either case, if the array's length is 0, an error will be thrown.",
	params: [Param("index", "int", "-1")],
	extra: [Extra("section", "Methods")]};

	uword array_pop(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Array);
		crocint index = -1;
		auto data = getArray(t, 0).toArray();

		if(data.length == 0)
			throwException(t, "Array is empty");

		if(stackSize(t) > 1)
			index = checkIntParam(t, 1);

		if(index < 0)
			index += data.length;

		if(index < 0 || index >= data.length)
			throwException(t, "Invalid array index: {}", index);

		idxi(t, 0, index);

		for(uword i = cast(uword)index; i < data.length - 1; i++)
			data[i] = data[i + 1];

		array.resize(t.vm.alloc, getArray(t, 0), data.length - 1);
		return 1;
	}

	version(CrocBuiltinDocs) Docs set_docs = {kind: "function", name: "set", docs:
	"Kind of like the inverse of '''`expand`''', this takes a variadic number of parameters, sets the length
	of the array to as many parameters as there are, and fills the array with those parameters. This is very
	similar to using an array constructor, but it reuses an array instead of creating a new one, which can
	save a lot of memory and time if you're doing this a lot.",
	params: [Param("vararg", "vararg")],
	extra: [Extra("section", "Methods")]};

	uword set(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 0, CrocValue.Type.Array);
		auto a = getArray(t, 0);

		array.resize(t.vm.alloc, a, numParams);

		for(uword i = 0; i < numParams; i++)
			a.data[i] = *getValue(t, i + 1);

		dup(t, 0);
		return 1;
	}

	uword minMaxImpl(CrocThread* t, uword numParams, bool max)
	{
		checkParam(t, 0, CrocValue.Type.Array);
		auto data = getArray(t, 0).toArray();

		if(data.length == 0)
			throwException(t, "Array is empty");

		auto extreme = data[0];
		uword extremeIdx = 0;

		if(numParams > 0)
		{
			for(uword i = 1; i < data.length; i++)
			{
				dup(t, 1);
				pushNull(t);
				idxi(t, 0, i);
				push(t, extreme);
				rawCall(t, -4, 1);

				if(!isBool(t, -1))
				{
					pushTypeString(t, -1);
					throwException(t, "extrema function should return 'bool', not '{}'", getString(t, -1));
				}

				if(getBool(t, -1))
				{
					extreme = data[i];
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

	version(CrocBuiltinDocs) Docs min_docs = {kind: "function", name: "min", docs:
	"Gets the smallest value in the array. All elements of the array must be comparable to
	each other for this to work. Throws an error if the array is empty. If the array only
	has one value, returns that value.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword min(CrocThread* t)
	{
		return minMaxImpl(t, 0, false);
	}

	version(CrocBuiltinDocs) Docs max_docs = {kind: "function", name: "max", docs:
	"Gets the largest value in the array. All elements of the array must be comparable to
	each other for this to work. Throws an error if the array is empty. If the array only
	has one value, returns that value.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword max(CrocThread* t)
	{
		return minMaxImpl(t, 0, true);
	}

	version(CrocBuiltinDocs) Docs extreme_docs = {kind: "function", name: "extreme", docs:
	"This is a generic version of '''`min`''' and '''`max`'''. Takes a predicate which should
	take two parameters: a new value, and the current extreme. The predicate should return `true`
	if the new value is more extreme than the current extreme, and false otherwise. To illustrate,
	\"`[1, 2, 3, 4, 5].extreme(\\new, extreme -> new > extreme)`\" will do the same thing as
	'''`max`''', since the predicate returns true if the value is bigger than the current extreme.
	(However, the '''`min`''' and '''`max`''' functions are optimized and will be faster than if
	you pass your own predicate.)

	Throws an error if the array is empty. If the array only has one value, returns that value.",
	params: [Param("pred", "function")],
	extra: [Extra("section", "Methods")]};

	uword extreme(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 1, CrocValue.Type.Function);
		return minMaxImpl(t, numParams, false);
	}

	version(CrocBuiltinDocs) Docs all_docs = {kind: "function", name: "all", docs:
	"This is a generalized boolean \"and\" (logical conjunction) operation.

	If called with no predicate function, returns `true` if every element in the array has a truth
	value of `true`, and `false` otherwise.

	If called with a predicate, returns `true` if the predicate returned `true` for every element
	in the array, and `false` otherwise.

	Returns `true` if called on an empty array.",
	params: [Param("pred", "function", "null")],
	extra: [Extra("section", "Methods")]};

	uword all(CrocThread* t)
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
				push(t, v);
				rawCall(t, -3, 1);

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
				if(v.isFalse())
				{
					pushBool(t, false);
					return 1;
				}
			}
		}

		pushBool(t, true);
		return 1;
	}
	
	version(CrocBuiltinDocs) Docs any_docs = {kind: "function", name: "any", docs:
	"This is a generalized boolean \"or\" (logical disjunction) operation.

	If called with no predicate function, returns `true` if any element in the array has a truth
	value of `true`, and `false` otherwise.
	
	If called with a predicate, returns `true` if the predicate returned `true` for any element
	in the array, and `false` otherwise.
	
	Returns `false` if called on an empty array.",
	params: [Param("pred", "function", "null")],
	extra: [Extra("section", "Methods")]};

	uword any(CrocThread* t)
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
				push(t, v);
				rawCall(t, -3, 1);

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
				if(!v.isFalse())
				{
					pushBool(t, true);
					return 1;
				}
			}
		}

		pushBool(t, false);
		return 1;
	}

	version(CrocBuiltinDocs) Docs fill_docs = {kind: "function", name: "fill", docs:
	"Sets every element in the array to the given value.",
	params: [Param("value")],
	extra: [Extra("section", "Methods")]};

	uword fill(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Array);
		checkAnyParam(t, 1);
		dup(t, 1);
		fillArray(t, 0);
		return 0;
	}

	version(CrocBuiltinDocs) Docs append_docs = {kind: "function", name: "append", docs:
	"Appends all the arguments to the end of the array, in order. This is different from the append
	operator (~=), because arrays will be appended as a single value, instead of having their elements
	appended.",
	params: [Param("vararg", "vararg")],
	extra: [Extra("section", "Methods")]};

	uword append(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 0, CrocValue.Type.Array);
		auto a = getArray(t, 0);

		if(numParams == 0)
			return 0;

		auto oldlen = a.length;
		array.resize(t.vm.alloc, a, a.length + numParams);

		for(uword i = oldlen, j = 1; i < a.length; i++, j++)
			a.data[i] = *getValue(t, j);

		return 0;
	}

	version(CrocBuiltinDocs) Docs flatten_docs = {kind: "function", name: "flatten", docs:
	"Flattens a multi-dimensional array into a single-dimensional array. The dimensions can be nested
	arbitrarily deep. If an array is directly or indirectly circularly referenced, throws an error. Always
	returns a new array. Can be called on single-dimensional arrays too, in which case it just returns a
	duplicate of the array.",
	params: [],
	extra: [Extra("section", "Methods")]};

	uword flatten(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Array);
		auto flattening = getUpval(t, 0);

		auto ret = newArray(t, 0);

		void flatten(word arr)
		{
			auto a = absIndex(t, arr);

			if(opin(t, a, flattening))
				throwException(t, "Attempting to flatten a self-referencing array");

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
				if(val.type == CrocValue.Type.Array)
					flatten(push(t, CrocValue(val.mArray)));
				else
				{
					push(t, val);
					cateq(t, ret, 1);
				}
			}
		}

		flatten(0);
		dup(t, ret);
		return 1;
	}

	version(CrocBuiltinDocs) Docs count_docs = {kind: "function", name: "count", docs:
	"Called with just a value, returns the number of elements in the array that are equal to that value
	(according, optionally, to any '''`opCmp`''' overloads). If called with a predicate, the predicate
	should take two parameters. The second parameter will always be the value that is being counted, the
	first parameter will be values from the array. The predicate should return a bool telling whether
	that value of the array should be counted. Returns the number of elements for which the predicate
	returned `true`.",
	params: [Param("value"), Param("pred", "function", "null")],
	extra: [Extra("section", "Methods")]};

	uword count(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		checkParam(t, 0, CrocValue.Type.Array);
		checkAnyParam(t, 1);

		bool delegate(CrocValue, CrocValue) pred;

		if(numParams > 1)
		{
			checkParam(t, 2, CrocValue.Type.Function);

			pred = (CrocValue a, CrocValue b)
			{
				auto reg = dup(t, 2);
				pushNull(t);
				push(t, a);
				push(t, b);
				rawCall(t, reg, 1);

				if(!isBool(t, -1))
				{
					pushTypeString(t, -1);
					throwException(t, "count predicate expected to return 'bool', not '{}'", getString(t, -1));
				}

				auto ret = getBool(t, -1);
				pop(t);
				return ret;
			};
		}
		else
		{
			pred = (CrocValue a, CrocValue b)
			{
				push(t, a);
				push(t, b);
				auto ret = cmp(t, -2, -1) == 0;
				pop(t, 2);
				return ret;
			};
		}

		pushInt(t, .count(getArray(t, 0).toArray(), *getValue(t, 1), pred));
		return 1;
	}

	version(CrocBuiltinDocs) Docs countIf_docs = {kind: "function", name: "countIf", docs:
	"Similar to '''`count`''', takes a predicate that should take a value and return a bool telling
	whether or not to count it. Returns the number of elements for which the predicate returned `true`.",
	params: [Param("pred", "function")],
	extra: [Extra("section", "Methods")]};

	uword countIf(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Array);
		checkParam(t, 1, CrocValue.Type.Function);

		pushInt(t, .countIf(getArray(t, 0).toArray(), (CrocValue a)
		{
			auto reg = dup(t, 1);
			pushNull(t);
			push(t, a);
			rawCall(t, reg, 1);

			if(!isBool(t, -1))
			{
				pushTypeString(t, -1);
				throwException(t, "count predicate expected to return 'bool', not '{}'", getString(t, -1));
			}
	
			auto ret = getBool(t, -1);
			pop(t);
			return ret;
		}));
		
		return 1;
	}
}