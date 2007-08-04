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

module minid.bind;

import minid.types;
import minid.utils;
import tango.core.Traits;
import tango.core.Tuple;
import utf = tango.text.convert.Utf;

/// Creates a module with the given name and members.
public void WrapModule(dchar[] name, Members...)(MDContext context)
{
	context.setModuleLoader(name, new MDClosure(context.globals.ns, delegate int (MDState s, uint numParams)
	{
		MDNamespace ns = s.getParam!(MDNamespace)(1);

		foreach(i, member; Members)
		{
			static if(is(typeof(member.isFunc)))
			{
				dchar[] name = utf.toUtf32(member.Name);
				ns[name] = MDValue(new MDClosure(ns, &member.Function, name));
			}
			else static if(is(typeof(member.isClass)))
			{
				dchar[] name = utf.toUtf32(member.Name);
				ns[name] = MDValue(new member.Class());
			}
			else
				static assert(false, "Invalid member type '" ~ typeof(member).stringof ~ "' in wrapped module '" ~ name ~ "'");
		}

		return 0;
	}, "module " ~ name));
}

/// This wraps a function, and is meant to be used as a parameter to WrapModule.
public struct WrapFunc(alias func, char[] name = NameOfFunc!(func), funcType = typeof(&func))
{
	const bool isFunc = true;
	alias WrappedFunc!(func, name, funcType) Function;
	const char[] Name = name;
}

/// ditto
public template WrapFunc(alias func, funcType)
{
	alias WrapFunc!(func, NameOfFunc!(func), funcType) WrapFunc;
}

/// Given a function alias, and an optional name and type for overloading, this will wrap the function and register
/// it in the global namespace.  This is not meant to be used as a parameter to WrapModule, as it's not in any module.
public void WrapGlobalFunc(alias func, char[] name = NameOfFunc!(func), funcType = typeof(&func))(MDContext context)
{
	dchar[] n = utf.toUtf32(name);
	context.globals[n] = context.newClosure(&WrappedFunc!(func, name, funcType), n);
}

/// ditto
public template WrapGlobalFunc(alias func, funcType)
{
	alias WrapGlobalFunc!(func, NameOfFunc!(func), funcType) WrapGlobalFunc;
}

private class WrappedInstance : MDInstance
{
	private this(MDClass owner)
	{
		super(owner);
	}

	private Object inst;
}

/// Wraps a D class of the given type with the given members.  name is the name that will be given to the class in MiniD.
public struct WrapClass(ClassType, char[] name = ClassType.stringof, Members...)
{
	static assert(!is(ClassType == Object), "Wrapping Object is not allowed");

	const bool isClass = true;
	const char[] Name = name;

	static class Class : MDClass
	{
		private this()
		{
			alias BaseTypeTupleOf!(ClassType) Bases;
			
			WrappedClasses[typeid(ClassType)] = this;
			dchar[] className = utf.toUtf32(name);

			static if(!is(Bases[0] == Object))
			{
				super(className, GetWrappedClass(typeid(Bases[0])));
			}
			else
			{
				super(className, null);
			}
			
			bool hasOwnCtors = false;

			foreach(i, member; Members)
			{
				static if(is(typeof(member.isMethod)))
				{
					dchar[] name = utf.toUtf32(member.Name);
					mMethods[name] = MDValue(new MDClosure(mMethods, &WrappedMethod!(member.Func, member.Name, member.FuncType, ClassType), className ~ "." ~ name));
				}
				else static if(is(typeof(member.isProperty)))
				{
					dchar[] name = utf.toUtf32(member.Name);
					mMethods[name] = MDValue(new MDClosure(mMethods, &WrappedProperty!(member.Func, member.Name, member.FuncType, ClassType), className ~ "." ~ name));
				}
				else static if(is(typeof(member.isCtors)))
				{
					assert(hasOwnCtors == false, "Cannot have more than one WrapCtors instance in wrapped class parameters");
					hasOwnCtors = true;
					mMethods["constructor"d] = MDValue(new MDClosure(mMethods, &constructor!(member.Types), className ~ ".constructor"));
				}
				else
					static assert(false, "Invalid member type '" ~ typeof(member).stringof ~ "' in wrapped class '" ~ name ~ "'");
			}

			if(!hasOwnCtors)
				mMethods["constructor"d] = MDValue(new MDClosure(mMethods, &defaultCtor, className ~ ".constructor"));
		}

		public override WrappedInstance newInstance()
		{
			return new WrappedInstance(this);
		}

