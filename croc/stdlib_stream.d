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

module croc.stdlib_stream;

import tango.core.Traits;
import tango.io.Console;
import tango.io.device.Conduit;
import tango.io.stream.Format;
import tango.io.stream.Lines;
import tango.math.Math;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_format;
import croc.types;
import croc.vm;

// TODO: abstract out common functionality between the three types of streams

struct StreamLib
{
static:
	public void init(CrocThread* t)
	{
		makeModule(t, "stream", function uword(CrocThread* t)
		{
			InStreamObj.init(t);
			OutStreamObj.init(t);
			InoutStreamObj.init(t);
			MemInStreamObj.init(t);
			MemOutStreamObj.init(t);
			MemInoutStreamObj.init(t);

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
		});

		importModuleNoNS(t, "stream");
	}
}

struct InStreamObj
{
static:
	enum Fields
	{
		stream,
		lines
	}

	align(1) struct Members
	{
		InputStream stream;
		Lines!(char) lines;
		bool closed = true;
		bool closable = true;
	}
	
	public InputStream getStream(CrocThread* t, word idx)
	{
		return checkInstParam!(Members)(t, idx, "stream.InStream").stream;
	}

	public InputStream getOpenStream(CrocThread* t, word idx)
	{
		auto ret = checkInstParam!(Members)(t, idx, "stream.InStream");

		if(ret.closed)
			throwStdException(t, "ValueException", "Attempting to perform operation on a closed stream");

		return ret.stream;
	}

