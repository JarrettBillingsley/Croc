/******************************************************************************
This module contains scary template stuff to make it possible to wrap D functions,
classes, and structs and expose them as functions and types in MiniD.

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
******************************************************************************/

module minid.bind;

import tango.core.Traits;
import tango.core.Tuple;
import Utf = tango.text.convert.Utf;

import minid.ex;
import minid.interpreter;
import minid.types;
import minid.utils : isCharType, NameOfFunc, realType, isStringType, isIntType,
					isFloatType, isArrayType, isAAType, isExpressionTuple,
					QSort;

public void WrapModule(char[] name, Members...)(MDThread* t)
{
	pushGlobal(t, "modules");
	field(t, -1, "customLoaders");

	newFunction(t, function uword(MDThread* t, uword numParams)
	{
		commonNamespace!(name, true, Members)(t);
		return 0;
	}, name);

	fielda(t, -2, name);
	pop(t, 2);
}

public void WrapGlobals(Members...)(MDThread* t)
{
	commonNamespace!("", true, Members)(t);
}

private void commonNamespace(char[] name, bool isModule, Members...)(MDThread* t)
{
	static if(!isModule)
		newNamespace(t, name);

	foreach(i, member; Members)
	{
		static if(is(typeof(member.isFunc)))
			newFunction(t, &member.WrappedFunc, member.Name);
		else static if(is(typeof(member.isNamespace)))
			commonNamespace!(member.Name, false, member.Values)(t);
		else static if(is(typeof(member.isValue)))
			superPush(t, member.Value);
		else static if(is(typeof(member.isClass)))
			member.init!(name)(t);
		else static if(isModule)
			static assert(false, "Invalid member type '" ~ member.stringof ~ "' in wrapped module '" ~ name ~ "'");
		else
			static assert(false, "Invalid member type '" ~ member.stringof ~ "' in wrapped namespace '" ~ name ~ "'");

		static if(isModule)
			newGlobal(t, member.Name);
		else
			fielda(t, -2, member.Name);
	}
}

/**
This wraps a function, and is meant to be used as a parameter to WrapModule.
*/
public struct WrapFunc(alias func)
{
	const bool isFunc = true;
	const char[] Name = NameOfFunc!(func);
	mixin WrappedFunc!(func, Name, typeof(&func), false);
}

/// ditto
public template WrapFunc(alias func, funcType)
{
	const bool isFunc = true;
	const char[] Name = NameOfFunc!(func);
	mixin WrappedFunc!(func, Name, funcType, true);
}

/// ditto
public struct WrapFunc(alias func, char[] name)
{
	const bool isFunc = true;
	const char[] Name = name;
	mixin WrappedFunc!(func, Name, typeof(&func), false);
}

/// ditto
public struct WrapFunc(alias func, char[] name, funcType)
{
	const bool isFunc = true;
	const char[] Name = name;
	mixin WrappedFunc!(func, Name, funcType, true);
}

public struct WrapNamespace(char[] name, members...)
{
	const bool isNamespace = true;
	const char[] Name = name;
	alias members Values;
}

public struct WrapValue(char[] name, value...)
{
	static assert(Value.length == 1 && isExpressionTuple!(Value), "WrapValue - must have exactly one expression");
	const bool isValue = true;
	const char[] Name = name;
	alias value Value;
}

public struct WrapType(Type, char[] name = NameOfType!(Type), Members...)
{
	// Why did I restrict this, again?
// 	static assert(!is(Type == Object), "Wrapping Object is not allowed");

	static assert(is(Type == class) || is(Type == struct), "Cannot wrap type " ~ Type.stringof);

	const bool isClass = true;
	const char[] Name = name;
	const char[] typeName = NameOfType!(Type);
	alias GetCtors!(Members) Ctors;
	static assert(Ctors.length <= 1, "Cannot have more than one WrapCtors instance in wrapped type parameters for type " ~ typeName);

	static if(Ctors.length == 1)
	{
		// alias Ctors[0].Types blah; doesn't parse right
		alias Ctors[0] DUMMY;
		alias DUMMY.Types CleanCtors;
	}
	else
		alias Tuple!() CleanCtors;

	public static word init(char[] moduleName)(MDThread* t)
	{
		getWrappedClass(t, typeid(Type));

		if(!isNull(t, -1))
			throwException(t, "Native type " ~ typeName ~ " cannot be wrapped more than once");

		pop(t);

		static if(is(Type == class))
		{
			alias BaseTypeTupleOf!(Type)[0] BaseClass;

			static if(!is(BaseClass == Object))
				auto base = getWrappedClass(t, typeid(BaseClass));
			else
				auto base = pushNull(t);

			pushClassObj!(Type, moduleName, name)(t, base);
		}
		else
			pushStructObj!(Type, moduleName, name)(t);

		const TypeName = moduleName ~ "." ~ name;

		foreach(i, member; Members)
		{
			static if(is(typeof(member.isMethod)))
			{
				auto f = &WrappedMethod!(member.Func, member.FuncType, Type, TypeName, member.explicitType);
				newFunction(t, f, name ~ "." ~ member.Name);
				fielda(t, -2, member.Name);
			}
			else static if(is(typeof(member.isProperty)))
			{
				auto f = &WrappedProperty!(member.Func, member.Name, member.FuncType, Type, TypeName);
				newFunction(t, f, name ~ "." ~ member.Name);
				fielda(t, -2, member.Name);
			}
			else static if(is(typeof(member.isCtors)))
			{
				// ignore
			}
			else
				static assert(false, "Invalid member type '" ~ typeof(member).stringof ~ "' in wrapped type '" ~ typeName ~ "'");
		}

		newFunction(t, &constructor!(TypeName), name ~ ".constructor");
		fielda(t, -2, "constructor");
		
		newFunction(t, &allocator, name ~ ".allocator");
		setAllocator(t, -2);

		setWrappedClass(t, typeid(Type));
		return stackSize(t) - 1;
	}

	private static uword allocator(MDThread* t, uword numParams)
	{
		newInstance(t, 0, 1);

		dup(t);
		pushNull(t);
		rotateAll(t, 3);
		methodCall(t, 2, "constructor", 0);
		return 1;
	}

	static if(CleanCtors.length == 0)
	{
		static if(is(Type == class))
			static assert(is(typeof(new Type())), "Cannot call default constructor for class " ~ typeName ~ "; please wrap a constructor explicitly");
		else
			static assert(is(typeof(Type())), "Cannot call default constructor for struct " ~ typeName ~ "; please wrap a constructor explicitly");

		private static uword constructor(char[] FullName)(MDThread* t, uword numParams)
		{
			static if(is(Type == class))
			{
				checkClassSelf!(Type, FullName)(t);
				pushNativeObj(t, new Type());
			}
			else
			{
				checkStructSelf!(Type, FullName)(t);
				pushNativeObj(t, new StructWrapper!(Type)(Type()));
			}

			setExtraVal(t, 0, 0);
			return 0;
		}
	}
	else
	{
		private static uword constructor(char[] FullName)(MDThread* t, uword numParams)
		{
			checkInstParam(t, 0, FullName);

			static if(is(Type == class))
			{
				static if(is(typeof(new Type())))
					const minArgs = 0;
				else
					const minArgs = ParameterTupleOf!(CleanCtors[0]).length;
			}
			else
			{
				static if(is(typeof(Type())))
					const minArgs = 0;
				else
					const minArgs = ParameterTupleOf!(CleanCtors[0]).length;
			}

			const maxArgs = ParameterTupleOf!(CleanCtors[$ - 1]).length;

			if(numParams < minArgs)
				throwException(t, "At least " ~ minArgs.stringof ~ " parameter" ~ (minArgs == 1 ? "" : "s") ~ " expected, not {}", numParams);

			if(numParams > maxArgs)
				numParams = maxArgs;

			static if(minArgs == 0)
			{
				if(numParams == 0)
				{
					static if(is(Type == class))
						pushNativeObj(t, new Type());
					else
						pushNativeObj(t, new StructWrapper!(Type)(Type()));

					setExtraVal(t, 0, 0);
					return 0;
				}
			}

			static if(is(Type == class))
				const Switch = CtorCases!(CleanCtors);
			else
				const Switch = StructCtorCases!(CleanCtors);

			mixin(Switch);

			auto buf = StrBuffer(t);

			buf.addChar('(');

			if(numParams > 0)
			{
				pushTypeString(t, 1);
				buf.addTop();

				for(uword i = 2; i <= numParams; i++)
				{
					buf.addString(", ");
					pushTypeString(t, i);
					buf.addTop();
				}
			}

			buf.addChar(')');
			buf.finish();
			throwException(t, "Parameter list {} passed to constructor does not match any wrapped constructors", getString(t, -1));
		}
	}
}

