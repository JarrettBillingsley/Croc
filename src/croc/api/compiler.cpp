
#include "croc/api.h"
#include "croc/compiler/docparser.hpp"
#include "croc/compiler/types.hpp"
#include "croc/api/apichecks.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

using namespace croc;

extern "C"
{
	/** Enable and disable VM-wide compiler flags. These control whether or not code is generated for various optional
	language features.

	\param flags
	\parblock
	must be an or-ing together of the members of the \ref CrocCompilerFlags enum. The flags are as follows:

	- \ref CrocCompilerFlags_TypeConstraints enables code generation for parameter type constraints. If you leave out
		this flag, no parameter typechecking is done when calling functions.
	- \ref CrocCompilerFlags_Asserts enables code generation for \c assert() statements. If you leave out this flag,
		assert statements become no-ops.
	- \ref CrocCompilerFlags_Debug enables outputting debug info (which includes line numbers, local variable info, and
		upvalue names). If you leave out this flag, no debug info will be emitted, saving space at the cost of
		worse error messages/tracebacks. <b><em>This flag does not yet work properly.</em> Debug info is always on.</b>
	- \ref CrocCompilerFlags_Docs will cause the compiler to parse documentation comments and place doc decorators on
		the program items they document, meaning run-time accessible documentation will be available. If you leave
		out this flag, doc comments are ignored (unless you use one of the DT compilation functions below).
	- \ref CrocCompilerFlags_All enables all features except runtime docs. This is the default setting.
	- \ref CrocCompilerFlags_AllDocs enables all optional features.
	\endparblock

	\returns
	\parblock
	the previous value of the compiler flags. This is so you can set the flags, compile something, then put the flags
	back the way they were, like so:

	\code{.c}
	int oldFlags;

	oldFlags = croc_compiler_setFlags(t, CrocCompilerFlags_AllDocs);
	// compile some code here...
	croc_compiler_setFlags(t, oldFlags); // restore them
	\endcode
	\endparblock */
	uword_t croc_compiler_setFlags(CrocThread* t, uword_t flags)
	{
		auto reg = croc_vm_pushRegistry(t);
		croc_pushString(t, CompilerRegistryFlags);
		uword_t ret;

		if(croc_in(t, -1, reg))
		{
			croc_dupTop(t);
			croc_fieldStk(t, reg);
			ret = cast(uword)croc_getInt(t, -1);
			croc_popTop(t);
		}
		else
			ret = CrocCompilerFlags_All;

		croc_pushInt(t, flags);
		croc_fieldaStk(t, reg);
		croc_popTop(t);

		return ret;
	}

	/** \returns the current VM-wide compiler flags as described in \ref croc_compiler_setFlags. */
	uword_t croc_compiler_getFlags(CrocThread* t)
	{
		auto reg = croc_vm_pushRegistry(t);
		croc_pushString(t, CompilerRegistryFlags);
		uword_t ret;

		if(croc_in(t, -1, reg))
		{
			croc_fieldStk(t, reg);
			ret = cast(uword)croc_getInt(t, -1);
		}
		else
			ret = CrocCompilerFlags_All;

		croc_pop(t, 2);
		return ret;
	}

	namespace
	{
		int commonCompileModule(CrocThread* t_, const char* name, const char** modName, bool leaveDocTable)
		{
			auto t = Thread::from(t_);
			API_CHECK_NUM_PARAMS(1);
			API_CHECK_PARAM(src, -1, String, "source code");
			Compiler c(t);
			crocstr modNameStr;
			c.leaveDocTable(leaveDocTable);
			auto ret = c.compileModule(src->toDArray(), atoda(name), modNameStr);
			*modName = cast(const char*)modNameStr.ptr;
			croc_remove(t_, (ret >= 0 && leaveDocTable) ? -3 : -2);
			return (ret >= 0) ? ret - 1 : ret;
		}

		int commonCompileStmts(CrocThread* t_, const char* name, bool leaveDocTable)
		{
			auto t = Thread::from(t_);
			API_CHECK_NUM_PARAMS(1);
			API_CHECK_PARAM(src, -1, String, "source code");
			Compiler c(t);
			c.leaveDocTable(leaveDocTable);
			auto ret = c.compileStmts(src->toDArray(), atoda(name));
			croc_remove(t_, (ret >= 0 && leaveDocTable) ? -3 : -2);
			return (ret >= 0) ? ret - 1 : ret;
		}
	}

	/** Compiles the module whose source is a string on top of the stack. The top slot will be replaced with the result
	of compilation.

	\param name is the filename that will be used in locations such as compilation errors and debug info.
	\param[out] modName is required, and will be assigned a string which is the name of the module as given in the
		module's \c 'module' statement. You can use this to see if the module name matches the name it was imported as.
	\returns
	\parblock
	different things depending on whether compilation was successful or not.

	If it was successful, returns a positive stack slot of the resulting function definition, which will have replaced
	the source code on top of the stack.

	If it failed, returns one of the \ref CrocCompilerReturn values explaining why compilation failed. In this case, the
	source on top of the stack will be replaced with an exception object which you can then rethrow if you want to.

	If you don't care about handling compilation failure, use \ref croc_compiler_compileModuleEx instead.
	\endparblock */
	int croc_compiler_compileModule(CrocThread* t_, const char* name, const char** modName)
	{
		return commonCompileModule(t_, name, modName, false);
	}

	/** Very similar to \ref croc_compiler_compileModule, but the source will be parsed as a list of statements without
	a \c 'module' statement at the beginning. There is no \c modName parameter as a result.

	If you don't care about handling compilation failure, use \ref croc_compiler_compileStmtsEx instead. */
	int croc_compiler_compileStmts(CrocThread* t_, const char* name)
	{
		return commonCompileStmts(t_, name, false);
	}

	/** Similar to \ref croc_compiler_compileModule, but additionally extracts the module's top-level documentation
	table as described in the spec.

	When you use this function, doc comments are parsed and turned into doctables, regardless of whether the compiler's
	CrocCompilerFlags_Docs flag is enabled. The CrocCompilerFlags_Docs compiler flag only controls whether or not
	runtime doc decorators are attached to program items.

	\returns a positive number if compilation succeeded. In this case, there will be \a two items on top of the stack:
	the module's funcdef on top, and the doc table below it. In case of failure, there will only be one value, the
	exception object, just like \ref croc_compiler_compileModule.

	If you don't care about handling compilation failure, use \ref croc_compiler_compileModuleDTEx instead. */
	int croc_compiler_compileModuleDT(CrocThread* t_, const char* name, const char** modName)
	{
		return commonCompileModule(t_, name, modName, true);
	}

	/** Just like \ref croc_compiler_compileStmts, but extracts the top-level documentation table like \ref
	croc_compiler_compileModuleDT, leaving it on the stack under the funcdef the same way.

	If you don't care about handling compilation failure, use \ref croc_compiler_compileStmtsDTEx instead. */
	int croc_compiler_compileStmtsDT(CrocThread* t_, const char* name)
	{
		return commonCompileStmts(t_, name, true);
	}

	/** Compiles a single Croc expression as a string on top of the stack into a funcdef which takes variadic arguments
	and returns the result of evaluating that expression. Just like with the other compilation functions, the source
	stack slot is replaced by either the funcdef on success or the exception object on failure.

	If you don't care about handling compilation failure, use \ref croc_compiler_compileExprEx instead. */
	int croc_compiler_compileExpr(CrocThread* t_, const char* name)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(src, -1, String, "source code");
		Compiler c(t);
		auto ret = c.compileExpr(src->toDArray(), atoda(name));
		croc_insertAndPop(t_, -2);
		return (ret >= 0) ? ret - 1 : ret;
	}

	/** This is a low-level interface to the documentation comment parser. It expects two values on top of the stack:
	the doc comment text as a string on top, and a doctable below it which only has the members \c "file", \c "line",
	\c "kind", and \c "name" filled in. It will parse the doc comment, filling in the other fields of the doctable. The
	comment source will then be popped, leaving just the doctable on top of the stack.

	\returns the stack index of the doctable. */
	word_t croc_compiler_processDocComment(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(2);
		API_CHECK_PARAM(src, -1, String, "comment source");
		API_CHECK_PARAM(_, -2, Table, "doctable");
		(void)_;
		croc_swapTop(t_);
		processComment(t_, src->toDArray());
		croc_remove(t_, -2);
		return croc_getStackSize(t_) - 1;
	}

	/** Expects a string on top of the stack which will be parsed into a doc comment paragraph list. This doesn't
	actually parse a whole doc comment like \ref croc_compiler_processDocComment does, so section commands are not
	allowed, but span and structure commands are.

	The source slot will be replaced by the resulting paragraph list (an array as described in the doc comment spec).

	\returns the stack index of the result. */
	word_t croc_compiler_parseDocCommentText(CrocThread* t_)
	{
		auto t = Thread::from(t_);
		API_CHECK_NUM_PARAMS(1);
		API_CHECK_PARAM(src, -1, String, "comment source");
		parseCommentText(t_, src->toDArray());
		croc_remove(t_, -2);
		return croc_getStackSize(t_) - 1;
	}
}