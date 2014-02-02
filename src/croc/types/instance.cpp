
#include "croc/base/writebarrier.hpp"
#include "croc/types/class.hpp"
#include "croc/types/instance.hpp"

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
	namespace instance
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

		Instance* create(Memory& mem, Class* parent)
		{
			assert(parent->isFrozen);
			auto i = createPartial(mem, InstanceExtraSize(parent), parent->finalizer != nullptr);
			finishCreate(i, parent);
			return i;
		}

		Instance* createPartial(Memory& mem, uword extraSize, bool finalizable)
		{
			if(finalizable)
				return ALLOC_OBJSZ_FINAL(mem, Instance, extraSize);
			else
				return ALLOC_OBJSZ(mem, Instance, extraSize);
		}

		bool finishCreate(Instance* i, Class* parent)
		{
			assert(parent->isFrozen);

			if(i->memSize != InstanceExtraSize(parent))
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

		Class::HashType::NodeType* getField(Instance* i, String* name)
		{
			return i->fields.lookupNode(name);
		}

		Class::HashType::NodeType* getMethod(Instance* i, String* name)
		{
			return classobj::getMethod(i->parent, name);
		}

		void setField(Memory& mem, Instance* i, Class::HashType::NodeType* slot, Value* value)
		{
			if(slot->value != *value)
			{
				REMOVEVALUEREF(mem, slot);
				slot->value = *value;

				if(value->isGCObject())
				{
					CONTAINER_WRITE_BARRIER(mem, i);
					SET_VAL_MODIFIED(slot);
				}
				else
					CLEAR_VAL_MODIFIED(slot);
			}
		}

		bool nextField(Instance* i, uword& idx, String**& key, Value*& val)
		{
			return i->fields.next(idx, key, val);
		}

		Class::HashType::NodeType* getHiddenField(Instance* i, String* name)
		{
			if(i->hiddenFields)
				return i->hiddenFields->lookupNode(name);
			else
				return nullptr;
		}

		bool nextHiddenField(Instance* i, uword& idx, String**& key, Value*& val)
		{
			if(i->hiddenFields)
				return i->hiddenFields->next(idx, key, val);
			else
				return false;
		}

		bool derivesFrom(Instance* i, Class* c)
		{
			return i->parent == c;
		}
	}
}
