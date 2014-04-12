#include <assert.h>
#include <setjmp.h>

#ifdef _WIN32
#include "windows.h"
#else
#include <signal.h>
#endif

#include "croc/api.h"

const char* Src =
R"xxxx(//#line 14
local _loadLibs = _croctmp._loadLibs
local _setInterruptibleThread = _croctmp._setInterruptibleThread
local _haltWasTriggered = _croctmp._haltWasTriggered
local _resetInterrupt = _croctmp._resetInterrupt

local Version = "Croc alpha"

if(#_croctmp._addons)
	Version ~= " (Available addons: " ~ ", ".join(_croctmp._addons) ~ ")"

local namespace ExitCode
{
	OK = 0
	BadArg = 1
	OtherError = 2
}

local ShortUsage =
@`Usage:
    croc [options] [filename [args]]   run file with args, or enter REPL
    croc [options] -e "string"         run "string"
    croc --compile outpath filename    compile module to bytecode
    croc --doctable outname filename   extract doctable as JSON
    croc --help (or croc -h)           prints the full help and exits
    croc --version (or croc -v)        prints version and exits

Options:
    -d (or --debug)                    load debug lib
    --docs=<on|off|default>            doc comment mode
    -I "path"                          add import path
    -l dotted.module.name              import module
    --safe                             safe libs only (overrides -d)`

local LongUsage =
@`This is the Croc standalone interpreter. It can be run in several different
modes, and the modes in which code is executed can also take options.

The execution options are as follows:
    -d, --debug
        Load the debug library.

    --docs=<on|off|default>
        Control whether documentation comments are extracted and attached to
        objects. The default is to enable them in interactive mode and disable
        them in file and string mode.

    -I "path"
        Specifies an import path to search when importing modules. You can
        add multiple import paths.

    -l dotted.module.name
        Imports the module "dotted.module.name" before running your code. You
        can have multiple imports.

    --safe
        Only load safe libraries. Overrides -d (prevents the debug library
        from being loaded even if -d is specified).

The execution modes are as follows:
    croc [options]
        Interactive mode. You are given a REPL where the code you type is
        immediately executed (once you type enough to form a valid statement
        or expression). You can exit this by calling 'exit()' or by typing
        Ctrl+D and hitting enter.

    croc [options] filename [args...]
        File mode. 'filename' can be either a path to a .croc or .croco file,
        or it can be a dotted.module.name. In either case, the given file or
        module is loaded/imported, and its main() function (if any) will be
        called with 'args' as the arguments. All the arguments will be
        strings.

    croc [options] -e "string"
        String mode. 'string' will be executed as if you typed it in at the
        REPL (it will be parsed as an expression or statement, whichever is
        appropriate).

    croc --compile outpath filename
        Compiles the module given by 'filename' (which must be an actual
        path), and then uses the serializeModule function in the serialization
        library to output the resulting funcdef to a '.croco' file to the
        directory 'outpath'.

        If 'outpath' is -, the output file will be in the same directory as
        the input. Otherwise, it must be a directory.

    croc --doctable outname filename
        Extracts documentation comments from the module given by 'filename'
        (which must be an actual path) and saves the documentation table for
        the file into 'outname' as JSON.

        If 'outname' is -, then the output JSON will be sent to stdout. If
        'filename' is -, then the source will be read from stdin. If
        'filename' is of the form '-name', then stdin will be read, but the
        name following the dash will be used as the filename of the module
        (i.e. the 'file' member of the doctables).

    croc -h
    croc --help
        Prints this message and exit.

    croc -v
    croc --version
        Prints the version info and exit.

Any invalid options are an error. Any extra arguments after options such as -e
and --compile are ignored.

Exit codes:
    0 means execution completed successfully.
    1 means there was an invalid program argument.
    2 means there was some error during execution.
    3 is reserved for something really bad happening.
`

local function printVersion()
	writeln(Version)

local function printUsage(full: bool)
{
	printVersion()
	write(full ? LongUsage : ShortUsage)
}

local function argError(ret, fmt: string, vararg)
{
	write("\nError: ")
	writefln(fmt, vararg)
	writeln()
	printUsage(false)
	ret.stop = true
	ret.failed = true
	return ret
}

local function parseArguments(args: array)
{
	local ret =
	{
		failed = false
		stop = false
		debugEnabled = false
		safe = false
		docsEnabled = "default"
		inputFile = ""
		args = []
		docOutfile = ""
		crocoOutfile = ""
		execStr = ""
		exec = false
	}

	if(#args == 0)
		return ret

	local i = 0

	switch(args[0])
	{
		case "-v", "--version":
			printVersion()
			ret.stop = true
			return ret

		case "-h", "--help":
			printUsage(true)
			ret.stop = true
			return ret

		case "--compile":
			i += 2

			if(i >= #args)
				return argError(ret, "--compile must be followed by two arguments");

			ret.crocoOutfile = args[i - 1]
			ret.inputFile = args[i]
			return ret

		case "--doctable":
			i += 2

			if(i >= #args)
				return argError(ret, "--doctable must be followed by two arguments");

			ret.docOutfile = args[i - 1]
			ret.inputFile = args[i]
			return ret

		default:
			break
	}

	for( ; i < #args; i++)
	{
		switch(args[i])
		{
			case "-v", "--version", "-h", "--help", "--compile", "--doctable":
				return argError(ret, "'{}' flag may not be preceded by options".format(args[i]))

			case "-I":
				i++

				if(i >= #args)
					return argError(ret, "-I must be followed by a path")

				modules.path ~= ';' ~ args[i]
				continue

			case "-d", "--debug":
				ret.debugEnabled = true
				continue

			case "-e":
				i++

				if(i >= #args)
					return argError(ret, "-e must be followed by a string")

				ret.exec = true
				ret.execStr = args[i]
				return ret

			case "--safe":
				ret.safe = true
				continue

			default:
				if(args[i].startsWith("--docs"))
				{
					local pos = args[i].find('=')

					if(pos == #args[i])
						return argError(ret, "Malfomed flag: '{}'", args[i]);

					local mode = args[i][pos + 1 ..]

					switch(mode)
					{
						case "on", "off", "default":
							ret.docsEnabled = mode
							break

						default:
							return argError(ret, "Invalid mode '{}' (must be on, off, or default)", mode)
					}

					continue
				}
				else if(args[i].startsWith("-"))
					return argError(ret, "Unknown flag '{}'", args[i])

				ret.inputFile = args[i]
				ret.args = args[i + 1 ..]
				break
		}

		break
	}

	return ret
}

local function doDocgen(inputFile: string, outputFile: string)
{
	local dt

	try
	{
		local src, name

		if(inputFile.startsWith("-"))
		{
			if(inputFile.length == 1)
				name = "stdin"
			else
				name = inputFile[1 ..]

			src = text.getCodec("utf8").decode(console.stdin.getStream().readAll())
		}
		else
		{
			name = inputFile
			src = file.readTextFile(inputFile)
		}

		compiler.setFlags("all")
		local fd, modName
		fd, modName, dt = compiler.compileModuleDT(src, name)
	}
	catch(e)
	{
		writefln("Error: {}", e)
		return ExitCode.OtherError
	}

	try
	{
		local f = (outputFile is "-") ?
			console.stdout :
			stream.TextWriter(file.outFile(outputFile, "c"))

		json.writeJSON(f, dt, true)
		f.newline()
		f.flush()

		if(f is not console.stdout)
			f.getStream().close()
	}
	catch(e)
	{
		writefln("Error: {}", e)
		return ExitCode.OtherError
	}

	return ExitCode.OK
}

local function filenameOf(p: string)
{
	local _, ret = path.splitAtLastSep(p)
	return ret
}

local function doCompile(inputFile: string, outputFile: string)
{
	if(not inputFile.endsWith(".croc") or not file.exists(inputFile))
	{
		writefln("'{}' is not a valid input filename")
		return ExitCode.BadArg
	}

	if(outputFile is "-")
		outputFile = inputFile ~ 'o'
	else
	{
		if(not file.exists(outputFile) or file.fileType(outputFile) is not "dir")
		{
			writefln("'{}' does not name a directory", outputFile)
			return ExitCode.BadArg
		}

		outputFile = path.join(outputFile, filenameOf(inputFile) ~ 'o')
	}

	try
	{
		local src = file.readTextFile(inputFile)
		local fd, modName = compiler.compileModule(src, inputFile)
		local out = file.outFile(outputFile, "c")
		serialization.serializeModule(fd, modName, out)
		out.close()
	}
	catch(e)
	{
		writefln("Error: {}", e)
		return ExitCode.OtherError
	}

	return ExitCode.OK
}

local function doFile(inputFile: string, docsEnabled: string, args: array)
{
	if(docsEnabled is "on")
		compiler.setFlags("alldocs")

	try
	{
		local modToRun = inputFile

		if(inputFile.endsWith(".croc") or inputFile.endsWith(".croco"))
		{
			local src = file.readTextFile(inputFile)
			local fd, modName = compiler.compileModule(src, inputFile)
			modules.customLoaders[modName] = fd
			modToRun = modName
		}

		modules.runMain(modules.load(modToRun), args.expand())
	}
	catch(e)
	{
		writefln("Error: {}", e)
		writeln(e.tracebackString())
		return ExitCode.OtherError
	}

	return ExitCode.OK
}

local namespace REPL : _G {}

local class ReplInout : repl.ConsoleInout
{
	_thread

	function init()
		:_thread = null

	function cleanup()
		:_thread = null

	function run(fd: funcdef)
	{
		local f = fd.close(REPL)

		if(:_thread)
		{
			assert(:_thread.isDead())
			:_thread.reset(f)
		}
		else
			:_thread = thread.new(f)

		_setInterruptibleThread(:_thread)
		local rets = []

		while(not :_thread.isDead())
		{
			try
				rets.set((:_thread)(with 5))
			catch(e)
			{
				local runEntry = #e.traceback

				for(i: 0 .. #e.traceback)
				{
					if(e.traceback[i].file.startsWith("<croc>.run"))
					{
						runEntry = i
						break
					}
				}

				e.traceback = e.traceback[0 .. runEntry]
				exceptions.rethrow(e)
			}
		}

		if(_haltWasTriggered())
		{
			:writeln("Halted by keyboard interrupt.")
			_resetInterrupt()
			return
		}

		return rets.expand()
	}
}

local function doInteractive(docsEnabled: string)
{
	if(docsEnabled is not "off")
		compiler.setFlags("alldocs")

	printVersion()

	try
		repl.interactive(ReplInout())
	catch(e)
	{
		writefln("Error: {}", e)
		writeln(e.tracebackString())
		return ExitCode.OtherError
	}

	return ExitCode.OK
}

local function doOneLine(code: string)
{
	try
	{
		local needMore, e = repl.runString(ReplInout(), code)

		if(needMore)
		{
			writefln("Error: {}", e)
			writeln(e.tracebackString())
			return ExitCode.OtherError
		}
	}
	catch(e)
	{
		writefln("Error: {}", e)
		writeln(e.tracebackString())
		return ExitCode.OtherError
	}

	return ExitCode.OK
}

return function main(args: array)
{
	local params = parseArguments(args)

	if(params.stop)
		return params.failed ? ExitCode.BadArg : ExitCode.OK
	else if(#params.docOutfile)
		return doDocgen(params.inputFile, params.docOutfile)
	else if(#params.crocoOutfile)
	{
		// Need file lib
		_loadLibs(false, false)
		return doCompile(params.inputFile, params.crocoOutfile)
	}

	_loadLibs(params.safe, params.debugEnabled)

	if(params.exec)
		return doOneLine(params.execStr)
	else if(#params.inputFile)
		return doFile(params.inputFile, params.docsEnabled, params.args)
	else
		return doInteractive(params.docsEnabled)
}
)xxxx";

word_t _loadLibs(CrocThread* t)
{
	auto isSafe = croc_ex_checkBoolParam(t, 1);
	auto loadDebug = croc_ex_checkBoolParam(t, 2);

	if(isSafe)
		croc_vm_loadAvailableAddonsExcept(t, CrocAddons_Unsafe);
	else
	{
		croc_vm_loadUnsafeLibs(t, loadDebug ? CrocUnsafeLib_ReallyAll : CrocUnsafeLib_All);
		croc_vm_loadAllAvailableAddons(t);
	}

	return 0;
}

CrocThread* _interruptThread = nullptr;
bool _triggered = false;

void _triggerIt()
{
	if(!_triggered && _interruptThread)
	{
		croc_thread_pendingHalt(_interruptThread);
		_triggered = true;
	}
}

#ifdef _WIN32
BOOL WINAPI sigHandler(DWORD type)
{
	if(type == CTRL_C_EVENT)
	{
		_triggerIt();
		return TRUE;
	}

	return FALSE;
}
#else
void sigHandler(int type)
{
	(void)type;
	_triggerIt();
	signal(SIGINT, &sigHandler);
}
#endif

word_t _setInterruptibleThread(CrocThread* t)
{
	croc_ex_checkParam(t, 1, CrocType_Thread);
	_interruptThread = croc_getThread(t, 1);
	_triggered = false;
	return 0;
}

word_t _haltWasTriggered(CrocThread* t)
{
	croc_pushBool(t, _triggered);
	return 1;
}

word_t _resetInterrupt(CrocThread* t)
{
	(void)t;
	_triggered = false;
	return 0;
}

jmp_buf unhandled;

word_t unhandledEx(CrocThread* t)
{
	(void)t;
	longjmp(unhandled, 1);
	return 0;
}

int main(int argc, char** argv)
{
#ifdef _WIN32
	if(!SetConsoleCtrlHandler(&sigHandler, TRUE))
	{
		fprintf(stderr, "Could not set Ctrl+C handler");
		return 3;
	}
#else
	if(signal(SIGINT, &sigHandler) == SIG_ERR)
	{
		fprintf(stderr, "Could not set SIGINT handler");
		return 3;
	}
#endif

	auto t = croc_vm_openDefault();
	croc_function_new(t, "_unhandledEx", 1, &unhandledEx, 0);
	croc_eh_setUnhandledExHandler(t);
	croc_popTop(t);

	if(setjmp(unhandled) == 0)
	{
		croc_table_new(t, 0);
			croc_function_new(t, "_loadLibs", 2, &_loadLibs, 0);
			croc_fielda(t, -2, "_loadLibs");
			croc_function_new(t, "_setInterruptibleThread", 1, &_setInterruptibleThread, 0);
			croc_fielda(t, -2, "_setInterruptibleThread");
			croc_function_new(t, "_haltWasTriggered", 0, &_haltWasTriggered, 0);
			croc_fielda(t, -2, "_haltWasTriggered");
			croc_function_new(t, "_resetInterrupt", 0, &_resetInterrupt, 0);
			croc_fielda(t, -2, "_resetInterrupt");

			auto start = croc_getStackSize(t);

			for(auto addon = croc_vm_includedAddons(); *addon != nullptr; addon++)
				croc_pushString(t, *addon);

			croc_array_newFromStack(t, croc_getStackSize(t) - start);
			croc_fielda(t, -2, "_addons");
		croc_newGlobal(t, "_croctmp");

		auto slot = croc_namespace_new(t, "<croc>");
		croc_ex_loadStringWithEnv(t, Src, "<croc>");
		croc_pushNull(t);
		croc_call(t, -2, 1);

		croc_pushGlobal(t, "_G");
		croc_pushString(t, "_croctmp");
		croc_removeKey(t, -2);
		croc_popTop(t);

		assert((uword_t)slot == croc_getStackSize(t) - 1);

		croc_pushNull(t);

		for(int i = 1; i < argc; i++)
			croc_pushString(t, argv[i]);

		croc_array_newFromStack(t, argc - 1);

		int ret;

		if(croc_tryCall(t, slot, 1) == CrocCallRet_Error)
		{
			fprintf(stderr, "-------- Error --------\n");
			croc_pushToString(t, -1);
			fprintf(stderr, "%s\n", croc_getString(t, -1));
			croc_popTop(t);
			croc_dupTop(t);
			croc_pushNull(t);
			croc_methodCall(t, -2, "tracebackString", 1);
			fprintf(stderr, "%s\n", croc_getString(t, -1));
			ret = 2;
		}
		else
			ret = croc_getInt(t, -1);

		croc_vm_close(t);
		return ret;
	}
	else
	{
		fprintf(stderr, "Fatal error\n");
		return 3;
	}
}