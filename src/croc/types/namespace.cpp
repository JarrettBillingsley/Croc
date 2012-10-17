#include "croc/base/alloc.hpp"
// #include "croc/base/writebarrier.hpp"
#include "croc/base/hash.hpp"
#include "croc/types.hpp"

#define NS_REMOVEKEYREF(alloc, slot)\
	do {\
		if(!((slot)->modified & KeyModified))\
			(alloc).decBuffer.add((alloc), cast(GCObject*)(slot)->key);\
	} while(false)

#define NS_REMOVEVALUEREF(alloc, slot)\
	do {\
		if(!((slot)->modified & ValModified) && (slot)->value.isGCObject())\
			(alloc).decBuffer.add((alloc), (slot)->value.toGCObject());\
	} while(false)

namespace croc
{
	namespace namespaceobj
	{
		// Create a new namespace object.
		Namespace* create(Allocator& alloc, String* name, Namespace* parent = NULL)
		{
			assert(name !is NULL);

			Namespace* ns = alloc.allocate<Namespace>();
			ns->parent = parent;
			ns->name = name;
			return ns;
		}

		// Free a namespace object.
		void free(Allocator& alloc, Namespace* ns)
		{
			ns->data.clear(alloc);
			alloc.free(ns);
		}

		// Get a pointer to the value of a key-value pair, or NULL if it doesn't exist.
		Value* get(Namespace* ns, String* key)
		{
			return ns->data.lookup(key);
		}

		// Sets a key-value pair.
		void set(Allocator& alloc, Namespace* ns, String* key, Value* value)
		{
			if(setIfExists(alloc, ns, key, value))
				return;

			// CONTAINER_WRITE_BARRIER(alloc, ns);
			Namespace::Node* node = ns->data.insertNode(alloc, key);
			node->value = *value;
			node->modified |= KeyModified | (value->isGCObject() ? ValModified : 0);
		}

		bool setIfExists(Allocator& alloc, Namespace* ns, String* key, Value* value)
		{
			Namespace::Node* node = ns->data.lookupNode(key);

			if(node == NULL)
				return false;

			if(node->value != *value)
			{
				NS_REMOVEVALUEREF(alloc, node)
				node->value = *value;

				if(value->isGCObject())
				{
					// CONTAINER_WRITE_BARRIER(alloc, ns);
					node->modified |= ValModified;
				}
				else
					node->modified &= ~ValModified;
			}

			return true;
		}

		// Remove a key-value pair from the namespace.
		void remove(Allocator& alloc, Namespace* ns, String* key)
		{
			Namespace::Node* node = ns->data.lookupNode(key);

			if(node)
			{
				NS_REMOVEKEYREF(alloc, node);
				NS_REMOVEVALUEREF(alloc, node);
				ns->data.remove(key);
			}
		}

		// Clears all items from the namespace.
		void clear(Allocator& alloc, Namespace* ns)
		{
			uword i = 0;
			Namespace::Node* node;

			while(ns->data.nextNode(i, node))
			{
				NS_REMOVEKEYREF(alloc, node);
				NS_REMOVEVALUEREF(alloc, node);
			}

			ns->data.clear(alloc);
		}

		// Returns `true` if the key exists in the table.
		bool contains(Namespace* ns, String* key)
		{
			return ns->data.lookup(key) != NULL;
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