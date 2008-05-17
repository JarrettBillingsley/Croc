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

import minid.compiler;
import minid.misc;
import minid.types;
import minid.utils;

import Integer = tango.text.convert.Integer;
import tango.io.Console;
import tango.io.GrowBuffer;
import tango.io.Print;
import tango.io.Stdout;
import tango.stdc.ctype;
import utf = tango.text.convert.Utf;

final class BaseLib
{
static:
	private MDString[] typeStrings;
	private MDString toStringStr;

	static this()
	{
		typeStrings = new MDString[MDValue.Type.max + 1];

		for(uint i = MDValue.Type.min; i <= MDValue.Type.max; i++)
			typeStrings[i] = new MDString(MDValue.typeString(cast(MDValue.Type)i));

		toStringStr = new MDString("toString"d);
	}

	public void init(MDContext context)
	{
		auto globals = context.globals;

		auto _Object = new MDObject("Object");
		_Object["clone"] = MDValue(new MDClosure(globals.ns, &objectClone, "Object.clone"));
		globals["Object"d] = _Object;

		globals["StringBuffer"d] =    new MDStringBufferClass(_Object);

		// Really basic stuff
		globals["getTraceback"d] =    new MDClosure(globals.ns, &getTraceback,          "getTraceback");
		globals["haltThread"d] =      new MDClosure(globals.ns, &haltThread,            "haltThread");
		globals["currentThread"d] =   new MDClosure(globals.ns, &currentThread,         "currentThread");
		globals["setModuleLoader"d] = new MDClosure(globals.ns, &setModuleLoader,       "setModuleLoader");
		globals["reloadModule"d] =    new MDClosure(globals.ns, &reloadModule,          "reloadModule");
		globals["removeKey"d] =       new MDClosure(globals.ns, &removeKey,             "removeKey");
		globals["rawSet"d] =          new MDClosure(globals.ns, &rawSet,                "rawSet");
		globals["rawGet"d] =          new MDClosure(globals.ns, &rawGet,                "rawGet");
		globals["runMain"d] =         new MDClosure(globals.ns, &runMain,               "runMain");

		// Functional stuff
		globals["curry"d] =           new MDClosure(globals.ns, &curry,                 "curry");
		globals["bindContext"d] =     new MDClosure(globals.ns, &bindContext,           "bindContext");

		// Reflection-esque stuff
		globals["findGlobal"d] =      new MDClosure(globals.ns, &findGlobal,            "findGlobal");
		globals["isSet"d] =           new MDClosure(globals.ns, &isSet,                 "isSet");
		globals["typeof"d] =          new MDClosure(globals.ns, &mdtypeof,              "typeof");
		globals["fieldsOf"d] =        new MDClosure(globals.ns, &fieldsOf,              "fieldsOf");
		globals["hasField"d] =        new MDClosure(globals.ns, &hasField,              "hasField");
		globals["hasMethod"d] =       new MDClosure(globals.ns, &hasMethod,             "hasMethod");
		globals["attributesOf"d] =    new MDClosure(globals.ns, &attributesOf,          "attributesOf");
		globals["hasAttributes"d] =   new MDClosure(globals.ns, &hasAttributes,         "hasAttributes");
		globals["isNull"d] =          new MDClosure(globals.ns, &isParam!("null"),      "isNull");
		globals["isBool"d] =          new MDClosure(globals.ns, &isParam!("bool"),      "isBool");
		globals["isInt"d] =           new MDClosure(globals.ns, &isParam!("int"),       "isInt");
		globals["isFloat"d] =         new MDClosure(globals.ns, &isParam!("float"),     "isFloat");
		globals["isChar"d] =          new MDClosure(globals.ns, &isParam!("char"),      "isChar");
		globals["isString"d] =        new MDClosure(globals.ns, &isParam!("string"),    "isString");
		globals["isTable"d] =         new MDClosure(globals.ns, &isParam!("table"),     "isTable");
		globals["isArray"d] =         new MDClosure(globals.ns, &isParam!("array"),     "isArray");
		globals["isFunction"d] =      new MDClosure(globals.ns, &isParam!("function"),  "isFunction");
		globals["isObject"d] =        new MDClosure(globals.ns, &isParam!("object"),    "isObject");
		globals["isNamespace"d] =     new MDClosure(globals.ns, &isParam!("namespace"), "isNamespace");
		globals["isThread"d] =        new MDClosure(globals.ns, &isParam!("thread"),    "isThread");

		// Conversions
		globals["toString"d] =        new MDClosure(globals.ns, &mdtoString,            "toString");
		globals["rawToString"d] =     new MDClosure(globals.ns, &rawToString,           "rawToString");
		globals["toBool"d] =          new MDClosure(globals.ns, &toBool,                "toBool");
		globals["toInt"d] =           new MDClosure(globals.ns, &toInt,                 "toInt");
		globals["toFloat"d] =         new MDClosure(globals.ns, &toFloat,               "toFloat");
		globals["toChar"d] =          new MDClosure(globals.ns, &toChar,                "toChar");
		globals["format"d] =          new MDClosure(globals.ns, &mdformat,              "format");

		// Console IO
		globals["write"d] =           new MDClosure(globals.ns, &write,                 "write");
		globals["writeln"d] =         new MDClosure(globals.ns, &writeln,               "writeln");
		globals["writef"d] =          new MDClosure(globals.ns, &mdwritef,              "writef");
		globals["writefln"d] =        new MDClosure(globals.ns, &mdwritefln,            "writefln");
		globals["dumpVal"d] =         new MDClosure(globals.ns, &dumpVal,               "dumpVal");
		globals["readln"d] =          new MDClosure(globals.ns, &readln,                "readln");

		// Dynamic compilation stuff
		globals["loadString"d] =      new MDClosure(globals.ns, &loadString,            "loadString");
		globals["eval"d] =            new MDClosure(globals.ns, &eval,                  "eval");
		globals["loadJSON"d] =        new MDClosure(globals.ns, &loadJSON,              "loadJSON");
		globals["toJSON"d] =          new MDClosure(globals.ns, &toJSON,                "toJSON");

		// The Namespace type's metatable
		MDNamespace namespace = new MDNamespace("namespace"d, globals.ns);

		namespace.addList
		(
			"opApply"d, new MDClosure(namespace, &namespaceApply,  "namespace.opApply")
		);

		context.setMetatable(MDValue.Type.Namespace, namespace);

		// The Thread type's metatable
		MDNamespace thread = new MDNamespace("thread"d, globals.ns);

		thread.addList
		(
			"reset"d,       new MDClosure(thread, &threadReset, "thread.reset"),
			"state"d,       new MDClosure(thread, &threadState, "thread.state"),
			"isInitial"d,   new MDClosure(thread, &isInitial,   "thread.isInitial"),
			"isRunning"d,   new MDClosure(thread, &isRunning,   "thread.isRunning"),
			"isWaiting"d,   new MDClosure(thread, &isWaiting,   "thread.isWaiting"),
			"isSuspended"d, new MDClosure(thread, &isSuspended, "thread.isSuspended"),
			"isDead"d,      new MDClosure(thread, &isDead,      "thread.isDead"),
			"opApply"d,     new MDClosure(thread, &threadApply, "thread.opApply",
			[
				MDValue(new MDClosure(thread, &threadIterator, "thread.iterator"))
			])
		);

		context.setMetatable(MDValue.Type.Thread, thread);

		// The Function type's metatable
		MDNamespace func = new MDNamespace("function"d, globals.ns);
		
		func.addList
		(
			"environment"d, new MDClosure(func, &functionEnvironment, "function.environment"),
			"isNative"d,    new MDClosure(func, &functionIsNative,    "function.isNative"),
			"numParams"d,   new MDClosure(func, &functionNumParams,   "function.numParams"),
			"isVararg"d,    new MDClosure(func, &functionIsVararg,    "function.isVararg")
		);

		context.setMetatable(MDValue.Type.Function, func);
	}