	public void init(CrocThread* t)
	{
		CreateClass(t, "InStream", (CreateClass* c)
		{
			c.method("constructor",  2, &constructor);
			c.method("readByte",     0, &readVal!(byte));
			c.method("readUByte",    0, &readVal!(ubyte));
			c.method("readShort",    0, &readVal!(short));
			c.method("readUShort",   0, &readVal!(ushort));
			c.method("readInt",      0, &readVal!(int));
			c.method("readUInt",     0, &readVal!(uint));
			c.method("readLong",     0, &readVal!(long));
			c.method("readULong",    0, &readVal!(ulong));
			c.method("readFloat",    0, &readVal!(float));
			c.method("readDouble",   0, &readVal!(double));
			c.method("readChar",     0, &readVal!(char));
			c.method("readWChar",    0, &readVal!(wchar));
			c.method("readDChar",    0, &readVal!(dchar));
			c.method("readString",   0, &readString);
			c.method("readln",       0, &readln);
			c.method("readChars",    1, &readChars);
			c.method("readMemblock", 2, &readMemblock);
			c.method("rawRead",      2, &rawRead);
			c.method("skip",         1, &skip);

			c.method("seek",         2, &seek);
			c.method("position",     1, &position);
			c.method("size",         0, &size);
			c.method("close",        0, &close);
			c.method("isOpen",       0, &isOpen);

				newFunction(t, &iterator, "InStream.iterator");
			c.method("opApply", 1, &opApply, 1);
		});

		newFunction(t, &allocator, "InStream.allocator");
		setAllocator(t, -2);

		newFunction(t, &finalizer, "InStream.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "InStream");
	}

	private Members* getThis(CrocThread* t)
	{
		return checkInstParam!(Members)(t, 0, "InStream");
	}

	private Members* getOpenThis(CrocThread* t)
	{
		auto ret = checkInstParam!(Members)(t, 0, "InStream");
		
		if(ret.closed)
			throwStdException(t, "ValueException", "Attempting to perform operation on a closed stream");
			
		return ret;
	}
	
	private void readExact(CrocThread* t, Members* memb, void* dest, uword size)
	{
		while(size > 0)
		{
			auto numRead = memb.stream.read(dest[0 .. size]);

			if(numRead == IOStream.Eof)
				throwStdException(t, "IOException", "End-of-flow encountered while reading");

			size -= numRead;
			dest += numRead;
		}
	}

	private uword readAtMost(CrocThread* t, Members* memb, void* dest, uword size)
	{
		auto initial = size;

		while(size > 0)
		{
			auto numRead = memb.stream.read(dest[0 .. size]);

			if(numRead == IOStream.Eof)
				break;
			else if(numRead < size)
			{
				size -= numRead;
				break;
			}

			size -= numRead;
			dest += numRead;
		}

		return initial - size;
	}

	uword allocator(CrocThread* t)
	{
		newInstance(t, 0, Fields.max + 1, Members.sizeof);
		*(cast(Members*)getExtraBytes(t, -1).ptr) = Members.init;

		dup(t);
		pushNull(t);
		rotateAll(t, 3);
		methodCall(t, 2, "constructor", 0);
		return 1;
	}

	uword finalizer(CrocThread* t)
	{
		auto memb = cast(Members*)getExtraBytes(t, 0).ptr;

		if(memb.closable && !memb.closed)
		{
			memb.closed = true;
			safeCode(t, "exceptions.Exception", memb.stream.close());
		}

		return 0;
	}

	public uword constructor(CrocThread* t)
	{
		auto memb = getThis(t);

		if(memb.stream !is null)
			throwStdException(t, "ValueException", "Attempting to call constructor on an already-initialized InStream");

		checkParam(t, 1, CrocValue.Type.NativeObj);
		auto input = cast(InputStream)getNativeObj(t, 1);

		if(input is null)
			throwStdException(t, "ValueException", "instances of InStream may only be created using instances of the Tango InputStream");

		memb.closable = optBoolParam(t, 2, true);
		memb.stream = input;
		memb.lines = new Lines!(char)(memb.stream);
		memb.closed = false;

		pushNativeObj(t, cast(Object)memb.stream); setExtraVal(t, 0, Fields.stream);
		pushNativeObj(t, memb.lines);              setExtraVal(t, 0, Fields.lines);

		return 0;
	}

	public uword readVal(T)(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		T val = void;
		
		safeCode(t, "exceptions.IOException", readExact(t, memb, &val, T.sizeof));

		static if(isIntegerType!(T))
			pushInt(t, cast(crocint)val);
		else static if(isRealType!(T))
			pushFloat(t, val);
		else static if(isCharType!(T))
			pushChar(t, val);
		else
			static assert(false);

		return 1;
	}

	public uword readString(CrocThread* t)
	{
		auto memb = getOpenThis(t);

		safeCode(t, "exceptions.IOException",
		{
			uword length = void;

			safeCode(t, "exceptions.IOException", readExact(t, memb, &length, length.sizeof));

			auto dat = t.vm.alloc.allocArray!(char)(length);

			scope(exit)
				t.vm.alloc.freeArray(dat);

			safeCode(t, "exceptions.IOException", readExact(t, memb, dat.ptr, dat.length * char.sizeof));

			pushString(t, dat);
		}());

		return 1;
	}

	public uword readln(CrocThread* t)
	{
		auto ret = safeCode(t, "exceptions.IOException", getOpenThis(t).lines.next());

		if(ret.ptr is null)
			throwStdException(t, "IOException", "Stream has no more data.");

		pushString(t, ret);
		return 1;
	}

	public uword readChars(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto num = checkIntParam(t, 1);

		if(num < 0 || num > uword.max)
			throwStdException(t, "RangeException", "Invalid number of characters ({})", num);

		safeCode(t, "exceptions.IOException",
		{
			auto dat = t.vm.alloc.allocArray!(char)(cast(uword)num);

			scope(exit)
				t.vm.alloc.freeArray(dat);

			safeCode(t, "exceptions.IOException", readExact(t, memb, dat.ptr, dat.length * char.sizeof));
			pushString(t, dat);
		}());

		return 1;
	}

	public uword readMemblock(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkAnyParam(t, 1);

		crocint size = void;
		CrocMemblock* mb = void;

		if(isString(t, 1))
		{
			auto type = getString(t, 1);
			size = checkIntParam(t, 2);

			if(size < 0 || size > uword.max)
				throwStdException(t, "RangeException", "Invalid size: {}", size);

			newMemblock(t, type, cast(uword)size);
			mb = getMemblock(t, -1);
		}
		else if(isMemblock(t, 1))
		{
			mb = getMemblock(t, 1);
			size = optIntParam(t, 2, mb.itemLength);

			if(size != mb.itemLength)
				lenai(t, 1, size);

			dup(t, 1);
		}
		else
			paramTypeError(t, 1, "string|memblock");

		uword numBytes = cast(uword)size * mb.kind.itemSize;
		safeCode(t, "exceptions.IOException", readExact(t, memb, mb.data.ptr, numBytes));
		return 1;
	}

	public uword rawRead(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkParam(t, 1, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 1);

		auto typeCode = mb.kind.code;

		if(typeCode != CrocMemblock.TypeCode.i8 && typeCode != CrocMemblock.TypeCode.u8)
			throwStdException(t, "ValueException", "Memblock must be of type i8 or u8, not '{}'", mb.kind.name);

		if(mb.itemLength == 0)
			throwStdException(t, "ValueException", "Memblock cannot be 0 elements long");

		auto realSize = safeCode(t, "exceptions.IOException", readAtMost(t, memb, mb.data.ptr, mb.itemLength));
		pushInt(t, realSize);
		return 1;
	}

	private uword iterator(CrocThread* t)
	{
		auto index = checkIntParam(t, 1) + 1;
		auto line = safeCode(t, "exceptions.IOException", getOpenThis(t).lines.next());

		if(line.ptr is null)
			return 0;

		pushInt(t, index);
		pushString(t, line);
		return 2;
	}

	public uword opApply(CrocThread* t)
	{
		checkInstParam(t, 0, "InStream");
		getUpval(t, 0);
		dup(t, 0);
		pushInt(t, 0);
		return 3;
	}

	public uword skip(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto dist_ = checkIntParam(t, 1);

		if(dist_ < 0 || dist_ > uword.max)
			throwStdException(t, "RangeException", "Invalid skip distance ({})", dist_);

		auto dist = cast(uword)dist_;

		// it's OK if this is shared - it's just a bit bucket
		static ubyte[1024] dummy;

		while(dist > 0)
		{
			uword numBytes = dist < dummy.length ? dist : dummy.length;
			safeCode(t, "exceptions.IOException", readExact(t, memb, dummy.ptr, numBytes));
			dist -= numBytes;
		}

		return 0;
	}

	public uword seek(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto pos = checkIntParam(t, 1);
		auto whence = checkCharParam(t, 2);

		if(whence == 'b')
			safeCode(t, "exceptions.IOException", memb.stream.seek(pos, IOStream.Anchor.Begin));
		else if(whence == 'c')
			safeCode(t, "exceptions.IOException", memb.stream.seek(pos, IOStream.Anchor.Current));
		else if(whence == 'e')
			safeCode(t, "exceptions.IOException", memb.stream.seek(pos, IOStream.Anchor.End));
		else
			throwStdException(t, "ValueException", "Invalid seek type '{}'", whence);

		dup(t, 0);
		return 1;
	}

	public uword position(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto numParams = stackSize(t) - 1;

		if(numParams == 0)
		{
			pushInt(t, safeCode(t, "exceptions.IOException", cast(crocint)memb.stream.seek(0, IOStream.Anchor.Current)));
			return 1;
		}
		else
		{
			safeCode(t, "exceptions.IOException", memb.stream.seek(checkIntParam(t, 1), IOStream.Anchor.Begin));
			return 0;
		}
	}

	public uword size(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto pos = safeCode(t, "exceptions.IOException", memb.stream.seek(0, IOStream.Anchor.Current));
		auto ret = safeCode(t, "exceptions.IOException", memb.stream.seek(0, IOStream.Anchor.End));
		safeCode(t, "exceptions.IOException", memb.stream.seek(pos, IOStream.Anchor.Begin));
		pushInt(t, cast(crocint)ret);
		return 1;
	}

	public uword close(CrocThread* t)
	{
		auto memb = getOpenThis(t);

		if(!memb.closable)
			throwStdException(t, "ValueException", "Attempting to close an unclosable stream");

		memb.closed = true;
		safeCode(t, "exceptions.IOException", memb.stream.close());

		return 0;
	}

	public uword isOpen(CrocThread* t)
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
		stream,
		print
	}

