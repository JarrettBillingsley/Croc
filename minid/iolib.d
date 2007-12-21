/******************************************************************************
License:
Copyright (c) 2007 Jarrett Billingsley

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

import tango.io.Buffer;
import tango.io.Conduit;
import tango.io.Console;
import tango.io.FileConduit;
import tango.io.FilePath;
import tango.io.FileScan;
import tango.io.FileSystem;
import tango.io.model.IConduit;
import tango.io.Print;
import tango.io.protocol.Reader;
import tango.io.protocol.Writer;
import tango.io.Stdout;
import tango.io.UnicodeFile;
import tango.text.convert.Layout;
import tango.text.stream.LineIterator;
import tango.util.PathUtil;

class IOLib
{
	private static IOLib lib;
	private static MDInputStreamClass inputStreamClass;
	private static MDOutputStreamClass outputStreamClass;
	private static MDStreamClass streamClass;
	
	static this()
	{
		lib = new IOLib();
		inputStreamClass = new MDInputStreamClass();
		outputStreamClass = new MDOutputStreamClass();
		streamClass = new MDStreamClass();
	}

	private this()
	{

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
		MDNamespace namespace = new MDNamespace("io"d, context.globals.ns);

		namespace.addList
		(
			"InputStream"d,  lib.inputStreamClass,
			"OutputStream"d, lib.outputStreamClass,
			"Stream"d,       lib.streamClass,

 			"stdin"d,        lib.inputStreamClass.newInstance(Cin.stream),
 			"stdout"d,       lib.outputStreamClass.newInstance(Cout.stream),
 			"stderr"d,       lib.outputStreamClass.newInstance(Cerr.stream),

			"FileMode"d,     MDTable.create
			(
				"In"d,       cast(int)FileMode.In,
				"Out"d,      cast(int)FileMode.Out,
				"New"d,      cast(int)FileMode.New,
				"Append"d,   cast(int)FileMode.Append,
				"OutNew"d,   cast(int)FileMode.OutNew
			),

			"File"d,         new MDClosure(namespace, &lib.File,        "io.File"),
			"rename"d,       new MDClosure(namespace, &lib.rename,      "io.rename"),
			"remove"d,       new MDClosure(namespace, &lib.remove,      "io.remove"),
			"copy"d,         new MDClosure(namespace, &lib.copy,        "io.copy"),
			"size"d,         new MDClosure(namespace, &lib.size,        "io.size"),
			"exists"d,       new MDClosure(namespace, &lib.exists,      "io.exists"),
			"isFile"d,       new MDClosure(namespace, &lib.isFile,      "io.isFile"),
			"isDir"d,        new MDClosure(namespace, &lib.isDir,       "io.isDir"),
			"currentDir"d,   new MDClosure(namespace, &lib.currentDir,  "io.currentDir"),
			"changeDir"d,    new MDClosure(namespace, &lib.changeDir,   "io.changeDir"),
			"makeDir"d,      new MDClosure(namespace, &lib.makeDir,     "io.makeDir"),
			"removeDir"d,    new MDClosure(namespace, &lib.removeDir,   "io.removeDir"),
			"listFiles"d,    new MDClosure(namespace, &lib.listFiles,   "io.listFiles"),
			"listDirs"d,     new MDClosure(namespace, &lib.listDirs,    "io.listDirs"),
			"readFile"d,     new MDClosure(namespace, &lib.readFile,    "io.readFile"),
			"writeFile"d,    new MDClosure(namespace, &lib.writeFile,   "io.writeFile")
		);
		
		context.globals["io"d] = namespace;
	}

	int rename(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.safeCode(fp.rename(s.getParam!(char[])(1)));
		return 0;
	}
	
	int remove(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.safeCode(fp.remove());
		return 0;
	}
	
	int copy(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(1));
		s.safeCode(fp.copy(s.getParam!(char[])(0)));
		return 0;
	}
	
	int size(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.push(cast(int)s.safeCode(fp.fileSize()));
		return 1;
	}
	
	int exists(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.push(cast(bool)fp.exists());
		return 1;
	}
	
	int isFile(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.push(s.safeCode(!fp.isFolder()));
		return 1;
	}

	int isDir(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.push(s.safeCode(fp.isFolder()));
		return 1;
	}
	
	int currentDir(MDState s, uint numParams)
	{
		s.push(s.safeCode(FileSystem.getDirectory()));
		return 1;
	}
	
	int changeDir(MDState s, uint numParams)
	{
		char[] path = s.getParam!(char[])(0);
		s.safeCode(FileSystem.setDirectory(path));
		return 0;
	}
	
	int makeDir(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		
		if(!fp.isAbsolute())
			fp.prepend(FileSystem.getDirectory());

		s.safeCode(fp.create());
		return 0;
	}
	
	int removeDir(MDState s, uint numParams)
	{
		scope fp = FilePath(s.getParam!(char[])(0));
		s.safeCode(fp.remove());
		return 0;
	}
	
	int listFiles(MDState s, uint numParams)
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
	
	int listDirs(MDState s, uint numParams)
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

	int readFile(MDState s, uint numParams)
	{
		auto name = s.getParam!(char[])(0);
		scope file = s.safeCode(new UnicodeFile!(dchar)(name, Encoding.Unknown));
		s.push(s.safeCode(file.read()));
		return 1;
	}
	
	int writeFile(MDState s, uint numParams)
	{
		auto name = s.getParam!(char[])(0);
		auto data = s.getParam!(dchar[])(1);
		scope file = s.safeCode(new UnicodeFile!(dchar)(name, Encoding.UTF_8));
		s.safeCode(file.write(data));
		return 0;
	}

	int File(MDState s, uint numParams)
	{
		FileConduit.Style parseFileMode(int mode)
		{
			FileConduit.Style s;
			s.share = FileConduit.Share.ReadWrite;
			s.cache = FileConduit.Cache.Stream;

			s.access = cast(FileConduit.Access)0;

			if(mode & FileMode.In)
				s.access |= FileConduit.Access.Read;

			if(mode & FileMode.Out)
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
			f = s.safeCode(new FileConduit(s.getParam!(char[])(0)));
		else
			f = s.safeCode(new FileConduit(s.getParam!(char[])(0), parseFileMode(s.getParam!(int)(1))));

		s.push(streamClass.newInstance(f, f));
		return 1;
	}

	static class MDInputStreamClass : MDClass
	{
		private MDClosure mIteratorClosure;

		public this()
		{
			super("InputStream", null);

			mIteratorClosure = new MDClosure(mMethods, &iterator, "InputStream.iterator");

			mMethods.addList
			(
				"readByte"d,    new MDClosure(mMethods, &readVal!(ubyte),   "InputStream.readByte"),
				"readShort"d,   new MDClosure(mMethods, &readVal!(ushort),  "InputStream.readShort"),
				"readInt"d,     new MDClosure(mMethods, &readVal!(int),     "InputStream.readInt"),
				"readFloat"d,   new MDClosure(mMethods, &readVal!(float),   "InputStream.readFloat"),
				"readDouble"d,  new MDClosure(mMethods, &readVal!(double),  "InputStream.readDouble"),
				"readChar"d,    new MDClosure(mMethods, &readVal!(char),    "InputStream.readChar"),
				"readWChar"d,   new MDClosure(mMethods, &readVal!(wchar),   "InputStream.readWChar"),
				"readDChar"d,   new MDClosure(mMethods, &readVal!(dchar),   "InputStream.readDChar"),
				"readString"d,  new MDClosure(mMethods, &readString,        "InputStream.readString"),
				"readln"d,      new MDClosure(mMethods, &readln,            "InputStream.readln"),
// 				"readf"d,       new MDClosure(mMethods, &readf,           	"InputStream.readf"),
				"readChars"d,   new MDClosure(mMethods, &readChars,         "InputStream.readChars"),
				"opApply"d,     new MDClosure(mMethods, &apply,             "InputStream.opApply")
			);
		}

		public override MDInputStream newInstance()
		{
			return new MDInputStream(this);
		}

		protected MDInputStream newInstance(InputStream input)
		{
			MDInputStream n = newInstance();
			n.constructor(input);
			return n;
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

			s.push(ret);
			return 1;
		}

// 		public int readf(MDState s, uint numParams)
// 		{
// 			MDStream i = s.getContext!(MDInputStream);
// 			MDValue[] ret = s.safeCode(baseUnFormat(s, s.getParam!(dchar[])(0), i.mStream));
//
// 			foreach(ref v; ret)
// 				s.push(v);
//
// 			return ret.length;
// 		}

		public int readChars(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDInputStream).readChars(s.getParam!(int)(0))));
			return 1;
		}

		private int iterator(MDState s, uint numParams)
		{
			int index = s.getParam!(int)(0) + 1;
			char[] ret = s.safeCode(s.getContext!(MDInputStream).readln());

			if(ret.ptr is null)
				return 0;

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

	static class MDInputStream : MDInstance
	{
		private InputStream mInput;
		private Reader mReader;
		private LineIterator!(char) mLines;

		public this(MDInputStreamClass owner)
		{
			super(owner);
		}
		
		public void constructor(InputStream input)
		{
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

	static class MDOutputStreamClass : MDClass
	{
		private Layout!(char) mLayout;

		public this()
		{
			super("OutputStream", null);

			mLayout = new Layout!(char)();
			
			mMethods.addList
			(
				"writeByte"d,   new MDClosure(mMethods, &writeVal!(ubyte),  "OutputStream.writeByte"),
				"writeShort"d,  new MDClosure(mMethods, &writeVal!(ushort), "OutputStream.writeShort"),
				"writeInt"d,    new MDClosure(mMethods, &writeVal!(int),    "OutputStream.writeInt"),
				"writeFloat"d,  new MDClosure(mMethods, &writeVal!(float),  "OutputStream.writeFloat"),
				"writeDouble"d, new MDClosure(mMethods, &writeVal!(double), "OutputStream.writeDouble"),
				"writeChar"d,   new MDClosure(mMethods, &writeVal!(char),   "OutputStream.writeChar"),
				"writeWChar"d,  new MDClosure(mMethods, &writeVal!(wchar),  "OutputStream.writeWChar"),
				"writeDChar"d,  new MDClosure(mMethods, &writeVal!(dchar),  "OutputStream.writeDChar"),
				"writeString"d, new MDClosure(mMethods, &writeString,       "OutputStream.writeString"),
				"write"d,       new MDClosure(mMethods, &write,             "OutputStream.write"),
				"writeln"d,     new MDClosure(mMethods, &writeln,           "OutputStream.writeln"),
				"writef"d,      new MDClosure(mMethods, &writef,            "OutputStream.writef"),
				"writefln"d,    new MDClosure(mMethods, &writefln,          "OutputStream.writefln"),
				"writeChars"d,  new MDClosure(mMethods, &writeChars,        "OutputStream.writeChars"),
				"writeJSON"d,   new MDClosure(mMethods, &writeJSON,         "OutputStream.writeJSON"),
				"flush"d,       new MDClosure(mMethods, &flush,             "OutputStream.flush")
			);
		}

		public override MDOutputStream newInstance()
		{
			return new MDOutputStream(this);
		}

		protected MDOutputStream newInstance(OutputStream output)
		{
			MDOutputStream n = newInstance();
			n.constructor(output);
			return n;
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
	}
	
	static class MDOutputStream : MDInstance
	{
		private Layout!(char) mLayout;
		private OutputStream mOutput;
		private Writer mWriter;
		private Print!(char) mPrint;

		public this(MDOutputStreamClass owner)
		{
			super(owner);
			mLayout = owner.mLayout;
		}

		public void constructor(OutputStream output)
		{
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
	}

	static class MDStreamClass : MDClass
	{
		public this()
		{
			super("Stream", null);

			mMethods.addList
			(
				"readByte"d,    new MDClosure(mMethods, &readVal!(ubyte),   "Stream.readByte"),
				"readShort"d,   new MDClosure(mMethods, &readVal!(ushort),  "Stream.readShort"),
				"readInt"d,     new MDClosure(mMethods, &readVal!(int),     "Stream.readInt"),
				"readFloat"d,   new MDClosure(mMethods, &readVal!(float),   "Stream.readFloat"),
				"readDouble"d,  new MDClosure(mMethods, &readVal!(double),  "Stream.readDouble"),
				"readChar"d,    new MDClosure(mMethods, &readVal!(char),    "Stream.readChar"),
				"readWChar"d,   new MDClosure(mMethods, &readVal!(wchar),   "Stream.readWChar"),
				"readDChar"d,   new MDClosure(mMethods, &readVal!(dchar),   "Stream.readDChar"),
				"readString"d,  new MDClosure(mMethods, &readString,        "Stream.readString"),
				"readln"d,      new MDClosure(mMethods, &readln,            "Stream.readln"),
// 				"readf"d,       new MDClosure(mMethods, &readf,             "Stream.readf"),
				"readChars"d,   new MDClosure(mMethods, &readChars,         "Stream.readChars"),
				"opApply"d,     new MDClosure(mMethods, &apply,             "Stream.opApply"),

				"writeByte"d,   new MDClosure(mMethods, &writeVal!(ubyte),  "Stream.writeByte"),
				"writeShort"d,  new MDClosure(mMethods, &writeVal!(ushort), "Stream.writeShort"),
				"writeInt"d,    new MDClosure(mMethods, &writeVal!(int),    "Stream.writeInt"),
				"writeFloat"d,  new MDClosure(mMethods, &writeVal!(float),  "Stream.writeFloat"),
				"writeDouble"d, new MDClosure(mMethods, &writeVal!(double), "Stream.writeDouble"),
				"writeChar"d,   new MDClosure(mMethods, &writeVal!(char),   "Stream.writeChar"),
				"writeWChar"d,  new MDClosure(mMethods, &writeVal!(wchar),  "Stream.writeWChar"),
				"writeDChar"d,  new MDClosure(mMethods, &writeVal!(dchar),  "Stream.writeDChar"),
				"writeString"d, new MDClosure(mMethods, &writeString,       "Stream.writeString"),
				"write"d,       new MDClosure(mMethods, &write,             "Stream.write"),
				"writeln"d,     new MDClosure(mMethods, &writeln,           "Stream.writeln"),
				"writef"d,      new MDClosure(mMethods, &writef,            "Stream.writef"),
				"writefln"d,    new MDClosure(mMethods, &writefln,          "Stream.writefln"),
				"writeChars"d,  new MDClosure(mMethods, &writeChars,        "Stream.writeChars"),
				"writeJSON"d,   new MDClosure(mMethods, &writeJSON,         "Stream.writeJSON"),
				"flush"d,       new MDClosure(mMethods, &flush,             "Stream.flush"),

				"seek"d,        new MDClosure(mMethods, &seek,              "Stream.seek"),
				"position"d,    new MDClosure(mMethods, &position,          "Stream.position"),
				"size"d,        new MDClosure(mMethods, &size,              "Stream.size"),
				"close"d,       new MDClosure(mMethods, &close,             "Stream.close"),
				"isOpen"d,      new MDClosure(mMethods, &isOpen,            "Stream.isOpen"),

				"input"d,       new MDClosure(mMethods, &input,             "Stream.input"),
				"output"d,      new MDClosure(mMethods, &output,            "Stream.output")
			);
		}

		public override MDStream newInstance()
		{
			return new MDStream(this);
		}
		
		protected MDStream newInstance(Conduit conduit, IConduit.Seek seeker = null)
		{
			MDStream n = newInstance();
			n.constructor(conduit, seeker);
			return n;
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

// 		public int readf(MDState s, uint numParams)
// 		{
// 			MDStream i = s.getContext!(MDStream);
// 			MDValue[] ret = s.safeCode(baseUnFormat(s, s.getParam!(dchar[])(0), i.mStream));
// 
// 			foreach(ref v; ret)
// 				s.push(v);
//
// 			return ret.length;
// 		}

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
			s.push(s.safeCode(s.getContext!(MDStream).mOutput.writeVal!(T)(s.getParam!(T)(0))));
			return 1;
		}

		public int writeString(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDStream).mOutput.writeString(s.getParam!(dchar[])(0))));
			return 1;
		}

		public int write(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDStream).mOutput.write(s, s.getAllParams())));
			return 1;
		}

		public int writeln(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDStream).mOutput.writeln(s, s.getAllParams())));
			return 1;
		}

		public int writef(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDStream).mOutput.writef(s, s.getAllParams())));
			return 1;
		}

		public int writefln(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDStream).mOutput.writefln(s, s.getAllParams())));
			return 1;
		}

		public int writeChars(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDStream).mOutput.writeChars(s.getParam!(char[])(0))));
			return 1;
		}

		public int writeJSON(MDState s, uint numParams)
		{
			bool pretty = false;

			if(numParams > 1)
				pretty = s.getParam!(bool)(1);

			s.push(s.getContext!(MDStream).mOutput.writeJSON(s, s.getParam(0u), pretty));
			return 1;
		}
		
		public int flush(MDState s, uint numParams)
		{
			s.push(s.safeCode(s.getContext!(MDStream).mOutput.flush()));
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
	
	static class MDStream : MDInstance
	{
		private Conduit mConduit;
		private MDInputStream mInput;
		private MDOutputStream mOutput;
		private IConduit.Seek mSeeker;

		public this(MDStreamClass owner)
		{
			super(owner);
		}

		public void constructor(Conduit conduit, IConduit.Seek seeker = null)
		{
			mConduit = conduit;
			auto b = new Buffer(mConduit);
			mInput = inputStreamClass.newInstance(b);
			mOutput = outputStreamClass.newInstance(b);
			mSeeker = seeker;
		}

		public void seek(uint pos, IConduit.Seek.Anchor whence)
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

			ulong pos, ret;
			pos = mSeeker.seek(0, IConduit.Seek.Anchor.Current);
			ret = mSeeker.seek(0, IConduit.Seek.Anchor.End);
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