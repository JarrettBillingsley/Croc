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

import std.stdio;
import std.stream;
import std.format;
import std.conv;
import std.cstream;
import std.stream;

MDValue[] baseUnFormat(MDState s, dchar[] formatStr, Stream input)
{
	MDValue[] output;

	void outputValue(inout MDValue val)
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
			
			char[] fmt = utf.toUTF8(formatStr[begin .. i + 1]);
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

dchar[] baseFormat(MDState s, MDValue[] params)
{
	dchar[] output;

	void outputChar(dchar c)
	{
		output ~= c;
	}

	void outputString(dchar[] s)
	{
		output ~= s;
	}

	void specialFormat(void delegate(dchar) putc, ...)
	{
		doFormat(putc, _arguments, _argptr);
	}

	for(int paramIndex = 0; paramIndex < params.length; paramIndex++)
	{
		if(params[paramIndex].isString())
		{
			MDString formatStr = params[paramIndex].as!(MDString);
			int formatStrIndex = paramIndex;

			int getIntParam(int index)
			{
				if(index >= params.length)
					s.throwRuntimeException("Not enough parameters to format parameter ", formatStrIndex);

				if(params[index].isInt() == false)
					s.throwRuntimeException("Expected 'int' but got '%s' for parameter ", params[index].typeString(), formatStrIndex);

				return params[index].as!(int);
			}

			mdfloat getFloatParam(int index)
			{
				if(index >= params.length)
					s.throwRuntimeException("Not enough parameters to format parameter ", formatStrIndex);

				if(params[index].isFloat() == false)
					s.throwRuntimeException("Expected 'float' but got '%s' for parameter ", params[index].typeString(), formatStrIndex);

				return params[index].as!(mdfloat);
			}

			dchar getCharParam(int index)
			{
				if(index >= params.length)
					s.throwRuntimeException("Not enough parameters to format parameter ", formatStrIndex);

				if(params[index].isChar() == false)
					s.throwRuntimeException("Expected 'char' but got '%s' for parameter ", params[index].typeString(), formatStrIndex);

				return params[index].as!(dchar);
			}

			MDValue getParam(int index)
			{
				if(index >= params.length)
					s.throwRuntimeException("Not enough parameters to format parameter ", formatStrIndex);

				return params[index];
			}

			for(int i = 0; i < formatStr.length; i++)
			{
				dchar[20] formatting;
				int formattingLength = 0;

				void addFormatChar(dchar c)
				{
					if(formattingLength >= formatting.length)
						s.throwRuntimeException("Format specifier too long in parameter ", formatStrIndex);

					formatting[formattingLength] = c;
					formattingLength++;
				}

				dchar c = formatStr[i];

				void nextChar()
				{
					i++;

					if(i >= formatStr.length)
						s.throwRuntimeException("Unterminated format specifier in parameter ", formatStrIndex);

					c = formatStr[i];
				}

				if(c == '%')
				{
					nextChar();

					if(c == '%')
					{
						outputChar('%');
						continue;
					}
					else
						addFormatChar('%');

					while(true)
					{
						switch(c)
						{
							case '-', '+', '#', '0', ' ':
								addFormatChar(c);
								nextChar();
								continue;

							default:
								break;
						}

						break;
					}

					if(c == '*')
						s.throwRuntimeException("Variable length (*) formatting specifiers are unsupported in parameter ", formatStrIndex);
					else if(std.ctype.isdigit(c))
					{
						addFormatChar(c);
						nextChar();

						while(true)
						{
							if(std.ctype.isdigit(c))
							{
								addFormatChar(c);
								nextChar();
								continue;
							}

							break;
						}
					}

					if(c == '.')
					{
						addFormatChar('.');
						nextChar();

						if(c == '*')
							s.throwRuntimeException("Variable length (*) formatting specifiers are unsupported in parameter ", formatStrIndex);
						else if(std.ctype.isdigit(c))
						{
							addFormatChar(c);
							nextChar();

							while(true)
							{
								if(std.ctype.isdigit(c))
								{
									addFormatChar(c);
									nextChar();
									continue;
								}

								break;
							}
						}
					}

					paramIndex++;

					addFormatChar(c);

					switch(c)
					{
						case 'd', 'i', 'b', 'o', 'x', 'X':
							int val = getIntParam(paramIndex);
							specialFormat(&outputChar, formatting[0 .. formattingLength], val);
							break;

						case 'e', 'E', 'f', 'F', 'g', 'G', 'a', 'A':
							mdfloat val;

							if(s.isParam!("int")(paramIndex))
								val = getIntParam(paramIndex);
							else
								val = getFloatParam(paramIndex);

							specialFormat(&outputChar, formatting[0 .. formattingLength], val);
							break;

						case 's':
							MDString val = s.valueToString(getParam(paramIndex));
							specialFormat(&outputChar, formatting[0 .. formattingLength], val.mData);
							break;
							
						case 'r':
							formatting[formattingLength - 1] = 's';
							char[] val = getParam(paramIndex).toString();
							specialFormat(&outputChar, formatting[0 .. formattingLength], val);
							break;

						case 'c':
							dchar val = getCharParam(paramIndex);
							specialFormat(&outputChar, formatting[0 .. formattingLength], val);
							break;

						default:
							// unsupported: %p
							s.throwRuntimeException("Unsupported format specifier '%s' in parameter ", c, formatStrIndex);
					}
				}
				else
					outputChar(c);
			}
		}
		else
		{
			MDString val = s.valueToString(params[paramIndex]);
			outputString(val.mData);
		}
	}

	return output;
}

class BaseLib
{
	int mdwritefln(MDState s, uint numParams)
	{
		writefln("%s", baseFormat(s, s.getAllParams()));
		return 0;
	}

	int mdwritef(MDState s, uint numParams)
	{
		writef("%s", baseFormat(s, s.getAllParams()));
		return 0;
	}
	
	int writeln(MDState s, uint numParams)
	{
		for(uint i = 0; i < numParams; i++)
			writef("%s", s.valueToString(s.getParam(i)).mData);

		writefln();
		return 0;
	}
	
	int write(MDState s, uint numParams)
	{
		for(uint i = 0; i < numParams; i++)
			writef("%s", s.valueToString(s.getParam(i)).mData);

		return 0;
	}

	int readf(MDState s, uint numParams)
	{
		MDValue[] ret = s.safeCode(baseUnFormat(s, s.getParam!(dchar[])(0), din));
		
		foreach(inout v; ret)
			s.push(v);
			
		return ret.length;
	}

	int mdformat(MDState s, uint numParams)
	{
		s.push(baseFormat(s, s.getAllParams()));
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
		s.push(typeStrings[s.getParam(0u).type]);
		return 1;
	}

	int mdtoString(MDState s, uint numParams)
	{
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
				s.throwRuntimeException("Assertion Failed: %s", s.getParam(1u).toString());
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
				s.push(s.safeCode(minid.utils.toInt(val.as!(dchar[]), 10)));
				break;
				
			default:
				s.throwRuntimeException("Cannot convert type '%s' to int", val.typeString());
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
				s.push(s.safeCode(std.conv.toFloat(val.as!(char[]))));
				break;

			default:
				s.throwRuntimeException("Cannot convert type '%s' to float", val.typeString());
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
			s.push(makeNamespaceIterator(s.getParam!(MDClass)(0).fields));
		else if(s.isParam!("instance")(0))
			s.push(makeNamespaceIterator(s.getParam!(MDInstance)(0).fields));
		else
			s.throwRuntimeException("Expected class or instance, not '%s'", s.getParam(0u).typeString());
	
		return 1;
	}
	
	int methodsOf(MDState s, uint numParams)
	{
		if(s.isParam!("class")(0))
			s.push(makeNamespaceIterator(s.getParam!(MDClass)(0).methods));
		else if(s.isParam!("instance")(0))
			s.push(makeNamespaceIterator(s.getParam!(MDInstance)(0).methods));
		else
			s.throwRuntimeException("Expected class or instance, not '%s'", s.getParam(0u).typeString());

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
					s.throwRuntimeException("'int' or 'string' expected for constructor, not '%s'", s.getParam(0u).typeString());
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
							return 0;
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
			dchar[] str = utf.toUTF32(s);
			resize(str.length);
			mBuffer[mLength .. mLength + str.length] = str[];
			mLength += str.length;
		}
		
		public void insert(int offset, MDStringBuffer other)
		{
			if(offset > mLength)
				throw new MDException("Offset out of bounds: ", offset);

			resize(other.mLength);
			
			for(int i = mLength + other.mLength - 1, j = mLength - 1; j >= offset; i--, j--)
				mBuffer[i] = mBuffer[j];
				
			mBuffer[offset .. offset + other.mLength] = other.mBuffer[0 .. other.mLength];
			mLength += other.mLength;
		}
		
		public void insert(int offset, MDString str)
		{
			if(offset > mLength)
				throw new MDException("Offset out of bounds: ", offset);

			resize(str.mData.length);

			for(int i = mLength + str.mData.length - 1, j = mLength - 1; j >= offset; i--, j--)
				mBuffer[i] = mBuffer[j];

			mBuffer[offset .. offset + str.mData.length] = str.mData[];
			mLength += str.mData.length;
		}

		public void insert(int offset, char[] s)
		{
			if(offset > mLength)
				throw new MDException("Offset out of bounds: ", offset);

			dchar[] str = utf.toUTF32(s);
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
				throw new MDException("Invalid indices: %d .. %d", start, end);

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
				throw new MDException("Invalid index: ", index);

			return mBuffer[index];
		}

		public void opIndexAssign(dchar c, int index)
		{
			if(index < 0)
				index += mLength;

			if(index >= mLength)
				throw new MDException("Invalid index: ", index);
				
			mBuffer[index] = c;
		}
		
		public dchar[] opSlice(int lo, int hi)
		{
			if(lo < 0)
				lo += mLength;
				
			if(hi < 0)
				hi += mLength;
				
			if(lo < 0 || lo > hi || hi >= mLength)
				throw new MDException("Invalid indices: %d .. %d", lo, hi);
				
			return mBuffer[lo .. hi];
		}
		
		public void opSliceAssign(dchar[] s, int lo, int hi)
		{
			if(lo < 0)
				lo += mLength;

			if(hi < 0)
				hi += mLength;

			if(lo < 0 || lo > hi || hi >= mLength)
				throw new MDException("Invalid indices: %d .. %d", lo, hi);

			if(hi - lo != s.length)
				throw new MDException("Slice length (%d) does not match length of string (%d)", hi - lo, s.length);

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

		setGlobal("StringBuffer"d,  lib.stringBufferClass);
		setGlobal("assert"d,        newClosure(&lib.mdassert,              "assert"));
		setGlobal("getTraceback"d,  newClosure(&lib.getTraceback,          "getTraceback"));
		setGlobal("typeof"d,        newClosure(&lib.mdtypeof,              "typeof"));
		setGlobal("fieldsOf"d,      newClosure(&lib.fieldsOf,              "fieldsOf"));
		setGlobal("methodsOf"d,     newClosure(&lib.methodsOf,             "methodsOf"));
		setGlobal("toString"d,      newClosure(&lib.mdtoString,            "toString"));
		setGlobal("rawToString"d,   newClosure(&lib.rawToString,           "rawToString"));
		setGlobal("toInt"d,         newClosure(&lib.toInt,                 "toInt"));
		setGlobal("toFloat"d,       newClosure(&lib.toFloat,               "toFloat"));
		setGlobal("toChar"d,        newClosure(&lib.toChar,                "toChar"));
		setGlobal("format"d,        newClosure(&lib.mdformat,              "format"));
		setGlobal("writefln"d,      newClosure(&lib.mdwritefln,            "writefln"));
		setGlobal("writef"d,        newClosure(&lib.mdwritef,              "writef"));
		setGlobal("writeln"d,       newClosure(&lib.writeln,               "writeln"));
		setGlobal("write"d,         newClosure(&lib.write,                 "write"));
		setGlobal("readf"d,         newClosure(&lib.readf,                 "readf"));
		setGlobal("isNull"d,        newClosure(&lib.isParam!("null"),      "isNull"));
		setGlobal("isBool"d,        newClosure(&lib.isParam!("bool"),      "isBool"));
		setGlobal("isInt"d,         newClosure(&lib.isParam!("int"),       "isInt"));
		setGlobal("isFloat"d,       newClosure(&lib.isParam!("float"),     "isFloat"));
		setGlobal("isChar"d,        newClosure(&lib.isParam!("char"),      "isChar"));
		setGlobal("isString"d,      newClosure(&lib.isParam!("string"),    "isString"));
		setGlobal("isTable"d,       newClosure(&lib.isParam!("table"),     "isTable"));
		setGlobal("isArray"d,       newClosure(&lib.isParam!("array"),     "isArray"));
		setGlobal("isFunction"d,    newClosure(&lib.isParam!("function"),  "isFunction"));
		setGlobal("isClass"d,       newClosure(&lib.isParam!("class"),     "isClass"));
		setGlobal("isInstance"d,    newClosure(&lib.isParam!("instance"),  "isInstance"));
		setGlobal("isNamespace"d,   newClosure(&lib.isParam!("namespace"), "isNamespace"));
		setGlobal("isThread"d,      newClosure(&lib.isParam!("thread"),    "isThread"));
		setGlobal("currentThread"d, newClosure(&lib.currentThread,         "currentThread"));
		setGlobal("curry"d,         newClosure(&lib.curry,                 "curry"));

		MDNamespace namespace = MDNamespace.create
		(
			"namespace"d, globals,
			"opApply"d,             newClosure(&lib.namespaceApply,        "namespace.opApply")
		);

		setMetatable(MDValue.Type.Namespace, namespace);

		MDNamespace thread = MDNamespace.create
		(
			"thread"d, globals,
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
	}
}