module minid.api_checks;

import minid.utils;

// I'd still really like macros though.
template apiCheckNumParams(char[] numParams, char[] t = "t")
{
	const char[] apiCheckNumParams =
	"debug assert(" ~ t ~ ".stackIndex > " ~ t ~ ".stackBase, (printStack(" ~ t ~ "), printCallStack(" ~ t ~ "), \"fail.\"));" ~
	FuncNameMix ~
	"if((stackSize(" ~ t ~ ") - 1) < " ~ numParams ~ ")"
		"throwException(" ~ t ~ ", __FUNCTION__ ~ \" - not enough parameters (expected {}, only have {} stack slots)\", " ~ numParams ~ ", stackSize(" ~ t ~ ") - 1);";
}
