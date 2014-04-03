
#include "croc/api.h"
#include "croc/base/gc.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/gc.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	void runFinalizers(Thread* t)
	{
		auto &mem = t->vm->mem;
		auto &decBuffer = mem.decBuffer;

		t->vm->disableGC();
		auto hooksEnabled = t->hooksEnabled;
		t->hooksEnabled = false;

		// FINALIZE. Go through the finalize buffer, running the finalizer, and setting it to finalized. At this point,
		// the object may have been resurrected but we can't really tell unless we make the write barrier more
		// complicated. Or something. So we just queue a decrement for it. It'll get deallocated the next time around.
		t->vm->toFinalize.foreach([&t, &hooksEnabled, &decBuffer, &mem](GCObject* i_)
		{
			auto i = cast(Instance*)i_;
			// debug Stdout.formatln("Taking {} off toFinalize", i).flush;

			auto slot = push(t, *i->parent->finalizer);
			push(t, Value::from(i));

			auto failed = tryCode(t, slot, [&]
			{
				auto absSlot = slot + t->stackBase;
				commonCall(t, absSlot, 0, callPrologue(t, absSlot, 0, 1));
			});

			if(failed)
			{
				croc_eh_pushStd(*t, "FinalizerError");
				croc_pushNull(*t);
				croc_pushFormat(*t, "Error finalizing instance of class '%s'", i->parent->name->toCString());
				croc_call(*t, -3, 1);
				croc_swapTop(*t);
				croc_fielda(*t, -2, "cause");
				t->hooksEnabled = hooksEnabled;
				croc_eh_throw(*t);
			}

			GCOBJ_SETFINALIZED(i);
			decBuffer.add(mem, cast(GCObject*)i);
		});

		t->hooksEnabled = hooksEnabled;
		t->vm->enableGC();
		t->vm->toFinalize.reset();
	}
}