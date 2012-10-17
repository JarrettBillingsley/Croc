#ifndef CROC_TYPES_NAMESPACE_HPP
#define CROC_TYPES_NAMESPACE_HPP

#include "croc/types.hpp"

namespace croc
{
	namespace namespaceobj
	{
		Namespace* create(Allocator& alloc, String* name, Namespace* parent = NULL);
		void free(Allocator& alloc, Namespace* ns);
		Value* get(Namespace* ns, String* key);
		void set(Allocator& alloc, Namespace* ns, String* key, Value* value);
		bool setIfExists(Allocator& alloc, Namespace* ns, String* key, Value* value);
		void remove(Allocator& alloc, Namespace* ns, String* key);
		void clear(Allocator& alloc, Namespace* ns);
		bool contains(Namespace* ns, String* key);
		bool next(Namespace* ns, uword& idx, String**& key, Value*& val);
		uword length(Namespace* ns);
	}
}

#endif