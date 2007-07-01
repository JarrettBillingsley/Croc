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
public void WrapModule(dchar[] name, Members...)()
{
	MDGlobalState().setModuleLoader(name, new MDClosure(MDGlobalState().globals.ns, delegate int (MDState s, uint numParams)
	{
		MDNamespace ns = s.getParam!(MDNamespace)(1);

		foreach(i, member; Members)
		{
			static if(is(typeof(member.isFunc)))
			{
				dchar[] name = utf.toUtf32(member.Name);
				ns[name] = new MDClosure(ns, &member.Function, name);
			}
		}

		return 0;
	}, "load " ~ name));
}

/// This wraps a function, and is meant to be used as a parameter to WrapModule.
public struct WrapFunc(alias func, char[] name = NameOfFunc!(func), funcType = typeof(&func))
{
	const bool isFunc = true;
	alias WrappedFunc!(func, name, funcType) Function;
	const char[] Name = name;
}

/// Given a function alias, and an optional name and type for overloading, this will wrap the function and register
/// it in the global namespace.
public void WrapGlobalFunc(alias func, char[] name = NameOfFunc!(func), funcType = typeof(&func))()
{
	MDGlobalState().globals[utf.toUtf32(name)] = MDGlobalState().newClosure(&WrappedFunc!(func, name, funcType), utf.toUtf32(name));
}

public struct WrapClass(alias Class, char[] name = ClassName.stringof, Members...)
{
	const bool isClass = true;
	const char[] Name = name;
		
}

private int WrappedFunc(alias func, char[] name, funcType)(MDState s, uint numParams)
{
	ParameterTupleOf!(funcType) args;
	const minArgs = MinArgs!(funcType);
	const maxArgs = args.length;

	if(numParams < minArgs)
		s.throwRuntimeException("Function " ~ name ~ " expects at least {} parameter" ~ (minArgs == 1 ? "" : "s") ~ ", not {}", minArgs, numParams);

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
			s.push(func());
			return 1;
		}
	}
	else
	{
		foreach(i, arg; args)
		{
			const argNum = i + 1;
			
			if(i < numParams)
				args[i] = s.getParam!(typeof(arg))(i);
	
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
						s.push(func(args[0 .. argNum]));
						return 1;
					}
				}
			}
		}
	}

	assert(false, "WrapFunc should never ever get here.");
}

/// Given an alias to a function, or a function type, this metafunction will give the minimum legal number of
/// arguments it can be called with.
public template MinArgs(alias func)
{
	const uint MinArgs = MinArgs!(typeof(&func));
}

/// ditto
public template MinArgs(funcType)
{
	const uint MinArgs = MinArgsImpl!(funcType, 0, InitsOf!(ParameterTupleOf!(funcType)));
}

public template MinArgsImpl(funcType, int index, Args...)
{
	static if(index >= Args.length)
		const uint MinArgsImpl = Args.length;
	else static if(is(typeof(funcType(Args[0 .. index]))))
		const uint MinArgsImpl = index;
	else
		const uint MinArgsImpl = MinArgsImpl!(funcType, index + 1, Args);
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

/// Gets the name of a function alias.
public template NameOfFunc(alias f)
{
	const char[] NameOfFunc = (&f).stringof[2 .. $];
}