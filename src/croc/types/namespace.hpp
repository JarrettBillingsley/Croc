#ifndef CROC_TYPES_NAMESPACE_HPP
#define CROC_TYPES_NAMESPACE_HPP

#include "croc/types.hpp"

namespace croc
{
	namespace namespaceobj
	{
		Namespace* create(Memory& mem, String* name, Namespace* parent = nullptr);
		Namespace* createPartial(Memory& mem);
		void finishCreate(Namespace* ns, String* name, Namespace* parent);
		void free(Memory& mem, Namespace* ns);
		Value* get(Namespace* ns, String* key);
		void set(Memory& mem, Namespace* ns, String* key, Value* value);
		bool setIfExists(Memory& mem, Namespace* ns, String* key, Value* value);
		void remove(Memory& mem, Namespace* ns, String* key);
		void clear(Memory& mem, Namespace* ns);
		bool contains(Namespace* ns, String* key);
		bool next(Namespace* ns, uword& idx, String**& key, Value*& val);
		uword length(Namespace* ns);
	}
}

#endif