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

module minid.baselib;

import minid.types;
import minid.compiler;
import minid.utils;

import Integer = tango.text.convert.Integer;
import tango.io.Console;
import tango.io.MemoryConduit;
import tango.io.Print;
import tango.io.Stdout;
import tango.stdc.ctype;
import tango.text.convert.Layout;
import utf = tango.text.convert.Utf;

/*
MDValue[] baseUnFormat(MDState s, dchar[] formatStr, Stream input)
{
	MDValue[] output;

	void outputValue(ref MDValue val)
	{
		output ~= val;
	}

	int begin = 0;

	for(int i = 0; i < formatStr.length; i++)
	{
		dchar c = formatStr[i];

		void nextChar()
		{
			i++;

			if(i >= formatStr.length)
				s.throwRuntimeException("Unterminated format specifier");

			c = formatStr[i];
		}

		if(c == '%')
		{
			nextChar();

			if(c == '%')
				continue;

			while(true)
			{
				switch(c)
				{
					case '-', '+', '#', '0', ' ':
						nextChar();
						continue;

					default:
						break;
				}

				break;
			}

			if(c == '*')
				s.throwRuntimeException("Variable length (*) formatting specifiers are unsupported");
			else if(std.ctype.isdigit(c))
			{
				do
					nextChar();
				while(std.ctype.isdigit(c))
			}

			if(c == '.')
			{
				nextChar();

				if(c == '*')
					s.throwRuntimeException("Variable length (*) formatting specifiers are unsupported");
				else if(std.ctype.isdigit(c))
				{
					do
						nextChar();
					while(std.ctype.isdigit(c))
				}
			}
			
			char[] fmt = utf.toUtf8(formatStr[begin .. i + 1]);
			MDValue val;

			switch(c)
			{
				case 'd', 'i', 'b', 'o', 'x', 'X':
					int v;
					input.readf(fmt, &v);
					val = v;
					break;

				case 'e', 'E', 'f', 'F', 'g', 'G', 'a', 'A':
					mdfloat f;
					input.readf(fmt, &f);
					val = f;
					break;

				case 'r', 's':
					char[] v;
					input.readf(fmt, &v);
					val = v;
					break;

				case 'c':
					char v;
					input.readf(fmt, &v);
					val = cast(dchar)v;
					break;

				default:
					// unsupported: %p
					s.throwRuntimeException("Unsupported format specifier '%c'", c);
			}

			outputValue(val);
			begin = i + 1;
		}
	}

	return output;
}
*/

private Layout!(dchar) Formatter;

static this()
{
	Formatter = new Layout!(dchar);
}

void baseFormat(MDState s, MDValue[] params, uint delegate(dchar[]) sink)
{
	void output(dchar[] fmt, MDValue* param, bool isRaw)
	{
		if(param is null)
			Formatter.convert(sink, fmt, "{invalid index}");
		else
		{
			switch(param.type)
			{
				case MDValue.Type.Null:
					Formatter.convert(sink, fmt, "null");
					break;

				case MDValue.Type.Bool:
					Formatter.convert(sink, fmt, param.as!(bool) ? "true" : "false");
					break;

				case MDValue.Type.Int:
					Formatter.convert(sink, fmt, param.as!(int));
					break;

				case MDValue.Type.Float:
					Formatter.convert(sink, fmt, param.as!(mdfloat));
					break;

				case MDValue.Type.Char:
					Formatter.convert(sink, fmt, param.as!(dchar));
					break;

				case MDValue.Type.String:
					Formatter.convert(sink, fmt, param.as!(dchar[]));
					break;

				default:
					if(isRaw)
						Formatter.convert(sink, fmt, param.toUtf8());
					else
						Formatter.convert(sink, fmt, s.valueToString(*param).asUTF32());
					break;
			}
		}
	}
	
	if(params.length > 64)
		s.throwRuntimeException("Too many parameters to format");

	bool[64] used;

	for(int paramIndex = 0; paramIndex < params.length; paramIndex++)
	{
		if(used[paramIndex])
			continue;

  		if(!params[paramIndex].isString())
			output("{}", &params[paramIndex], false);
		else
		{
			MDString formatStr = params[paramIndex].as!(MDString);
			int formatStrIndex = paramIndex;
			int autoIndex = paramIndex + 1;

			MDValue* getParam(int index)
			{
				if(index >= params.length)
					return null;

				return &params[index];
			}

			for(int i = 0; i < formatStr.length; i++)
			{
				dchar c = formatStr[i];

				void nextChar()
				{
					i++;

					if(i >= formatStr.length)
						c = dchar.init;
					else
						c = formatStr[i];
				}

				dchar[20] format = void;
				int iFormat = 0;

				void addChar(dchar c)
				{
					if(iFormat >= format.length)
						s.throwRuntimeException("Format specifier too long in parameter {}", formatStrIndex);

					format[iFormat++] = c;
				}

				if(c != '{')
					sink([c]);
				else
				{
					nextChar();

					if(c == '{')
					{
						sink("{");
						continue;
					}
					
					addChar('{');
					
					bool isRaw = false;

					if(c == 'r')
					{
						isRaw = true;
						nextChar();
					}
					
					int index = autoIndex;

					if(c == '-' || isdigit(c))
					{
						int begin = i;

						if(!isdigit(c))
							s.throwRuntimeException("Format index must have at least one digit in parameter {}", formatStrIndex);

						while(isdigit(c))
							nextChar();

						int offset = Integer.atoi(formatStr.sliceData(begin, i));
						
						index = formatStrIndex + offset + 1;
					}
					else
						autoIndex++;
					
					if(c == ',')
					{
						addChar(',');
						nextChar();
						
						if(c == '-')
						{
							addChar('-');
							nextChar();
						}
						
						if(!isdigit(c))
							s.throwRuntimeException("Format width must have at least one digit in parameter {}", formatStrIndex);

						while(isdigit(c))
						{
							addChar(c);
							nextChar();
						}
					}
					
					if(c == ':')
					{
						addChar(':');
						nextChar();

						while(c != '}')
						{
							addChar(c);
							nextChar();
						}
					}
					
					if(c != '}')
					{
						sink("{missing or misplaced '}'}");
						sink(format[0 .. iFormat]);
						i--;
						continue;
					}

					addChar('}');
					used[index] = true;

					output(format[0 .. iFormat], getParam(index), isRaw);
				}
			}
		}
	}
}