public struct WrapCtors(T...)
{
	static assert(T.length > 0, "WrapCtors must be instantiated with at least one type");
	const bool isCtors = true;
	alias Unique!(QSort!(SortByNumParams, T)) Types;
}

public struct WrapMethod(alias func)
{
	const bool isMethod = true;
	const char[] Name = NameOfFunc!(func);
	const bool explicitType = false;
	alias func Func;
	alias typeof(&func) FuncType;
}

public struct WrapMethod(alias func, char[] name)
{
	const bool isMethod = true;
	const char[] Name = name;
	const bool explicitType = false;
	alias func Func;
	alias typeof(&func) FuncType;
}

public struct WrapMethod(alias func, funcType)
{
	const bool isMethod = true;
	const char[] Name = NameOfFunc!(func);
	const bool explicitType = true;
	alias func Func;
	alias funcType FuncType;
}

public struct WrapMethod(alias func, char[] name, funcType)
{
	const bool isMethod = true;
	const char[] Name = name;
	const bool explicitType = true;
	alias func Func;
	alias funcType FuncType;
}

word getWrappedClass(MDThread* t, TypeInfo ti)
{
	pushWrappedClasses(t);
	pushNativeObj(t, ti);

	if(!opin(t, -1, -2))
	{
		pop(t, 2);
		return pushNull(t);
	}

	idx(t, -2);
	insertAndPop(t, -2);
	return stackSize(t) - 1;
}

void setWrappedClass(MDThread* t, TypeInfo ti)
{
	pushWrappedClasses(t);
	pushNativeObj(t, ti);
	dup(t, -3);
	idxa(t, -3);
	pop(t);
}

word pushWrappedClasses(MDThread* t)
{
	auto reg = getRegistry(t);
	pushString(t, "minid.bind.WrappedClasses");

	if(!opin(t, -1, -2))
	{
		newTable(t);
		swap(t);
		dup(t, -2);
		fielda(t, reg);
	}
	else
		field(t, reg);

	insertAndPop(t, -2);
	return stackSize(t) - 1;
}

word pushClassObj(Type, char[] ModName, char[] ClassName)(MDThread* t, word base)
{
	const FullName = ModName ~ "." ~ ClassName;

	auto ret = newClass(t, base, ClassName);
	return ret;
}

word pushStructObj(Type, char[] ModName, char[] StructName)(MDThread* t)
{
	const FullName = ModName ~ "." ~ StructName;

	static uword getField(MDThread* t, uword numParams)
	{
		auto self = checkStructSelf!(Type, FullName)(t);
		auto fieldName = checkStringParam(t, 1);

		const Switch = GetStructField!(Type);
		mixin(Switch);

		return 1;
	}

	static uword setField(MDThread* t, uword numParams)
	{
		auto self = checkStructSelf!(Type, FullName)(t);
		auto fieldName = checkStringParam(t, 1);

		const Switch = SetStructField!(Type);
		mixin(Switch);

		return 0;
	}

	auto ret = newClass(t, StructName);
		newFunction(t, &getField, StructName ~ ".opField");       fielda(t, ret, "opField");
		newFunction(t, &setField, StructName ~ ".opFieldAssign"); fielda(t, ret, "opFieldAssign");
	return ret;
}

private class StructWrapper(T)
{
	T inst;

	this(T t)
	{
		inst = t;
	}
}

static Type* checkStructSelf(Type, char[] FullName)(MDThread* t)
{
	checkInstParam(t, 0, FullName);
	getExtraVal(t, 0, 0);
	auto ret = &(cast(StructWrapper!(Type))cast(void*)getNativeObj(t, -1)).inst;
	pop(t);
	return ret;
}

static Type checkClassSelf(Type, char[] FullName)(MDThread* t)
{
	checkInstParam(t, 0, FullName);
	getExtraVal(t, 0, 0);
	auto ret = cast(Type)cast(void*)getNativeObj(t, -1);
	pop(t);
	return ret;
}

private template WrappedFunc(alias func, char[] name, funcType, bool explicitType)
{
	static uword WrappedFunc(MDThread* t, uword numParams)
	{
		static if(explicitType)
			const minArgs = NumParams!(funcType);
		else
			const minArgs = MinArgs!(func);

		const maxArgs = NumParams!(funcType);

		if(numParams < minArgs)
			throwException(t, "At least" ~ minArgs.stringof ~ " parameter" ~ (minArgs == 1 ? "" : "s") ~ " expected, not {}", numParams);

		if(numParams > maxArgs)
			numParams = maxArgs;

		static if(NumParams!(funcType) == 0)
		{
			static if(is(ReturnTypeOf!(funcType) == void))
			{
				safeCode(t, func());
				return 0;
			}
			else
			{
				superPush(t, safeCode(t, func()));
				return 1;
			}
		}
		else
		{
			ParameterTupleOf!(funcType) args;

			static if(minArgs == 0)
			{
				if(numParams == 0)
				{
					static if(is(ReturnTypeOf!(funcType) == void))
					{
						safeCode(t, func());
						return 0;
					}
					else
					{
						superPush(t, safeCode(t, func()));
						return 1;
					}
				}
			}

			foreach(i, arg; args)
			{
				const argNum = i + 1;

				if(i < numParams)
					getParameter(t, argNum, args[i]);

				static if(argNum >= minArgs && argNum <= maxArgs)
				{
					if(argNum == numParams)
					{
						static if(is(ReturnTypeOf!(funcType) == void))
						{
							safeCode(t, safeCode(t, func(args[0 .. argNum])));
							return 0;
						}
						else
						{
							superPush(t, safeCode(t, func(args[0 .. argNum])));
							return 1;
						}
					}
				}
			}

			assert(false, "WrappedFunc (" ~ name ~ ") should never ever get here.");
		}
	}
}

