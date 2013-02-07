/******************************************************************************
This module contains the enumeration of Croc metamethods and some data about
them used by the interpreter.

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

module croc.base_metamethods;

package:

enum MM
{
	Cat,
	CatEq,
	Cat_r,

	Index,
	IndexAssign,
	Slice,
	SliceAssign,
	Field,
	FieldAssign,
	Length,
	LengthAssign,

	Cmp,
	Equals,

	Call,
	Method,

	Apply,
	In,
	ToString,
}

const char[][] MetaNames =
[
	MM.Cat:          "opCat",
	MM.CatEq:        "opCatAssign",
	MM.Cat_r:        "opCat_r",

	MM.Index:        "opIndex",
	MM.IndexAssign:  "opIndexAssign",
	MM.Slice:        "opSlice",
	MM.SliceAssign:  "opSliceAssign",
	MM.Field:        "opField",
	MM.FieldAssign:  "opFieldAssign",
	MM.Length:       "opLength",
	MM.LengthAssign: "opLengthAssign",

	MM.Cmp:          "opCmp",
	MM.Equals:       "opEquals",

	MM.Call:         "opCall",
	MM.Method:       "opMethod",

	MM.Apply:        "opApply",
	MM.In:           "opIn",
	MM.ToString:     "toString",
];