	align(1) struct Members
	{
		OutputStream stream;
		FormatOutput!(char) print;
		bool closed = true;
		bool closable = true;
	}

	public OutputStream getStream(CrocThread* t, word idx)
	{
		return checkInstParam!(Members)(t, idx, "stream.OutStream").stream;
	}

	public OutputStream getOpenStream(CrocThread* t, word idx)
	{
		auto ret = checkInstParam!(Members)(t, idx, "stream.OutStream");

		if(ret.closed)
			throwStdException(t, "ValueException", "Attempting to perform operation on a closed stream");

		return ret.stream;
	}

	public void init(CrocThread* t)
	{
		CreateClass(t, "OutStream", (CreateClass* c)
		{
			c.method("constructor",   2, &constructor);
			c.method("writeByte",     1, &writeVal!(byte));
			c.method("writeUByte",    1, &writeVal!(ubyte));
			c.method("writeShort",    1, &writeVal!(short));
			c.method("writeUShort",   1, &writeVal!(ushort));
			c.method("writeInt",      1, &writeVal!(int));
			c.method("writeUInt",     1, &writeVal!(uint));
			c.method("writeLong",     1, &writeVal!(long));
			c.method("writeULong",    1, &writeVal!(ulong));
			c.method("writeFloat",    1, &writeVal!(float));
			c.method("writeDouble",   1, &writeVal!(double));
			c.method("writeChar",     1, &writeVal!(char));
			c.method("writeWChar",    1, &writeVal!(wchar));
			c.method("writeDChar",    1, &writeVal!(dchar));
			c.method("writeString",   1, &writeString);
			c.method("write",            &write);
			c.method("writeln",          &writeln);
			c.method("writef",           &writef);
			c.method("writefln",         &writefln);
			c.method("writeChars",    1, &writeChars);
			c.method("writeMemblock", 3, &writeMemblock);
			c.method("flush",         0, &flush);
			c.method("copy",          1, &copy);
			c.method("flushOnNL",     1, &flushOnNL);

			c.method("seek",          2, &seek);
			c.method("position",      1, &position);
			c.method("size",          0, &size);
			c.method("close",         0, &close);
			c.method("isOpen",        0, &isOpen);
		});

		newFunction(t, &allocator, "OutStream.allocator");
		setAllocator(t, -2);

		newFunction(t, &finalizer, "OutStream.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "OutStream");
	}
	
	Members* getThis(CrocThread* t)
	{
		return checkInstParam!(Members)(t, 0, "OutStream");
	}

	private Members* getOpenThis(CrocThread* t)
	{
		auto ret = checkInstParam!(Members)(t, 0, "OutStream");
		
		if(ret.closed)
			throwStdException(t, "ValueException", "Attempting to perform operation on a closed stream");
			
		return ret;
	}
	
	private void writeExact(CrocThread* t, Members* memb, void* src, uword size)
	{
		while(size > 0)
		{
			auto numWritten = memb.stream.write(src[0 .. size]);
			
			if(numWritten == IOStream.Eof)
				throwStdException(t, "IOException", "End-of-flow encountered while writing");
				
			size -= numWritten;
			src += numWritten;
		}
	}

	uword allocator(CrocThread* t)
	{
		newInstance(t, 0, Fields.max + 1, Members.sizeof);
		*(cast(Members*)getExtraBytes(t, -1).ptr) = Members.init;

		dup(t);
		pushNull(t);
		rotateAll(t, 3);
		methodCall(t, 2, "constructor", 0);
		return 1;
	}

	uword finalizer(CrocThread* t)
	{
		auto memb = cast(Members*)getExtraBytes(t, 0).ptr;

		if(memb.closable && !memb.closed)
		{
			memb.closed = true;
			safeCode(t, "exceptions.IOException", memb.stream.flush());
			safeCode(t, "exceptions.IOException", memb.stream.close());
		}

		return 0;
	}

	public uword constructor(CrocThread* t)
	{
		auto memb = getThis(t);

		if(memb.stream !is null)
			throwStdException(t, "ValueException", "Attempting to call constructor on an already-initialized OutStream");

		checkParam(t, 1, CrocValue.Type.NativeObj);
		auto output = cast(OutputStream)getNativeObj(t, 1);

		if(output is null)
			throwStdException(t, "ValueException", "instances of OutStream may only be created using instances of the Tango OutputStream");

		memb.closable = optBoolParam(t, 2, true);
		memb.stream = output;
		memb.print = new FormatOutput!(char)(t.vm.formatter, memb.stream);
		memb.closed = false;

		pushNativeObj(t, cast(Object)memb.stream); setExtraVal(t, 0, Fields.stream);
		pushNativeObj(t, memb.print);              setExtraVal(t, 0, Fields.print);

		return 0;
	}

	public uword writeVal(T)(CrocThread* t)
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

		safeCode(t, "exceptions.IOException", writeExact(t, memb, &val, val.sizeof));
		dup(t, 0);
		return 1;
	}

