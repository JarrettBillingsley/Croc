/******************************************************************************
This module contains a struct that implements a simple interactive commandline
for running Croc code.

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

Authors:
	John Demme <me@teqdruid.com> (2007, initial code)
	Robert Clipsham <robert@octarineparrot.com> (2009, added readline support)
******************************************************************************/

module croc.ex_commandline;

import tango.core.Exception;
import tango.io.Console;
import tango.io.Stdout;
import tango.io.model.IConduit;
import tango.io.stream.Lines;
import tango.stdc.signal;
import tango.stdc.stringz;
import tango.text.Util;

alias tango.text.Util.contains contains;

import croc.api;
import croc.compiler;

version(CrocReadline)
{
	extern(C)
	{
		void using_history();
		void add_history(char*);
		void clear_history();
		void stifle_history(int);
		int	unstifle_history();
		char* readline(char*);
		int	printf(char*, ...);
		char* function(char*, int) rl_completion_entry_function;

		static char* emptyCompleter(char*, int)
		{
			return null;
		}
	}

	static this()
	{
		using_history();
		rl_completion_entry_function = &emptyCompleter;
	}

	// It's a singleton since there's only one stdin..!
	class ReadlineStream : InputBuffer
	{
		private static ReadlineStream _instance;

		public static ReadlineStream instance()
		{
			return _instance;
		}

		static this()
		{
			_instance = new ReadlineStream();
			_instance.maxHistory = -1;
		}

		// nonstatic
		private char* mPrompt;
		private char[] mBuffer;
		private bool mFirstCall = true;

		private this()
		{
			if(_instance !is null)
				throw new Exception("Attempting to create more than one instance of ReadlineStream");
		}

		public size_t readln(ref char[] dst)
		{
			dst = cast(char[])load();
			return dst.length;
		}

		public void maxHistory(int max)
		{
			if(max == -1)
				unstifle_history();
			else if(max >= 0)
				stifle_history(max);
		}

		/**
		This depends on p always being 0-terminated (like a string literal).
		*/
		public void prompt(char[] p)
		{
			mPrompt = p.ptr;
		}

		public override size_t read(void[] dst)
		{
			throw new IOException("Unimplemented");
		}

		public override void[] load(size_t max = size_t.max)
		{
			if(mFirstCall)
			{
				mFirstCall = false;
				return null;
			}

			if(mBuffer is null)
			{
				auto line = readline(mPrompt);

				while(fromStringz(line).length == 0)
					line = readline(mPrompt);

				add_history(line);
				return fromStringz(line);
			}

			auto buf = mBuffer;
			mBuffer = null;
			return buf;
		}

		public override InputStream input()
		{
			return this;
		}

		public override IConduit conduit()
		{
			return cast(IConduit)this;
		}

		public override long seek(long, Anchor)
		{
			throw new IOException( "Unimplemented" );
		}

		public override IOStream flush()
		{
			return this;
		}

		public override void close()
		{
			mBuffer = null;
			clear_history();
		}

		public override void[] slice()
		{
			if(mBuffer is null)
				mBuffer = cast(char[])load();

			return cast(void[])mBuffer[0 .. $];
		}

		public override bool next(size_t delegate(void[]) scan)
		{
			if(mBuffer is null)
				mBuffer = cast(char[])load();

			if(scan(cast(void[])mBuffer) is Eof)
			{
				mBuffer = null;
				return false;
			}

			return true;
		}

		public override size_t reader(size_t delegate(void[]) consumer)
		{
			if(mBuffer is null)
				mBuffer = cast(char[])load();

			return consumer(mBuffer[0 .. $]);
		}
	}

	/**
	An Input struct to be used with the CLI struct, which wraps libreadline.
	*/
	struct CrocReadlineInput
	{
		static Lines!(char) mLines;

		static this()
		{
			mLines = new Lines!(char)(ReadlineStream.instance.input);
		}

		char[] readln(CrocThread* t, char[] prompt)
		{
			ReadlineStream.instance.prompt = prompt;
			return mLines.next();
		}
	}
}

/**
An Input struct to be used with the CLI struct, which wraps standard in/out.
*/
struct CrocConsoleInput
{
	Lines!(char) mLines;

	void init(CrocThread* t)
	{
		mLines = new Lines!(char)(Cin.input);
	}

	char[] readln(CrocThread* t, char[] prompt)
	{
		Stdout(prompt)();
		return mLines.next();
	}
}

version(CrocReadline)
	/** An alias to the default Input type. */
	alias CrocReadlineInput CrocDefaultInput;
else
	/** An alias to the default Input type. */
	alias CrocConsoleInput CrocDefaultInput;

