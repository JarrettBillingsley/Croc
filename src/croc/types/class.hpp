#ifndef CROC_TYPES_CLASS_HPP
#define CROC_TYPES_CLASS_HPP

#include "croc/types.hpp"

namespace croc
{
	namespace classobj
	{
		Class* create(Allocator& alloc, String* name, Class* parent);
		Value* getField(Class* c, String* name);
		Value* getField(Class* c, String* name, Class*& owner);
		void setField(Allocator& alloc, Class* c, String* name, Value* value);
		void setFinalizer(Allocator& alloc, Class* c, Function* f);
		void setAllocator(Allocator& alloc, Class* c, Function* f);
		Namespace* fieldsOf(Class* c);
		bool next(Class* c, uword& idx, String**& key, Value*& val);
	}
}

#endif