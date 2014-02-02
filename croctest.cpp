#include <stdio.h>
#include <stdlib.h>
#include <typeinfo>

#include "croc/base/memory.hpp"
#include "croc/base/darray.hpp"
#include "croc/utils.hpp"
#include "croc/base/gcobject.hpp"
#include "croc/types.hpp"

using namespace croc;

void* DefaultMemFunc(void* ctx, void* p, size_t oldSize, size_t newSize)
{
	(void)ctx;
	(void)oldSize;

	if(newSize == 0)
	{
		free(p);
		return nullptr;
	}
	else
	{
		void* ret = cast(void*)realloc(p, newSize);
		assert(ret != nullptr);
		return ret;
	}
}

int main()
{
	Memory mem;
	mem.init(DefaultMemFunc, nullptr);

	Hash<int, int> h;
	h.init();

	for(int i = 1; i <= 10; i++)
	{
		auto n = h.insertNode(mem, i);
		n->value = i * 5;

		if(i & 1)
			SET_KEY_MODIFIED(n);
	}

	for(auto n: h.modifiedNodes())
		printf("h[%d (%d)] = %d (%d) \n", n->key, IS_KEY_MODIFIED(n) != 0, n->value, IS_VAL_MODIFIED(n) != 0);

	return 0;
}