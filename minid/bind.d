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

		static if(moduleName.length == 0)
			const TypeName = name;
		else
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
				auto f = &WrappedProperty!(member.Func, member.FuncType, Type, TypeName);
				newFunction(t, f, name ~ "." ~ member.Name);
				fielda(t, -2, member.Name);
			}
			else static if(is(typeof(member.isCtors)))
			{
				// ignore
			}
			else static if(is(typeof(member.isValue)))
			{
				superPush(t, member.Value);
				fielda(t, -2, member.Name);
			}
			else
				static assert(false, "Invalid member type '" ~ member.stringof ~ "' in wrapped type '" ~ typeName ~ "'");
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
			checkInstParam(t, 0, FullName);

			static if(is(Type == class))
			{
				auto obj = new Type();
				pushNativeObj(t, obj);
				setExtraVal(t, 0, 0);
				setWrappedInstance(t, obj, 0);
			}
			else
			{
				pushNativeObj(t, new StructWrapper!(Type)(Type()));
				setExtraVal(t, 0, 0);
			}

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
					{
						auto obj = new Type();
						pushNativeObj(t, obj);
						setExtraVal(t, 0, 0);
						setWrappedInstance(t, obj, 0);
					}
					else
					{
						pushNativeObj(t, new StructWrapper!(Type)(Type()));
						setExtraVal(t, 0, 0);
					}

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

public struct WrapProperty(alias func)
{
	const bool isProperty = true;
	const char[] Name = NameOfFunc!(func);
	const bool explicitType = false;
	alias func Func;
	alias typeof(&func) FuncType;
}

public struct WrapProperty(alias func, char[] name)
{
	const bool isProperty = true;
	const char[] Name = name;
	const bool explicitType = false;
	alias func Func;
	alias typeof(&func) FuncType;
}

public struct WrapProperty(alias func, funcType)
{
	const bool isProperty = true;
	const char[] Name = NameOfFunc!(func);
	const bool explicitType = true;
	alias func Func;
	alias typeof(&func) FuncType;
}

public struct WrapProperty(alias func, char[] name, funcType)
{
	const bool isProperty = true;
	const char[] Name = name;
	const bool explicitType = true;
	alias func Func;
	alias typeof(&func) FuncType;
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

void setWrappedInstance(MDThread* t, Object o, word idx)
{
	pushWrappedInstances(t);
	pushNativeObj(t, o);
	pushWeakRef(t, idx);
	idxa(t, -3);
	pop(t);
}

// assumes class object is on the top of the stack
word getWrappedInstance(MDThread* t, Object o)
{
	pushWrappedInstances(t);
	pushNativeObj(t, o);
	idx(t, -2);
	deref(t, -1);

	if(isNull(t, -1))
	{
		pop(t, 2);

		newInstance(t, -3, 1);
		pushNativeObj(t, o);
		setExtraVal(t, -1, 0);

		pushNativeObj(t, o);
		pushWeakRef(t, -2);

		idxa(t, -4);
		insertAndPop(t, -2);
	}
	else
		insertAndPop(t, -3);
		
	return stackSize(t) - 1;
}

word pushWrappedInstances(MDThread* t)
{
	auto reg = getRegistry(t);
	pushString(t, "minid.bind.WrappedInstances");

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
							safeCode(t, func(args[0 .. argNum]));
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

private uword WrappedProperty(alias func, funcType, Type, char[] FullName)(MDThread* t, uword numParams)
{
	const char[] name = NameOfFunc!(func);

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

	static if(is(Type == class))
		auto self = checkClassSelf!(Type, FullName)(t);
	else
		auto self = checkStructSelf!(Type, FullName)(t);

	assert(self !is null, "Invalid 'this' parameter passed to method " ~ FullName ~ "." ~ name);

	if(numParams == 0)
	{
		mixin("superPush(t, safeCode(t, self." ~ name ~ "));");
		return 1;
	}
	else
	{
		static if(is(setterType == void))
			throwException(t, "Attempting to set read-only property '" ~ name ~ "' of type '" ~ FullName ~ "'");
		else static if(is(ReturnTypeOf!(setterType) == void))
		{
			propType val = void;
			getParameter(t, 1, val);
			mixin("safeCode(t, self." ~ name ~ " = val);");
			return 0;
		}
		else
		{
			propType val = void;
			getParameter(t, 1, val);
			mixin("superPush(t, safeCode(t, self." ~ name ~ "(val)));");
			return 1;
		}
	}

	assert(false, "WrappedProperty should never ever get here.");
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

		return getWrappedInstance(t, val);
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

// BUG 1667
T InitOf_shim(T)()
{
	T t;
	return t;
}

// This template exists for the sole reason that T.init doesn't work for structs inside templates due
// to a forward declaration error.
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

	auto obj = new Type(params);
	pushNativeObj(t, obj);
	setExtraVal(t, 0, 0);
	setWrappedInstance(t, obj, 0);
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
		"case \"" ~ Fields[0] ~ "\": static if(!is(typeof(self. " ~ Fields[0] ~ "))) goto default; else "
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
		"case \"" ~ Fields[0] ~ "\": static if(!is(typeof(self. " ~ Fields[0] ~ "))) goto default; else "
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