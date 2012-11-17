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
struct RegisterCodec
{
	char[] className;
	char[] name;
	char[][] aliases;
	NativeFunc encodeInto;
	NativeFunc decodeRange;
	NativeFunc incrementalEncoder;
	NativeFunc incrementalDecoder;
}

/**
*/
word registerCodec(CrocThread* t, ref RegisterCodec codec)
{
	auto c = lookup(t, "text.TextCodec");
	newClass(t, -1, codec.className);
	insertAndPop(t, -2);

	pushString(t, codec.name);                                         addField(t, c, "name");
	newFunction(t, 4, codec.encodeInto, "encodeInto");                 addMethod(t, c, "encodeInto");
	newFunction(t, 4, codec.decodeRange, "decodeRange");               addMethod(t, c, "decodeRange");
	// newFunction(t, 4, codec.incrementalEncoder, "incrementalEncoder"); addMethod(t, c, "incrementalEncoder");
	// newFunction(t, 4, codec.incrementalDecoder, "incrementalDecoder"); addMethod(t, c, "incrementalDecoder");

	// text.registerCodec(name, text.CodecName())
	auto f = lookup(t, "text.registerCodec");
	pushNull(t);
	pushString(t, codec.name);
	dup(t, c);
	pushNull(t);
	rawCall(t, -2, 1);
	rawCall(t, f, 0);

	if(codec.aliases.length > 0)
	{
		// text.aliasCodec(name, aliases...)
		f = lookup(t, "text.aliasCodec");
		pushNull(t);
		pushString(t, codec.name);

		foreach(a; codec.aliases)
			pushString(t, a);

		rawCall(t, f, 0);
	}

	return stackSize(t) - 1;
}

/**
*/
uword _encodeInto(alias encodeFunc)(CrocThread* t)
{
	auto str = checkStringParam(t, 1);
	auto strlen = cast(uword)len(t, 1);
	checkParam(t, 2, CrocValue.Type.Memblock);
	auto destlen = len(t, 2);
	auto start = checkIntParam(t, 3);
	auto errors = optStringParam(t, 4, "strict");

	if(start < 0) start += destlen;
	if(start < 0 || start > destlen)
		throwStdException(t, "BoundsException", "Invalid start index {} for memblock of length {}", start, destlen);

	encodeFunc(t, 2, cast(uword)start, str, strlen, errors);
	dup(t, 2);
	return 1;
}

/**
*/
uword _decodeRange(alias decodeFunc)(CrocThread* t)
{
	checkParam(t, 1, CrocValue.Type.Memblock);
	auto src = getMemblockData(t, 1);
	auto lo = checkIntParam(t, 2);
	auto hi = checkIntParam(t, 3);
	auto errors = optStringParam(t, 4, "strict");

	if(lo < 0) lo += src.length;
	if(hi < 0) hi += src.length;

	if(lo < 0 || lo > hi || hi > src.length)
	{
		throwStdException(t, "BoundsException",
			"Invalid slice indices({} .. {}) for memblock of length {}", lo, hi, src.length);
	}

	auto s = StrBuffer(t);
	decodeFunc(t, s, src[cast(uword)lo .. cast(uword)hi], errors);
	s.finish();
	return 1;
}