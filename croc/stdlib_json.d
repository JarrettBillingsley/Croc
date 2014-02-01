/******************************************************************************
This module contains the JSON standard library module, used to read and write
JSON objects.

License:
Copyright (c) 2011 Jarrett Billingsley

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

module croc.stdlib_json;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_json;
import croc.ex_library;
import croc.types;

struct JSONLib
{
static:
	void init(CrocThread* t)
	{
		makeModule(t, "json", function uword(CrocThread* t)
		{
			newFunction(t, 1, &fromJSON,  "fromJSON");  newGlobal(t, "fromJSON");
			newFunction(t, 2, &toJSON,    "toJSON");    newGlobal(t, "toJSON");
			newFunction(t, 3, &writeJSON, "writeJSON"); newGlobal(t, "writeJSON");

			return 0;
		});

		importModuleNoNS(t, "json");
	}

	uword fromJSON(CrocThread* t)
	{
		.fromJSON(t, checkStringParam(t, 1));
		return 1;
	}

	uword toJSON(CrocThread* t)
	{
		checkAnyParam(t, 1);
		auto pretty = optBoolParam(t, 2, false);

		auto buf = StrBuffer(t);

		void output(char[] s) { buf.addString(s); }
		void newline() { buf.addString("\n"); }

		.toJSON(t, 1, pretty, &output, &newline);

		buf.finish();
		return 1;
	}

	uword writeJSON(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Instance);
		checkAnyParam(t, 2);
		auto pretty = optBoolParam(t, 3, false);

		lookup(t, "stream.TextWriter");

		if(!instanceOf(t, 1, -1))
			paramTypeError(t, 1, "stream.TextWriter");

		pop(t);

		void output(char[] s)
		{
			dup(t, 1);
			pushNull(t);
			pushString(t, s);
			methodCall(t, -3, "write", 0);
		}

		void newline()
		{
			dup(t, 1);
			pushNull(t);
			methodCall(t, -2, "writeln", 0);
		}

		.toJSON(t, 2, pretty, &output, &newline);
		return 0;
	}

}