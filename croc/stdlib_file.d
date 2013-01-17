/******************************************************************************
This module contains the 'file' standard library.

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

module croc.stdlib_file;

import tango.io.Path;
import tango.io.device.File;
import tango.io.stream.Buffered;
import tango.io.UnicodeFile;
import tango.sys.Environment;
import tango.time.WallClock;

alias tango.io.Path.accessed Path_accessed;
alias tango.io.Path.children Path_children;
alias tango.io.Path.copy Path_copy;
alias tango.io.Path.created Path_created;
alias tango.io.Path.createFolder Path_createFolder;
alias tango.io.Path.createPath Path_createPath;
alias tango.io.Path.exists Path_exists;
alias tango.io.Path.fileSize Path_fileSize;
alias tango.io.Path.isFolder Path_isFolder;
alias tango.io.Path.isWritable Path_isWritable;
alias tango.io.Path.join Path_join;
alias tango.io.Path.modified Path_modified;
alias tango.io.Path.parse Path_parse;
alias tango.io.Path.patternMatch Path_patternMatch;
alias tango.io.Path.remove Path_remove;
alias tango.io.Path.rename Path_rename;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.ex_library;
import croc.stdlib_stream;
import croc.stdlib_time;
import croc.types;

alias croc.api_stack.pop pop;

struct FileLib
{
static:
	void init(CrocThread* t)
	{
		makeModule(t, "file", function uword(CrocThread* t)
		{
			importModuleNoNS(t, "stream");

			newFunction(t, 2, &inFile,                "inFile");        newGlobal(t, "inFile");
			newFunction(t, 3, &outFile,               "outFile");       newGlobal(t, "outFile");
			newFunction(t, 3, &inoutFile,             "inoutFile");     newGlobal(t, "inoutFile");
			newFunction(t, 2, &rename,                "rename");        newGlobal(t, "rename");
			newFunction(t, 1, &remove,                "remove");        newGlobal(t, "remove");
			newFunction(t, 2, &copy,                  "copy");          newGlobal(t, "copy");
			newFunction(t, 1, &size,                  "size");          newGlobal(t, "size");
			newFunction(t, 1, &exists,                "exists");        newGlobal(t, "exists");
			newFunction(t, 1, &isFile,                "isFile");        newGlobal(t, "isFile");
			newFunction(t, 1, &isDir,                 "isDir");         newGlobal(t, "isDir");
			newFunction(t, 1, &isReadOnly,            "isReadOnly");    newGlobal(t, "isReadOnly");
			newFunction(t, 2, &fileTime!("modified"), "modified");      newGlobal(t, "modified");
			newFunction(t, 2, &fileTime!("created"),  "created");       newGlobal(t, "created");
			newFunction(t, 2, &fileTime!("accessed"), "accessed");      newGlobal(t, "accessed");
			newFunction(t, 0, &currentDir,            "currentDir");    newGlobal(t, "currentDir");
			newFunction(t, 1, &changeDir,             "changeDir");     newGlobal(t, "changeDir");
			newFunction(t, 1, &makeDir,               "makeDir");       newGlobal(t, "makeDir");
			newFunction(t, 1, &makeDirChain,          "makeDirChain");  newGlobal(t, "makeDirChain");
			newFunction(t, 1, &removeDir,             "removeDir");     newGlobal(t, "removeDir");
			newFunction(t, 3, &listFiles,             "listFiles");     newGlobal(t, "listFiles");
			newFunction(t, 3, &listDirs,              "listDirs");      newGlobal(t, "listDirs");
			newFunction(t, 2, &readFile,              "readFile");      newGlobal(t, "readFile");
			newFunction(t, 2, &writeFile,             "writeFile");     newGlobal(t, "writeFile");
			newFunction(t, 1, &readMemblock,          "readMemblock");  newGlobal(t, "readMemblock");
			newFunction(t, 2, &writeMemblock,         "writeMemblock"); newGlobal(t, "writeMemblock");

				newFunction(t, &linesStripIterator, "linesIterator");
				newFunction(t, &linesNostripIterator, "linesIterator");
			newFunction(t, 3, &lines, "lines", 2);        newGlobal(t, "lines");

			return 0;
		});

		importModuleNoNS(t, "file");
	}

	uword inFile(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		auto bufSize = optIntParam(t, 2, 4096);
		auto f = safeCode(t, "exceptions.IOException", new File(name, File.ReadExisting));

		auto slot = lookupCT!("stream.NativeStream")(t);
		pushNull(t);
		pushNativeObj(t, f);
		pushBool(t, true);
		pushBool(t, true);
		pushBool(t, false);
		rawCall(t, slot, 1);

		if(bufSize > 0)
		{
			lookupCT!("stream.BufferedInStream")(t);
			pushNull(t);
			dup(t, slot);
			pushInt(t, bufSize);
			rawCall(t, -4, 1);
		}

		return 1;
	}

	uword outFile(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		auto mode = optCharParam(t, 2, 'c');
		auto bufSize = optIntParam(t, 3, 4096);

		File.Style style;

		switch(mode)
		{
			case 'e': style = File.WriteExisting;  break;
			case 'a': style = File.WriteAppending; break;
			case 'c': style = File.WriteCreate;    break;
			default:
				throwStdException(t, "ValueException", "Unknown open mode '{}'", mode);
		}

		auto f = safeCode(t, "exceptions.IOException", new File(name, style));

		auto slot = lookupCT!("stream.NativeStream")(t);
		pushNull(t);
		pushNativeObj(t, f);
		pushBool(t, true);
		pushBool(t, false);
		pushBool(t, true);
		rawCall(t, slot, 1);

		if(bufSize > 0)
		{
			lookupCT!("stream.BufferedOutStream")(t);
			pushNull(t);
			dup(t, slot);
			pushInt(t, bufSize);
			rawCall(t, -4, 1);
		}

		return 1;
	}

	uword inoutFile(CrocThread* t)
	{
		static const File.Style ReadWriteAppending = { File.Access.ReadWrite, File.Open.Append };

		auto name = checkStringParam(t, 1);
		auto mode = optCharParam(t, 2, 'e');
		auto bufSize = optIntParam(t, 3, 4096);

		File.Style style;

		switch(mode)
		{
			case 'e': style = File.ReadWriteExisting; break;
			case 'a': style = ReadWriteAppending;     break;
			case 'c': style = File.ReadWriteCreate;   break;
			default:
				throwStdException(t, "ValueException", "Unknown open mode '{}'", mode);
		}

		auto f = safeCode(t, "exceptions.IOException", new File(name, style));

		auto slot = lookupCT!("stream.NativeStream")(t);
		pushNull(t);
		pushNativeObj(t, f);
		pushBool(t, true);
		pushBool(t, true);
		pushBool(t, true);
		rawCall(t, slot, 1);

		// TODO:
		// if(bufSize > 0)
		// {
		// 	lookupCT!("stream.BufferedInoutStream")(t);
		// 	pushNull(t);
		// 	dup(t, slot);
		// 	pushInt(t, bufSize);
		// 	rawCall(t, -4, 1);
		// }

		return 1;
	}

	uword rename(CrocThread* t)
	{
		safeCode(t, "exceptions.IOException", Path_rename(checkStringParam(t, 1), checkStringParam(t, 2)));
		return 0;
	}

	uword remove(CrocThread* t)
	{
		safeCode(t, "exceptions.IOException", Path_remove(checkStringParam(t, 1)));
		return 0;
	}

	uword copy(CrocThread* t)
	{
		safeCode(t, "exceptions.IOException", Path_copy(checkStringParam(t, 1), checkStringParam(t, 2)));
		return 0;
	}

	uword size(CrocThread* t)
	{
		pushInt(t, cast(crocint)safeCode(t, "exceptions.IOException", Path_fileSize(checkStringParam(t, 1))));
		return 1;
	}

	uword exists(CrocThread* t)
	{
		pushBool(t, Path_exists(checkStringParam(t, 1)));
		return 1;
	}

	uword isFile(CrocThread* t)
	{
		pushBool(t, safeCode(t, "exceptions.IOException", !Path_isFolder(checkStringParam(t, 1))));
		return 1;
	}

	uword isDir(CrocThread* t)
	{
		pushBool(t, safeCode(t, "exceptions.IOException", Path_isFolder(checkStringParam(t, 1))));
		return 1;
	}

	uword isReadOnly(CrocThread* t)
	{
		pushBool(t, safeCode(t, "exceptions.IOException", !Path_isWritable(checkStringParam(t, 1))));
		return 1;
	}

	uword fileTime(char[] which)(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto time = safeCode(t, "exceptions.IOException", mixin("Path_" ~ which ~ "(checkStringParam(t, 1))"));
		word tab;

		if(numParams == 1)
			tab = newTable(t);
		else
		{
			checkParam(t, 2, CrocValue.Type.Table);
			tab = 2;
		}

		TimeLib.DateTimeToTable(t, WallClock.toDate(time), tab);
		dup(t, tab);
		return 1;
	}

	uword currentDir(CrocThread* t)
	{
		pushString(t, safeCode(t, "exceptions.IOException", Environment.cwd()));
		return 1;
	}

	uword changeDir(CrocThread* t)
	{
		safeCode(t, "exceptions.IOException", Environment.cwd(checkStringParam(t, 1)));
		return 0;
	}

	uword makeDir(CrocThread* t)
	{
		auto p = Path_parse(checkStringParam(t, 1));

		if(!p.isAbsolute())
			safeCode(t, "exceptions.IOException", Path_createFolder(Path_join(Environment.cwd(), p.toString())));
		else
			safeCode(t, "exceptions.IOException", Path_createFolder(p.toString()));

		return 0;
	}

	uword makeDirChain(CrocThread* t)
	{
		auto p = Path_parse(checkStringParam(t, 1));

		if(!p.isAbsolute())
			safeCode(t, "exceptions.IOException", Path_createPath(Path_join(Environment.cwd(), p.toString())));
		else
			safeCode(t, "exceptions.IOException", Path_createPath(p.toString()));

		return 0;
	}

	uword removeDir(CrocThread* t)
	{
		safeCode(t, "exceptions.IOException", Path_remove(checkStringParam(t, 1)));
		return 0;
	}

	uword listImpl(CrocThread* t, bool isFolder)
	{
		auto numParams = stackSize(t) - 1;
		auto fp = optStringParam(t, 1, ".");

		if(fp == ".")
			fp = Environment.cwd();

		if(numParams >= 3)
		{
			auto filter = checkStringParam(t, 2);
			checkParam(t, 3, CrocValue.Type.Function);

			safeCode(t, "exceptions.IOException",
			{
				foreach(ref info; Path_children(fp))
				{
					if(info.folder is isFolder)
					{
						if(!Path_patternMatch(info.name, filter))
							continue;

						dup(t, 3);
						pushNull(t);
						pushString(t, info.path);
						pushString(t, info.name);
						cat(t, 2);
						rawCall(t, -3, 1);

						if(isBool(t, -1) && !getBool(t, -1))
							break;

						pop(t);
					}
				}
			}());
		}
		else
		{
			checkParam(t, 2, CrocValue.Type.Function);

			safeCode(t, "exceptions.IOException",
			{
				foreach(ref info; Path_children(fp))
				{
					if(info.folder is isFolder)
					{
						dup(t, 2);
						pushNull(t);
						pushString(t, info.path);
						pushString(t, info.name);
						cat(t, 2);
						rawCall(t, -3, 1);

						if(isBool(t, -1) && !getBool(t, -1))
							break;

						pop(t);
					}
				}
			}());
		}

		return 0;
	}

	uword listFiles(CrocThread* t)
	{
		return listImpl(t, false);
	}

	uword listDirs(CrocThread* t)
	{
		return listImpl(t, true);
	}

	uword readFile(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		auto shouldConvert = optBoolParam(t, 2, false);

		if(shouldConvert)
		{
			auto data = safeCode(t,"exceptions.IOException", cast(ubyte[]).File.get(name));

			scope(exit)
				delete data;

			foreach(ref c; data)
				if(c > 0x7f)
					c = '\u001a';

			pushString(t, cast(char[])data);
		}
		else
		{
			safeCode(t, "exceptions.IOException",
			{
				scope file = new UnicodeFile!(char)(name, Encoding.Unknown);
				pushString(t, file.read());
			}());
		}

		return 1;
	}

	uword writeFile(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		auto data = checkStringParam(t, 2);

		safeCode(t, "exceptions.IOException",
		{
			scope file = new UnicodeFile!(char)(name, Encoding.UTF_8);
			file.write(data, true);
		}());

		return 0;
	}

	uword readMemblock(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		auto size = safeCode(t, "exceptions.IOException", Path_fileSize(name));

		if(size > uword.max)
			throwStdException(t, "ValueException", "file too big ({} bytes)", size);

		newMemblock(t, cast(uword)size);
		auto mb = getMemblock(t, -1);
		safeCode(t, "exceptions.IOException", File.get(name, mb.data));
		return 1;
	}

	uword writeMemblock(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		checkParam(t, 2, CrocValue.Type.Memblock);
		auto mb = getMemblock(t, 2);
		safeCode(t, "exceptions.IOException", File.set(name, mb.data));
		return 1;
	}

	uword linesStripIterator(CrocThread* t)
	{
		auto index = checkIntParam(t, 1) + 1;

		dup(t, 0);
		pushNull(t);
		methodCall(t, -2, "readln", 1);

		if(isNull(t, -1))
		{
			dup(t, 0);
			pushNull(t);
			methodCall(t, -2, "getStream", 1);
			pushNull(t);
			methodCall(t, -2, "close", 0);
			return 0;
		}

		pushInt(t, index);
		swap(t);
		return 2;
	}

	uword linesNostripIterator(CrocThread* t)
	{
		auto index = checkIntParam(t, 1) + 1;

		dup(t, 0);
		pushNull(t);
		pushBool(t, false);
		methodCall(t, -3, "readln", 1);

		if(isNull(t, -1))
		{
			dup(t, 0);
			pushNull(t);
			methodCall(t, -2, "getStream", 1);
			pushNull(t);
			methodCall(t, -2, "close", 0);
			return 0;
		}

		pushInt(t, index);
		swap(t);
		return 2;
	}

	uword lines(CrocThread* t)
	{
		const StripIterator = 0;
		const NostripIterator = 1;

		checkStringParam(t, 1);
		bool stripEnding = optBoolParam(t, 2, true);
		auto encoding = optStringParam(t, 3, "utf-8");

		pushGlobal(t, "inFile");
		pushNull(t);
		dup(t, 1);
		pushInt(t, 0); // disable buffering, as TextReader does its own
		rawCall(t, -4, 1);

		lookupCT!("stream.TextReader")(t);
		pushNull(t);
		moveToTop(t, -3);
		pushString(t, encoding);
		rawCall(t, -4, 1);

		pushInt(t, 0);
		getUpval(t, stripEnding ? StripIterator : NostripIterator);
		insert(t, -3);

		return 3;
	}
}