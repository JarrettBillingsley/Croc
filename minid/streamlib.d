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

module minid.streamlib;

import tango.core.Traits;
import tango.io.Buffer;
import tango.io.Console;
import tango.io.device.Conduit;
import tango.io.Print;
import tango.io.protocol.Reader;
import tango.io.protocol.Writer;
import tango.text.stream.LineIterator;

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
			InputStreamObj.init(t);
			OutputStreamObj.init(t);
			StreamObj.init(t);

				pushGlobal(t, "InputStream");
				pushNull(t);
				pushNativeObj(t, cast(Object)Cin.stream);
				rawCall(t, -3, 1);
			newGlobal(t, "stdin");

				pushGlobal(t, "OutputStream");
				pushNull(t);
				pushNativeObj(t, cast(Object)Cout.stream);
				rawCall(t, -3, 1);
			newGlobal(t, "stdout");

				pushGlobal(t, "OutputStream");
				pushNull(t);
				pushNativeObj(t, cast(Object)Cerr.stream);
				rawCall(t, -3, 1);
			newGlobal(t, "stderr");

			return 0;
		}, "stream");

		fielda(t, -2, "stream");
		importModule(t, "stream");
		pop(t, 3);
	}
}

struct InputStreamObj
{
static:
	enum Fields
	{
		stream,
		reader,
		lines
	}

	align(1) struct Members
	{
		InputStream stream;
		IReader reader;
		LineIterator!(char) lines;
		IBuffer buf;
	}

	public void init(MDThread* t)
	{
		CreateClass(t, "InputStream", (CreateClass* c)
		{
			c.method("constructor", &constructor);
			c.method("readByte", &readVal!(ubyte));
			c.method("readShort", &readVal!(ushort));
			c.method("readInt", &readVal!(int));
			c.method("readLong", &readVal!(long));
			c.method("readFloat", &readVal!(float));
			c.method("readDouble", &readVal!(double));
			c.method("readChar", &readVal!(char));
			c.method("readWChar", &readVal!(wchar));
			c.method("readDChar", &readVal!(dchar));
			c.method("readString", &readString);
			c.method("readln", &readln);
			c.method("readChars", &readChars);
			c.method("readVector", &readVector);
			c.method("clear", &clear);

				newFunction(t, &iterator, "InputStream.iterator");
			c.method("opApply", &opApply, 1);
		});

		newFunction(t, &allocator, "InputStream.allocator");
		setAllocator(t, -2);

		newGlobal(t, "InputStream");
	}

	private Members* getThis(MDThread* t)
	{
		return checkInstParam!(Members)(t, 0, "InputStream");
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

	public uword constructor(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		
		if(memb.stream !is null)
			throwException(t, "Attempting to call constructor on an already-initialized InputStream");

		checkParam(t, 1, MDValue.Type.NativeObj);
		auto input = cast(InputStream)getNativeObj(t, 1);

		if(input is null)
			throwException(t, "instances of InputStream may only be created using instances of the Tango InputStream");

		memb.buf = Buffer.share(input);
		memb.stream = memb.buf;
		memb.reader = new Reader(memb.buf);
		memb.lines = new LineIterator!(char)(memb.buf);

		pushNativeObj(t, cast(Object)memb.stream); setExtraVal(t, 0, Fields.stream);
		pushNativeObj(t, memb.reader);             setExtraVal(t, 0, Fields.reader);
		pushNativeObj(t, memb.lines);              setExtraVal(t, 0, Fields.lines);

		return 0;
	}

	public uword readVal(T)(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		T val = void;
		safeCode(t, memb.reader.get(val));

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
		auto memb = getThis(t);

		safeCode(t,
		{
			uword length = void;
			memb.reader.get(length);

			auto dat = t.vm.alloc.allocArray!(char)(length);

			scope(exit)
				t.vm.alloc.freeArray(dat);

			memb.buf.readExact(dat.ptr, length * char.sizeof);
			pushString(t, dat);
		}());

		return 1;
	}

	public uword readln(MDThread* t, uword numParams)
	{
		auto ret = safeCode(t, getThis(t).lines.next());

		if(ret.ptr is null)
			throwException(t, "Stream has no more data.");

		pushString(t, ret);
		return 1;
	}

	public uword readChars(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto num = checkIntParam(t, 1);

		if(num < 0 || num > uword.max)
			throwException(t, "Invalid number of characters ({})", num);

		safeCode(t,
		{
			auto dat = t.vm.alloc.allocArray!(char)(cast(uword)num);

			scope(exit)
				t.vm.alloc.freeArray(dat);

			memb.buf.readExact(dat.ptr, cast(uword)num * char.sizeof);
			pushString(t, dat);
		}());

		return 1;
	}

	public uword readVector(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
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
			pushGlobal(t, "Vector");

			if(!as(t, 1, -1))
				paramTypeError(t, 1, "Vector");

			vecMemb = getMembers!(VectorObj.Members)(t, -1);
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

		memb.buf.readExact(vecMemb.data, cast(uword)size * vecMemb.type.itemSize);

		return 1;
	}

	private uword clear(MDThread* t, uword numParams)
	{
		getThis(t).stream.clear();
		dup(t, 0);
		return 1;
	}

	private uword iterator(MDThread* t, uword numParams)
	{
		auto index = checkIntParam(t, 1) + 1;
		auto line = safeCode(t, getThis(t).lines.next());

		if(line.ptr is null)
			return 0;

		pushInt(t, index);
		pushString(t, line);
		return 2;
	}

	public uword opApply(MDThread* t, uword numParams)
	{
		checkInstParam(t, 0, "InputStream");
		getUpval(t, 0);
		dup(t, 0);
		pushInt(t, 0);
		return 3;
	}
}

struct OutputStreamObj
{
static:
	enum Fields
	{
		stream,
		writer,
		print
	}

