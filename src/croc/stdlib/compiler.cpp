
#include <string.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{
void _pushFlagsArray(CrocThread* t, uword f)
{
	auto start = croc_getStackSize(t);

	if(f & CrocCompilerFlags_TypeConstraints) croc_pushString(t, "typeconstraints");
	if(f & CrocCompilerFlags_Asserts)         croc_pushString(t, "asserts");
	if(f & CrocCompilerFlags_Debug)           croc_pushString(t, "debug");
	if(f & CrocCompilerFlags_Docs)            croc_pushString(t, "docs");

	croc_array_newFromStack(t, croc_getStackSize(t) - start);
}

uword _stringToFlag(CrocThread* t, word idx)
{
	croc_ex_checkParam(t, idx, CrocType_String);
	auto s = getCrocstr(t, idx);

	if(s == ATODA("typeconstraints"))
		return CrocCompilerFlags_TypeConstraints;
	if(s == ATODA("asserts"))
		return CrocCompilerFlags_Asserts;
	if(s == ATODA("debug"))
		return CrocCompilerFlags_Debug;
	if(s == ATODA("docs"))
		return CrocCompilerFlags_Docs;
	if(s == ATODA("all"))
		return CrocCompilerFlags_All;
	if(s == ATODA("alldocs"))
		return CrocCompilerFlags_AllDocs;

	croc_eh_throwStd(t, "ValueError", "Invalid flag '%.*s'", cast(int)s.length, s.ptr);
	return 0; // dummy
}

const StdlibRegisterInfo _setFlags_info =
{
	Docstr(DFunc("setFlags") DVararg
	R"(Enable and disable VM-wide compiler flags. These control whether or not code is generated for various optional
	language features.

	\param[vararg] are strings which represent the flags. The valid flags are as follows:
		\blist
			\li \tt{"typeconstraints"} enables code generation for parameter type constraints. If you leave out this
				flag, no parameter typechecking is done when calling functions.
			\li \tt{"asserts"} enables code generation for \tt{assert()} statements. If you leave out this flag, assert
				statements become no-ops.
			\li \tt{"debug"} enables outputting debug info (which includes line numbers, local variable info, and
				upvalue names). If you leave out this flag, no debug info will be emitted, saving space at the cost of
				worse error messages/tracebacks. \b{\em{This flag does not yet work properly.} Debug info is always on.}
			\li \tt{"docs"} will cause the compiler to parse documentation comments and place doc decorators on the
				program items they document, meaning run-time accessible documentation will be available. If you leave
				out this flag, doc comments are ignored (unless you use one of the DT compilation functions below).
			\li \tt{"all"} is the same as specifying \tt{"typeconstraints"}, \tt{"asserts"}, and \tt{"debug"}.
			\li \tt{"alldocs"} is the same as specifying \tt{"all"} and \tt{"docs"}.
		\endlist

	\returns an array of strings containing the compiler flags as they were before this function was called. This way
	you can set the compiler flags and then return them to how they were:

\code
local oldFlags = compiler.setFlags("alldocs")

// do some compilation here.

compiler.setFlags(oldFlags.expand()) // restore old flags
\endcode)"),

	"setFlags", -1
};

word_t _setFlags(CrocThread* t)
{
	uword f = 0;

	for(uword i = 1; i < croc_getStackSize(t); i++)
		f |= _stringToFlag(t, i);

	_pushFlagsArray(t, croc_compiler_setFlags(t, f));
	return 1;
}

const StdlibRegisterInfo _getFlags_info =
{
	Docstr(DFunc("getFlags")
	R"(\returns an array of strings containing the compiler's currently enabled flags. See \link{setFlags} for which
	strings it may return (except for \tt{"all"} and \tt{"alldocs"}).)"),

	"getFlags", 0
};

word_t _getFlags(CrocThread* t)
{
	_pushFlagsArray(t, croc_compiler_getFlags(t));
	return 1;
}

void _pushResultToString(CrocThread* t, word result)
{
	switch(result)
	{
		case CrocCompilerReturn_UnexpectedEOF: croc_pushString(t, "unexpectedeof"); break;
		case CrocCompilerReturn_LoneStatement: croc_pushString(t, "lonestatement"); break;
		case CrocCompilerReturn_DanglingDoc:   croc_pushString(t, "danglingdoc");   break;
		case CrocCompilerReturn_Error:         croc_pushString(t, "error");         break;
		default: assert(false);
	}
}

