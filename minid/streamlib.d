/******************************************************************************
This module contains the 'stream' standard library.

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

module minid.streamlib;

import tango.core.Traits;
import tango.io.Buffer;
import tango.io.Console;
import tango.io.device.Conduit;
import tango.io.stream.Buffer;
import tango.io.stream.Format;
import tango.io.stream.Lines;

import minid.ex;
import minid.interpreter;
import minid.misc;
import minid.types;
import minid.vector;

struct StreamLib
{
static:
	public void init(MDThread* t)
	{
		pushGlobal(t, "modules");
		field(t, -1, "customLoaders");

		newFunction(t, function uword(MDThread* t, uword numParams)
		{
			InStreamObj.init(t);
			OutStreamObj.init(t);
			InoutStreamObj.init(t);

				pushGlobal(t, "InStream");
				pushNull(t);
				pushNativeObj(t, cast(Object)Cin.stream);
				pushBool(t, false);
				rawCall(t, -4, 1);
			newGlobal(t, "stdin");

				pushGlobal(t, "OutStream");
				pushNull(t);
				pushNativeObj(t, cast(Object)Cout.stream);
				pushBool(t, false);
				rawCall(t, -4, 1);
			newGlobal(t, "stdout");

				pushGlobal(t, "OutStream");
				pushNull(t);
				pushNativeObj(t, cast(Object)Cerr.stream);
				pushBool(t, false);
				rawCall(t, -4, 1);
			newGlobal(t, "stderr");

			return 0;
		}, "stream");

		fielda(t, -2, "stream");
		importModule(t, "stream");
		pop(t, 3);
	}
}

struct InStreamObj
{
static:
	enum Fields
	{
		buf,
		lines
	}

	align(1) struct Members
	{
		BufferInput buf;
		Lines!(char) lines;
		bool closed = true;
		bool closable = true;
	}

	public void init(MDThread* t)
	{
		CreateClass(t, "InStream", (CreateClass* c)
		{
			c.method("constructor", &constructor);
			c.method("readByte",    &readVal!(ubyte));
			c.method("readShort",   &readVal!(ushort));
			c.method("readInt",     &readVal!(int));
			c.method("readLong",    &readVal!(long));
			c.method("readFloat",   &readVal!(float));
			c.method("readDouble",  &readVal!(double));
			c.method("readChar",    &readVal!(char));
			c.method("readWChar",   &readVal!(wchar));
			c.method("readDChar",   &readVal!(dchar));
			c.method("readString",  &readString);
			c.method("readln",      &readln);
			c.method("readChars",   &readChars);
			c.method("readVector",  &readVector);
			c.method("skip",        &skip);
			c.method("seek",        &seek);
			c.method("position",    &position);
			c.method("size",        &size);
			c.method("close",       &close);
			c.method("isOpen",      &isOpen);

				newFunction(t, &iterator, "InStream.iterator");
			c.method("opApply", &opApply, 1);
		});

		newFunction(t, &allocator, "InStream.allocator");
		setAllocator(t, -2);
		
		newFunction(t, &finalizer, "InStream.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "InStream");
	}

	private Members* getThis(MDThread* t)
	{
		return checkInstParam!(Members)(t, 0, "InStream");
	}
	
	private Members* getOpenThis(MDThread* t)
	{
		auto ret = checkInstParam!(Members)(t, 0, "InStream");
		
		if(ret.closed)
			throwException(t, "Attempting to perform operation on a closed stream");
			
		return ret;
	}

	uword allocator(MDThread* t, uword numParams)
	{
		newInstance(t, 0, Fields.max + 1, Members.sizeof);
		*(cast(Members*)getExtraBytes(t, -1).ptr) = Members.init;

		dup(t);
		pushNull(t);
		rotateAll(t, 3);
		methodCall(t, 2, "constructor", 0);
		return 1;
	}

	uword finalizer(MDThread* t, uword numParams)
	{
		auto memb = cast(Members*)getExtraBytes(t, 0).ptr;

		if(memb.closable && !memb.closed)
		{
			memb.closed = true;
			safeCode(t, memb.buf.close());
		}

		return 0;
	}

	public uword constructor(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		if(memb.buf !is null)
			throwException(t, "Attempting to call constructor on an already-initialized InStream");

		checkParam(t, 1, MDValue.Type.NativeObj);
		auto input = cast(InputStream)getNativeObj(t, 1);

		if(input is null)
			throwException(t, "instances of InStream may only be created using instances of the Tango InputStream");
			
		memb.closable = optBoolParam(t, 2, true);
		
		if(auto b = cast(BufferInput)input)
			memb.buf = b;
		else
			memb.buf = new BufferInput(input);

		memb.lines = new Lines!(char)(memb.buf);
		memb.closed = false;

		pushNativeObj(t, memb.buf);    setExtraVal(t, 0, Fields.buf);
		pushNativeObj(t, memb.lines);  setExtraVal(t, 0, Fields.lines);

		return 0;
	}

	public uword readVal(T)(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		T val = void;
		
		safeCode(t, memb.buf.fill((cast(void*)&val)[0 .. T.sizeof], true));

		static if(isIntegerType!(T))
			pushInt(t, val);
		else static if(isRealType!(T))
			pushFloat(t, val);
		else static if(isCharType!(T))
			pushChar(t, val);
		else
			static assert(false);

		return 1;
	}

	public uword readString(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);

		safeCode(t,
		{
			uword length = void;

			safeCode(t, memb.buf.fill((cast(void*)&length)[0 .. length.sizeof], true));

			auto dat = t.vm.alloc.allocArray!(char)(length);

			scope(exit)
				t.vm.alloc.freeArray(dat);
				
			safeCode(t, memb.buf.fill(dat, true));

			pushString(t, dat);
		}());

		return 1;
	}

	public uword readln(MDThread* t, uword numParams)
	{
		auto ret = safeCode(t, getOpenThis(t).lines.next());

		if(ret.ptr is null)
			throwException(t, "Stream has no more data.");

		pushString(t, ret);
		return 1;
	}

	public uword readChars(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto num = checkIntParam(t, 1);

		if(num < 0 || num > uword.max)
			throwException(t, "Invalid number of characters ({})", num);

		safeCode(t,
		{
			auto dat = t.vm.alloc.allocArray!(char)(cast(uword)num);

			scope(exit)
				t.vm.alloc.freeArray(dat);
				
			safeCode(t, memb.buf.fill(dat, true));
			pushString(t, dat);
		}());

		return 1;
	}

	public uword readVector(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		checkAnyParam(t, 1);

		mdint size = void;
		VectorObj.Members* vecMemb = void;

		if(isString(t, 1))
		{
			auto type = getString(t, 1);
			size = checkIntParam(t, 2);

			pushGlobal(t, "Vector");
			pushNull(t);
			pushString(t, type);
			pushInt(t, size);
			rawCall(t, -4, 1);

			vecMemb = getMembers!(VectorObj.Members)(t, -1);
		}
		else
		{
			vecMemb = checkInstParam!(VectorObj.Members)(t, 1, "Vector");
			size = optIntParam(t, 2, vecMemb.length);

			if(size != vecMemb.length)
			{
				dup(t, 1);
				pushNull(t);
				pushInt(t, size);
				methodCall(t, -3, "opLengthAssign", 0);
			}

			dup(t, 1);
		}

		uword numBytes = cast(uword)size * vecMemb.type.itemSize;
		safeCode(t, memb.buf.fill(vecMemb.data[0 .. numBytes], true));
		return 1;
	}

	private uword iterator(MDThread* t, uword numParams)
	{
		auto index = checkIntParam(t, 1) + 1;
		auto line = safeCode(t, getOpenThis(t).lines.next());

		if(line.ptr is null)
			return 0;

		pushInt(t, index);
		pushString(t, line);
		return 2;
	}

	public uword opApply(MDThread* t, uword numParams)
	{
		checkInstParam(t, 0, "InStream");
		getUpval(t, 0);
		dup(t, 0);
		pushInt(t, 0);
		return 3;
	}

	public uword skip(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		safeCode(t, memb.buf.skip(checkIntParam(t, 1)));
		return 0;
	}

	public uword seek(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto pos = checkIntParam(t, 1);
		auto whence = checkCharParam(t, 2);

		if(whence == 'b')
			safeCode(t, memb.buf.seek(pos, IOStream.Anchor.Begin));
		else if(whence == 'c')
			safeCode(t, memb.buf.seek(pos, IOStream.Anchor.Current));
		else if(whence == 'e')
			safeCode(t, memb.buf.seek(pos, IOStream.Anchor.End));
		else
			throwException(t, "Invalid seek type '{}'", whence);

		dup(t, 0);
		return 1;
	}

	public uword position(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);

		if(numParams == 0)
		{
			pushInt(t, safeCode(t, cast(mdint)memb.buf.seek(0, IOStream.Anchor.Current)));
			return 1;
		}
		else
		{
			safeCode(t, memb.buf.seek(checkIntParam(t, 1), IOStream.Anchor.Begin));
			return 0;
		}
	}

	public uword size(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto pos = safeCode(t, memb.buf.seek(0, IOStream.Anchor.Current));
		auto ret = safeCode(t, memb.buf.seek(0, IOStream.Anchor.End));
		safeCode(t, memb.buf.seek(pos, IOStream.Anchor.Begin));
		pushInt(t, cast(mdint)ret);
		return 1;
	}

	public uword close(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);

		if(!memb.closable)
			throwException(t, "Attempting to close an unclosable stream");

		memb.closed = true;
		safeCode(t, memb.buf.close());
		
		return 0;
	}

	public uword isOpen(MDThread* t, uword numParams)
	{
		pushBool(t, !getThis(t).closed);
		return 1;
	}
}

struct OutStreamObj
{
static:
	enum Fields
	{
		buf,
		print
	}

	align(1) struct Members
	{
		BufferOutput buf;
		FormatOutput!(char) print;
		bool closed = true;
		bool closable = true;
	}

	public void init(MDThread* t)
	{
		CreateClass(t, "OutStream", (CreateClass* c)
		{
			c.method("constructor", &constructor);
			c.method("writeByte",   &writeVal!(ubyte));
			c.method("writeShort",  &writeVal!(ushort));
			c.method("writeInt",    &writeVal!(int));
			c.method("writeLong",   &writeVal!(long));
			c.method("writeFloat",  &writeVal!(float));
			c.method("writeDouble", &writeVal!(double));
			c.method("writeChar",   &writeVal!(char));
			c.method("writeWChar",  &writeVal!(wchar));
			c.method("writeDChar",  &writeVal!(dchar));
			c.method("writeString", &writeString);
			c.method("write",       &write);
			c.method("writeln",     &writeln);
			c.method("writef",      &writef);
			c.method("writefln",    &writefln);
			c.method("writeChars",  &writeChars);
			c.method("writeJSON",   &writeJSON);
			c.method("writeVector", &writeVector);
			c.method("flush",       &flush);
			c.method("copy",        &copy);

			c.method("seek",        &seek);
			c.method("position",    &position);
			c.method("size",        &size);
			c.method("close",       &close);
			c.method("isOpen",      &isOpen);
		});

		newFunction(t, &allocator, "OutStream.allocator");
		setAllocator(t, -2);

		newFunction(t, &finalizer, "OutStream.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "OutStream");
	}
	
	Members* getThis(MDThread* t)
	{
		return checkInstParam!(Members)(t, 0, "OutStream");
	}

	private Members* getOpenThis(MDThread* t)
	{
		auto ret = checkInstParam!(Members)(t, 0, "OutStream");
		
		if(ret.closed)
			throwException(t, "Attempting to perform operation on a closed stream");
			
		return ret;
	}

	uword allocator(MDThread* t, uword numParams)
	{
		newInstance(t, 0, Fields.max + 1, Members.sizeof);
		*(cast(Members*)getExtraBytes(t, -1).ptr) = Members.init;

		dup(t);
		pushNull(t);
		rotateAll(t, 3);
		methodCall(t, 2, "constructor", 0);
		return 1;
	}

	uword finalizer(MDThread* t, uword numParams)
	{
		auto memb = cast(Members*)getExtraBytes(t, 0).ptr;

		if(memb.closable && !memb.closed)
		{
			memb.closed = true;
			safeCode(t, memb.buf.flush());
			safeCode(t, memb.buf.close());
		}

		return 0;
	}

	public uword constructor(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		if(memb.buf !is null)
			throwException(t, "Attempting to call constructor on an already-initialized OutStream");

		checkParam(t, 1, MDValue.Type.NativeObj);
		auto output = cast(OutputStream)getNativeObj(t, 1);

		if(output is null)
			throwException(t, "instances of OutStream may only be created using instances of the Tango OutputStream");

		memb.closable = optBoolParam(t, 2, true);

		if(auto b = cast(BufferOutput)output)
			memb.buf = b;
		else
			memb.buf = new BufferOutput(output);

		memb.print = new FormatOutput!(char)(t.vm.formatter, memb.buf);
		memb.closed = false;

		pushNativeObj(t, memb.buf);    setExtraVal(t, 0, Fields.buf);
		pushNativeObj(t, memb.print);  setExtraVal(t, 0, Fields.print);

		return 0;
	}

	public uword writeVal(T)(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);

		static if(isIntegerType!(T))
			T val = cast(T)checkIntParam(t, 1);
		else static if(isRealType!(T))
			T val = cast(T)checkFloatParam(t, 1);
		else static if(isCharType!(T))
			T val = cast(T)checkCharParam(t, 1);
		else
			static assert(false);

		safeCode(t, memb.buf.append(&val, val.sizeof));
		dup(t, 0);
		return 1;
	}

	public uword writeString(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto str = checkStringParam(t, 1);

		safeCode(t,
		{
			auto len = str.length;
			memb.buf.append(&len, len.sizeof);
			memb.buf.append(str.ptr, str.length * char.sizeof);
		}());

		dup(t, 0);
		return 1;
	}

	public uword write(MDThread* t, uword numParams)
	{
		auto p = getOpenThis(t).print;

		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);
			safeCode(t, p.print(getString(t, -1)));
			pop(t);
		}

		dup(t, 0);
		return 1;
	}

	public uword writeln(MDThread* t, uword numParams)
	{
		auto p = getOpenThis(t).print;

		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);
			safeCode(t, p.print(getString(t, -1)));
			pop(t);
		}

		safeCode(t, p.newline());
		dup(t, 0);
		return 1;
	}

	public uword writef(MDThread* t, uword numParams)
	{
		auto p = getOpenThis(t).print;

		safeCode(t, formatImpl(t, numParams, (char[] s)
		{
			p.print(s);
			return s.length;
		}));

		dup(t, 0);
		return 1;
	}

	public uword writefln(MDThread* t, uword numParams)
	{
		auto p = getOpenThis(t).print;

		safeCode(t, formatImpl(t, numParams, (char[] s)
		{
			p.print(s);
			return s.length;
		}));

		safeCode(t, p.newline());
		dup(t, 0);
		return 1;
	}

	public uword writeChars(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto str = checkStringParam(t, 1);
		safeCode(t, memb.buf.append(str.ptr, str.length * char.sizeof));
		dup(t, 0);
		return 1;
	}

	public uword writeJSON(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		checkAnyParam(t, 1);
		auto pretty = optBoolParam(t, 2, false);
		toJSONImpl(t, 1, pretty, memb.print);
		dup(t, 0);
		return 1;
	}

	public uword writeVector(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto vecMemb = checkInstParam!(VectorObj.Members)(t, 1, "Vector");
		auto lo = optIntParam(t, 2, 0);
		auto hi = optIntParam(t, 3, vecMemb.length);

		if(lo < 0)
			lo += vecMemb.length;

		if(lo < 0 || lo > vecMemb.length)
			throwException(t, "Invalid low index: {} (vector length: {})", lo, vecMemb.length);

		if(hi < 0)
			hi += vecMemb.length;

		if(hi < lo || hi > vecMemb.length)
			throwException(t, "Invalid indices: {} .. {} (vector length: {})", lo, hi, vecMemb.length);

		auto isize = vecMemb.type.itemSize;
		memb.buf.append(vecMemb.data[cast(uword)lo * isize .. cast(uword)hi * isize]);
		dup(t, 0);
		return 1;
	}

	public uword flush(MDThread* t, uword numParams)
	{
		safeCode(t, getOpenThis(t).buf.flush());
		dup(t, 0);
		return 1;
	}

	public uword copy(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		checkInstParam(t, 1);

		InputStream stream;
		pushGlobal(t, "InStream");

		if(as(t, 1, -1))
		{
			pop(t);
			stream = getMembers!(InStreamObj.Members)(t, 1).buf;
		}
		else
		{
			pop(t);
			pushGlobal(t, "InoutStream");

			if(as(t, 1, -1))
			{
				pop(t);
				stream = getMembers!(InoutStreamObj.Members)(t, 1).buf;
			}
			else
				paramTypeError(t, 1, "InStream|InoutStream");
		}

		safeCode(t, memb.buf.copy(stream));
		dup(t, 0);
		return 1;
	}
	
	public uword seek(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto pos = checkIntParam(t, 1);
		auto whence = checkCharParam(t, 2);

		if(whence == 'b')
			safeCode(t, memb.buf.seek(pos, IOStream.Anchor.Begin));
		else if(whence == 'c')
			safeCode(t, memb.buf.seek(pos, IOStream.Anchor.Current));
		else if(whence == 'e')
			safeCode(t, memb.buf.seek(pos, IOStream.Anchor.End));
		else
			throwException(t, "Invalid seek type '{}'", whence);

		dup(t, 0);
		return 1;
	}

	public uword position(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);

		if(numParams == 0)
		{
			pushInt(t, safeCode(t, cast(mdint)memb.buf.seek(0, IOStream.Anchor.Current)));
			return 1;
		}
		else
		{
			safeCode(t, memb.buf.seek(checkIntParam(t, 1), IOStream.Anchor.Begin));
			return 0;
		}
	}

	public uword size(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto pos = safeCode(t, memb.buf.seek(0, IOStream.Anchor.Current));
		auto ret = safeCode(t, memb.buf.seek(0, IOStream.Anchor.End));
		safeCode(t, memb.buf.seek(pos, IOStream.Anchor.Begin));
		pushInt(t, cast(mdint)ret);
		return 1;
	}

	public uword close(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		
		if(!memb.closable)
			throwException(t, "Attempting to close an unclosable stream");

		memb.closed = true;
		safeCode(t, memb.buf.flush());
		safeCode(t, memb.buf.close());
		return 0;
	}

	public uword isOpen(MDThread* t, uword numParams)
	{
		pushBool(t, !getThis(t).closed);
		return 1;
	}
}

struct InoutStreamObj
{
static:
	enum Fields
	{
		buf,
		lines,
		print
	}

	align(1) struct Members
	{
		Buffer buf;
		Lines!(char) lines;
		FormatOutput!(char) print;
		bool closed = true;
		bool closable = true;
		bool dirty = false;
	}

	public void init(MDThread* t)
	{
		CreateClass(t, "Stream", (CreateClass* c)
		{
			c.method("constructor", &constructor);

			c.method("readByte",    &readVal!(ubyte));
			c.method("readShort",   &readVal!(ushort));
			c.method("readInt",     &readVal!(int));
			c.method("readLong",    &readVal!(long));
			c.method("readFloat",   &readVal!(float));
			c.method("readDouble",  &readVal!(double));
			c.method("readChar",    &readVal!(char));
			c.method("readWChar",   &readVal!(wchar));
			c.method("readDChar",   &readVal!(dchar));
			c.method("readString",  &readString);
			c.method("readln",      &readln);
			c.method("readChars",   &readChars);
			c.method("readVector",  &readVector);

				newFunction(t, &iterator, "InoutStream.iterator");
			c.method("opApply", &opApply, 1);

			c.method("writeByte",   &writeVal!(ubyte));
			c.method("writeShort",  &writeVal!(ushort));
			c.method("writeInt",    &writeVal!(int));
			c.method("writeLong",   &writeVal!(long));
			c.method("writeFloat",  &writeVal!(float));
			c.method("writeDouble", &writeVal!(double));
			c.method("writeChar",   &writeVal!(char));
			c.method("writeWChar",  &writeVal!(wchar));
			c.method("writeDChar",  &writeVal!(dchar));
			c.method("writeString", &writeString);
			c.method("write",       &write);
			c.method("writeln",     &writeln);
			c.method("writef",      &writef);
			c.method("writefln",    &writefln);
			c.method("writeChars",  &writeChars);
			c.method("writeJSON",   &writeJSON);
			c.method("writeVector", &writeVector);
			c.method("flush",       &flush);
			c.method("copy",        &copy);

			c.method("skip",        &skip);
			c.method("seek",        &seek);
			c.method("position",    &position);
			c.method("size",        &size);
			c.method("close",       &close);
			c.method("isOpen",      &isOpen);
		});

		newFunction(t, &allocator, "InoutStream.allocator");
		setAllocator(t, -2);

		newFunction(t, &finalizer, "InoutStream.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "InoutStream");
	}

	Members* getThis(MDThread* t)
	{
		return checkInstParam!(Members)(t, 0, "InoutStream");
	}

	private Members* getOpenThis(MDThread* t)
	{
		auto ret = checkInstParam!(Members)(t, 0, "InoutStream");
		
		if(ret.closed)
			throwException(t, "Attempting to perform operation on a closed stream");
			
		return ret;
	}

	uword allocator(MDThread* t, uword numParams)
	{
		newInstance(t, 0, Fields.max + 1, Members.sizeof);
		*(cast(Members*)getExtraBytes(t, -1).ptr) = Members.init;

		dup(t);
		pushNull(t);
		rotateAll(t, 3);
		methodCall(t, 2, "constructor", 0);
		return 1;
	}

	uword finalizer(MDThread* t, uword numParams)
	{
		auto memb = cast(Members*)getExtraBytes(t, 0).ptr;

		if(memb.closable && !memb.closed)
		{
			memb.closed = true;
			safeCode(t, memb.buf.flush());
			safeCode(t, memb.buf.close());
		}

		return 0;
	}

	public uword constructor(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		if(memb.buf !is null)
			throwException(t, "Attempting to call constructor on an already-initialized InoutStream");

		checkParam(t, 1, MDValue.Type.NativeObj);
		auto conduit = cast(IConduit)getNativeObj(t, 1);

		if(conduit is null)
			throwException(t, "instances of Stream may only be created using instances of Tango's IConduit");

		memb.closable = optBoolParam(t, 2, true);

		if(auto b = cast(Buffer)conduit)
			memb.buf = b;
		else
			memb.buf = new Buffer(conduit);

		memb.lines = new Lines!(char)(memb.buf);
		memb.print = new FormatOutput!(char)(t.vm.formatter, memb.buf);
		memb.closed = false;

		pushNativeObj(t, memb.buf);    setExtraVal(t, 0, Fields.buf);
		pushNativeObj(t, memb.lines);  setExtraVal(t, 0, Fields.lines);
		pushNativeObj(t, memb.print);  setExtraVal(t, 0, Fields.print);

		return 0;
	}

	void checkDirty(MDThread* t, Members* memb)
	{
		if(memb.dirty)
		{
			memb.dirty = false;
			safeCode(t, memb.buf.flush()); // may have to wrap this in a bullshit try-catch?
			safeCode(t, memb.buf.clear());
		}
	}

	public uword readVal(T)(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);

		T val = void;

		safeCode(t, memb.buf.readExact(&val, T.sizeof));

		static if(isIntegerType!(T))
			pushInt(t, val);
		else static if(isRealType!(T))
			pushFloat(t, val);
		else static if(isCharType!(T))
			pushChar(t, val);
		else
			static assert(false);

		return 1;
	}

	public uword readString(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);

		safeCode(t,
		{
			uword length = void;

			safeCode(t, memb.buf.readExact(&length, length.sizeof));

			auto dat = t.vm.alloc.allocArray!(char)(length);

			scope(exit)
				t.vm.alloc.freeArray(dat);
				
			safeCode(t, memb.buf.readExact(dat.ptr, dat.length * char.sizeof));

			pushString(t, dat);
		}());

		return 1;
	}

	public uword readln(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);
		auto ret = safeCode(t, memb.lines.next());

		if(ret.ptr is null)
			throwException(t, "Stream has no more data.");

		pushString(t, ret);
		return 1;
	}

	public uword readChars(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto num = checkIntParam(t, 1);

		if(num < 0 || num > uword.max)
			throwException(t, "Invalid number of characters ({})", num);

		checkDirty(t, memb);

		safeCode(t,
		{
			auto dat = t.vm.alloc.allocArray!(char)(cast(uword)num);

			scope(exit)
				t.vm.alloc.freeArray(dat);
				
			safeCode(t, memb.buf.readExact(dat.ptr, dat.length * char.sizeof));
			pushString(t, dat);
		}());

		return 1;
	}

	public uword readVector(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);

		checkAnyParam(t, 1);

		mdint size = void;
		VectorObj.Members* vecMemb = void;

		if(isString(t, 1))
		{
			auto type = getString(t, 1);
			size = checkIntParam(t, 2);

			pushGlobal(t, "Vector");
			pushNull(t);
			pushString(t, type);
			pushInt(t, size);
			rawCall(t, -4, 1);

			vecMemb = getMembers!(VectorObj.Members)(t, -1);
		}
		else
		{
			vecMemb = checkInstParam!(VectorObj.Members)(t, 1, "Vector");
			size = optIntParam(t, 2, vecMemb.length);

			if(size != vecMemb.length)
			{
				dup(t, 1);
				pushNull(t);
				pushInt(t, size);
				methodCall(t, -3, "opLengthAssign", 0);
			}

			dup(t, 1);
		}

		uword numBytes = cast(uword)size * vecMemb.type.itemSize;
		safeCode(t, memb.buf.readExact(vecMemb.data, numBytes));
		return 1;
	}

	private uword iterator(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);
		auto index = checkIntParam(t, 1) + 1;
		auto line = safeCode(t, memb.lines.next());

		if(line.ptr is null)
			return 0;

		pushInt(t, index);
		pushString(t, line);
		return 2;
	}

	public uword opApply(MDThread* t, uword numParams)
	{
		checkInstParam(t, 0, "InoutStream");
		getUpval(t, 0);
		dup(t, 0);
		pushInt(t, 0);
		return 3;
	}

	public uword writeVal(T)(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);

		static if(isIntegerType!(T))
			T val = cast(T)checkIntParam(t, 1);
		else static if(isRealType!(T))
			T val = cast(T)checkFloatParam(t, 1);
		else static if(isCharType!(T))
			T val = cast(T)checkCharParam(t, 1);
		else
			static assert(false);

		safeCode(t, memb.buf.append(&val, val.sizeof));
		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword writeString(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto str = checkStringParam(t, 1);

		safeCode(t,
		{
			auto len = str.length;
			memb.buf.append(&len, len.sizeof);
			memb.buf.append(str.ptr, str.length * char.sizeof);
		}());

		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword write(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto p = memb.print;

		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);
			safeCode(t, p.print(getString(t, -1)));
			pop(t);
		}

		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword writeln(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto p = memb.print;

		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);
			safeCode(t, p.print(getString(t, -1)));
			pop(t);
		}

		safeCode(t, p.newline());
		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword writef(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto p = memb.print;

		safeCode(t, formatImpl(t, numParams, (char[] s)
		{
			p.print(s);
			return s.length;
		}));

		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword writefln(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto p = memb.print;

		safeCode(t, formatImpl(t, numParams, (char[] s)
		{
			p.print(s);
			return s.length;
		}));

		safeCode(t, p.newline());
		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword writeChars(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto str = checkStringParam(t, 1);
		safeCode(t, memb.buf.append(str.ptr, str.length * char.sizeof));
		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword writeJSON(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		checkAnyParam(t, 1);
		auto pretty = optBoolParam(t, 2, false);
		toJSONImpl(t, 1, pretty, memb.print);
		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword writeVector(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		auto vecMemb = checkInstParam!(VectorObj.Members)(t, 1, "Vector");
		auto lo = optIntParam(t, 2, 0);
		auto hi = optIntParam(t, 3, vecMemb.length);

		if(lo < 0)
			lo += vecMemb.length;

		if(lo < 0 || lo > vecMemb.length)
			throwException(t, "Invalid low index: {} (vector length: {})", lo, vecMemb.length);

		if(hi < 0)
			hi += vecMemb.length;

		if(hi < lo || hi > vecMemb.length)
			throwException(t, "Invalid indices: {} .. {} (vector length: {})", lo, hi, vecMemb.length);

		auto isize = vecMemb.type.itemSize;
		memb.buf.append(vecMemb.data[cast(uword)lo * isize .. cast(uword)hi * isize]);
		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword flush(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		safeCode(t, memb.buf.flush());
		memb.dirty = false;
		dup(t, 0);
		return 1;
	}

	public uword copy(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		checkInstParam(t, 1);

		InputStream stream;
		pushGlobal(t, "InStream");

		if(as(t, 1, -1))
		{
			pop(t);
			stream = getMembers!(InStreamObj.Members)(t, 1).buf;
		}
		else
		{
			pop(t);
			pushGlobal(t, "InoutStream");

			if(as(t, 1, -1))
			{
				pop(t);
				stream = getMembers!(InoutStreamObj.Members)(t, 1).buf;
			}
			else
				paramTypeError(t, 1, "InStream|InoutStream");
		}

		safeCode(t, memb.buf.copy(stream));
		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword skip(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);
		safeCode(t, memb.buf.skip(checkIntParam(t, 1)));
		return 0;
	}

	public uword seek(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);
		auto pos = checkIntParam(t, 1);
		auto whence = checkCharParam(t, 2);

		if(whence == 'b')
			safeCode(t, memb.buf.seek(pos, IOStream.Anchor.Begin));
		else if(whence == 'c')
			safeCode(t, memb.buf.seek(pos, IOStream.Anchor.Current));
		else if(whence == 'e')
			safeCode(t, memb.buf.seek(pos, IOStream.Anchor.End));
		else
			throwException(t, "Invalid seek type '{}'", whence);

		dup(t, 0);
		return 1;
	}

	public uword position(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);

		if(numParams == 0)
		{
			pushInt(t, safeCode(t, cast(mdint)memb.buf.seek(0, IOStream.Anchor.Current)));
			return 1;
		}
		else
		{
			checkDirty(t, memb);
			safeCode(t, memb.buf.seek(checkIntParam(t, 1), IOStream.Anchor.Begin));
			return 0;
		}
	}

	public uword size(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);
		auto pos = safeCode(t, memb.buf.seek(0, IOStream.Anchor.Current));
		auto ret = safeCode(t, memb.buf.seek(0, IOStream.Anchor.End));
		safeCode(t, memb.buf.seek(pos, IOStream.Anchor.Begin));
		pushInt(t, cast(mdint)ret);
		return 1;
	}

	public uword close(MDThread* t, uword numParams)
	{
		auto memb = getOpenThis(t);

		if(!memb.closable)
			throwException(t, "Attempting to close an unclosable stream");

		memb.closed = true;
		safeCode(t, memb.buf.flush()); // maybe a bullshit try-catch here too
		safeCode(t, memb.buf.close());
		
		return 0;
	}

	public uword isOpen(MDThread* t, uword numParams)
	{
		pushBool(t, !getThis(t).closed);
		return 1;
	}
}