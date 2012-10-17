#include "croc/base/alloc.hpp"
// #include "croc/base/writebarrier.hpp"
#include "croc/types/namespace.hpp"
#include "croc/types/string.hpp"
#include "croc/types.hpp"

namespace croc
{
	namespace classobj
	{
		Class* create(Allocator& alloc, String* name, Class* parent)
		{
			Class* c = alloc.allocate<Class>();
			c->name = name;
			c->parent = parent;

			if(parent)
			{
				c->allocator = parent->allocator;
				c->finalizer = parent->finalizer;
				// c->fields = namespace::create(alloc, name, parent->fields);
			}
			else
			{
				// c->fields = namespace::create(alloc, name);
			}

			// Note that even if this class has a finalizer copied from its parent, we can still change it -- once
			c->finalizerSet = false;
			return c;
		}

		Value* getField(Class* c, String* name)
		{
			Class* dummy;
			return getField(c, name, dummy);
		}

		Value* getField(Class* c, String* name, Class*& owner)
		{
			for(Class* obj = c; obj !is null; obj = obj.parent)
			{
				Value* ret = namespace::get(obj->fields, name);

				if(ret)
				{
					owner = obj;
					return ret;
				}
			}

			return NULL;
		}

		void setField(Allocator& alloc, Class* c, String* name, Value* value)
		{
			namespace::set(alloc, c->fields, name, value);
		}

		void setFinalizer(Allocator& alloc, Class* c, Function* f)
		{
			if(c->finalizer != f)
			{
				// WRITE_BARRIER(alloc, c);
			}

			c->finalizer = f;
		}

		void setAllocator(Allocator& alloc, Class* c, Function* f)
		{
			if(c->allocator != f)
			{
				// WRITE_BARRIER(alloc, c);
			}

			c->allocator = f;
		}

		Namespace* fieldsOf(Class* c)
		{
			return c->fields;
		}

		bool next(Class* c, uword& idx, String**& key, Value*& val)
		{
			return c->fields->data.next(idx, key, val);
		}
	}
}