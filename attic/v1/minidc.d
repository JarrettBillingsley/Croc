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

module minidc;

import minid.compiler;
import minid.types;
import minid.utils;

import tango.io.Stdout;

void printUsage()
{
	Stdout.formatln("MiniD Compiler v{}.{}", MiniDVersion >> 16, MiniDVersion & 0xFFFF).newline;
	Stdout.newline;
	Stdout("Usage:").newline;
	Stdout("\tminidc filename").newline;
	Stdout.newline;
	Stdout("This program is very straightforward.  You give it the name of a .md").newline;
	Stdout("file, and it will compile the module and write it to a binary .mdm file.").newline;
	Stdout("The output file will have the same name as the input file but with the").newline;
	Stdout(".mdm extension.").newline;
}

void main(char[][] args)
{
	if(args.length != 2)
	{
		printUsage();
		return;
	}

	compileModule(args[1]).writeToFile(args[1] ~ "m");
}