private uword WrappedMethod(alias func, funcType, Type, char[] FullName, bool explicitType)(MDThread* t, uword numParams)
{
	const char[] name = NameOfFunc!(func);
	
	static if(explicitType)
		const minArgs = NumParams!(funcType);
	else
		const minArgs = MinArgs!(func);

	const maxArgs = NumParams!(funcType);

	if(numParams < minArgs)
		throwException(t, "At least " ~ minArgs.stringof ~ " parameter" ~ (minArgs == 1 ? "" : "s") ~ " expected, not {}", numParams);

	if(numParams > maxArgs)
		numParams = maxArgs;

	static if(is(Type == class))
		auto self = checkClassSelf!(Type, FullName)(t);
	else
		auto self = checkStructSelf!(Type, FullName)(t);

	assert(self !is null, "Invalid 'this' parameter passed to method " ~ Type.stringof ~ "." ~ name);

	static if(NumParams!(funcType) == 0)
	{
		static if(is(ReturnTypeOf!(funcType) == void))
		{
			mixin("safeCode(t, self." ~ name ~ "());");
			return 0;
		}
		else
		{
			mixin("superPush(t, safeCode(t, self." ~ name ~ "()));");
			return 1;
		}
	}
	else
	{
		ParameterTupleOf!(funcType) args;

		static if(minArgs == 0)
		{
			if(numParams == 0)
			{
				static if(is(ReturnTypeOf!(funcType) == void))
				{
					mixin("safeCode(t, self." ~  name ~ "());");
					return 0;
				}
				else
				{
					mixin("superPush(t, safeCode(t, self." ~ name ~ "()));");
					return 1;
				}
			}
		}

		foreach(i, arg; args)
		{
			const argNum = i + 1;

			if(i < numParams)
				getParameter(t, argNum, args[i]);

			static if(argNum >= minArgs && argNum <= maxArgs)
			{
				if(argNum == numParams)
				{
					static if(is(ReturnTypeOf!(funcType) == void))
					{
						mixin("safeCode(t, self." ~ name ~ "(args[0 .. argNum]));");
						return 0;
					}
					else
					{
						mixin("superPush(t, safeCode(t, self." ~ name ~ "(args[0 .. argNum])));");
						return 1;
					}
				}
			}
		}
	}

	assert(false, "WrappedMethod (" ~ name ~ ") should never ever get here.");
}

private void getParameter(T)(MDThread* t, word index, ref T ret)
{
	ret = to!(T)(t, index);
}

private word superPush(Type)(MDThread* t, Type val)
{
	alias realType!(Type) T;

	static if(is(T == bool))
		return pushBool(t, cast(T)val);
	else static if(isIntType!(T))
		return pushInt(t, cast(T)val);
	else static if(isFloatType!(T))
		return pushFloat(t, cast(T)val);
	else static if(isCharType!(T))
		return pushChar(t, cast(T)val);
	else static if(isStringType!(T))
	{
		static if(is(T == char[]))
			return pushString(t, cast(T)val);
		else
			return pushString(t, Utf.toString(cast(T)val));
	}
	else static if(isAAType!(T))
	{
		auto ret = newTable(t, val.length);

		foreach(k, v; val)
		{
			superPush(t, k);
			superPush(t, v);
			idxa(t, ret);
		}

		return ret;
	}
	else static if(isArrayType!(T))
	{
		auto ret = newArray(t, val.length);

		foreach(i, v; val)
		{
			superPush(t, v);
			idxai(t, ret, i);
		}

		return ret;
	}
	else static if(is(T : Object))
	{
		getWrappedClass(t, typeid(T));

		if(isNull(t, -1))
			throwException(t, "Cannot convert class {} to a MiniD value; class type has not been wrapped", typeid(T));

		newInstance(t, -1, 1);
		insertAndPop(t, -2);
		pushNativeObj(t, val);
		setExtraVal(t, -2, 0);
		return stackSize(t) - 1;
	}
	else static if(is(T == struct))
	{
		getWrappedClass(t, typeid(T));

		if(isNull(t, -1))
			throwException(t, "Cannot convert struct {} to a MiniD value; struct type has not been wrapped", typeid(T));

		newInstance(t, -1, 1);
		insertAndPop(t, -2);
		pushNativeObj(t, new StructWrapper!(Type)(val));
		setExtraVal(t, -2, 0);
		return stackSize(t) - 1;
	}
	else static if(is(T == MDThread*))
		return pushThread(t, cast(T)val);
	else
	{
		// I do this because static assert won't show the template instantiation "call stack."
		pragma(msg, "superPush - Invalid argument type '" ~ T.stringof ~ "'");
		ARGUMENT_ERROR(T);
	}
}

private Type to(Type)(MDThread* t, word idx)
{
	alias realType!(Type) T;

	static if(!isStringType!(T) && isArrayType!(T))
	{
		alias typeof(T[0]) ElemType;

		if(!isArray(t, idx))
		{
			pushTypeString(t, idx);
			throwException(t, "to - Cannot convert MiniD type '{}' to D type '" ~ Type.stringof ~ "'", getString(t, -1));
		}

		auto data = getArray(t, idx).slice;
		auto ret = new T(data.length);

		foreach(i, ref elem; data)
		{
			auto elemIdx = push(t, elem);

			if(!canCastTo!(ElemType)(t, elemIdx))
			{
				pushTypeString(t, idx);
				pushTypeString(t, elemIdx);
				throwException(t, "to - Cannot convert MiniD type '{}' to D type '" ~ Type.stringof ~ "': element {} should be '" ~
					ElemType.stringof ~ "', not '{}'", getString(t, -2), i, getString(t, -1));
			}

			ret[i] = to!(ElemType)(t, elemIdx);
			pop(t);
		}

		return cast(Type)ret;
	}
	else static if(isAAType!(T))
	{
		alias typeof(T.init.keys[0]) KeyType;
		alias typeof(T.init.values[0]) ValueType;

		if(!isTable(t, idx))
		{
			pushTypeString(t, idx);
			throwException(t, "to - Cannot convert MiniD type '{}' to D type '" ~ Type.stringof ~ "'", getString(t, -1));
		}

		T ret;

		foreach(ref key, ref val; getTable(t, idx).data)
		{
			auto keyIdx = push(t, key);

			if(!canCastTo!(KeyType)(t, keyIdx))
			{
				pushTypeString(t, idx);
				pushTypeString(t, keyIdx);
				throwException(t, "to - Cannot convert MiniD type '{}' to D type '" ~ Type.stringof ~ "': key should be '" ~
					ElemType.stringof ~ "', not '{}'", getString(t, -2), getString(t, -1));
			}

			auto valIdx = push(t, val);

			if(!canCastTo!(ValueType)(t, valIdx))
			{
				pushTypeString(t, idx);
				pushTypeString(t, valIdx);
				throwException(t, "to - Cannot convert MiniD type '{}' to D type '" ~ Type.stringof ~ "': value should be '" ~
					ElemType.stringof ~ "', not '{}'", getString(t, -2), getString(t, -1));
			}

			ret[to!(KeyType)(t, keyIdx)] = to!(ValueType)(t, valIdx);
			pop(t, 2);
		}

		return cast(Type)ret;
	}
	else static if(is(T : Object))
	{
		if(isNull(t, idx))
			return null;

		getWrappedClass(t, typeid(T));

		if(!as(t, idx, -1))
			paramTypeError(t, idx, "instance of " ~ Type.stringof);

		pop(t);

		getExtraVal(t, idx, 0);
		auto ret = cast(Type)cast(void*)getNativeObj(t, -1);
		pop(t);
		
		return ret;
	}
	else static if(is(T == struct))
	{
		getWrappedClass(t, typeid(T));
		// the wrapped class will always be non-null, since the struct got on the stack in the first place..

		if(!as(t, idx, -1))
			paramTypeError(t, idx, "instance of " ~ Type.stringof);

		pop(t);

		getExtraVal(t, idx, 0);
		auto ret = cast(Type)(cast(StructWrapper!(T))getNativeObj(t, -1)).inst;
		pop(t);

		return ret;
	}
	else
	{
		if(!canCastTo!(T)(t, idx))
		{
			pushTypeString(t, idx);
			throwException(t, "to - Cannot convert MiniD type '{}' to D type '" ~ Type.stringof ~ "'", getString(t, -1));
		}

		static if(is(T == bool))
		{
			return cast(Type)getBool(t, idx);
		}
		else static if(isIntType!(T))
		{
			return cast(Type)getInt(t, idx);
		}
		else static if(isFloatType!(T))
		{
			if(isInt(t, idx))
				return cast(Type)getInt(t, idx);
			else if(isFloat(t, idx))
				return cast(Type)getFloat(t, idx);
			else
				assert(false, "to!(" ~ T.stringof ~ ")");
		}
		else static if(isCharType!(T))
		{
			return cast(Type)getChar(t, idx);
		}
		else static if(isStringType!(T))
		{
			static if(is(T == char[]))
				return cast(Type)getString(t, idx).dup;
			else static if(is(T == wchar[]))
				return cast(Type)Utf.toString16(getString(t, idx));
			else
				return cast(Type)Utf.toString32(getString(t, idx));
		}
		else
		{
			// I do this because static assert won't show the template instantiation "call stack."
			pragma(msg, "to - Invalid argument type '" ~ Type.stringof ~ "'");
			ARGUMENT_ERROR(Type);
		}
	}
}

