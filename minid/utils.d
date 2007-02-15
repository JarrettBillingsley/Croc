module minid.utils;

import format = std.format;
import std.c.string;
import std.conv;
import std.stdarg;
import std.stream;
import utf = std.utf;

// Some type traits stuff.
template isStringType(T)
{
	const bool isStringType = is(T : char[]) || is(T : wchar[]) || is(T : dchar[]);
}

template isCharType(T)
{
	const bool isCharType = is(T == char) || is(T == wchar) || is(T == dchar);
}

template isIntType(T)
{
	const bool isIntType = is(T : int);
}

template isFloatType(T)
{
	const bool isFloatType = is(T == float) || is(T == double) || is(T == real);
}

template isArrayType(T)
{
	const bool isArrayType = is(typeof(T[0])) & is(typeof(T.length));
}

template isPointerType(T)
{
	const bool isPointerType = is(typeof(*T)) & !isArrayType!(T);
}

// Convert any function pointer into a delegate that calls the function when it's called.
RetType delegate(Args) ToDelegate(RetType, Args...)(RetType function(Args) func)
{
	struct S
	{
		RetType function(Args) func;
		
		RetType callMe(Args args)
		{
			return func(args);
		}
	}
	
	S* s = new S;
	s.func = func;
	return &s.callMe;
}

// Don't know why this isn't in phobos.
char[] vformat(TypeInfo[] arguments, va_list argptr)
{
	char[] s;
	
	void putc(dchar c)
	{
		utf.encode(s, c);
	}
	
	format.doFormat(&putc, arguments, argptr);

	return s;
}

// Or this.
int dcmp(dchar[] s1, dchar[] s2)
{
	auto len = s1.length;
	int result;

	if(s2.length < len)
		len = s2.length;

	result = memcmp(s1.ptr, s2.ptr, len);

	if(result == 0)
		result = cast(int)s1.length - cast(int)s2.length;

	return result;
}

// Like std.string.join, but for dchar[]s.
dchar[] djoin(dchar[][] strings, dchar[] separator)
{
	uint length = 0;

	foreach(s; strings)
		length += s.length;

	length += (strings.length - 1) * separator.length;

	dchar[] ret = new dchar[length];
	
	uint numStrings = strings.length;
	uint sepLength = separator.length;

	for(int i = 0, j = 0; i < numStrings; i++)
	{
		ret[j .. j + strings[i].length] = strings[i];
		j += strings[i].length;

		if(j < length)
		{
			ret[j .. j + sepLength] = separator;
			j += sepLength;
		}
	}

	return ret;
}

// Same, but with a single-character separator (optimized a bit).
dchar[] djoin(dchar[][] strings, dchar separator)
{
	uint length = 0;

	foreach(s; strings)
		length += s.length;

	length += strings.length - 1;

	dchar[] ret = new dchar[length];
	
	uint numStrings = strings.length;

	for(int i = 0, j = 0; i < numStrings; i++)
	{
		ret[j .. j + strings[i].length] = strings[i];
		j += strings[i].length;

		if(j < length)
		{
			ret[j] = separator;
			j++;
		}
	}

	return ret;
}

// For joining lists of strings which aren't kept in dchar[][]s.
dchar[] djoin(dchar[] delegate(uint) dg, dchar[] separator)
{
	dchar[] ret = dg(0);
	uint i = 1;

	for(dchar[] string = dg(i++); string !is null; string = dg(i++))
		ret ~= separator ~ string;

	return ret;
}

// Parse a based integer out of a dchar[].
int toInt(dchar[] s, int base)
{
	assert(base >= 2 && base <= 36, "toInt - invalid base");

	static char[] transTable =
	[
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 0, 0, 0, 0, 0, 0,
		0, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72,
		73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 0, 0, 0, 0, 0,
		0, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72,
		73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	];

    int length = s.length;

	if(!length)
		throw new ConvError(utf.toUTF8(s));

	int sign = 0;
	int v = 0;

	char maxDigit = '0' + base - 1;

	for(int i = 0; i < length; i++)
	{
		char c = transTable[s[i]];

		if(c >= '0' && c <= maxDigit)
		{
			uint v1 = v;
			v = v * base + (c - '0');

			if(cast(uint)v < v1)
				throw new ConvOverflowError(utf.toUTF8(s));
		}
		else if(c == '-' && i == 0)
		{
			sign = -1;

			if(length == 1)
				throw new ConvError(utf.toUTF8(s));
		}
		else if(c == '+' && i == 0)
		{
			if(length == 1)
				throw new ConvError(utf.toUTF8(s));
		}
		else
			throw new ConvError(utf.toUTF8(s));
	}

	if(sign == -1)
	{
		if(cast(uint)v > 0x80000000)
			throw new ConvOverflowError(utf.toUTF8(s));

		v = -v;
	}
	else
	{
		if(cast(uint)v > 0x7FFFFFFF)
			throw new ConvOverflowError(utf.toUTF8(s));
	}

	return v;
}

