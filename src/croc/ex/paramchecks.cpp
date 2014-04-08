
#include <limits>

#include "croc/api.h"
#include "croc/types/base.hpp"

using namespace croc;

namespace
{
	uword_t commonCheckSliceParam(CrocThread* t, word_t index, uword_t length, const char* name, crocint_t def)
	{
		auto ret = croc_ex_optIntParam(t, index, def);

		if(ret < 0)
			ret += length;

		// big difference from croc_ex_checkIndexParam is that ret == length is okay!
		if(ret < 0 || cast(uword)ret > length || cast(uword)ret > std::numeric_limits<uword_t>::max())
		{
			croc_eh_throwStd(t, "BoundsError",
				"Invalid %s slice index %" CROC_INTEGER_FORMAT " (length is %" CROC_SIZE_T_FORMAT")",
				name, ret, length);
		}

		return cast(uword_t)ret;
	}
}

extern "C"
{
	/** Throws a \c TypeError exception with a nice message about the \c expected type for the parameter \c index, and
	what type was actually passed instead, like "Expected type 'int' for parameter 2, not 'string'".

	If \c index is 0, the message will say \c 'this' instead of <tt>'parameter n'</tt>.

	\returns a dummy value like \ref croc_ex_throw. */
	word_t croc_ex_paramTypeError(CrocThread* t, word_t index, const char* expected)
	{
		index = croc_absIndex(t, index);
		croc_pushTypeString(t, index);

		if(index == 0)
			return croc_eh_throwStd(t, "TypeError", "Expected type '%s' for 'this', not '%s'",
				expected, croc_getString(t, -1));
		else
			return croc_eh_throwStd(t, "TypeError",
				"Expected type '%s' for parameter %" CROC_SIZE_T_FORMAT ", not '%s'",
				expected, index, croc_getString(t, -1));
	}

	/** Given positive slice indices \c lo and \c hi, sees if they define a valid slice within a list-like object of
	length \c length. Calls \ref croc_ex_sliceIndexError if not.

	\param name is the descriptive name as listed in \ref croc_ex_sliceIndexError. */
	void croc_ex_checkValidSlice(CrocThread* t, crocint_t lo, crocint_t hi, uword_t length, const char* name)
	{
		if(lo < 0 || lo > hi || cast(uword)hi > length)
			croc_ex_sliceIndexError(t, lo, hi, length, name);
	}

	/** Throws a \c BoundsError exception with a nice message about \c index being an invalid index in a list-like
	object of length \c length, where \c name is a descriptive name of the object. For example, the message might be
	"Invalid Vector index 6 (length: 4)".

	\returns a dummy value like \ref croc_ex_throw. */
	word_t croc_ex_indexError(CrocThread* t, crocint_t index, uword_t length, const char* name)
	{
		return croc_eh_throwStd(t, "BoundsError",
			"Invalid %s index %" CROC_INTEGER_FORMAT " (length: %" CROC_SIZE_T_FORMAT")", name, index, length);
	}

	/** Throws a \c BoundsError exception with a nice message about \c lo and \c hi being invalid slice indices in a
	list-like object of length \c length, where \c name is a descriptive name of the object. For example, the message
	might be "Invalid Vector slice indices: 2 .. 5 (length: 4)".

	\returns a dummy value like \ref croc_ex_throw. */
	word_t croc_ex_sliceIndexError(CrocThread* t, crocint_t lo, crocint_t hi, uword_t length, const char* name)
	{
		return croc_eh_throwStd(t, "BoundsError",
			"Invalid %s slice indices: %" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT " (length: %"
				CROC_SIZE_T_FORMAT ")",
			name, lo, hi, length);
	}

	/** Checks that a parameter of any type has been passed at the given \c index, and if not, throws a \c ParamError
	saying that at least \c index parameters were expected. */
	void croc_ex_checkAnyParam(CrocThread* t, word_t index)
	{
		if(!croc_isValidIndex(t, index))
			croc_eh_throwStd(t, "ParamError",
				"Too few parameters (expected at least %" CROC_SIZE_T_FORMAT ", got %" CROC_SIZE_T_FORMAT ")",
				index, croc_getStackSize(t) - 1);
	}

	/** Checks that parameter \c index is of type \c type, and if not, throws an exception. */
	void croc_ex_checkParam(CrocThread* t, word_t index, CrocType type)
	{
		assert(type >= CrocType_FirstUserType && type <= CrocType_LastUserType);

		croc_ex_checkAnyParam(t, index);

		if(croc_type(t, index) != type)
			croc_ex_paramTypeError(t, index, typeToString(type));
	}

	/** Checks that parameter \c index is a bool, and returns its value. */
	int croc_ex_checkBoolParam(CrocThread* t, word_t index)
	{
		croc_ex_checkParam(t, index, CrocType_Bool);
		return croc_getBool(t, index);
	}

	/** Checks that parameter \c index is an int, and returns its value. */
	crocint_t croc_ex_checkIntParam(CrocThread* t, word_t index)
	{
		croc_ex_checkParam(t, index, CrocType_Int);
		return croc_getInt(t, index);
	}

	/** Checks that parameter \c index is a float, and returns its value. */
	crocfloat_t croc_ex_checkFloatParam(CrocThread* t, word_t index)
	{
		croc_ex_checkParam(t, index, CrocType_Float);
		return croc_getFloat(t, index);
	}

	/** Checks that parameter \c index is an int or float, and returns the value (cast to a float if needed). */
	crocfloat_t croc_ex_checkNumParam(CrocThread* t, word_t index)
	{
		croc_ex_checkAnyParam(t, index);

		if(croc_isInt(t, index))
			return croc_getInt(t, index);
		else if(croc_isFloat(t, index))
			return croc_getFloat(t, index);

		croc_ex_paramTypeError(t, index, "int|float");
		assert(false);
		return 0; // dummy
	}

	/** Checks that parameter \c index is a string, and returns the value. The same warnings that apply to \ref
	croc_getString apply here. */
	const char* croc_ex_checkStringParam(CrocThread* t, word_t index)
	{
		croc_ex_checkParam(t, index, CrocType_String);
		return croc_getString(t, index);
	}

	/** Checks that parameter \c index is a string, and returns the value, as well as returning the byte length of the
	string through the \c len parameter. The same warnings that apply to \ref croc_getString apply here. */
	const char* croc_ex_checkStringParamn(CrocThread* t, word_t index, uword_t* len)
	{
		croc_ex_checkParam(t, index, CrocType_String);
		return croc_getStringn(t, index, len);
	}

	/** Checks that parameter \c index is a one-codepoint string, and returns the codepoint. */
	crocchar_t croc_ex_checkCharParam(CrocThread* t, word_t index)
	{
		croc_ex_checkAnyParam(t, index);

		if(!croc_isChar(t, index))
			croc_ex_paramTypeError(t, index, "string");

		return croc_getChar(t, index);
	}

	/** Checks that parameter \c index is an instance of the class \c name (which is looked up with \ref
	croc_ex_lookup). */
	void croc_ex_checkInstParam(CrocThread* t, word_t index, const char* name)
	{
		index = croc_absIndex(t, index);
		croc_ex_checkParam(t, index, CrocType_Instance);

		croc_ex_lookup(t, name);

		if(!croc_isInstanceOf(t, index, -1))
		{
			croc_pushTypeString(t, index);

			if(index == 0)
				croc_eh_throwStd(t, "TypeError", "Expected instance of class %s for 'this', not %s",
					name, croc_getString(t, -1));
			else
				croc_eh_throwStd(t, "TypeError",
					"Expected instance of class %s for parameter %" CROC_SIZE_T_FORMAT ", not %s",
					name, index, croc_getString(t, -1));
		}

		croc_popTop(t);
	}

	/** Same as \ref croc_ex_checkInstParam, but checks that parameter \c index is an instance of the class in slot
	\c classIndex. */
	void croc_ex_checkInstParamSlot(CrocThread* t, word_t index, word_t classIndex)
	{
		croc_ex_checkParam(t, index, CrocType_Instance);

		if(!croc_isInstanceOf(t, index, classIndex))
		{
			auto name = croc_getNameOf(t, classIndex);
			croc_pushTypeString(t, index);

			if(index == 0)
				croc_eh_throwStd(t, "TypeError", "Expected instance of class %s for 'this', not %s",
					name, croc_getString(t, -1));
			else
				croc_eh_throwStd(t, "TypeError",
					"Expected instance of class %s for parameter %" CROC_SIZE_T_FORMAT ", not %s",
					name, index, croc_getString(t, -1));
		}
	}

	/** Checks that parameter \c index is an integer that is suitable to be used as an index into a list-like object of
	length \length. The parameter can be negative to mean from the end of the object, in which case it will
	automatically have \c length added to it before being returned.

	\param name is a descriptive name of the object which will be passed to \ref croc_ex_indexError if this function
		fails.

	\returns the value, which will always be >= 0. */
	uword_t croc_ex_checkIndexParam(CrocThread* t, word_t index, uword_t length, const char* name)
	{
		auto ret = croc_ex_checkIntParam(t, index);

		if(ret < 0)
			ret += length;

		if(ret < 0 || cast(uword)ret >= length || cast(uword)ret > std::numeric_limits<uword_t>::max())
			croc_ex_indexError(t, ret, length, name);

		return cast(uword_t)ret;
	}

	/** Checks that parameter \c index is an optional integer that is suitable to be used as a slice index into a
	list-like object of length \length. If no parameter was passed for \c index, returns 0 (as the default behavior for
	a null low slice is to slice from the beginning of the list). This differs from \ref croc_ex_checkIndexParam in one
	important regard: slice indices can be equal to \c length, whereas normal indices cannot.

	\param name is a descriptive name of the object which will be passed to \ref croc_ex_indexError if this function
		fails.

	\returns the value, which will always be >= 0. */
	uword_t croc_ex_checkLoSliceParam(CrocThread* t, word_t index, uword_t length, const char* name)
	{
		return commonCheckSliceParam(t, index, length, name, 0);
	}

	/** Same as \ref croc_ex_checkLoSliceParam, except defaults to returning \c length if \c null was passed for
	parameter \c index. */
	uword_t croc_ex_checkHiSliceParam(CrocThread* t, word_t index, uword_t length, const char* name)
	{
		return commonCheckSliceParam(t, index, length, name, length);
	}

	/** Combines checking for low and high slice parameters into one function. The parameters at \c index and
	<tt>index + 1</tt> are checked as low and high slice indices into a list-like object of length \c length;

	\param[out] hi will receive the high slice index value.
	\returns the low slice index value. */
	uword_t croc_ex_checkSliceParams(CrocThread* t, word_t index, uword_t length, const char* name, uword_t* hi)
	{
		assert(hi);
		auto lo = croc_ex_optIntParam(t, index, 0);
		auto hi_ = croc_ex_optIntParam(t, index + 1, length);

		if(lo < 0)
			lo += length;

		if(hi_ < 0)
			hi_ += length;

		if(lo < 0 || lo > hi_ || cast(uword_t)hi_ > length)
			croc_ex_sliceIndexError(t, lo, hi_, length, name);

		*hi = hi_;
		return lo;
	}

	/** \returns nonzero if a value of type \c type was passed for parameter \c index, or 0 if \c null was passed or no
	parameter was passed. */
	int croc_ex_optParam(CrocThread* t, word_t index, CrocType type)
	{
		if(!croc_isValidIndex(t, index) || croc_isNull(t, index))
			return false;

		if(croc_type(t, index) != type)
			croc_ex_paramTypeError(t, index, typeToString(type));

		return true;
	}

	/** If there was a bool passed for parameter \c index, returns its value; otherwise, returns \c def. */
	int croc_ex_optBoolParam(CrocThread* t, word_t index, int def)
	{
		if(croc_ex_optParam(t, index, CrocType_Bool))
			return croc_getBool(t, index);
		else
			return def;
	}

	/** If there was an int passed for parameter \c index, returns its value; otherwise, returns \c def. */
	crocint_t croc_ex_optIntParam(CrocThread* t, word_t index, crocint_t def)
	{
		if(croc_ex_optParam(t, index, CrocType_Int))
			return croc_getInt(t, index);
		else
			return def;
	}

	/** If there was a float passed for parameter \c index, returns its value; otherwise, returns \c def. */
	crocfloat_t croc_ex_optFloatParam(CrocThread* t, word_t index, crocfloat_t def)
	{
		if(croc_ex_optParam(t, index, CrocType_Float))
			return croc_getFloat(t, index);
		else
			return def;
	}

	/** If there was a number passed for parameter \c index, returns its value; otherwise, returns \c def. */
	crocfloat_t croc_ex_optNumParam(CrocThread* t, word_t index, crocfloat_t def)
	{
		if(!croc_isValidIndex(t, index) || croc_isNull(t, index))
			return def;

		if(!croc_isNum(t, index))
			croc_ex_paramTypeError(t, index, "int|float");

		return croc_getNum(t, index);
	}

	/** If there was a string  passed for parameter \c index, returns its value; otherwise, returns \c def. */
	const char* croc_ex_optStringParam(CrocThread* t, word_t index, const char* def)
	{
		if(croc_ex_optParam(t, index, CrocType_String))
			return croc_getString(t, index);
		else
			return def;
	}

	/** Same as \ref croc_ex_optStringParam, but returns the length of the string (or of \c def) through the \c len
	parameter. */
	const char* croc_ex_optStringParamn(CrocThread* t, word_t index, const char* def, uword_t* len)
	{
		if(croc_ex_optParam(t, index, CrocType_String))
			return croc_getStringn(t, index, len);
		else
		{
			*len = strlen(def);
			return def;
		}
	}

	/** If there was a one-codepoint string passed for parameter \c index, returns that codepoint; otherwise, returns
	\c def. */
	crocchar_t croc_ex_optCharParam(CrocThread* t, word_t index, crocchar_t def)
	{
		if(!croc_isValidIndex(t, index) || croc_isNull(t, index))
			return def;

		if(!croc_isChar(t, index))
			croc_ex_paramTypeError(t, index, "string");

		return croc_getChar(t, index);
	}

	/** If there was an int passed for parameter \c index, checks that it's a valid index like
	\ref croc_ex_checkIndexParam; otherwise, returns \c def. */
	uword_t croc_ex_optIndexParam(CrocThread* t, word_t index, uword_t length, const char* name, crocint_t def)
	{
		auto ret = croc_ex_optIntParam(t, index, def);

		if(ret < 0)
			ret += length;

		if(ret < 0 || cast(uword)ret >= length || cast(uword)ret > std::numeric_limits<uword_t>::max())
			croc_ex_indexError(t, ret, length, name);

		return cast(uword_t)ret;
	}
}