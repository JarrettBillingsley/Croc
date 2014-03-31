#include "croc/base/hash.hpp"
#include "croc/base/sanity.hpp"
#include "croc/apitypes.h"
#include "croc/types/base.hpp"

namespace croc
{
	const char* typeToString(CrocType t)
	{
		switch(t)
		{
			case CrocType_Null:      return "null";
			case CrocType_Bool:      return "bool";
			case CrocType_Int:       return "int";
			case CrocType_Float:     return "float";
			case CrocType_Nativeobj: return "nativeobj";

			case CrocType_String:    return "string";
			case CrocType_Weakref:   return "weakref";

			case CrocType_Table:     return "table";
			case CrocType_Namespace: return "namespace";
			case CrocType_Array:     return "array";
			case CrocType_Memblock:  return "memblock";
			case CrocType_Function:  return "function";
			case CrocType_Funcdef:   return "funcdef";
			case CrocType_Class:     return "class";
			case CrocType_Instance:  return "instance";
			case CrocType_Thread:    return "thread";

			case CrocType_Upval:     return "upval";

			default: assert(false); return nullptr; // dummy
		}
	}

	const Value Value::nullValue = {CrocType_Null, { cast(crocint)0 }};

	hash_t Value::toHash() const
	{
		switch(this->type)
		{
			case CrocType_Null:      return 0;
			case CrocType_Bool:      return cast(hash_t)mBool;
			case CrocType_Int:       return cast(hash_t)mInt;
			case CrocType_Float:     return cast(hash_t)mFloat;
			case CrocType_Nativeobj: return cast(hash_t)cast(uword)mNativeobj;
			case CrocType_String:    return mString->hash;
			default:                 return cast(hash_t)cast(uword)mGCObj;
		}
	}

	const char* ThreadStateStrings[5] =
	{
		"initial",
		"waiting",
		"running",
		"suspended",
		"dead"
	};
}