// Make a FOURCC code out of a four-character string.  This is I guess for little-endian platforms..
template FOURCC(char[] name)
{
	static assert(name.length == 4, "FOURCC's parameter must be 4 characters");
	const uint FOURCC = (cast(uint)name[3] << 24) | (cast(uint)name[2] << 16) | (cast(uint)name[1] << 8) | cast(uint)name[0];
}

// Make a version with the major number in the upper 16 bits and the minor in the lower 16 bits.
template MakeVersion(uint major, uint minor)
{
	const uint MakeVersion = (major << 16) | minor;
}

// The current version of MiniD.  (this is kind of buried here)
const uint MiniDVersion = MakeVersion!(0, 1);

// See if T is a type that can't be automatically serialized.
template isInvalidSerializeType(T)
{
	const bool isInvalidSerializeType = isPointerType!(T) | is(T == function) | is(T == delegate) |
		is(T == interface) | is(T == union) | (is(typeof(T.keys)) & is(typeof(T.values)));
}

// Write out a value to a stream.  This will automatically write out nested arrays and entire structures.
// Pointers, functions, delegates, interfaces, unions, and AAs can't be serialized.
// Beware serializing structs, though, as there is no way for this to detect if there are anonymous unions, and if
// you do serialize something with anonymous unions, you'll probably end up with a bad file.
// If you serialize structs, you can optionally define a "void serialize(Stream)" member function which will
// be called instead of the struct being serialized automatically.  Additionally, you can define a
// "static const bool SerializeAsChunk = true" in your struct, and that way arrays of that struct will be written
// out all at once instead of one member at a time.
// If you serialize classes, it will try to call the "void serialize(Stream)" method.
void Serialize(T)(Stream s, T value)
{
	static if(isInvalidSerializeType!(T))
	{
		pragma(msg, "Error: Serialize does not support pointers, functions, delegates, interfaces, unions, or associative arrays.");
		INVALID_TYPE();
	}
	else static if(isArrayType!(T))
	{
		alias typeof(T[0]) ElemType;

		s.write(value.length);

		static if(isInvalidSerializeType!(ElemType))
		{
			pragma(msg, "Error: Serialize does not support pointers, functions, delegates, interfaces, unions, or associative arrays.");
			INVALID_TYPE();
		}
		else static if(isArrayType!(ElemType) || is(ElemType == class))
		{
			foreach(v; value)
				Serialize(s, v);
		}
		else static if(is(ElemType == struct))
		{
			static if(is(typeof(ElemType.SerializeAsChunk) == bool))
				s.writeExact(value.ptr, ElemType.sizeof * value.length);
			else
			{
				foreach(v; value)
					Serialize(s, v);
			}
		}
		else
			s.writeExact(value.ptr, ElemType.sizeof * value.length);
	}
	else static if(is(T == class))
	{
		value.serialize(s);
	}
	else static if(is(T == struct))
	{
		static if(is(typeof(T.serialize)))
			value.serialize(s);
		else
		{
			foreach(member; value.tupleof)
				Serialize(s, member);
		}
	}
	else
	{
		s.writeExact(&value, T.sizeof);
	}
}

// The opposite of Serialize().  The same rules apply here for structs and classes as with Serialize().
void Deserialize(T)(Stream s, out T dest)
{
	static if(isInvalidSerializeType!(T))
	{
		pragma(msg, "Error: Deerialize does not support pointers, functions, delegates, interfaces, unions, or associative arrays.");
		INVALID_TYPE();
	}
	else static if(isArrayType!(T))
	{
		alias typeof(T[0]) ElemType;

		size_t len;
		s.read(len);
		dest.length = len;

		static if(isInvalidSerializeType!(ElemType))
		{
			pragma(msg, "Error: Serialize does not support pointers, functions, delegates, interfaces, unions, or associative arrays.");
			INVALID_TYPE();
		}
		else static if(isArrayType!(ElemType) || is(ElemType == class))
		{
			foreach(inout v; dest)
				Deserialize(s, v);
		}
		else static if(is(ElemType == struct))
		{
			static if(is(typeof(ElemType.SerializeAsChunk) == bool))
				s.readExact(dest.ptr, ElemType.sizeof * dest.length);
			else
			{
				foreach(inout v; dest)
					Deserialize(s, v);
			}
		}
		else
			s.readExact(dest.ptr, ElemType.sizeof * dest.length);
	}
	else static if(is(T == class))
	{
		dest = T.deserialize(s);
	}
	else static if(is(T == struct))
	{
		static if(is(typeof(T.deserialize)))
			dest = T.deserialize(s);
		else
		{
			foreach(member; dest.tupleof)
				Deserialize(s, member);
		}
	}
	else
	{
		s.readExact(&dest, T.sizeof);
	}
}