	align(1) struct Members
	{
		OutputStream stream;
		IWriter writer;
		Print!(char) print;
		IBuffer buf;
	}

	public void init(MDThread* t)
	{
		CreateClass(t, "OutputStream", (CreateClass* c)
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
		});

		newFunction(t, &allocator, "OutputStream.allocator");
		setAllocator(t, -2);

		newFunction(t, &finalizer, "OutputStream.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "OutputStream");
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

		if(memb.stream !is null)
		{
			memb.stream.flush();
			memb.stream = null;
		}

		return 0;
	}

	Members* getThis(MDThread* t)
	{
		return checkInstParam!(Members)(t, 0, "OutputStream");
	}

	public uword constructor(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		
		if(memb.stream !is null)
			throwException(t, "Attempting to call constructor on an already-initialized OutputStream");

		checkParam(t, 1, MDValue.Type.NativeObj);
		auto output = cast(OutputStream)getNativeObj(t, 1);

		if(output is null)
			throwException(t, "instances of OutputStream may only be created using instances of the Tango OutputStream");

		memb.buf = Buffer.share(output);
		memb.stream = memb.buf;
		memb.writer = new Writer(memb.buf);
		memb.print = new Print!(char)(t.vm.formatter, memb.buf);

		pushNativeObj(t, cast(Object)memb.stream); setExtraVal(t, 0, Fields.stream);
		pushNativeObj(t, memb.writer);             setExtraVal(t, 0, Fields.writer);
		pushNativeObj(t, memb.print);              setExtraVal(t, 0, Fields.print);

		return 0;
	}

	public uword writeVal(T)(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		static if(isIntegerType!(T))
			T val = cast(T)checkIntParam(t, 1);
		else static if(isRealType!(T))
			T val = cast(T)checkFloatParam(t, 1);
		else static if(isCharType!(T))
			T val = cast(T)checkCharParam(t, 1);
		else
			static assert(false);

		safeCode(t, memb.writer.put(val));
		dup(t, 0);
		return 1;
	}

	public uword writeString(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		auto str = checkStringParam(t, 1);

		safeCode(t,
		{
			memb.writer.put(str.length);
			memb.buf.append(str.ptr, str.length * char.sizeof);
		}());

		dup(t, 0);
		return 1;
	}

	public uword write(MDThread* t, uword numParams)
	{
		auto p = getThis(t).print;

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
		auto p = getThis(t).print;

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
		auto p = getThis(t).print;

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
		auto p = getThis(t).print;

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
		auto memb = getThis(t);
		auto str = checkStringParam(t, 1);
		safeCode(t, memb.buf.append(str.ptr, str.length * char.sizeof));
		dup(t, 0);
		return 1;
	}

	public uword writeJSON(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkAnyParam(t, 1);
		auto pretty = optBoolParam(t, 2, false);
		toJSONImpl(t, 1, pretty, memb.print);
		dup(t, 0);
		return 1;
	}