	int objectClone(MDState s, uint numParams)
	{
		auto self = s.getContext!(MDObject);
		s.push(new MDObject(self.name, self));
		return 1;
	}

	int mdwritefln(MDState s, uint numParams)
	{
		char[256] buffer = void;
		char[] buf = buffer;

		uint sink(dchar[] data)
		{
			buf = utf.toString(data, buf);
			Stdout(buf);
			return data.length;
		}

		formatImpl(s, s.getAllParams(), &sink);
		Stdout.newline;
		return 0;
	}

	int mdwritef(MDState s, uint numParams)
	{
		char[256] buffer = void;
		char[] buf = buffer;

		uint sink(dchar[] data)
		{
			buf = utf.toString(data, buf);
			Stdout(buf);
			return data.length;
		}

		formatImpl(s, s.getAllParams(), &sink);
		Stdout.flush;
		return 0;
	}
	
	int writeln(MDState s, uint numParams)
	{
		char[256] buffer = void;
		char[] buf = buffer;

		for(uint i = 0; i < numParams; i++)
		{
			buf = utf.toString(s.valueToString(s.getParam(i)).mData, buf);
			Stdout(buf);
		}

		Stdout.newline;
		return 0;
	}

	int write(MDState s, uint numParams)
	{
		char[256] buffer = void;
		char[] buf = buffer;

		for(uint i = 0; i < numParams; i++)
		{
			buf = utf.toString(s.valueToString(s.getParam(i)).mData, buf);
			Stdout(buf);
		}

		Stdout.flush;
		return 0;
	}

