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

module minid.utils;

import tango.core.Vararg;
import tango.io.Buffer;
import tango.io.FileConduit;
import tango.io.Print;
import tango.io.protocol.model.IReader;
import tango.io.protocol.model.IWriter;
import tango.io.Stdout;
import tango.text.Util;
import tango.util.time.StopWatch;
import tango.text.convert.Utf;
import tango.stdc.string;
import UniChar;

alias double mdfloat;

/// Metafunction to see if a given type is one of char[], wchar[] or dchar[].
template isStringType(T)
{
	const bool isStringType = is(T : char[]) || is(T : wchar[]) || is(T : dchar[]);
}

/// Sees if a type is char, wchar, or dchar.
template isCharType(T)
{
	const bool isCharType = is(T == char) || is(T == wchar) || is(T == dchar);
}

/// Sees if a type is a signed or unsigned byte, short, int, or long.
template isIntType(T)
{
	const bool isIntType = is(T == int) || is(T == uint) || is(T == long) || is(T == ulong) ||
							is(T == short) || is(T == ushort) || is(T == byte) || is(T == ubyte) /* || is(T == cent) || is(T == ucent) */;
}

/// Sees if a type is float, double, or real.
template isFloatType(T)
{
	const bool isFloatType = is(T == float) || is(T == double) || is(T == real);
}

/// Sees if a type is an array.
template isArrayType(T)
{
	const bool isArrayType = false;
}

template isArrayType(T : T[])
{
	const bool isArrayType = true;
}

/// Sees if a type is a pointer.
template isPointerType(T)
{
	const bool isPointerType = is(typeof(*T)) && !isArrayType!(T);
}

/// Get to the bottom of any chain of typedefs!  Returns the first non-typedef'ed type.
template realType(T)
{
	static if(is(T Base == typedef))
		alias realType!(Base) realType;
	else
		alias T realType;
}

/// Determine if a given aggregate type contains any unions, explicit or anonymous.
/// Thanks to Frits van Bommel for the original code.
template hasUnions(T, size_t Idx = 0)
{
	static if(!is(typeof(T.tupleof)))
		const bool hasUnions = false;
	else static if(is(realType!(T) == union))
		const bool hasUnions = true;
	else static if(Idx < T.tupleof.length)
	{
		static if(is(realType!(typeof(T.tupleof)[Idx]) == union))
			const bool hasUnions = true;
		else static if(Idx + 1 < T.tupleof.length && T.tupleof[Idx].offsetof + T.tupleof[Idx].sizeof > T.tupleof[Idx + 1].offsetof)
			const bool hasUnions = true;
		else
		{
			static if(is(typeof(T.tupleof)[Idx] == struct))
				const bool hasUnions = hasUnions!(typeof(T.tupleof)[Idx]) || hasUnions!(T, Idx + 1);
			else
				const bool hasUnions = hasUnions!(T, Idx + 1);
		}
	}
	else
		const bool hasUnions = false;
}

unittest
{
	assert(isStringType!(char[]));
	assert(isStringType!(wchar[]));
	assert(isStringType!(dchar[]));
	assert(!isStringType!(int));
	assert(!isStringType!(Object));
	
	assert(isCharType!(char));
	assert(isCharType!(wchar));
	assert(isCharType!(dchar));
	assert(!isCharType!(int));
	assert(!isCharType!(Object));
	
	assert(isIntType!(int));
	assert(isIntType!(uint));
	assert(isIntType!(byte));
	assert(isIntType!(ulong));
	assert(!isIntType!(float));
	assert(!isIntType!(bool));
	assert(!isIntType!(creal));
	assert(!isIntType!(dchar));

	assert(isFloatType!(float));
	assert(isFloatType!(double));
	assert(isFloatType!(real));
	assert(!isFloatType!(ifloat));
	assert(!isFloatType!(int));
	assert(!isFloatType!(Object));
	
	assert(isArrayType!(int[]));
	assert(isArrayType!(char[]));
	assert(isArrayType!(int[3][4]));
	assert(!isArrayType!(int[int]));
	assert(!isArrayType!(Object));

	assert(isPointerType!(int*));
	assert(!isPointerType!(int[]));
	assert(!isPointerType!(Object));
	
	typedef int X;
	typedef X Y;
	
	assert(is(realType!(X) == int));
	assert(is(realType!(Y) == int));
	
	union U {}
	typedef U V;
	
	struct A {}
	struct B { U u; }
	struct C { V v; }
	struct D { union { int x; int y; } }
	struct E { D d; }

	assert(!hasUnions!(A));
	assert(hasUnions!(B));
	assert(hasUnions!(C));
	assert(hasUnions!(D));
	assert(hasUnions!(E));
}

