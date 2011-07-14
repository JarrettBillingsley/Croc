/******************************************************************************
This module contains the 'memblock' standard library.

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

module croc.stdlib_memblock;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.stdlib_utils;
import croc.types;
import croc.types_memblock;

struct MemblockLib
{
static:
	alias CrocMemblock.TypeCode TypeCode;

	void init(CrocThread* t)
	{
		makeModule(t, "memblock", function uword(CrocThread* t)
		{
			register(t, 2, "new", &memblock_new);

			newNamespace(t, "memblock");
				registerField(t, 1, "type",     &type);
				registerField(t, 0, "itemSize", &itemSize);
				registerField(t, 0, "toString", &toString);
				registerField(t, 0, "dup",      &mbDup);
				registerField(t, 0, "reverse",  &reverse);
				registerField(t, 0, "sort",     &sort);
			setTypeMT(t, CrocValue.Type.Memblock);

			return 0;
		});

		importModuleNoNS(t, "memblock");
	}

	uword memblock_new(CrocThread* t)
	{
		auto typeCode = checkStringParam(t, 1);
		auto size = optIntParam(t, 2, 0);

		if(size < 0 || size > uword.max)
			throwException(t, "Invalid size ({})", size);

		.newMemblock(t, typeCode, cast(uword)size);
		return 1;
	}

	uword type(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto numParams = stackSize(t) - 1;

		if(numParams == 0)
		{
			dup(t, 0);
			pushString(t, memblockType(t, -1));
			return 1;
		}
		else
		{
			auto type = checkStringParam(t, 1);
			dup(t, 0);
			setMemblockType(t, -1, type);
			return 0;
		}
	}

	uword itemSize(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		pushInt(t, getMemblock(t, 0).kind.itemSize);
		return 1;
	}

	uword toString(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		auto b = StrBuffer(t);
		pushFormat(t, "memblock({})[", mb.kind.name);
		b.addTop();

		if(mb.kind.code != CrocMemblock.TypeCode.v)
		{
			for(uword i = 0; i < mb.itemLength; i++)
			{
				if(i > 0)
					b.addString(", ");

				push(t, memblock.index(mb, i));
				pushToString(t, -1, true);
				insertAndPop(t, -2);
				b.addTop();
			}
		}

		b.addString("]");
		b.finish();
		return 1;
	}

	uword mbDup(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);
		
		newMemblock(t, mb.kind.name, mb.itemLength);
		auto n = getMemblock(t, -1);
		auto byteSize = mb.itemLength * mb.kind.itemSize;
		(cast(ubyte*)n.data)[0 .. byteSize] = (cast(ubyte*)mb.data)[0 .. byteSize];
		
		return 1;
	}
	
	uword reverse(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		switch(mb.kind.itemSize)
		{
			case 1: (cast(ubyte*)mb.data)[0 .. mb.itemLength].reverse;  break;
			case 2: (cast(ushort*)mb.data)[0 .. mb.itemLength].reverse; break;
			case 4: (cast(uint*)mb.data)[0 .. mb.itemLength].reverse;   break;
			case 8: (cast(ulong*)mb.data)[0 .. mb.itemLength].reverse;  break;

			default:
				throwException(t, "Not a horrible error, but somehow a memblock type must've been added that doesn't have 1-, 2-, 4-, or 8-byte elements, so I don't know how to reverse it.");
		}

		dup(t, 0);
		return 1;
	}

	uword sort(CrocThread* t)
	{
		checkParam(t, 0, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 0);

		switch(mb.kind.code)
		{
			case TypeCode.v:   throwException(t, "Attempting to sort a void memblock");
			case TypeCode.i8:  (cast(byte*)mb.data)[0 .. mb.itemLength].sort;   break;
			case TypeCode.i16: (cast(short*)mb.data)[0 .. mb.itemLength].sort;  break;
			case TypeCode.i32: (cast(int*)mb.data)[0 .. mb.itemLength].sort;    break;
			case TypeCode.i64: (cast(long*)mb.data)[0 .. mb.itemLength].sort;   break;
			case TypeCode.u8:  (cast(ubyte*)mb.data)[0 .. mb.itemLength].sort;  break;
			case TypeCode.u16: (cast(ushort*)mb.data)[0 .. mb.itemLength].sort; break;
			case TypeCode.u32: (cast(uint*)mb.data)[0 .. mb.itemLength].sort;   break;
			case TypeCode.u64: (cast(ulong*)mb.data)[0 .. mb.itemLength].sort;  break;
			case TypeCode.f32: (cast(float*)mb.data)[0 .. mb.itemLength].sort;  break;
			case TypeCode.f64: (cast(double*)mb.data)[0 .. mb.itemLength].sort; break;
			default: assert(false);
		}

		dup(t, 0);
		return 1;
	}
}