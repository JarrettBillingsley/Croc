
#include "croc/api.h"
#include "croc/types/base.hpp"

namespace croc
{
	void checkStack(Thread* t, AbsStack idx)
	{
		if(idx >= t->stack.length)
		{
			uword size = idx * 2;
			auto oldBase = t->stack.ptr;
			t->stack.resize(t->vm->mem, size);
			auto newBase = t->stack.ptr;

			if(newBase != oldBase)
			{
				for(auto uv = t->upvalHead; uv != nullptr; uv = uv->nextuv)
					uv->value = (uv->value - oldBase) + newBase;
			}
		}
	}

	RelStack fakeToRel(Thread* t, word fake)
	{
		assert(t->stackIndex > t->stackBase);

		auto size = croc_getStackSize(*t);

		if(fake < 0)
			fake += size;

		if(fake < 0 || fake >= cast(word)size)
			croc_eh_throwStd(*t, "ApiError",
				"Invalid stack index %" CROC_SSIZE_T_FORMAT " (stack size = %" CROC_SIZE_T_FORMAT ")", fake, size);

		return cast(RelStack)fake;
	}

	AbsStack fakeToAbs(Thread* t, word fake)
	{
		return fakeToRel(t, fake) + t->stackBase;
	}

	word push(Thread* t, Value val)
	{
		checkStack(t, t->stackIndex);
		t->stack[t->stackIndex] = val;
		t->stackIndex++;
		return cast(word)(t->stackIndex - 1 - t->stackBase);
	}

	word pushCrocstr(CrocThread* t, crocstr s)
	{
		return croc_pushStringn(t, cast(const char*)s.ptr, s.length);
	}

	Value* getValue(Thread* t, word slot)
	{
		return &t->stack[fakeToAbs(t, slot)];
	}

	String* getStringObj(Thread* t, word slot)
	{
		auto v = &t->stack[fakeToAbs(t, slot)];

		if(v->type == CrocType_String)
			return v->mString;
		else
			return nullptr;
	}

	crocstr getCrocstr(Thread* t, word slot)
	{
		auto v = &t->stack[fakeToAbs(t, slot)];

		if(v->type == CrocType_String)
			return v->mString->toDArray();
		else
			return crocstr();
	}

	crocstr getCrocstr(CrocThread* t, word slot)
	{
		return getCrocstr(Thread::from(t), slot);
	}

#define MAKE_GET(Type)\
	Type* get##Type(Thread* t, word slot)\
	{\
		auto v = &t->stack[fakeToAbs(t, slot)];\
		\
		if(v->type == CrocType_##Type)\
			return v->m##Type;\
		else\
			return nullptr;\
	}

	MAKE_GET(Weakref)
	MAKE_GET(Table)
	MAKE_GET(Namespace)
	MAKE_GET(Array)
	MAKE_GET(Memblock)
	MAKE_GET(Function)
	MAKE_GET(Funcdef)
	MAKE_GET(Class)
	MAKE_GET(Instance)
	MAKE_GET(Thread)

}