public bool canCastTo(Type)(MDThread* t, word idx)
{
	alias realType!(Type) T;

	static if(is(T == bool))
	{
		return isBool(t, idx);
	}
	else static if(isIntType!(T))
	{
		return isInt(t, idx);
	}
	else static if(isFloatType!(T))
	{
		return isNum(t, idx);
	}
	else static if(isCharType!(T))
	{
		return isChar(t, idx);
	}
	else static if(isStringType!(T) || is(T : MDString))
	{
		return isString(t, idx);
	}
	else static if(isAAType!(T))
	{
		if(!isTable(t, idx))
			return false;

		alias typeof(T.init.keys[0]) KeyType;
		alias typeof(T.init.values[0]) ValueType;

		foreach(ref k, ref v; mTable)
		{
			auto keyIdx = push(t, k);

			if(!canCastTo!(KeyType)(t, keyIdx))
			{
				pop(t);
				return false;
			}

			auto valIdx = push(t, v);

			if(!canCastTo!(ValueType)(t, valIdx))
			{
				pop(t, 2);
				return false;
			}

			pop(t, 2);
		}

		return true;
	}
	else static if(isArrayType!(T))
	{
		if(!isArray(t, idx))
			return false;

		alias typeof(T[0]) ElemType;

		foreach(ref v; mArray)
		{
			auto valIdx = push(t, v);

			if(!canCastTo!(ElemType)(t, valIdx))
			{
				pop(t);
				return false;
			}

			pop(t);
		}

		return true;
	}
	else static if(is(T : Object))
	{
		if(isNull(t, idx))
			return true;

		getWrappedClass(t, typeid(T));
		auto ret = as(t, idx, -1);
		pop(t);
		return ret;
	}
	else static if(is(T == struct))
	{
		getWrappedClass(t, typeid(T));
		auto ret = as(t, idx, -1);
		pop(t);
		return ret;
	}
	else
		return false;
}

/**
Given an alias to a function, this metafunction will give the minimum legal number of arguments it can be called with.
Even works for aliases to class methods.
*/
public template MinArgs(alias func)
{
	const uint MinArgs = MinArgsImpl!(func, 0, InitsOf!(ParameterTupleOf!(typeof(&func))));
}

public template MinArgsImpl(alias func, int index, Args...)
{
	static if(index >= Args.length)
		const uint MinArgsImpl = Args.length;
	else static if(is(typeof(func(Args[0 .. index]))))
		const uint MinArgsImpl = index;
	else
		const uint MinArgsImpl = MinArgsImpl!(func, index + 1, Args);
}

/**
Given a type tuple, this metafunction will give an expression tuple of all the .init values for each type.
*/
public template InitsOf(T...)
{
	static if(T.length == 0)
		alias Tuple!() InitsOf;
	else static if(is(T[0] == MDValue))
		alias Tuple!(MDValue.nullValue, InitsOf!(T[1 .. $])) InitsOf;
	else
		alias Tuple!(InitOf!(T[0]), InitsOf!(T[1 .. $])) InitsOf;
}

// BUG 2449.
// FUCK YOU DMDFE.  FUCK YOU SO MUCH.
T InitOf_shim(T)()
{
	T t;
	return t;
}

// This template exists for the sole reason that T.init doesn't work for structs inside templates due
// to a forward declaration error.
// Fucking DMDFE.
private template InitOf(T)
{
	static if(!is(typeof(Tuple!(T.init))))
		alias Tuple!(InitOf_shim!(T)()) InitOf;
	else
		alias Tuple!(T.init) InitOf;
}

private template NameOfType(T)
{
	const char[] NameOfType = T.stringof;
}

private class Fribble {}
private struct Frobble {}

static assert(NameOfType!(Fribble) == "Fribble", "NameOfType doesn't work for classes (got " ~ NameOfType!(Fribble) ~ ")");
static assert(NameOfType!(Frobble) == "Frobble", "NameOfType doesn't work for structs (got " ~ NameOfType!(Frobble) ~ ")");

private template CtorCases(Ctors...)
{
	const CtorCases = "switch(numParams) { default: throwException(t, \"Invalid number of parameters ({})\", numParams);\n"
		~ CtorCasesImpl!(-1, 0, Ctors) ~ "\nbreak; }";
}

private template CtorCasesImpl(int num, int idx, Ctors...)
{
	static if(Ctors.length == 0)
		const CtorCasesImpl = "";
	else static if(NumParams!(Ctors[0]) != num)
		const CtorCasesImpl = "break;\ncase " ~ NumParams!(Ctors[0]).stringof ~ ":\n" ~ CtorCasesImpl!(NumParams!(Ctors[0]), idx, Ctors);
	else
	{
		const CtorCasesImpl = "if(TypesMatch!(ParameterTupleOf!(CleanCtors[" ~ idx.stringof ~ "]))(t))
{
	ParameterTupleOf!(CleanCtors[" ~ idx.stringof ~ "]) params;

	foreach(i, arg; params)
		getParameter(t, i + 1, params[i]);

	pushNativeObj(t, new Type(params));
	setExtraVal(t, 0, 0);
	return 0;
}\n\n" ~ CtorCasesImpl!(num, idx + 1, Ctors[1 .. $]);
	}
}

private template StructCtorCases(Ctors...)
{
	const StructCtorCases = "switch(numParams) { default: throwException(t, \"Invalid number of parameters ({})\", numParams);\n"
		~ StructCtorCasesImpl!(-1, 0, Ctors) ~ "\nbreak; }";
}

private template StructCtorCasesImpl(int num, int idx, Ctors...)
{
	static if(Ctors.length == 0)
		const StructCtorCasesImpl = "";
	else static if(NumParams!(Ctors[0]) != num)
		const StructCtorCasesImpl = "break;\ncase " ~ NumParams!(Ctors[0]).stringof ~ ":\n" ~ StructCtorCasesImpl!(NumParams!(Ctors[0]), idx, Ctors);
	else
	{
		const StructCtorCasesImpl = "if(TypesMatch!(ParameterTupleOf!(CleanCtors[" ~ idx.stringof ~ "]))(t))
{
	ParameterTupleOf!(CleanCtors[" ~ idx.stringof ~ "]) params;

	foreach(i, arg; params)
		getParameter(t, i + 1, params[i]);

	pushNativeObj(t, new StructWrapper!(Type)(Type(params)));
	setExtraVal(t, 0, 0);
	//self.updateFields();
	return 0;
}\n\n" ~ StructCtorCasesImpl!(num, idx + 1, Ctors[1 .. $]);
	}
}

private template NumParams(T)
{
	const NumParams = ParameterTupleOf!(T).length;
}

private template SortByNumParams(T1, T2)
{
	const SortByNumParams = cast(int)ParameterTupleOf!(T1).length - cast(int)ParameterTupleOf!(T2).length;
}

private template GetCtors(T...)
{
	static if(T.length == 0)
		alias Tuple!() GetCtors;
	else static if(is(typeof(T[0].isCtors)))
		alias Tuple!(T[0], GetCtors!(T[1 .. $])) GetCtors;
	else
		alias GetCtors!(T[1 .. $]) GetCtors;
}

