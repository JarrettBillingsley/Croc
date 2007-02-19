module minid.iolib;

import minid.types;
import minid.baselib;

import std.file;
import std.stream;

class IOLib
{
	this(MDNamespace namespace)
	{
		fileClass = new MDFileClass();

		namespace.addList
		(
			"File",        fileClass,
			"FileMode",    MDTable.create
			(
				"In",     cast(int)FileMode.In,
				"Out",    cast(int)FileMode.Out,
				"OutNew", cast(int)FileMode.OutNew,
				"Append", cast(int)FileMode.Append
			),

			"rename",      new MDClosure(namespace, &rename,      "io.rename"),
			"remove",      new MDClosure(namespace, &remove,      "io.remove"),
			"copy",        new MDClosure(namespace, &copy,        "io.copy"),
			"size",        new MDClosure(namespace, &size,        "io.size"),
			"exists",      new MDClosure(namespace, &exists,      "io.exists"),
			"isFile",      new MDClosure(namespace, &isFile,      "io.isFile"),
			"isDir",       new MDClosure(namespace, &isDir,       "io.isDir"),
			"currentDir",  new MDClosure(namespace, &currentDir,  "io.currentDir"),
			"changeDir",   new MDClosure(namespace, &changeDir,   "io.changeDir"),
			"makeDir",     new MDClosure(namespace, &makeDir,     "io.makeDir"),
			"removeDir",   new MDClosure(namespace, &removeDir,   "io.removeDir")
		);
	}

	int rename(MDState s)
	{
		char[] file = s.getStringParam(0).asUTF8();
		char[] newName = s.getStringParam(1).asUTF8();
		
		s.safeCode(std.file.rename(file, newName));

		return 0;
	}
	
	int remove(MDState s)
	{
		char[] file = s.getStringParam(0).asUTF8();

		s.safeCode(std.file.remove(file));

		return 0;
	}
	
	int copy(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		char[] dest = s.getStringParam(1).asUTF8();

		s.safeCode(std.file.copy(src, dest));

		return 0;
	}
	
	int size(MDState s)
	{
		char[] file = s.getStringParam(0).asUTF8();
		ulong ret = s.safeCode(std.file.getSize(file));

		s.push(cast(int)ret);
		return 1;
	}
	
	int exists(MDState s)
	{
		s.push(cast(bool)std.file.exists(s.getStringParam(0).asUTF8()));
		return 1;
	}
	
	int isFile(MDState s)
	{
		char[] file = s.getStringParam(0).asUTF8();
		s.push(s.safeCode(cast(bool)std.file.isfile(file)));
		return 1;
	}
	
	int isDir(MDState s)
	{
		char[] file = s.getStringParam(0).asUTF8();
		s.push(s.safeCode(cast(bool)std.file.isdir(file)));
		return 1;
	}
	
	int currentDir(MDState s)
	{
		char[] ret = s.safeCode(std.file.getcwd());
		s.push(ret);

		return 1;
	}
	
	int changeDir(MDState s)
	{
		char[] path = s.getStringParam(0).asUTF8();
		s.safeCode(std.file.chdir(path));

		return 0;
	}
	
	int makeDir(MDState s)
	{
		char[] path = s.getStringParam(0).asUTF8();
		s.safeCode(std.file.mkdir(path));

		return 0;
	}
	
	int removeDir(MDState s)
	{
		char[] path = s.getStringParam(0).asUTF8();
		s.safeCode(std.file.rmdir(path));

		return 0;
	}
	
	MDFileClass fileClass;

	static class MDFileClass : MDClass
	{
		public this()
		{
			super("File", null);
			
			mMethods.addList
			(
				"constructor"d, new MDClosure(mMethods, &constructor,    "File.constructor"),
				"readByte"d,    new MDClosure(mMethods, &read!(ubyte),   "File.readByte"),
				"readShort"d,   new MDClosure(mMethods, &read!(ushort),  "File.readShort"),
				"readInt"d,     new MDClosure(mMethods, &read!(int),     "File.readInt"),
				"readFloat"d,   new MDClosure(mMethods, &read!(float),   "File.readFloat"),
				"readChar"d,    new MDClosure(mMethods, &read!(char),    "File.readChar"),
				"readWChar"d,   new MDClosure(mMethods, &read!(wchar),   "File.readWChar"),
				"readDChar"d,   new MDClosure(mMethods, &read!(dchar),   "File.readDChar"),
				"readLine"d,    new MDClosure(mMethods, &readLine,       "File.readLine"),
				"eof"d,         new MDClosure(mMethods, &eof,            "File.eof"),
				"writeByte"d,   new MDClosure(mMethods, &write!(ubyte),  "File.writeByte"),
				"writeShort"d,  new MDClosure(mMethods, &write!(ushort), "File.writeShort"),
				"writeInt"d,    new MDClosure(mMethods, &write!(int),    "File.writeInt"),
				"writeFloat"d,  new MDClosure(mMethods, &write!(float),  "File.writeFloat"),
				"writeChar"d,   new MDClosure(mMethods, &write!(char),   "File.writeChar"),
				"writeWChar"d,  new MDClosure(mMethods, &write!(wchar),  "File.writeWChar"),
				"writeDChar"d,  new MDClosure(mMethods, &write!(dchar),  "File.writeDChar"),
				"writeLine"d,   new MDClosure(mMethods, &writeLine,      "File.writeLine"),
				"writef"d,      new MDClosure(mMethods, &writef,         "File.writef"),
				"writefln"d,    new MDClosure(mMethods, &writefln,       "File.writefln"),
				"close"d,       new MDClosure(mMethods, &close,          "File.close")
			);
		}