	public uword writeVector(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
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
		safeCode(t, getThis(t).buf.flush());
		dup(t, 0);
		return 1;
	}

	public uword copy(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkInstParam(t, 1);

		InputStream stream;
		pushGlobal(t, "InputStream");

		if(as(t, 1, -1))
		{
			pop(t);
			stream = (cast(InputStreamObj.Members*)getExtraBytes(t, 1).ptr).stream;
		}
		else
		{
			pop(t);
			pushGlobal(t, "Stream");

			if(as(t, 1, -1))
			{
				pop(t);
				getExtraVal(t, 1, StreamObj.Fields.input);
				stream = (cast(InputStreamObj.Members*)getExtraBytes(t, -1).ptr).stream;
				pop(t);
			}
			else
				paramTypeError(t, 1, "InputStream|Stream");
		}

		safeCode(t, memb.stream.copy(stream));
		dup(t, 0);
		return 1;
	}
}

import tango.io.Stdout;

struct StreamObj
{
static:
	enum Fields
	{
		conduit,
		input,
		output,
		seeker
	}

	align(1) struct Members
	{
		bool closed = true;
		bool dirty;
		IConduit conduit;
		IConduit.Seek seeker;
		IBuffer buf;
	}

	public void init(MDThread* t)
	{
		CreateClass(t, "Stream", (CreateClass* c)
		{
			c.method("constructor", &constructor);

			c.method("readByte", &readVal!(ubyte));
			c.method("readShort", &readVal!(ushort));
			c.method("readInt", &readVal!(int));
			c.method("readLong", &readVal!(long));
			c.method("readFloat", &readVal!(float));
			c.method("readDouble", &readVal!(double));
			c.method("readChar", &readVal!(char));
			c.method("readWChar", &readVal!(wchar));
			c.method("readDChar", &readVal!(dchar));
			c.method("readString", &readString);
			c.method("readln", &readln);
			c.method("readChars", &readChars);
			c.method("readVector", &readVector);
			c.method("clear", &clear);
			c.method("opApply", &opApply);

			c.method("writeByte", &writeVal!(ubyte));
			c.method("writeShort", &writeVal!(ushort));
			c.method("writeInt", &writeVal!(int));
			c.method("writeLong", &writeVal!(long));
			c.method("writeFloat", &writeVal!(float));
			c.method("writeDouble", &writeVal!(double));
			c.method("writeChar", &writeVal!(char));
			c.method("writeWChar", &writeVal!(wchar));
			c.method("writeDChar", &writeVal!(dchar));
			c.method("writeString", &writeString);
			c.method("write", &write);
			c.method("writeln", &writeln);
			c.method("writef", &writef);
			c.method("writefln", &writefln);
			c.method("writeChars", &writeChars);
			c.method("writeJSON", &writeJSON);
			c.method("writeVector", &writeVector);
			c.method("flush", &flush);
			c.method("copy", &copy);

			c.method("seek", &seek);
			c.method("position", &position);
			c.method("size", &size);
			c.method("close", &close);
			c.method("isOpen", &isOpen);

			c.method("input", &input);
			c.method("output", &output);
		});

		newFunction(t, &allocator, "Stream.allocator");
		setAllocator(t, -2);

		newFunction(t, &finalizer, "Stream.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "Stream");
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

		if(!memb.closed)
		{
			memb.closed = true;

			if(memb.dirty)
			{
				memb.dirty = false;
				getExtraVal(t, 0, Fields.output);
				(cast(OutputStreamObj.Members*)getExtraBytes(t, -1).ptr).stream.flush();
				pop(t);
			}

			memb.conduit.close();
		}

		return 0;
	}

	public uword constructor(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkParam(t, 1, MDValue.Type.NativeObj);
		
		if(memb.conduit !is null)
			throwException(t, "Attempting to call constructor on an already-initialized Stream");

		auto conduit = cast(IConduit)getNativeObj(t, 1);

		if(conduit is null)
			throwException(t, "instances of Stream may only be created using instances of Tango's IConduit");

		memb.closed = false;
		memb.dirty = false;
		memb.seeker = cast(IConduit.Seek)conduit;

		if(auto b = cast(Buffered)conduit)
		{
			memb.buf = b.buffer;
			memb.conduit = b.buffer;
		}
		else
		{
			memb.buf = new Buffer(conduit);
			memb.conduit = memb.buf;
		}

		pushNativeObj(t, cast(Object)memb.conduit); setExtraVal(t, 0, Fields.conduit);

		if(memb.seeker is null)
			pushNull(t);
		else
			pushNativeObj(t, cast(Object)memb.seeker);

		setExtraVal(t, 0, Fields.seeker);

			pushGlobal(t, "InputStream");
			pushNull(t);
			pushNativeObj(t, cast(Object)memb.conduit);
			rawCall(t, -3, 1);
		setExtraVal(t, 0, Fields.input);

			pushGlobal(t, "OutputStream");
			pushNull(t);
			pushNativeObj(t, cast(Object)memb.conduit);
			rawCall(t, -3, 1);
		setExtraVal(t, 0, Fields.output);

		return 0;
	}

	word pushInput(MDThread* t)
	{
		return getExtraVal(t, 0, Fields.input);
	}

	word pushOutput(MDThread* t)
	{
		return getExtraVal(t, 0, Fields.output);
	}

	Members* getThis(MDThread* t)
	{
		return checkInstParam!(Members)(t, 0, "Stream");
	}

	void checkDirty(MDThread* t, Members* memb)
	{
		if(memb.dirty)
		{
			memb.dirty = false;
			pushOutput(t);
			(cast(OutputStreamObj.Members*)getExtraBytes(t, -1).ptr).stream.flush();
			pop(t);
			pushInput(t);
			(cast(InputStreamObj.Members*)getExtraBytes(t, -1).ptr).stream.clear();
			pop(t);
		}
	}

	public uword readVal(T)(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		Stderr.formatln("Reading: readable {}, writable {}, position {}", memb.buf.readable, memb.buf.writable, memb.buf.position);
		checkDirty(t, memb);
		pushInput(t);
		swap(t, 0);
		pop(t);
		return InputStreamObj.readVal!(T)(t, numParams);
	}

	public uword readString(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkDirty(t, memb);
		pushInput(t);
		swap(t, 0);
		pop(t);
		return InputStreamObj.readString(t, numParams);
	}

	public uword readln(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkDirty(t, memb);
		pushInput(t);
		swap(t, 0);
		pop(t);
		return InputStreamObj.readln(t, numParams);
	}

	public uword readChars(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkDirty(t, memb);
		pushInput(t);
		swap(t, 0);
		pop(t);
		return InputStreamObj.readChars(t, numParams);
	}

	public uword readVector(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkDirty(t, memb);

		setStackSize(t, 3);

		pushInput(t);
		swap(t, 0);
		pop(t);
		return InputStreamObj.readVector(t, numParams);
	}

	public uword clear(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		pushInput(t);
		(cast(InputStreamObj.Members*)getExtraBytes(t, -1).ptr).stream.clear();
		dup(t, 0);
		return 1;
	}

	public uword opApply(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		checkDirty(t, memb);
		pushInput(t);
		pushNull(t);
		return methodCall(t, -2, "opApply", -1);
	}

	public uword writeVal(T)(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		memb.dirty = true;
		Stderr.formatln("Writing: readable {}, writable {}, position {}", memb.buf.readable, memb.buf.writable, memb.buf.position);
		pushOutput(t);
		swap(t, 0);
		OutputStreamObj.writeVal!(T)(t, numParams);
		pop(t);
		return 1;
	}

	public uword writeString(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		memb.dirty = true;
		pushOutput(t);
		swap(t, 0);
		OutputStreamObj.writeString(t, numParams);
		pop(t);
		return 1;
	}

	public uword write(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		memb.dirty = true;
		pushOutput(t);
		swap(t, 0);
		OutputStreamObj.write(t, numParams);
		pop(t);
		return 1;
	}

	public uword writeln(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		memb.dirty = true;
		pushOutput(t);
		swap(t, 0);
		OutputStreamObj.writeln(t, numParams);
		pop(t);
		return 1;
	}

	public uword writef(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		memb.dirty = true;
		pushOutput(t);
		swap(t, 0);
		OutputStreamObj.writef(t, numParams);
		pop(t);
		return 1;
	}

	public uword writefln(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		memb.dirty = true;
		pushOutput(t);
		swap(t, 0);
		OutputStreamObj.writefln(t, numParams);
		pop(t);
		return 1;
	}

	public uword writeChars(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		memb.dirty = true;
		pushOutput(t);
		swap(t, 0);
		OutputStreamObj.writeChars(t, numParams);
		pop(t);
		return 1;
	}

	public uword writeJSON(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		memb.dirty = true;
		checkAnyParam(t, 1);

		// Have to set up the stack so that OutputStream.writeJSON sees optional params correctly
		setStackSize(t, 3);

		pushOutput(t);
		swap(t, 0);
		OutputStreamObj.writeJSON(t, numParams);
		pop(t);
		return 1;
	}

	public uword writeVector(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		memb.dirty = true;

		setStackSize(t, 4);
		pushOutput(t);
		swap(t, 0);
		OutputStreamObj.writeVector(t, numParams);
		pop(t);
		return 1;
	}

	public uword flush(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		memb.dirty = false;
		pushOutput(t);
		(cast(OutputStreamObj.Members*)getExtraBytes(t, -1).ptr).stream.flush();
		dup(t, 0);
		return 1;
	}

	public uword copy(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);
		memb.dirty = true;
		pushOutput(t);
		swap(t, 0);
		OutputStreamObj.copy(t, numParams);
		pop(t);
		return 1;
	}

