
#include "croc/base/writebarrier.hpp"
#include "croc/types/table.hpp"

#define REMOVEKEYREF(mem, slot)\
	do {\
	if(!IS_KEY_MODIFIED(slot) && (slot)->key.isGCObject())\
		(mem).decBuffer.add((mem), (slot)->key.toGCObject());\
	} while(false)

#define REMOVEVALUEREF(mem, slot)\
	do {\
	if(!IS_VAL_MODIFIED(slot) && (slot)->value.isGCObject())\
		(mem).decBuffer.add((mem), (slot)->value.toGCObject());\
	} while(false)

namespace croc
{
	namespace table
	{
		Table* create(Memory& mem, uword size)
		{
			auto t = ALLOC_OBJ(mem, Table);
			t->data.prealloc(mem, size);
			return t;
		}

		// Duplicate an existing table efficiently.
		Table* dup(Memory& mem, Table* src)
		{
			auto t = ALLOC_OBJ(mem, Table);
			t->data.prealloc(mem, src->data.capacity());

			assert(t->data.capacity() == src->data.capacity());
			src->data.dupInto(t->data);

			// At this point we've basically done the equivalent of inserting every key-value pair from src into t,
			// so we have to do run through the new table and do the "insert" write barrier stuff.

			for(auto node: t->data)
			{
				if(node->key.isGCObject() || node->value.isGCObject())
				{
					CONTAINER_WRITE_BARRIER(mem, t);

					if(node->key.isGCObject())
						SET_KEY_MODIFIED(node);

					if(node->value.isGCObject())
						SET_VAL_MODIFIED(node);
				}
			}

			return t;
		}

		// Free a table object.
		void free(Memory& mem, Table* t)
		{
			t->data.clear(mem);
			FREE_OBJ(mem, Table, t);
		}

		// Get a pointer to the value of a key-value pair, or null if it doesn't exist.
		Value* get(Table* t, Value key)
		{
			return t->data.lookup(key);
		}

		void idxa(Memory& mem, Table* t, Value& key, Value& val)
		{
			auto node = t->data.lookupNode(key);

			if(node != nullptr)
			{
				if(val.type == CrocType_Null)
				{
					// Remove
					REMOVEKEYREF(mem, node);
					REMOVEVALUEREF(mem, node);
					t->data.remove(key);
				}
				else if(node->value != val)
				{
					// Update
					REMOVEVALUEREF(mem, node);
					node->value = val;

					if(val.isGCObject())
					{
						CONTAINER_WRITE_BARRIER(mem, t);
						SET_VAL_MODIFIED(node);
					}
					else
						CLEAR_VAL_MODIFIED(node);
				}
			}
			else if(val.type != CrocType_Null)
			{
				// Insert
				node = t->data.insertNode(mem, key);
				node->value = val;

				if(key.isGCObject() || val.isGCObject())
				{
					CONTAINER_WRITE_BARRIER(mem, t);

					if(key.isGCObject())
						SET_KEY_MODIFIED(node);

					if(val.isGCObject())
						SET_VAL_MODIFIED(node);
				}
			}

			// otherwise, do nothing (val is null and key doesn't exist)
		}

		// remove all key-value pairs from the table.
		void clear(Memory& mem, Table* t)
		{
			for(auto node: t->data)
			{
				REMOVEKEYREF(mem, node);
				REMOVEVALUEREF(mem, node);
			}

			t->data.clear(mem);
		}

		// Returns `true` if the key exists in the table.
		bool contains(Table* t, Value& key)
		{
			return t->data.lookup(key) != nullptr;
		}

		// Get the number of key-value pairs in the table.
		uword length(Table* t)
		{
			return t->data.length();
		}

		bool next(Table* t, size_t& idx, Value*& key, Value*& val)
		{
			return t->data.next(idx, key, val);
		}
	}
}