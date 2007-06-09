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
import utf = tango.text.convert.Utf;
import tango.text.convert.Layout;
import tango.io.Stdout;
import tango.stdc.ctype;
import tango.io.Console;

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
						s.throwRuntimeException("Unterminated format specifier in parameter {}", formatStrIndex);

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

	static MDString[] typeStrings;
	
	static this()
	{
		typeStrings = new MDString[MDValue.Type.max + 1];

		for(uint i = MDValue.Type.min; i <= MDValue.Type.max; i++)
			typeStrings[i] = new MDString(MDValue.typeString(cast(MDValue.Type)i));
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
		s.push(new MDString(MDState.getTracebackString()));
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

	MDClosure makeNamespaceIterator(MDNamespace ns)
	{
		MDValue[3] upvalues;

		upvalues[0] = ns;
		upvalues[1] = ns.keys;
		upvalues[2] = -1;

		return MDGlobalState().newClosure(&namespaceIterator, "namespaceIterator", upvalues);
	}

	int namespaceApply(MDState s, uint numParams)
	{
		s.push(makeNamespaceIterator(s.getContext!(MDNamespace)));
		return 1;
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
	
	MDClosure threadIteratorClosure;
	
	int threadIterator(MDState s, uint numParams)
	{
		MDState thread = s.getContext!(MDState);
		int index = s.getParam!(int)(0);
		index++;

		s.push(index);
		uint numRets = s.call(s.push(thread), 0, -1) + 1;

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
		
		s.push(threadIteratorClosure);
		s.push(thread);
		s.push(0);
		return 3;
	}
	
	int currentThread(MDState s, uint numParams)
	{
		if(s is MDGlobalState().mainThread)
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
	
	int loadString(MDState s, uint numParams)
	{
		char[] name;
		
		if(numParams > 1)
			name = s.getParam!(char[])(1);
		else
			name = "<loaded by loadString>";
			
		bool dummy;
		MDFuncDef def = compileStatements(s.getParam!(dchar[])(0), name, dummy);
		s.push(new MDClosure(s.environment(1), def));
		return 1;
	}
	
	int eval(MDState s, uint numParams)
	{
		bool dummy;
		MDFuncDef def = compileStatements("return " ~ s.getParam!(dchar[])(0) ~ ";", "<loaded by eval>", dummy);
		MDNamespace env = s.environment(1);
		s.easyCall(new MDClosure(env, def), 1, MDValue(env));
		return 1;
	}
	
	int loadJSON(MDState s, uint numParams)
	{
		MDFuncDef def = compileJSON(s.getParam!(dchar[])(0));
		MDNamespace env = s.environment(1);
		s.easyCall(new MDClosure(env, def), 1, MDValue(env));
		return 1;
	}
	
	int setModuleLoader(MDState s, uint numParams)
	{
		MDGlobalState().setModuleLoader(s.getParam!(dchar[])(0), s.getParam!(MDClosure)(1));
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

	MDStringBufferClass stringBufferClass;

	static class MDStringBufferClass : MDClass
	{
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
		
		MDClosure iteratorClosure;
		MDClosure iteratorReverseClosure;
		
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
		protected uint mLength = 0;

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
}

public void init()
{
	with(MDGlobalState())
	{
		BaseLib lib = new BaseLib();
		lib.stringBufferClass = new BaseLib.MDStringBufferClass();

		globals["StringBuffer"d] =    lib.stringBufferClass;
		globals["assert"d] =          newClosure(&lib.mdassert,              "assert");
		globals["getTraceback"d] =    newClosure(&lib.getTraceback,          "getTraceback");
		globals["typeof"d] =          newClosure(&lib.mdtypeof,              "typeof");
		globals["fieldsOf"d] =        newClosure(&lib.fieldsOf,              "fieldsOf");
		globals["methodsOf"d] =       newClosure(&lib.methodsOf,             "methodsOf");
		globals["toString"d] =        newClosure(&lib.mdtoString,            "toString");
		globals["rawToString"d] =     newClosure(&lib.rawToString,           "rawToString");
		globals["toInt"d] =           newClosure(&lib.toInt,                 "toInt");
		globals["toFloat"d] =         newClosure(&lib.toFloat,               "toFloat");
		globals["toChar"d] =          newClosure(&lib.toChar,                "toChar");
		globals["format"d] =          newClosure(&lib.mdformat,              "format");
		globals["writefln"d] =        newClosure(&lib.mdwritefln,            "writefln");
		globals["writef"d] =          newClosure(&lib.mdwritef,              "writef");
		globals["writeln"d] =         newClosure(&lib.writeln,               "writeln");
		globals["write"d] =           newClosure(&lib.write,                 "write");
		//globals["readf"d] =           newClosure(&lib.readf,                 "readf");
		globals["readln"d] =          newClosure(&lib.readln,                "readln");
		globals["isNull"d] =          newClosure(&lib.isParam!("null"),      "isNull");
		globals["isBool"d] =          newClosure(&lib.isParam!("bool"),      "isBool");
		globals["isInt"d] =           newClosure(&lib.isParam!("int"),       "isInt");
		globals["isFloat"d] =         newClosure(&lib.isParam!("float"),     "isFloat");
		globals["isChar"d] =          newClosure(&lib.isParam!("char"),      "isChar");
		globals["isString"d] =        newClosure(&lib.isParam!("string"),    "isString");
		globals["isTable"d] =         newClosure(&lib.isParam!("table"),     "isTable");
		globals["isArray"d] =         newClosure(&lib.isParam!("array"),     "isArray");
		globals["isFunction"d] =      newClosure(&lib.isParam!("function"),  "isFunction");
		globals["isClass"d] =         newClosure(&lib.isParam!("class"),     "isClass");
		globals["isInstance"d] =      newClosure(&lib.isParam!("instance"),  "isInstance");
		globals["isNamespace"d] =     newClosure(&lib.isParam!("namespace"), "isNamespace");
		globals["isThread"d] =        newClosure(&lib.isParam!("thread"),    "isThread");
		globals["currentThread"d] =   newClosure(&lib.currentThread,         "currentThread");
		globals["curry"d] =           newClosure(&lib.curry,                 "curry");
		globals["loadString"d] =      newClosure(&lib.loadString,            "loadString");
		globals["eval"d] =            newClosure(&lib.eval,                  "eval");
		globals["loadJSON"d] =        newClosure(&lib.loadJSON,              "loadJSON");
		globals["setModuleLoader"d] = newClosure(&lib.setModuleLoader,       "setModuleLoader");

		MDNamespace namespace = MDNamespace.create
		(
			"namespace"d, globals.ns,
			"opApply"d,             newClosure(&lib.namespaceApply,        "namespace.opApply")
		);

		setMetatable(MDValue.Type.Namespace, namespace);

		MDNamespace thread = MDNamespace.create
		(
			"thread"d, globals.ns,
			"state"d,               newClosure(&lib.threadState,           "thread.state"),
			"isInitial"d,           newClosure(&lib.isInitial,             "thread.isInitial"),
			"isRunning"d,           newClosure(&lib.isRunning,             "thread.isRunning"),
			"isWaiting"d,           newClosure(&lib.isWaiting,             "thread.isWaiting"),
			"isSuspended"d,         newClosure(&lib.isSuspended,           "thread.isSuspended"),
			"isDead"d,              newClosure(&lib.isDead,                "thread.isDead"),
			"opApply"d,             newClosure(&lib.threadApply,           "thread.opApply")
		);

		lib.threadIteratorClosure = new MDClosure(thread, &lib.threadIterator, "thread.iterator");

		setMetatable(MDValue.Type.Thread, thread);
		
		MDNamespace func = MDNamespace.create
		(
			"function"d, globals.ns,
			"environment"d,         newClosure(&lib.functionEnvironment,   "function.environment")
		);
		
		setMetatable(MDValue.Type.Function, func);
	}
}