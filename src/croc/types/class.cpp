
#include "croc/base/hash.hpp"
#include "croc/base/memory.hpp"
#include "croc/base/writebarrier.hpp"
#include "croc/types.hpp"
#include "croc/types/string.hpp"
#include "croc/types/class.hpp"

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
	namespace classobj
	{
		Class* create(Memory& mem, String* name)
		{
			auto c = ALLOC_OBJ(mem, Class);
			c->name = name;
			return c;
		}

		Class::HashType::NodeType* derive(Memory& mem, Class* c, Class* parent, const char*& which)
		{
			assert(parent->isFrozen);
			assert(parent->finalizer == nullptr);

			for(auto node: parent->fields)
			{
				if(!addField(mem, c, node->key, &node->value, false))
				{
					which = "field";
					return node;
				}
			}

			for(auto node: parent->methods)
			{
				if(!addMethod(mem, c, node->key, &node->value, false))
				{
					which = "method";
					return node;
				}
			}

			for(auto node: parent->hiddenFields)
			{
				if(!addHiddenField(mem, c, node->key, &node->value))
				{
					which = "hidden field";
					return node;
				}
			}

			return nullptr;
		}

		void free(Memory& mem, Class* c)
		{
			c->hiddenFields.clear(mem);
			c->fields.clear(mem);
			c->methods.clear(mem);
			FREE_OBJ(mem, Class, c);
		}

		void freeze(Class* c)
		{
			c->isFrozen = true;
		}

		// =================================================================================================================
		// Common stuff

	#define MAKE_GET_MEMBER(funcName, memberName)\
		Class::HashType::NodeType* funcName(Class* c, String* name)\
		{\
			return c->memberName.lookupNode(name);\
		}

		void setMember(Memory& mem, Class* c, Class::HashType::NodeType* slot, Value* value)
		{
			if(slot->value != *value)
			{
				REMOVEVALUEREF(mem, slot);
				slot->value = *value;

				if(value->isGCObject())
				{
					CONTAINER_WRITE_BARRIER(mem, c);
					SET_VAL_MODIFIED(slot);
				}
				else
					CLEAR_VAL_MODIFIED(slot);
			}
		}

	#define COMMON_ADD_MEMBER(memberName)\
			CONTAINER_WRITE_BARRIER(mem, c);\
			auto slot = c->memberName.insertNode(mem, name);\
			slot->value = *value;\
			if(value->isGCObject())\
				SET_BOTH_MODIFIED(slot);\
			else\
				SET_KEY_MODIFIED(slot);\
\
			return true;

		bool addHiddenField(Memory& mem, Class* c, String* name, Value* value)
		{
			assert(!c->isFrozen);

			if(c->hiddenFields.lookupNode(name))
				return false;

			COMMON_ADD_MEMBER(hiddenFields)
		}

#define MAKE_ADD_MEMBER(funcName, memberName, wantedSlot, otherSlot)\
		bool funcName(Memory& mem, Class* c, String* name, Value* value, bool isOverride)\
		{\
			assert(!c->isFrozen);\
\
			auto fieldSlot = c->fields.lookupNode(name);\
			auto methodSlot = c->methods.lookupNode(name);\
\
			if(isOverride)\
			{\
				if(otherSlot != nullptr || wantedSlot == nullptr)\
					return false;\
				else\
				{\
					setMember(mem, c, wantedSlot, value);\
					return true;\
				}\
			}\
			else if(methodSlot != nullptr || fieldSlot != nullptr)\
				return false;\
\
			COMMON_ADD_MEMBER(memberName)\
		}

	#define MAKE_REMOVE_MEMBER(funcName, memberName)\
		bool funcName(Memory& mem, Class* c, String* name)\
		{\
			assert(!c->isFrozen);\
\
			if(auto slot = c->memberName.lookupNode(name))\
			{\
				REMOVEKEYREF(mem, slot);\
				REMOVEVALUEREF(mem, slot);\
				c->memberName.remove(name);\
				return true;\
			}\
			else\
				return false;\
		}

	#define MAKE_NEXT_MEMBER(funcName, memberName)\
		bool funcName(Class* c, uword& idx, String**& key, Value*& val)\
		{\
			return c->memberName.next(idx, key, val);\
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

		bool removeMember(Memory& mem, Class* c, String* name)
		{
			return
				removeField(mem, c, name) ||
				removeMethod(mem, c, name);
		}

		MAKE_NEXT_MEMBER(nextField, fields)
		MAKE_NEXT_MEMBER(nextMethod, methods)
		MAKE_NEXT_MEMBER(nextHiddenField, hiddenFields)
	}
}