	int dumpVal(MDState s, uint numParams)
	{
		void outputRepr(ref MDValue v)
		{
			if(s.hasPendingHalt())
				throw new MDHaltException();
	
			static bool[MDBaseObject] shown;
	
			void escape(dchar c)
			{
				switch(c)
				{
					case '\'': Stdout(`\'`); break;
					case '\"': Stdout(`\"`); break;
					case '\\': Stdout(`\\`); break;
					case '\a': Stdout(`\a`); break;
					case '\b': Stdout(`\b`); break;
					case '\f': Stdout(`\f`); break;
					case '\n': Stdout(`\n`); break;
					case '\r': Stdout(`\r`); break;
					case '\t': Stdout(`\t`); break;
					case '\v': Stdout(`\v`); break;
	
					default:
						if(c <= 0x7f && isprint(c))
							Stdout(c);
						else if(c <= 0xFFFF)
							Stdout.format("\\u{:x4}", cast(uint)c);
						else
							Stdout.format("\\U{:x8}", cast(uint)c);
						break;
				}
			}
			
			void delegate(MDArray) outputArray;
			void delegate(MDTable) outputTable;
	
			void outputArray_(MDArray a)
			{
				if(a in shown)
				{
					Stdout("[...]");
					return;
				}
	
				shown[a] = true;
				
				scope(exit)
					shown.remove(a);
	
				Stdout('[');
	
				if(a.length > 0)
				{
					outputRepr(*a[0]);
	
					for(int i = 1; i < a.length; i++)
					{
						if(s.hasPendingHalt())
							throw new MDHaltException();
	
						Stdout(", ");
						outputRepr(*a[i]);
					}
				}
	
				Stdout(']');
			}
	
			void outputTable_(MDTable t)
			{
				if(t in shown)
				{
					Stdout("{...}");
					return;
				}
	
				shown[t] = true;
	
				Stdout('{');
	
				if(t.length > 0)
				{
					if(t.length == 1)
					{
						foreach(k, v; t)
						{
							if(s.hasPendingHalt())
								throw new MDHaltException();
					
							Stdout('[');
							outputRepr(k);
							Stdout("] = ");
							outputRepr(v);
						}
					}
					else
					{
						bool first = true;
	
						foreach(k, v; t)
						{
							if(first)
								first = !first;
							else
								Stdout(", ");
								
							if(s.hasPendingHalt())
								throw new MDHaltException();
	
							Stdout('[');
							outputRepr(k);
							Stdout("] = ");
							outputRepr(v);
						}
					}
				}
	
				Stdout('}');

				shown.remove(t);
			}
	
			outputArray = &outputArray_;
			outputTable = &outputTable_;
	
			if(v.isString)
			{
				Stdout('"');
				
				auto s = v.as!(MDString);
	
				for(int i = 0; i < s.length; i++)
					escape(s[i]);
	
				Stdout('"');
			}
			else if(v.isChar)
			{
				Stdout("'");
				escape(v.as!(dchar));
				Stdout("'");
			}
			else if(v.isArray)
				outputArray(v.as!(MDArray));
			else if(v.isTable)
			{
				if(s.hasMethod(v, toStringStr))
					Stdout(s.valueToString(v));
				else
					outputTable(v.as!(MDTable));
			}
			else
				Stdout(s.valueToString(v));
		}

		outputRepr(s.getParam(0u));
		
		if(numParams == 1 || (numParams > 1 && s.getParam!(bool)(1)))
			Stdout.newline;

		return 0;
	}

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

