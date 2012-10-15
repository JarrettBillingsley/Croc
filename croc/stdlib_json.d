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

import tango.io.Console;
import tango.io.device.Array;
import tango.io.stream.Format;

import croc.api_interpreter;
import croc.ex;
import croc.ex_json;
import croc.ex_library;
import croc.stdlib_stream;
import croc.types;

struct JSONLib
{
static:
	void init(CrocThread* t)
	{
		makeModule(t, "json", function uword(CrocThread* t)
		{
			importModuleNoNS(t, "stream");

			newFunction(t, 1, &fromJSON, "fromJSON");   newGlobal(t, "fromJSON");
			newFunction(t, 2, &toJSON, "toJSON");       newGlobal(t, "toJSON");
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
// 		static scope class CrocHeapBuffer : Array
// 		{
// 			Allocator* alloc;
// 			uint increment;
//
// 			this(ref Allocator alloc)
// 			{
// 				super(null);
//
// 				this.alloc = &alloc;
// 				setContent(alloc.allocArray!(ubyte)(1024), 0);
// 				this.increment = 1024;
// 			}
//
// 			~this()
// 			{
// 				alloc.freeArray(data);
// 			}
//
// 			override uint fill(InputStream src)
// 			{
// 				if(writable <= increment / 8)
// 					expand(increment);
//
// 				return write(&src.read);
// 			}
//
// 			override uint expand(uint size)
// 			{
// 				if(size < increment)
// 					size = increment;
//
// 				dimension += size;
// 				alloc.resizeArray(data, dimension);
// 				return writable;
// 			}
// 		}

		checkAnyParam(t, 1);
		auto pretty = optBoolParam(t, 2, false);

		scope buf = new Array(256, 256);
		scope printer = new FormatOutput!(char)(t.vm.formatter, buf);

		.toJSON(t, 1, pretty, printer);

		pushString(t, safeCode(t, "exceptions.RuntimeException", cast(char[])buf.slice()));
		return 1;
	}

	uword writeJSON(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Instance);
		checkAnyParam(t, 2);
		auto pretty = optBoolParam(t, 3, false);
		FormatOutput!(char) printer = void;

		lookupCT!("stream.OutStream")(t);

		if(as(t, 1, -1))
			printer = getMembers!(OutStreamObj.Members)(t, 1).print;
		else
		{
			lookupCT!("stream.InoutStream")(t);

			if(as(t, 1, -1))
				printer = getMembers!(InoutStreamObj.Members)(t, 1).print;
			else
				paramTypeError(t, 1, "OutStream|InoutStream");
		}

		.toJSON(t, 2, pretty, printer);
		return 0;
	}

}