/******************************************************************************
This module contains the 'io' standard library.

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

import Path = tango.io.Path;
import tango.io.device.File;
import tango.io.FileSystem;
import tango.io.UnicodeFile;
import tango.util.PathUtil;

import minid.ex;
import minid.interpreter;
import minid.streamlib;
import minid.types;
import minid.vector;

struct IOLib
{
static:
// 	private const .File.Style DefaultFileStyle;
// 
// 	static this()
// 	{
// 		DefaultFileStyle = .File.Style
// 		(
// 			.File.Access.Read,
// 			.File.Open.Exists,
// 			.File.Share.ReadWrite,
// 			.File.Cache.None
// 		);
// 	}
// 
// 	enum FileMode : mdint
// 	{
// 		In = 1,
// 		Out = 2,
// 		New = 4,
// 		Append = 8,
// 		OutNew = Out | New
// 	}

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

// 			newTable(t, 5);
// 				pushInt(t, FileMode.In);     fielda(t, -2, "In");
// 				pushInt(t, FileMode.Out);    fielda(t, -2, "Out");
// 				pushInt(t, FileMode.New);    fielda(t, -2, "New");
// 				pushInt(t, FileMode.Append); fielda(t, -2, "Append");
// 				pushInt(t, FileMode.OutNew); fielda(t, -2, "OutNew");
// 			newGlobal(t, "FileMode");

// 			newFunction(t, &File, "File");                 newGlobal(t, "File");
			newFunction(t, &inFile,       "inFile");       newGlobal(t, "inFile");
			newFunction(t, &outFile,      "outFile");      newGlobal(t, "outFile");
			newFunction(t, &rename,       "rename");       newGlobal(t, "rename");
			newFunction(t, &remove,       "remove");       newGlobal(t, "remove");
			newFunction(t, &copy,         "copy");         newGlobal(t, "copy");
			newFunction(t, &size,         "size");         newGlobal(t, "size");
			newFunction(t, &exists,       "exists");       newGlobal(t, "exists");
			newFunction(t, &isFile,       "isFile");       newGlobal(t, "isFile");
			newFunction(t, &isDir,        "isDir");        newGlobal(t, "isDir");
			newFunction(t, &isReadOnly,   "isReadOnly");   newGlobal(t, "isReadOnly");
			newFunction(t, &currentDir,   "currentDir");   newGlobal(t, "currentDir");
			newFunction(t, &parentDir,    "parentDir");    newGlobal(t, "parentDir");
			newFunction(t, &changeDir,    "changeDir");    newGlobal(t, "changeDir");
			newFunction(t, &makeDir,      "makeDir");      newGlobal(t, "makeDir");
			newFunction(t, &makeDirChain, "makeDirChain"); newGlobal(t, "makeDirChain");
			newFunction(t, &removeDir,    "removeDir");    newGlobal(t, "removeDir");
			newFunction(t, &listFiles,    "listFiles");    newGlobal(t, "listFiles");
			newFunction(t, &listDirs,     "listDirs");     newGlobal(t, "listDirs");
			newFunction(t, &readFile,     "readFile");     newGlobal(t, "readFile");
			newFunction(t, &writeFile,    "writeFile");    newGlobal(t, "writeFile");
			newFunction(t, &readVector,   "readVector");   newGlobal(t, "readVector");
			newFunction(t, &writeVector,  "writeVector");  newGlobal(t, "writeVector");
			newFunction(t, &join,         "join");         newGlobal(t, "join");
			newFunction(t, &dirName,      "dirName");      newGlobal(t, "dirName");
			newFunction(t, &name,         "name");         newGlobal(t, "name");
			newFunction(t, &extension,    "extension");    newGlobal(t, "extension");

// 				newFunction(t, &linesIterator, "linesIterator");
// 			newFunction(t, &lines, "lines", 1);        newGlobal(t, "lines");

			return 0;
		}, "io");

		fielda(t, -2, "io");
		importModule(t, "io");
		pop(t, 3);
	}
	
	uword inFile(MDThread* t, uword numParams)
	{
		auto name = checkStringParam(t, 1);
		auto f = safeCode(t, new File(name, File.ReadExisting));
		
		lookupCT!("stream.InStream")(t);
		pushNull(t);
		pushNativeObj(t, f);
		rawCall(t, -3, 1);
		
		return 1;
	}
	
	uword outFile(MDThread* t, uword numParams)
	{
		auto name = checkStringParam(t, 1);
		auto appending = optBoolParam(t, 2, false);
		auto f = safeCode(t, new File(name, appending ? File.WriteAppending : File.WriteCreate));

		lookupCT!("stream.OutStream")(t);
		pushNull(t);
		pushNativeObj(t, f);
		rawCall(t, -3, 1);

		return 1;
	}

	uword rename(MDThread* t, uword numParams)
	{
		safeCode(t, Path.rename(checkStringParam(t, 1), checkStringParam(t, 2)));
		return 0;
	}

	uword remove(MDThread* t, uword numParams)
	{
		safeCode(t, Path.remove(checkStringParam(t, 1)));
		return 0;
	}

	uword copy(MDThread* t, uword numParams)
	{
		safeCode(t, Path.copy(checkStringParam(t, 1), checkStringParam(t, 1)));
		return 0;
	}

	uword size(MDThread* t, uword numParams)
	{
		pushInt(t, cast(mdint)safeCode(t, Path.fileSize(checkStringParam(t, 1))));
		return 1;
	}

	uword exists(MDThread* t, uword numParams)
	{
		pushBool(t, Path.exists(checkStringParam(t, 1)));
		return 1;
	}

	uword isFile(MDThread* t, uword numParams)
	{
		pushBool(t, safeCode(t, !Path.isFolder(checkStringParam(t, 1))));
		return 1;
	}

	uword isDir(MDThread* t, uword numParams)
	{
		pushBool(t, safeCode(t, Path.isFolder(checkStringParam(t, 1))));
		return 1;
	}
	
	uword isReadOnly(MDThread* t, uword numParams)
	{
		pushBool(t, safeCode(t, !Path.isWritable(checkStringParam(t, 1))));
		return 1;
	}

	uword currentDir(MDThread* t, uword numParams)
	{
		pushString(t, safeCode(t, FileSystem.getDirectory()));
		return 1;
	}
	
	uword parentDir(MDThread* t, uword numParams)
	{
		auto p = optStringParam(t, 1, ".");
		
		if(p == ".")
			p = FileSystem.getDirectory();

		auto pp = safeCode(t, Path.parse(p));

		if(pp.isAbsolute)
			pushString(t, safeCode(t, Path.pop(p)));
		else
			pushString(t, safeCode(t, Path.join(FileSystem.getDirectory(), p)));

		return 1;
	}

	uword changeDir(MDThread* t, uword numParams)
	{
		safeCode(t, FileSystem.setDirectory(checkStringParam(t, 1)));
		return 0;
	}

	uword makeDir(MDThread* t, uword numParams)
	{
		auto p = Path.parse(checkStringParam(t, 1));

		if(!p.isAbsolute())
			safeCode(t, Path.createFolder(Path.join(FileSystem.getDirectory(), p.toString())));
		else
			safeCode(t, Path.createFolder(p.toString()));

		return 0;
	}

	uword makeDirChain(MDThread* t, uword numParams)
	{
		auto p = Path.parse(checkStringParam(t, 1));
		
		if(!p.isAbsolute())
			safeCode(t, Path.createPath(Path.join(FileSystem.getDirectory(), p.toString())));
		else
			safeCode(t, Path.createPath(p.toString()));

		return 0;
	}

	uword removeDir(MDThread* t, uword numParams)
	{
		safeCode(t, Path.remove(checkStringParam(t, 1)));
		return 0;
	}
	
	uword listImpl(MDThread* t, uword numParams, bool isFolder)
	{
		auto fp = optStringParam(t, 1, ".");
		
		if(fp == ".")
			fp = FileSystem.getDirectory();

		auto listing = newArray(t, 0);

		if(numParams >= 2)
		{
			auto filter = checkStringParam(t, 2);

			safeCode(t,
			{
				foreach(ref info; Path.children(fp))
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
		else
		{
			safeCode(t,
			{
				foreach(ref info; Path.children(fp))
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
		auto shouldConvert = optBoolParam(t, 2, false);

		if(shouldConvert)
		{
			safeCode(t,
			{
				auto data = cast(ubyte[]).File.get(name);

				scope(exit)
					delete data;

				foreach(ref c; data)
					if(c > 0x7f)
						c = '?';

				pushString(t, cast(char[])data);
			}());
		}
		else
		{
			safeCode(t,
			{
				scope file = new UnicodeFile!(char)(name, Encoding.Unknown);
				pushString(t, file.read());
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
			file.write(data, true);
		}());

		return 0;
	}
	
	uword readVector(MDThread* t, uword numParams)
	{
		auto name = checkStringParam(t, 1);
		auto size = safeCode(t, Path.fileSize(name));

		pushGlobal(t, "Vector");
		pushNull(t);
		pushString(t, "u8");
		pushInt(t, size);
		rawCall(t, -4, 1);
		auto memb = getMembers!(VectorObj.Members)(t, -1);

		safeCode(t, File.get(name, memb.data[0 .. size]));
		
		return 1;
	}
	
	uword writeVector(MDThread* t, uword numParams)
	{
		auto name = checkStringParam(t, 1);
		auto memb = checkInstParam!(VectorObj.Members)(t, 2, "Vector");
		auto data = memb.data[0 .. memb.length * memb.type.itemSize];

		safeCode(t, File.set(name, data));

		return 1;
	}

// 	uword linesIterator(MDThread* t, uword numParams)
// 	{
// 		getExtraVal(t, 0, StreamObj.Fields.input);
// 		auto lines = (cast(InStreamObj.Members*)getExtraBytes(t, -1).ptr).lines;
// 
// 		auto index = checkIntParam(t, 1) + 1;
// 		auto line = safeCode(t, lines.next());
// 
// 		if(line.ptr is null)
// 		{
// 			dup(t, 0);
// 			pushNull(t);
// 			methodCall(t, -2, "close", 0);
// 			return 0;
// 		}
// 
// 		pushInt(t, index);
// 		pushString(t, line);
// 		return 2;
// 	}
// 
// 	uword lines(MDThread* t, uword numParams)
// 	{
// 		auto name = checkStringParam(t, 1);
// 
// 		pushGlobal(t, "File");
// 		pushNull(t);
// 		pushString(t, name);
// 		rawCall(t, -3, 1);
// 
// 		pushInt(t, 0);
// 		getUpval(t, 0);
// 		
// 		return 3;
// 	}

// 	uword File(MDThread* t, uword numParams)
// 	{
// 		.File.Style parseFileMode(mdint mode)
// 		{
// 			auto s = DefaultFileStyle;
// 
// 			if(mode & FileMode.Out)
// 				s.access |= .File.Access.Write;
// 
// 			s.open = cast(.File.Open)0;
// 
// 			if(mode & FileMode.New)
// 				s.open |= .File.Open.Create;
// 			else
// 			{
// 				if(mode & FileMode.Append)
// 					s.open |= .File.Open.Append;
// 
// 				s.open |= .File.Open.Exists;
// 			}
// 
// 			return s;
// 		}
// 
// 		safeCode(t,
// 		{
// 			auto name = checkStringParam(t, 1);
// 
// 			auto f = numParams == 1
// 				? new .File(name, DefaultFileStyle)
// 				: new .File(name, parseFileMode(checkIntParam(t, 2)));
// 
// 			lookup(t, "stream.Stream");
// 			pushNull(t);
// 			pushNativeObj(t, f);
// 			rawCall(t, -3, 1);
// 		}());
// 
// 		return 1;
// 	}

	uword join(MDThread* t, uword numParams)
	{
		checkAnyParam(t, 1);
		
		char[][] tmp;
		
		scope(exit)
			delete tmp;

		for(uword i = 1; i <= numParams; i++)
			tmp ~= checkStringParam(t, i);

		pushString(t, safeCode(t, Path.join(tmp)));
		return 1;
	}
	
	uword dirName(MDThread* t, uword numParams)
	{
		pushString(t, safeCode(t, Path.parse(checkStringParam(t, 1))).path);
		return 1;
	}

	uword name(MDThread* t, uword numParams)
	{
		pushString(t, safeCode(t, Path.parse(checkStringParam(t, 1))).name);
		return 1;
	}

	uword extension(MDThread* t, uword numParams)
	{
		pushString(t, safeCode(t, Path.parse(checkStringParam(t, 1))).ext);
		return 1;
	}
}