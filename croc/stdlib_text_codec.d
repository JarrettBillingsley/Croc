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

module croc.stdlib_text_codec;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.types;

// =====================================================================================================================
// Public
// =====================================================================================================================

public:

/**
*/
const char[] encodeIntoHeader =
`	auto str = checkStringParam(t, 1);
	auto strlen = cast(uword)len(t, 1);
	checkParam(t, 2, CrocValue.Type.Memblock);
	auto destlen = len(t, 2);
	auto start = checkIntParam(t, 3);
	auto errors = optStringParam(t, 4, "strict");

	if(start < 0) start += destlen;
	if(start < 0 || start > destlen)
		throwStdException(t, "BoundsException", "Invalid start index {} for memblock of length {}", start, destlen);`;

/**
*/
const char[] decodeRangeHeader =
`	checkParam(t, 1, CrocValue.Type.Memblock);
	auto data = getMemblockData(t, 1);
	auto lo = checkIntParam(t, 2);
	auto hi = checkIntParam(t, 3);
	auto errors = optStringParam(t, 4, "strict");

	if(lo < 0) lo += data.length;
	if(hi < 0) hi += data.length;

	if(lo < 0 || lo > hi || hi > data.length)
	{
		throwStdException(t, "BoundsException",
			"Invalid slice indices({} .. {}) for memblock of length {}", lo, hi, data.length);
	}

	auto mb = data[cast(uword)lo .. cast(uword)hi];`;