word_t _compileModuleImpl(CrocThread* t, bool dt)
{
	croc_ex_checkStringParam(t, 1);
	auto name = croc_ex_optStringParam(t, 2, "<compiled from string>");

	croc_dup(t, 1);
	const char* modName;
	auto result = (dt ? croc_compiler_compileModuleDT : croc_compiler_compileModule)(t, name, &modName);

	if(result >= 0)
	{
		croc_pushString(t, modName);

		if(dt)
		{
			croc_moveToTop(t, -3);
			return 3;
		}
		else
			return 2;
	}

	_pushResultToString(t, result);
	return 2;
}
const StdlibRegisterInfo _compileModule_info =
{
	Docstr(DFunc("compileModule") DParam("source", "string") DParamD("filename", "string", "\"<compiled from string>\"")
	R"(Compiles a Croc module.

	\param[source] is the source code of the module.
	\param[filename] is the filename which will be used in compiler errors and debug locations.

	\returns different things depending on whether or not compilation was successful. If you don't care about handling
	compilation errors, see the \link{compileModuleEx} function instead.

	If compilation was successful, returns two values: the first is an uninstantiated \tt{funcdef} that represents the
	module's top-level function, and the second is a string containing the module's name as was given in its \tt{module}
	statement. You can use this to check whether the name matches the filename or whatever.

	If compilation failed, returns two values: the exception object (an \tt{instance}) which the compiler threw, and a
	string explaining what kind of error it was. These are the possible values for this string:

	\blist
		\li \tt{"unexpectedeof"} means that the compiler was expecting more code, but the source ended before it could
			finish parsing.
		\li \tt{"lonestatement"} means that the compiler encountered a statement which, on its own, could not possibly
			have a side effect and is therefore illegal.
		\li \tt{"danglingdoc"} means that the compiler found a documentation comment at the end of the source code which
			isn't attached to any declaration.
		\li \tt{"error"} means any other kind of compilation error.
	\endlist

	These "failure modes" are mostly useful for implementing interactive Croc interpreters. For example, an
	\tt{"unexpectedeof"} or \tt{"danglingdoc"} error might just mean that the user has to type another line to finish
	the code, whereas a \tt{"lonestatement"} error might mean that evaluating the code as an expression and displaying
	its result would be better.)"),

	"compileModule", 2
};

word_t _compileModule(CrocThread* t)
{
	return _compileModuleImpl(t, false);
}

word_t _compileStmtsImpl(CrocThread* t, bool dt)
{
	croc_ex_checkStringParam(t, 1);
	auto name = croc_ex_optStringParam(t, 2, "<compiled from string>");
	croc_dup(t, 1);
	auto result = (dt ? croc_compiler_compileStmtsDT : croc_compiler_compileStmts)(t, name);

	if(result >= 0)
	{
		if(dt)
			croc_swapTop(t);

		return dt ? 2 : 1;
	}

	_pushResultToString(t, result);
	return 2;
}

const StdlibRegisterInfo _compileStmts_info =
{
	Docstr(DFunc("compileStmts") DParam("source", "string") DParamD("filename", "string", "\"<compiled from string>\"")
	R"(Compiles a list of Croc statements. Almost identical to \link{compileModule} except there should be no
	\tt{module} statement at the beginning of the code.

	\param[source] is the source code.
	\param[filename] is the filename which will be used in compiler errors and debug locations.

	\returns different things depending on whether or not compilation was successful. If you don't care about handling
	compilation errors, see the \link{compileStmtsEx} function instead.

	If compilation was successful, returns an uninstantiated \tt{funcdef} that represents an anonymous function which
	contains the statements. It's just like a module's top-level function.

	If compilation failed, it returns the exact same things as \link{compileModule}.)"),

	"compileStmts", 2
};

word_t _compileStmts(CrocThread* t)
{
	return _compileStmtsImpl(t, false);
}

word_t _compileExprImpl(CrocThread* t)
{
	croc_ex_checkStringParam(t, 1);
	auto name = croc_ex_optStringParam(t, 2, "<compiled from string>");
	croc_dup(t, 1);
	auto result = croc_compiler_compileExpr(t, name);

	if(result >= 0)
		return 1;

	_pushResultToString(t, result);
	return 2;
}

const StdlibRegisterInfo _compileExpr_info =
{
	Docstr(DFunc("compileExpr") DParam("source", "string") DParamD("filename", "string", "\"<compiled from string>\"")
	R"(Compiles a single Croc expression into a function which takes variadic arguments and returns the result of
	evaluating that expression.

	For example, compiling the string \tt{"3 + vararg[0]"} as an expression will give you a function which is
	essentially \tt{\\vararg -> 3 + vararg[0]}.

	\param[source] is the string containing the expression. It must comprise a single expression; if there is any extra
		code after it, it is a compilation error.
	\param[filename] is the filename which will be used in compiler errors and debug locations.

	\returns different things depending on whether or not compilation was successful. If you don't care about handling
	compilation errors, see the \link{compileExprEx} function instead.

	If compilation was successful, returns an uninstantiated \tt{funcdef} that represents the function as described
	above.

	If compilation failed, it returns the exact same things as \link{compileModule}.)"),

	"compileExpr", 2
};

