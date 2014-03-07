#ifndef CROC_API_APICHECKS_HPP
#define CROC_API_APICHECKS_HPP

#include "croc/internal/stack.hpp"

#define API_CHECK_NUM_PARAMS(numParams)\
	do {\
		assert(t->stackIndex > t->stackBase);\
		if((croc_getStackSize(*t) - 1) < (numParams))\
			croc_eh_throwStd(*t, "ApiError",\
				"%s - not enough parameters (expected %u, only have %u stack slots)",\
				__FUNCTION__,\
				(numParams),\
				croc_getStackSize(*t) - 1);\
	} while(false)

#define API_CHECK_PARAM(name, idx, type, niceName)\
	if(croc_type(*t, (idx)) != CrocType_##type)\
		API_PARAM_TYPE_ERROR(idx, niceName, typeToString(CrocType_##type));\
	auto name = getValue(t, (idx))->m##type;

#define API_PARAM_TYPE_ERROR(idx, paramName, expected)\
	do {\
		croc_pushTypeString(*t, (idx));\
		croc_eh_throwStd(*t, "TypeError", "%s - Expected type '%s' for %s, not '%s'",\
			__FUNCTION__, (expected), (paramName), croc_getString(*t, -1));\
	} while(false)

#endif