module minid.iolib;

import minid.state;
import minid.types;
import minid.baselib;

import std.file;
import std.stream;

class IOLib
{
	int rename(MDState s)
	{
		char[] file = s.getStringParam(0).asUTF8();
		char[] newName = s.getStringParam(1).asUTF8();
		
		try
		{
			std.file.rename(file, newName);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}
		
		return 0;
	}
	
	int remove(MDState s)
	{
		char[] file = s.getStringParam(0).asUTF8();

		try
		{
			std.file.remove(file);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}
		
		return 0;
	}
	
	int copy(MDState s)
	{
		char[] src = s.getStringParam(0).asUTF8();
		char[] dest = s.getStringParam(1).asUTF8();

		try
		{
			std.file.copy(src, dest);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}
		
		return 0;
	}
	
	int size(MDState s)
	{
		char[] file = s.getStringParam(0).asUTF8();
		ulong ret = 0;

		try
		{
			ret = std.file.getSize(file);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(cast(int)ret);
		return 1;
	}
	
	int exists(MDState s)
	{
		s.push(std.file.exists(s.getStringParam(0).asUTF8()));
		return 1;
	}
	
	int isFile(MDState s)
	{
		char[] file = s.getStringParam(0).asUTF8();
		bool ret = false;

		try
		{
			ret = cast(bool)std.file.isfile(file);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(ret);
		return 1;
	}
	
	int isDir(MDState s)
	{
		char[] file = s.getStringParam(0).asUTF8();
		bool ret = false;

		try
		{
			ret = cast(bool)std.file.isdir(file);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(ret);
		return 1;
	}
	
	int currentDir(MDState s)
	{
		char[] ret;

		try
		{
			ret = std.file.getcwd();
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		s.push(ret);
		return 1;
	}
	
	int changeDir(MDState s)
	{
		char[] path = s.getStringParam(0).asUTF8();

		try
		{
			std.file.chdir(path);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		return 0;
	}
	
	int makeDir(MDState s)
	{
		char[] path = s.getStringParam(0).asUTF8();

		try
		{
			std.file.mkdir(path);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		return 0;
	}
	
	int removeDir(MDState s)
	{
		char[] path = s.getStringParam(0).asUTF8();

		try
		{
			std.file.rmdir(path);
		}
		catch(Exception e)
		{
			throw new MDRuntimeException(s, e.toString());
		}

		return 0;
	}
	
	MDFileClass fileClass;
	
	/*wrappedClass!(MDFile) f;
	f.def!(MDFile.readByte);
	f.def!(MDFile.readShort);
	...
	f.init!(void function(char[], int));
	s.finalizeClass(f);*/

	static class MDFileClass : MDClass
	{
		public this(MDState s)
		{
			super(s, "File", null);
			
			this["constructor"] = new MDClosure(s, &constructor,    "File.constructor");
			this["readByte"] =    new MDClosure(s, &read!(ubyte),   "File.readByte");
			this["readShort"] =   new MDClosure(s, &read!(ushort),  "File.readShort");
			this["readInt"] =     new MDClosure(s, &read!(int),     "File.readInt");
			this["readFloat"] =   new MDClosure(s, &read!(float),   "File.readFloat");
			this["readChar"] =    new MDClosure(s, &read!(char),    "File.readChar");
			this["readWChar"] =   new MDClosure(s, &read!(wchar),   "File.readWChar");
			this["readDChar"] =   new MDClosure(s, &read!(dchar),   "File.readDChar");
			this["readLine"] =    new MDClosure(s, &readLine,       "File.readLine");
			this["eof"] =         new MDClosure(s, &eof,            "File.eof");
			this["writeByte"] =   new MDClosure(s, &write!(ubyte),  "File.writeByte");
			this["writeShort"] =  new MDClosure(s, &write!(ushort), "File.writeShort");
			this["writeInt"] =    new MDClosure(s, &write!(int),    "File.writeInt");
			this["writeFloat"] =  new MDClosure(s, &write!(float),  "File.writeFloat");
			this["writeChar"] =   new MDClosure(s, &write!(char),   "File.writeChar");
			this["writeWChar"] =  new MDClosure(s, &write!(wchar),  "File.writeWChar");
			this["writeDChar"] =  new MDClosure(s, &write!(dchar),  "File.writeDChar");
			this["writeLine"] =   new MDClosure(s, &writeLine,      "File.writeLine");
			this["writef"] =      new MDClosure(s, &writef,         "File.writef");
			this["writefln"] =    new MDClosure(s, &writefln,       "File.writefln");
			this["close"] =       new MDClosure(s, &close,          "File.close");
		}

		public override MDFile newInstance()
		{
			MDFile n = new MDFile();
			n.mClass = this;
			//n.mFields = mFields.dup;
			
			foreach(k, v; mFields)
				n.mFields[k] = v;

			n.mMethods = mMethods;

			return n;
		}

		public int constructor(MDState s)
		{
			MDFile i = cast(MDFile)s.getInstanceParam(0, this);

			try
			{
				if(s.numParams() == 2)
					i.constructor(s.getStringParam(1).asUTF8());
				else
					i.constructor(s.getStringParam(1).asUTF8(), cast(FileMode)s.getIntParam(2));
			}
			catch(StreamException e)
			{
				throw new MDRuntimeException(s, e.toString());
			}

			return 0;
		}

		public int read(T)(MDState s)
		{
			MDFile i = cast(MDFile)s.getInstanceParam(0, this);

			T val;
			
			try
			{
				val = i.read!(T)();
			}
			catch(StreamException e)
			{
				throw new MDRuntimeException(s, e.toString());
			}

			s.push(val);
			return 1;
		}

		public int readLine(MDState s)
		{
			MDFile i = cast(MDFile)s.getInstanceParam(0, this);

			char[] val;
			
			try
			{
				val = i.readLine();
			}
			catch(StreamException e)
			{
				throw new MDRuntimeException(s, e.toString());
			}
			
			s.push(val);
			return 1;
		}
		
		public int write(T)(MDState s)
		{
			MDFile i = cast(MDFile)s.getInstanceParam(0, this);

			T val;
			
			static if(is(T == ubyte) || is(T == ushort) || is(T == int))
				val = s.getIntParam(1);
			else static if(is(T == float))
				val = s.getFloatParam(1);
			else static if(is(T == char) || is(T == wchar) || is(T == dchar))
				val = s.getCharParam(1);

			try
			{
				i.write!(T)(val);
			}
			catch(StreamException e)
			{
				throw new MDRuntimeException(s, e.toString());
			}

			return 0;
		}

		public int writeLine(MDState s)
		{
			MDFile i = cast(MDFile)s.getInstanceParam(0, this);
			char[] val = s.getStringParam(1).asUTF8();
			
			try
			{
				i.writeLine(val);
			}
			catch(StreamException e)
			{
				throw new MDRuntimeException(s, e.toString());
			}

			return 0;
		}

		public int writef(MDState s)
		{
			MDFile i = cast(MDFile)s.getInstanceParam(0, this);
			dchar[] output = baseFormat(s, s.getParams(1, -1));
			
			try
			{
				i.writef(output);
			}
			catch(StreamException e)
			{
				throw new MDRuntimeException(s, e.toString());
			}

			return 0;
		}
		
		public int writefln(MDState s)
		{
			MDFile i = cast(MDFile)s.getInstanceParam(0, this);
			dchar[] output = baseFormat(s, s.getParams(1, -1));
			
			try
			{
				i.writefln(output);
			}
			catch(StreamException e)
			{
				throw new MDRuntimeException(s, e.toString());
			}

			return 0;
		}

		public int eof(MDState s)
		{
			MDFile i = cast(MDFile)s.getInstanceParam(0, this);
			s.push(i.eof());
			return 1;
		}
		
		public int close(MDState s)
		{
			MDFile i = cast(MDFile)s.getInstanceParam(0, this);
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

public void init(MDState s)
{
	IOLib lib = new IOLib();
	
	lib.fileClass = new IOLib.MDFileClass(s);

	MDTable ioTable = MDTable.create
	(
		"File",        lib.fileClass,
		"FileMode",    MDTable.create
		(
			"In",     cast(int)FileMode.In,
			"Out",    cast(int)FileMode.Out,
			"OutNew", cast(int)FileMode.OutNew,
			"Append", cast(int)FileMode.Append
		),
		"rename",      new MDClosure(s, &lib.rename,      "io.rename"),
		"remove",      new MDClosure(s, &lib.remove,      "io.remove"),
		"copy",        new MDClosure(s, &lib.copy,        "io.copy"),
		"size",        new MDClosure(s, &lib.size,        "io.size"),
		"exists",      new MDClosure(s, &lib.exists,      "io.exists"),
		"isFile",      new MDClosure(s, &lib.isFile,      "io.isFile"),
		"isDir",       new MDClosure(s, &lib.isDir,       "io.isDir"),
		"currentDir",  new MDClosure(s, &lib.currentDir,  "io.currentDir"),
		"changeDir",   new MDClosure(s, &lib.changeDir,   "io.changeDir"),
		"makeDir",     new MDClosure(s, &lib.makeDir,     "io.makeDir"),
		"removeDir",   new MDClosure(s, &lib.removeDir,   "io.removeDir")
	);

	s.setGlobal("io"d, ioTable);
}