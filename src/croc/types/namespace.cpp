
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
	// Create a new namespace object.
	Namespace* Namespace::create(Memory& mem, String* name, Namespace* parent)
	{
		auto ret = createPartial(mem);
		finishCreate(ret, name, parent);
		return ret;
	}

	// Partially construct a namespace. This is used by the serialization system.
	Namespace* Namespace::createPartial(Memory& mem)
	{
		return ALLOC_OBJ(mem, Namespace);
	}

	// Finish constructing a namespace. Also used by serialization.
	void Namespace::finishCreate(Namespace* ns, String* name, Namespace* parent)
	{
		assert(name != nullptr);
		ns->name = name;

		if(parent)
		{
			ns->parent = parent;
			auto root = parent;
			for( ; root->parent != nullptr; root = root->parent){}
			ns->root = root;
		}
	}

	// Free a namespace object.
	void Namespace::free(Memory& mem, Namespace* ns)
	{
		ns->data.clear(mem);
		FREE_OBJ(mem, Namespace, ns);
	}

	// Sets a key-value pair.
	void Namespace::set(Memory& mem, String* key, Value* value)
	{
		if(this->setIfExists(mem, key, value))
			return;

		CONTAINER_WRITE_BARRIER(mem, this);
		auto node = this->data.insertNode(mem, key);
		node->value = *value;

		if(value->isGCObject())
			SET_BOTH_MODIFIED(node);
		else
			SET_KEY_MODIFIED(node);
	}

	bool Namespace::setIfExists(Memory& mem, String* key, Value* value)
	{
		auto node = this->data.lookupNode(key);

		if(node == nullptr)
			return false;

		if(node->value != *value)
		{
			REMOVEVALUEREF(mem, node);
			node->value = *value;

			if(value->isGCObject())
			{
				CONTAINER_WRITE_BARRIER(mem, this);
				SET_VAL_MODIFIED(node);
			}
			else
				CLEAR_VAL_MODIFIED(node);
		}

		return true;
	}

	// Remove a key-value pair from the namespace.
	void Namespace::remove(Memory& mem, String* key)
	{
		if(auto node = this->data.lookupNode(key))
		{
			REMOVEKEYREF(mem, node);
			REMOVEVALUEREF(mem, node);
			this->data.remove(key);
		}
	}

	// Clears all items from the namespace.
	void Namespace::clear(Memory& mem)
	{
		for(auto node: this->data)
		{
			REMOVEKEYREF(mem, node);
			REMOVEVALUEREF(mem, node);
		}

		this->data.clear(mem);
	}
}