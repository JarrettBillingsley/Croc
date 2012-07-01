/******************************************************************************

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

module croc.stdlib_object;

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

void initObjectClass(CrocThread* t)
{
	version(CrocBuiltinDocs)
	{
		scope doc = new CrocDoc(t, __FILE__);
		docGlobals(t, doc, _docTables);
	}
}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

version(CrocBuiltinDocs) const Docs[] _docTables =
[
	{kind: "class", name: "Object", 
	extra: [Extra("protection", "global")],
	docs:
	`The root of the class hierarchy, \tt{Object}, is declared at global scope. It has no methods defined right
	now. It is the only class in Croc which has no base class (that is, "\tt{Object.super}" returns \tt{null}).`},
];