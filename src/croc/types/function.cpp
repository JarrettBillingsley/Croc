#include <limits>

#include "croc/base/writebarrier.hpp"
#include "croc/types/function.hpp"

#define SCRIPT_CLOSURE_EXTRA_SIZE(numUpvals) (sizeof(Upval*) * (numUpvals))
#define NATIVE_CLOSURE_EXTRA_SIZE(numUpvals) (sizeof(Value) * (numUpvals))

namespace croc
{
	namespace func
	{
		namespace
		{
		const uint32_t MaxParams = std::numeric_limits<uint32_t>::max();
		}

		// Create a script function.
		Function* create(Memory& mem, Namespace* env, Funcdef* def)
		{
			if(def->environment && def->environment != env)
				return nullptr;

			if(def->cachedFunc)
				return def->cachedFunc;

			auto f = createPartial(mem, def->upvals.length);
			finishCreate(mem, f, env, def);
			return f;
		}

		// Partially construct a script closure. This is used by the serialization system.
		Function* createPartial(Memory& mem, uword numUpvals)
		{
			auto f = ALLOC_OBJSZ(mem, Function, SCRIPT_CLOSURE_EXTRA_SIZE(numUpvals));
			f->isNative = false;
			f->numUpvals = numUpvals;
			f->scriptUpvals().fill(nullptr);
			return f;
		}

		// Finish constructing a script closure. Also used by serialization.
		void finishCreate(Memory& mem, Function* f, Namespace* env, Funcdef* def)
		{
			f->environment = env;
			f->name = def->name;
			f->numParams = def->numParams;

			if(def->isVararg)
				f->maxParams = MaxParams + 1;
			else
				f->maxParams = def->numParams;

			f->scriptFunc = def;

			if(def->environment == nullptr)
			{
				WRITE_BARRIER(mem, def);
				def->environment = env;
			}

			if(def->upvals.length == 0 && def->cachedFunc == nullptr)
			{
				WRITE_BARRIER(mem, def);
				def->cachedFunc = f;
			}
		}

		// Create a native function.
		Function* create(Memory& mem, Namespace* env, String* name, CrocNativeFunc func, uword numUpvals, uword numParams)
		{
			auto f = ALLOC_OBJSZ(mem, Function, NATIVE_CLOSURE_EXTRA_SIZE(numUpvals));
			f->nativeUpvals().fill(Value::nullValue);
			f->isNative = true;
			f->environment = env;
			f->name = name;
			f->numUpvals = numUpvals;
			f->numParams = numParams + 1; // +1 to include 'this'
			f->maxParams = f->numParams;
			f->nativeFunc = func;
			return f;
		}

		void setNativeUpval(Memory& mem, Function* f, uword idx, Value* val)
		{
			auto slot = &f->nativeUpvals()[idx];

			if(*slot != *val)
			{
				if(slot->isGCObject() || val->isGCObject())
					WRITE_BARRIER(mem, f);

				*slot = *val;
			}
		}

		void setEnvironment(Memory& mem, Function* f, Namespace* ns)
		{
			if(f->environment != ns)
			{
				WRITE_BARRIER(mem, f);
				f->environment = ns;
			}
		}

		bool isNative(Function* f)
		{
			return f->isNative;
		}

		bool isVararg(Function* f)
		{
			if(f->isNative)
				return f->numParams == MaxParams + 1;
			else
				return f->scriptFunc->isVararg;
		}
	}
}