	public uword seek(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		if(memb.seeker is null)
			throwException(t, "Stream is not seekable.");

		auto pos = checkIntParam(t, 1);
		auto whence = checkCharParam(t, 2);

		pushOutput(t);
		(cast(OutputStreamObj.Members*)getExtraBytes(t, -1).ptr).stream.flush();
		pop(t);
		pushInput(t);
		(cast(InputStreamObj.Members*)getExtraBytes(t, -1).ptr).stream.clear();
		pop(t);

		memb.dirty = false;

		if(whence == 'b')
			safeCode(t, memb.seeker.seek(pos, IConduit.Seek.Anchor.Begin));
		else if(whence == 'c')
			safeCode(t, memb.seeker.seek(pos, IConduit.Seek.Anchor.Current));
		else if(whence == 'e')
			safeCode(t, memb.seeker.seek(pos, IConduit.Seek.Anchor.End));
		else
			throwException(t, "Invalid seek type '{}'", whence);

		dup(t, 0);
		return 1;
	}

	public uword position(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		if(memb.seeker is null)
			throwException(t, "Stream is not seekable.");

		Stderr.formatln("Seeking: readable {}, writable {}, position {}", memb.buf.readable, memb.buf.writable, memb.buf.position);

		if(numParams == 0)
		{
			pushInt(t, safeCode(t, cast(mdint)memb.seeker.seek(0, IConduit.Seek.Anchor.Current)));
			return 1;
		}
		else
		{
			pushOutput(t);
			(cast(OutputStreamObj.Members*)getExtraBytes(t, -1).ptr).stream.flush();
			pop(t);
			pushInput(t);
			(cast(InputStreamObj.Members*)getExtraBytes(t, -1).ptr).stream.clear();
			pop(t);

			memb.dirty = false;

			safeCode(t, memb.seeker.seek(checkIntParam(t, 1), IConduit.Seek.Anchor.Begin));
			return 0;
		}
	}

	public uword size(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		if(memb.seeker is null)
			throwException(t, "Stream is not seekable.");

		auto pos = memb.seeker.seek(0, IConduit.Seek.Anchor.Current);
		auto ret = memb.seeker.seek(0, IConduit.Seek.Anchor.End);
		memb.seeker.seek(pos, IConduit.Seek.Anchor.Begin);

		pushInt(t, cast(mdint)ret);
		return 1;
	}

	public uword close(MDThread* t, uword numParams)
	{
		auto memb = getThis(t);

		memb.closed = true;

		pushOutput(t);
		(cast(OutputStreamObj.Members*)getExtraBytes(t, -1).ptr).stream.flush();
		pop(t);

		memb.dirty = false;
		memb.conduit.close();
		return 0;
	}

	public uword isOpen(MDThread* t, uword numParams)
	{
		pushBool(t, !getThis(t).closed);
		return 1;
	}

	public uword input(MDThread* t, uword numParams)
	{
		checkInstParam(t, 0, "Stream");
		getExtraVal(t, 0, Fields.input);
		return 1;
	}

	public uword output(MDThread* t, uword numParams)
	{
		checkInstParam(t, 0, "Stream");
		getExtraVal(t, 0, Fields.output);
		return 1;
	}
}