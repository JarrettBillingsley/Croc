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

module minid.commandline;

private import minid.compiler;
private import minid.minid;
private import minid.types;
private import minid.utils;

private import tango.io.Print;
private import tango.io.model.IConduit;
private import tango.text.convert.Layout;
private import tango.text.stream.LineIterator;
private import tango.stdc.ctype;
private import Uni = tango.text.Unicode;

private import utf = tango.text.convert.Utf;

public class CommandLine
{
	const char[] Prompt1 = ">>> ";
	const char[] Prompt2 = "... ";

	private Print!(char) mOutput;
	private LineIterator!(char) mInput;

	public this(Print!(char) output, InputStream inputStream)
	{
		mOutput = output;
		mInput = new LineIterator!(char)(inputStream);
	}

	public this(OutputStream outputStream, InputStream inputStream)
	{
		this(new Print!(char)(new Layout!(char), outputStream), inputStream);
	}

	private void printVersion()
	{
		mOutput("MiniD Command-Line interpreter beta").newline;
	}
	
	private void printUsage(char[] progname)
	{
		printVersion();
		mOutput("Usage:").newline;
		mOutput("\t")(progname)(" [flags] [filename [args]]").newline;
		mOutput.newline;
		mOutput("Flags:").newline;
		mOutput("\t-i		Enter interactive mode, after executing any script file.").newline;
		mOutput("\t-v		Print the version of the CLI.").newline;
		mOutput("\t-h		Print this message and end.").newline;
		mOutput("\t-I path Specifies an import path to search when importing modules.").newline;
		mOutput.newline;
		mOutput("If mdcl is called without any arguments, it will be as if you passed it").newline;
		mOutput("the -v and -i arguments (it will print the version and enter interactive").newline;
		mOutput("mode).").newline;
		mOutput.newline;
		mOutput("If the filename has no extension, it will be treated as a MiniD import-").newline;
		mOutput("style module name.  So \"a.b\" will look for a module named b in the a").newline;
		mOutput("directory.  The -I flag also affects the search paths used for this.").newline;
		mOutput.newline;
		mOutput("When passing a filename followed by args, all the args will be available").newline;
		mOutput("to the script by using the vararg expression.  The arguments will all be").newline;
		mOutput("strings.").newline;
		mOutput.newline;
		mOutput("In interactive mode, you will be given a >>> prompt.  When you hit enter,").newline;
		mOutput("you may be given a ... prompt.  That means you need to type more to make").newline;
		mOutput("the code complete.  Once you enter enough code to make it complete, the").newline;
		mOutput("code will be run.	If there is an error, the code buffer is cleared.").newline;
		mOutput("To end interactive mode, either use the function \"exit();\", or force").newline;
		mOutput("exit by hitting Ctrl-C.").newline;
	}

	private void outputRepr(MDState state, ref MDValue v)
	{
		void escape(dchar c)
		{
			switch(c)
			{
				case '\'': mOutput(`\'`); break;
				case '\"': mOutput(`\"`); break;
				case '\\': mOutput(`\\`); break;
				case '\a': mOutput(`\a`); break;
				case '\b': mOutput(`\b`); break;
				case '\f': mOutput(`\f`); break;
				case '\n': mOutput(`\n`); break;
				case '\r': mOutput(`\r`); break;
				case '\t': mOutput(`\t`); break;
				case '\v': mOutput(`\v`); break;

				default:
					if(c <= 0x7f && isprint(c))
						mOutput(c);
					else if(c <= 0xFFFF)
						mOutput.format("\\u{:x4}", cast(uint)c);
					else
						mOutput.format("\\U{:x8}", cast(uint)c);
					break;
			}
		}

		if(v.isString)
		{
			mOutput('"');
			
			auto s = v.as!(MDString);

			for(int i = 0; i < s.length; i++)
				escape(s[i]);

			mOutput('"');
		}
		else if(v.isChar)
		{
			mOutput("'");
			escape(v.as!(dchar));
			mOutput("'");
		}
		else
			mOutput(state.valueToString(v));
	}

