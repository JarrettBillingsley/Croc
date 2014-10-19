
#include "croc/base/hash.hpp"
#include "croc/base/memory.hpp"
#include "croc/base/writebarrier.hpp"
#include "croc/types/base.hpp"

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
	Class* Class::create(Memory& mem, String* name)
	{
		auto c = ALLOC_OBJ(mem, Class);
		c->type = CrocType_Class;
		c->name = name;
		return c;
	}

	Class::HashType::NodeType* Class::derive(Memory& mem, Class* c, Class* parent, const char*& which)
	{
		assert(!c->isFrozen);
		assert(parent->isFrozen);
		assert(parent->finalizer == nullptr);

		for(auto node: parent->methods)
		{
			if(!c->addMethod(mem, node->key, node->value, false))
			{
				which = "method";
				return node;
			}
		}

		for(auto node: parent->fields)
		{
			if(!c->addField(mem, node->key, parent->frozenFields[cast(uword)node->value.mInt].value, false))
			{
				which = "field";
				return node;
			}
		}

		for(auto node: parent->hiddenFields)
		{
			if(!c->addHiddenField(mem, node->key, parent->frozenHiddenFields[cast(uword)node->value.mInt].value))
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
		c->frozenFields.free(mem);
		c->frozenHiddenFields.free(mem);
		FREE_OBJ(mem, Class, c);
	}

	void Class::freeze(Memory& mem)
	{
		if(this->isFrozen)
			return;

		this->isFrozen = true;

		this->frozenFields = DArray<Array::Slot>::alloc(mem, this->fields.length());
		uword i = 0;
		for(auto n: this->fields)
		{
			auto &f = this->frozenFields[i];
			f.value = n->value;
			f.modified = IS_VAL_MODIFIED(n);
			CLEAR_VAL_MODIFIED(n);
			n->value = Value::from(cast(crocint)i);
			i++;
		}

		this->frozenHiddenFields = DArray<Array::Slot>::alloc(mem, this->hiddenFields.length());
		i = 0;
		for(auto n: this->hiddenFields)
		{
			auto &f = this->frozenHiddenFields[i];
			f.value = n->value;
			f.modified = IS_VAL_MODIFIED(n);
			CLEAR_VAL_MODIFIED(n);
			n->value = Value::from(cast(crocint)i);
			i++;
		}

		this->numInstanceFields = this->fields.length() + this->hiddenFields.length();
	}

	// =================================================================================================================
	// Get

	Value* Class::getMethod(String* name)
	{
		if(auto n = this->methods.lookupNode(name))
			return &n->value;
		else
			return nullptr;
	}

#define MAKE_GET_MEMBER(funcName, memberName, frozenMemberName)\
	Value* Class::funcName(String* name)\
	{\
		if(auto n = this->memberName.lookupNode(name))\
		{\
			if(this->isFrozen)\
				return &this->frozenMemberName[cast(uword)n->value.mInt].value;\
			else\
				return &n->value;\
		}\
\
		return nullptr;\
	}

	MAKE_GET_MEMBER(getField, fields, frozenFields)
	MAKE_GET_MEMBER(getHiddenField, hiddenFields, frozenHiddenFields)

	// =================================================================================================================
	// Set

	bool Class::setMethod(Memory& mem, String* name, Value value)
	{
		// assert(!this->isFrozen);

		if(auto slot = this->methods.lookupNode(name))
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

			return true;
		}

		return false;
	}

#define MAKE_SET_MEMBER(funcName, memberName, frozenMemberName)\
	bool Class::funcName(Memory& mem, String* name, Value value)\
	{\
		if(auto slot = this->memberName.lookupNode(name))\
		{\
			if(this->isFrozen)\
			{\
				auto &fslot = this->frozenMemberName[cast(uword)slot->value.mInt];\
\
				if(fslot.value != value)\
				{\
					REMOVEFROZENVALUEREF(mem, fslot);\
					fslot.value = value;\
\
					if(value.isGCObject())\
					{\
						CONTAINER_WRITE_BARRIER(mem, this);\
						fslot.modified = true;\
					}\
					else\
						fslot.modified = false;\
				}\
			}\
			else if(slot->value != value)\
			{\
				REMOVEVALUEREF(mem, slot);\
				slot->value = value;\
\
				if(value.isGCObject())\
				{\
					CONTAINER_WRITE_BARRIER(mem, this);\
					SET_VAL_MODIFIED(slot);\
				}\
				else\
					CLEAR_VAL_MODIFIED(slot);\
			}\
\
			return true;\
		}\
\
		return false;\
	}

	MAKE_SET_MEMBER(setField, fields, frozenFields)
	MAKE_SET_MEMBER(setHiddenField, hiddenFields, frozenHiddenFields)

	// =================================================================================================================
	// Add

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

#define MAKE_ADD_MEMBER(funcName, memberName, wantedSlot, otherSlot, setFunc)\
	bool Class::funcName(Memory& mem, String* name, Value value, bool isOverride)\
	{\
		auto fieldSlot = this->fields.lookupNode(name);\
		auto methodSlot = this->methods.lookupNode(name);\
\
		if(isOverride)\
		{\
			if(otherSlot != nullptr || wantedSlot == nullptr)\
				return false;\
			else\
			{\
				this->setFunc(mem, name, value);\
				return true;\
			}\
		}\
		else if(methodSlot != nullptr || fieldSlot != nullptr)\
			return false;\
\
		COMMON_ADD_MEMBER(memberName)\
	}

	MAKE_ADD_MEMBER(addField, fields, fieldSlot, methodSlot, setField)
	MAKE_ADD_MEMBER(addMethod, methods, methodSlot, fieldSlot, setMethod)

	// =================================================================================================================
	// Remove

#define MAKE_REMOVE_MEMBER(funcName, memberName)\
	bool Class::funcName(Memory& mem, String* name)\
	{\
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

	MAKE_REMOVE_MEMBER(removeField, fields)
	MAKE_REMOVE_MEMBER(removeMethod, methods)
	MAKE_REMOVE_MEMBER(removeHiddenField, hiddenFields)

	bool Class::removeMember(Memory& mem, String* name)
	{
		return
			this->removeField(mem, name) ||
			this->removeMethod(mem, name);
	}

	// =================================================================================================================
	// Next

	bool Class::nextMethod(uword& idx, String**& key, Value*& val)
	{
		return this->methods.next(idx, key, val);
	}

#define MAKE_NEXT_MEMBER(funcName, memberName, frozenMemberName)\
	bool Class::funcName(uword& idx, String**& key, Value*& val)\
	{\
		if(this->memberName.next(idx, key, val))\
		{\
			if(this->isFrozen)\
				val = &this->frozenMemberName[cast(uword)val->mInt].value;\
\
			return true;\
		}\
\
		return false;\
	}

	MAKE_NEXT_MEMBER(nextField, fields, frozenFields)
	MAKE_NEXT_MEMBER(nextHiddenField, hiddenFields, frozenHiddenFields)
}