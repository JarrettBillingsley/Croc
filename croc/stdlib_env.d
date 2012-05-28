/******************************************************************************
This module contains the 'env' standard library.

License:
Copyright (c) 2012 Jarrett Billingsley

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

module croc.stdlib_env;

import tango.sys.Environment;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.stdlib_utils;
import croc.types;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initEnvLib(CrocThread* t)
{
	makeModule(t, "env", function uword(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);
		return 0;
	});

	importModule(t, "env");

	version(CrocBuiltinDocs)
	{
		scope doc = new CrocDoc(t, __FILE__);
		doc.push(Docs("module", "env",
		`This library holds functions for manipulating the program's environment variables.`));

		docFields(t, doc, _globalFuncDocs);

		doc.pop(-1);
	}

	pop(t);
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

const RegisterFunc[] _globalFuncs =
[
	{"getEnv",   &_getEnv,   maxParams: 2},
	{"putEnv",   &_putEnv,   maxParams: 2}
];

uword _getEnv(CrocThread* t)
{
	auto numParams = stackSize(t) - 1;

	if(numParams == 0)
	{
		newTable(t);

		foreach(k, v; Environment.get())
		{
			pushString(t, k);
			pushString(t, v);
			idxa(t, -3);
		}
	}
	else
	{
		auto val = Environment.get(checkStringParam(t, 1), optStringParam(t, 2, null));

		if(val is null)
			pushNull(t);
		else
			pushString(t, val);
	}

	return 1;
}

uword _putEnv(CrocThread* t)
{
	auto name = checkStringParam(t, 1);
	checkAnyParam(t, 2);

	if(isNull(t, 2))
		Environment.set(name, null);
	else if(isString(t, 2))
		Environment.set(name, getString(t, 2));
	else
		paramTypeError(t, 2, "null|string");

	return 0;
}

version(CrocBuiltinDocs) const Docs[] _globalFuncDocs =
[
];