/**
A template that checks that a given type conforms to the Input interface used by
the CLI struct. The given type T $(B must) implement "char[] readln(CrocThread* t, char[] p)",
where 't' is a thread object and 'p' is the prompt to be used for getting a line of input. It
may optionally implement a method "init(CrocThread* t)", which is called when the interactive
CLI prompt is started and can be used to initialize members. It may optionally implement a
method "cleanup(CrocThread* t)", which is called when the interactive CLI prompt is exited and
can be used to clean up resources. If T is a class, it must have a no-argument constructor.
*/
template IsValidInputType(T)
{
	const bool IsValidInputType = is(typeof
	({
		CrocThread* t;
		T input;

		static if(is(T : Object))
			input = new T;

		static if(is(typeof(&input.init) == delegate))
			input.init(t);

		char[] prompt;
		char[] line = input.readln(t, prompt);

		static if(is(typeof(&input.cleanup) == delegate))
			input.cleanup(t);
	}));
}

/**
This struct encapsulates an interactive Croc interpreter. croc uses this struct to do its
interactive prompt.

This struct installs a signal handler that catches Ctrl+C (SIGINT) signals. It restores
the old signal handler when it exits.

The Input type must be a struct or class type which implements the Input interface as described
in IsValidInputType.
*/
struct CLI(Input)
{
	static assert(IsValidInputType!(Input), "Type '" ~ Input.stringof ~ "' does not fulfill the Input interface");

	const char[] Prompt1 = ">>> ";
	const char[] Prompt2 = "... ";

	private Input mInput;
	private char[] mPrompt = Prompt1;
	private bool mRunning;
	private bool mReplacedExit = false;
	
	static class Goober
	{
		CLI!(Input)* self;
		
		this(CLI!(Input)* self)
		{
			this.self = self;
		}
	}

	private void setupExit(CrocThread* t)
	{
		// Check that croc.commandline.oldExits exists
		getRegistry(t);
		pushString(t, "croc.commandline.oldExits");

		if(!opin(t, -1, -2))
		{
			newArray(t, 0);
			fielda(t, -3);
		}
		else
			pop(t);

		// Check that the croc.commandline.ExitObj class exists
		pushString(t, "croc.commandline.ExitObj");

		if(!opin(t, -1, -2))
		{
			// class ExitObj { function toString() = ... }
			newClass(t, "ExitObj");

			newFunction(t, 0, function uword(CrocThread* t)
			{
				pushString(t, "Use \"exit()\" or Ctrl+D<enter> to end.");
				return 1;
			}, "toString");

			fielda(t, -2, "toString");

			dup(t, -2);
			dup(t, -2);
			fielda(t, -5);
			insertAndPop(t, -3);
		}
		else
		{
			field(t, -2);
			insertAndPop(t, -2);
		}

		// Set up the exit object
		pushNull(t);
		rawCall(t, -2, 1);

			pushNativeObj(t, new Goober(this));
		newFunction(t, 0, function uword(CrocThread* t)
		{
			getUpval(t, 0);
			auto g = cast(Goober)getNativeObj(t, -1);
			g.self.mRunning = false;
			return 0;
		}, "exit", 1);

		fielda(t, -2, "opCall");

		// Is there already an 'exit'?
		if(findGlobal(t, "exit"))
		{
			// Already a global named 'exit', replace it carefully.
			field(t, -1, "exit");
			dup(t);
			fielda(t, -4, "old");
			getRegistryVar(t, "croc.commandline.oldExits");
			swap(t);
			cateq(t, -2, 1);
			pop(t);
			swap(t);
			fielda(t, -2, "exit");
			pop(t);

			mReplacedExit = true;
		}
		else
		{
			// We can just make the global.
			newGlobal(t, "exit");
			mReplacedExit = false;
		}
	}

	private void cleanupExit(CrocThread* t)
	{
		if(mReplacedExit)
		{
			// exit = registry.("croc.commandline.oldExits").pop()
			getRegistryVar(t, "croc.commandline.oldExits");
			pushNull(t);
			methodCall(t, -2, "pop", 1);
			setGlobal(t, "exit");
		}
		else
		{
			// This *should* return true, but just in case.
			if(findGlobal(t, "exit"))
			{
				// unset("exit")
				pushString(t, "exit");
				removeKey(t, -2);
				pop(t);
			}
		}
	}