		private int defaultCtor(MDState s, uint numParams)
		{
			static assert(is(typeof(new ClassType())), "Cannot call default constructor for class " ~ ClassType.stringof ~ "; please wrap a constructor explicitly");
			
			auto self = s.getContext!(WrappedInstance);
			assert(self !is null, "Invalid 'this' parameter passed to " ~ ClassType.stringof ~ ".constructor");
			
			self.inst = new ClassType();
			return 0;
		}

		private int constructor(Ctors...)(MDState s, uint numParams)
		{
			auto self = s.getContext!(WrappedInstance);
			assert(self !is null, "Invalid 'this' parameter passed to " ~ ClassType.stringof ~ ".constructor");

			static if(is(typeof(new ClassType())))
				const minArgs = 0;
			else
				const minArgs = ParameterTupleOf!(Ctors[0]).length;

			const maxArgs = ParameterTupleOf!(Ctors[$ - 1]).length;

			MDValue[maxArgs] args;

			if(numParams < minArgs)
				s.throwRuntimeException("At least " ~ itoa!(minArgs) ~ " parameter" ~ (minArgs == 1 ? "" : "s") ~ " expected, not {}", minArgs, numParams);

			if(numParams > maxArgs)
				numParams = maxArgs;

			static if(minArgs == 0)
			{
				if(numParams == 0)
				{
					self.inst = new ClassType();
					return 0;
				}
			}
			
			for(uint i = 0; i < numParams; i++)
				args[i] = s.getParam(i);

			const Switch = GenerateCases!(Ctors);
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
		const GenerateCasesImpl = "break;\ncase " ~ itoa!(NumParams!(Ctors[0])) ~ ":\n" ~ GenerateCasesImpl!(NumParams!(Ctors[0]), idx, Ctors);
	else
	{
		const GenerateCasesImpl = "if(TypesMatch!(ParameterTupleOf!(Ctors[" ~ itoa!(idx) ~ "]))(args[0 .. " ~ itoa!(num) ~ "]))
{
	ParameterTupleOf!(Ctors[" ~ itoa!(idx) ~ "]) params;

	foreach(i, arg; params)
		params[i] = ToDType!(typeof(arg))(args[i]);

	self.inst = new ClassType(params);
	return 0;
}\n\n" ~ GenerateCasesImpl!(num, idx + 1, Ctors[1 .. $]);
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

/// Like WrapClass but lets you skip the name.  This is named differently because otherwise there would be a naming conflict.
public template WrapClassEx(ClassType, Members...)
{
	alias WrapClass!(ClassType, ClassType.stringof, Members) WrapClassEx;
}

/// Wrap a class and insert it into the global namespace.
public void WrapGlobalClass(ClassType, char[] name = ClassType.stringof, Members...)(MDContext context)
{
	dchar[] n = utf.toUtf32(name);
	context.globals[n] = MDValue(new WrapClass!(ClassType, name, Members).Class());
}

/// Like WrapGlobalClass but lets you skip the name.  This is named differently because otherwise there would be a naming conflict.
public template WrapGlobalClassEx(ClassType, Members...)
{
	alias WrapGlobalClass!(ClassType, ClassType.stringof, Members) WrapGlobalClassEx;
}

/// Wrap a class method given an alias to the method (like A.foo).  To be used as a parameter to one of the class wrapping templates.
public struct WrapMethod(alias func, char[] name = NameOfFunc!(func), funcType = typeof(&func))
{
	const bool isMethod = true;
	alias func Func;
	const char[] Name = name;
	alias funcType FuncType;
}

/// ditto
public template WrapMethod(alias func, funcType)
{
	alias WrapMethod!(func, NameOfFunc!(func), funcType) WrapMethod;
}

/// Wrap a property given an alias to the property (like A.foo).  To be used as a parameter to one of the class wrapping templates.
/// MiniD doesn't have properties, but there is a protocol for property-like functions.  A function which takes one parameter and
/// returns 0 or 1 values is a setter; a function of the same name with no parameters is the getter.  This will automatically
/// figure out the setters/getters of the D class's properties, and wrap them into a single MiniD method which will call the setter
/// or getter as appropriate based on how many parameters were passed to the MiniD method.
public struct WrapProperty(alias func, char[] name = NameOfFunc!(func), funcType = typeof(&func))
{
	const bool isProperty = true;
	alias func Func;
	const char[] Name = name;
	alias funcType FuncType;
}

public struct WrapCtors(T...)
{
	static assert(T.length > 0, "WrapCtors must be instantiated with at least one type");
	const bool isCtors = true;
	alias Unique!(QSort!(SortByNumParams, T)) Types;
}

private template SortByNumParams(T1, T2)
{
	const SortByNumParams = cast(int)ParameterTupleOf!(T1).length - cast(int)ParameterTupleOf!(T2).length;
}

private template itoa(int i)
{
	static if(i < 0)
		const char[] itoa = "-" ~ itoa!(-i);
	else static if(i > 10)
		const char[] itoa = itoa!(i / 10) ~ "0123456789"[i % 10];
	else
		const char[] itoa = "" ~ "0123456789"[i % 10];
}

private MDClass[TypeInfo] WrappedClasses;

private MDClass GetWrappedClass(TypeInfo ti)
{
	if(auto c = ti in WrappedClasses)
		return *c;
		
	return null;
}

private int WrappedFunc(alias func, char[] name, funcType)(MDState s, uint numParams)
{
	ParameterTupleOf!(funcType) args;
	const minArgs = MinArgs!(func);
	const maxArgs = args.length;

	if(numParams < minArgs)
		s.throwRuntimeException("At least " ~ itoa!(minArgs) ~ " parameter" ~ (minArgs == 1 ? "" : "s") ~ " expected, not {}", minArgs, numParams);

	if(numParams > maxArgs)
		numParams = maxArgs;

	static if(args.length == 0)
	{
		static if(is(ReturnTypeOf!(funcType) == void))
		{
			func();
			return 0;
		}
		else
		{
			s.push(ToMiniDType(func()));
			return 1;
		}
	}
	else
	{
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
						func(args[0 .. argNum]);
						return 0;
					}
					else
					{
						s.push(ToMiniDType(func(args[0 .. argNum])));
						return 1;
					}
				}
			}
		}
	}

