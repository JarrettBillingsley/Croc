#include "croc/base/hash.hpp"
#include "croc/base/sanity.hpp"
#include "croc/apitypes.h"
#include "croc/types.hpp"

extern "C" const char* croc_typeToString(CrocType t)
{
	switch(t)
	{
		case CrocType_Null:      return "null";
		case CrocType_Bool:      return "bool";
		case CrocType_Int:       return "int";
		case CrocType_Float:     return "float";
		case CrocType_Char:      return "char";
		case CrocType_NativeObj: return "nativeobj";

		case CrocType_String:    return "string";
		case CrocType_WeakRef:   return "weakref";

		case CrocType_Table:     return "table";
		case CrocType_Namespace: return "namespace";
		case CrocType_Array:     return "array";
		case CrocType_Memblock:  return "memblock";
		case CrocType_Function:  return "function";
		case CrocType_FuncDef:   return "funcdef";
		case CrocType_Class:     return "class";
		case CrocType_Instance:  return "instance";
		case CrocType_Thread:    return "thread";

		case CrocType_Upvalue:   return "upvalue";

		default:
			// TODO: make this actually error
			assert(false);
	}
}

namespace croc
{
	// ========================================
	// Value

	const Value Value::nullValue = {CrocType_Null, cast(crocint)0};

	bool Value::operator==(const Value& other) const
	{
		if(this->type != other.type)
			return false;

		switch(this->type)
		{
			case CrocType_Null:      return true;
			case CrocType_Bool:      return this->mBool == other.mBool;
			case CrocType_Int:       return this->mInt == other.mInt;
			case CrocType_Float:     return this->mFloat == other.mFloat;
			case CrocType_Char:      return this->mChar == other.mChar;
			case CrocType_NativeObj: return this->mNativeObj == other.mNativeObj;
			default:                 return this->mGCObj == other.mGCObj;
		}
	}

	bool Value::isFalse() const
	{
		return
		(this->type == CrocType_Null) ||
		(this->type == CrocType_Bool && this->mBool == false) ||
		(this->type == CrocType_Int && this->mInt == 0) ||
		(this->type == CrocType_Float && this->mFloat == 0.0) ||
		(this->type == CrocType_Char && this->mChar == 0);
	}

	hash_t Value::toHash() const
	{
		switch(this->type)
		{
			case CrocType_Null:      return 0;
			case CrocType_Bool:      return cast(hash_t)mBool;
			case CrocType_Int:       return cast(hash_t)mInt;
			case CrocType_Float:     return cast(hash_t)mFloat;
			case CrocType_Char:      return cast(hash_t)mChar;
			case CrocType_NativeObj: return cast(hash_t)mNativeObj;
			case CrocType_String:    return mString->hash;
			default:                 return cast(hash_t)cast(void*)mGCObj;
		}
	}

	// ========================================
	// Thread

	const char* Thread::StateStrings[5] =
	{
		"initial",
		"waiting",
		"running",
		"suspended",
		"dead"
	};
}