class BaseLib
{
	private static BaseLib lib;
	private static MDString[] typeStrings;
	
	static this()
	{
		lib = new BaseLib();
		
		typeStrings = new MDString[MDValue.Type.max + 1];

		for(uint i = MDValue.Type.min; i <= MDValue.Type.max; i++)
			typeStrings[i] = new MDString(MDValue.typeString(cast(MDValue.Type)i));
	}

	private MDStringBufferClass stringBufferClass;
	
	private this()
	{
		stringBufferClass = new MDStringBufferClass();
	}

	public static void init(MDContext context)
	{
		auto globals = context.globals;

		globals["StringBuffer"d] =    lib.stringBufferClass;
		globals["assert"d] =          new MDClosure(globals.ns, &lib.mdassert,              "assert");
		globals["getTraceback"d] =    new MDClosure(globals.ns, &lib.getTraceback,          "getTraceback");
		globals["typeof"d] =          new MDClosure(globals.ns, &lib.mdtypeof,              "typeof");
		globals["fieldsOf"d] =        new MDClosure(globals.ns, &lib.fieldsOf,              "fieldsOf");
		globals["methodsOf"d] =       new MDClosure(globals.ns, &lib.methodsOf,             "methodsOf");
		globals["toString"d] =        new MDClosure(globals.ns, &lib.mdtoString,            "toString");
		globals["rawToString"d] =     new MDClosure(globals.ns, &lib.rawToString,           "rawToString");
		globals["toInt"d] =           new MDClosure(globals.ns, &lib.toInt,                 "toInt");
		globals["toFloat"d] =         new MDClosure(globals.ns, &lib.toFloat,               "toFloat");
		globals["toChar"d] =          new MDClosure(globals.ns, &lib.toChar,                "toChar");
		globals["format"d] =          new MDClosure(globals.ns, &lib.mdformat,              "format");
		globals["writefln"d] =        new MDClosure(globals.ns, &lib.mdwritefln,            "writefln");
		globals["writef"d] =          new MDClosure(globals.ns, &lib.mdwritef,              "writef");
		globals["writeln"d] =         new MDClosure(globals.ns, &lib.writeln,               "writeln");
		globals["write"d] =           new MDClosure(globals.ns, &lib.write,                 "write");
		//globals["readf"d] =           new MDClosure(globals.ns, &lib.readf,                 "readf");
		globals["readln"d] =          new MDClosure(globals.ns, &lib.readln,                "readln");
		globals["isNull"d] =          new MDClosure(globals.ns, &lib.isParam!("null"),      "isNull");
		globals["isBool"d] =          new MDClosure(globals.ns, &lib.isParam!("bool"),      "isBool");
		globals["isInt"d] =           new MDClosure(globals.ns, &lib.isParam!("int"),       "isInt");
		globals["isFloat"d] =         new MDClosure(globals.ns, &lib.isParam!("float"),     "isFloat");
		globals["isChar"d] =          new MDClosure(globals.ns, &lib.isParam!("char"),      "isChar");
		globals["isString"d] =        new MDClosure(globals.ns, &lib.isParam!("string"),    "isString");
		globals["isTable"d] =         new MDClosure(globals.ns, &lib.isParam!("table"),     "isTable");
		globals["isArray"d] =         new MDClosure(globals.ns, &lib.isParam!("array"),     "isArray");
		globals["isFunction"d] =      new MDClosure(globals.ns, &lib.isParam!("function"),  "isFunction");
		globals["isClass"d] =         new MDClosure(globals.ns, &lib.isParam!("class"),     "isClass");
		globals["isInstance"d] =      new MDClosure(globals.ns, &lib.isParam!("instance"),  "isInstance");
		globals["isNamespace"d] =     new MDClosure(globals.ns, &lib.isParam!("namespace"), "isNamespace");
		globals["isThread"d] =        new MDClosure(globals.ns, &lib.isParam!("thread"),    "isThread");
		globals["currentThread"d] =   new MDClosure(globals.ns, &lib.currentThread,         "currentThread");
		globals["curry"d] =           new MDClosure(globals.ns, &lib.curry,                 "curry");
		globals["loadString"d] =      new MDClosure(globals.ns, &lib.loadString,            "loadString");
		globals["eval"d] =            new MDClosure(globals.ns, &lib.eval,                  "eval");
		globals["loadJSON"d] =        new MDClosure(globals.ns, &lib.loadJSON,              "loadJSON");
		globals["toJSON"d] =          new MDClosure(globals.ns, &lib.toJSON,                "toJSON");
		globals["setModuleLoader"d] = new MDClosure(globals.ns, &lib.setModuleLoader,       "setModuleLoader");
		globals["removeKey"d] =       new MDClosure(globals.ns, &lib.removeKey,             "removeKey");
		globals["bindContext"d] =     new MDClosure(globals.ns, &lib.bindContext,           "bindContext");

		MDNamespace namespace = new MDNamespace("namespace"d, globals.ns);
		
		namespace.addList
		(
			"opApply"d, new MDClosure(namespace, &lib.namespaceApply,  "namespace.opApply")
		);

		context.setMetatable(MDValue.Type.Namespace, namespace);

		MDNamespace thread = new MDNamespace("thread"d, globals.ns);
		
		thread.addList
		(
			"reset"d,       new MDClosure(thread, &lib.threadReset, "thread.reset"),
			"state"d,       new MDClosure(thread, &lib.threadState, "thread.state"),
			"isInitial"d,   new MDClosure(thread, &lib.isInitial,   "thread.isInitial"),
			"isRunning"d,   new MDClosure(thread, &lib.isRunning,   "thread.isRunning"),
			"isWaiting"d,   new MDClosure(thread, &lib.isWaiting,   "thread.isWaiting"),
			"isSuspended"d, new MDClosure(thread, &lib.isSuspended, "thread.isSuspended"),
			"isDead"d,      new MDClosure(thread, &lib.isDead,      "thread.isDead"),
			"opApply"d,     new MDClosure(thread, &lib.threadApply, "thread.opApply",
			[
				MDValue(new MDClosure(thread, &lib.threadIterator, "thread.iterator"))
			])
		);

		context.setMetatable(MDValue.Type.Thread, thread);

		MDNamespace func = new MDNamespace("function"d, globals.ns);
		
		func.addList
		(
			"environment"d, new MDClosure(func, &lib.functionEnvironment, "function.environment")
		);

		context.setMetatable(MDValue.Type.Function, func);
	}

