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

import tango.io.device.FileConduit;
import tango.io.File;
import tango.io.FileSystem;
import tango.io.UnicodeFile;
import tango.util.PathUtil;

import minid.ex;
import minid.interpreter;
import minid.streamlib;
import minid.types;

struct IOLib
{
static:
	private const FileConduit.Style DefaultFileStyle;

	static this()
	{
		DefaultFileStyle = FileConduit.Style
		(
			FileConduit.Access.Read,
			FileConduit.ReadExisting.open,
			FileConduit.Share.ReadWrite,
			FileConduit.ReadExisting.cache
		);
	}

	enum FileMode : mdint
	{
		In = 1,
		Out = 2,
		New = 4,
		Append = 8,
		OutNew = Out | New
	}

	public void init(MDThread* t)
	{
		pushGlobal(t, "modules");
		field(t, -1, "customLoaders");

		newFunction(t, function uword(MDThread* t, uword numParams)
		{
			importModule(t, "stream");
			pop(t);
			
			lookup(t, "stream.stdin");
			newGlobal(t, "stdin");

			lookup(t, "stream.stdout");
			newGlobal(t, "stdout");

			lookup(t, "stream.stderr");
			newGlobal(t, "stderr");

			newTable(t, 5);
				pushString(t, "In");     pushInt(t, FileMode.In);     fielda(t, -3);
				pushString(t, "Out");    pushInt(t, FileMode.Out);    fielda(t, -3);
				pushString(t, "New");    pushInt(t, FileMode.New);    fielda(t, -3);
				pushString(t, "Append"); pushInt(t, FileMode.Append); fielda(t, -3);
				pushString(t, "OutNew"); pushInt(t, FileMode.OutNew); fielda(t, -3);
			newGlobal(t, "FileMode");

			newFunction(t, &File, "File");             newGlobal(t, "File");
			newFunction(t, &rename, "rename");         newGlobal(t, "rename");
			newFunction(t, &remove, "remove");         newGlobal(t, "remove");
			newFunction(t, &copy, "copy");             newGlobal(t, "copy");
			newFunction(t, &size, "size");             newGlobal(t, "size");
			newFunction(t, &exists, "exists");         newGlobal(t, "exists");
			newFunction(t, &isFile, "isFile");         newGlobal(t, "isFile");
			newFunction(t, &isDir, "isDir");           newGlobal(t, "isDir");
			newFunction(t, &currentDir, "currentDir"); newGlobal(t, "currentDir");
			newFunction(t, &changeDir, "changeDir");   newGlobal(t, "changeDir");
			newFunction(t, &makeDir, "makeDir");       newGlobal(t, "makeDir");
			newFunction(t, &removeDir, "removeDir");   newGlobal(t, "removeDir");
			newFunction(t, &listFiles, "listFiles");   newGlobal(t, "listFiles");
			newFunction(t, &listDirs, "listDirs");     newGlobal(t, "listDirs");
			newFunction(t, &readFile, "readFile");     newGlobal(t, "readFile");
			newFunction(t, &writeFile, "writeFile");   newGlobal(t, "writeFile");

				newFunction(t, &linesIterator, "linesIterator");
			newFunction(t, &lines, "lines", 1);        newGlobal(t, "lines");

			return 0;
		}, "io");

		fielda(t, -2, "io");
		importModule(t, "io");
		pop(t, 3);
	}

	uword rename(MDThread* t, uword numParams)
	{
		scope fp = new FilePath(checkStringParam(t, 1));
		safeCode(t, fp.rename(checkStringParam(t, 2)));
		return 0;
	}

	uword remove(MDThread* t, uword numParams)
	{
		scope fp = new FilePath(checkStringParam(t, 1));
		safeCode(t, fp.remove());
		return 0;
	}

	uword copy(MDThread* t, uword numParams)
	{
		scope fp = new FilePath(checkStringParam(t, 2));
		safeCode(t, fp.copy(checkStringParam(t, 1)));
		return 0;
	}

	uword size(MDThread* t, uword numParams)
	{
		scope fp = new FilePath(checkStringParam(t, 1));
		pushInt(t, cast(mdint)safeCode(t, fp.fileSize()));
		return 1;
	}

	uword exists(MDThread* t, uword numParams)
	{
		scope fp = new FilePath(checkStringParam(t, 1));
		pushBool(t, fp.exists());
		return 1;
	}

	uword isFile(MDThread* t, uword numParams)
	{
		scope fp = new FilePath(checkStringParam(t, 1));
		pushBool(t, safeCode(t, !fp.isFolder()));
		return 1;
	}

