#ifndef CROC_TYPES_CLASS_HPP
#define CROC_TYPES_CLASS_HPP

#include "croc/types.hpp"

namespace croc
{
	namespace classobj
	{
		Class* create(Memory& mem, String* name);
		Class::HashType::NodeType* derive(Memory& mem, Class* c, Class* parent, const char*& which);
		void free(Memory& mem, Class* c);
		void freeze(Class* c);
		Class::HashType::NodeType* getField(Class* c, String* name);
		Class::HashType::NodeType* getMethod(Class* c, String* name);
		Class::HashType::NodeType* getHiddenField(Class* c, String* name);
		void setMember(Memory& mem, Class* c, Class::HashType::NodeType* slot, Value* value);
		bool addField(Memory& mem, Class* c, String* name, Value* value, bool isOverride);
		bool addMethod(Memory& mem, Class* c, String* name, Value* value, bool isOverride);
		bool addHiddenField(Memory& mem, Class* c, String* name, Value* value);
		bool removeField(Memory& mem, Class* c, String* name);
		bool removeMethod(Memory& mem, Class* c, String* name);
		bool removeHiddenMethod(Memory& mem, Class* c, String* name);
		bool removeMember(Memory& mem, Class* c, String* name);
		bool nextField(Class* c, uword& idx, String**& key, Value*& val);
		bool nextMethod(Class* c, uword& idx, String**& key, Value*& val);
		bool nextHiddenMethod(Class* c, uword& idx, String**& key, Value*& val);
	}
}

#endif