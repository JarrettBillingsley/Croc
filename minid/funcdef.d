/******************************************************************************
License:
Copyright (c) 2008 Jarrett Billingsley

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

module minid.funcdef;

import tango.io.protocol.model.IReader;
import tango.io.protocol.model.IWriter;

import minid.alloc;
import minid.opcodes;
import minid.string;
import minid.types;
import minid.utils;

struct funcdef
{
static:
	// ================================================================================================================================================
	// Package
	// ================================================================================================================================================

	package MDFuncDef* create(ref Allocator alloc)
	{
		return alloc.allocate!(MDFuncDef);
	}

	package void free(ref Allocator alloc, MDFuncDef* fd)
	{
		alloc.freeArray(fd.paramMasks);
		alloc.freeArray(fd.innerFuncs);
		alloc.freeArray(fd.constants);
		alloc.freeArray(fd.code);

		foreach(ref st; fd.switchTables)
			st.offsets.clear(alloc);

		alloc.freeArray(fd.switchTables);
		alloc.freeArray(fd.lineInfo);
		alloc.freeArray(fd.upvalNames);
		alloc.freeArray(fd.locVarDescs);

		alloc.free(fd);
	}

	private void serialize(MDValue* v, IWriter s)
	{
		Serialize(s, v.type);

		switch(v.type)
		{
			case MDValue.Type.Null:
				break;

			case MDValue.Type.Bool:
				Serialize(s, v.mBool);
				break;

			case MDValue.Type.Int:
				Serialize(s, v.mInt);
				break;

			case MDValue.Type.Float:
				Serialize(s, v.mFloat);
				break;

			case MDValue.Type.Char:
				Serialize(s, v.mChar);
				break;

			case MDValue.Type.String:
				Serialize(s, v.mString.toString32());
				break;

			default:
				assert(false, "MDValue.serialize()");
		}
	}
	
	private void deserialize(MDVM* vm, MDValue* v, IReader s)
	{
		Deserialize(s, v.type);

		switch(v.type)
		{
			case MDValue.Type.Null:
				break;

			case MDValue.Type.Bool:
				Deserialize(s, v.mBool);
				break;

			case MDValue.Type.Int:
				int x;
				Deserialize(s, x);
				v.mInt = x;
				break;

			case MDValue.Type.Float:
				Deserialize(s, v.mFloat);
				break;

			case MDValue.Type.Char:
				Deserialize(s, v.mChar);
				break;

			case MDValue.Type.String:
				// TODO: change this
				dchar[] str;
				Deserialize(s, str);
				v.mString = string.create(vm, str);
				break;

			default:
				assert(false, "MDValue.deserialize()");
		}
	}

	package void serialize(MDFuncDef* fd, IWriter s)
	{
		Serialize(s, fd.location.line);
		Serialize(s, fd.location.column);
		Serialize(s, fd.location.fileName.toString32());

		Serialize(s, fd.isVararg);
		Serialize(s, fd.name.toString32());
		Serialize(s, fd.numParams);
		Serialize(s, fd.paramMasks);
		Serialize(s, fd.numUpvals);
		Serialize(s, fd.stackSize);
		
		Serialize(s, fd.constants.length);

		foreach(ref c; fd.constants)
			serialize(&c, s);

		Serialize(s, fd.code);
		// TODO: isPure
		Serialize(s, fd.lineInfo);

		Serialize(s, fd.upvalNames.length);

		foreach(name; fd.upvalNames)
			Serialize(s, name.toString32());

		Serialize(s, fd.locVarDescs.length);

		foreach(ref desc; fd.locVarDescs)
		{
			Serialize(s, desc.name.toString32());
			Serialize(s, desc.pcStart);
			Serialize(s, desc.pcEnd);
			Serialize(s, desc.reg);
		}

		Serialize(s, fd.switchTables.length);

		foreach(ref st; fd.switchTables)
		{
			Serialize(s, st.offsets.length);

			foreach(ref k, v; st.offsets)
			{
				serialize(&k, s);
				Serialize(s, v);
			}

			Serialize(s, st.defaultOffset);
		}
		
		Serialize(s, fd.innerFuncs.length);
		
		foreach(inner; fd.innerFuncs)
			funcdef.serialize(inner, s);
	}

	package MDFuncDef* deserialize(MDVM* vm, IReader s)
	{
		auto ret = funcdef.create(vm.alloc);

		Deserialize(s, ret.location.line);
		Deserialize(s, ret.location.column);

		// TODO: change this
		dchar[] str;
		Deserialize(s, str);
		ret.location.fileName = string.create(vm, str);

		Deserialize(s, ret.isVararg);

		// TODO: and this
		Deserialize(s, str);
		ret.name = string.create(vm, str);

		Deserialize(s, ret.numParams);
		
		// TODO: and this
		uword len;
		Deserialize(s, len);
		ret.paramMasks = vm.alloc.allocArray!(uword)(len);
		s.buffer.readExact(ret.paramMasks.ptr, ret.paramMasks.length * uword.sizeof);

		Deserialize(s, ret.numUpvals);
		Deserialize(s, ret.stackSize);

		Deserialize(s, len);
		ret.constants = vm.alloc.allocArray!(MDValue)(len);

		foreach(ref c; ret.constants)
			deserialize(vm, &c, s);

		// TODO: and this
		Deserialize(s, len);
		ret.code = vm.alloc.allocArray!(Instruction)(len);
		s.buffer.readExact(ret.code.ptr, ret.code.length * Instruction.sizeof);

		// TODO: isPure

		Deserialize(s, len);
		ret.lineInfo = vm.alloc.allocArray!(uword)(len);
		s.buffer.readExact(ret.lineInfo.ptr, ret.lineInfo.length * uword.sizeof);

		// TODO: and this
		Deserialize(s, len);
		ret.upvalNames = vm.alloc.allocArray!(MDString*)(len);

		foreach(ref name; ret.upvalNames)
		{
			// TODO: and this
			Deserialize(s, str);
			name = string.create(vm, str);
		}
		
		// TODO: and this
		Deserialize(s, len);
		ret.locVarDescs = vm.alloc.allocArray!(MDFuncDef.LocVarDesc)(len);

		foreach(ref desc; ret.locVarDescs)
		{
			// TODO: and this
			Deserialize(s, str);
			desc.name = string.create(vm, str);

			Deserialize(s, desc.pcStart);
			Deserialize(s, desc.pcEnd);
			Deserialize(s, desc.reg);
		}

		Deserialize(s, len);
		ret.switchTables = vm.alloc.allocArray!(MDFuncDef.SwitchTable)(len);

		foreach(ref st; ret.switchTables)
		{
			Deserialize(s, len);

			for(uword i = 0; i < len; i++)
			{
				MDValue key;
				word value;

				deserialize(vm, &key, s);
				Deserialize(s, value);

				*st.offsets.insert(vm.alloc, key) = value;
			}

			Deserialize(s, st.defaultOffset);
		}

		// TODO: aaaaand this.
		Deserialize(s, len);
		ret.innerFuncs = vm.alloc.allocArray!(MDFuncDef*)(len);

		foreach(ref inner; ret.innerFuncs)
			inner = funcdef.deserialize(vm, s);

		return ret;
	}
}