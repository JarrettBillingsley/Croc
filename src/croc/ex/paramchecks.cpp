
#include "croc/api.h"
#include "croc/types/base.hpp"

namespace croc
{
extern "C"
{
	word_t croc_ex_paramTypeError(CrocThread* t, word_t index, const char* expected)
	{
		index = croc_absIndex(t, index);
		croc_pushTypeString(t, index);

		if(index == 0)
			return croc_eh_throwStd(t, "TypeError", "Expected type '%s' for 'this', not '%s'",
				expected, croc_getString(t, -1));
		else
			return croc_eh_throwStd(t, "TypeError", "Expected type '%s' for parameter %u, not '%s'",
				expected, index, croc_getString(t, -1));
	}

	void croc_ex_checkAnyParam(CrocThread* t, word_t index)
	{
		if(!croc_isValidIndex(t, index))
			croc_eh_throwStd(t, "ParamError", "Too few parameters (expected at least %u, got %u)",
				index, croc_getStackSize(t) - 1);
	}

	void croc_ex_checkParam(CrocThread* t, word_t index, CrocType type)
	{
		// ORDER CROCTYPE
		assert(type >= CrocType_FirstUserType && type <= CrocType_LastUserType);

		croc_ex_checkAnyParam(t, index);

		if(croc_type(t, index) != type)
			croc_ex_paramTypeError(t, index, typeToString(type));
	}

	int croc_ex_checkBoolParam(CrocThread* t, word_t index)
	{
		croc_ex_checkParam(t, index, CrocType_Bool);
		return croc_getBool(t, index);
	}

	crocint_t croc_ex_checkIntParam(CrocThread* t, word_t index)
	{
		croc_ex_checkParam(t, index, CrocType_Int);
		return croc_getInt(t, index);
	}

	crocfloat_t croc_ex_checkFloatParam(CrocThread* t, word_t index)
	{
		croc_ex_checkParam(t, index, CrocType_Float);
		return croc_getFloat(t, index);
	}

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

	const char* croc_ex_checkStringParam(CrocThread* t, word_t index)
	{
		croc_ex_checkParam(t, index, CrocType_String);
		return croc_getString(t, index);
	}

	const char* croc_ex_checkStringParamn(CrocThread* t, word_t index, uword_t* len)
	{
		croc_ex_checkParam(t, index, CrocType_String);
		return croc_getStringn(t, index, len);
	}

	crocchar_t croc_ex_checkCharParam(CrocThread* t, word_t index)
	{
		croc_ex_checkAnyParam(t, index);

		if(!croc_isChar(t, index))
			croc_ex_paramTypeError(t, index, "string");

		return croc_getChar(t, index);
	}

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
				croc_eh_throwStd(t, "TypeError", "Expected instance of class %s for parameter %u, not %s",
					name, index, croc_getString(t, -1));
		}

		croc_popTop(t);
	}

	void croc_ex_checkInstParamSlot(CrocThread* t, word_t index, word_t classIndex)
	{
		croc_ex_checkParam(t, index, CrocType_Instance);

		if(!croc_isInstanceOf(t, index, classIndex))
		{
			auto name = croc_class_getName(t, classIndex);
			croc_pushTypeString(t, index);

			if(index == 0)
				croc_eh_throwStd(t, "TypeError", "Expected instance of class %s for 'this', not %s",
					name, croc_getString(t, -1));
			else
				croc_eh_throwStd(t, "TypeError", "Expected instance of class %s for parameter %u, not %s",
					name, index, croc_getString(t, -1));
		}
	}

	int croc_ex_optParam(CrocThread* t, word_t index, CrocType type)
	{
		if(!croc_isValidIndex(t, index) || croc_isNull(t, index))
			return false;

		if(croc_type(t, index) != type)
			croc_ex_paramTypeError(t, index, typeToString(type));

		return true;
	}

	int croc_ex_optBoolParam(CrocThread* t, word_t index, int def)
	{
		if(croc_ex_optParam(t, index, CrocType_Bool))
			return croc_getBool(t, index);
		else
			return def;
	}

	crocint_t croc_ex_optIntParam(CrocThread* t, word_t index, crocint_t def)
	{
		if(croc_ex_optParam(t, index, CrocType_Int))
			return croc_getInt(t, index);
		else
			return def;
	}

	crocfloat_t croc_ex_optFloatParam(CrocThread* t, word_t index, crocfloat_t def)
	{
		if(croc_ex_optParam(t, index, CrocType_Float))
			return croc_getFloat(t, index);
		else
			return def;
	}

	crocfloat_t croc_ex_optNumParam(CrocThread* t, word_t index, crocfloat_t def)
	{
		if(!croc_isValidIndex(t, index) || croc_isNull(t, index))
			return def;

		if(!croc_isNum(t, index))
			croc_ex_paramTypeError(t, index, "int|float");

		return croc_getNum(t, index);
	}

	const char* croc_ex_optStringParam(CrocThread* t, word_t index, const char* def)
	{
		if(croc_ex_optParam(t, index, CrocType_String))
			return croc_getString(t, index);
		else
			return def;
	}

	const char* croc_ex_optStringParamn(CrocThread* t, word_t index, const char* def, uword_t* len)
	{
		if(croc_ex_optParam(t, index, CrocType_String))
			return croc_getStringn(t, index, len);
		else
			return def;
	}

	crocchar_t croc_ex_optCharParam(CrocThread* t, word_t index, crocchar_t def)
	{
		if(!croc_isValidIndex(t, index) || croc_isNull(t, index))
			return def;

		if(!croc_isChar(t, index))
			croc_ex_paramTypeError(t, index, "string");

		return croc_getChar(t, index);
	}
}
}