private template GetStructField(T)
{
	const GetStructField =
	"switch(fieldName)"
	"{"
		"default:"
			"throwException(t, \"Attempting to access nonexistent field '{}' from type " ~ T.stringof ~ "\", fieldName);\n"
		~ GetStructFieldImpl!(T, FieldNames!(T)) ~
	"}";
}

private template GetStructFieldImpl(T, Fields...)
{
	static if(Fields.length == 0)
		const GetStructFieldImpl = "";
	else
	{
		const GetStructFieldImpl =
		"case \"" ~ Fields[0] ~ "\": static if(!is(typeof(self. " ~ Fields[0] ~ "))) throwException(t, \"Attempting to access private field '" ~ Fields[0] ~ "'\"); else "
			"superPush(t, self." ~ Fields[0] ~ "); break;\n"
		~ GetStructFieldImpl!(T, Fields[1 .. $]);
	}
}

private template SetStructField(T)
{
	const SetStructField =
	"switch(fieldName)"
	"{"
		"default:"
			"throwException(t, \"Attempting to access nonexistent field '{}' from type " ~ T.stringof ~ "\", fieldName);\n"
		~ SetStructFieldImpl!(FieldNames!(T)) ~
	"}";
}

private template SetStructFieldImpl(Fields...)
{
	static if(Fields.length == 0)
		const SetStructFieldImpl = "";
	else
	{
		const SetStructFieldImpl =
		"case \"" ~ Fields[0] ~ "\": static if(!is(typeof(self. " ~ Fields[0] ~ "))) throwException(t, \"Attempting to access private field '" ~ Fields[0] ~ "'\"); else "
			"getParameter(t, 2, self." ~ Fields[0] ~ "); break;\n"
		~ SetStructFieldImpl!(Fields[1 .. $]);
	}
}

private bool TypesMatch(T...)(MDThread* t)
{
	foreach(i, type; T)
	{
		if(!canCastTo!(type)(t, i + 1))
			return false;
		else
		{
			static if(isFloatType!(type))
			{
				if(isInt(t, i + 1))
					return false;
			}
		}
	}

	return true;
}

public template FieldNames(S, int idx = 0)
{
	static if(idx >= S.tupleof.length)
		alias Tuple!() FieldNames;
	else
		alias Tuple!(GetLastName!(S.tupleof[idx].stringof), FieldNames!(S, idx + 1)) FieldNames;
}

private template GetLastName(char[] fullName, int idx = fullName.length - 1)
{
	static if(idx < 0)
		const char[] GetLastName = fullName;
	else static if(fullName[idx] == '.')
		const char[] GetLastName = fullName[idx + 1 .. $];
	else
		const char[] GetLastName = GetLastName!(fullName, idx - 1);
}

/+
/**
Used to wrap a module that is exposed to MiniD.  A module can contain any number of functions, classes, structs,
and other values.  They are added to the module using this struct's methods.

Examples:
-----
WrapModule("foo.bar", myContext) // name it foo.bar, load it into myContext
	.func!(funcOne)() // wrap native function funcOne; the empty parens here are necessary
	.func!(funcTwo)()
	.custom("x", 6)() // set member "x" to the value 6.  This can be any convertible type.
	.type(WrapClass!(MyClass) // wrap the native class MyClass.
		.method!(MyClass.method)() // A method.  Again, the empty parens are necessary.
		.property!(MyClass.property)()); // a property
-----
*/
struct WrapModule
{
	struct Loader
	{
		private MDNamespace namespace;

		private int loader(MDState s, uint numParams)
		{
			MDNamespace ns = s.getParam!(MDNamespace)(1);

			foreach(k, v; namespace)
			{
				if(v.isFunction())
					v.as!(MDClosure).environment = ns;

				ns[k] = v;
			}

			return 0;
		}
	}

	private Loader* loader;

	/**
	Creates an instance of this struct so you can start wrapping a module.

	Params:
		name = The name of the module to expose to MiniD.  This can be a multi-part name, with dots (like "foo.bar").
		context = The MiniD context to load this module into.

	Returns:
		An instance of this struct ready to have members added.
	*/
	public static typeof(*this) opCall(char[] name, MDContext context)
	{
		typeof(*this) ret;

		ret.loader = new Loader;
		ret.loader.namespace = new MDNamespace();

		dchar[] name32 = utf.toString32(name);

		context.setModuleLoader(name32, new MDClosure(context.globals.ns, &ret.loader.loader, "module " ~ name32));

		return ret;
	}

	/**
	Wrap a function and insert it into this module's namespace.  This must be a non-member D function.

	Params:
		f = An alias to the function you want to wrap.
		name = The name to call it in MiniD.  Defaults to the D function name.
		funcType = The type of the function to wrap.  This defaults to typeof(f), but you'll need to specify this
			explicitly if you're wrapping an overloaded function, in order to select the proper overload.

	Returns:
		A chaining reference to this module.
	*/
	public typeof(this) func(alias f, char[] name = NameOfFunc!(f), funcType = typeof(f))()
	{
		const name32 = ToUTF32!(name);
		loader.namespace[name32] = MDValue(new MDClosure(loader.namespace, &WrappedFunc!(f, name, funcType), name32));

		return this;
	}

	/** ditto */
	public typeof(this) func(alias f, funcType)()
	{
		const name = NameOfFunc!(f);
		const name32 = ToUTF32!(name);
		loader.namespace[name32] = MDValue(new MDClosure(loader.namespace, &WrappedFunc!(f, name, funcType), name32));

		return this;
	}

	/**
	Insert an arbitrary key-value pair into the module.  The value can be any convertible type.

	Params:
		name = The name to give this value in the module.
		value = The value to insert.

	Returns:
		A chaining reference to this module.
	*/
	public typeof(this) custom(T)(char[] name, T value)
	{
		loader.namespace[utf.toString32(name)] = MDValue(value);
		return this;
	}

	/**
	Insert a wrapped class or struct type into the module.

	Params:
		value = The wrapped class or struct type to insert.  This should be an instance of the WrapClass struct, and should have
		already had its members added to it.
		name = The name to give this type in the MiniD module.  Defaults to "", which means it will use the D name of the type.

	Returns:
		A chaining reference to this module.
	*/
	public typeof(this) type(T)(T value)
	{
		value.addToNamespace(loader.namespace);
		return this;
	}

	public typeof(this) type(T, U)(U name, T value)
	{
		static if(is(U == dchar[]))
			value.addToNamespace(loader.namespace, name[]);
		else
			value.addToNamespace(loader.namespace, utf.toString32(name[]));

		return this;
	}
}

/**
Used to wrap a class or struct type that is exposed to MiniD.  Since classes and structs are very similar, both can be
wrapped by this one template.  They can have any number of constructors, methods, and properties, and structs will have all their
fields wrapped in opIndex and opIndexAssign metamethods so that they can be accessed from within MiniD.

Params:
	ClassType = The type of the class or struct to wrap.
	Ctors = An optional list of function types which represent the constructors (or in the case of structs, static opCalls) which
		should be wrapped.  If this is left out, it will attempt to wrap the default (no-parameter) constructor.

Bugs:
	As explained in the module header, wrapping structs with private fields fails.  You could try making a wrapper type for it, and
	then wrapping that :X

Examples:
-----
WrapClass!(MyClass, void function(int), void function(int, float)) // class type, followed by ctor types
	.method!(MyClass.methodOne)() // wrap a method
	.property!(MyClass.position)() // wrap a property
.addToNamespace(someNamespace); // register it into a namespace
-----
*/
struct WrapClass(ClassType, Ctors...)
{
	static if(is(ClassType == class))
	{
		const ClassName = ToUTF32!(ClassType.stringof);
		alias WrappedInstance InstanceType;
		alias WrappedClass MDClassType;
	}
	else static if(is(ClassType == struct))
	{
		// DMDFE inserts a spurious space after struct.stringof.
		const ClassName = ToUTF32!(ClassType.stringof[0 .. $ - 1]);
		alias WrappedStruct!(ClassType) InstanceType;
		alias WrappedStructClass!(ClassType) MDClassType;
	}
	else
		static assert(false, "Cannot wrap type " ~ ClassType.stringof);

