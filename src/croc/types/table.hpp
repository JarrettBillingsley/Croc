#ifndef CROC_TYPES_TABLE_HPP
#define CROC_TYPES_TABLE_HPP

#include "croc/types.hpp"

namespace croc
{
	namespace table
	{
		Table* create(Memory& mem, uword size = 0);
		Table* dup(Memory& mem, Table* src);
		void free(Memory& mem, Table* t);
		Value* get(Table* t, Value key);
		void idxa(Memory& mem, Table* t, Value& key, Value& val);
		void clear(Memory& mem, Table* t);
		bool contains(Table* t, Value& key);
		uword length(Table* t);
		bool next(Table* t, size_t& idx, Value*& key, Value*& val);
	}
}

#endif