/******************************************************************************
This module contains the 'path' standard library.

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

module croc.stdlib_path;

import tango.io.Path;
import tango.sys.Environment;

alias tango.io.Path.join Path_join;
alias tango.io.Path.parse Path_parse;
alias tango.io.Path.pop Path_pop;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_library;
import croc.types;

alias croc.api_stack.pop pop;

alias CrocDoc.Docs Docs;
alias CrocDoc.Param Param;
alias CrocDoc.Extra Extra;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

void initPathLib(CrocThread* t)
{
	makeModule(t, "path", function uword(CrocThread* t)
	{
		registerGlobals(t, _globalFuncs);
		return 0;
	});

	importModule(t, "path");

	version(CrocBuiltinDocs)
	{
		scope doc = new CrocDoc(t, __FILE__);
		doc.push(Docs("module", "path",
		`The path library contains functions for doing file path manipulation. It's a safe library, because it's just string
		manipulation.`));

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
	{"join",      &_join},
	{"dirName",   &_dirName,   maxParams: 1},
	{"name",      &_name,      maxParams: 1},
	{"extension", &_extension, maxParams: 1},
	{"fileName",  &_fileName,  maxParams: 1},
	{"parentDir", &_parentDir, maxParams: 1}
];

uword _join(CrocThread* t)
{
	checkAnyParam(t, 1);

	auto numParams = stackSize(t) - 1;
	char[][] tmp = allocArray!(char[])(t, numParams);

	scope(exit)
		freeArray(t, tmp);

	for(uword i = 1; i <= numParams; i++)
		tmp[i - 1] = checkStringParam(t, i);

	pushString(t, safeCode(t, "exceptions.ValueError", Path_join(tmp)));
	return 1;
}

uword _dirName(CrocThread* t)
{
	pushString(t, safeCode(t, "exceptions.ValueError", Path_parse(checkStringParam(t, 1))).path);
	return 1;
}

uword _name(CrocThread* t)
{
	pushString(t, safeCode(t, "exceptions.ValueError", Path_parse(checkStringParam(t, 1))).name);
	return 1;
}

uword _extension(CrocThread* t)
{
	pushString(t, safeCode(t, "exceptions.ValueError", Path_parse(checkStringParam(t, 1))).ext);
	return 1;
}

uword _fileName(CrocThread* t)
{
	pushString(t, safeCode(t, "exceptions.ValueError", Path_parse(checkStringParam(t, 1))).file);
	return 1;
}

uword _parentDir(CrocThread* t)
{
	auto p = optStringParam(t, 1, ".");

	if(p == ".")
		p = Environment.cwd();

	auto pp = safeCode(t, "exceptions.ValueError", Path_parse(p));

	if(pp.isAbsolute)
		pushString(t, safeCode(t, "exceptions.ValueError", Path_pop(p)));
	else
		pushString(t, safeCode(t, "exceptions.ValueError", Path_join(Environment.cwd(), p)));

	return 1;
}

version(CrocBuiltinDocs) const Docs[] _globalFuncDocs =
[
];