
#include "croc/base/writebarrier.hpp"

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
	Table* Table::create(Memory& mem, uword size)
	{
		auto t = ALLOC_OBJ(mem, Table);
		t->data.prealloc(mem, size);
		return t;
	}

	// Free a table object.
	void Table::free(Memory& mem, Table* t)
	{
		t->data.clear(mem);
		FREE_OBJ(mem, Table, t);
	}

	// Duplicate an existing table efficiently.
	Table* Table::dup(Memory& mem)
	{
		auto newTab = ALLOC_OBJ(mem, Table);
		newTab->data.prealloc(mem, this->data.capacity());

		assert(newTab->data.capacity() == this->data.capacity());
		this->data.dupInto(newTab->data);

		// At this point we've basically done the equivalent of inserting every key-value pair from this into t,
		// so we have to do run through the new table and do the "insert" write barrier stuff.

		for(auto node: newTab->data)
		{
			if(node->key.isGCObject() || node->value.isGCObject())
			{
				CONTAINER_WRITE_BARRIER(mem, newTab);

				if(node->key.isGCObject())
					SET_KEY_MODIFIED(node);

				if(node->value.isGCObject())
					SET_VAL_MODIFIED(node);
			}
		}

		return newTab;
	}

	void Table::idxa(Memory& mem, Value& key, Value& val)
	{
		auto node = this->data.lookupNode(key);

		if(node != nullptr)
		{
			if(val.type == CrocType_Null)
			{
				// Remove
				REMOVEKEYREF(mem, node);
				REMOVEVALUEREF(mem, node);
				this->data.remove(key);
			}
			else if(node->value != val)
			{
				// Update
				REMOVEVALUEREF(mem, node);
				node->value = val;

				if(val.isGCObject())
				{
					CONTAINER_WRITE_BARRIER(mem, this);
					SET_VAL_MODIFIED(node);
				}
				else
					CLEAR_VAL_MODIFIED(node);
			}
		}
		else if(val.type != CrocType_Null)
		{
			// Insert
			node = this->data.insertNode(mem, key);
			node->value = val;

			if(key.isGCObject() || val.isGCObject())
			{
				CONTAINER_WRITE_BARRIER(mem, this);

				if(key.isGCObject())
					SET_KEY_MODIFIED(node);

				if(val.isGCObject())
					SET_VAL_MODIFIED(node);
			}
		}

		// otherwise, do nothing (val is null and key doesn't exist)
	}

	// remove all key-value pairs from the table.
	void Table::clear(Memory& mem)
	{
		for(auto node: this->data)
		{
			REMOVEKEYREF(mem, node);
			REMOVEVALUEREF(mem, node);
		}

		this->data.clear(mem);
	}
}