		public override MDFile newInstance()
		{
			MDFile n = new MDFile();
			n.mClass = this;

			foreach(k, v; mFields)
				n.mFields[k] = v;

			n.mMethods = mMethods;

			return n;
		}

		public int constructor(MDState s)
		{
			MDFile i = cast(MDFile)s.getContext().asInstance();

			try
			{
				if(s.numParams() == 1)
					i.constructor(s.getStringParam(0).asUTF8());
				else
					i.constructor(s.getStringParam(0).asUTF8(), cast(FileMode)s.getIntParam(1));
			}
			catch(StreamException e)
			{
				s.throwRuntimeException(e.toString());
			}

			return 0;
		}

		public int read(T)(MDState s)
		{
			MDFile i = cast(MDFile)s.getContext().asInstance();

			T val = s.safeCode(i.read!(T)());

			s.push(val);
			return 1;
		}

		public int readLine(MDState s)
		{
			MDFile i = cast(MDFile)s.getContext().asInstance();

			char[] val = s.safeCode(i.readLine());

			s.push(val);
			return 1;
		}
		
		public int write(T)(MDState s)
		{
			MDFile i = cast(MDFile)s.getContext().asInstance();

			T val;
			
			static if(is(T == ubyte) || is(T == ushort) || is(T == int))
				val = s.getIntParam(0);
			else static if(is(T == float))
				val = s.getFloatParam(0);
			else static if(is(T == char) || is(T == wchar) || is(T == dchar))
				val = s.getCharParam(0);

			s.safeCode(i.write!(T)(val));

			return 0;
		}

		public int writeLine(MDState s)
		{
			MDFile i = cast(MDFile)s.getContext().asInstance();
			char[] val = s.getStringParam(0).asUTF8();
			
			s.safeCode(i.writeLine(val));

			return 0;
		}

		public int writef(MDState s)
		{
			MDFile i = cast(MDFile)s.getContext().asInstance();
			dchar[] output = baseFormat(s, s.getAllParams());
			
			s.safeCode(i.writef(output));

			return 0;
		}
		
		public int writefln(MDState s)
		{
			MDFile i = cast(MDFile)s.getContext().asInstance();
			dchar[] output = baseFormat(s, s.getAllParams());
			
			s.safeCode(i.writefln(output));

			return 0;
		}

		public int eof(MDState s)
		{
			MDFile i = cast(MDFile)s.getContext().asInstance();
			s.push(i.eof());
			return 1;
		}
		
		public int close(MDState s)
		{
			MDFile i = cast(MDFile)s.getContext().asInstance();
			i.close();
			return 0;
		}
	}

	static class MDFile : MDInstance
	{
		protected File mFile;

		public void constructor(char[] filename, FileMode mode = FileMode.In)
		{
			mFile = new File(filename, mode);
		}
		
		public T read(T)()
		{
			T val;
			mFile.read(val);
			return val;
		}
		
		public char[] readLine()
		{
			return mFile.readLine();
		}
		
		public void write(T)(T val)
		{
			mFile.write(val);
		}
		
		public void writeLine(char[] val)
		{
			mFile.writeLine(val);
		}
		
		public void writef(dchar[] val)
		{
			mFile.writef(val);
		}
		
		public void writefln(dchar[] val)
		{
			mFile.writefln(val);
		}

		public bool eof()
		{
			return mFile.eof();
		}
		
		public void close()
		{
			mFile.close();
		}
	}
}

public void init()
{
	MDNamespace namespace = new MDNamespace("io"d, MDGlobalState().globals);
	new IOLib(namespace);
	MDGlobalState().setGlobal("io"d, namespace);
}