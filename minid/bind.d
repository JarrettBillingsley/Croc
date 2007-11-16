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

/**
Creates a module with the given name and members.
*/
public void WrapModule(char[] name, Members...)(MDContext context)
{
	dchar[] name32 = utf.toUtf32(name);

	context.setModuleLoader(name32, new MDClosure(context.globals.ns, delegate int (MDState s, uint numParams)
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
			else static if(is(typeof(member.isStruct)))
			{
				dchar[] name = utf.toUtf32(member.Name);
				ns[name] = MDValue(new member.Class());
			}
			else static if(is(typeof(member.isCustom)))
			{
				dchar[] name = utf.toUtf32(member.Name);

				static assert(!is(ReturnTypeOf!(member.Func) == void), "Custom member function may not return void");

				static if(is(typeof(member.Func(s, ns))))
					ns[name] = MDValue(member.Func(s, ns));
				else
					ns[name] = MDValue(member.Func());
			}
			else
				static assert(false, "Invalid member type '" ~ typeof(member).stringof ~ "' in wrapped module '" ~ name ~ "'");
		}

		return 0;
	}, "module " ~ name32));
}

/**
This wraps a function, and is meant to be used as a parameter to WrapModule.
*/
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

/**
Given a function alias, and an optional name and type for overloading, this will wrap the function and register
it in the global namespace.  This is not meant to be used as a parameter to WrapModule, as it's not in any module.
*/
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

public struct WrapCustom(char[] name, alias func)
{
	const bool isCustom = true;
	const char[] Name = name;
	alias func Func;
}

private class WrappedInstance : MDInstance
{
	private Object inst;

	private this(MDClass owner)
	{
		super(owner);
	}
}

private class WrappedStruct(T) : MDInstance
{
//	alias FieldNames!(T) fieldNames;
	private T inst;

	private this(MDClass owner)
	{
		super(owner);
	}

// 	private void updateFields()
// 	{
// 		foreach(i, v; fieldNames)
// 			mFields[mixin("\"" ~ fieldNames[i] ~ "\"d")] = MDValue(inst.tupleof[i]);
// 	}
// 
// 	private T* toStruct()
// 	{
// 		foreach(i, v; fieldNames)
// 			inst.tupleof[i] = mFields[mixin("\"" ~ fieldNames[i] ~ "\"d")].to!(typeof(inst.tupleof[i]));
// 
// 		return &inst;
// 	}
}

/**
Wraps a D class of the given type with the given members.  name is the name that will be given to the class in MiniD.
*/
public struct WrapClass(ClassType, char[] name = ClassType.stringof, Members...)
{
	static assert(!is(ClassType == Object), "Wrapping Object is not allowed");

	const bool isClass = true;
	const char[] Name = name;
	const CtorCount = CountCtors!(Members);

	static assert(CtorCount <= 1, "Cannot have more than one WrapCtors instance in wrapped class parameters for class " ~ ClassType.stringof);

	static class Class : MDClass
	{
		private this()
		{
			alias BaseTypeTupleOf!(ClassType) Bases;
			
			if(typeid(ClassType) in WrappedClasses)
				throw new MDException("Native class " ~ ClassType.stringof ~ " cannot be wrapped more than once");
			
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

			foreach(i, member; Members)
			{
				static if(is(typeof(member.isMethod)))
				{
					dchar[] name = utf.toUtf32(member.Name);
					mMethods[name] = MDValue(new MDClosure(mMethods, &WrappedMethod!(member.Func, member.FuncType, ClassType), className ~ "." ~ name));
				}
				else static if(is(typeof(member.isProperty)))
				{
					dchar[] name = utf.toUtf32(member.Name);
					mMethods[name] = MDValue(new MDClosure(mMethods, &WrappedProperty!(member.Func, member.Name, member.FuncType, ClassType), className ~ "." ~ name));
				}
				else static if(is(typeof(member.isCtors)))
				{
					mMethods["constructor"d] = MDValue(new MDClosure(mMethods, &constructor!(member.Types), className ~ ".constructor"));
				}
				else
					static assert(false, "Invalid member type '" ~ typeof(member).stringof ~ "' in wrapped class '" ~ name ~ "'");
			}

			static if(CtorCount == 0)
				mMethods["constructor"d] = MDValue(new MDClosure(mMethods, &defaultCtor, className ~ ".constructor"));
		}

		public override WrappedInstance newInstance()
		{
			return new WrappedInstance(this);
		}

