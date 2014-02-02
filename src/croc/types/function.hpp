#ifndef CROC_TYPES_FUNCTION_HPP
#define CROC_TYPES_FUNCTION_HPP

#include "croc/types.hpp"

namespace croc
{
	namespace func
	{
		Function* create(Memory& mem, Namespace* env, Funcdef* def);
		Function* createPartial(Memory& mem, uword numUpvals);
		void finishCreate(Memory& mem, Function* f, Namespace* env, Funcdef* def);
		Function* create(Memory& mem, Namespace* env, String* name, CrocNativeFunc func, uword numUpvals, uword numParams);
		void setNativeUpval(Memory& mem, Function* f, uword idx, Value* val);
		void setEnvironment(Memory& mem, Function* f, Namespace* ns);
		bool isNative(Function* f);
		bool isVararg(Function* f);
	}
}

#endif