	uword isDir(MDThread* t, uword numParams)
	{
		scope fp = new FilePath(checkStringParam(t, 1));
		pushBool(t, safeCode(t, !fp.isFolder()));
		return 1;
	}

	uword currentDir(MDThread* t, uword numParams)
	{
		pushString(t, safeCode(t, FileSystem.getDirectory()));
		return 1;
	}

	uword changeDir(MDThread* t, uword numParams)
	{
		safeCode(t, FileSystem.setDirectory(checkStringParam(t, 1)));
		return 0;
	}

	uword makeDir(MDThread* t, uword numParams)
	{
		scope fp = new FilePath(checkStringParam(t, 1));

		if(!fp.isAbsolute())
			fp.prepend(FileSystem.getDirectory());

		safeCode(t, fp.create());
		return 0;
	}

	uword removeDir(MDThread* t, uword numParams)
	{
		scope fp = new FilePath(checkStringParam(t, 1));
		safeCode(t, fp.remove());
		return 0;
	}
	
	uword listImpl(MDThread* t, uword numParams, bool isFolder)
	{
		scope fp = new FilePath(checkStringParam(t, 1));
		auto listing = newArray(t, 0);

		if(numParams == 1)
		{
			safeCode(t,
			{
				foreach(ref info; fp)
				{
					if(info.folder is isFolder)
					{
						pushString(t, info.path);
						pushString(t, info.name);
						cat(t, 2);
						cateq(t, listing, 1);
					}
				}
			}());
		}
		else
		{
			auto filter = checkStringParam(t, 2);

			safeCode(t,
			{
				foreach(ref info; fp)
				{
					if(info.folder is isFolder)
					{
						pushString(t, info.path);
						pushString(t, info.name);
						cat(t, 2);
						auto fullName = getString(t, -1);
						
						if(patternMatch(fullName, filter))
							cateq(t, listing, 1);
						else
							pop(t);
					}
				}
			}());
		}

		return 1;
	}

	uword listFiles(MDThread* t, uword numParams)
	{
		return listImpl(t, numParams, false);
	}

	uword listDirs(MDThread* t, uword numParams)
	{
		return listImpl(t, numParams, true);
	}

	uword readFile(MDThread* t, uword numParams)
	{
		auto name = checkStringParam(t, 1);

		if(numParams == 1 || checkBoolParam(t, 2) == false)
		{
			safeCode(t,
			{
				scope file = new UnicodeFile!(char)(name, Encoding.Unknown);
				pushString(t, file.read());
			}());
		}
		else
		{
			safeCode(t,
			{
				scope file = new .File(name);
				auto data = cast(ubyte[])file.read();

				scope(exit)
					delete data;

				foreach(ref c; data)
					if(c > 0x7f)
						c = '?';

				pushString(t, cast(char[])data);
			}());
		}

		return 1;
	}

	uword writeFile(MDThread* t, uword numParams)
	{
		auto name = checkStringParam(t, 1);
		auto data = checkStringParam(t, 2);

		safeCode(t,
		{
			scope file = new UnicodeFile!(char)(name, Encoding.UTF_8N);
			file.write(data);
		}());

		return 0;
	}
	
	uword linesIterator(MDThread* t, uword numParams)
	{
		getExtraVal(t, 0, StreamObj.Fields.input);
		auto lines = (cast(InputStreamObj.Members*)getExtraBytes(t, -1).ptr).lines;

		auto index = checkIntParam(t, 1) + 1;
		auto line = safeCode(t, lines.next());

		if(line.ptr is null)
		{
			dup(t, 0);
			pushNull(t);
			methodCall(t, -2, "close", 0);
			return 0;
		}

		pushInt(t, index);
		pushString(t, line);
		return 2;
	}

	uword lines(MDThread* t, uword numParams)
	{
		auto name = checkStringParam(t, 1);
		
		pushGlobal(t, "File");
		pushNull(t);
		pushString(t, name);
		rawCall(t, -3, 1);
		
		pushInt(t, 0);
		getUpval(t, 0);
		
		return 3;
	}

	uword File(MDThread* t, uword numParams)
	{
		FileConduit.Style parseFileMode(mdint mode)
		{
			auto s = DefaultFileStyle;

			s.access = FileConduit.Access.Read;

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

		safeCode(t,
		{
			auto name = checkStringParam(t, 1);

			auto f = numParams == 1
				? new FileConduit(name, DefaultFileStyle)
				: new FileConduit(name, parseFileMode(checkIntParam(t, 2)));
				
			lookup(t, "stream.Stream");
			pushNull(t);
			pushNativeObj(t, f);
			rawCall(t, -3, 1);
		}());

		return 1;
	}
}