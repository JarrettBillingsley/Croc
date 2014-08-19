#include "croc/base/gc.hpp"
#include "croc/base/gcobject.hpp"
#include "croc/base/memory.hpp"
#include "croc/base/writebarrier.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
		// Free an object.
		void free(VM* vm, GCObject* o)
		{
			// debug(FREES) printf("FREE: {} at {}", CrocValue.typeStrings[(cast(CrocBaseObject*)o).mType], o).flush;

			if(auto r = vm->weakrefTab.lookup(cast(GCObject*)o))
			{
				(*r)->obj = nullptr;
				vm->weakrefTab.remove(cast(GCObject*)o);
			}

			switch(o->type)
			{
				case CrocType_String:    String::free(vm, cast(String*)o);              return;
				case CrocType_Table:     Table::free(vm->mem, cast(Table*)o);           return;
				case CrocType_Array:     Array::free(vm->mem, cast(Array*)o);           return;
				case CrocType_Memblock:  Memblock::free(vm->mem, cast(Memblock*)o);     return;
				case CrocType_Namespace: Namespace::free(vm->mem, cast(Namespace*)o);   return;
				case CrocType_Thread:    Thread::free(cast(Thread*)o);                  return;
				case CrocType_Weakref:   Weakref::free(vm, cast(Weakref*)o);            return;
				case CrocType_Funcdef:   Funcdef::free(vm->mem, cast(Funcdef*)o);       return;
				case CrocType_Class:     Class::free(vm->mem, cast(Class*)o);           return;
				case CrocType_Function:  FREE_OBJ(vm->mem, Function, cast(Function*)o); return;
				case CrocType_Instance:  FREE_OBJ(vm->mem, Instance, cast(Instance*)o); return;
				case CrocType_Upval:     FREE_OBJ(vm->mem, Upval, cast(Upval*)o);       return;

				default: /*debug printf("{}", (cast(GCObject*)o).mType).flush;*/ assert(false);
			}
		}

		void rcIncrement(GCObject* obj)
		{
			assert(GCOBJ_INRC(obj));

			obj->refCount++;

			if(GCOBJ_COLOR(obj) != GCFlags_Green)
				GCOBJ_SETCOLOR(obj, GCFlags_Black);
		}

		// =============================================================================================================
		// Cycle collection

		void markGray(GCObject* obj)
		{
			assert(GCOBJ_INRC(obj));
			assert(GCOBJ_COLOR(obj) != GCFlags_Green);
			assert(obj->type != CrocType_String);

			if(GCOBJ_COLOR(obj) != GCFlags_Grey)
			{
				GCOBJ_SETCOLOR(obj, GCFlags_Grey);

				visitObj(obj, false, [](GCObject* slot)
				{
					if(GCOBJ_COLOR(slot) != GCFlags_Green)
					{
						slot->refCount--;
						assert(slot->refCount != cast(uint32_t)-1);
						markGray(slot);
					}
				});
			}
		}

		void cycleScanBlack(GCObject* obj)
		{
			assert(GCOBJ_INRC(obj));
			assert(GCOBJ_COLOR(obj) != GCFlags_Green);
			assert(obj->type != CrocType_String);

			GCOBJ_SETCOLOR(obj, GCFlags_Black);

			visitObj(obj, false, [](GCObject* slot)
			{
				auto color = GCOBJ_COLOR(slot);

				if(color != GCFlags_Green)
				{
					slot->refCount++;

					if(color != GCFlags_Black)
						cycleScanBlack(slot);
				}
			});
		}

		void cycleScan(VM* vm, GCObject* obj)
		{
			assert(GCOBJ_INRC(obj));

			if(GCOBJ_COLOR(obj) == GCFlags_Grey)
			{
				if(obj->refCount > 0)
					cycleScanBlack(obj);
				else if(GCOBJ_FINALIZABLE(obj) && !GCOBJ_FINALIZED(obj))
				{
					obj->refCount = 1;
					// debug(FINALIZE) printf("Putting {} on toFinalize", obj);
					vm->toFinalize.add(vm->mem, obj);
					cycleScanBlack(obj);
				}
				else
				{
					GCOBJ_SETCOLOR(obj, GCFlags_White);

					visitObj(obj, false, [&](GCObject* slot)
					{
						cycleScan(vm, slot);
					});
				}
			}
		}

		void collectCycleWhite(VM* vm, GCObject* obj)
		{
			assert(GCOBJ_INRC(obj));

			auto color = GCOBJ_COLOR(obj);

			if(color == GCFlags_Green)
			{
				// It better not be in the roots. that'd be impossible.
				assert(!GCOBJ_CYCLELOGGED(obj));

				if(--obj->refCount == 0)
					free(vm, obj);
			}
			else if(color == GCFlags_White && !GCOBJ_CYCLELOGGED(obj))
			{
				// Is this even possible since we mark it black in the previous phase?
				// if((obj.gcflags & GCFlags_Finalizable) && (obj.gcflags & GCFlags_Finalized) == 0)
				// 	throw new CrocFatalException("Unfinalized finalizable object (instance of "
				// 		 ~ (cast(CrocInstance*)obj).parent.name.toString() ~ ") in cycle!");

				GCOBJ_SETCOLOR(obj, GCFlags_Black);

				visitObj(obj, false, [&](GCObject* slot)
				{
					collectCycleWhite(vm, slot);
				});

				vm->toFree.add(vm->mem, obj);
			}
		}

		void collectCycles(VM* vm)
		{
			auto &cycleRoots = vm->cycleRoots;

			// Mark
			for(auto it = cycleRoots.iterator(); it.hasNext(); )
			{
				auto obj = it.next();
				assert(GCOBJ_INRC(obj));

				if(GCOBJ_COLOR(obj) == GCFlags_Purple)
					markGray(obj);
				else
				{
					GCOBJ_CYCLEUNLOG(obj);
					it.removeCurrent();

					if(GCOBJ_COLOR(obj) == GCFlags_Black && obj->refCount == 0)
						free(vm, obj);
				}
			}

			// Scan
			cycleRoots.foreach([&](GCObject* obj)
			{
				cycleScan(vm, obj);
			});

			// Collect
			while(!cycleRoots.isEmpty())
			{
				auto obj = cycleRoots.remove();
				GCOBJ_CYCLEUNLOG(obj);
				collectCycleWhite(vm, obj);
			}

			// Free
			while(!vm->toFree.isEmpty())
			{
				auto obj = vm->toFree.remove();
				free(vm, obj);
			}
		}
	} // end anonymous namespace

	void gcCycle(VM* vm, GCCycleType cycleType)
	{
		// debug(BEGINEND)
		// {
		// 	static counter = 0;
		// 	printf("======================= BEGIN {} =============================== {}",
		// 		++counter, cast(uint)cycleType).flush;
		// 	printf("Nursery: {} bytes allocated out of {}; mod buffer length = {}, dec buffer length = {}",
		// 		vm->mem.nurseryBytes, vm->mem.nurseryLimit, vm->mem.modBuffer.length, vm->mem.decBuffer.length);
		// }

		assert(!vm->inGCCycle);
		assert(vm->mem.gcDisabled == 0);

		vm->inGCCycle = true;

		auto &modBuffer = vm->mem.modBuffer;
		auto &decBuffer = vm->mem.decBuffer;
		auto &cycleRoots = vm->cycleRoots;
		auto &toFinalize = vm->toFinalize;

		{ // block to control scope of old/newRoots
		auto &oldRoots = vm->roots[vm->oldRootIdx];
		auto &newRoots = vm->roots[1 - vm->oldRootIdx];

		assert(newRoots.isEmpty());
		assert(toFinalize.isEmpty());

		// ROOT PHASE. Go through roots, including stacks, and for each object reference, if it's in the nursery, move
		// it out. Regardless of whether it's a nursery object or not, put it in the new root buffer. debug(PHASES)
		// printf("ROOTS").flush;

		if(cycleType != GCCycleType_NoRoots)
		{
			visitRoots(vm, [&](GCObject* obj)
			{
				if(!GCOBJ_INRC(obj))
					vm->mem.makeRC(obj);

				newRoots.add(vm->mem, obj);
			});
		}

		// PROCESS MODIFIED BUFFER. Go through the modified buffer, unlogging each. For each object pointed to by an
		// object, if it's in the nursery, move it out. Increment all the reference counts (spurious increments to RC
		// space objects will be undone by the queued decrements created during the mutation phase by the write
		// barrier). debug(PHASES) printf("MODBUFFER").flush;
		while(!modBuffer.isEmpty())
		{
			auto obj = modBuffer.remove();
			assert(GCOBJ_COLOR(obj) != GCFlags_Green);

			// debug(INCDEC)
			// 	printf("let's look at {} {}", CrocValue.typeStrings[(cast(CrocBaseObject*)obj).mType], obj).flush;

			GCOBJ_UNLOG(obj);

			visitObj(obj, true, [&](GCObject* slot)
			{
				if(!GCOBJ_INRC(slot))
					vm->mem.makeRC(slot);

				// debug(INCDEC) printf("Visited {} through {}, rc will be {}", slot, obj, slot.refCount + 1).flush;

				rcIncrement(slot);
			});
		}

		// PROCESS OLD ROOT BUFFER. Move all objects from the old root buffer into the decrement buffer.
		// debug(PHASES) printf("OLDROOTS").flush;
		decBuffer.append(vm->mem, oldRoots);
		oldRoots.reset();

		// PROCESS NEW ROOT BUFFER. Go through the new root buffer, incrementing their RCs, and put them all in the old
		// root buffer.
		// debug(PHASES) printf("NEWROOTS").flush;
		newRoots.foreach([](GCObject* obj)
		{
			assert(GCOBJ_INRC(obj));
			rcIncrement(obj);
			// debug(INCDEC) printf("Incremented {}, rc is now {}", obj, obj.refCount).flush;
		});

		// heehee sneaky
		vm->oldRootIdx = 1 - vm->oldRootIdx;
		}

		// PROCESS DECREMENT BUFFER. Go through the decrement buffer, decrementing their RCs. If an RC hits 0, if it's
		// not finalizable, queue decrements for any RC objects it points to, and if it isn't logged for cycles and
		// didn't just move out of the nursery, free it. If it is finalizable, put it on the finalize list. If an RC is
		// nonzero after being decremented, mark it as a possible cycle root as follows: if its color is not purple,
		// color it purple, and if it's not already buffered, mark it buffered and put it in the possible cycle buffer.

		// debug(PHASES) printf("DECBUFFER").flush;

		while(!decBuffer.isEmpty())
		{
			auto obj = decBuffer.remove();
			assert(GCOBJ_INRC(obj));
			// debug(INCDEC) printf("About to decrement {}, rc will be {}", obj, obj.refCount - 1).flush;

			if(--obj->refCount == 0)
			{
				// Ref count hit 0. It's garbage.

				if(GCOBJ_FINALIZABLE(obj) && !GCOBJ_FINALIZED(obj))
				{
					GCOBJ_SETCOLOR(obj, GCFlags_Black);
					obj->refCount = 1;
					// debug(FINALIZE) printf("Putting {} on toFinalize", obj);
					toFinalize.add(vm->mem, obj);
				}
				else
				{
					visitObj(obj, false, [&](GCObject* slot)
					{
						decBuffer.add(vm->mem, slot);
					});

					if(GCOBJ_CYCLELOGGED(obj))
						GCOBJ_SETCOLOR(obj, GCFlags_Black);
					else if(!GCOBJ_JUSTMOVED(obj))
					{
						// If it just moved out of the nursery, we'll let the nursery phase sweep it up
						free(vm, obj);
					}
				}
			}
			else
			{
				// Ref count hasn't hit 0 yet, which means it's a potential cycle root (unless it's acyclic).
				// debug assert(obj.refCount != typeof(obj.refCount).max);

				auto color = GCOBJ_COLOR(obj);

				if(color != GCFlags_Green && color != GCFlags_Purple)
				{
					GCOBJ_SETCOLOR(obj, GCFlags_Purple);

					if(!GCOBJ_CYCLELOGGED(obj))
					{
						GCOBJ_CYCLELOG(obj);
						cycleRoots.add(vm->mem, obj);
					}
				}
			}
		}

		// NURSERY PHASE. Go through the nursery objects, clearing the "just moved" flag from living ones, and freeing
		// those that weren't moved out (so long as they're not logged by the cycle logger). Then empty the nursery
		// list.

		// debug(PHASES) printf("NURSERY").flush;

		vm->mem.nursery.foreach([&](GCObject* obj)
		{
			if(GCOBJ_INRC(obj) && obj->refCount > 0)
				GCOBJ_CLEARJUSTMOVED(obj);
			else
			{
				assert(!GCOBJ_FINALIZABLE(obj));

				if(!GCOBJ_CYCLELOGGED(obj)) // let the cycle collector sweep up otherwise
					free(vm, obj);
			}
		});

		vm->mem.clearNurserySpace();

		// CYCLE DETECT. Mark, scan, and collect as described in Bacon and Rajan.
		bool cycleCollect =
			(cycleRoots.length() * sizeof(GCObject*)) >= vm->mem.cycleMetadataLimit ||
			cycleType != GCCycleType_Normal ||
			vm->mem.cycleCollectCountdown == 0;

		if(cycleCollect)
		{
			vm->mem.cycleCollectCountdown = vm->mem.nextCycleCollect;
			// debug(BEGINEND) printf("CYCLES").flush;
			collectCycles(vm);
		}
		else
			vm->mem.cycleCollectCountdown--;

		assert(modBuffer.isEmpty());
		assert(decBuffer.isEmpty());
		assert(vm->roots[1 - vm->oldRootIdx].isEmpty());

#ifndef NDEBUG
		if(cycleCollect)
		{
			assert(cycleRoots.isEmpty());
			assert(vm->toFree.isEmpty());
		}
#endif

		vm->inGCCycle = false;

		// debug(BEGINEND) printf("======================= END {} =================================", counter).flush;
	}
}