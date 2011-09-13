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

module crocc;

import tango.io.device.File;
import tango.io.Stdout;

import croc.api;
import croc.compiler;
import croc.serialization;

void printUsage()
{
	Stdout.formatln("Croc Compiler v{}.{}", CrocVersion >> 16, CrocVersion & 0xFFFF).newline;
	Stdout("Usage:").newline;
	Stdout("\tcrocc filename").newline;
	Stdout.newline;
	Stdout("This program is very straightforward. You give it the name of a .croc").newline;
	Stdout("file, and it will compile the module and write it to a binary .croco file.").newline;
	Stdout("The output file will have the same name as the input file but with the").newline;
	Stdout(".croco extension.").newline;
}

void main(char[][] args)
{
	if(args.length != 2)
	{
		printUsage();
		return;
	}

	CrocVM vm;
	auto t = openVM(&vm);
	loadStdlibs(t, CrocStdlib.All);

	scope(exit)
		closeVM(&vm);

	scope c = new Compiler(t);
	char[] loadedName = void;
	c.compileModule(args[1], loadedName);

	auto fc = new File(args[1] ~ "o", File.WriteCreate);
	serializeModule(t, -1, loadedName, fc);
	fc.close();
}