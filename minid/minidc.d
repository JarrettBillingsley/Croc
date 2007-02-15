module minid.minidc;

import minid.compiler;
import minid.types;
import minid.utils;

import std.stdio;
import std.stream;

void printUsage()
{
	writefln("MiniD Compiler beta");
	writefln();
	writefln("Usage:");
	writefln("\tminidc filename");
	writefln();
	writefln("This program is very straightforward.  You give it the name of a .md");
	writefln("file, and it will compile the module and write it to a binary .mdm file.");
	writefln("The output file will have the same name as the input file but with the");
	writefln(".mdm extension.");
}

void main(char[][] args)
{
	if(args.length != 2)
	{
		printUsage();
		return;
	}

	MDModuleDef def = compileModule(args[1]);
	scope f = new BufferedFile(args[1] ~ "m", FileMode.OutNew);
	Serialize(f, def);
	f.flush();
}