/// Convert any function pointer into a delegate that calls the function when it's called.
template ToDelegate(alias func)
{
	ReturnType!(func) delegate(ParameterTypeTuple!(func)) ToDelegate()
	{
		struct S
		{
			static S s;

			ReturnType!(func) callMe(ParameterTypeTuple!(func) args)
			{
				return func(args);
			}
		}
	
		return &S.s.callMe;
	}
}

/// Compares dchar[] strings stupidly (just by character value, not lexicographically).
int dcmp(dchar[] s1, dchar[] s2)
{
	auto len = s1.length;

	if(s2.length < len)
		len = s2.length;

	int result = mismatch(s1.ptr, s2.ptr, len);

	if(result == len)
		result = cast(int)s1.length - cast(int)s2.length;
	else
		result = s1[result] - s2[result];

	return result;
}

/// Lowercase a dchar[] using proper Unicode character functions.
dchar[] toLowerD(dchar[] s)
{
	bool changed = false;

	for(int i = 0; i < s.length; i++)
	{
		if(isUniUpper(s[i]))
		{
			if(!changed)
			{
				s = s.dup;
				changed = true;
			}

			s[i] = toUniLower(s[i]);
		}
	}

	return s;
}

/// Uppercase a dchar[] using proper Unicode character functions.
dchar[] toUpperD(dchar[] s)
{
	bool changed = false;

	for(int i = 0; i < s.length; i++)
	{
		if(isUniLower(s[i]))
		{
			if(!changed)
			{
				s = s.dup;
				changed = true;
			}

			s[i] = toUniUpper(s[i]);
		}
	}

	return s;
}

unittest
{
	dchar[] s = "HelloOoO!";
	assert(toLowerD(s) == "helloooo!");
	assert(toUpperD(s) == "HELLOOOO!");
	
	dchar[] t = "hi";
	assert(toLowerD(t) is t);
	assert(toUpperD(t) !is t);
}

/// See if a given Unicode character is valid.
bool isValidUniChar(dchar c)
{
	return c < 0xD800 || (c > 0xDFFF && c <= 0x10FFFF);
}

/// Make a FOURCC code out of a four-character string.  This is I guess for little-endian platforms..
template FOURCC(char[] name)
{
	static assert(name.length == 4, "FOURCC's parameter must be 4 characters");
	const uint FOURCC = (cast(uint)name[3] << 24) | (cast(uint)name[2] << 16) | (cast(uint)name[1] << 8) | cast(uint)name[0];
}

/// Make a version with the major number in the upper 16 bits and the minor in the lower 16 bits.
template MakeVersion(uint major, uint minor)
{
	const uint MakeVersion = (major << 16) | minor;
}

/// The current version of MiniD.  (this is kind of buried here)
const uint MiniDVersion = MakeVersion!(0, 7);

/// See if T is a type that can't be automatically serialized.
template isInvalidSerializeType(T)
{
	const bool isInvalidSerializeType = isPointerType!(T) || is(T == function) || is(T == delegate) ||
		is(T == interface) || is(T == union) || (is(typeof(T.keys)) && is(typeof(T.values)));
}

/// The different ways data can be serialized and deserialized.
enum SerializeMethod
{
	Invalid,
	Vector,
	Sequence,
	Custom,
	Tuple,
	Chunk
}