	assert(false, "WrappedFunc should never ever get here.");
}

private int WrappedMethod(alias func, char[] name, funcType, ClassType)(MDState s, uint numParams)
{
	ParameterTupleOf!(funcType) args;
	const minArgs = MinArgs!(func);
	const maxArgs = args.length;

	if(numParams < minArgs)
		s.throwRuntimeException("At least " ~ itoa!(minArgs) ~ " parameter" ~ (minArgs == 1 ? "" : "s") ~ " expected, not {}", numParams);

	if(numParams > maxArgs)
		numParams = maxArgs;

	auto self = cast(ClassType)s.getContext!(WrappedInstance).inst;
	assert(self !is null, "Invalid 'this' parameter passed to method " ~ ClassType.stringof ~ "." ~ name);

	static if(args.length == 0)
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
	else
	{
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

		static if(is(typeof(func(propType.init)) T))
			alias T function(propType) setterType;
		else
			alias void setterType;
	}
	else
	{
		alias funcType setterType;
		alias Args[0] propType;
	}

	auto self = cast(ClassType)s.getContext!(WrappedInstance).inst;
	assert(self !is null, "Invalid 'this' parameter passed to method " ~ ClassType.stringof ~ "." ~ name);

	if(numParams == 0)
	{
		mixin("s.push(ToMiniDType(self." ~ name ~ "));");
		return 1;
	}
	else
	{
		static if(is(setterType == void))
			s.throwRuntimeException("Attempting to set read-only property '" ~ name ~ "' of class '" ~ ClassType.stringof ~ "'");
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
	else
		return v.to!(T);
}

private bool CanCastTo(T)(ref MDValue v)
{
	static if(is(T : Object) && !is(T : MDObject))
	{
		if(v.isNull())
			return true;

		if(!v.canCastTo!(WrappedInstance))
			return false;
			
		return (cast(T)v.as!(WrappedInstance).inst) !is null;
	}
	else
		return v.canCastTo!(T);
}

private WrappedInstance[Object] WrappedClassRefs;

private MDValue ToMiniDType(T)(T v)
{
	static if(is(T : Object) && !is(T : MDObject))
	{
		auto cls = GetWrappedClass(typeid(T));

		if(cls !is null)
		{
			if(v is null)
				return MDValue.nullValue;

			auto ret = v in WrappedClassRefs;

			if(ret)
				return MDValue(*ret);
			else
			{
				WrappedInstance inst = new WrappedInstance(cls);
				inst.inst = v;
				WrappedClassRefs[v] = inst;
				return MDValue(inst);
			}
		}
		else
			throw new MDException("Cannot convert reference to class {} to a MiniD value; class has not been wrapped", typeid(T));
	}
	else
		return MDValue(v);
}

/// Given an alias to a function, this metafunction will give the minimum legal number of arguments it can be called with.
/// Even works for aliases to class methods.
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

/// Given a type tuple, this metafunction will give an expression tuple of all the .init values for each type.
public template InitsOf(T...)
{
	static if(T.length == 0)
		alias Tuple!() InitsOf;
	else static if(is(T[0] == MDValue))
		alias Tuple!(MDValue.nullValue, InitsOf!(T[1 .. $])) InitsOf;
	else
		alias Tuple!(T[0].init, InitsOf!(T[1 .. $])) InitsOf;
}