word_t _compileExpr(CrocThread* t)
{
	return _compileExprImpl(t);
}

const StdlibRegisterInfo _compileModuleDT_info =
{
	Docstr(DFunc("compileModuleDT") DParam("source", "string")
		DParamD("filename", "string", "\"<compiled from string>\"")
	R"(Works just like \link{compileModule} but additionally extracts the module's top-level documentation table as
	described in the spec.

	When you use this function, doc comments are parsed and turned into doctables, regardless of whether the compiler's
	\tt{"docs"} flag is enabled. The \tt{"docs"} compiler flag only controls whether or not runtime doc decorators are
	attached to program items.

	The parameters are the same as \link{compileModule}.

	\returns different things depending on whether or not compilation was successful. If you don't care about handling
	compilation errors, see the \link{compileModuleDTEx} function instead.

	If compilation was successful, it returns three values: the first two are the same as \link{compileModule}, and the
	third is the documentation table.

	If compilation failed, it returns the exact same things as \link{compileModule}.)"),

	"compileModuleDT", 2
};

word_t _compileModuleDT(CrocThread* t)
{
	return _compileModuleImpl(t, true);
}

const StdlibRegisterInfo _compileStmtsDT_info =
{
	Docstr(DFunc("compileStmtsDT") DParam("source", "string")
		DParamD("filename", "string", "\"<compiled from string>\"")
	R"(This is to \link{compileStmts} as \link{compileModuleDT} is to \link{compileModule}.

	\returns different things depending on whether or not compilation was successful. If you don't care about handling
	compilation errors, see the \link{compileStmtsDTEx} function instead.

	If compilation was successful, it returns two values: the first is the same as \link{compileStmts}, and the second
	is the documentation table.

	If compilation failed, it returns the exact same things as \link{compileStmts}.)"),

	"compileStmtsDT", 2
};

word_t _compileStmtsDT(CrocThread* t)
{
	return _compileStmtsImpl(t, true);
}

const StdlibRegisterInfo _compileModuleEx_info =
{
	Docstr(DFunc("compileModuleEx") DParam("source", "string")
		DParamD("filename", "string", "\"<compiled from string>\"")
	R"(Just like \link{compileModule}, except if compilation failed, it rethrows the exception, so this function only
	ever returns successfully.)"),

	"compileModuleEx", 2
};

word_t _compileModuleEx(CrocThread* t)
{
	_compileModuleImpl(t, false);

	if(!croc_isFuncdef(t, -2))
	{
		croc_popTop(t);
		croc_eh_throw(t);
	}

	return 2;
}

const StdlibRegisterInfo _compileStmtsEx_info =
{
	Docstr(DFunc("compileStmtsEx") DParam("source", "string")
		DParamD("filename", "string", "\"<compiled from string>\"")
	R"(Just like \link{compileStmts}, except if compilation failed, it rethrows the exception, so this function only
	ever returns successfully.)"),

	"compileStmtsEx", 2
};

word_t _compileStmtsEx(CrocThread* t)
{
	if(_compileStmtsImpl(t, false) == 2)
	{
		croc_popTop(t);
		croc_eh_throw(t);
	}

	return 1;
}

const StdlibRegisterInfo _compileExprEx_info =
{
	Docstr(DFunc("compileExprEx") DParam("source", "string")
		DParamD("filename", "string", "\"<compiled from string>\"")
	R"(Just like \link{compileExpr}, except if compilation failed, it rethrows the exception, so this function only
	ever returns successfully.)"),

	"compileExprEx", 2
};

word_t _compileExprEx(CrocThread* t)
{
	if(_compileExprImpl(t) == 2)
	{
		croc_popTop(t);
		croc_eh_throw(t);
	}

	return 1;
}

const StdlibRegisterInfo _compileModuleDTEx_info =
{
	Docstr(DFunc("compileModuleDTEx") DParam("source", "string")
		DParamD("filename", "string", "\"<compiled from string>\"")
	R"(Just like \link{compileModuleDT}, except if compilation failed, it rethrows the exception, so this function only
	ever returns successfully.)"),

	"compileModuleDTEx", 2
};

word_t _compileModuleDTEx(CrocThread* t)
{
	if(_compileModuleImpl(t, true) == 2)
	{
		croc_popTop(t);
		croc_eh_throw(t);
	}

	return 3;
}