	alias Unique!(QSort!(SortByNumParams, Ctors)) CleanCtors;

	private MDClassType mClass;

	/**
	Creates an instance of this struct so you can start wrapping your class or struct.

	Returns:
		An instance of this struct.
	*/
	public static typeof(*this) opCall()
	{
		typeof(*this) ret;

		if(typeid(ClassType) in WrappedClasses)
			throw new MDException("Native type " ~ ToUTF8!(ClassName) ~ " cannot be wrapped more than once");

		static if(is(ClassType == class))
		{
			alias BaseTypeTupleOf!(ClassType) Bases;

			static if(!is(Bases[0] == Object))
				ret.mClass = new MDClassType(ClassName, GetWrappedClass(typeid(Bases[0])));
			else
				ret.mClass = new MDClassType(ClassName, null);
		}
		else
		{
			ret.mClass = new MDClassType(ClassName, null);
		}

		WrappedClasses[typeid(ClassType)] = ret.mClass;

		static if(is(ClassType == struct))
		{
			ret.mClass.mMethods["opIndex"d] = MDValue(new MDClosure(ret.mClass.mMethods, &ret.mClass.getField, ClassName ~ ".opIndex"));
			ret.mClass.mMethods["opIndexAssign"d] = MDValue(new MDClosure(ret.mClass.mMethods, &ret.mClass.setField, ClassName ~ ".opIndexAssign"));
		}

		static if(CleanCtors.length == 0)
			ret.mClass.mMethods["constructor"d] = MDValue(new MDClosure(ret.mClass.mMethods, &defaultCtor, ClassName ~ ".constructor"));
		else
			ret.mClass.mMethods["constructor"d] = MDValue(new MDClosure(ret.mClass.mMethods, &constructor, ClassName ~ ".constructor"));

		return ret;
	}

	/**
	Wrap a class or struct method.

	Params:
		func = An alias to the method to wrap.  If your class type is "MyClass" and the method is "foo", use "MyClass.foo" (without the quotes)
			as the parameter.
		name = The name that should be used on the MiniD side to represent the method.  Defaults to the D method name.
		funcType = The type of the method to wrap.  This defaults to typeof(func), but you'll need to specify this
			explicitly if you're wrapping an overloaded method, in order to select the proper overload.

	Returns:
		A chaining reference to this struct.
	*/
	public typeof(this) method(alias func, char[] name = NameOfFunc!(func), funcType = typeof(func))()
	{
		const name32 = ToUTF32!(name);
		mClass.mMethods[name32] = MDValue(new MDClosure(mClass.mMethods, &WrappedMethod!(func, funcType, ClassType), ClassName ~ "." ~ name32));

		return this;
	}

	/// ditto
	public typeof(this) method(alias func, funcType)()
	{
		const name = NameOfFunc!(func);
		const name32 = ToUTF32!(name);
		mClass.mMethods[name32] = MDValue(new MDClosure(mClass.mMethods, &WrappedMethod!(func, funcType, ClassType), ClassName ~ "." ~ name32));

		return this;
	}

	/**
	Wrap a property.  MiniD doesn't have explicit support for properties, but the MiniD standard library follows a certain convention, which is
	compatible with the D property convention.  In MiniD, a property is represented as a function which sets the value when called with one
	parameter, and which gets the value when called with none, just like in D.  A wrapped property will call the getter and/or setter appropriately
	when used from MiniD.  The getter and setter are automatically determined, so you don't have to wrap them separately.  It will also work if
	your property is read-only or write-only.

	Params:
		func = An alias to the property to wrap, just like with method wrapping.
		name = The name that should be used on the MiniD side to represent the property.  Defaults to the D property name.
		funcType = The type of the property to wrap.  This defaults to typeof(func), but you might have to use an explicit type if you have
			another class method with the same name as the property but with a different number of parameters.  This can be either
			the type of the setter or the getter.

	Returns:
		A chaining reference to this struct.
	*/
	public typeof(this) property(alias func, char[] name = NameOfFunc!(func), funcType = typeof(func))()
	{
		const name32 = ToUTF32!(name);
		mClass.mMethods[name32] = MDValue(new MDClosure(mClass.mMethods, &WrappedProperty!(func, name, funcType, ClassType), ClassName ~ "." ~ name32));

		return this;
	}

	/// ditto
	public typeof(this) property(alias func, funcType)()
	{
		const name = NameOfFunc!(func);
		const name32 = ToUTF32!(name);
		mClass.mMethods[name32] = MDValue(new MDClosure(mClass.mMethods, &WrappedProperty!(func, name, funcType, ClassType), ClassName ~ "." ~ name32));

		return this;
	}

	/**
	Registers this class as a global variable in the given context.

	Params:
		ctx = The context to load this class into.
		name = The name to give the class in MiniD.  Defaults to "", which means the class's D name will be used as the MiniD name.
	*/
	public void makeGlobal(MDContext ctx, dchar[] name = "")
	{
		if(name.length == 0)
			ctx.globals[ClassName] = MDValue(mClass);
		else
			ctx.globals[name] = MDValue(mClass);
	}

	/**
	Adds this class to some namespace.

	Params:
		ns = The namespace to put this class in.
		name = The name to give the class in MiniD.  Defaults to "", which means the class's D name will be used as the MiniD name.
	*/
	public void addToNamespace(MDNamespace ns, dchar[] name = "")
	{
		if(name.length == 0)
			ns[ClassName] = MDValue(mClass);
		else
			ns[name] = MDValue(mClass);
	}

	static if(CleanCtors.length == 0)
	{
		static if(is(ClassType == class))
			static assert(is(typeof(new ClassType())), "Cannot call default constructor for class " ~ ToUTF8!(ClassName) ~ "; please wrap a constructor explicitly");
		else
			static assert(is(typeof(ClassType())), "Cannot call default constructor for struct " ~ ToUTF8!(ClassName) ~ "; please wrap a constructor explicitly");

		private static int defaultCtor(MDState s, uint numParams)
		{
			auto self = s.getContext!(InstanceType);
			assert(self !is null, "Invalid 'this' parameter passed to " ~ ToUTF8!(ClassName) ~ ".constructor");

			static if(is(ClassType == class))
				self.inst = new ClassType();
			else
				self.inst = ClassType();

			return 0;
		}
	}
	else
	{
		private static int constructor(MDState s, uint numParams)
		{
			auto self = s.getContext!(InstanceType);
			assert(self !is null, "Invalid 'this' parameter passed to " ~ ToUTF8!(ClassName) ~ ".constructor");

			static if(is(ClassType == class))
			{
				static if(is(typeof(new ClassType())))
					const minArgs = 0;
				else
					const minArgs = ParameterTupleOf!(CleanCtors[0]).length;
			}
			else
			{
				static if(is(typeof(ClassType())))
					const minArgs = 0;
				else
					const minArgs = ParameterTupleOf!(CleanCtors[0]).length;
			}

			const maxArgs = ParameterTupleOf!(CleanCtors[$ - 1]).length;

			MDValue[maxArgs] args;

			if(numParams < minArgs)
				s.throwRuntimeException("At least " ~ Itoa!(minArgs) ~ " parameter" ~ (minArgs == 1 ? "" : "s") ~ " expected, not {}", numParams);

			if(numParams > maxArgs)
				numParams = maxArgs;

			static if(minArgs == 0)
			{
				if(numParams == 0)
				{
					static if(is(ClassType == class))
						self.inst = new ClassType();
					else
						self.inst = ClassType();

					return 0;
				}
			}

			for(uint i = 0; i < numParams; i++)
				args[i] = s.getParam(i);

			static if(is(ClassType == class))
				const Switch = GenerateCases!(CleanCtors);
			else
				const Switch = GenerateStructCases!(CleanCtors);

			mixin(Switch);

			dchar[] typeString = "(";

			if(numParams > 0)
			{
				typeString ~= s.getParam(0u).typeString();
	
				for(uint i = 1; i < numParams; i++)
					typeString ~= ", " ~ s.getParam(i).typeString();
			}
	
			typeString ~= ")";

			s.throwRuntimeException("Parameter list {} passed to constructor does not match any wrapped constructors", typeString);
		}
	}
}