	void run(char[][] args = null, MDContext ctx = null)
	{
		bool printedVersion = false;
		bool interactive = false;
		char[] inputFile;
		char[][] scriptArgs;
		char[][] importPaths;
		char[] progname = (args.length > 0) ? args[0] : "";

		if(args.length == 1 || args == null)
		{
			interactive = true;
		}
		
		_argLoop: for(int i = 1; i < args.length; i++)
		{
			switch(args[i])
			{
			case "-i":
				interactive = true;
				break;

			case "-v":
				if(printedVersion == false)
				{
					printedVersion = true;
					printVersion();
				}
				break;
				
			case "-h":
				printUsage(progname);
				return;
				
			case "-I":
				i++;
				
				if(i >= args.length)
				{
					mOutput("-I must be followed by a path").newline;
					printUsage(progname);
					return;
				}
				
				importPaths ~= args[i];
				break;

			default:
				if(args[i][0] == '-')
				{
					return;
				}

				inputFile = args[i];
				scriptArgs = args[i + 1 .. $];
				break _argLoop;
			}
		}

		if(ctx is null)
			ctx = NewContext();
		
		MDState state = ctx.mainThread;

		foreach(path; importPaths)
			ctx.addImportPath(path);

		if(inputFile.length > 0)
		{
			MDModuleDef def;

			if(inputFile.length >= 3 && inputFile[$ - 3 .. $] == ".md")
				def = compileModule(inputFile);
			else if(inputFile.length >= 4 && inputFile[$ - 4 .. $] == ".mdm")
				def = MDModuleDef.loadFromFile(inputFile);

			MDValue[] params = new MDValue[scriptArgs.length];

			foreach(i, arg; scriptArgs)
				params[i] = arg;

			if(def is null)
			{
				try
				{
					if(ctx.loadModuleFromFile(state, utf.toString32(inputFile), params) is null)
						mOutput.formatln("Error: could not find module '{}'", inputFile);
				}
				catch(MDException e)
				{
					mOutput.formatln("Error: {}", e);
					mOutput.formatln("{}", ctx.getTracebackString());
				}
			}
			else
			{
				try
					ctx.initializeModule(state, def, params);
				catch(MDException e)
				{
					mOutput.formatln("Error: {}", e);
					mOutput.formatln("{}", ctx.getTracebackString());
				}
			}
		}

		if(interactive)
		{
			dchar[1024] utf32buffer;
			List!(MDValue) returnBuffer;

			char[] buffer;
			bool run = true;

			ctx.globals["exit"d] = ctx.newClosure
			(
				(MDState s, uint numParams)
				{
					run = false;
					return 0;
				}, "exit"
			);

			mOutput("Use the \"exit()\" function to end, or hit Ctrl-C.").newline;
			mOutput(Prompt1)();
			
			bool couldBeDecl()
			{
				if(buffer.length == 0)
					return false;

				size_t i = 0;

				for( ; i < buffer.length && Uni.isWhitespace(buffer[i]); i++)
				{}
				
				auto temp = buffer[i .. $];

				return temp.startsWith("function") || temp.startsWith("class") || temp.startsWith("namespace");
			}

			bool tryAsStatement(Exception e = null)
			{
				try
				{
					auto def = compileStatements(utf.toString32(buffer), "stdin");
					scope closure = ctx.newClosure(def);
					state.easyCall(closure, 0, MDValue(ctx.globals.ns));
				}
				catch(MDCompileException e2)
				{
					if(e2.atEOF)
					{
						mOutput(Prompt2)();
						return true;
					}
					else if(e2.solitaryExpression && e !is null)
					{
						// output e, the exception that caused it not to be evaluable as an expression in the first place
						mOutput.formatln("Error: {}", e);
						mOutput.newline;
					}
					else
					{
						mOutput.formatln("Error: {}", e2);
						mOutput.newline;
					}
				}
				catch(MDException e2)
				{
					mOutput.formatln("Error: {}", e2);
					mOutput.formatln("{}", ctx.getTracebackString());
					mOutput.newline;
				}

				return false;
			}
			
			bool tryAsExpression()
			{
				try
				{
					auto numRets = evalMultRet(state, utf.toString32(buffer, utf32buffer));
					
					if(numRets > 0)
					{
						mOutput(" => ");
						returnBuffer.length = 0;
						
						for(uint i = 0; i < numRets; i++)
							returnBuffer ~= state.pop();

						auto returns = returnBuffer.toArray();
						
						outputRepr(state, returns[$ - 1]);

						foreach_reverse(val; returns[0 .. $ - 1])
						{
							mOutput(", ");
							outputRepr(state, val);
						}
						
						mOutput.newline;
					}
				}
				catch(MDCompileException e)
				{
					if(e.atEOF)
					{
						mOutput(Prompt2)();
						return true;
					}
					else
						return tryAsStatement(e);
				}
				catch(MDException e)
				{
					mOutput.formatln("Error: {}", e);
					mOutput.formatln("{}", ctx.getTracebackString());
					mOutput.newline;
				}
				
				return false;
			}

			while(run)
			{
				char[] line = mInput.next();

				if(line.ptr is null)
					break;
					
				if(buffer.length is 0 && line.length is 0)
				{
					mOutput(Prompt1)();
					continue;
				}

				buffer ~= '\n' ~ line;

				if(couldBeDecl())
				{
					if(tryAsStatement())
						continue;
				}
				else
				{
					if(tryAsExpression())
						continue;
				}

				mOutput(Prompt1)();
				buffer.length = 0;
			}
		}
	}
}
