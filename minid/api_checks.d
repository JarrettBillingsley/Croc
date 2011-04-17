module minid.api_checks;

import minid.utils;

// I'd really like macros.
template apiCheckNumParams(char[] numParams, char[] t = "t")
{
	const char[] apiCheckNumParams =
	"debug assert(" ~ t ~ ".stackIndex > " ~ t ~ ".stackBase, (printStack(" ~ t ~ "), printCallStack(" ~ t ~ "), \"fail.\"));" ~
	FuncNameMix ~
	"if((stackSize(" ~ t ~ ") - 1) < " ~ numParams ~ ")"
		"throwException(" ~ t ~ ", __FUNCTION__ ~ \" - not enough parameters (expected {}, only have {} stack slots)\", " ~ numParams ~ ", stackSize(" ~ t ~ ") - 1);";
}

// template apiCheckParam(char[] newVar, char[] idx, char[] paramName, char[] expected, char[] t = "t")
// {
// 
// }

template apiParamTypeError(char[] idx, char[] paramName, char[] expected, char[] t = "t")
{
	const char[] apiParamTypeError =
	"pushTypeString(" ~ t ~ ", " ~ idx ~ ");" ~
	"throwException(" ~ t ~ ", __FUNCTION__ ~ \" - Expected type '" ~ expected ~ "' for " ~ paramName ~ ", not '{}'\", getString(t, -1));";
}