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

import minid.types;
import minid.baselib;
import minid.utils;

import tango.io.Buffer;
import tango.io.FilePath;
import tango.io.FileScan;
import tango.io.FileSystem;
import tango.io.Print;
import tango.io.protocol.Reader;
import tango.io.protocol.Writer;
import tango.io.Stdout;
import tango.text.stream.LineIterator;
import tango.util.PathUtil;

class IOLib
{
	this(MDNamespace namespace)
	{
		//streamClass = new MDStreamClass();

		namespace.addList
		(
			/*"Stream"d,      streamClass,

			"stdin"d,       streamClass.newInstance(din),
			"stdout"d,      streamClass.newInstance(dout),
			"stderr"d,      streamClass.newInstance(derr),

			"FileMode"d,    MDTable.create
			(
				"In"d,      cast(int)FileMode.In,
				"Out"d,     cast(int)FileMode.Out,
				"OutNew"d,  cast(int)FileMode.OutNew,
				"Append"d,  cast(int)FileMode.Append
			),

			"File"d,        new MDClosure(namespace, &file,        "io.File"),*/
			"rename"d,      new MDClosure(namespace, &rename,      "io.rename"),
			"remove"d,      new MDClosure(namespace, &remove,      "io.remove"),
			"copy"d,        new MDClosure(namespace, &copy,        "io.copy"),
			"size"d,        new MDClosure(namespace, &size,        "io.size"),
			"exists"d,      new MDClosure(namespace, &exists,      "io.exists"),
			"isFile"d,      new MDClosure(namespace, &isFile,      "io.isFile"),
			"isDir"d,       new MDClosure(namespace, &isDir,       "io.isDir"),
			"currentDir"d,  new MDClosure(namespace, &currentDir,  "io.currentDir"),
			"changeDir"d,   new MDClosure(namespace, &changeDir,   "io.changeDir"),
			"makeDir"d,     new MDClosure(namespace, &makeDir,     "io.makeDir"),
			"removeDir"d,   new MDClosure(namespace, &removeDir,   "io.removeDir"),
			"listDir"d,     new MDClosure(namespace, &listDir,     "io.listDir")
		);
	}

	int rename(MDState s, uint numParams)
	{
		scope fp = new FilePath(s.getParam!(char[])(0));
		s.safeCode(fp.rename(s.getParam!(char[])(1)));
		return 0;
	}
	
	int remove(MDState s, uint numParams)
	{
		scope fp = new FilePath(s.getParam!(char[])(0));
		s.safeCode(fp.remove());
		return 0;
	}
	
	int copy(MDState s, uint numParams)
	{
		scope fp = new FilePath(s.getParam!(char[])(1));
		s.safeCode(fp.copy(s.getParam!(char[])(0)));
		return 0;
	}
	
	int size(MDState s, uint numParams)
	{
		scope fp = new FilePath(s.getParam!(char[])(0));
		s.push(cast(int)s.safeCode(fp.fileSize()));
		return 1;
	}
	
	int exists(MDState s, uint numParams)
	{
		scope fp = new FilePath(s.getParam!(char[])(0));
		s.push(cast(bool)fp.exists());
		return 1;
	}
	
	int isFile(MDState s, uint numParams)
	{
		scope fp = new FilePath(s.getParam!(char[])(0));
		s.push(s.safeCode(!fp.isFolder()));
		return 1;
	}
	
	int isDir(MDState s, uint numParams)
	{
		scope fp = new FilePath(s.getParam!(char[])(0));
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
		scope fp = new FilePath(s.getParam!(char[])(0), true);
		
		if(!fp.isAbsolute())
			fp.prepend(FileSystem.getDirectory());

		s.safeCode(fp.create());
		return 0;
	}
	
	int removeDir(MDState s, uint numParams)
	{
		scope fp = new FilePath(s.getParam!(char[])(0), true);
		s.safeCode(fp.remove());
		return 0;
	}
	