/**
Wraps a free function and places it into a given namespace.

Params:
	func = An alias to the function you want to wrap.
	name = The name to call it in MiniD.  Defaults to the D function name.
	funcType = The type of the function to wrap.  This defaults to typeof(func), but you'll need to specify this
		explicitly if you're wrapping an overloaded function, in order to select the proper overload.
	ns = The namespace to put the function in.
*/
public void WrapFunc(alias func, char[] name = NameOfFunc!(func), funcType = typeof(&func))(MDNamespace ns)
{
	const name32 = ToUTF32!(name);
	ns[name32] = new MDClosure(ns, &WrappedFunc!(func, name, funcType), name32);
}

/// ditto
public template WrapFunc(alias func, funcType)
{
	alias WrapFunc!(func, NameOfFunc!(func), funcType) WrapFunc;
}

/**
Wraps a free function and places it into the global namespace of a given context.

Params:
	func = An alias to the function you want to wrap.
	name = The name to call it in MiniD.  Defaults to the D function name.
	funcType = The type of the function to wrap.  This defaults to typeof(func), but you'll need to specify this
		explicitly if you're wrapping an overloaded function, in order to select the proper overload.
	context = The context into whose global namespace this function will be placed.
*/
public void WrapGlobalFunc(alias func, char[] name = NameOfFunc!(func), funcType = typeof(&func))(MDContext context)
{
	const name32 = ToUTF32!(name);
	context.globals[name32] = context.newClosure(&WrappedFunc!(func, name, funcType), name32);
}

/// ditto
public template WrapGlobalFunc(alias func, funcType)
{
	alias WrapGlobalFunc!(func, NameOfFunc!(func), funcType) WrapGlobalFunc;
}

/**
Given a struct type, gives a tuple of strings of the names of fields in the struct.
*/
public template FieldNames(S, int idx = 0)
{
	static if(idx >= S.tupleof.length)
		alias Tuple!() FieldNames;
	else
		alias Tuple!(GetLastName!(S.tupleof[idx].stringof), FieldNames!(S, idx + 1)) FieldNames;
}

private template GetLastName(char[] fullName, int idx = fullName.length - 1)
{
	static if(idx < 0)
		const char[] GetLastName = fullName;
	else static if(fullName[idx] == '.')
		const char[] GetLastName = fullName[idx + 1 .. $];
	else
		const char[] GetLastName = GetLastName!(fullName, idx - 1);
}

private template GenerateCases(Ctors...)
{
	const GenerateCases = "switch(numParams) { default: s.throwRuntimeException(\"Invalid number of parameters ({})\", numParams);\n"
		~ GenerateCasesImpl!(-1, 0, Ctors) ~ "\nbreak; }";
}

private template GenerateCasesImpl(int num, int idx, Ctors...)
{
	static if(Ctors.length == 0)
		const GenerateCasesImpl = "";
	else static if(NumParams!(Ctors[0]) != num)
		const GenerateCasesImpl = "break;\ncase " ~ Itoa!(NumParams!(Ctors[0])) ~ ":\n" ~ GenerateCasesImpl!(NumParams!(Ctors[0]), idx, Ctors);
	else
	{
		const GenerateCasesImpl = "if(TypesMatch!(ParameterTupleOf!(Ctors[" ~ Itoa!(idx) ~ "]))(args[0 .. " ~ Itoa!(num) ~ "]))
{
	ParameterTupleOf!(Ctors[" ~ Itoa!(idx) ~ "]) params;

	foreach(i, arg; params)
		params[i] = ToDType!(typeof(arg))(args[i]);

	self.inst = new ClassType(params);
	return 0;
}\n\n" ~ GenerateCasesImpl!(num, idx + 1, Ctors[1 .. $]);
	}
}

private template GenerateStructCases(Ctors...)
{
	const GenerateStructCases = "switch(numParams) { default: s.throwRuntimeException(\"Invalid number of parameters ({})\", numParams);\n"
		~ GenerateStructCasesImpl!(-1, 0, Ctors) ~ "\nbreak; }";
}

private template GenerateStructCasesImpl(int num, int idx, Ctors...)
{
	static if(Ctors.length == 0)
		const GenerateStructCasesImpl = "";
	else static if(NumParams!(Ctors[0]) != num)
		const GenerateStructCasesImpl = "break;\ncase " ~ Itoa!(NumParams!(Ctors[0])) ~ ":\n" ~ GenerateStructCasesImpl!(NumParams!(Ctors[0]), idx, Ctors);
	else
	{
		const GenerateStructCasesImpl = "if(TypesMatch!(ParameterTupleOf!(Ctors[" ~ Itoa!(idx) ~ "]))(args[0 .. " ~ Itoa!(num) ~ "]))
{
	ParameterTupleOf!(Ctors[" ~ Itoa!(idx) ~ "]) params;

	foreach(i, arg; params)
		params[i] = ToDType!(typeof(arg))(args[i]);

	self.inst = ClassType(params);
	//self.updateFields();
	return 0;
}\n\n" ~ GenerateStructCasesImpl!(num, idx + 1, Ctors[1 .. $]);
	}
}

private template GetStructField(T)
{
	const GetStructField =
	"switch(fieldName)"
	"{"
		"default:"
			"s.throwRuntimeException(\"Attempting to access nonexistent field '{}' from type " ~ T.stringof ~ "\", fieldName);\n"
		~ GetStructFieldImpl!(FieldNames!(T)) ~
	"}";
}

private template GetStructFieldImpl(Fields...)
{
	static if(Fields.length == 0)
		const GetStructFieldImpl = "";
	else
	{
		const GetStructFieldImpl =
		"case \"" ~ Fields[0] ~ "\"d: s.push(ToMiniDType(self." ~ Fields[0] ~ ")); break;\n"
		~ GetStructFieldImpl!(Fields[1 .. $]);
	}
}

private template SetStructField(T)
{
	const SetStructField =
	"switch(fieldName)"
	"{"
		"default:"
			"s.throwRuntimeException(\"Attempting to access nonexistent field '{}' from type " ~ T.stringof ~ "\", fieldName);\n"
		~ SetStructFieldImpl!(FieldNames!(T)) ~
	"}";
}

private template SetStructFieldImpl(Fields...)
{
	static if(Fields.length == 0)
		const SetStructFieldImpl = "";
	else
	{
		const SetStructFieldImpl =
		"case \"" ~ Fields[0] ~ "\"d: self." ~ Fields[0] ~ " = GetParameter!(typeof(self." ~ Fields[0] ~ "))(s, 1); break;\n"
		~ SetStructFieldImpl!(Fields[1 .. $]);
	}
}

private bool TypesMatch(T...)(MDValue[] vals)
{
	foreach(i, type; T)
	{
		if(!CanCastTo!(type)(vals[i]))
			return false;
		else
		{
			static if(isFloatType!(type))
			{
				if(vals[i].isInt())
					return false;
			}
		}
	}

	return true;
}

