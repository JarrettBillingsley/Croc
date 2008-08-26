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

module minid.iolib;

import minid.misc;
import minid.types;
import minid.utils;

import tango.io.Conduit;
import tango.io.Console;
import tango.io.File;
import tango.io.FileConduit;
import tango.io.FilePath;
import tango.io.FileSystem;
import tango.io.model.IConduit;
import tango.io.Print;
import tango.io.protocol.Reader;
import tango.io.protocol.Writer;
import tango.io.UnicodeFile;
import tango.text.convert.Layout;
import tango.text.stream.LineIterator;
import tango.util.PathUtil;
import Utf = tango.text.convert.Utf;

class IOLib
{
	private static const FileConduit.Style DefaultFileStyle;
	private MDInputStreamClass inputStreamClass;
	private MDOutputStreamClass outputStreamClass;
	private MDStreamClass streamClass;

	static this()
	{
		DefaultFileStyle = FileConduit.Style
		(
			FileConduit.ReadExisting.access,
			FileConduit.ReadExisting.open,
			FileConduit.Share.ReadWrite,
			FileConduit.ReadExisting.cache
		);
	}

	private this(MDObject _Object)
	{
		inputStreamClass = new MDInputStreamClass(_Object);
		streamClass = new MDStreamClass(_Object);
		outputStreamClass = new MDOutputStreamClass(_Object, inputStreamClass, streamClass);
	}

	enum FileMode
	{
		In = 1,
		Out = 2,
		New = 4,
		Append = 8,
		OutNew = Out | New
	}

	public static void init(MDContext context)
	{
		context.setModuleLoader("io", context.newClosure(function int(MDState s, uint numParams)
		{
			auto ioLib = new IOLib(s.context.globals.get!(MDObject)("Object"d));
			
			auto lib = s.getParam!(MDNamespace)(1);
	
			lib.addList
			(
				"InputStream"d,  ioLib.inputStreamClass,
				"OutputStream"d, ioLib.outputStreamClass,
				"Stream"d,       ioLib.streamClass,

				"stdin"d,        ioLib.inputStreamClass.nativeClone(Cin.stream),
				"stdout"d,       ioLib.outputStreamClass.nativeClone(Cout.stream),
				"stderr"d,       ioLib.outputStreamClass.nativeClone(Cerr.stream),
	
				"FileMode"d,     MDTable.create
				(
					"In"d,       cast(int)FileMode.In,
					"Out"d,      cast(int)FileMode.Out,
					"New"d,      cast(int)FileMode.New,
					"Append"d,   cast(int)FileMode.Append,
					"OutNew"d,   cast(int)FileMode.OutNew
				),
	
				"File"d,         new MDClosure(lib, &ioLib.File,  "io.File"),
				"rename"d,       new MDClosure(lib, &rename,      "io.rename"),
				"remove"d,       new MDClosure(lib, &remove,      "io.remove"),
				"copy"d,         new MDClosure(lib, &copy,        "io.copy"),
				"size"d,         new MDClosure(lib, &size,        "io.size"),
				"exists"d,       new MDClosure(lib, &exists,      "io.exists"),
				"isFile"d,       new MDClosure(lib, &isFile,      "io.isFile"),
				"isDir"d,        new MDClosure(lib, &isDir,       "io.isDir"),
				"currentDir"d,   new MDClosure(lib, &currentDir,  "io.currentDir"),
				"changeDir"d,    new MDClosure(lib, &changeDir,   "io.changeDir"),
				"makeDir"d,      new MDClosure(lib, &makeDir,     "io.makeDir"),
				"removeDir"d,    new MDClosure(lib, &removeDir,   "io.removeDir"),
				"listFiles"d,    new MDClosure(lib, &listFiles,   "io.listFiles"),
				"listDirs"d,     new MDClosure(lib, &listDirs,    "io.listDirs"),
				"readFile"d,     new MDClosure(lib, &readFile,    "io.readFile"),
				"writeFile"d,    new MDClosure(lib, &writeFile,   "io.writeFile")
			);

			return 0;
		}, "io"));

		context.importModule("io");
	}

