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
import minid.utils : isCharType, NameOfFunc, realType, isStringType, isIntType, isFloatType, isArrayType, isAAType, isExpressionTuple;

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

private void commonNamespace(char[] name, bool isModule, Members...)(MDThread* t)
{
	static if(!isModule)
		newNamespace(t, name);

	foreach(i, member; Members)
	{
		static if(is(typeof(member.isFunc)))
		{
			newFunction(t, &member.WrappedFunc, member.Name);

			static if(isModule)
				newGlobal(t, member.Name);
			else
				fielda(t, -2, member.Name);
		}
		else static if(is(typeof(member.isNamespace)))
		{
			commonNamespace!(member.Name, false, member.Values)(t);

			static if(isModule)
				newGlobal(t, member.Name);
			else
				fielda(t, -2, member.Name);
		}
		else static if(is(typeof(member.isValue)))
		{
			superPush(t, member.Value);

			static if(isModule)
				newGlobal(t, member.Name);
			else
				fielda(t, -2, member.Name);
		}
// 		else static if(is(typeof(member.isClass)))
// 		{
// 			dchar[] name = utf.toUtf32(member.Name);
// 			ns[name] = MDValue(member.makeClass());
// 		}
		else static if(is(typeof(member.isStruct)))
		{
			member.init(t);
			fielda(t, -2, member.Name);
		}
		else static if(isModule)
			static assert(false, "Invalid member type '" ~ member.stringof ~ "' in wrapped module '" ~ name ~ "'");
		else
			static assert(false, "Invalid member type '" ~ member.stringof ~ "' in wrapped namespace '" ~ name ~ "'");
	}
}

public void WrapGlobals(Members...)(MDThread* t)
{
	commonNamespace!("<globals>", true, Members)(t);
}

/**
This wraps a function, and is meant to be used as a parameter to WrapModule.
*/
public struct WrapFunc(alias func)
{
	const bool isFunc = true;
	const char[] Name = NameOfFunc!(func);
	mixin WrappedFunc!(func, Name, typeof(&func));
}

/// ditto
public template WrapFunc(alias func, funcType)
{
	const bool isFunc = true;
	const char[] Name = NameOfFunc!(func);
	mixin WrappedFunc!(func, Name, funcType);
}

/// ditto
public struct WrapFunc(alias func, char[] name)
{
	const bool isFunc = true;
	const char[] Name = name;
	mixin WrappedFunc!(func, Name, typeof(&func));
}

/// ditto
public struct WrapFunc(alias func, char[] name, funcType)
{
	const bool isFunc = true;
	const char[] Name = name;
	mixin WrappedFunc!(func, Name, funcType);
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

private template WrappedFunc(alias func, char[] name, funcType)
{
	static uword WrappedFunc(MDThread* t, uword numParams)
	{
		ParameterTupleOf!(funcType) args;
		const minArgs = MinArgs!(func);
		const maxArgs = args.length;

		if(numParams < minArgs)
			throwException(t, "At least" ~ minArgs.stringof ~ " parameter" ~ (minArgs == 1 ? "" : "s") ~ " expected, not {}", numParams);

		if(numParams > maxArgs)
			numParams = maxArgs;
	
		static if(args.length == 0)
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
		}

		assert(false, "WrappedFunc (" ~ name ~ ") should never ever get here.");
	}
}

private void getParameter(T)(MDThread* t, word index, ref T ret)
{
	static if(is(T : Object))
	{
		if(isNull(t, index))
			return ret = null;

		assert(false);

// 		auto ret = cast(T)s.getParam!(WrappedInstance)(index).inst;
// 		assert(ret !is null, "Class instance parameter is null");
// 		return ret;
	}
// 	else static if(is(T == struct))
// 	{
// 		return s.getParam!(WrappedStruct!(T))(index).inst;
// 	}
	else
		return ret = to!(T)(t, index);
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
// 	else static if(is(T : MDObject))
// 	{
// 		mType = Type.Object;
// 		mObject = src;
// 	}
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

			ret[i] = as!(ElemType)(t, elemIdx);
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

			ret[as!(KeyType)(t, keyIdx)] = as!(ValueType)(t, valIdx);
			pop(t, 2);
		}

		return cast(Type)ret;
	}
	else
	{
		if(!canCastTo!(T)(t, idx))
		{
			pushTypeString(t, idx);
			throwException(t, "to - Cannot convert MiniD type '{}' to D type '" ~ Type.stringof ~ "'", getString(t, -1));
		}

		return cast(Type)convertTo!(T)(t, idx);
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
	else
		return false;
}

private Type convertTo(Type)(MDThread* t, word idx)
{
	alias realType!(Type) T;

	static if(is(T == bool))
	{
		return getBool(t, idx);
	}
	else static if(isIntType!(T))
	{
		return getInt(t, idx);
	}
	else static if(isFloatType!(T))
	{
		if(isInt(t, idx))
			return cast(T)getInt(t, idx);
		else if(isFloat(t, idx))
			return getFloat(t, idx);
		else
			assert(false, "convertTo!(" ~ T.stringof ~ ")");
	}
	else static if(isCharType!(T))
	{
		return getChar(t, idx);
	}
	else static if(isStringType!(T))
	{
		static if(is(T == char[]))
			return getString(t, idx).dup;
		else static if(is(T == wchar[]))
			return Utf.toString16(getString(t, idx));
		else
			return Utf.toString32(getString(t, idx));
	}
	else
	{
		// I do this because static assert won't show the template instantiation "call stack."
		pragma(msg, "convertTo - Invalid argument type '" ~ Type.stringof ~ "'");
		ARGUMENT_ERROR(Type);
	}
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

private template InitOf(T)
{
	static if(!is(typeof(Tuple!(T.init))))
	{
		static assert(is(T == struct), "I don't know what to do with this.");
		alias Tuple!(T(InitsOf!(typeof(T.tupleof)))) InitOf;
	}
	else
		alias Tuple!(T.init) InitOf;
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