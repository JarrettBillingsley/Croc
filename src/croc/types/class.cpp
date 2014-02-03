
#include "croc/base/hash.hpp"
#include "croc/base/memory.hpp"
#include "croc/base/writebarrier.hpp"
#include "croc/types.hpp"

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
	Class* Class::create(Memory& mem, String* name)
	{
		auto c = ALLOC_OBJ(mem, Class);
		c->type = CrocType_Class;
		c->name = name;
		return c;
	}

	Class::HashType::NodeType* Class::derive(Memory& mem, Class* c, Class* parent, const char*& which)
	{
		assert(parent->isFrozen);
		assert(parent->finalizer == nullptr);

		for(auto node: parent->fields)
		{
			if(!c->addField(mem, node->key, node->value, false))
			{
				which = "field";
				return node;
			}
		}

		for(auto node: parent->methods)
		{
			if(!c->addMethod(mem, node->key, node->value, false))
			{
				which = "method";
				return node;
			}
		}

		for(auto node: parent->hiddenFields)
		{
			if(!c->addHiddenField(mem, node->key, node->value))
			{
				which = "hidden field";
				return node;
			}
		}

		return nullptr;
	}

	void Class::free(Memory& mem, Class* c)
	{
		c->hiddenFields.clear(mem);
		c->fields.clear(mem);
		c->methods.clear(mem);
		FREE_OBJ(mem, Class, c);
	}

	void Class::freeze()
	{
		this->isFrozen = true;
	}

	// =================================================================================================================
	// Common stuff

#define MAKE_GET_MEMBER(funcName, memberName)\
	Class::HashType::NodeType* Class::funcName(String* name)\
	{\
		return this->memberName.lookupNode(name);\
	}

	void Class::setMember(Memory& mem, Class::HashType::NodeType* slot, Value value)
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

#define COMMON_ADD_MEMBER(memberName)\
		CONTAINER_WRITE_BARRIER(mem, this);\
		auto slot = this->memberName.insertNode(mem, name);\
		slot->value = value;\
		if(value.isGCObject())\
			SET_BOTH_MODIFIED(slot);\
		else\
			SET_KEY_MODIFIED(slot);\
\
		return true;

	bool Class::addHiddenField(Memory& mem, String* name, Value value)
	{
		assert(!this->isFrozen);

		if(this->hiddenFields.lookupNode(name))
			return false;

		COMMON_ADD_MEMBER(hiddenFields)
	}

#define MAKE_ADD_MEMBER(funcName, memberName, wantedSlot, otherSlot)\
	bool Class::funcName(Memory& mem, String* name, Value value, bool isOverride)\
	{\
		assert(!this->isFrozen);\
\
		auto fieldSlot = this->fields.lookupNode(name);\
		auto methodSlot = this->methods.lookupNode(name);\
\
		if(isOverride)\
		{\
			if(otherSlot != nullptr || wantedSlot == nullptr)\
				return false;\
			else\
			{\
				this->setMember(mem, wantedSlot, value);\
				return true;\
			}\
		}\
		else if(methodSlot != nullptr || fieldSlot != nullptr)\
			return false;\
\
		COMMON_ADD_MEMBER(memberName)\
	}

#define MAKE_REMOVE_MEMBER(funcName, memberName)\
	bool Class::funcName(Memory& mem, String* name)\
	{\
		assert(!this->isFrozen);\
\
		if(auto slot = this->memberName.lookupNode(name))\
		{\
			REMOVEKEYREF(mem, slot);\
			REMOVEVALUEREF(mem, slot);\
			this->memberName.remove(name);\
			return true;\
		}\
		else\
			return false;\
	}

#define MAKE_NEXT_MEMBER(funcName, memberName)\
	bool Class::funcName(uword& idx, String**& key, Value*& val)\
	{\
		return this->memberName.next(idx, key, val);\
	}

	// =================================================================================================================
	// Blerf

	MAKE_GET_MEMBER(getField, fields)
	MAKE_GET_MEMBER(getMethod, methods)
	MAKE_GET_MEMBER(getHiddenField, hiddenFields)

	MAKE_ADD_MEMBER(addField, fields, fieldSlot, methodSlot)
	MAKE_ADD_MEMBER(addMethod, methods, methodSlot, fieldSlot)

	MAKE_REMOVE_MEMBER(removeField, fields)
	MAKE_REMOVE_MEMBER(removeMethod, methods)
	MAKE_REMOVE_MEMBER(removeHiddenField, hiddenFields)

	bool Class::removeMember(Memory& mem, String* name)
	{
		return
			this->removeField(mem, name) ||
			this->removeMethod(mem, name);
	}

	MAKE_NEXT_MEMBER(nextField, fields)
	MAKE_NEXT_MEMBER(nextMethod, methods)
	MAKE_NEXT_MEMBER(nextHiddenField, hiddenFields)
}