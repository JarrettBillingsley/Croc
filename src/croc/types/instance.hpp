#ifndef CROC_TYPES_INSTANCE_HPP
#define CROC_TYPES_INSTANCE_HPP

#include "croc/types.hpp"

namespace croc
{
	namespace instance
	{
		Instance* create(Memory& mem, Class* parent);
		Instance* createPartial(Memory& mem, uword size, bool finalizable);
		bool finishCreate(Instance* i, Class* parent);
		Class::HashType::NodeType* getField(Instance* i, String* name);
		Class::HashType::NodeType* getMethod(Instance* i, String* name);
		void setField(Memory& mem, Instance* i, Class::HashType::NodeType* slot, Value* value);
		bool nextField(Instance* i, uword& idx, String**& key, Value*& val);
		Class::HashType::NodeType* getHiddenField(Instance* i, String* name);
		bool nextHiddenField(Instance* i, uword& idx, String**& key, Value*& val);
		bool derivesFrom(Instance* i, Class* c);
	}
}

#endif