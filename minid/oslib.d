/******************************************************************************
License:
Copyright (c) 2007 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module minid.oslib;

import minid.types;
import minid.utils;

import tango.stdc.stdlib;
import tango.stdc.stringz;
import tango.sys.Environment;

final class OSLib
{
static:
	public void init(MDContext context)
	{
		context.setModuleLoader("os", context.newClosure(function int(MDState s, uint numParams)
		{
			s.context.importModule("io");

			auto lib = s.getParam!(MDNamespace)(1);

			lib.addList
			(
				"system"d,       new MDClosure(lib, &system,     "os.system"),
				"getEnv"d,       new MDClosure(lib, &getEnv,     "os.getEnv")
			);

			return 0;
		}, "os"));

		context.importModule("os");
	}

	int system(MDState s, uint numParams)
	{
		if(numParams == 0)
			s.push(.system(null) ? true : false);
		else
			s.push(.system(toStringz(s.getParam!(char[])(0))));

		return 1;
	}

	int getEnv(MDState s, uint numParams)
	{
		if(numParams == 0)
			s.push(Environment.get());
		else
		{
			char[] def = null;
			
			if(numParams > 1)
				def = s.getParam!(char[])(1);

			char[] val = Environment.get(s.getParam!(char[])(0), def);

			if(val is null)
				s.pushNull();
			else
				s.push(val);
		}
		
		return 1;
	}
}