	public uword writeString(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto str = checkStringParam(t, 1);

		safeCode(t, "exceptions.IOException",
		{
			auto len = str.length;
			writeExact(t, memb, &len, len.sizeof);
			writeExact(t, memb, str.ptr, str.length * char.sizeof);
		}());

		dup(t, 0);
		return 1;
	}

	public uword write(CrocThread* t)
	{
		auto p = getOpenThis(t).print;
		auto numParams = stackSize(t) - 1;

		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);
			safeCode(t, "exceptions.IOException", p.print(getString(t, -1)));
			pop(t);
		}

		dup(t, 0);
		return 1;
	}

	public uword writeln(CrocThread* t)
	{
		auto p = getOpenThis(t).print;
		auto numParams = stackSize(t) - 1;

		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);
			safeCode(t, "exceptions.IOException", p.print(getString(t, -1)));
			pop(t);
		}

		safeCode(t, "exceptions.IOException", p.newline());
		dup(t, 0);
		return 1;
	}

	public uword writef(CrocThread* t)
	{
		auto p = getOpenThis(t).print;
		auto numParams = stackSize(t) - 1;

		safeCode(t, "exceptions.IOException", formatImpl(t, numParams, delegate uint(char[] s)
		{
			p.print(s);
			return s.length;
		}));

		dup(t, 0);
		return 1;
	}

	public uword writefln(CrocThread* t)
	{
		auto p = getOpenThis(t).print;
		auto numParams = stackSize(t) - 1;

		safeCode(t, "exceptions.IOException", formatImpl(t, numParams, delegate uint(char[] s)
		{
			p.print(s);
			return s.length;
		}));

		safeCode(t, "exceptions.IOException", p.newline());
		dup(t, 0);
		return 1;
	}

	public uword writeChars(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto str = checkStringParam(t, 1);
		safeCode(t, "exceptions.IOException", writeExact(t, memb, str.ptr, str.length * char.sizeof));
		dup(t, 0);
		return 1;
	}

	public uword writeMemblock(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkParam(t, 1, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 1);
		auto lo = optIntParam(t, 2, 0);
		auto hi = optIntParam(t, 3, mb.itemLength);

		if(lo < 0)
			lo += mb.itemLength;

		if(hi < 0)
			hi += mb.itemLength;

		if(lo < 0 || lo > hi || hi > mb.itemLength)
			throwStdException(t, "BoundsException", "Invalid indices: {} .. {} (memblock length: {})", lo, hi, mb.itemLength);

		auto isize = mb.kind.itemSize;
		safeCode(t, "exceptions.IOException", writeExact(t, memb, mb.data.ptr + (cast(uword)lo * isize), (cast(uword)(hi - lo)) * isize));
		dup(t, 0);
		return 1;
	}

	public uword flush(CrocThread* t)
	{
		safeCode(t, "exceptions.IOException", getOpenThis(t).stream.flush());
		dup(t, 0);
		return 1;
	}

	public uword copy(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkInstParam(t, 1);

		InputStream stream;
		pushGlobal(t, "InStream");

		if(as(t, 1, -1))
		{
			pop(t);
			stream = getMembers!(InStreamObj.Members)(t, 1).stream;
		}
		else
		{
			pop(t);
			pushGlobal(t, "InoutStream");

			if(as(t, 1, -1))
			{
				pop(t);
				stream = getMembers!(InoutStreamObj.Members)(t, 1).conduit;
			}
			else
				paramTypeError(t, 1, "InStream|InoutStream");
		}

		safeCode(t, "exceptions.IOException", memb.stream.copy(stream));
		dup(t, 0);
		return 1;
	}

	public uword flushOnNL(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		safeCode(t, "exceptions.IOException", memb.print.flush = checkBoolParam(t, 1));
		return 0;
	}

	public uword seek(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto pos = checkIntParam(t, 1);
		auto whence = checkCharParam(t, 2);

		if(whence == 'b')
			safeCode(t, "exceptions.IOException", memb.stream.seek(pos, IOStream.Anchor.Begin));
		else if(whence == 'c')
			safeCode(t, "exceptions.IOException", memb.stream.seek(pos, IOStream.Anchor.Current));
		else if(whence == 'e')
			safeCode(t, "exceptions.IOException", memb.stream.seek(pos, IOStream.Anchor.End));
		else
			throwStdException(t, "ValueException", "Invalid seek type '{}'", whence);

		dup(t, 0);
		return 1;
	}

	public uword position(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto numParams = stackSize(t) - 1;

		if(numParams == 0)
		{
			pushInt(t, safeCode(t, "exceptions.IOException", cast(crocint)memb.stream.seek(0, IOStream.Anchor.Current)));
			return 1;
		}
		else
		{
			safeCode(t, "exceptions.IOException", memb.stream.seek(checkIntParam(t, 1), IOStream.Anchor.Begin));
			return 0;
		}
	}

	public uword size(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto pos = safeCode(t, "exceptions.IOException", memb.stream.seek(0, IOStream.Anchor.Current));
		auto ret = safeCode(t, "exceptions.IOException", memb.stream.seek(0, IOStream.Anchor.End));
		safeCode(t, "exceptions.IOException", memb.stream.seek(pos, IOStream.Anchor.Begin));
		pushInt(t, cast(crocint)ret);
		return 1;
	}

	public uword close(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		
		if(!memb.closable)
			throwStdException(t, "ValueException", "Attempting to close an unclosable stream");

		memb.closed = true;
		safeCode(t, "exceptions.IOException", memb.stream.flush());
		safeCode(t, "exceptions.IOException", memb.stream.close());
		return 0;
	}

	public uword isOpen(CrocThread* t)
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
		conduit,
		lines,
		print
	}

	align(1) struct Members
	{
		IConduit conduit;
		Lines!(char) lines;
		FormatOutput!(char) print;
		bool closed = true;
		bool closable = true;
		bool dirty = false;
	}
	
	public IConduit getConduit(CrocThread* t, word idx)
	{
		return checkInstParam!(Members)(t, idx, "stream.InoutStream").conduit;
	}

	public IConduit getOpenConduit(CrocThread* t, word idx)
	{
		auto ret = checkInstParam!(Members)(t, idx, "stream.InoutStream");

		if(ret.closed)
			throwStdException(t, "ValueException", "Attempting to perform operation on a closed stream");

		return ret.conduit;
	}

	public void init(CrocThread* t)
	{
		CreateClass(t, "Stream", (CreateClass* c)
		{
			c.method("constructor", 2, &constructor);

			c.method("readByte",      0, &readVal!(byte));
			c.method("readUByte",     0, &readVal!(ubyte));
			c.method("readShort",     0, &readVal!(short));
			c.method("readUShort",    0, &readVal!(ushort));
			c.method("readInt",       0, &readVal!(int));
			c.method("readUInt",      0, &readVal!(uint));
			c.method("readLong",      0, &readVal!(long));
			c.method("readULong",     0, &readVal!(ulong));
			c.method("readFloat",     0, &readVal!(float));
			c.method("readDouble",    0, &readVal!(double));
			c.method("readChar",      0, &readVal!(char));
			c.method("readWChar",     0, &readVal!(wchar));
			c.method("readDChar",     0, &readVal!(dchar));
			c.method("readString",    0, &readString);
			c.method("readln",        0, &readln);
			c.method("readChars",     1, &readChars);
			c.method("readMemblock",  2, &readMemblock);
			c.method("rawRead",       2, &rawRead);

				newFunction(t, &iterator, "InoutStream.iterator");
			c.method("opApply", 1, &opApply, 1);

			c.method("writeByte",     1, &writeVal!(byte));
			c.method("writeUByte",    1, &writeVal!(ubyte));
			c.method("writeShort",    1, &writeVal!(short));
			c.method("writeUShort",   1, &writeVal!(ushort));
			c.method("writeInt",      1, &writeVal!(int));
			c.method("writeUInt",     1, &writeVal!(uint));
			c.method("writeLong",     1, &writeVal!(long));
			c.method("writeULong",    1, &writeVal!(ulong));
			c.method("writeFloat",    1, &writeVal!(float));
			c.method("writeDouble",   1, &writeVal!(double));
			c.method("writeChar",     1, &writeVal!(char));
			c.method("writeWChar",    1, &writeVal!(wchar));
			c.method("writeDChar",    1, &writeVal!(dchar));
			c.method("writeString",   1, &writeString);
			c.method("write",            &write);
			c.method("writeln",          &writeln);
			c.method("writef",           &writef);
			c.method("writefln",         &writefln);
			c.method("writeChars",    1, &writeChars);
			c.method("writeMemblock", 3, &writeMemblock);
			c.method("flush",         0, &flush);
			c.method("copy",          1, &copy);
			c.method("flushOnNL",     1, &flushOnNL);

			c.method("skip",          1, &skip);
			c.method("seek",          2, &seek);
			c.method("position",      1, &position);
			c.method("size",          0, &size);
			c.method("close",         0, &close);
			c.method("isOpen",        0, &isOpen);
		});

		newFunction(t, &allocator, "InoutStream.allocator");
		setAllocator(t, -2);

		newFunction(t, &finalizer, "InoutStream.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "InoutStream");
	}

	Members* getThis(CrocThread* t)
	{
		return checkInstParam!(Members)(t, 0, "InoutStream");
	}

	private Members* getOpenThis(CrocThread* t)
	{
		auto ret = checkInstParam!(Members)(t, 0, "InoutStream");
		
		if(ret.closed)
			throwStdException(t, "ValueException", "Attempting to perform operation on a closed stream");

		return ret;
	}

	private void readExact(CrocThread* t, Members* memb, void* dest, uword size)
	{
		while(size > 0)
		{
			auto numRead = memb.conduit.read(dest[0 .. size]);

			if(numRead == IOStream.Eof)
				throwStdException(t, "IOException", "End-of-flow encountered while reading");

			size -= numRead;
			dest += numRead;
		}
	}

	private uword readAtMost(CrocThread* t, Members* memb, void* dest, uword size)
	{
		auto initial = size;

		while(size > 0)
		{
			auto numRead = memb.conduit.read(dest[0 .. size]);

			if(numRead == IOStream.Eof)
				break;
			else if(numRead < size)
			{
				size -= numRead;
				break;
			}

			size -= numRead;
			dest += numRead;
		}

		return initial - size;
	}

	private void writeExact(CrocThread* t, Members* memb, void* src, uword size)
	{
		while(size > 0)
		{
			auto numWritten = memb.conduit.write(src[0 .. size]);

			if(numWritten == IOStream.Eof)
				throwStdException(t, "IOException", "End-of-flow encountered while writing");

			size -= numWritten;
			src += numWritten;
		}
	}

	uword allocator(CrocThread* t)
	{
		newInstance(t, 0, Fields.max + 1, Members.sizeof);
		*(cast(Members*)getExtraBytes(t, -1).ptr) = Members.init;

		dup(t);
		pushNull(t);
		rotateAll(t, 3);
		methodCall(t, 2, "constructor", 0);
		return 1;
	}

	uword finalizer(CrocThread* t)
	{
		auto memb = cast(Members*)getExtraBytes(t, 0).ptr;

		if(memb.closable && !memb.closed)
		{
			memb.closed = true;
			
			if(memb.dirty)
			{
				safeCode(t, "exceptions.IOException", memb.conduit.flush());
				memb.dirty = false;
			}

			safeCode(t, "exceptions.IOException", memb.conduit.close());
		}

		return 0;
	}

	public uword constructor(CrocThread* t)
	{
		auto memb = getThis(t);

		if(memb.conduit !is null)
			throwStdException(t, "ValueException", "Attempting to call constructor on an already-initialized InoutStream");

		checkParam(t, 1, CrocValue.Type.NativeObj);
		auto conduit = cast(IConduit)getNativeObj(t, 1);

		if(conduit is null)
			throwStdException(t, "ValueException", "instances of Stream may only be created using instances of Tango's IConduit");

		memb.closable = optBoolParam(t, 2, true);
		memb.conduit = conduit;
		memb.lines = new Lines!(char)(memb.conduit);
		memb.print = new FormatOutput!(char)(t.vm.formatter, memb.conduit);
		memb.closed = false;

		pushNativeObj(t, cast(Object)memb.conduit); setExtraVal(t, 0, Fields.conduit);
		pushNativeObj(t, memb.lines);               setExtraVal(t, 0, Fields.lines);
		pushNativeObj(t, memb.print);               setExtraVal(t, 0, Fields.print);

		return 0;
	}

	void checkDirty(CrocThread* t, Members* memb)
	{
		if(memb.dirty)
		{
			memb.dirty = false;
			safeCode(t, "exceptions.IOException", memb.conduit.flush());
		}
	}

	public uword readVal(T)(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);

		T val = void;

		safeCode(t, "exceptions.IOException", readExact(t, memb, &val, T.sizeof));

		static if(isIntegerType!(T))
			pushInt(t, cast(crocint)val);
		else static if(isRealType!(T))
			pushFloat(t, val);
		else static if(isCharType!(T))
			pushChar(t, val);
		else
			static assert(false);

		return 1;
	}

	public uword readString(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);

		safeCode(t, "exceptions.IOException",
		{
			uword length = void;

			safeCode(t, "exceptions.IOException", readExact(t, memb, &length, length.sizeof));

			auto dat = t.vm.alloc.allocArray!(char)(length);

			scope(exit)
				t.vm.alloc.freeArray(dat);

			safeCode(t, "exceptions.IOException", readExact(t, memb, dat.ptr, dat.length * char.sizeof));

			pushString(t, dat);
		}());

		return 1;
	}

	public uword readln(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);
		auto ret = safeCode(t, "exceptions.IOException", memb.lines.next());

		if(ret.ptr is null)
			throwStdException(t, "IOException", "Stream has no more data.");

		pushString(t, ret);
		return 1;
	}

	public uword readChars(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto num = checkIntParam(t, 1);

		if(num < 0 || num > uword.max)
			throwStdException(t, "RangeException", "Invalid number of characters ({})", num);

		checkDirty(t, memb);

		safeCode(t, "exceptions.IOException",
		{
			auto dat = t.vm.alloc.allocArray!(char)(cast(uword)num);

			scope(exit)
				t.vm.alloc.freeArray(dat);

			safeCode(t, "exceptions.IOException", readExact(t, memb, dat.ptr, dat.length * char.sizeof));
			pushString(t, dat);
		}());

		return 1;
	}

	public uword readMemblock(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);

		checkAnyParam(t, 1);

		crocint size = void;
		CrocMemblock* mb = void;

		if(isString(t, 1))
		{
			auto type = getString(t, 1);
			size = checkIntParam(t, 2);
			
			if(size < 0 || size > uword.max)
				throwStdException(t, "RangeException", "Invalid size: {}", size);

			newMemblock(t, type, cast(uword)size);
			mb = getMemblock(t, -1);
		}
		else if(isMemblock(t, 1))
		{
			mb = getMemblock(t, 1);
			size = optIntParam(t, 2, mb.itemLength);

			if(size != mb.itemLength)
				lenai(t, 1, size);

			dup(t, 1);
		}
		else
			paramTypeError(t, 1, "string|memblock");

		uword numBytes = cast(uword)size * mb.kind.itemSize;
		safeCode(t, "exceptions.IOException", readExact(t, memb, mb.data.ptr, numBytes));
		return 1;
	}

	public uword rawRead(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);

		checkParam(t, 1, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 1);

		auto typeCode = mb.kind.code;

		if(typeCode != CrocMemblock.TypeCode.i8 && typeCode != CrocMemblock.TypeCode.u8)
			throwStdException(t, "ValueException", "Memblock must be of type i8 or u8, not '{}'", mb.kind.name);

		if(mb.itemLength == 0)
			throwStdException(t, "ValueException", "Memblock cannot be 0 elements long");

		auto realSize = safeCode(t, "exceptions.IOException", readAtMost(t, memb, mb.data.ptr, mb.itemLength));
		pushInt(t, realSize);
		return 1;
	}

	private uword iterator(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);
		auto index = checkIntParam(t, 1) + 1;
		auto line = safeCode(t, "exceptions.IOException", memb.lines.next());

		if(line.ptr is null)
			return 0;

		pushInt(t, index);
		pushString(t, line);
		return 2;
	}

	public uword opApply(CrocThread* t)
	{
		checkInstParam(t, 0, "InoutStream");
		getUpval(t, 0);
		dup(t, 0);
		pushInt(t, 0);
		return 3;
	}

	public uword writeVal(T)(CrocThread* t)
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

		safeCode(t, "exceptions.IOException", writeExact(t, memb, &val, val.sizeof));
		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword writeString(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto str = checkStringParam(t, 1);

		safeCode(t, "exceptions.IOException",
		{
			auto len = str.length;
			writeExact(t, memb, &len, len.sizeof);
			writeExact(t, memb, str.ptr, str.length * char.sizeof);
		}());

		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword write(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto p = memb.print;
		auto numParams = stackSize(t) - 1;

		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);
			safeCode(t, "exceptions.IOException", p.print(getString(t, -1)));
			pop(t);
		}

		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword writeln(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto p = memb.print;
		auto numParams = stackSize(t) - 1;

		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);
			safeCode(t, "exceptions.IOException", p.print(getString(t, -1)));
			pop(t);
		}

		safeCode(t, "exceptions.IOException", p.newline());
		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword writef(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto p = memb.print;
		auto numParams = stackSize(t) - 1;

		safeCode(t, "exceptions.IOException", formatImpl(t, numParams, delegate uint(char[] s)
		{
			p.print(s);
			return s.length;
		}));

		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword writefln(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto p = memb.print;
		auto numParams = stackSize(t) - 1;

		safeCode(t, "exceptions.IOException", formatImpl(t, numParams, delegate uint(char[] s)
		{
			p.print(s);
			return s.length;
		}));

		safeCode(t, "exceptions.IOException", p.newline());
		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword writeChars(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto str = checkStringParam(t, 1);
		safeCode(t, "exceptions.IOException", writeExact(t, memb, str.ptr, str.length * char.sizeof));
		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword writeMemblock(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkParam(t, 1, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 1);
		auto lo = optIntParam(t, 2, 0);
		auto hi = optIntParam(t, 3, mb.itemLength);

		if(lo < 0)
			lo += mb.itemLength;

		if(hi < 0)
			hi += mb.itemLength;

		if(lo < 0 || lo > hi || hi > mb.itemLength)
			throwStdException(t, "BoundsException", "Invalid indices: {} .. {} (memblock length: {})", lo, hi, mb.itemLength);

		auto isize = mb.kind.itemSize;
		safeCode(t, "exceptions.IOException", writeExact(t, memb, mb.data.ptr + (cast(uword)lo * isize), (cast(uword)(hi - lo)) * isize));
		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword flush(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		safeCode(t, "exceptions.IOException", memb.conduit.flush());
		//safeCode(t, "exceptions.IOException", memb.conduit.clear());
		memb.dirty = false;
		dup(t, 0);
		return 1;
	}

	public uword copy(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkInstParam(t, 1);

		InputStream stream;
		pushGlobal(t, "InStream");

		if(as(t, 1, -1))
		{
			pop(t);
			stream = getMembers!(InStreamObj.Members)(t, 1).stream;
		}
		else
		{
			pop(t);
			pushGlobal(t, "InoutStream");

			if(as(t, 1, -1))
			{
				pop(t);
				stream = getMembers!(InoutStreamObj.Members)(t, 1).conduit;
			}
			else
				paramTypeError(t, 1, "InStream|InoutStream");
		}

		safeCode(t, "exceptions.IOException", memb.conduit.copy(stream));
		memb.dirty = true;
		dup(t, 0);
		return 1;
	}

	public uword flushOnNL(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		safeCode(t, "exceptions.IOException", memb.print.flush = checkBoolParam(t, 1));
		return 0;
	}

	public uword skip(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto dist_ = checkIntParam(t, 1);

		if(dist_ < 0 || dist_ > uword.max)
			throwStdException(t, "RangeException", "Invalid skip distance ({})", dist_);

		auto dist = cast(uword)dist_;

		checkDirty(t, memb);

		// it's OK if this is shared - it's just a bit bucket
		static ubyte[1024] dummy;

		while(dist > 0)
		{
			uword numBytes = dist < dummy.length ? dist : dummy.length;
			safeCode(t, "exceptions.IOException", readExact(t, memb, dummy.ptr, numBytes));
			dist -= numBytes;
		}

		return 0;
	}

	public uword seek(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);
		auto pos = checkIntParam(t, 1);
		auto whence = checkCharParam(t, 2);

		if(whence == 'b')
			safeCode(t, "exceptions.IOException", memb.conduit.seek(pos, IOStream.Anchor.Begin));
		else if(whence == 'c')
			safeCode(t, "exceptions.IOException", memb.conduit.seek(pos, IOStream.Anchor.Current));
		else if(whence == 'e')
			safeCode(t, "exceptions.IOException", memb.conduit.seek(pos, IOStream.Anchor.End));
		else
			throwStdException(t, "ValueException", "Invalid seek type '{}'", whence);

		dup(t, 0);
		return 1;
	}

	public uword position(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto numParams = stackSize(t) - 1;

		if(numParams == 0)
		{
			pushInt(t, safeCode(t, "exceptions.IOException", cast(crocint)memb.conduit.seek(0, IOStream.Anchor.Current)));
			return 1;
		}
		else
		{
			checkDirty(t, memb);
			safeCode(t, "exceptions.IOException", memb.conduit.seek(checkIntParam(t, 1), IOStream.Anchor.Begin));
			return 0;
		}
	}

	public uword size(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		checkDirty(t, memb);
		auto pos = safeCode(t, "exceptions.IOException", memb.conduit.seek(0, IOStream.Anchor.Current));
		auto ret = safeCode(t, "exceptions.IOException", memb.conduit.seek(0, IOStream.Anchor.End));
		safeCode(t, "exceptions.IOException", memb.conduit.seek(pos, IOStream.Anchor.Begin));
		pushInt(t, cast(crocint)ret);
		return 1;
	}

	public uword close(CrocThread* t)
	{
		auto memb = getOpenThis(t);

		if(!memb.closable)
			throwStdException(t, "ValueException", "Attempting to close an unclosable stream");

		memb.closed = true;
		safeCode(t, "exceptions.IOException", memb.conduit.flush());
		safeCode(t, "exceptions.IOException", memb.conduit.close());

		return 0;
	}

	public uword isOpen(CrocThread* t)
	{
		pushBool(t, !getThis(t).closed);
		return 1;
	}
}

class MemblockConduit : Conduit, Conduit.Seek
{
	private CrocVM* vm;
	private ulong mMB;
	private uword mPos = 0;

	private this(CrocVM* vm, ulong mb)
	{
		super();
		this.vm = vm;
		mMB = mb;
	}

	override char[] toString()
	{
		return "<memblock>";
	}

	override uword bufferSize()
	{
		return 1024;
	}

	override void detach()
	{

	}

	override uword read(void[] dest)
	{
		auto t = currentThread(vm);
		pushRef(t, mMB);
		auto mb = getMemblock(t, -1);

		auto byteSize = mb.itemLength * mb.kind.itemSize;

		if(mPos >= byteSize)
			return Eof;

		auto numBytes = min(byteSize - mPos, dest.length);
		dest[0 .. numBytes] = mb.data[mPos .. mPos + numBytes];
		mPos += numBytes;
		return numBytes;
	}

	override uword write(void[] src)
	{
		auto t = currentThread(vm);
		pushRef(t, mMB);
		auto mb = getMemblock(t, -1);

		auto byteSize = mb.itemLength * mb.kind.itemSize;
		auto bytesLeft = byteSize - mPos;

		if(src.length > bytesLeft)
		{
			auto newByteSize = byteSize - bytesLeft + src.length;
			auto newSize = newByteSize / mb.kind.itemSize;

			if((newSize * mb.kind.itemSize) < newByteSize)
				newSize++;
				
			lenai(t, -1, newSize);
		}

		pop(t);

		mb.data[mPos .. mPos + src.length] = src[];
		mPos += src.length;
		return src.length;
	}

	override long seek(long offset, Anchor anchor = Anchor.Begin)
	{
		auto t = currentThread(vm);
		pushRef(t, mMB);
		auto mb = getMemblock(t, -1);
		pop(t);

		auto byteSize = mb.itemLength * mb.kind.itemSize;

		if(offset > byteSize)
			offset = byteSize;

		switch(anchor)
		{
			case Anchor.Begin:
				mPos = cast(uword)offset;
				break;

			case Anchor.End:
				mPos = cast(uword)(byteSize - offset);
				break;

			case Anchor.Current:
				auto off = cast(uword)(mPos + offset);

				if(off < 0)
					off = 0;

				if(off > byteSize)
					off = byteSize;

				mPos = off;
				break;

			default: assert(false);
		}

		return mPos;
	}
}

struct MemInStreamObj
{
static:
	alias InStreamObj.Members Members;

	public void init(CrocThread* t)
	{
		CreateClass(t, "MemInStream", "InStream", (CreateClass* c)
		{
			c.method("constructor", &constructor);
		});

		newFunction(t, &finalizer, "MemInStream.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "MemInStream");
	}

	uword finalizer(CrocThread* t)
	{
		auto memb = cast(Members*)getExtraBytes(t, 0).ptr;

		if(!memb.closed)
		{
			memb.closed = true;
			removeRef(t, (cast(MemblockConduit)memb.stream).mMB);
		}

		return 0;
	}

	public uword constructor(CrocThread* t)
	{
		auto memb = InStreamObj.getThis(t);

		if(memb.stream !is null)
			throwStdException(t, "ValueException", "Attempting to call constructor on an already-initialized MemInStream");

		checkParam(t, 1, CrocValue.Type.Memblock);

		pushNull(t);
		pushNull(t);
		pushNativeObj(t, new MemblockConduit(getVM(t), createRef(t, 1)));
		pushBool(t, true);
		superCall(t, -4, "constructor", 0);

		return 0;
	}
}

struct MemOutStreamObj
{
static:
	alias OutStreamObj.Members Members;

	public void init(CrocThread* t)
	{
		CreateClass(t, "MemOutStream", "OutStream", (CreateClass* c)
		{
			c.method("constructor", &constructor);
		});

		newFunction(t, &finalizer, "MemOutStream.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "MemOutStream");
	}

	uword finalizer(CrocThread* t)
	{
		auto memb = cast(Members*)getExtraBytes(t, 0).ptr;

		if(!memb.closed)
		{
			memb.closed = true;
			removeRef(t, (cast(MemblockConduit)memb.stream).mMB);
		}

		return 0;
	}

	public uword constructor(CrocThread* t)
	{
		auto memb = OutStreamObj.getThis(t);

		if(memb.stream !is null)
			throwStdException(t, "ValueException", "Attempting to call constructor on an already-initialized MemOutStream");

		checkParam(t, 1, CrocValue.Type.Memblock);

		pushNull(t);
		dup(t);
		pushNativeObj(t, new MemblockConduit(getVM(t), createRef(t, 1)));
		pushBool(t, true);
		superCall(t, -4, "constructor", 0);

		return 0;
	}
}

struct MemInoutStreamObj
{
static:
	alias InoutStreamObj.Members Members;

	public void init(CrocThread* t)
	{
		CreateClass(t, "MemInoutStream", "InoutStream", (CreateClass* c)
		{
			c.method("constructor", &constructor);
		});

		newFunction(t, &finalizer, "MemInoutStream.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "MemInoutStream");
	}

	uword finalizer(CrocThread* t)
	{
		auto memb = cast(Members*)getExtraBytes(t, 0).ptr;

		if(!memb.closed)
		{
			memb.closed = true;
			removeRef(t, (cast(MemblockConduit)memb.conduit).mMB);
		}

		return 0;
	}

	public uword constructor(CrocThread* t)
	{
		auto memb = InoutStreamObj.getThis(t);

		if(memb.conduit !is null)
			throwStdException(t, "ValueException", "Attempting to call constructor on an already-initialized MemInoutStream");

		checkParam(t, 1, CrocValue.Type.Memblock);

		pushNull(t);
		dup(t);
		pushNativeObj(t, new MemblockConduit(getVM(t), createRef(t, 1)));
		pushBool(t, true);
		superCall(t, -4, "constructor", 0);

		return 0;
	}
}