	int listDir(MDState s, uint numParams)
	{
		char[] path = s.getParam!(char[])(0);
		char[][] listing;

		if(numParams == 1)
		{
			scope fp = new FilePath(path, true);
			listing = s.safeCode(fp.toList());
		}
		else
		{
			char[] filter = s.getParam!(char[])(1);
			scope scan = new FileScan();
			
			s.safeCode(scan(path, (FilePath fp, bool isDir)
			{
				if(isDir)
					return false;

				return patternMatch(fp.toUtf8(), filter);
			}));
			
			foreach(folder; scan.folders)
				listing ~= folder.toUtf8();
				
			foreach(file; scan.files)
				listing ~= file.toUtf8();
		}

		s.push(MDArray.fromArray(listing));
		return 1;
	}
	/*
	int file(MDState s, uint numParams)
	{
		File f;

		try
		{
			if(numParams == 1)
				f = new File(s.getParam!(char[])(0));
			else
				f = new File(s.getParam!(char[])(0), cast(FileMode)s.getParam!(int)(1));
		}
		catch(StreamException e)
		{
			s.throwRuntimeException(e.toUtf8());
		}
		
		s.push(streamClass.newInstance(f));
		return 1;
	}
	
	MDStreamClass streamClass;

	static class MDStreamClass : MDClass
	{
		public this()
		{
			super("Stream", null);
			
			iteratorClosure = new MDClosure(mMethods, &iterator, "Stream.iterator");
			
			mMethods.addList
			(
				"readByte"d,    new MDClosure(mMethods, &read!(ubyte),    "Stream.readByte"),
				"readShort"d,   new MDClosure(mMethods, &read!(ushort),   "Stream.readShort"),
				"readInt"d,     new MDClosure(mMethods, &read!(int),      "Stream.readInt"),
				"readFloat"d,   new MDClosure(mMethods, &read!(float),    "Stream.readFloat"),
				"readDouble"d,  new MDClosure(mMethods, &read!(double),   "Stream.readDouble"),
				"readChar"d,    new MDClosure(mMethods, &read!(char),     "Stream.readChar"),
				"readWChar"d,   new MDClosure(mMethods, &read!(wchar),    "Stream.readWChar"),
				"readDChar"d,   new MDClosure(mMethods, &read!(dchar),    "Stream.readDChar"),
				"readString"d,  new MDClosure(mMethods, &readString,      "Stream.readString"),
				"readLine"d,    new MDClosure(mMethods, &readLine,        "Stream.readLine"),
// 				"readf"d,       new MDClosure(mMethods, &readf,           "Stream.readf"),
				"readChars"d,   new MDClosure(mMethods, &readChars,       "Stream.readChars"),

				"writeByte"d,   new MDClosure(mMethods, &write!(ubyte),   "Stream.writeByte"),
				"writeShort"d,  new MDClosure(mMethods, &write!(ushort),  "Stream.writeShort"),
				"writeInt"d,    new MDClosure(mMethods, &write!(int),     "Stream.writeInt"),
				"writeFloat"d,  new MDClosure(mMethods, &write!(float),   "Stream.writeFloat"),
				"writeDouble"d, new MDClosure(mMethods, &write!(double),  "Stream.writeDouble"),
				"writeChar"d,   new MDClosure(mMethods, &write!(char),    "Stream.writeChar"),
				"writeWChar"d,  new MDClosure(mMethods, &write!(wchar),   "Stream.writeWChar"),
				"writeDChar"d,  new MDClosure(mMethods, &write!(dchar),   "Stream.writeDChar"),
				"writeString"d, new MDClosure(mMethods, &writeString,     "Stream.writeString"),
				"writeLine"d,   new MDClosure(mMethods, &writeLine,       "Stream.writeLine"),
				"writef"d,      new MDClosure(mMethods, &writef,          "Stream.writef"),
				"writefln"d,    new MDClosure(mMethods, &writefln,        "Stream.writefln"),
				"writeChars"d,  new MDClosure(mMethods, &writeChars,      "Stream.writeChars"),

				"available"d,   new MDClosure(mMethods, &available,       "Stream.available"),
				"eof"d,         new MDClosure(mMethods, &eof,             "Stream.eof"),
				"isOpen"d,      new MDClosure(mMethods, &isOpen,          "Stream.isOpen"),
				"flush"d,       new MDClosure(mMethods, &flush,           "Stream.flush"),
				"seek"d,        new MDClosure(mMethods, &seek,            "Stream.seek"),
				"position"d,    new MDClosure(mMethods, &position,        "Stream.position"),
				"size"d,        new MDClosure(mMethods, &size,            "Stream.size"),
				"close"d,       new MDClosure(mMethods, &close,           "Stream.close"),
				"opApply"d,     new MDClosure(mMethods, &apply,           "Stream.opApply")
			);
		}

		public override MDStream newInstance()
		{
			return new MDStream(this);
		}
		
		protected MDStream newInstance(Buffer buffer)
		{
			MDStream n = newInstance();
			n.constructor(buffer);
			return n;
		}

		public int read(T)(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.push(s.safeCode(i.read!(T)()));
			return 1;
		}
		
		public int readString(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.push(s.safeCode(i.readString()));
			return 1;
		}

		public int readLine(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.push(s.safeCode(i.readLine()));
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
			MDStream i = s.getContext!(MDStream);
			s.push(s.safeCode(i.readChars(s.getParam!(int)(0))));
			return 1;
		}
		
		public int write(T)(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.safeCode(i.write!(T)(s.getParam!(T)(0)));
			return 0;
		}
		
		public int writeString(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.safeCode(i.writeString(s.getParam!(dchar[])(0)));
			return 0;
		}

		public int writeLine(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.safeCode(i.writeLine(s.getParam!(char[])(0)));
			return 0;
		}

		public int writef(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.safeCode(i.writef(baseFormat(s, s.getAllParams())));
			return 0;
		}
		
		public int writefln(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.safeCode(i.writefln(baseFormat(s, s.getAllParams())));
			return 0;
		}
		
		public int writeChars(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.safeCode(i.writeChars(s.getParam!(char[])(0)));
			return 0;
		}
		
		public int available(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.push(s.safeCode(i.available()));
			return 1;
		}

		public int eof(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.push(s.safeCode(i.eof()));
			return 1;
		}
		
		public int isOpen(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.push(s.safeCode(i.isOpen()));
			return 1;
		}

		public int flush(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.safeCode(i.flush());
			return 0;
		}
		
		public int seek(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			int pos = s.getParam!(int)(0);
			dchar whence = s.getParam!(dchar)(1);
			
			if(whence == 'b')
				s.safeCode(i.seek(pos, SeekPos.Set));
			else if(whence == 'c')
				s.safeCode(i.seek(pos, SeekPos.Current));
			else if(whence == 'e')
				s.safeCode(i.seek(pos, SeekPos.End));
			else
				s.throwRuntimeException("Invalid seek type '{}'", whence);

			return 0;
		}
		
		public int position(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			
			if(numParams == 0)
			{
				s.push(s.safeCode(i.position()));
				return 1;
			}
			else
			{
				s.safeCode(i.position(s.getParam!(int)(0)));
				return 0;
			}
		}
		
		public int size(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.push(s.safeCode(i.streamSize()));
			return 1;
		}

		public int close(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.safeCode(i.close());
			return 0;
		}
		
		MDClosure iteratorClosure;

		int iterator(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			int index = s.getParam!(int)(0);

			index++;

			if(i.eof())
				return 0;

			s.push(index);
			s.push(s.safeCode(i.readLine()));

			return 2;
		}

		public int apply(MDState s, uint numParams)
		{
			MDStream i = s.getContext!(MDStream);
			s.push(iteratorClosure);
			s.push(i);
			s.push(0);
			return 3;
		}
	}

	static class MDStream : MDInstance
	{
		protected Buffer mBuffer;
		protected Reader mReader;
		protected Writer mWriter;
		protected LineIterator!(dchar) mLines;
		protected Print!(char) mPrint;
		
		public this(MDClass owner)
		{
			super(owner);
		}

		public void constructor(Buffer buffer)
		{
			mBuffer = buffer;
			mReader = new Reader(mBuffer);
			mWriter = new Writer(mBuffer);
			mLines = new LineIterator!(dchar)(mBuffer);
			
			version(Windows)
				mPrint = new Print!(char)(Stdout.layout, mBuffer, "\r\n");
			else
				mPrint = new Print!(char)(Stdout.layout, mBuffer, "\n");
		}
		
		public T read(T)()
		{
			T val;
			mReader.read(val);
			return val;
		}
		
		public dchar[] readString()
		{
			dchar[] s;
			Deserialize(mReader, s);
			return s;
		}

		public char[] readLine()
		{
			return mLines.next();
		}
		
		public MDString readChars(uint length)
		{
			char[] data = new char[length];
			mBuffer.readExact(data.ptr, length * char.sizeof);
			return new MDString(data);
		}

		public void write(T)(T val)
		{
			mWriter.write(val);
		}
		
		public void writeString(dchar[] s)
		{
			Serialize(mWriter, s);
		}

		public void writeLine(char[] val)
		{
			mPrint.print(val);
		}

		public void writef(dchar[] val)
		{
			mStream.writef(val);
		}
		
		public void writefln(dchar[] val)
		{
			mStream.writefln(val);
		}
		
		public void writeChars(char[] data)
		{
			mStream.writeString(data);
		}

		public int available()
		{
			return mStream.available();
		}

		public bool eof()
		{
			return mStream.eof();
		}
		
		public bool isOpen()
		{
			return mStream.isOpen();
		}
		
		public void flush()
		{
			mStream.flush();
		}
		
		public void seek(uint pos, SeekPos whence)
		{
			mStream.seek(pos, whence);
		}
		
		public void position(uint pos)
		{
			mStream.position = pos;
		}
		
		public int position()
		{
			return mStream.position;
		}
		
		public int streamSize()
		{
			return mStream.size();
		}

		public void close()
		{
			mStream.close();
		}
	}*/
}

public void init()
{
	MDNamespace namespace = new MDNamespace("io"d, MDGlobalState().globals.ns);
	new IOLib(namespace);
	MDGlobalState().globals["io"d] = namespace;
}