const StdlibRegisterInfo _compileStmtsDTEx_info =
{
	Docstr(DFunc("compileStmtsDTEx") DParam("source", "string")
		DParamD("filename", "string", "\"<compiled from string>\"")
	R"(Just like \link{compileStmtsDT}, except if compilation failed, it rethrows the exception, so this function only
	ever returns successfully.)"),

	"compileStmtsDTEx", 2
};

word_t _compileStmtsDTEx(CrocThread* t)
{
	_compileStmtsImpl(t, true);

	if(!croc_isFuncdef(t, -2))
	{
		croc_popTop(t);
		croc_eh_throw(t);
	}

	return 2;
}

const StdlibRegisterInfo _runString_info =
{
	Docstr(DFunc("runString") DParam("source", "string") DParamD("filename", "string", "\"<compiled from string>\"")
		DParamD("env", "namespace", "null")
	R"(A little convenience function to run a string of code containing Croc statements.

	This basically compiles the statements, instantiates the funcdef using the \tt{env} namespace, calls the function,
	and returns all the values it does.

	Note that this code cannot access local variables from the function that called this! This is just how Croc works.

	\param[source] is the source code.
	\param[filename] is the filename which will be used in compiler errors and debug locations.
	\param[env] is the environment in which the statements should be executed. If you don't pass anything for this
		parameter, the statements will be evaluated in the environment of the function that called this.

	\returns any values that the compiled code returned after being executed.)"),

	"runString", 3
};

word_t _runString(CrocThread* t)
{
	auto haveEnv = croc_ex_optParam(t, 3, CrocType_Namespace);

	if(_compileStmtsImpl(t, false) == 2)
	{
		croc_popTop(t);
		croc_eh_throw(t);
	}

	if(haveEnv)
		croc_dup(t, 3);
	else
		croc_pushCurEnvironment(t);

	croc_function_newScriptWithEnv(t, -2);
	croc_pushNull(t);
	return croc_call(t, -2, -1);
}

const StdlibRegisterInfo _eval_info =
{
	Docstr(DFunc("eval") DParam("source", "string") DParamD("filename", "string", "\"<compiled from string>\"")
		DParamD("env", "namespace", "null")
	R"(Similar to \link{runString}, but evaluates a single expression instead of statements.

	This basically compiles the expression, instantiates the funcdef using the \tt{env} namespace, calls the function,
	and returns the value it does.

	Note that this code cannot access local variables from the function that called this! This is just how Croc works.

	\param[source] is the source code.
	\param[filename] is the filename which will be used in compiler errors and debug locations.
	\param[env] is the environment in which the expression should be executed. If you don't pass anything for this
		parameter, the expression will be evaluated in the environment of the function that called this.

	\returns the result of evaluating the expression.)"),

	"eval", 3
};

word_t _eval(CrocThread* t)
{
	auto haveEnv = croc_ex_optParam(t, 3, CrocType_Namespace);

	if(_compileExprImpl(t) == 2)
	{
		croc_popTop(t);
		croc_eh_throw(t);
	}

	if(haveEnv)
		croc_dup(t, 3);
	else
		croc_pushCurEnvironment(t);

	croc_function_newScriptWithEnv(t, -2);
	croc_pushNull(t);
	return croc_call(t, -2, -1);
}

const StdlibRegister _globalFuncs[] =
{
	_DListItem(_setFlags),
	_DListItem(_getFlags),
	_DListItem(_compileModule),
	_DListItem(_compileStmts),
	_DListItem(_compileExpr),
	_DListItem(_compileModuleDT),
	_DListItem(_compileStmtsDT),
	_DListItem(_compileModuleEx),
	_DListItem(_compileStmtsEx),
	_DListItem(_compileExprEx),
	_DListItem(_compileModuleDTEx),
	_DListItem(_compileStmtsDTEx),
	_DListItem(_runString),
	_DListItem(_eval),
	_DListEnd
};

word loader(CrocThread* t)
{
	registerGlobals(t, _globalFuncs);
	return 0;
}
}

void initCompilerLib(CrocThread* t)
{
	croc_ex_makeModule(t, "compiler", &loader);
	croc_ex_importNS(t, "compiler");
#ifdef CROC_BUILTIN_DOCS
	CrocDoc doc;
	croc_ex_doc_init(t, &doc, __FILE__);
	croc_ex_doc_push(&doc,
	DModule("compiler")
	R"(This module gives you access to the Croc compiler. Often you won't need to deal with the compiler directly as
	the module system takes care of loading most of your code, but if you need to dynamically compile something or
	write a new module system, this is the interface.)");
		docFields(&doc, _globalFuncs);
	croc_ex_doc_pop(&doc, -1);
	croc_ex_doc_finish(&doc);
#endif
	croc_popTop(t);
}
}