module croc.addons.gl_wrap;

version(CrocAllAddons)
	version = CrocGlAddon;

version(CrocGlAddon)
{

import tango.core.Traits;
import tango.stdc.stringz;

import derelict.opengl.gl;
import derelict.opengl.glu;
import derelict.opengl.glext;
import derelict.util.exception;

import croc.api;

version(CrocGLCheckErrors)
	pragma(msg, "Compiling Croc GL with error checking enabled.");

// Kind of a tiny binding lib just for OGL
void register(CrocThread* t, NativeFunc func, char[] name)
{
	newFunction(t, func, name);
	newGlobal(t, name);
}

void pushGL(char[] funcName, T)(CrocThread* t, T v)
{
	static if(isIntegerType!(realType!(T)))
		pushInt(t, v);
	else static if(is(T == GLboolean))
		pushBool(t, v);
	else static if(isRealType!(realType!(T)))
		pushFloat(t, v);
	else static if(is(T == GLchar))
		pushChar(t, v);
	else static if(is(T == char*))
		pushString(t, fromStringz(v));
	else
		static assert(false, "function " ~ funcName ~ " can't be wrapped");
}

T getGLParam(T)(CrocThread* t, word slot)
{
	static if(isIntegerType!(realType!(T)))
		return cast(T)checkIntParam(t, slot);
	else static if(is(T == GLboolean))
		return cast(T)checkBoolParam(t, slot);
	else static if(isRealType!(realType!(T)))
		return cast(T)checkNumParam(t, slot);
	else static if(is(T == GLchar))
		return cast(T)checkCharParam(t, slot);
	// have to special case for void* since you can't get get typeof(*(void*)) :P
	else static if(is(T == void*) || (isPointerType!(T) && !isPointerType!(typeof(*T))))
	{
		checkAnyParam(t, slot);

		if(isMemblock(t, slot))
			return cast(T)getMemblockData(t, slot).ptr;
		else if(isInt(t, slot))
			return cast(T)getInt(t, slot);
		else if(isNull(t, slot))
			return cast(T)null;
		else
			paramTypeError(t, slot, "memblock|int|null");
	}
	else
		static assert(false, "function can't be wrapped");
}

template getGLParams(uint idx, T...)
{
	static if(idx >= T.length)
		const char[] getGLParams = "";
	else
		const char[] getGLParams =
		"_params[" ~ idx.stringof ~ "] = getGLParam!(ParameterTupleOf!(f)[" ~ idx.stringof ~ "])(t, " ~ idx.stringof ~ " + 1);\n"
		~ getGLParams!(idx + 1, T);
}

uword wrapGL(alias f)(CrocThread* t)
{
	ParameterTupleOf!(f) _params;
	mixin(getGLParams!(0, ParameterTupleOf!(f)));

	static if(is(ReturnTypeOf!(f) == void))
		f(_params);
	else
		pushGL!(NameOfFunc!(f))(t, f(_params));

	version(CrocGLCheckErrors)
	{
		static if(NameOfFunc!(f) == "glBegin")
		{
			pushBool(t, true);
			setRegistryVar(t, "gl.insideBeginEnd");
		}
		else
		{
			static if(NameOfFunc!(f) == "glEnd")
			{
				pushBool(t, false);
				setRegistryVar(t, "gl.insideBeginEnd");
				bool insideBeginEnd = false;
			}
			else
			{
				getRegistryVar(t, "gl.insideBeginEnd");
				bool insideBeginEnd = getBool(t, -1);
				pop(t);
			}

			if(!insideBeginEnd)
			{
				auto err = glGetError();

				if(err != GL_NO_ERROR)
					throwNamedException(t, "GLException", NameOfFunc!(f) ~ " - {}", fromStringz(cast(char*)gluErrorString(err)));
			}
		}
	}

	static if(is(ReturnTypeOf!(f) == void))
		return 0;
	else
		return 1;
}

}