	int mdwritefln(MDState s, uint numParams)
	{
		char[256] buffer = void;
		char[] buf = buffer;

		uint sink(dchar[] data)
		{
			buf = utf.toUtf8(data, buf);
			Stdout(buf);
			return data.length;
		}

		baseFormat(s, s.getAllParams(), &sink);
		Stdout.newline;
		return 0;
	}

	int mdwritef(MDState s, uint numParams)
	{
		char[256] buffer = void;
		char[] buf = buffer;

		uint sink(dchar[] data)
		{
			buf = utf.toUtf8(data, buf);
			Stdout(buf);
			return data.length;
		}

		baseFormat(s, s.getAllParams(), &sink);
		Cout();
		return 0;
	}
	
	int writeln(MDState s, uint numParams)
	{
		for(uint i = 0; i < numParams; i++)
			Stdout.format("{}", s.valueToString(s.getParam(i)).mData);

		Stdout.newline;
		return 0;
	}

	int write(MDState s, uint numParams)
	{
		for(uint i = 0; i < numParams; i++)
			Stdout.format("{}", s.valueToString(s.getParam(i)).mData);

		Cout();
		return 0;
	}

	/*int readf(MDState s, uint numParams)
	{
		MDValue[] ret = s.safeCode(baseUnFormat(s, s.getParam!(dchar[])(0), din));
		
		foreach(ref v; ret)
			s.push(v);
			
		return ret.length;
	}*/
	
	int readln(MDState s, uint numParams)
	{
		s.push(Cin.copyln());
		return 1;
	}

	int mdformat(MDState s, uint numParams)
	{
		dchar[] ret;

		uint sink(dchar[] data)
		{
			ret ~= data;
			return data.length;
		}

		baseFormat(s, s.getAllParams(), &sink);
		s.push(ret);
		return 1;
	}

	int mdtypeof(MDState s, uint numParams)
	{
		s.push(s.getParam(0u).typeString());
		return 1;
	}

	int mdtoString(MDState s, uint numParams)
	{
		s.push(s.valueToString(s.getParam(0u)));
		return 1;
	}
	
	int rawToString(MDState s, uint numParams)
	{
		s.push(s.getParam(0u).toUtf8());
		return 1;
	}

	int getTraceback(MDState s, uint numParams)
	{
		s.push(new MDString(s.context.getTracebackString()));
		return 1;
	}
	
	int isParam(char[] type)(MDState s, uint numParams)
	{
		s.push(s.isParam!(type)(0));
		return 1;
	}

