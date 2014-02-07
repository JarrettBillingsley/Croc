
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

namespace croc
{
	namespace
	{
		uword InstanceExtraSize(Class* parent)
		{
			auto ret = parent->fields.dataSize();

			if(parent->hiddenFields.length() > 0)
				ret += sizeof(Class::HashType) + parent->hiddenFields.dataSize();

			return ret;
		}
	}

	Instance* Instance::create(Memory& mem, Class* parent)
	{
		assert(parent->isFrozen);
		auto i = createPartial(mem, InstanceExtraSize(parent), parent->finalizer != nullptr);
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

		if(i->memSize != sizeof(Instance) + InstanceExtraSize(parent))
			return false;

		i->parent = parent;

		void* hiddenFieldsLoc = cast(void*)(i + 1);

		if(parent->fields.length() > 0)
		{
			auto instNodes = DArray<Class::HashType::NodeType>::n(
				cast(Class::HashType::NodeType*)(i + 1),
				parent->fields.capacity());

			parent->fields.dupInto(i->fields, instNodes);

			hiddenFieldsLoc = cast(void*)(instNodes.ptr + instNodes.length);

			for(auto node: i->fields)
			{
				if(node->value.isGCObject())
					SET_BOTH_MODIFIED(node);
				else
					SET_KEY_MODIFIED(node);
			}
		}

		if(parent->hiddenFields.length() > 0)
		{
			i->hiddenFields = cast(Class::HashType*)hiddenFieldsLoc;
			auto hiddenNodes = DArray<Class::HashType::NodeType>::n(
				cast(Class::HashType::NodeType*)(i->hiddenFields + 1),
				parent->hiddenFields.capacity());

			assert(cast(char*)(hiddenNodes.ptr + hiddenNodes.length) == (cast(char*)i + i->memSize));

			parent->hiddenFields.dupInto(*i->hiddenFields, hiddenNodes);

			for(auto node: *i->hiddenFields)
			{
				if(node->value.isGCObject())
					SET_BOTH_MODIFIED(node);
				else
					SET_KEY_MODIFIED(node);
			}
		}

		return true;
	}

	void Instance::setField(Memory& mem, Class::HashType::NodeType* slot, Value value)
	{
		if(slot->value != value)
		{
			REMOVEVALUEREF(mem, slot);
			slot->value = value;

			if(value.isGCObject())
			{
				CONTAINER_WRITE_BARRIER(mem, this);
				SET_VAL_MODIFIED(slot);
			}
			else
				CLEAR_VAL_MODIFIED(slot);
		}
	}
}