		static if(CtorCount == 0)
		{
			static assert(is(typeof(new ClassType())), "Cannot call default constructor for class " ~ ClassType.stringof ~ "; please wrap a constructor explicitly");

			private int defaultCtor(MDState s, uint numParams)
			{
				auto self = s.getContext!(WrappedInstance);
				assert(self !is null, "Invalid 'this' parameter passed to " ~ ClassType.stringof ~ ".constructor");

				self.inst = new ClassType();
				return 0;
			}
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
				s.throwRuntimeException("At least " ~ itoa!(minArgs) ~ " parameter" ~ (minArgs == 1 ? "" : "s") ~ " expected, not {}", numParams);

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
		const GenerateStructCasesImpl = "break;\ncase " ~ itoa!(NumParams!(Ctors[0])) ~ ":\n" ~ GenerateStructCasesImpl!(NumParams!(Ctors[0]), idx, Ctors);
	else
	{
		const GenerateStructCasesImpl = "if(TypesMatch!(ParameterTupleOf!(Ctors[" ~ itoa!(idx) ~ "]))(args[0 .. " ~ itoa!(num) ~ "]))
{
	ParameterTupleOf!(Ctors[" ~ itoa!(idx) ~ "]) params;

	foreach(i, arg; params)
		params[i] = ToDType!(typeof(arg))(args[i]);

	self.inst = StructType(params);
	//self.updateFields();
	return 0;
}\n\n" ~ GenerateStructCasesImpl!(num, idx + 1, Ctors[1 .. $]);
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

/**
Like WrapClass but lets you skip the name.  This is named differently because otherwise there would be a naming conflict.
*/
public template WrapClassEx(ClassType, Members...)
{
	alias WrapClass!(ClassType, ClassType.stringof, Members) WrapClassEx;
}

/**
Wrap a class and insert it into the global namespace.
*/
public void WrapGlobalClass(ClassType, char[] name = ClassType.stringof, Members...)(MDContext context)
{
	dchar[] n = utf.toUtf32(name);
	context.globals[n] = MDValue(new WrapClass!(ClassType, name, Members).Class());
}

/**
Like WrapGlobalClass but lets you skip the name.  This is named differently because otherwise there would be a naming conflict.
*/
public template WrapGlobalClassEx(ClassType, Members...)
{
	alias WrapGlobalClass!(ClassType, ClassType.stringof, Members) WrapGlobalClassEx;
}

/**
Wrap a class method given an alias to the method (like A.foo).  To be used as a parameter to one of the class wrapping templates.
*/
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

/**
Wrap a property given an alias to the property (like A.foo).  To be used as a parameter to one of the class wrapping templates.
MiniD doesn't have properties, but there is a protocol for property-like functions.  A function which takes one parameter and
returns 0 or 1 values is a setter; a function of the same name with no parameters is the getter.  This will automatically
figure out the setters/getters of the D class's properties, and wrap them into a single MiniD method which will call the setter
or getter as appropriate based on how many parameters were passed to the MiniD method.
*/
public struct WrapProperty(alias func, char[] name = NameOfFunc!(func), funcType = typeof(&func))
{
	const bool isProperty = true;
	alias func Func;
	const char[] Name = name;
	alias funcType FuncType;
}

/**
Wrap a list of constructors for a class.  To be used as a parameter to one of the class wrapping templates.  The parameters to
this should be a list of function types in the form "void function(params)".  You can wrap multiple constructors with the
same number of parameters.
*/
public struct WrapCtors(T...)
{
	static assert(T.length > 0, "WrapCtors must be instantiated with at least one type");
	const bool isCtors = true;
	alias Unique!(QSort!(SortByNumParams, T)) Types;
}

/**
Wraps a D class of the given type with the given members.  name is the name that will be given to the class in MiniD.
*/
public struct WrapStruct(StructType, char[] name = StructType.stringof, Members...)
{
	const bool isStruct = true;
	const char[] Name = name;
	const CtorCount = CountCtors!(Members);

	static assert(CtorCount <= 1, "Cannot have more than one WrapCtors instance in wrapped struct parameters for struct " ~ StructType.stringof);

	static class Class : MDClass
	{
		private this()
		{
			if(typeid(StructType) in WrappedClasses)
				throw new MDException("Native struct " ~ StructType.stringof ~ " cannot be wrapped more than once");

			WrappedClasses[typeid(StructType)] = this;
			dchar[] structName = utf.toUtf32(name);
			
			super(structName, null);

			//foreach(i, n; FieldNames!(StructType))
			//	mFields[mixin("\"" ~ FieldNames!(StructType)[i] ~ "\"d")] = MDValue(StructType.init.tupleof[i]);

			mMethods["opIndex"d] = MDValue(new MDClosure(mMethods, &getField, structName ~ ".opIndex"));
			mMethods["opIndexAssign"d] = MDValue(new MDClosure(mMethods, &setField, structName ~ ".opIndexAssign"));

			foreach(i, member; Members)
			{
				static if(is(typeof(member.isMethod)))
				{
					dchar[] name = utf.toUtf32(member.Name);
					mMethods[name] = MDValue(new MDClosure(mMethods, &WrappedMethod!(member.Func, member.FuncType, StructType), structName ~ "." ~ name));
				}
				else static if(is(typeof(member.isProperty)))
				{
					dchar[] name = utf.toUtf32(member.Name);
					mMethods[name] = MDValue(new MDClosure(mMethods, &WrappedProperty!(member.Func, member.Name, member.FuncType, StructType), structName ~ "." ~ name));
				}
				else static if(is(typeof(member.isCtors)))
				{
					mMethods["constructor"d] = MDValue(new MDClosure(mMethods, &constructor!(member.Types), structName ~ ".constructor"));
				}
				else
					static assert(false, "Invalid member type '" ~ typeof(member).stringof ~ "' in wrapped struct '" ~ name ~ "'");
			}

			static if(CtorCount == 0)
				mMethods["constructor"d] = MDValue(new MDClosure(mMethods, &defaultCtor, structName ~ ".constructor"));
		}

		public override WrappedStruct!(StructType) newInstance()
		{
			return new WrappedStruct!(StructType)(this);
		}

		static if(CtorCount == 0)
		{
			private int defaultCtor(MDState s, uint numParams)
			{
				auto self = s.getContext!(WrappedInstance);
				assert(self !is null, "Invalid 'this' parameter passed to " ~ StructType.stringof ~ ".constructor");

				self.inst = StructType.init;
				return 0;
			}
		}

		private int constructor(Ctors...)(MDState s, uint numParams)
		{
			auto self = s.getContext!(WrappedStruct!(StructType));
			assert(self !is null, "Invalid 'this' parameter passed to " ~ StructType.stringof ~ ".constructor");

			static if(is(typeof(StructType())))
				const minArgs = 0;
			else
				const minArgs = ParameterTupleOf!(Ctors[0]).length;

			const maxArgs = ParameterTupleOf!(Ctors[$ - 1]).length;

			MDValue[maxArgs] args;

			if(numParams < minArgs)
				s.throwRuntimeException("At least " ~ itoa!(minArgs) ~ " parameter" ~ (minArgs == 1 ? "" : "s") ~ " expected, not {}", numParams);

			if(numParams > maxArgs)
				numParams = maxArgs;

			static if(minArgs == 0)
			{
				if(numParams == 0)
				{
					self.inst = StructType();
					return 0;
				}
			}
			
			for(uint i = 0; i < numParams; i++)
				args[i] = s.getParam(i);

			const Switch = GenerateStructCases!(Ctors);
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
		
		private int getField(MDState s, uint numParams)
		{
			StructType* self = &s.getContext!(WrappedStruct!(StructType)).inst;
			dchar[] fieldName = s.getParam!(MDString)(0).mData;

			const Switch = GetStructField!(StructType);
			mixin(Switch);

			return 1;
		}

		private int setField(MDState s, uint numParams)
		{
			StructType* self = &s.getContext!(WrappedStruct!(StructType)).inst;
			dchar[] fieldName = s.getParam!(MDString)(0).mData;

			const Switch = SetStructField!(StructType);
			mixin(Switch);

			return 0;
		}
	}
}

public template WrapStructEx(StructType, Members...)
{
	alias WrapStruct!(StructType, StructType.stringof, Members) WrapStructEx;
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
		"case \"" ~ Fields[0] ~ "\"d: s.push(self." ~ Fields[0] ~ "); break;\n"
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

private template CountCtors(T...)
{
	static if(T.length == 0)
		const CountCtors = 0;
	else
		const CountCtors = (is(typeof(T[0].isCtors)) ? 1 : 0) + CountCtors!(T[1 .. $]);
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
		s.throwRuntimeException("At least " ~ itoa!(minArgs) ~ " parameter" ~ (minArgs == 1 ? "" : "s") ~ " expected, not {}", numParams);

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
		static if(minArgs == 0)
		{
			if(numParams == 0)
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

private int WrappedMethod(alias func, funcType, ClassType)(MDState s, uint numParams)
{
	const char[] name = NameOfFunc!(func);
	ParameterTupleOf!(funcType) args;
	const minArgs = MinArgs!(func);
	const maxArgs = args.length;

	if(numParams < minArgs)
		s.throwRuntimeException("At least " ~ itoa!(minArgs) ~ " parameter" ~ (minArgs == 1 ? "" : "s") ~ " expected, not {}", numParams);

	if(numParams > maxArgs)
		numParams = maxArgs;

	static if(is(ClassType == class))
	{
		auto self = cast(ClassType)s.getContext!(WrappedInstance).inst;
		assert(self !is null, "Invalid 'this' parameter passed to method " ~ ClassType.stringof ~ "." ~ name);
	}
	else
	{
		auto self = &s.getContext!(WrappedStruct!(ClassType)).inst;
	}

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
	else static if(is(T == struct))
	{
		auto cls = GetWrappedClass(typeid(T));

		if(cls !is null)
		{
			auto inst = new WrappedStruct!(T)(cls);
			inst.inst = v;
			//inst.updateFields();
			return MDValue(inst);
		}
		else
			throw new MDException("Cannot convert struct {} to a MiniD value; struct has not been wrapped", typeid(T));
	}
	else
		return MDValue(v);
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

private template GetLastName(char[] fullName, int idx = fullName.length - 1)
{
	static if(idx < 0)
		const char[] GetLastName = fullName;
	else static if(fullName[idx] == '.')
		const char[] GetLastName = fullName[idx + 1 .. $];
	else
		const char[] GetLastName = GetLastName!(fullName, idx - 1);
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