	int mdassert(MDState s, uint numParams)
	{
		MDValue condition = s.getParam(0u);
		
		if(condition.isFalse())
		{
			if(numParams == 1)
				s.throwRuntimeException("Assertion Failed!");
			else
				s.throwRuntimeException("Assertion Failed: {}", s.getParam(1u).toUtf8());
		}
		
		return 0;
	}
	
	int toInt(MDState s, uint numParams)
	{
		MDValue val = s.getParam(0u);

		switch(val.type)
		{
			case MDValue.Type.Bool:
				s.push(cast(int)val.as!(bool));
				break;

			case MDValue.Type.Int:
				s.push(val.as!(int));
				break;

			case MDValue.Type.Float:
				s.push(cast(int)val.as!(mdfloat));
				break;

			case MDValue.Type.Char:
				s.push(cast(int)val.as!(dchar));
				break;
				
			case MDValue.Type.String:
				s.push(s.safeCode(Integer.parse(val.as!(dchar[]), 10)));
				break;
				
			default:
				s.throwRuntimeException("Cannot convert type '{}' to int", val.typeString());
		}

		return 1;
	}
	
	int toFloat(MDState s, uint numParams)
	{
		MDValue val = s.getParam(0u);

		switch(val.type)
		{
			case MDValue.Type.Bool:
				s.push(cast(mdfloat)val.as!(bool));
				break;

			case MDValue.Type.Int:
				s.push(cast(mdfloat)val.as!(int));
				break;

			case MDValue.Type.Float:
				s.push(val.as!(mdfloat));
				break;

			case MDValue.Type.Char:
				s.push(cast(mdfloat)val.as!(dchar));
				break;

			case MDValue.Type.String:
				s.push(s.safeCode(Float.parse(val.as!(dchar[]))));
				break;

			default:
				s.throwRuntimeException("Cannot convert type '{}' to float", val.typeString());
		}

		return 1;
	}
	
	int toChar(MDState s, uint numParams)
	{
		s.push(cast(dchar)s.getParam!(int)(0));
		return 1;
	}

	int namespaceIterator(MDState s, uint numParams)
	{
		MDNamespace namespace = s.getUpvalue!(MDNamespace)(0);
		MDArray keys = s.getUpvalue!(MDArray)(1);
		int index = s.getUpvalue!(int)(2);

		index++;
		s.setUpvalue(2u, index);

		if(index >= keys.length)
			return 0;

		s.push(keys[index]);
		s.push(namespace[keys[index].as!(MDString)]);

		return 2;
	}

	int namespaceApply(MDState s, uint numParams)
	{
		MDNamespace ns = s.getContext!(MDNamespace);

		MDValue[3] upvalues;
		upvalues[0] = ns;
		upvalues[1] = ns.keys;
		upvalues[2] = -1;

		s.push(s.context.newClosure(&namespaceIterator, "namespaceIterator", upvalues));
		return 1;
	}
	
	int removeKey(MDState s, uint numParams)
	{
		MDValue container = s.getParam(0u);

		if(container.isTable())
		{
			MDValue key = s.getParam(1u);
			
			if(key.isNull)
				s.throwRuntimeException("Table key cannot be null");
				
			container.as!(MDTable).remove(key);
		}
		else if(container.isNamespace())
		{
			MDNamespace ns = container.as!(MDNamespace);
			MDString key = s.getParam!(MDString)(1);

			if(!(key in ns))
				s.throwRuntimeException("Key '{}' does not exist in namespace '{}'", key, ns.nameString());

			ns.remove(key);
		}

		return 0;
	}
	
	int fieldsOf(MDState s, uint numParams)
	{
		if(s.isParam!("class")(0))
			s.push(s.getParam!(MDClass)(0).fields);
		else if(s.isParam!("instance")(0))
			s.push(s.getParam!(MDInstance)(0).fields);
		else
			s.throwRuntimeException("Expected class or instance, not '{}'", s.getParam(0u).typeString());
	
		return 1;
	}

	int methodsOf(MDState s, uint numParams)
	{
		if(s.isParam!("class")(0))
			s.push(s.getParam!(MDClass)(0).methods);
		else if(s.isParam!("instance")(0))
			s.push(s.getParam!(MDInstance)(0).methods);
		else
			s.throwRuntimeException("Expected class or instance, not '{}'", s.getParam(0u).typeString());

		return 1;
	}
	
