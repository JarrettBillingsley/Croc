
#include "croc/base/writebarrier.hpp"
#include "croc/types.hpp"

#define SCRIPT_CLOSURE_EXTRA_SIZE(numUpvals) (sizeof(Upval*) * (numUpvals))
#define NATIVE_CLOSURE_EXTRA_SIZE(numUpvals) (sizeof(Value) * (numUpvals))

namespace croc
{
	namespace
	{
		const uint32_t MaxParams = cast(uint32_t)MaxParams;
	}

	// Create a script function.
	Function* Function::create(Memory& mem, Namespace* env, Funcdef* def)
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
	Function* Function::createPartial(Memory& mem, uword numUpvals)
	{
		auto f = ALLOC_OBJSZ(mem, Function, SCRIPT_CLOSURE_EXTRA_SIZE(numUpvals));
		f->type = CrocType_Function;
		f->isNative = false;
		f->numUpvals = numUpvals;
		f->scriptUpvals().fill(nullptr);
		return f;
	}

	// Finish constructing a script closure. Also used by serialization.
	void Function::finishCreate(Memory& mem, Function* f, Namespace* env, Funcdef* def)
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
	Function* Function::create(Memory& mem, Namespace* env, String* name, uword numParams, CrocNativeFunc func, uword numUpvals)
	{
		auto f = ALLOC_OBJSZ(mem, Function, NATIVE_CLOSURE_EXTRA_SIZE(numUpvals));
		f->type = CrocType_Function;
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

	void Function::setNativeUpval(Memory& mem, uword idx, Value val)
	{
		auto slot = &this->nativeUpvals()[idx];

		if(*slot != val)
		{
			if(slot->isGCObject() || val.isGCObject())
				WRITE_BARRIER(mem, this);

			*slot = val;
		}
	}

	void Function::setEnvironment(Memory& mem, Namespace* ns)
	{
		if(this->environment != ns)
		{
			WRITE_BARRIER(mem, this);
			this->environment = ns;
		}
	}

	bool Function::isVararg()
	{
		if(this->isNative)
			return this->numParams == MaxParams + 1;
		else
			return this->scriptFunc->isVararg;
	}
}
