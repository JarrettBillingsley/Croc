#ifndef CROC_INTERNAL_APICHECKS_HPP
#define CROC_INTERNAL_APICHECKS_HPP

#define API_CHECK_NUM_PARAMS(numParams)\
	do {\
		assert(t->stackIndex > t->stackBase);\
		if((croc_getStackSize(*t) - 1) < (numParams))\
			croc_eh_throwStd(*t, "ApiError",\
				"{} - not enough parameters (expected {}, only have {} stack slots)",\
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
		croc_eh_throwStd(*t, "TypeError", "{} - Expected type '{}' for {}, not '{}'",\
			__FUNCTION__, (expected), (paramName), croc_getString(*t, -1));\
	} while(false)

#endif