/// Given a type, determine how to serialize or deserialize a value of that type.
template TypeSerializeMethod(T)
{
	static if(isInvalidSerializeType!(T))
		const TypeSerializeMethod = SerializeMethod.Invalid;
	else static if(isArrayType!(T))
	{
		static if(TypeSerializeMethod!(typeof(T[0])) == SerializeMethod.Invalid)
			const TypeSerializeMethod = SerializeMethod.Invalid;
		else static if(TypeSerializeMethod!(typeof(T[0])) == SerializeMethod.Chunk)
			const TypeSerializeMethod = SerializeMethod.Vector;
		else
			const TypeSerializeMethod = SerializeMethod.Sequence;
	}
	else static if(is(T == class))
		const TypeSerializeMethod = SerializeMethod.Custom;
	else static if(is(T == struct))
	{
		static if(is(typeof(T.SerializeAsChunk)))
			const TypeSerializeMethod = SerializeMethod.Chunk;
		else
		{
			static if(is(typeof(T.serialize)))
			{
				static if(is(typeof(T.deserialize)))
					const TypeSerializeMethod = SerializeMethod.Custom;
				else
					const TypeSerializeMethod = SerializeMethod.Invalid;
			}
			else static if(is(typeof(T.deserialize)))
				const TypeSerializeMethod = SerializeMethod.Invalid;
			else static if(hasUnions!(T))
				const TypeSerializeMethod = SerializeMethod.Invalid;
			else
				const TypeSerializeMethod = SerializeMethod.Tuple;
		}
	}
	else
		const TypeSerializeMethod = SerializeMethod.Chunk;
}

/**
Write out a value to a stream.  This will automatically write out nested arrays and entire structures.
Pointers, functions, delegates, interfaces, unions, and AAs can't be serialized.

For arrays, it will try to write the biggest chunks at a time possible.  So if you write out an int[],
or an S[] where S is a struct type marked as SerializeAsChunk, it will write out all the data in the
array at once.  Otherwise, it'll write out the array element-by-element.

For structs, the following methods are tried:
	1) If the struct has both "void serialize(Stream s)" and "static T deserialize(Stream s)" methods,
	   Serialize/Deserialize will call those.
	2) If the struct has a "const bool SerializeAsChunk = true" declaration in the struct, then it will
	   serialize instances of the struct as chunks of memory.
	3) As a last resort, it will try to write out the struct member-by-member.  If the struct has any
	   unions (explicit or anonymous), the struct will not be able to be automatically serialized, and
	   you will either have to make it chunk-serializable or provide custom serialization methods.

For classes, it will expect for there to be custom serialize/deserialize methods.

For all other types, it will just write them out.  All other types are also considered chunk-serializable,
so arrays of them will be serialized in one call.

If your struct or class declares custom serialize/deserialize methods, it must declare both or neither.
These methods must always follow the form:

	void serialize(Stream s);
	static T deserialize(Stream s);
	
where T is your custom type.
*/
void Serialize(T)(IWriter s, T value)
{
	const method = TypeSerializeMethod!(T);

	static if(method == SerializeMethod.Invalid)
	{
		pragma(msg, "Error: Type '" ~ T.stringof ~ "' cannot be serialized.");
		INVALID_TYPE();
	}
	else static if(method == SerializeMethod.Vector)
	{
		static if(is(T == dchar[]) || is(T == wchar[]))
		{
			s.put(toUtf8(value));
		}
		else
		{
			s.put(value.length);
			s.buffer.append((cast(void*)value.ptr)[0 .. typeof(T[0]).sizeof * value.length]);
		}
	}
	else static if(method == SerializeMethod.Sequence)
	{
		s.put(value.length);

		foreach(v; value)
			Serialize(s, v);
	}
	else static if(method == SerializeMethod.Custom)
	{
		value.serialize(s);
	}
	else static if(method == SerializeMethod.Tuple)
	{
		foreach(member; value.tupleof)
			Serialize(s, member);
	}
	else
	{
		static assert(method == SerializeMethod.Chunk, "Serialize");
		s.buffer.append(&value, T.sizeof);
	}
}

