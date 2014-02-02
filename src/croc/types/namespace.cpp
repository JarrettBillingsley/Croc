
#include "croc/base/writebarrier.hpp"
#include "croc/types/namespace.hpp"

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
	namespace namespaceobj
	{
		// Create a new namespace object.
		Namespace* create(Memory& mem, String* name, Namespace* parent)
		{
			auto ret = createPartial(mem);
			finishCreate(ret, name, parent);
			return ret;
		}

		// Partially construct a namespace. This is used by the serialization system.
		Namespace* createPartial(Memory& mem)
		{
			return ALLOC_OBJ(mem, Namespace);
		}

		// Finish constructing a namespace. Also used by serialization.
		void finishCreate(Namespace* ns, String* name, Namespace* parent)
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
		void free(Memory& mem, Namespace* ns)
		{
			ns->data.clear(mem);
			FREE_OBJ(mem, Namespace, ns);
		}

		// Get a pointer to the value of a key-value pair, or null if it doesn't exist.
		Value* get(Namespace* ns, String* key)
		{
			return ns->data.lookup(key);
		}

		// Sets a key-value pair.
		void set(Memory& mem, Namespace* ns, String* key, Value* value)
		{
			if(setIfExists(mem, ns, key, value))
				return;

			CONTAINER_WRITE_BARRIER(mem, ns);
			auto node = ns->data.insertNode(mem, key);
			node->value = *value;

			if(value->isGCObject())
				SET_BOTH_MODIFIED(node);
			else
				SET_KEY_MODIFIED(node);
		}

		bool setIfExists(Memory& mem, Namespace* ns, String* key, Value* value)
		{
			auto node = ns->data.lookupNode(key);

			if(node == nullptr)
				return false;

			if(node->value != *value)
			{
				REMOVEVALUEREF(mem, node);
				node->value = *value;

				if(value->isGCObject())
				{
					CONTAINER_WRITE_BARRIER(mem, ns);
					SET_VAL_MODIFIED(node);
				}
				else
					CLEAR_VAL_MODIFIED(node);
			}

			return true;
		}

		// Remove a key-value pair from the namespace.
		void remove(Memory& mem, Namespace* ns, String* key)
		{
			if(auto node = ns->data.lookupNode(key))
			{
				REMOVEKEYREF(mem, node);
				REMOVEVALUEREF(mem, node);
				ns->data.remove(key);
			}
		}

		// Clears all items from the namespace.
		void clear(Memory& mem, Namespace* ns)
		{
			for(auto node: ns->data)
			{
				REMOVEKEYREF(mem, node);
				REMOVEVALUEREF(mem, node);
			}

			ns->data.clear(mem);
		}

		// Returns `true` if the key exists in the table.
		bool contains(Namespace* ns, String* key)
		{
			return ns->data.lookup(key) != nullptr;
		}

		bool next(Namespace* ns, uword& idx, String**& key, Value*& val)
		{
			return ns->data.next(idx, key, val);
		}

		uword length(Namespace* ns)
		{
			return ns->data.length();
		}
	}
}