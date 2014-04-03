
#include <functional>
#include <limits>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"
#include "croc/util/array.hpp"

namespace croc
{
	namespace
	{
#define checkArrayParam(t, n) (croc_ex_checkParam((t), (n), CrocType_Array), getArray(Thread::from(t), (n)))

DBeginList(_globalFuncs)
	Docstr(DFunc("new") DParam("size", "int") DParamD("fill", "any", "null")
	R"(Creates an array object of length \tt{size}, filling it with the value \tt{fill} (which defaults to
	\tt{null}).

	\throws[RangeError] if \tt{size} is invalid.)"),

	"new", 2, [](CrocThread* t) -> word_t
	{
		auto length = croc_ex_checkIntParam(t, 1);
		auto haveFill = croc_isValidIndex(t, 2);

		if(length < 0 || cast(uword)length > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid length: %" CROC_INTEGER_FORMAT, length);

		croc_array_new(t, cast(uword)length);

		if(haveFill)
		{
			croc_dup(t, 2);
			croc_array_fill(t, -2);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("new2D") DParam("size1", "int") DParam("size2", "int") DParamD("fill", "any", "null")
	R"(Just like \link{new}, but creates an array of arrays. The outer array will have length \tt{size1}, and each of
	its elements will be an array of length \tt{size2}. Each of the sub-arrays will be filled with \tt{fill}.

	\throws[RangeError] if \tt{size1} or \tt{size2} is invalid.)"),

	"new2D", 3, [](CrocThread* t) -> word_t
	{
		auto length1 = croc_ex_checkIntParam(t, 1);
		auto length2 = croc_ex_checkIntParam(t, 2);
		auto haveFill = croc_isValidIndex(t, 3);

		if(length1 <= 0 || cast(uword)length1 > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid first dimension length: %" CROC_INTEGER_FORMAT, length1);

		if(length2 < 0 || cast(uword)length2 > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid second dimension length: %" CROC_INTEGER_FORMAT, length2);

		croc_array_new(t, cast(uword)length1);

		if(haveFill)
		{
			for(uword i = 0; i < cast(uword)length1; i++)
			{
				croc_array_new(t, cast(uword)length2);
				croc_dup(t, 3);
				croc_array_fill(t, -2);
				croc_idxai(t, -2, i);
			}
		}
		else
		{
			for(uword i = 0; i < cast(uword)length1; i++)
			{
				croc_array_new(t, cast(uword)length2);
				croc_idxai(t, -2, i);
			}
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("new3D") DParam("size1", "int") DParam("size2", "int") DParam("size3", "int")
		DParamD("fill", "any", "null")
	R"(Just like \link{new2D}, but creates an array of arrays of arrays. The outer array has length \tt{size1}; its
	elements will be arrays of length \tt{size2}; and those arrays' elements will be arrays of length \tt{size3}, all
	filled with \tt{fill}.

	\throws[RangeError] if \tt{size1}, \tt{size2}, or \tt{size3} is invalid.)"),

	"new3D", 4, [](CrocThread* t) -> word_t
	{
		auto length1 = croc_ex_checkIntParam(t, 1);
		auto length2 = croc_ex_checkIntParam(t, 2);
		auto length3 = croc_ex_checkIntParam(t, 3);
		auto haveFill = croc_isValidIndex(t, 4);

		if(length1 <= 0 || cast(uword)length1 > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid first dimension length: %" CROC_INTEGER_FORMAT, length1);

		if(length2 <= 0 || cast(uword)length2 > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid second dimension length: %" CROC_INTEGER_FORMAT, length2);

		if(length3 < 0 || cast(uword)length3 > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Invalid third dimension length: %" CROC_INTEGER_FORMAT, length3);

		croc_array_new(t, cast(uword)length1);

		if(haveFill)
		{
			for(uword i = 0; i < cast(uword)length1; i++)
			{
				croc_array_new(t, cast(uword)length2);

				for(uword j = 0; j < cast(uword)length2; j++)
				{
					croc_array_new(t, cast(uword)length3);
					croc_dup(t, 4);
					croc_array_fill(t, -2);
					croc_idxai(t, -2, j);
				}

				croc_idxai(t, -2, i);
			}
		}
		else
		{
			for(uword i = 0; i < cast(uword)length1; i++)
			{
				croc_array_new(t, cast(uword)length2);

				for(uword j = 0; j < cast(uword)length2; j++)
				{
					croc_array_new(t, cast(uword)length3);
					croc_idxai(t, -2, j);
				}

				croc_idxai(t, -2, i);
			}
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("range") DParam("val1", "int") DParamD("val2", "int", "null") DParamD("step", "int", "null")
	R"(Creates a new array whose elements are a range of integers.

	If only one argument is given, that argument specifies the noninclusive ending index, and the beginning index is
	assumed to be 0 and the step to be 1. This means \tt{array.range(5)} will return \tt{[0, 1, 2, 3, 4]} and
	\tt{array.range(-5)} will return \tt{[0, -1, -2, -3, -4]}.

	If two arguments are given, the first is the beginning inclusive index and the second is the ending noninclusive
	index. The step is again assumed to be 1. Examples: \tt{array.range(3, 8)} gives \tt{[3, 4, 5, 6, 7]};
	\tt{array.range(2, -2)} gives \tt{[2, 1, 0, -1]}; and \tt{array.range(-10, -7)} gives \tt{[-10, -9, -8]}.

	Lastly, if three arguments are given, the first is the beginning inclusive index, the second the ending noninclusive
	index, and the third the step value. The step must be greater than 0; this function will automatically figure out
	that it needs to subtract the step if the ending index is less than the beginning index. Example: \tt{array.range(1,
	20, 4)} yields \tt{[1, 5, 9, 13, 17]} and \tt{array.range(10, 0, 2)} yields \tt{[10, 8, 6, 4, 2]}.

	\throws[RangeError] if \tt{step <= 0} or if the resulting array would be too large.)"),

	"range", 3, [](CrocThread* t) -> word_t
	{
		auto v1 = croc_ex_checkIntParam(t, 1);
		crocint v2;
		crocint step = 1;

		switch(croc_getStackSize(t) - 1)
		{
			case 1: v2 = v1; v1 = 0; break;
			case 2: v2 = croc_ex_checkIntParam(t, 2); break;
			default:
				v2 = croc_ex_checkIntParam(t, 2);
				step = croc_ex_checkIntParam(t, 3);
		}

		if(step <= 0)
			croc_eh_throwStd(t, "RangeError", "Step may not be negative or 0");

		crocint range = abs(v2 - v1);
		crocint size = range / step;

		if((range % step) != 0)
			size++;

		if(cast(uword)size > std::numeric_limits<uword>::max())
			croc_eh_throwStd(t, "RangeError", "Array is too big");

		croc_array_new(t, cast(uword)size);
		auto data = getArray(Thread::from(t), -1)->toDArray();
		auto val = v1;

		// no write barrier here. the array is new and we're filling it with scalars.

		if(v2 < v1)
		{
			for(uword i = 0; val > v2; i++, val -= step)
				data[i].value = Value::from(val);
		}
		else
		{
			for(uword i = 0; val < v2; i++, val += step)
				data[i].value = Value::from(val);
		}

		return 1;
	}
DEndList()

DBeginList(_methodFuncs)
	Docstr(DFunc("opEquals") DParam("other", "array")
	R"(Compares two arrays for shallow equality.

	Shallow equality means two arrays are equal if they are the same length, and for each index i, \tt{this[i] is
	other[i]} is true. This does not call opEquals metamethods on any of this arrays' elements.)"),

	"opEquals", 1, [](CrocThread* t) -> word_t
	{
		auto a = checkArrayParam(t, 0)->toDArray();
		auto b = checkArrayParam(t, 1)->toDArray();
		croc_pushBool(t, a == b);
		return 1;
	}

DListSep()
	Docstr(DFunc("sort") DParamD("how", "function|string", "null")

	R"(Sorts this array in-place. This is \b{not} a stable sort. This implementation uses smoothsort, which gives best-
	case linear time, and average-case and worst-case O(\em{n} log \em{n}) time, using constant space.

	All the elements must be comparable with one another, and any \b{\tt{opCmp}} metamethods will be called on the
	elements.

	\param[how] indicates how to sort this array:
		\blist
			\li If no value is given for this parameter, this array will be sorted in ascending order.
			\li If the string \tt{"reverse"} is given, this array will be sorted in descending order.
			\li Otherwise, this parameter must be a function which is treated as a sorting predicate. It should take two
				arguments (which will be elements from this array), compare them, and return a comparison value (i.e.
				negative int if the first is less than the second, positive int if greater, and 0 if equal).
		\endlist

	\returns this array.
	\throws[TypeError] if \tt{how} was a function and it returned something other than an \tt{int}.)"),

	"sort", 1, [](CrocThread* t) -> word_t
	{
		auto arr = checkArrayParam(t, 0);

		std::function<bool(Array::Slot, Array::Slot)> pred;

		auto t_ = Thread::from(t);

		if(croc_isValidIndex(t, 1))
		{
			if(croc_isString(t, 1))
			{
				if(getCrocstr(t, 1) == ATODA("reverse"))
				{
					pred = [&](Array::Slot v1, Array::Slot v2)
					{
						push(t_, v1.value);
						push(t_, v2.value);
						auto v = croc_cmp(t, -2, -1);
						croc_pop(t, 2);
						return v < 0;
					};
				}
				else
					croc_eh_throwStd(t, "ValueError", "Unknown array sorting method");
			}
			else
			{
				croc_ex_checkParam(t, 1, CrocType_Function);
				croc_dupTop(t);

				pred = [&](Array::Slot v1, Array::Slot v2)
				{
					auto reg = croc_dupTop(t);
					croc_pushNull(t);
					push(t_, v1.value);
					push(t_, v2.value);
					croc_call(t, reg, 1);

					if(!croc_isInt(t, -1))
					{
						croc_pushTypeString(t, -1);
						croc_eh_throwStd(t, "TypeError", "comparison function expected to return 'int', not '%s'",
							croc_getString(t, -1));
					}

					auto v = croc_getInt(t, -1);
					croc_popTop(t);
					return v >= 0;
				};
			}
		}
		else
		{
			pred = [&](Array::Slot v1, Array::Slot v2)
			{
				push(t_, v1.value);
				push(t_, v2.value);
				auto v = croc_cmp(t, -2, -1);
				croc_pop(t, 2);
				return v >= 0;
			};
		}

		// No write barrier. we're just moving items around, the items themselves don't change.
		arrSort(arr->toDArray(), pred);
		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("reverse")
	R"(Reverses this array's elements in place.

	\returns this array.)"),

	"reverse", 0, [](CrocThread* t) -> word_t
	{
		auto arr = checkArrayParam(t, 0)->toDArray();
		// No write barrier. Just moving items around.
		arrReverse(arr);
		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("dup")
	R"(\returns a shallow copy of this array. Only the elements are copied, not any data that they point to.)"),

	"dup", 0, [](CrocThread* t) -> word_t
	{
		auto src = checkArrayParam(t, 0);
		croc_array_new(t, cast(uword)croc_len(t, 0));
		auto t_ = Thread::from(t);
		auto dest = getArray(t_, -1);
		dest->sliceAssign(t_->vm->mem, 0, dest->length, src);
		return 1;
	}

DListSep()
	Docstr(DFunc("expand")
	R"(\returns all the elements of this array in order. In this way, you can "unpack" an array's values to pass as
	separate parameters to a function, or as return values, etc.

	\throws[ValueError] if this array is longer than 50 elements. Trying to return so many values can be a memory
		problem (and usually indicates a bug).)"),

	"expand", 0, [](CrocThread* t) -> word_t
	{
		auto arr = checkArrayParam(t, 0)->toDArray();

		if(arr.length > 50)
			croc_eh_throwStd(t, "ValueError", "Array too large to expand (more than 50 elements)");

		auto t_ = Thread::from(t);

		for(auto &val: arr)
			push(t_, val.value);

		return arr.length;
	}

DListSep()
	Docstr(DFunc("toString")
	R"(Returns a nice string representation of this array. This will format this array into a string that looks like a
	Croc expression, like "[1, 2, 3]". String elements will also be surrounded by double quotes.

	Note that the elements of the array do not have their toString metamethods called, since that could lead to infinite
	loops if this array references itself directly or indirectly. To get a more complete representation of an array,
	look at the \link{dumpVal} function (though that only outputs to the console).)"),

	"toString", 0, [](CrocThread* t) -> word_t
	{
		CrocStrBuffer buf;
		croc_ex_buffer_init(t, &buf);
		croc_ex_buffer_addChar(&buf, '[');
		auto length = cast(uword)croc_len(t, 0);

		for(uword i = 0; i < length; i++)
		{
			croc_idxi(t, 0, i);

			if(croc_isString(t, -1))
			{
				// this is GC-safe since the string is stored in the array
				uword n;
				auto s = croc_getStringn(t, -1, &n);
				croc_popTop(t);
				croc_ex_buffer_addChar(&buf, '"');
				croc_ex_buffer_addStringn(&buf, s, n);
				croc_ex_buffer_addChar(&buf, '"');
			}
			else
			{
				croc_pushToStringRaw(t, -1);
				croc_insertAndPop(t, -2);
				croc_ex_buffer_addTop(&buf);
			}

			if(i < length - 1)
				croc_ex_buffer_addString(&buf, ", ");
		}

		croc_ex_buffer_addChar(&buf, ']');
		croc_ex_buffer_finish(&buf);
		return 1;
	}

DListSep()
	Docstr(DFunc("apply") DParam("func", "function")
	R"(Iterates over this array, calling the function with each element of this array, and assigns the result of the
	function back into the corresponding array element.

	\examples "\tt{[1, 2, 3, 4, 5].apply(\\x -> x * x)}" will replace the values in the array with
	"\tt{[1, 4, 9, 16, 25]}".

	\param[func] should take one value and return one value.

	\returns this array.)"),

	"apply", 1, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);

		auto t_ = Thread::from(t);
		uword i = 0;
		for(auto &v: data)
		{
			auto reg = croc_dup(t, 1);
			croc_dup(t, 0);
			push(t_, v.value);
			croc_call(t, reg, 1);
			croc_idxai(t, 0, i++);
		}

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("map") DParam("func", "function")
	R"(Same as \link{apply}, except this array is unmodified and the values returned by \tt{func} are put into a new
	array of the same length.

	\returns the new array.)"),

	"map", 1, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);
		auto newArr = croc_array_new(t, cast(uword)croc_len(t, 0));

		auto t_ = Thread::from(t);
		uword i = 0;
		for(auto &v: data)
		{
			auto reg = croc_dup(t, 1);
			croc_dup(t, 0);
			push(t_, v.value);
			croc_call(t, reg, 1);
			croc_idxai(t, newArr, i);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("reduce") DParam("func", "function") DParamD("start", "any", "null")

	R"(Also known as \tt{fold} or \tt{foldl} (left fold) in many functional languages. This function takes a function
	\tt{func} of two arguments which is expected to return a value. It treats this array as a list of operands, and uses
	\tt{func} as if it were a left-associative binary operator between each pair of items in this array.

	This sounds confusing, but it makes sense with a bit of illustration: "\tt{[1 2 3 4 5].reduce(\\a, b -> a + b)}"
	will sum all the elements of the array and return 15, since it's like writing \tt{((((1 + 2) + 3) + 4) + 5)}. Notice
	that the operations are always performed left-to-right.

	This function optionally takes a "start value" which will be used as the very first item in the sequence. For
	instance, "\tt{[1 2 3].reduce(\\a, b -> a + b, 10)}" will do the same thing as \tt{(((10 + 1) + 2) + 3)}. In the
	event that the array's length is 0, the start value is simply returned as is.

	\returns the calculated value.

	\throws[ParamError] if \tt{#this == 0} and no value was passed for \tt{start}.)"),

	"reduce", 2, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);
		auto haveInitial = croc_isValidIndex(t, 2);

		if(data.length == 0)
		{
			if(!haveInitial)
				croc_eh_throwStd(t, "ParamError", "Attempting to reduce an empty array without an initial value");
			else
			{
				croc_dup(t, 2);
				return 1;
			}
		}

		uword start = 0;
		auto t_ = Thread::from(t);

		if(!haveInitial)
		{
			push(t_, data[0].value);
			start = 1;
		}
		else
			croc_dup(t, 2);

		for(auto &v: data.slice(start, data.length))
		{
			croc_dup(t, 1);
			croc_pushNull(t);
			croc_dup(t, -3);
			push(t_, v.value);
			croc_call(t, -4, 1);
			croc_insertAndPop(t, -2);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("rreduce") DParam("func", "function") DParamD("start", "any", "null")
	R"(Similar to \link{reduce}, but treats \tt{func} as a right-associative operator, meaning it goes through this
	array's elements in reverse order.

	"\tt{[1 2 3 4 5].rreduce(\\a, b -> a + b)}" will still sum all the elements, because addition is commutative, but
	the order in which this is done becomes \tt{(1 + (2 + (3 + (4 + 5))))}. Obviously if \tt{func} is not commutative,
	\tt{reduce} and \tt{rreduce} will give different results.

	\param[start] is treated as an optional \em{last} value, which means
	"\tt{[1 2 3 4 5].rreduce(\\a, b -> a + b), 10}" is like writing \tt{(1 + (2 + (3 + (4 + (5 + 10)))))}.

	\returns the calculated value.

	\throws[ParamError] if \tt{#this == 0} and no value was passed for \tt{start}.)"),

	"rreduce", 2, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);
		auto haveInitial = croc_isValidIndex(t, 2);

		if(data.length == 0)
		{
			if(!haveInitial)
				croc_eh_throwStd(t, "ParamError", "Attempting to reduce an empty array without an initial value");
			else
			{
				croc_dup(t, 2);
				return 1;
			}
		}

		uword start = data.length;
		auto t_ = Thread::from(t);

		if(!haveInitial)
		{
			start--;
			push(t_, data[start].value);
		}
		else
			croc_dup(t, 2);

		for(auto &v: data.slice(0, start).reverse())
		{
			croc_dup(t, 1);
			croc_pushNull(t);
			push(t_, v.value);
			croc_dup(t, -4);
			croc_call(t, -4, 1);
			croc_insertAndPop(t, -2);
		}

		return 1;
	}

DListSep()
	Docstr(DFunc("filter") DParam("func", "function")
	R"(Creates a new array which holds only those elements for which the given function returned \tt{true} when called
	with elements from the source array.

	The function is passed two arguments, the index and the value, and should return a boolean value. \tt{true} means
	the given element should be included in the result, and \tt{false} means it should be skipped.

	"\tt{[1, 2, "hi", 4.5, 6].filter(\\i, v -> isInt(v))}" would result in the array "\tt{[1, 2, 6]}", as the filter
	function only returns true for integral elements.

	\returns the new array.

	\throws[TypeError] if \tt{func} returns anything other than a bool.)"),

	"filter", 1, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);

		auto newLen = data.length / 2;
		auto retArray = croc_array_new(t, cast(uword)newLen);
		uword retIdx = 0;
		auto t_ = Thread::from(t);
		uword i = 0;

		for(auto &v: data)
		{
			croc_dup(t, 1);
			croc_dup(t, 0);
			croc_pushInt(t, i++);
			push(t_, v.value);
			croc_call(t, -4, 1);

			if(!croc_isBool(t, -1))
			{
				croc_pushTypeString(t, -1);
				croc_eh_throwStd(t, "TypeError", "filter function expected to return 'bool', not '%s'",
					croc_getString(t, -1));
			}

			if(croc_getBool(t, -1))
			{
				if(retIdx >= newLen)
				{
					newLen += 10;
					croc_pushInt(t, newLen);
					croc_lena(t, retArray);
				}

				push(t_, v.value);
				croc_idxai(t, retArray, retIdx++);
			}

			croc_popTop(t);
		}

		croc_pushInt(t, retIdx);
		croc_lena(t, retArray);
		croc_dup(t, retArray);
		return 1;
	}

DListSep()
	Docstr(DFunc("find") DParamAny("value") DParamD("start", "int", "0")
	R"(Performs a linear search for \tt{value} in this array, starting at \tt{start} and going right.

	This works by looping over this array's elements, and if the element is the same type as \tt{value}, it is compared
	(calling \tt{opCmp} if necessary). The index of the first element that is the same type as \tt{value} and which
	compares equal is returned.

	This differs from "\tt{val in a}" in that 'in' only checks if \tt{val} is identical to any of the values in \tt{a};
	it never calls \tt{opCmp} metamethods like this function does.

	\param[value] is the value to search for.
	\param[start] is the index where the search should begin. Can be negative to mean from the end of the array.

	\returns \tt{#this} if it wasn't found, or the index if it was.

	\throws[BoundsError] if \tt{start} is invalid.)"),

	"find", 2, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkAnyParam(t, 1);
		auto searchedType = croc_type(t, 1);
		auto start = croc_ex_optIndexParam(t, 2, data.length, "start", 0);
		auto t_ = Thread::from(t);
		uword i = start;

		for(auto &v: data.sliceToEnd(start))
		{
			if(searchedType == v.value.type)
			{
				push(t_, v.value);

				if(croc_cmp(t, 1, -1) == 0)
				{
					croc_pushInt(t, i);
					return 1;
				}

				croc_popTop(t);
			}

			i++;
		}

		croc_pushLen(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("findIf") DParam("pred", "function") DParamD("start", "int", "0")
	R"(Performs a linear search starting at \tt{start} and going right for the first element which, when passed to
	\tt{pred}, causes \tt{pred} to return \tt{true}. This is a generic form of \link{find}.

	\param[pred] is the predicate function; it will be called with a single parameter (a value from this array) and
		should return a bool saying whether or not it is the value being searched for.
	\param[start] is the index where the search should begin. Can be negative to mean from the end of the array.

	\returns \tt{#this} if nothing was found (\tt{pred} never returned \tt{true} for any element), or the index if
	something was.

	\throws[BoundsError] if \tt{start} is invalid.
	\throws[TypeError] if \tt{pred} returns something other than a bool.)"),

	"findIf", 2, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);
		auto start = croc_ex_optIndexParam(t, 2, data.length, "start", 0);
		auto t_ = Thread::from(t);
		uword i = start;

		for(auto &v: data.sliceToEnd(start))
		{
			auto reg = croc_dup(t, 1);
			croc_pushNull(t);
			push(t_, v.value);
			croc_call(t, reg, 1);

			if(!croc_isBool(t, -1))
			{
				croc_pushTypeString(t, -1);
				croc_eh_throwStd(t, "TypeError", "find function expected to return 'bool', not '%s'",
					croc_getString(t, -1));
			}

			if(croc_getBool(t, -1))
			{
				croc_pushInt(t, i);
				return 1;
			}

			croc_popTop(t);
			i++;
		}

		croc_pushLen(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("bsearch") DParamAny("value")

	R"(Performs a binary search for the value in this array. The array must be sorted for this search to work properly.
	Additionally, all the elements must be comparable (they had to be for the sort to work in the first place).

	\returns \tt{#this} if the value wasn't found, or its index if it was.)"),

	"bsearch", 1, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkAnyParam(t, 1);

		uword lo = 0;
		uword hi = data.length - 1;
		auto t_ = Thread::from(t);

		while((hi - lo) > 8)
		{
			uword mid = (lo + hi) >> 1;
			push(t_, data[mid].value);
			auto cmp = croc_cmp(t, 1, -1);
			croc_popTop(t);

			if(cmp == 0)
			{
				croc_pushInt(t, mid);
				return 1;
			}
			else if(cmp < 0)
				hi = mid - 1;
			else
				lo = mid + 1;
		}

		for(uword i = lo; i <= hi; i++)
		{
			push(t_, data[i].value);

			if(croc_cmp(t, 1, -1) == 0)
			{
				croc_pushInt(t, i);
				return 1;
			}

			croc_popTop(t);
		}

		croc_pushLen(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("pop") DParamD("index", "int", "-1")
	R"(Removes a single element from this array (by default the last one), shifting up any elements after it if there
	are any, and returns the removed value.

	This function makes it easy to use an array as a stack. Simply append values to push, and call \tt{a.pop()} to pop.

	\param[index] is the index of the element to be removed. Can be negative to mean from the end of this array.

	\returns the removed value.

	\throws[ValueError] if \tt{#this == 0}.
	\throws[BoundsError] if \tt{index} is invalid.)"),

	"pop", 1, [](CrocThread* t) -> word_t
	{
		auto arr = checkArrayParam(t, 0);
		auto data = arr->toDArray();
		auto index = croc_ex_optIndexParam(t, 1, data.length, "array", -1);
		auto t_ = Thread::from(t);
		push(t_, data[index].value);
		arr->idxa(t_->vm->mem, index, Value::nullValue); // to trigger write barrier

		for(uword i = cast(uword)index; i < data.length - 1; i++)
			data[i] = data[i + 1];

		data[data.length - 1].value = Value::nullValue; // to NOT trigger write barrier ;P
		arr->resize(t_->vm->mem, data.length - 1);
		return 1;
	}

DListSep()
	Docstr(DFunc("insert") DParam("index", "int") DParamAny("value")
	R"(The inverse of \link{pop}, this inserts a value into this array at a given index, shifting down any elements
	after if if there are any.

	\param[index] is the index where \tt{value} will be inserted. The value is inserted \em{before} the given index.
		\tt{index} can also be \tt{#this}, in which case the new value is simply appended to the end of this array. This
		can be negative to mean from the end of this array.
	\param[value] is the value to insert.

	\returns this array.

	\throws[BoundsError] if \tt{index} is invalid.)"),

	"insert", 2, [](CrocThread* t) -> word_t
	{
		auto arr = checkArrayParam(t, 0);
		auto data = arr->toDArray();
		crocint index = croc_ex_checkIntParam(t, 1);
		croc_ex_checkAnyParam(t, 2);

		if(index < 0)
			index += data.length;

		if(index < 0 || cast(uword)index > data.length)
			croc_eh_throwStd(t, "BoundsError", "Invalid array index: %" CROC_INTEGER_FORMAT, index);

		arr->resize(Thread::from(t)->vm->mem, data.length + 1);
		data = arr->toDArray(); // might have been invalidated

		for(uword i = data.length - 1; i > cast(uword)index; i--)
			data[i] = data[i - 1];

		croc_dup(t, 2);
		croc_idxai(t, 0, index);
		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("swap") DParam("idx1", "int") DParam("idx2", "int")
	R"(Swaps the values at the given indices.

	Both \tt{idx1} and \tt{idx2} can be negative to mean from the end of this array. If \tt{idx1 == idx2}, this method
	is a no-op.

	\returns this array.

	\throws[BoundsError] if \tt{idx1} or \tt{idx2} is invalid.)"),

	"swap", 2, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		auto idx1 = croc_ex_checkIndexParam(t, 1, data.length, "array");
		auto idx2 = croc_ex_checkIndexParam(t, 2, data.length, "array");

		if(idx1 != idx2)
		{
			auto tmp = data[idx1];
			data[idx1] = data[idx2];
			data[idx2] = tmp;
		}

		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("set") DVararg
	R"(Something like the inverse of \link{expand}, this takes a variadic number of arguments, sets this array's length
	to the number of arguments passed, and copies the arguments into this array.

	This is similar to using an array constructor, but reuses an array instead of allocating a new one.

	\returns this array.)"),

	"set", -1, [](CrocThread* t) -> word_t
	{
		auto numParams = croc_getStackSize(t) - 1;
		auto arr = checkArrayParam(t, 0);
		auto t_ = Thread::from(t);
		arr->resize(t_->vm->mem, numParams);
		arr->sliceAssign(t_->vm->mem, 0, numParams, t_->stack.slice(t_->stackIndex - numParams, t_->stackIndex));
		croc_dup(t, 0);
		return 1;
	}

DListSep()
	Docstr(DFunc("min")
	R"(\returns the smallest value in this array. All elements of the array must be comparable to each other for this to
	work. If this array only has one value, returns that value.

	\throws[ValueError] if this array is empty.)"),

	"min", 0, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();

		if(data.length == 0)
			croc_eh_throwStd(t, "ValueError", "Array is empty");

		uword extremeIdx = 0;
		auto t_ = Thread::from(t);
		push(t_, data[0].value);

		for(uword i = 1; i < data.length; i++)
		{
			push(t_, data[i].value);

			if(croc_cmp(t, -1, -2) < 0)
			{
				extremeIdx = i;
				croc_insert(t, -2);
			}

			croc_popTop(t);
		}

		croc_pushInt(t, extremeIdx);
		return 2;
	}

DListSep()
	Docstr(DFunc("max")
	R"(\returns the largest value in this array. All elements of the array must be comparable to each other for this to
	work. If this array only has one value, returns that value.

	\throws[ValueError] if this array is empty.)"),

	"max", 0, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();

		if(data.length == 0)
			croc_eh_throwStd(t, "ValueError", "Array is empty");

		uword extremeIdx = 0;
		auto t_ = Thread::from(t);
		push(t_, data[0].value);

		for(uword i = 1; i < data.length; i++)
		{
			push(t_, data[i].value);

			if(croc_cmp(t, -1, -2) > 0)
			{
				extremeIdx = i;
				croc_insert(t, -2);
			}

			croc_popTop(t);
		}

		croc_pushInt(t, extremeIdx);
		return 2;
	}

DListSep()
	Docstr(DFunc("extreme") DParam("pred", "function")
	R"(A generic version of \link{min} and \link{max}, this uses a predicate function to determine which element is the
	most "extreme." If this

	\param[pred] should take two parameters: the first is the new value to be tested, and the second is the current
		extreme so far. \tt{pred} should return \tt{true} if the new value is more extreme than the previous and
		\tt{false} otherwise.

		To illustrate, \tt{a.extreme(\\new, extreme -> new > extreme)} will do the same thing as \tt{a.max()} since the
		predicate returns \tt{true} if the new value is bigger than the previous extreme. (In this case, using \tt{max}
		is faster since it's optimized to do this, but this just illustrates the point.)

	\returns the most extreme value.

	\throws[ValueError] if this array is empty.
	\throws[TypeError] if \tt{pred} returns anything other than a bool.
	)"),

	"extreme", 1, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);

		if(data.length == 0)
			croc_eh_throwStd(t, "ValueError", "Array is empty");

		uword extremeIdx = 0;
		auto extreme = data[0].value;
		auto t_ = Thread::from(t);

		for(uword i = 1; i < data.length; i++)
		{
			croc_dup(t, 1);
			croc_pushNull(t);
			push(t_, data[i].value);
			push(t_, extreme);
			croc_call(t, -4, 1);

			if(!croc_isBool(t, -1))
			{
				croc_pushTypeString(t, -1);
				croc_eh_throwStd(t, "TypeError", "extrema function should return 'bool', not '%s'",
					croc_getString(t, -1));
			}

			if(croc_getBool(t, -1))
			{
				extreme = data[i].value;
				extremeIdx = i;
			}

			croc_popTop(t);
		}

		push(t_, extreme);
		croc_pushInt(t, extremeIdx);
		return 2;
	}

DListSep()
	Docstr(DFunc("any") DParamD("pred", "function", "null")
	R"(This is a generalized boolean "or" (logical disjunction) operation.

	\param[pred] is an optional predicate function.

		If none is passed, this method returns \tt{true} if any element in the array has a truth value of \tt{true}, and
		\tt{false} otherwise.

		If a function is passed, the function must take one parameter and return any value. The value returned from
		\tt{pred} can be any type, only its truth value matters. This method will return \tt{true} if \tt{pred} returned
		a value with a truth value of \tt{true} for any element in the array, and \tt{false} otherwise.

	\returns \tt{false} if called on an empty array.)"),

	"any", 1, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();

		if(croc_ex_optParam(t, 1, CrocType_Function))
		{
			auto t_ = Thread::from(t);

			for(auto &v: data)
			{
				croc_dup(t, 1);
				croc_pushNull(t);
				push(t_, v.value);
				croc_call(t, -3, 1);

				if(croc_isTrue(t, -1))
				{
					croc_pushBool(t, true);
					return 1;
				}

				croc_popTop(t);
			}
		}
		else
		{
			for(auto &v: data)
			{
				if(!v.value.isFalse())
				{
					croc_pushBool(t, true);
					return 1;
				}
			}
		}

		croc_pushBool(t, false);
		return 1;
	}

DListSep()
	Docstr(DFunc("all") DParamD("pred", "function", "null")
	R"(This is a generalized boolean "and" (logical conjunction) operation.

	\param[pred] is an optional predicate function.

		If none is passed, this method returns \tt{true} if all the elements in the array have a truth value of
		\tt{true}, and \tt{false} otherwise.

		If a function is passed, the function must take one parameter and return any value. The value returned from
		\tt{pred} can be any type, only its truth value matters. This method will return \tt{true} if \tt{pred} returned
		a value with a truth value of \tt{true} for all the elements in the array, and \tt{false} otherwise.

	\returns \tt{true} if called on an empty array.)"),

	"all", 1, [](CrocThread* t) -> word_t
	{
		auto data = checkArrayParam(t, 0)->toDArray();

		if(croc_ex_optParam(t, 1, CrocType_Function))
		{
			auto t_ = Thread::from(t);

			for(auto &v: data)
			{
				croc_dup(t, 1);
				croc_pushNull(t);
				push(t_, v.value);
				croc_call(t, -3, 1);

				if(!croc_isTrue(t, -1))
				{
					croc_pushBool(t, false);
					return 1;
				}

				croc_popTop(t);
			}
		}
		else
		{
			for(auto &v: data)
			{
				if(v.value.isFalse())
				{
					croc_pushBool(t, false);
					return 1;
				}
			}
		}

		croc_pushBool(t, true);
		return 1;
	}

DListSep()
	Docstr(DFunc("fill") DParamAny("value")
	R"(Sets every element in the array to the given value.)"),

	"fill", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Array);
		croc_ex_checkAnyParam(t, 1);
		croc_dup(t, 1);
		croc_array_fill(t, 0);
		return 0;
	}

DListSep()
	Docstr(DFunc("append") DVararg
	R"(Appends all the arguments to the end of the array, in order. This is different from the append operator (~=),
	because arrays will be appended as a single value, instead of having their elements appended.)"),

	"append", -1, [](CrocThread* t) -> word_t
	{
		auto arr = checkArrayParam(t, 0);
		auto numParams = croc_getStackSize(t) - 1;

		if(numParams == 0)
			return 0;

		auto oldlen = arr->length;
		auto t_ = Thread::from(t);
		arr->resize(t_->vm->mem, arr->length + numParams);
		arr->sliceAssign(t_->vm->mem, oldlen, oldlen + numParams,
			t_->stack.slice(t_->stackIndex - numParams, t_->stackIndex));

		return 0;
	}

DListSep()
	Docstr(DFunc("count") DParamAny("value") DParamD("pred", "function", "null")
	R"(Counts the number of times \tt{value} appears in this array, optionally using a predicate function to perform the
	comparison.

	\param[value] is the value to count.
	\param[pred] is the optional comparison predicate.

		If \tt{pred} is null, then this function simply loops over the array, testing if each element is equal to
		\tt{value} (calling \tt{opCmp} metamethods if needed), and counting each one which compares equal.

		If \tt{pred} is a function, it should take two values; the first will be elements from the array and the second
		will always be \tt{value}. It should return a bool indicating whether the two values compare equal.

		You can use this method instead of \link{countIf} to avoid creating a function closure, or to refactor code to
		use a cacheable function literal instead of a non-cacheable one.

	\returns the number of elements which compared equal to \tt{value} according to the behavior explained above.

	\throws[TypeError] if \tt{pred} is a function and it returns anything other than a bool.)"),

	"count", 2, [](CrocThread* t) -> word_t
	{
		auto arr = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkAnyParam(t, 1);
		auto t_ = Thread::from(t);
		auto searched = *getValue(t_, 1);
		uword count = 0;

		if(croc_ex_optParam(t, 2, CrocType_Function))
		{
			for(auto &val: arr)
			{
				auto reg = croc_dup(t, 2);
				croc_pushNull(t);
				push(t_, val.value);
				push(t_, searched);
				croc_call(t, reg, 1);

				if(!croc_isBool(t, -1))
				{
					croc_pushTypeString(t, -1);
					croc_eh_throwStd(t, "TypeError", "count predicate expected to return 'bool', not '%s'",
						croc_getString(t, -1));
				}

				if(croc_getBool(t, -1))
					count++;

				croc_popTop(t);
			}
		}
		else
		{
			for(auto &val: arr)
			{
				push(t_, val.value);
				push(t_, searched);

				if(croc_equals(t, -2, -1))
					count++;

				croc_pop(t, 2);
			}
		}

		croc_pushInt(t, count);
		return 1;
	}

DListSep()
	Docstr(DFunc("countIf") DParam("pred", "function")
	R"(Very similar to \link{count}, but more general. This version simply counts the number of items for which
	\tt{pred} returns true.

	\returns that count.

	\throws[TypeError] if \tt{pred} returns anything other than a bool.)"),

	"countIf", 1, [](CrocThread* t) -> word_t
	{
		auto arr = checkArrayParam(t, 0)->toDArray();
		croc_ex_checkParam(t, 1, CrocType_Function);
		uword count = 0;
		auto t_ = Thread::from(t);

		for(auto &val: arr)
		{
			auto reg = croc_dup(t, 1);
			croc_pushNull(t);
			push(t_, val.value);
			croc_call(t, reg, 1);

			if(!croc_isBool(t, -1))
			{
				croc_pushTypeString(t, -1);
				croc_eh_throwStd(t, "TypeError", "count predicate expected to return 'bool', not '%s'",
					croc_getString(t, -1));
			}

			if(croc_getBool(t, -1))
				count++;

			croc_popTop(t);
		}

		croc_pushInt(t, count);
		return 1;
	}
DEndList()

DBeginList(_opApply)
	nullptr,
	"iterator", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Array);
		auto index = croc_ex_checkIntParam(t, 1) + 1;

		if(index >= croc_len(t, 0))
			return 0;

		croc_pushInt(t, index);
		croc_dupTop(t);
		croc_idx(t, 0);
		return 2;
	}

DListSep()
	nullptr,
	"iteratorReverse", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Array);
		auto index = croc_ex_checkIntParam(t, 1) - 1;

		if(index < 0)
			return 0;

		croc_pushInt(t, index);
		croc_dupTop(t);
		croc_idx(t, 0);
		return 2;
	}

DListSep()
	Docstr(DFunc("opApply") DParamD("mode", "string", "null")
	R"(This allows you to iterate over arrays using \tt{foreach} loops.

\code
foreach(i, v; a)
// ...

foreach(i, v; a, "reverse")
// iterate backwards
\endcode

	As the second example shows, passing in the string "reverse" as the second parameter will cause the iteration to run
	in reverse.)"),

