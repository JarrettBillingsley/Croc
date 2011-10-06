module newsocket;

import croc.api;
import croc.ex;
import croc.types;

struct SocketLib
{
static:
	struct Members
	{
			
	}

	public void init(CrocThread* t)
	{
		makeModule(t, "socket", function uword(CrocThread* t)
		{
			importModuleNoNS(t, "streams");

			CreateClass(t, "Socket", "streams.Stream", (CreateClass* c)
			{
				c.allocator("allocator", &BasicClassAllocator!(0, Members));
				c.finalizer("finalizer", &finalizer);

				c.method("constructor", &constructor);
			});

			newGlobal(t, "Socket");

			return 0;
		});

		importModuleNoNS(t, "socket");
	}
	
	uword finalizer(CrocThread* t)
	{
		return 0;
	}
	
	uword constructor(CrocThread* t)
	{
		return 0;
	}
}