private template NumParams(T)
{
	const NumParams = ParameterTupleOf!(T).length;
}

private template SortByNumParams(T1, T2)
{
	const SortByNumParams = cast(int)ParameterTupleOf!(T1).length - cast(int)ParameterTupleOf!(T2).length;
}

private class WrappedClass : MDClass
{
	private this(dchar[] name, MDClass base)
	{
		super(name, base);
	}

	public override WrappedInstance newInstance()
	{
		return new WrappedInstance(this);
	}
}

private class WrappedInstance : MDInstance
{
	private Object inst;

	private this(MDClass owner)
	{
		super(owner);
	}
}

private class WrappedStructClass(T) : MDClass
{
	private this(dchar[] name, MDClass base)
	{
		super(name, base);
	}

	public override WrappedStruct!(T) newInstance()
	{
		return new WrappedStruct!(T)(this);
	}

	private int getField(MDState s, uint numParams)
	{
		T* self = &s.getContext!(WrappedStruct!(T)).inst;
		dchar[] fieldName = s.getParam!(MDString)(0).mData;

		const Switch = GetStructField!(T);
		mixin(Switch);

		return 1;
	}

	private int setField(MDState s, uint numParams)
	{
		T* self = &s.getContext!(WrappedStruct!(T)).inst;
		dchar[] fieldName = s.getParam!(MDString)(0).mData;

		const Switch = SetStructField!(T);
		mixin(Switch);

		return 0;
	}
}

private class WrappedStruct(T) : MDInstance
{
	private T inst;

	private this(MDClass owner)
	{
		super(owner);
	}
}

private int WrappedMethod(alias func, funcType, ClassType)(MDState s, uint numParams)
{
	const char[] name = NameOfFunc!(func);
	ParameterTupleOf!(funcType) args;
	const minArgs = MinArgs!(func, funcType);
	const maxArgs = args.length;

	if(numParams < minArgs)
		s.throwRuntimeException("At least " ~ Itoa!(minArgs) ~ " parameter" ~ (minArgs == 1 ? "" : "s") ~ " expected, not {}", numParams);

	if(numParams > maxArgs)
		numParams = maxArgs;

	static if(is(ClassType == class))
		auto self = cast(ClassType)s.getContext!(WrappedInstance).inst;
	else
		auto self = &s.getContext!(WrappedStruct!(ClassType)).inst;

	assert(self !is null, "Invalid 'this' parameter passed to method " ~ ClassType.stringof ~ "." ~ name);

	static if(args.length == 0)
	{
		static if(is(ReturnTypeOf!(funcType) == void))
		{
			mixin("self." ~ name ~ "();");
			return 0;
		}
		else
		{
			mixin("s.push(ToMiniDType(self." ~ name ~ "()));");
			return 1;
		}
	}
	else
	{
		static if(minArgs == 0)
		{
			if(numParams == 0)
			{
				static if(is(ReturnTypeOf!(funcType) == void))
				{
					mixin("self." ~  name ~ "();");
					return 0;
				}
				else
				{
					mixin("s.push(ToMiniDType(self." ~ name ~ "()));");
					return 1;
				}
			}
		}

		foreach(i, arg; args)
		{
			const argNum = i + 1;

			if(i < numParams)
				args[i] = GetParameter!(typeof(arg))(s, i);

			static if(argNum >= minArgs && argNum <= maxArgs)
			{
				if(argNum == numParams)
				{
					static if(is(ReturnTypeOf!(funcType) == void))
					{
						mixin("self." ~ name ~ "(args[0 .. argNum]);");
						return 0;
					}
					else
					{
						mixin("s.push(ToMiniDType(self." ~ name ~ "(args[0 .. argNum])));");
						return 1;
					}
				}
			}
		}
	}

	assert(false, "WrappedMethod should never ever get here.");
}

private int WrappedProperty(alias func, char[] name, funcType, ClassType)(MDState s, uint numParams)
{
	alias ParameterTupleOf!(funcType) Args;

	static if(Args.length == 0)
	{
		alias ReturnTypeOf!(funcType) propType;

		static if(is(typeof(func(InitOf!(propType))) T))
			alias T function(propType) setterType;
		else
			alias void setterType;
	}
	else
	{
		alias funcType setterType;
		alias Args[0] propType;
	}

	static if(is(ClassType == class))
		auto self = cast(ClassType)s.getContext!(WrappedInstance).inst;
	else
		auto self = &s.getContext!(WrappedStruct!(ClassType)).inst;

	assert(self !is null, "Invalid 'this' parameter passed to method " ~ ClassType.stringof ~ "." ~ name);

	if(numParams == 0)
	{
		mixin("s.push(ToMiniDType(self." ~ name ~ "));");
		return 1;
	}
	else
	{
		static if(is(setterType == void))
			s.throwRuntimeException("Attempting to set read-only property '" ~ name ~ "' of type '" ~ ClassType.stringof ~ "'");
		else static if(is(ReturnTypeOf!(setterType) == void))
		{
			mixin("self." ~ name ~ " = GetParameter!(propType)(s, 0);");
			return 0;
		}
		else
		{
			mixin("s.push(ToMiniDType(self." ~ name ~ "(GetParameter!(propType)(s, 0))));");
			return 1;
		}
	}

	assert(false, "WrappedProperty should never ever get here.");
}

private MDClass[TypeInfo] WrappedClasses;
private WrappedInstance[Object] WrappedClassRefs;

private MDClass GetWrappedClass(TypeInfo ti)
{
	if(auto c = ti in WrappedClasses)
		return *c;
		
	return null;
}

private WrappedInstance GetWrappedInstance(Object o)
{
	if(auto i = o in WrappedClassRefs)
		return *i;

	return null;
}

private T GetParameter(T)(MDState s, int index)
{
	static if(is(T : Object) && !is(T : MDObject))
	{
		if(s.isParam!("null")(index))
			return null;

		auto ret = cast(T)s.getParam!(WrappedInstance)(index).inst;
		assert(ret !is null, "Class instance parameter is null");
		return ret;
	}
	else static if(is(T == struct))
	{
		return s.getParam!(WrappedStruct!(T))(index).inst;
	}
	else
		return s.getParam!(T)(index);
}

private T ToDType(T)(ref MDValue v)
{
	static if(is(T : Object) && !is(T : MDObject))
	{
		if(v.isNull())
			return null;

		auto ret = cast(T)v.to!(WrappedInstance).inst;
		assert(ret !is null, "Class instance is null");
		return ret;
	}
	else static if(is(T == struct))
	{
		return v.to!(WrappedStruct!(T)).inst;
	}
	else
		return v.to!(T);
}

private MDValue ToMiniDType(T)(T v)
{
	static if(is(T : Object) && !is(T : MDObject))
	{
		auto cls = GetWrappedClass(typeid(T));

		if(cls !is null)
		{
			if(v is null)
				return MDValue.nullValue;

			if(auto ret = GetWrappedInstance(v))
				return MDValue(ret);

			auto inst = new WrappedInstance(cls);
			inst.inst = v;
			WrappedClassRefs[v] = inst;
			return MDValue(inst);
		}
		else
			throw new MDException("Cannot convert reference to class {} to a MiniD value; class has not been wrapped", typeid(T));
	}
	else static if(is(T == struct))
	{
		auto cls = GetWrappedClass(typeid(T));

		if(cls !is null)
		{
			auto inst = new WrappedStruct!(T)(cls);
			inst.inst = v;
			return MDValue(inst);
		}
		else
			throw new MDException("Cannot convert struct {} to a MiniD value; struct has not been wrapped", typeid(T));
	}
	else
		return MDValue(v);
}
+/