	"opApply", 1, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Array);

		if(croc_ex_optParam(t, 1, CrocType_String) && getCrocstr(t, 1) == ATODA("reverse"))
		{
			croc_pushUpval(t, 1);
			croc_dup(t, 0);
			croc_pushLen(t, 0);
		}
		else
		{
			croc_pushUpval(t, 0);
			croc_dup(t, 0);
			croc_pushInt(t, -1);
		}

		return 3;
	}
DEndList()

const StdlibRegister _flatten =
{
	Docstr(DFunc("flatten")
	R"(Flattens a multi-dimensional array into a single-dimensional array.

	The dimensions can be nested arbitrarily deep. Always returns a new array. Can be called on single-dimensional
	arrays too, in which case it just returns a duplicate of the array.

	\throws[ValueError] if any array is directly or indirectly circularly referenced.)"),

	"flatten", 0, [](CrocThread* t) -> word_t
	{
		croc_ex_checkParam(t, 0, CrocType_Array);
		auto flattening = croc_pushUpval(t, 0);
		auto ret = croc_array_new(t, 0);

		std::function<void(word)> flatten = [&](word arr)
		{
			auto a = croc_absIndex(t, arr);

			if(croc_in(t, a, flattening))
			{
				croc_table_clear(t, flattening);
				croc_eh_throwStd(t, "ValueError", "Attempting to flatten a self-referencing array");
			}

			croc_dup(t, a);
			croc_pushBool(t, true);
			croc_idxa(t, flattening);
			auto t_ = Thread::from(t);

			for(auto &val: getArray(t_, a)->toDArray())
			{
				if(val.value.type == CrocType_Array)
					flatten(push(t_, Value::from(val.value.mArray)));
				else
				{
					push(t_, val.value);
					croc_cateq(t, ret, 1);
				}
			}

			croc_dup(t, a);
			croc_pushNull(t);
			croc_idxa(t, flattening);
		};

		croc_table_clear(t, flattening);
		flatten(0);
		croc_dup(t, ret);
		return 1;
	}
};

	word loader(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);

		croc_namespace_new(t, "array");
			registerFields(t, _methodFuncs);
			registerFieldUV(t, _opApply);

				croc_table_new(t, 0);
			registerField(t, _flatten, 1);
		croc_vm_setTypeMT(t, CrocType_Array);
		return 0;
	}
	}

	void initArrayLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "array", &loader);
		croc_ex_importNS(t, "array");
#ifdef CROC_BUILTIN_DOCS
		CrocDoc doc;
		croc_ex_doc_init(t, &doc, __FILE__);
		croc_ex_doc_push(&doc,
		DModule("array")
		R"(The array library provides functionality for creating and manipulating arrays.)");
			docFields(&doc, _globalFuncs);

			croc_vm_pushTypeMT(t, CrocType_Array);
				croc_ex_doc_push(&doc,
				DNs("array")
				R"(This is the method namespace for array objects.)");
				docFields(&doc, _methodFuncs);
				docFieldUV(&doc, _opApply);
				docField(&doc, _flatten);
				croc_ex_doc_pop(&doc, -1);
			croc_popTop(t);
		croc_ex_doc_pop(&doc, -1);
		croc_ex_doc_finish(&doc);
#endif
		croc_popTop(t);
	}
}