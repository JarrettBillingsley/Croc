
#include "croc/base/writebarrier.hpp"

#define REMOVEKEYREF(mem, slot)\
	do {\
	if(!IS_KEY_MODIFIED(slot))\
		(mem).decBuffer.add((mem), cast(GCObject*)(slot)->key);\
	} while(false)

#define REMOVEVALUEREF(mem, slot)\
	do {\
	if(!IS_VAL_MODIFIED(slot) && (slot)->value.isGCObject())\
		(mem).decBuffer.add((mem), (slot)->value.toGCObject());\
	} while(false)

#define REMOVEFROZENVALUEREF(mem, slot)\
	do {\
	if(!(slot).modified && (slot).value.isGCObject())\
		(mem).decBuffer.add((mem), (slot).value.toGCObject());\
	} while(false)

namespace croc
{
	Instance* Instance::create(Memory& mem, Class* parent)
	{
		assert(parent->isFrozen);
		auto i = createPartial(mem, parent->numInstanceFields * sizeof(Array::Slot), parent->finalizer != nullptr);
		auto b = finishCreate(i, parent);
		assert(b);
		return i;
	}

	Instance* Instance::createPartial(Memory& mem, uword extraSize, bool finalizable)
	{
		Instance* ret;
		if(finalizable)
			ret = ALLOC_OBJSZ_FINAL(mem, Instance, extraSize);
		else
			ret = ALLOC_OBJSZ(mem, Instance, extraSize);

		ret->type = CrocType_Instance;
		return ret;
	}

	bool Instance::finishCreate(Instance* i, Class* parent)
	{
		assert(parent->isFrozen);

		if(i->memSize != sizeof(Instance) + parent->numInstanceFields * sizeof(Array::Slot))
			return false;

		i->parent = parent;
		i->fields = &parent->fields;

		void* hiddenFieldsLoc = cast(void*)(i + 1);

		if(parent->frozenFields.length > 0)
		{
			auto instFields = DArray<Array::Slot>::n(cast(Array::Slot*)(i + 1), parent->frozenFields.length);
			instFields.slicea(parent->frozenFields);

			for(auto &slot: instFields)
				slot.modified = slot.value.isGCObject();

			hiddenFieldsLoc = cast(void*)(instFields.ptr + instFields.length);
		}

		if(parent->frozenHiddenFields.length > 0)
		{
			i->hiddenFieldsData = cast(Array::Slot*)hiddenFieldsLoc;

			auto instHiddenFields = DArray<Array::Slot>::n(cast(Array::Slot*)hiddenFieldsLoc,
				parent->frozenHiddenFields.length);
			instHiddenFields.slicea(parent->frozenHiddenFields);

			for(auto &slot: instHiddenFields)
				slot.modified = slot.value.isGCObject();
		}

		return true;
	}

	bool Instance::setField(Memory& mem, String* name, Value value)
	{
		if(auto slot = this->fields->lookupNode(name))
		{
			auto &fslot = (cast(Array::Slot*)(this + 1))[cast(uword)slot->value.mInt];

			if(fslot.value != value)
			{
				REMOVEFROZENVALUEREF(mem, fslot);
				fslot.value = value;

				if(value.isGCObject())
				{
					CONTAINER_WRITE_BARRIER(mem, this);
					fslot.modified = true;
				}
				else
					fslot.modified = false;
			}

			return true;
		}

		return false;
	}

	bool Instance::setHiddenField(Memory& mem, String* name, Value value)
	{
		if(this->hiddenFieldsData == nullptr)
			return false;

		if(auto slot = this->parent->hiddenFields.lookupNode(name))
		{
			auto &fslot = this->hiddenFieldsData[cast(uword)slot->value.mInt];

			if(fslot.value != value)
			{
				REMOVEFROZENVALUEREF(mem, fslot);
				fslot.value = value;

				if(value.isGCObject())
				{
					CONTAINER_WRITE_BARRIER(mem, this);
					fslot.modified = true;
				}
				else
					fslot.modified = false;
			}

			return true;
		}

		return false;
	}
}