	static int rename(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.safeCode(fp.rename(s.getParam!(char[])(1)));
		return 0;
	}

	static int remove(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.safeCode(fp.remove());
		return 0;
	}

	static int copy(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(1));
		s.safeCode(fp.copy(s.getParam!(char[])(0)));
		return 0;
	}

	static int size(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.push(cast(int)s.safeCode(fp.fileSize()));
		return 1;
	}

	static int exists(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.push(cast(bool)fp.exists());
		return 1;
	}

	static int isFile(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.push(s.safeCode(!fp.isFolder()));
		return 1;
	}

	static int isDir(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.push(s.safeCode(fp.isFolder()));
		return 1;
	}

	static int currentDir(MDState s, uint numParams)
	{
		s.push(s.safeCode(FileSystem.getDirectory()));
		return 1;
	}

	static int changeDir(MDState s, uint numParams)
	{
		char[] path = s.getParam!(char[])(0);
		s.safeCode(FileSystem.setDirectory(path));
		return 0;
	}

	static int makeDir(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));

		if(!fp.isAbsolute())
			fp.prepend(FileSystem.getDirectory());

		s.safeCode(fp.create());
		return 0;
	}

	static int removeDir(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.safeCode(fp.remove());
		return 0;
	}

	static int listFiles(MDState s, uint numParams)
	{
		char[] path = s.getParam!(char[])(0);
		char[][] listing;

		if(numParams == 1)
		{
			scope fp = FilePath(path);

			s.safeCode
			({
				foreach(info; fp)
				{
					if(!info.folder)
						listing ~= (info.path ~ info.name);
				}
			}());
		}
		else
		{
			char[] filter = s.getParam!(char[])(1);
			scope fp = FilePath(path);

			s.safeCode
			({
				foreach(info; fp)
				{
					if(!info.folder)
					{
						char[] fullName = info.path ~ info.name;

						if(patternMatch(fullName, filter))
							listing ~= fullName;
					}
				}
			}());
		}

		s.push(MDArray.fromArray(listing));
		return 1;
	}

	static int listDirs(MDState s, uint numParams)
	{
		char[] path = s.getParam!(char[])(0);
		char[][] listing;

		if(numParams == 1)
		{
			scope fp = FilePath(path);

			s.safeCode
			({
				foreach(info; fp)
				{
					if(info.folder)
						listing ~= (info.path ~ info.name);
				}
			}());
		}
		else
		{
			char[] filter = s.getParam!(char[])(1);
			scope fp = FilePath(path);

			s.safeCode
			({
				foreach(info; fp)
				{
					if(info.folder)
					{
						char[] fullName = info.path ~ info.name;

						if(patternMatch(fullName, filter))
							listing ~= fullName;
					}
				}
			}());
		}

		s.push(MDArray.fromArray(listing));
		return 1;
	}

	static int readFile(MDState s, uint numParams)
	{
		auto name = s.getParam!(char[])(0);

		if(numParams == 1 || s.getParam!(bool)(1) == false)
		{
			scope file = s.safeCode(new UnicodeFile!(dchar)(name, Encoding.Unknown));
			s.push(s.safeCode(file.read()));
		}
		else
		{
			scope file = s.safeCode(new .File(name));
			ubyte[] data = s.safeCode(cast(ubyte[])file.read());

			foreach(ref d; data)
				if(d > 0x7f)
					d = '?';

			s.push(new MDString(cast(char[])data));
		}

		return 1;
	}

	static int writeFile(MDState s, uint numParams)
	{
		auto name = s.getParam!(char[])(0);
		auto data = s.getParam!(MDString)(1).mData;
		scope file = s.safeCode(new UnicodeFile!(dchar)(name, Encoding.UTF_8N));
		s.safeCode(file.write(data));
		return 0;
	}

	int File(MDState s, uint numParams)
	{
		FileConduit.Style parseFileMode(int mode)
		{
			FileConduit.Style s = DefaultFileStyle;

			s.access = FileConduit.Access.Read;

			if((mode & FileMode.Out) || (mode & FileMode.Append))
				s.access |= FileConduit.Access.Write;

			s.open = cast(FileConduit.Open)0;

			if(mode & FileMode.New)
				s.open |= FileConduit.Open.Create;
			else
			{
				if(mode & FileMode.Append)
					s.open |= FileConduit.Open.Append;

				s.open |= FileConduit.Open.Exists;
			}

			return s;
		}

		FileConduit f;

		if(numParams == 1)
			f = s.safeCode(new FileConduit(s.getParam!(char[])(0), DefaultFileStyle));
		else
			f = s.safeCode(new FileConduit(s.getParam!(char[])(0), parseFileMode(s.getParam!(int)(1))));

		s.push(streamClass.nativeClone(f));
		return 1;
	}

	static class MDInputStreamClass : MDObject
	{
		private MDClosure mIteratorClosure;

		public this(MDObject owner)
		{
			super("InputStream", owner);

			mIteratorClosure = new MDClosure(fields, &iterator, "InputStream.iterator");

			fields.addList
			(
				"readByte"d,    new MDClosure(fields, &readVal!(ubyte),   "InputStream.readByte"),
				"readShort"d,   new MDClosure(fields, &readVal!(ushort),  "InputStream.readShort"),
				"readInt"d,     new MDClosure(fields, &readVal!(int),     "InputStream.readInt"),
				"readFloat"d,   new MDClosure(fields, &readVal!(float),   "InputStream.readFloat"),
				"readDouble"d,  new MDClosure(fields, &readVal!(double),  "InputStream.readDouble"),
				"readChar"d,    new MDClosure(fields, &readVal!(char),    "InputStream.readChar"),
				"readWChar"d,   new MDClosure(fields, &readVal!(wchar),   "InputStream.readWChar"),
				"readDChar"d,   new MDClosure(fields, &readVal!(dchar),   "InputStream.readDChar"),
				"readString"d,  new MDClosure(fields, &readString,        "InputStream.readString"),
				"readln"d,      new MDClosure(fields, &readln,            "InputStream.readln"),
				"readChars"d,   new MDClosure(fields, &readChars,         "InputStream.readChars"),
				"opApply"d,     new MDClosure(fields, &apply,             "InputStream.opApply")
			);
			
			fields()["clone"d] = MDValue.nullValue;
		}

		package MDInputStream nativeClone(InputStream input)
		{
			return new MDInputStream(this, input);
		}

		public int readVal(T)(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDInputStream)().readVal!(T)()));
			return 1;
		}

		public int readString(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDInputStream).readString()));
			return 1;
		}

		public int readln(MDState s, uint numParams)
		{
			char[] ret = s.safeCode(s.getContext!(MDInputStream).readln());

			if(ret.ptr is null)
				s.throwRuntimeException("Stream has no more data.");

			s.push(s.safeCode(Utf.toString32(ret)));
			return 1;
		}

		public int readChars(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDInputStream).readChars(s.getParam!(int)(0))));
			return 1;
		}

		private int iterator(MDState s, uint numParams)
		{
			int index = s.getParam!(int)(0) + 1;
			auto line = s.safeCode(s.getContext!(MDInputStream).readln());

			if(line.ptr is null)
				return 0;

			auto ret = s.safeCode(Utf.toString32(line));

			s.push(index);
			s.push(ret);

			return 2;
		}

		public int apply(MDState s, uint numParams)
		{
			s.push(mIteratorClosure);
			s.push(s.getContext!(MDInputStream));
			s.push(0);
			return 3;
		}
	}

	static class MDInputStream : MDObject
	{
		private InputStream mInput;
		private Reader mReader;
		private LineIterator!(char) mLines;

		public this(MDInputStreamClass owner, InputStream input)
		{
			super("InputStream", owner);

			mInput = input;
			mReader = new Reader(mInput);
			mLines = new LineIterator!(char)(mInput);
		}

		public T readVal(T)()
		{
			T val;
			mReader.get(val);
			return val;
		}
		
		public dchar[] readString()
		{
			dchar[] s;
			Deserialize(mReader, s);
			return s;
		}

		public char[] readln()
		{
			return mLines.next();
		}

		public MDString readChars(uint length)
		{
			char[] data = new char[length];
			mReader.buffer.readExact(data.ptr, length * char.sizeof);
			return new MDString(data);
		}
	}

	static class MDOutputStreamClass : MDObject
	{
		private Layout!(char) mLayout;
		private MDInputStreamClass mInputStreamClass;
		private MDStreamClass mStreamClass;

		public this(MDObject owner, MDInputStreamClass inputStreamClass, MDStreamClass streamClass)
		{
			super("OutputStream", owner);

			mLayout = new Layout!(char)();
			mInputStreamClass = inputStreamClass;
			mStreamClass = streamClass;

			fields.addList
			(
				"writeByte"d,   new MDClosure(fields, &writeVal!(ubyte),  "OutputStream.writeByte"),
				"writeShort"d,  new MDClosure(fields, &writeVal!(ushort), "OutputStream.writeShort"),
				"writeInt"d,    new MDClosure(fields, &writeVal!(int),    "OutputStream.writeInt"),
				"writeFloat"d,  new MDClosure(fields, &writeVal!(float),  "OutputStream.writeFloat"),
				"writeDouble"d, new MDClosure(fields, &writeVal!(double), "OutputStream.writeDouble"),
				"writeChar"d,   new MDClosure(fields, &writeVal!(char),   "OutputStream.writeChar"),
				"writeWChar"d,  new MDClosure(fields, &writeVal!(wchar),  "OutputStream.writeWChar"),
				"writeDChar"d,  new MDClosure(fields, &writeVal!(dchar),  "OutputStream.writeDChar"),
				"writeString"d, new MDClosure(fields, &writeString,       "OutputStream.writeString"),
				"write"d,       new MDClosure(fields, &write,             "OutputStream.write"),
				"writeln"d,     new MDClosure(fields, &writeln,           "OutputStream.writeln"),
				"writef"d,      new MDClosure(fields, &writef,            "OutputStream.writef"),
				"writefln"d,    new MDClosure(fields, &writefln,          "OutputStream.writefln"),
				"writeChars"d,  new MDClosure(fields, &writeChars,        "OutputStream.writeChars"),
				"writeJSON"d,   new MDClosure(fields, &writeJSON,         "OutputStream.writeJSON"),
				"flush"d,       new MDClosure(fields, &flush,             "OutputStream.flush"),
				"copy"d,        new MDClosure(fields, &copy,              "OutputStream.copy")
			);
			
			fields()["clone"d] = MDValue.nullValue;
		}

		package MDOutputStream nativeClone(OutputStream output)
		{
			return new MDOutputStream(this, output);
		}

		public int writeVal(T)(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDOutputStream)().writeVal!(T)(s.getParam!(T)(0))));
			return 1;
		}

		public int writeString(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDOutputStream).writeString(s.getParam!(dchar[])(0))));
			return 1;
		}

		public int write(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDOutputStream).write(s, s.getAllParams())));
			return 1;
		}

		public int writeln(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDOutputStream).writeln(s, s.getAllParams())));
			return 1;
		}

		public int writef(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDOutputStream).writef(s, s.getAllParams())));
			return 1;
		}

		public int writefln(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDOutputStream).writefln(s, s.getAllParams())));
			return 1;
		}

		public int writeChars(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDOutputStream).writeChars(s.getParam!(char[])(0))));
			return 1;
		}

		public int writeJSON(MDState s, uint numParams)
		{
			bool pretty = false;

			if(numParams > 1)
				pretty = s.getParam!(bool)(1);

			s.push(s.getContext!(MDOutputStream).writeJSON(s, s.getParam(0u), pretty));
			return 1;
		}

		public int flush(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDOutputStream).flush()));
			return 1;
		}
		
		public int copy(MDState s, uint numParams)
		{
			auto o = s.getParam!(MDObject)(0);
			
			InputStream stream;

			if(auto i = cast(MDInputStream)o)
				stream = i.mInput;
			else if(auto s = cast(MDStream)o)
				stream = s.mInput.mInput;
			else
				s.throwRuntimeException("object must be either an InputStream or a Stream, not a '{}'", s.getParam(0u).typeString());

			s.push(s.safeCode(s.getContext!(MDOutputStream).copy(stream)));
			return 1;
		}
	}
	
	static class MDOutputStream : MDObject
	{
		private Layout!(char) mLayout;
		private OutputStream mOutput;
		private Writer mWriter;
		private Print!(char) mPrint;

		public this(MDOutputStreamClass owner, OutputStream output)
		{
			super("OutputStream", owner);

			mLayout = owner.mLayout;
			mOutput = output;
			mWriter = new Writer(mOutput);
			mPrint = new Print!(char)(mLayout, mOutput);
		}

		public MDOutputStream writeVal(T)(T val)
		{
			mWriter.put(val);
			return this;
		}

		public MDOutputStream writeString(dchar[] s)
		{
			Serialize(mWriter, s);
			return this;
		}

		public MDOutputStream write(MDState s, MDValue[] params)
		{
			foreach(ref val; params)
				mPrint.print(s.valueToString(val).mData);
				
			return this;
		}

		public MDOutputStream writeln(MDState s, MDValue[] params)
		{
			foreach(ref val; params)
				mPrint.print(s.valueToString(val).mData);

			mPrint.newline;
			return this;
		}

		public MDOutputStream writef(MDState s, MDValue[] params)
		{
			formatImpl(s, params, (dchar[] data) { mPrint.print(data); return data.length; });
			return this;
		}

		public MDOutputStream writefln(MDState s, MDValue[] params)
		{
			formatImpl(s, params, (dchar[] data) { mPrint.print(data); return data.length; });
			mPrint.newline;
			return this;
		}

		public MDOutputStream writeChars(char[] data)
		{
			mWriter.buffer.append(data.ptr, data.length * char.sizeof);
			return this;
		}

		public MDOutputStream writeJSON(MDState s, MDValue root, bool pretty = false)
		{
			toJSONImpl(s, root, pretty, mPrint);
			return this;
		}

		public MDOutputStream flush()
		{
			mOutput.flush();
			return this;
		}
		
		public MDOutputStream copy(InputStream s)
		{
			mOutput.copy(s);
			return this;
		}
	}

	class MDStreamClass : MDObject
	{
		public this(MDObject owner)
		{
			super("Stream", owner);

			fields.addList
			(
				"readByte"d,    new MDClosure(fields, &readVal!(ubyte),   "Stream.readByte"),
				"readShort"d,   new MDClosure(fields, &readVal!(ushort),  "Stream.readShort"),
				"readInt"d,     new MDClosure(fields, &readVal!(int),     "Stream.readInt"),
				"readFloat"d,   new MDClosure(fields, &readVal!(float),   "Stream.readFloat"),
				"readDouble"d,  new MDClosure(fields, &readVal!(double),  "Stream.readDouble"),
				"readChar"d,    new MDClosure(fields, &readVal!(char),    "Stream.readChar"),
				"readWChar"d,   new MDClosure(fields, &readVal!(wchar),   "Stream.readWChar"),
				"readDChar"d,   new MDClosure(fields, &readVal!(dchar),   "Stream.readDChar"),
				"readString"d,  new MDClosure(fields, &readString,        "Stream.readString"),
				"readln"d,      new MDClosure(fields, &readln,            "Stream.readln"),
				"readChars"d,   new MDClosure(fields, &readChars,         "Stream.readChars"),
				"opApply"d,     new MDClosure(fields, &apply,             "Stream.opApply"),

				"writeByte"d,   new MDClosure(fields, &writeVal!(ubyte),  "Stream.writeByte"),
				"writeShort"d,  new MDClosure(fields, &writeVal!(ushort), "Stream.writeShort"),
				"writeInt"d,    new MDClosure(fields, &writeVal!(int),    "Stream.writeInt"),
				"writeFloat"d,  new MDClosure(fields, &writeVal!(float),  "Stream.writeFloat"),
				"writeDouble"d, new MDClosure(fields, &writeVal!(double), "Stream.writeDouble"),
				"writeChar"d,   new MDClosure(fields, &writeVal!(char),   "Stream.writeChar"),
				"writeWChar"d,  new MDClosure(fields, &writeVal!(wchar),  "Stream.writeWChar"),
				"writeDChar"d,  new MDClosure(fields, &writeVal!(dchar),  "Stream.writeDChar"),
				"writeString"d, new MDClosure(fields, &writeString,       "Stream.writeString"),
				"write"d,       new MDClosure(fields, &write,             "Stream.write"),
				"writeln"d,     new MDClosure(fields, &writeln,           "Stream.writeln"),
				"writef"d,      new MDClosure(fields, &writef,            "Stream.writef"),
				"writefln"d,    new MDClosure(fields, &writefln,          "Stream.writefln"),
				"writeChars"d,  new MDClosure(fields, &writeChars,        "Stream.writeChars"),
				"writeJSON"d,   new MDClosure(fields, &writeJSON,         "Stream.writeJSON"),
				"flush"d,       new MDClosure(fields, &flush,             "Stream.flush"),
				"copy"d,        new MDClosure(fields, &copy,              "Stream.copy"),

				"seek"d,        new MDClosure(fields, &seek,              "Stream.seek"),
				"position"d,    new MDClosure(fields, &position,          "Stream.position"),
				"size"d,        new MDClosure(fields, &size,              "Stream.size"),
				"close"d,       new MDClosure(fields, &close,             "Stream.close"),
				"isOpen"d,      new MDClosure(fields, &isOpen,            "Stream.isOpen"),

				"input"d,       new MDClosure(fields, &input,             "Stream.input"),
				"output"d,      new MDClosure(fields, &output,            "Stream.output")
			);
			
			fields()["clone"d] = MDValue.nullValue;
		}

		protected MDStream nativeClone(IConduit conduit)
		{
			return new MDStream(this, conduit);
		}

		public int readVal(T)(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDStream).mInput.readVal!(T)()));
			return 1;
		}

		public int readString(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDStream).mInput.readString()));
			return 1;
		}
		
		public int readln(MDState s, uint numParams)
		{
			auto self = s.getContext!(MDStream);
			char[] ret = s.safeCode(self.mInput.readln());

			if(ret.ptr is null)
				s.throwRuntimeException("Stream {} has no more data.", self.mConduit);

			s.push(ret);
			return 1;
		}

		public int readChars(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDStream).mInput.readChars(s.getParam!(int)(0))));
			return 1;
		}
		
		public int apply(MDState s, uint numParams)
		{
			s.push(inputStreamClass.mIteratorClosure);
			s.push(s.getContext!(MDStream).mInput);
			s.push(0);
			return 3;
		}

		public int writeVal(T)(MDState s, uint numParams)
		{
			s.safeCode(s.getContext!(MDStream).mOutput.writeVal!(T)(s.getParam!(T)(0)));
			s.push(s.getContext());
			return 1;
		}

		public int writeString(MDState s, uint numParams)
		{
			s.safeCode(s.getContext!(MDStream).mOutput.writeString(s.getParam!(dchar[])(0)));
			s.push(s.getContext());
			return 1;
		}

		public int write(MDState s, uint numParams)
		{
			s.safeCode(s.getContext!(MDStream).mOutput.write(s, s.getAllParams()));
			s.push(s.getContext());
			return 1;
		}

		public int writeln(MDState s, uint numParams)
		{
			s.safeCode(s.getContext!(MDStream).mOutput.writeln(s, s.getAllParams()));
			s.push(s.getContext());
			return 1;
		}

		public int writef(MDState s, uint numParams)
		{
			s.safeCode(s.getContext!(MDStream).mOutput.writef(s, s.getAllParams()));
			s.push(s.getContext());
			return 1;
		}

		public int writefln(MDState s, uint numParams)
		{
			s.safeCode(s.getContext!(MDStream).mOutput.writefln(s, s.getAllParams()));
			s.push(s.getContext());
			return 1;
		}

		public int writeChars(MDState s, uint numParams)
		{
			s.safeCode(s.getContext!(MDStream).mOutput.writeChars(s.getParam!(char[])(0)));
			s.push(s.getContext());
			return 1;
		}

		public int writeJSON(MDState s, uint numParams)
		{
			bool pretty = false;

			if(numParams > 1)
				pretty = s.getParam!(bool)(1);

			s.getContext!(MDStream).mOutput.writeJSON(s, s.getParam(0u), pretty);
			s.push(s.getContext());
			return 1;
		}

		public int flush(MDState s, uint numParams)
		{
			s.safeCode(s.getContext!(MDStream).mOutput.flush());
			s.push(s.getContext());
			return 1;
		}
		
		public int copy(MDState s, uint numParams)
		{
			auto o = s.getParam!(MDObject)(0);

			InputStream stream;

			if(auto i = cast(MDInputStream)o)
				stream = i.mInput;
			else if(auto s = cast(MDStream)o)
				stream = s.mInput.mInput;
			else
				s.throwRuntimeException("object must be either an InputStream or a Stream, not a '{}'", s.getParam(0u).typeString());

			s.safeCode(s.getContext!(MDStream).mOutput.copy(stream));
			s.push(s.getContext());
			return 1;
		}

		public int seek(MDState s, uint numParams)
		{
			auto self = s.getContext!(MDStream);
			int pos = s.getParam!(int)(0);
			dchar whence = s.getParam!(dchar)(1);

			if(whence == 'b')
				s.safeCode(self.seek(pos, IConduit.Seek.Anchor.Begin));
			else if(whence == 'c')
				s.safeCode(self.seek(pos, IConduit.Seek.Anchor.Current));
			else if(whence == 'e')
				s.safeCode(self.seek(pos, IConduit.Seek.Anchor.End));
			else
				s.throwRuntimeException("Invalid seek type '{}'", whence);

			return 0;
		}

		public int position(MDState s, uint numParams)
		{
			if(numParams == 0)
			{
				s.push(s.safeCode(s.getContext!(MDStream).position()));
				return 1;
			}
			else
			{
				s.safeCode(s.getContext!(MDStream).position(s.getParam!(int)(0)));
				return 0;
			}
		}

		public int size(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDStream).size()));
			return 1;
		}

		public int close(MDState s, uint numParams)
		{
			s.safeCode(s.getContext!(MDStream).close());
			return 0;
		}

		public int isOpen(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDStream).isOpen()));
			return 1;
		}

		public int input(MDState s, uint numParams)
		{
			s.push(s.getContext!(MDStream).mInput);
			return 1;
		}
		
		public int output(MDState s, uint numParams)
		{
			s.push(s.getContext!(MDStream).mOutput);
			return 1;
		}
	}
	
	class MDStream : MDObject
	{
		private IConduit mConduit;
		private MDInputStream mInput;
		private MDOutputStream mOutput;
		private IConduit.Seek mSeeker;

		public this(MDStreamClass owner, IConduit conduit)
		{
			super("Stream", owner);

			mConduit = conduit;

			if(auto seeker = cast(IConduit.Seek)conduit)
				mSeeker = seeker;

			mInput = inputStreamClass.nativeClone(conduit);
			mOutput = outputStreamClass.nativeClone(conduit);
		}

		public void seek(int pos, IConduit.Seek.Anchor whence)
		{
			if(mSeeker is null)
				throw new MDException("Stream {} is not seekable.", mConduit);

			mSeeker.seek(pos, whence);
			mInput.mInput.clear();
		}

		public void position(uint pos)
		{
			if(mSeeker is null)
				throw new MDException("Stream {} is not seekable.", mConduit);

			mSeeker.seek(pos, IConduit.Seek.Anchor.Begin);
			mInput.mInput.clear();
		}

		public int position()
		{
			if(mSeeker is null)
				throw new MDException("Stream {} is not seekable.", mConduit);

			return mSeeker.seek(0, IConduit.Seek.Anchor.Current);
		}

		public int size()
		{
			if(mSeeker is null)
				throw new MDException("Stream {} is not seekable.", mConduit);

			ulong pos = mSeeker.seek(0, IConduit.Seek.Anchor.Current);
			ulong ret = mSeeker.seek(0, IConduit.Seek.Anchor.End);
			mSeeker.seek(pos, IConduit.Seek.Anchor.Begin);
			return ret;
		}

		public void close()
		{
			try mOutput.flush(); catch{}
			mConduit.close();
		}

		public bool isOpen()
		{
			return mConduit.isAlive();
		}
	}
}