	/**
	This method runs an interactive prompt using the Input type that this struct was templated
	with.

	Params:
		t = The thread to use for this CLI.
	*/
	public void interactive(CrocThread* t)
	{
		// Initialize the input
		static if(is(Input : Object))
			mInput = new Input;

		static if(is(typeof(&mInput.init) == delegate))
			mInput.init(t);

		char[] buffer;

		// Set up the exit object
		setupExit(t);

		// Set up the Ctrl+C handler
		// static so the interrupt handler can access it.
		static bool didHalt = false;
		didHalt = false;
		static CrocThread* thread;
		thread = t;

		static extern(C) void interruptHandler(int s)
		{
			pendingHalt(thread);
			didHalt = true;
			signal(s, &interruptHandler);
		}

		auto oldInterrupt = signal(SIGINT, &interruptHandler);

		scope(exit)
			signal(SIGINT, oldInterrupt);

		// Support funcs
		bool couldBeDecl()
		{
			auto temp = buffer.triml();
			return temp.startsWith("function") || temp.startsWith("class") || temp.startsWith("namespace") || temp.startsWith("@") ||
				temp.startsWith("///") || temp.startsWith("/**");
		}

		bool tryAsStatement(Exception e = null)
		{
			scope c = new Compiler(t);
			word reg;

			try
				reg = c.compileStatements(buffer, "CLI");
			catch(CrocException e2)
			{
				catchException(t);
				pop(t);

				if(c.isEof())
				{
					mPrompt = Prompt2;
					return true;
				}
				else if(c.isLoneStmt())
				{
					if(e)
					{
						Stdout.formatln("When attempting to evaluate as an expression:");
						Stdout.formatln("Error: {}", e);
						Stdout.formatln("When attempting to evaluate as a statement:");
					}
				}

				Stdout.formatln("Error: {}", e2).newline;
				return false;
			}
			
			if(c.isDanglingDoc())
			{
				mPrompt = Prompt2;
				return true;
			}

			try
			{
				newFunction(t, reg);
				insertAndPop(t, -2);
				pushNull(t);
				rawCall(t, reg, 0);
			}
			catch(CrocException e2)
			{
				catchException(t);
				pop(t);

				Stdout.formatln("Error: {}", e2);

				getTraceback(t);
				Stdout.formatln("{}", getString(t, -1));
				pop(t);
				Stdout.newline;
			}

			return false;
		}

		bool tryAsExpression()
		{
			scope c = new Compiler(t);
			word reg;

			try
				reg = c.compileExpression(buffer, "CLI");
			catch(CrocException e)
			{
				catchException(t);
				pop(t);

				if(c.isEof())
				{
					mPrompt = Prompt2;
					return true;
				}
				else
					return tryAsStatement(e);
			}

			try
			{
				newFunction(t, reg);
				insertAndPop(t, -2);

				pushNull(t);
				auto numRets = rawCall(t, reg, -1);

				if(numRets > 0)
				{
					Stdout(" => ");

					bool first = true;

					for(word i = stackSize(t) - numRets; i < stackSize(t); i++)
					{
						if(first)
							first = false;
						else
							Stdout(", ");

						reg = pushGlobal(t, "dumpVal");
						pushNull(t);
						dup(t, i);
						pushBool(t, false);
						rawCall(t, reg, 0);
					}

					Stdout.newline;
				}
			}
			catch(CrocException e)
			{
				catchException(t);
				pop(t);

				Stdout.formatln("Error: {}", e);

				getTraceback(t);
				Stdout.formatln("{}", getString(t, -1));
				pop(t);
				Stdout.newline;
			}

			return false;
		}

		// Main loop
		Stdout.formatln("Use exit() or Ctrl+D<Enter> to end.");
		mRunning = true;
		mPrompt = Prompt1;

		auto stackIdx = stackSize(t);
		
		scope(exit)
		{
			// Clean up the exit object
			setStackSize(t, stackIdx);
			cleanupExit(t);

			// Clean up the input
			static if(is(typeof(&mInput.cleanup) == delegate))
				mInput.cleanup(t);
		}

		while(mRunning)
		{
			if(auto diff = stackSize(t) - stackIdx)
				pop(t, diff);

			// Get input
			try
			{
				auto line = mInput.readln(t, mPrompt);

				if(line.ptr is null)
				{
					if(didHalt)
					{
						didHalt = false;
						Stdout.newline;
					}
					else
						break;
				}

				// Look for Ctrl+D
				if(line.contains('\4'))
					break;

				if(buffer.length is 0 && line.trim().length is 0)
				{
					mPrompt = Prompt1;
					continue;
				}

				if(buffer.length == 0)
					buffer ~= line;
				else
					buffer ~= '\n' ~ line;
			}
			catch(CrocHaltException e)
			{
				Stdout.formatln("Halted by keyboard interrupt.");
				didHalt = false;
				mPrompt = Prompt1;
				continue;
			}

			// Execute
			try
			{
				if(couldBeDecl())
				{
					if(tryAsStatement())
						continue;
				}
				else if(tryAsExpression())
					continue;
			}
			catch(CrocHaltException e)
			{
				Stdout.formatln("Halted by keyboard interrupt.");
				didHalt = false;
			}

			mPrompt = Prompt1;
			buffer.length = 0;
		}
	}
}

/**
An alias for CLI instantiated with the default Input type. This is a basic console-
based CLI.
*/
alias CLI!(CrocDefaultInput) ConsoleCLI;