/// The opposite of Serialize().  The same rules apply here as with Serialize().
void Deserialize(T)(IReader s, out T dest)
{
	const method = TypeSerializeMethod!(T);

	static if(method == SerializeMethod.Invalid)
	{
		pragma(msg, "Error: Type '" ~ T.stringof ~ "' cannot be deserialized.");
		INVALID_TYPE();
	}
	else static if(method == SerializeMethod.Vector)
	{
		static if(is(T == dchar[]) || is(T == wchar[]))
		{
			char[] str;
			s.get(str);

			static if(is(T == dchar[]))
				dest = toUtf32(str);
			else
				dest = toUtf16(str);
		}
		else
		{
			size_t length;
			s.get(length);
			dest.length = length;
			s.buffer.read((cast(void*)dest.ptr)[0 .. typeof(T[0]).sizeof * dest.length]);
		}
	}
	else static if(method == SerializeMethod.Sequence)
	{
		size_t len;
		s.get(len);
		dest.length = len;

		foreach(ref v; dest)
			Deserialize(s, v);
	}
	else static if(method == SerializeMethod.Custom)
	{
		dest = T.deserialize(s);
	}
	else static if(method == SerializeMethod.Tuple)
	{
		foreach(member; dest.tupleof)
			Deserialize(s, member);
	}
	else
	{
		static assert(method == SerializeMethod.Chunk, "Deserialize");
		s.buffer.readExact(&dest, T.sizeof);
	}
}

/// A class used for profiling pieces of code.  You initialize it with an output filename,
/// and during execution of your program, you just create instances of this class with a
/// certain name.  Timings for each profile name are accumulated over the course of the program and
/// the final output will show the name of the profile, how many times it was instanced, the
/// tital time in milliseconds, and the average time per instance in milliseconds.
scope class Profiler
{
	private StopWatch mTimer;
	private static Print!(char) mOutLog;

	struct Timing
	{
		char[] name;
		Interval time = 0;
		ulong count = 0;

		static Timing opCall(char[] name)
		{
			Timing t;
			t.name = name;
			return t;
		}

		int opCmp(Timing* other)
		{
			if(time < other.time)
				return 1;
			else if(time == other.time)
				return 0;
			else
				return -1;
		}
	}

	private static Timing[char[]] mTimings;

	public static void init(char[] output)
	{
		mOutLog = new Print!(char)(Stdout.layout, new Buffer(new FileConduit(output, FileConduit.ReadWriteCreate)));
	}

	debug(TIMINGS) static ~this()
	{
		mOutLog.formatln("Name           | Count        | Total Time         | Average Time");
		mOutLog.formatln("-----------------------------------------------------------------");

		foreach(timing; mTimings.values.sort)
			mOutLog.formatln("{,-14} | {,-12} | {,-18:9f} | {,-18:9f}", timing.name, timing.count, timing.time, timing.time / timing.count);

		mOutLog.flush();
	}

	private char[] mName;

	public this(char[] name)
	{
		mName = name;

		if(!(name in mTimings))
			mTimings[name] = Timing(name);

		mTimer.start();
	}

	~this()
	{
		Interval endTime = mTimer.stop();
		Timing* t = (mName in mTimings);
		t.time += endTime;
		t.count++;
	}
}

static this()
{
	debug(TIMINGS) Profiler.init("timings.txt");
}

struct List(T)
{
	private T[] mData;
	private uint mIndex = 0;

	public void add(T item)
	{
		if(mIndex >= mData.length)
		{
			if(mData.length == 0)
				mData.length = 10;
			else
				mData.length = mData.length * 2;
		}

		mData[mIndex] = item;
		mIndex++;
	}
	
	public T opIndex(uint index)
	{
		return mData[index];
	}
	
	public uint length()
	{
		return mIndex;
	}

	public T[] toArray()
	{
		return mData[0 .. mIndex];
	}
	
	public int opApply(int delegate(ref T) dg)
	{
		int result = 0;

		foreach(ref v; mData[0 .. mIndex])
		{
			result = dg(v);
			
			if(result)
				break;
		}
		
		return result;
	}
	
	public int opApply(int delegate(size_t, ref T) dg)
	{
		int result = 0;

		foreach(i, ref v; mData[0 .. mIndex])
		{
			result = dg(i, v);
			
			if(result)
				break;
		}
		
		return result;
	}
}