	int threadState(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDState).stateString());
		return 1;
	}
	
	int isInitial(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDState).state() == MDState.State.Initial);
		return 1;
	}
	
	int isRunning(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDState).state() == MDState.State.Running);
		return 1;
	}

	int isWaiting(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDState).state() == MDState.State.Waiting);
		return 1;
	}

	int isSuspended(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDState).state() == MDState.State.Suspended);
		return 1;
	}

	int isDead(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDState).state() == MDState.State.Dead);
		return 1;
	}
	
	int threadIterator(MDState s, uint numParams)
	{
		MDState thread = s.getContext!(MDState);
		int index = s.getParam!(int)(0);
		index++;

		s.push(index);
		
		uint threadIdx = s.push(thread);
		s.pushNull();
		uint numRets = s.call(threadIdx, 1, -1) + 1;

		if(thread.state == MDState.State.Dead)
			return 0;

		return numRets;
	}

	int threadApply(MDState s, uint numParams)
	{
		MDState thread = s.getContext!(MDState);
		MDValue init = s.getParam(0u);

		if(thread.state != MDState.State.Initial)
			s.throwRuntimeException("Iterated coroutine must be in the initial state");

		uint funcReg = s.push(thread);
		s.push(thread);
		s.push(init);
		s.call(funcReg, 2, 0);
		
		s.push(s.getUpvalue(0u));
		s.push(thread);
		s.push(0);
		return 3;
	}
	
	int threadReset(MDState s, uint numParams)
	{
		s.getContext!(MDState).reset();
		return 0;
	}
	
	int currentThread(MDState s, uint numParams)
	{
		if(s is s.context.mainThread)
			s.pushNull();
		else
			s.push(s);

		return 1;
	}

	int curryClosure(MDState s, uint numParams)
	{
		uint funcReg = s.push(s.getUpvalue!(MDClosure)(0));
		s.push(s.getContext());
		s.push(s.getUpvalue(1u));

		for(uint i = 0; i < numParams; i++)
			s.push(s.getParam(i));

		return s.call(funcReg, numParams + 2, -1);
	}

	int curry(MDState s, uint numParams)
	{
		MDValue[2] upvalues;
		upvalues[0] = s.getParam!(MDClosure)(0);
		upvalues[1] = s.getParam(1u);
		
		s.push(new MDClosure(upvalues[0].as!(MDClosure).environment, &curryClosure, "curryClosure", upvalues));
		return 1;
	}
	
	int bindContext(MDState s, uint numParams)
	{
		struct Closure
		{
			MDClosure func;
			MDValue context;

			int call(MDState s, uint numParams)
			{
				uint funcReg = s.push(func);
				s.push(context);

				for(uint i = 0; i < numParams; i++)
					s.push(s.getParam(i));

				return s.call(funcReg, numParams + 1, -1);
			}
		}

		auto cl = new Closure;
		cl.func = s.getParam!(MDClosure)(0);
		cl.context = s.getParam(1u);

		s.push(new MDClosure(cl.func.environment, &cl.call, "bound function"));
		return 1;
	}
	
	int loadString(MDState s, uint numParams)
	{
		char[] name;

		if(numParams > 1)
			name = s.getParam!(char[])(1);
		else
			name = "<loaded by loadString>";

		MDFuncDef def = compileStatements(s.getParam!(dchar[])(0), name);
		s.push(new MDClosure(s.environment(1), def));
		return 1;
	}
	
	int eval(MDState s, uint numParams)
	{
		MDFuncDef def = compileExpression(s.getParam!(dchar[])(0), "<loaded by eval>");
		MDNamespace env;
		
		if(s.callDepth() > 1)
			env = s.environment(1);
		else
			env = s.context.globals.ns;

		s.easyCall(new MDClosure(env, def), 1, MDValue(env));
		return 1;
	}
	
	int loadJSON(MDState s, uint numParams)
	{
		s.push(.loadJSON(s.getParam!(dchar[])(0)));
		return 1;
	}

	static package void toJSONImpl(T)(MDState s, MDValue root, bool pretty, Print!(T) printer)
	{
		bool[MDValue] cycles;

		int indent = 0;

		void newline(int dir = 0)
		{
			printer.newline;

			if(dir > 0)
				indent++;
			else if(dir < 0)
				indent--;

			for(int i = indent; i > 0; i--)
				printer.print("\t");
		}

		void delegate(MDTable) outputTable;
		void delegate(MDArray) outputArray;
		void delegate(ref MDValue) outputValue;

		void _outputTable(MDTable t)
		{
			printer.print("{");
			
			if(pretty)
				newline(1);

			bool first = true;

			foreach(k, ref v; t)
			{
				if(!k.isString())
					s.throwRuntimeException("All keys in a JSON table must be strings");

				if(first)
					first = false;
				else
				{
					printer.print(",");

					if(pretty)
						newline();
				}

				outputValue(k);

				if(pretty)
					printer.print(": ");
				else
					printer.print(":");

				outputValue(v);
			}

			if(pretty)
				newline(-1);

			printer.print("}");
		}

		void _outputArray(MDArray a)
		{
			printer.print("[");

			bool first = true;

			foreach(ref v; a)
			{
				if(first)
					first = false;
				else
				{
					if(pretty)
						printer.print(", ");
					else
						printer.print(",");
				}

				outputValue(v);
			}

			printer.print("]");
		}

		void _outputValue(ref MDValue v)
		{
			switch(v.type)
			{
				case MDValue.Type.Null:
					printer.print("null");
					break;

				case MDValue.Type.Bool:
					printer.print(v.isFalse() ? "false" : "true");
					break;

				case MDValue.Type.Int:
					printer.format("{}", v.as!(int));
					break;

				case MDValue.Type.Float:
					printer.format("{}", v.as!(double));
					break;

				case MDValue.Type.Char:
					printer.print("\"");
					printer.print(v.as!(dchar));
					printer.print("\"");
					break;

				case MDValue.Type.String:
					printer.print('"');

					foreach(c; v.as!(MDString).mData)
					{
						switch(c)
						{
							case '\b': printer.print("\\b"); break;
							case '\f': printer.print("\\f"); break;
							case '\n': printer.print("\\n"); break;
							case '\r': printer.print("\\r"); break;
							case '\t': printer.print("\\t"); break;

							case '"', '\\', '/':
								printer.print("\\");
								printer.print(c);
								break;

							default:
								if(c > 0x7f)
									printer.format("\\u{:x4}", cast(int)c);
								else
									printer.print(c);

								break;
						}
					}

					printer.print('"');
					break;
					
				case MDValue.Type.Table:
					if(v in cycles)
						s.throwRuntimeException("Table is cyclically referenced");
						
					cycles[v] = true;
				
					scope(exit)
						cycles.remove(v);

					outputTable(v.as!(MDTable));
					break;
					
				case MDValue.Type.Array:
					if(v in cycles)
						s.throwRuntimeException("Array is cyclically referenced");
						
					cycles[v] = true;

					scope(exit)
						cycles.remove(v);

					outputArray(v.as!(MDArray));
					break;
					
				default:
					s.throwRuntimeException("Type '{}' is not a valid type for conversion to JSON", v.typeString());
			}
		}

		outputTable = &_outputTable;
		outputArray = &_outputArray;
		outputValue = &_outputValue;

		if(root.isArray())
			outputArray(root.as!(MDArray));
		else if(root.isTable())
			outputTable(root.as!(MDTable));
		else
			s.throwRuntimeException("Root element must be either a table or an array, not a '{}'", root.typeString());

		printer.flush();
	}

	int toJSON(MDState s, uint numParams)
	{
		MDValue root = s.getParam(0u);
		bool pretty = false;

		if(numParams > 1)
			pretty = s.getParam!(bool)(1);

		scope cond = new MemoryConduit();
		scope printer = new Print!(dchar)(Formatter, cond);

		toJSONImpl(s, root, pretty, printer);

		s.push(cast(dchar[])cond.slice());
		return 1;
	}

	int setModuleLoader(MDState s, uint numParams)
	{
		s.context.setModuleLoader(s.getParam!(dchar[])(0), s.getParam!(MDClosure)(1));
		return 0;
	}
	
	int functionEnvironment(MDState s, uint numParams)
	{
		MDClosure cl = s.getContext!(MDClosure);
		
		s.push(cl.environment);

		if(numParams > 0)
			cl.environment = s.getParam!(MDNamespace)(0);

		return 1;
	}

	static class MDStringBufferClass : MDClass
	{
		MDClosure iteratorClosure;
		MDClosure iteratorReverseClosure;

		public this()
		{
			super("StringBuffer", null);

			iteratorClosure = new MDClosure(mMethods, &iterator, "StringBuffer.iterator");
			iteratorReverseClosure = new MDClosure(mMethods, &iteratorReverse, "StringBuffer.iteratorReverse");
			auto catEq = new MDClosure(mMethods, &opCatAssign, "StringBuffer.opCatAssign");

			mMethods.addList
			(
				"constructor"d,   new MDClosure(mMethods, &constructor,   "StringBuffer.constructor"),
				"append"d,        catEq,
				"opCatAssign"d,   catEq,
				"insert"d,        new MDClosure(mMethods, &insert,        "StringBuffer.insert"),
				"remove"d,        new MDClosure(mMethods, &remove,        "StringBuffer.remove"),
				"toString"d,      new MDClosure(mMethods, &toString,      "StringBuffer.toString"),
				"length"d,        new MDClosure(mMethods, &length,        "StringBuffer.length"),
				"opLength"d,      new MDClosure(mMethods, &opLength,      "StringBuffer.opLength"),
				"opIndex"d,       new MDClosure(mMethods, &opIndex,       "StringBuffer.opIndex"),
				"opIndexAssign"d, new MDClosure(mMethods, &opIndexAssign, "StringBuffer.opIndexAssign"),
				"opApply"d,       new MDClosure(mMethods, &opApply,       "StringBuffer.opApply"),
				"opSlice"d,       new MDClosure(mMethods, &opSlice,       "StringBuffer.opSlice"),
				"opSliceAssign"d, new MDClosure(mMethods, &opSliceAssign, "StringBuffer.opSliceAssign"),
				"reserve"d,       new MDClosure(mMethods, &reserve,       "StringBuffer.reserve")
			);
		}

		public MDStringBuffer newInstance()
		{
			return new MDStringBuffer(this);
		}

		public int constructor(MDState s, uint numParams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);
			
			if(numParams > 0)
			{
				if(s.isParam!("int")(0))
					i.constructor(s.getParam!(uint)(0));
				else if(s.isParam!("string")(0))
					i.constructor(s.getParam!(dchar[])(0));
				else
					s.throwRuntimeException("'int' or 'string' expected for constructor, not '{}'", s.getParam(0u).typeString());
			}
			else
				i.constructor();

			return 0;
		}

		public int opCatAssign(MDState s, uint numParams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);
			
			for(uint j = 0; j < numParams; j++)
			{
				MDValue param = s.getParam(j);

				if(param.isObj)
				{
					if(param.isInstance)
					{
						MDStringBuffer other = cast(MDStringBuffer)param.as!(MDInstance);
		
						if(other)
						{
							i.append(other);
							continue;
						}
					}
		
					i.append(s.valueToString(param));
				}
				else
					i.append(param.toUtf8());
			}
			
			return 0;
		}

		public int insert(MDState s, uint numparams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);
			MDValue param = s.getParam(1u);

			if(param.isObj)
			{
				if(param.isInstance)
				{
					MDStringBuffer other = cast(MDStringBuffer)param.as!(MDInstance);
					
					if(other)
					{
						i.insert(s.getParam!(int)(0), other);
						return 0;
					}
				}
				
				i.insert(s.getParam!(int)(0), s.valueToString(param));
			}
			else
				i.insert(s.getParam!(int)(0), param.toUtf8());

			return 0;
		}

		public int remove(MDState s, uint numParams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);
			uint start = s.getParam!(uint)(0);
			uint end = start + 1;

			if(numParams > 1)
				end = s.getParam!(uint)(1);

			i.remove(start, end);
			return 0;
		}
		
		public int toString(MDState s, uint numParams)
		{
			s.push(s.getContext!(MDStringBuffer).toMDString());
			return 1;
		}
		
		public int length(MDState s, uint numParams)
		{
			s.getContext!(MDStringBuffer).length = s.getParam!(uint)(0);
			return 0;
		}
		
		public int opLength(MDState s, uint numParams)
		{
			s.push(s.getContext!(MDStringBuffer).length);
			return 1;
		}
		
		public int opIndex(MDState s, uint numParams)
		{
			s.push(s.getContext!(MDStringBuffer)()[s.getParam!(int)(0)]);
			return 1;
		}

		public int opIndexAssign(MDState s, uint numParams)
		{
			s.getContext!(MDStringBuffer)()[s.getParam!(int)(0)] = s.getParam!(dchar)(1);
			return 0;
		}

		public int iterator(MDState s, uint numParams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);
			int index = s.getParam!(int)(0);

			index++;

			if(index >= i.length)
				return 0;

			s.push(index);
			s.push(i[index]);

			return 2;
		}
		
		public int iteratorReverse(MDState s, uint numParams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);
			int index = s.getParam!(int)(0);
			
			index--;
	
			if(index < 0)
				return 0;
				
			s.push(index);
			s.push(i[index]);
			
			return 2;
		}
		
		public int opApply(MDState s, uint numParams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);

			if(s.isParam!("string")(0) && s.getParam!(MDString)(0) == "reverse"d)
			{
				s.push(iteratorReverseClosure);
				s.push(i);
				s.push(cast(int)i.length);
			}
			else
			{
				s.push(iteratorClosure);
				s.push(i);
				s.push(-1);
			}

			return 3;
		}
		
		public int opSlice(MDState s, uint numParams)
		{
			s.push(s.getContext!(MDStringBuffer)()[s.getParam!(int)(0) .. s.getParam!(int)(1)]);
			return 1;
		}
		
		public int opSliceAssign(MDState s, uint numParams)
		{
			s.getContext!(MDStringBuffer)()[s.getParam!(int)(0) .. s.getParam!(int)(1)] = s.getParam!(dchar[])(2);
			return 0;
		}
		
		public int reserve(MDState s, uint numParams)
		{
			s.getContext!(MDStringBuffer).reserve(s.getParam!(uint)(0));
			return 0;
		}
	}

	static class MDStringBuffer : MDInstance
	{
		protected dchar[] mBuffer;
		protected size_t mLength = 0;

		public this(MDClass owner)
		{
			super(owner);
		}

		public void constructor()
		{
			mBuffer = new dchar[32];
		}

		public void constructor(int size)
		{
			mBuffer = new dchar[size];
		}

		public void constructor(dchar[] data)
		{
			mBuffer = data;
			mLength = mBuffer.length;
		}
		
		public void append(MDStringBuffer other)
		{
			resize(other.mLength);
			mBuffer[mLength .. mLength + other.mLength] = other.mBuffer[0 .. other.mLength];
			mLength += other.mLength;
		}

		public void append(MDString str)
		{
			resize(str.mData.length);
			mBuffer[mLength .. mLength + str.mData.length] = str.mData[];
			mLength += str.mData.length;
		}
		
		public void append(char[] s)
		{
			dchar[] str = utf.toUtf32(s);
			resize(str.length);
			mBuffer[mLength .. mLength + str.length] = str[];
			mLength += str.length;
		}
		
		public void insert(int offset, MDStringBuffer other)
		{
			if(offset > mLength)
				throw new MDException("Offset out of bounds: {}", offset);

			resize(other.mLength);
			
			for(int i = mLength + other.mLength - 1, j = mLength - 1; j >= offset; i--, j--)
				mBuffer[i] = mBuffer[j];
				
			mBuffer[offset .. offset + other.mLength] = other.mBuffer[0 .. other.mLength];
			mLength += other.mLength;
		}
		
		public void insert(int offset, MDString str)
		{
			if(offset > mLength)
				throw new MDException("Offset out of bounds: {}", offset);

			resize(str.mData.length);

			for(int i = mLength + str.mData.length - 1, j = mLength - 1; j >= offset; i--, j--)
				mBuffer[i] = mBuffer[j];

			mBuffer[offset .. offset + str.mData.length] = str.mData[];
			mLength += str.mData.length;
		}

		public void insert(int offset, char[] s)
		{
			if(offset > mLength)
				throw new MDException("Offset out of bounds: {}", offset);

			dchar[] str = utf.toUtf32(s);
			resize(str.length);

			for(int i = mLength + str.length - 1, j = mLength - 1; j >= offset; i--, j--)
				mBuffer[i] = mBuffer[j];

			mBuffer[offset .. offset + str.length] = str[];
			mLength += str.length;
		}
		
		public void remove(uint start, uint end)
		{
			if(end > mLength)
				end = mLength;

			if(start > mLength || start > end)
				throw new MDException("Invalid indices: {} .. {}", start, end);

			for(int i = start, j = end; j < mLength; i++, j++)
				mBuffer[i] = mBuffer[j];

			mLength -= (end - start);
		}
		
		public MDString toMDString()
		{
			return new MDString(mBuffer[0 .. mLength]);
		}
		
		public void length(uint len)
		{
			uint oldLength = mLength;
			mLength = len;

			if(mLength > mBuffer.length)
				mBuffer.length = mLength;
				
			if(mLength > oldLength)
				mBuffer[oldLength .. mLength] = dchar.init;
		}
		
		public uint length()
		{
			return mLength;
		}
		
		public dchar opIndex(int index)
		{
			if(index < 0)
				index += mLength;

			if(index < 0 || index >= mLength)
				throw new MDException("Invalid index: {}", index);

			return mBuffer[index];
		}

		public void opIndexAssign(dchar c, int index)
		{
			if(index < 0)
				index += mLength;

			if(index >= mLength)
				throw new MDException("Invalid index: {}", index);

			mBuffer[index] = c;
		}

		public dchar[] opSlice(int lo, int hi)
		{
			if(lo < 0)
				lo += mLength;

			if(hi < 0)
				hi += mLength;

			if(lo < 0 || lo > hi || hi >= mLength)
				throw new MDException("Invalid indices: {} .. {}", lo, hi);

			return mBuffer[lo .. hi];
		}

		public void opSliceAssign(dchar[] s, int lo, int hi)
		{
			if(lo < 0)
				lo += mLength;

			if(hi < 0)
				hi += mLength;

			if(lo < 0 || lo > hi || hi >= mLength)
				throw new MDException("Invalid indices: {} .. {}", lo, hi);

			if(hi - lo != s.length)
				throw new MDException("Slice length ({}) does not match length of string ({})", hi - lo, s.length);

			mBuffer[lo .. hi] = s[];
		}
		
		public void reserve(int size)
		{
			if(size > mBuffer.length)
				mBuffer.length = size;
		}

		protected void resize(uint length)
		{
			if(length > (mBuffer.length - mLength))
				mBuffer.length = mBuffer.length + length;
		}
	}
	
