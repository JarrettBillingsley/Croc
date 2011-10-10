module croc.addons.devil_wrap;

version(CrocAllAddons)
	version = CrocDevilAddon;

version(CrocDevilAddon)
{

import tango.core.Traits;
import tango.stdc.stringz;

import derelict.devil.il;
import derelict.devil.ilu;

import croc.api;

version(CrocILCheckErrors)
	pragma(msg, "Compiling Croc DevIL with error checking enabled.");

void registerConst(CrocThread* t, char[] name, word value)
{
	pushInt(t, value);
	newGlobal(t, name);
}

void pushIL(char[] funcName, T)(CrocThread* t, T v)
{
	static if(isIntegerType!(realType!(T)))
		pushInt(t, v);
	else static if(is(T == ILboolean))
		pushBool(t, v);
	else static if(isRealType!(realType!(T)))
		pushFloat(t, v);
	else static if(is(T == ILchar))
		pushChar(t, v);
	else static if(is(T == char*) || is(T == ILstring))
		pushString(t, fromStringz(v));
	else
		static assert(false, "function " ~ funcName ~ " can't be wrapped: " ~ T.stringof);
}

T getILParam(T)(CrocThread* t, word slot)
{
	static if(isIntegerType!(realType!(T)))
		return cast(T)checkIntParam(t, slot);
	else static if(is(T == ILboolean))
		return cast(T)checkBoolParam(t, slot);
	else static if(isRealType!(realType!(T)))
		return cast(T)checkNumParam(t, slot);
	else static if(is(T == ILchar))
		return cast(T)checkCharParam(t, slot);
	else static if(is(T == ILstring))
		return toStringz(checkStringParam(t, slot));
	// have to special case for void* since you can't get get typeof(*(void*)) :P
	else static if(is(T == void*) || (isPointerType!(T) && !isPointerType!(typeof(*T)) && !is(typeof(*T) == function) && !is(typeof(*T) == struct)))
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

template getILParams(uint idx, T...)
{
	static if(idx >= T.length)
		const char[] getILParams = "";
	else
		const char[] getILParams =
		"_params[" ~ idx.stringof ~ "] = getILParam!(ParameterTupleOf!(f)[" ~ idx.stringof ~ "])(t, " ~ idx.stringof ~ " + 1);\n"
		~ getILParams!(idx + 1, T);
}

uword wrapIL(alias f)(CrocThread* t)
{
	ParameterTupleOf!(f) _params;
	mixin(getILParams!(0, ParameterTupleOf!(f)));

	static if(is(ReturnTypeOf!(f) == void))
		f(_params);
	else
		pushIL!(NameOfFunc!(f))(t, f(_params));

	version(CrocILCheckErrors)
	{
		auto err = ilGetError();

		if(err != IL_NO_ERROR)
			throwNamedException(t, "DevILException", NameOfFunc!(f) ~ " - {}", fromStringz(cast(char*)iluErrorString(err)));
	}

	static if(is(ReturnTypeOf!(f) == void))
		return 0;
	else
		return 1;
}

}