		formatImpl(s, s.getAllParams(), &sink);
		s.push(ret);
		return 1;
	}

	int findGlobal(MDState s, uint numParams)
	{
		auto ns = s.findGlobal(s.getParam!(MDString)(0), 1);

		if(ns is null)
			s.pushNull();
		else
			s.push(ns);

		return 1;
	}

	int isSet(MDState s, uint numParams)
	{
		s.push(s.findGlobal(s.getParam!(MDString)(0), 1) !is null);
		return 1;
	}

	int mdtypeof(MDState s, uint numParams)
	{
		s.push(s.getParam(0u).typeString());
		return 1;
	}

	int mdtoString(MDState s, uint numParams)
	{
		auto val = s.getParam(0u);
		
		if(val.isInt())
		{
			char style = 'd';

			if(numParams > 1)
				style = s.getParam!(char)(1);

			s.push(Integer.toString32(val.as!(int), cast(Integer.Style)style));
		}
		else
			s.push(s.valueToString(s.getParam(0u)));

		return 1;
	}
	
	int rawToString(MDState s, uint numParams)
	{
		s.push(s.getParam(0u).toString());
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

	int toBool(MDState s, uint numParams)
	{
		s.push(s.getParam(0u).isTrue());
		return 1;
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
		else
			s.throwRuntimeException("Container must be a table or namespace");

		return 0;
	}

	int fieldsOf(MDState s, uint numParams)
	{
		if(s.isParam!("object")(0))
			s.push(s.getParam!(MDObject)(0).fields);
		else
			s.throwRuntimeException("Expected object, not '{}'", s.getParam(0u).typeString());

		return 1;
	}
	
	int hasField(MDState s, uint numParams)
	{
		s.push(s.hasField(s.getParam(0u), s.getParam!(MDString)(1)));
		return 1;
	}

	int hasMethod(MDState s, uint numParams)
	{
		s.push(s.hasMethod(s.getParam(0u), s.getParam!(MDString)(1)));
		return 1;
	}

	int attributesOf(MDState s, uint numParams)
	{
		MDTable ret;

		if(s.isParam!("function")(0))
			ret = s.getParam!(MDClosure)(0).attributes;
		else if(s.isParam!("object")(0))
			ret = s.getParam!(MDObject)(0).attributes;
		else if(s.isParam!("namespace")(0))
			ret = s.getParam!(MDNamespace)(0).attributes;
		else
			s.throwRuntimeException("Expected function, class, or namespace, not '{}'", s.getParam(0u).typeString());

		if(ret is null)
			s.pushNull();
		else
			s.push(ret);

		return 1;
	}
	
	int hasAttributes(MDState s, uint numParams)
	{
		MDTable ret;

		if(s.isParam!("function")(0))
			ret = s.getParam!(MDClosure)(0).attributes;
		else if(s.isParam!("object")(0))
			ret = s.getParam!(MDObject)(0).attributes;
		else if(s.isParam!("namespace")(0))
			ret = s.getParam!(MDNamespace)(0).attributes;

		s.push(ret !is null);
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
		uint numRets = s.rawCall(threadIdx, -1) + 1;

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
		s.rawCall(funcReg, 0);

		s.push(s.getUpvalue(0u));
		s.push(thread);
		s.push(0);
		return 3;
	}

	int threadReset(MDState s, uint numParams)
	{
		MDClosure cl;

		if(numParams > 0)
			cl = s.getParam!(MDClosure)(0);

		s.getContext!(MDState).reset(cl);
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

	int curry(MDState s, uint numParams)
	{
		struct Closure
		{
			MDClosure func;
			MDValue val;

			int call(MDState s, uint numParams)
			{
				uint funcReg = s.push(func);
				s.push(s.getContext());
				s.push(val);
				
				for(uint i = 0; i < numParams; i++)
					s.push(s.getParam(i));
					
				return s.rawCall(funcReg, -1);
			}
		}
		
		auto cl = new Closure;
		cl.func = s.getParam!(MDClosure)(0);
		cl.val = s.getParam(1u);
		
		s.push(new MDClosure(cl.func.environment, &cl.call, "curryClosure"));
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

				return s.rawCall(funcReg, -1);
			}
		}

		auto cl = new Closure;
		cl.func = s.getParam!(MDClosure)(0);
		cl.context = s.getParam(1u);

		s.push(new MDClosure(cl.func.environment, &cl.call, "bound function"));
		return 1;
	}
	
	int reloadModule(MDState s, uint numParams)
	{
		s.push(s.context.reloadModule(s.getParam!(MDString)(0).mData, s));
		return 1;
	}

	int loadString(MDState s, uint numParams)
	{
		char[] name;
		MDNamespace env;

		if(numParams > 1)
		{
			if(s.isParam!("string")(1))
			{
				name = s.getParam!(char[])(1);

				if(numParams > 2)
					env = s.getParam!(MDNamespace)(2);
				else
					env = s.environment(1);
			}
			else
				env = s.getParam!(MDNamespace)(1);
		}
		else
		{
			name = "<loaded by loadString>";
			env = s.environment(1);
		}

		MDFuncDef def = Compiler().compileStatements(s.getParam!(dchar[])(0), name);
		s.push(new MDClosure(env, def));
		return 1;
	}
	
	int eval(MDState s, uint numParams)
	{
		MDFuncDef def = Compiler().compileExpression(s.getParam!(dchar[])(0), "<loaded by eval>");
		MDNamespace env;

		if(numParams > 1)
			env = s.getParam!(MDNamespace)(1);
		else
			env = s.environment(1);

		return s.call(new MDClosure(env, def), -1);
	}
	
	int loadJSON(MDState s, uint numParams)
	{
		s.push(Compiler().loadJSON(s.getParam!(dchar[])(0)));
		return 1;
	}

	int toJSON(MDState s, uint numParams)
	{
		MDValue root = s.getParam(0u);
		bool pretty = false;

		if(numParams > 1)
			pretty = s.getParam!(bool)(1);

		scope cond = new GrowBuffer();
		scope printer = new Print!(dchar)(FormatterD, cond);

		toJSONImpl(s, root, pretty, printer);

		s.push(cast(dchar[])cond.slice());
		return 1;
	}

	int setModuleLoader(MDState s, uint numParams)
	{
		s.context.setModuleLoader(s.getParam!(dchar[])(0), s.getParam!(MDClosure)(1));
		return 0;
	}
	
	int rawSet(MDState s, uint numParams)
	{
		if(s.isParam!("table")(0))
			s.getParam!(MDTable)(0)[s.getParam(1u)] = s.getParam(2u);
		else if(s.isParam!("object")(0))
			s.getParam!(MDObject)(0)[s.getParam!(MDString)(1)] = s.getParam(2u);
		else
			s.throwRuntimeException("'table' or 'object' expected, not '{}'", s.getParam(0u).typeString());

		return 0;
	}
	
	int rawGet(MDState s, uint numParams)
	{
		if(s.isParam!("table")(0))
			s.push(s.getParam!(MDTable)(0)[s.getParam(1u)]);
		else if(s.isParam!("object")(0))
			s.push(s.getParam!(MDObject)(0)[s.getParam!(MDString)(1)]);
		else
			s.throwRuntimeException("'table' or 'object' expected, not '{}'", s.getParam(0u).typeString());

		return 1;
	}
	
	int runMain(MDState s, uint numParams)
	{
		auto ns = s.getParam!(MDNamespace)(0);

		if(auto main = "main"d in ns)
		{
			auto funcReg = s.push(main);
			s.push(ns);

			for(uint i = 1; i < numParams; i++)
				s.push(s.getParam(i));

			s.rawCall(funcReg, 0);
		}
		
		return 0;
	}
	
	int haltThread(MDState s, uint numParams)
	{
		if(numParams == 0)
			s.halt();
		else
		{
			auto thread = s.getParam!(MDState)(0);
			thread.pendingHalt();
			s.call(thread, 0);
		}

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
	
	int functionIsNative(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDClosure).isNative);
		return 1;
	}
	
	int functionNumParams(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDClosure).numParams);
		return 1;
	}
	
	int functionIsVararg(MDState s, uint numParams)
	{
		s.push(s.getContext!(MDClosure).isVararg);
		return 1;
	}

	static class MDStringBufferClass : MDObject
	{
		MDClosure iteratorClosure;
		MDClosure iteratorReverseClosure;

		public this(MDObject owner)
		{
			super("StringBuffer", owner);

			iteratorClosure = new MDClosure(fields, &iterator, "StringBuffer.iterator");
			iteratorReverseClosure = new MDClosure(fields, &iteratorReverse, "StringBuffer.iteratorReverse");
			auto catEq = new MDClosure(fields, &opCatAssign, "StringBuffer.opCatAssign");

			fields.addList
			(
				"clone"d,          new MDClosure(fields, &clone,          "StringBuffer.clone"),
				"append"d,         catEq,
				"opCatAssign"d,    catEq,
				"insert"d,         new MDClosure(fields, &insert,         "StringBuffer.insert"),
				"remove"d,         new MDClosure(fields, &remove,         "StringBuffer.remove"),
				"toString"d,       new MDClosure(fields, &toString,       "StringBuffer.toString"),
				"opLengthAssign"d, new MDClosure(fields, &opLengthAssign, "StringBuffer.opLengthAssign"),
				"opLength"d,       new MDClosure(fields, &opLength,       "StringBuffer.opLength"),
				"opIndex"d,        new MDClosure(fields, &opIndex,        "StringBuffer.opIndex"),
				"opIndexAssign"d,  new MDClosure(fields, &opIndexAssign,  "StringBuffer.opIndexAssign"),
				"opApply"d,        new MDClosure(fields, &opApply,        "StringBuffer.opApply"),
				"opSlice"d,        new MDClosure(fields, &opSlice,        "StringBuffer.opSlice"),
				"opSliceAssign"d,  new MDClosure(fields, &opSliceAssign,  "StringBuffer.opSliceAssign"),
				"reserve"d,        new MDClosure(fields, &reserve,        "StringBuffer.reserve"),
				"format"d,         new MDClosure(fields, &format,         "StringBuffer.format"),
				"formatln"d,       new MDClosure(fields, &formatln,       "StringBuffer.formatln")
			);
		}

		public int clone(MDState s, uint numParams)
		{
			MDStringBuffer ret;

			if(numParams > 0)
			{
				if(s.isParam!("int")(0))
					ret = new MDStringBuffer(this, s.getParam!(uint)(0));
				else if(s.isParam!("string")(0))
					ret = new MDStringBuffer(this, s.getParam!(dchar[])(0));
				else
					s.throwRuntimeException("'int' or 'string' expected for constructor, not '{}'", s.getParam(0u).typeString());
			}
			else
				ret = new MDStringBuffer(this);
				
			s.push(ret);
			return 1;
		}

		public int opCatAssign(MDState s, uint numParams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);
			
			for(uint j = 0; j < numParams; j++)
			{
				MDValue param = s.getParam(j);

				if(param.isObj)
				{
					if(param.isObject)
					{
						MDStringBuffer other = cast(MDStringBuffer)param.as!(MDObject);
		
						if(other)
						{
							i.append(other);
							continue;
						}
					}
		
					i.append(s.valueToString(param));
				}
				else
					i.append(param.toString());
			}
			
			return 0;
		}

		public int insert(MDState s, uint numparams)
		{
			MDStringBuffer i = s.getContext!(MDStringBuffer);
			MDValue param = s.getParam(1u);

			if(param.isObj)
			{
				if(param.isObject)
				{
					MDStringBuffer other = cast(MDStringBuffer)param.as!(MDObject);
					
					if(other)
					{
						i.insert(s.getParam!(int)(0), other);
						return 0;
					}
				}
				
				i.insert(s.getParam!(int)(0), s.valueToString(param));
			}
			else
				i.insert(s.getParam!(int)(0), param.toString());

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
		
		public int opLengthAssign(MDState s, uint numParams)
		{
			int newLen = s.getParam!(int)(0);
			
			if(newLen < 0)
				s.throwRuntimeException("Invalid length ({})", newLen);

			s.getContext!(MDStringBuffer).length = newLen;
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
		
		public int format(MDState s, uint numParams)
		{
			auto self = s.getContext!(MDStringBuffer);

			uint sink(dchar[] data)
			{
				self.append(data);
				return data.length;
			}

			formatImpl(s, s.getAllParams(), &sink);
			return 0;
		}

		public int formatln(MDState s, uint numParams)
		{
			auto self = s.getContext!(MDStringBuffer);

			uint sink(dchar[] data)
			{
				self.append(data);
				return data.length;
			}

			formatImpl(s, s.getAllParams(), &sink);
			self.append("\n"d);
			return 0;
		}
	}

	static class MDStringBuffer : MDObject
	{
		protected dchar[] mBuffer;
		protected size_t mLength = 0;

		public this(MDStringBufferClass owner)
		{
			super("StringBuffer", owner);
			mBuffer = new dchar[32];
		}

		public this(MDStringBufferClass owner, size_t size)
		{
			super("StringBuffer", owner);
			mBuffer = new dchar[size];
		}

		public this(MDStringBufferClass owner, dchar[] data)
		{
			super("StringBuffer", owner);
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
			append(utf.toString32(s));
		}
		
		public void append(dchar[] s)
		{
			resize(s.length);
			mBuffer[mLength .. mLength + s.length] = s[];
			mLength += s.length;
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

			dchar[] str = utf.toString32(s);
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
}