// 	static class MDBlobClass : MDClass
// 	{
// 		public this()
// 		{
// 			super("Blob", null);
// 
// 			auto catEq = new MDClosure(mMethods, &opCatAssign, "Blob.opCatAssign");
// 
// 			mMethods.addList
// 			(
// 				"constructor"d,   new MDClosure(mMethods, &constructor,   "Blob.constructor"),
// 				"append"d,        catEq,
// 				"opCatAssign"d,   catEq,
// 				"insert"d,        new MDClosure(mMethods, &insert,        "Blob.insert"),
// 				"remove"d,        new MDClosure(mMethods, &remove,        "Blob.remove"),
// 				"toString"d,      new MDClosure(mMethods, &toString,      "Blob.toString"),
// 				"length"d,        new MDClosure(mMethods, &length,        "Blob.length"),
// 				"opLength"d,      new MDClosure(mMethods, &opLength,      "Blob.opLength"),
// 				"opIndex"d,       new MDClosure(mMethods, &opIndex,       "Blob.opIndex"),
// 				"opIndexAssign"d, new MDClosure(mMethods, &opIndexAssign, "Blob.opIndexAssign"),
// 				"opSlice"d,       new MDClosure(mMethods, &opSlice,       "Blob.opSlice"),
// 				"opSliceAssign"d, new MDClosure(mMethods, &opSliceAssign, "Blob.opSliceAssign"),
// 				"reserve"d,       new MDClosure(mMethods, &reserve,       "Blob.reserve")
// 			);
// 		}
// 	}
// 
// 	static class MDBlob : MDInstance
// 	{
// 		private void[] mData;
// 		protected size_t mLength;
// 
// 		public this(MDClass owner)
// 		{
// 			super(owner);
// 		}
// 		
// 		public void constructor()
// 		{
// 			mData = new void[32];
// 		}
// 
// 		public void constructor(int size)
// 		{
// 			mData = new void[size];
// 		}
// 
// 		public void constructor(void[] data)
// 		{
// 			mData = data;
// 			mLength = mData.length;
// 		}
// 	}
}