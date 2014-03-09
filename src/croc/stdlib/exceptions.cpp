
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
#define EXDESC_LIST(X)\
	X("LexicalException", "Thrown for lexical errors in source code. The \\tt{location} field is the source location "\
		"that caused the exception to be thrown.")\
	X("SyntaxException", "Thrown for syntactic errors in source code. The \\tt{location} field is the source location "\
		"that caused the exception to be thrown.")\
	X("SemanticException", "Thrown for semantic errors in source code. The \\tt{location} field is the source "\
		"location that caused the exception to be thrown.")\
	X("ImportException", "Thrown when an import fails; may also have a 'cause' exception in case the import failed "\
		"because of an exception being thrown from the module's top-level function.")\
	X("OSException", "OS error APIs are often a poor match for the way Croc does error handling, but unhandled OS "\
		"errors can lead to bad things happening. Therefore Croc libraries are encouraged to translate OS errors into "\
		"OSExceptions so that code won't blindly march on past errors, but they can still be caught and handled "\
		"appropriately.")\
	X("IOException", "Thrown when an IO operation fails or is given invalid inputs. The rationale for this exception "\
		"type is the same as that of \\link{OSException}.")\
	X("AssertError", "Thrown when an assertion fails.")\
	X("ApiError", "Thrown when the native API is given certain kinds of invalid input, generally inputs which mean "\
		"the host is malfunctioning or incorrectly programmed.")\
	X("ParamError", "Thrown for function calls which are invalid because they were given an improper number of "\
		"parameters. However if a function is given parameters of incorrect type, a \\link{TypeError} is thrown "\
		"instead.")\
	X("FinalizerError", "Thrown when an exception is thrown by a class finalizer. This is a big problem as "\
		"finalizers should never fail. The exception that the finalizer threw is set as the 'cause'.")\
	X("NameError", "Thrown on invalid global access (either the name doesn't exist or trying to redefine an existing "\
		"global). Also thrown on invalid local names when using the debug library.")\
	X("BoundsError", "Thrown when trying to access an array-like object out of bounds. You could also use this for "\
		"other kinds of containers.")\
	X("FieldError", "Thrown when trying to access an invalid field from a namespace, class, instance etc., unless "\
		"it's global access, in which case a \\link{NameError} is thrown.")\
	X("MethodError", "Thrown when trying to call an invalid method on an object.")\
	X("LookupError", "Thrown when any general kind of lookup has failed. Use one of the more specific types (like "\
		"\\link{BoundsError} or \\link{NameError} if you can.")\
	X("RuntimeError", "Kind of a catchall type for other random runtime errors. Other exceptions will probably grow "\
		"out of this one.")\
	X("NotImplementedError", "An exception type that you can throw in methods that are unimplemented (such as in "\
		"abstract base class methods). This way when an un-overridden method is called, you get an error instead of "\
		"it silently working.")\
	X("SwitchError", "Thrown when a switch without a 'default' is given a value not listed in its cases.")\
	X("TypeError", "Thrown when an incorrect type is given to an operation (i.e. trying to add strings, or when "\
		"invalid types are given to function parameters).")\
	X("ValueError", "Generally speaking, indicates that an operation was given a value of the proper type, but the "\
		"value is invalid somehow - not an acceptable value, or incorrectly formed, or in an invalid state. If "\
		"possible, try to use one of the more specific classes like \\link{RangeError}, or derive your own.")\
	X("RangeError", "Thrown to indicate that a value is out of a valid range of acceptable values. Typically used "\
		"for mathematical functions, i.e. square root only works on non-negative values. Note that if the error is "\
		"because a value is out of the range of valid indices for a container, you should use a \\link{BoundsError} "\
		"instead.")\
	X("StateError", "Thrown to indicate that an object is in an invalid state.")\
	X("UnicodeError", "Thrown when Croc is given malformed/invalid Unicode data for a string, or when invalid "\
		"Unicode data is encountered during transcoding.")\
	X("VMError", "Thrown for some kinds of internal VM errors.")

	const crocint Unknown = 0;
	const crocint Native = -1;
	const crocint Script = -2;

	word _locationConstructor(CrocThread* t)
	{
		auto file = croc_ex_optStringParam(t, 1, nullptr);

		if(file == nullptr)
			return 0;

		auto line = croc_ex_optIntParam(t, 2, -1);
		auto col = croc_ex_optIntParam(t, 3, Script);

		croc_pushString(t, file); croc_fielda(t, 0, "file");
		croc_pushInt(t, line);    croc_fielda(t, 0, "line");
		croc_pushInt(t, col);     croc_fielda(t, 0, "col");
		return 0;
	}

	word _locationToString(CrocThread* t)
	{
		croc_field(t, 0, "col");

		switch(croc_getInt(t, -1))
		{
			case Unknown: {
				croc_pushString(t, "<unknown location>");
				break;
			}
			case Native: {
				croc_field(t, 0, "file");
				croc_pushString(t, "(native)");
				croc_cat(t, 2);
				break;
			}
			case Script: {
				auto first = croc_field(t, 0, "file");
				croc_pushString(t, "(");

				croc_field(t, 0, "line");

				if(croc_getInt(t, -1) < 1)
					croc_pushString(t, "?");
				else
					croc_pushToStringRaw(t, -1);

				croc_insertAndPop(t, -2);

				croc_pushString(t, ")");
				croc_cat(t, croc_getStackSize(t) - first);
				break;
			}
			default: {
				auto first = croc_field(t, 0, "file");
				croc_pushString(t, "(");

				croc_field(t, 0, "line");

				if(croc_getInt(t, -1) < 1)
					croc_pushString(t, "?");
				else
					croc_pushToStringRaw(t, -1);

				croc_insertAndPop(t, -2);

				croc_pushString(t, ":");

				croc_field(t, 0, "col");
				croc_pushToStringRaw(t, -1);
				croc_insertAndPop(t, -2);

				croc_pushString(t, ")");
				croc_cat(t, croc_getStackSize(t) - first);
				break;
			}
		}

		return 1;
	}

	word _throwableConstructor(CrocThread* t)
	{
		auto msg = croc_ex_optStringParam(t, 1, "");

		if(croc_isValidIndex(t, 2))
			croc_dup(t, 2);
		else
			croc_pushNull(t);

		croc_fielda(t, 0, "cause");

		croc_pushString(t, msg);
		croc_fielda(t, 0, "msg");
		return 0;
	}

	word _throwableToString(CrocThread* t)
	{
		auto first = croc_superOf(t, 0);
		croc_pushString(t, croc_class_getName(t, first));
		croc_insertAndPop(t, first);
		croc_pushString(t, " at ");
		croc_field(t, 0, "location");
		croc_pushNull(t);
		croc_methodCall(t, -2, "toString", 1);

		croc_field(t, 0, "msg");

		if(croc_len(t, -1) > 0)
		{
			croc_pushString(t, ": ");
			croc_insert(t, -2);
		}
		else
			croc_popTop(t);

		first = croc_cat(t, croc_getStackSize(t) - first);

		croc_field(t, 0, "cause");

		if(croc_isNull(t, -1))
			croc_popTop(t);
		else
		{
			croc_pushString(t, "\nCaused by:\n");
			croc_insert(t, -2);
			croc_pushNull(t);
			croc_methodCall(t, -2, "toString", 1);
			croc_cat(t, croc_getStackSize(t) - first);
		}

		return 1;
	}

	word _throwableSetLocation(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Instance);

		croc_eh_pushLocationClass(t);
		if(!croc_isInstanceOf(t, 1, -1))
			croc_ex_paramTypeError(t, 1, "instance of Location");
		croc_popTop(t);

		croc_dup(t, 1);
		croc_fielda(t, 0, "location");
		croc_dup(t, 0);
		return 1;
	}

	word _throwableSetCause(CrocThread* t)
	{
		croc_ex_checkParam(t, 1, CrocType_Instance);
		croc_dup(t, 1);
		croc_fielda(t, 0, "cause");
		croc_dup(t, 0);
		return 1;
	}

	word _throwableTracebackString(CrocThread* t)
	{
		auto traceback = croc_field(t, 0, "traceback");
		auto tblen = croc_len(t, traceback);

		if(tblen == 0)
		{
			croc_pushString(t, "");
			return 1;
		}

		CrocStrBuffer s;
		croc_ex_buffer_init(t, &s);
		croc_ex_buffer_addString(&s, "Traceback: ");

		croc_idxi(t, traceback, 0);
		croc_pushNull(t);
		croc_methodCall(t, -2, "toString", 1);
		croc_ex_buffer_addTop(&s);

		for(crocint i = 1; i < tblen; i++)
		{
			croc_ex_buffer_addString(&s, "\n       at: ");
			croc_idxi(t, traceback, i);
			croc_pushNull(t);
			croc_methodCall(t, -2, "toString", 1);
			croc_ex_buffer_addTop(&s);
		}

		croc_ex_buffer_finish(&s);
		return 1;
	}

	word _stdException(CrocThread* t)
	{
		croc_eh_pushStd(t, croc_ex_checkStringParam(t, 1));
		return 1;
	}

	const CrocRegisterFunc _locationMethods[] =
	{
		{"constructor", 3, &_locationConstructor},
		{"toString",    0, &_locationToString   },
		{nullptr, 0, nullptr}
	};

	const CrocRegisterFunc _throwableMethods[] =
	{
		{"constructor",     2, &_throwableConstructor    },
		{"toString",        0, &_throwableToString       },
		{"setLocation",     1, &_throwableSetLocation    },
		{"setCause",        1, &_throwableSetCause       },
		{"tracebackString", 0, &_throwableTracebackString},
		{nullptr, 0, nullptr}
	};

	const CrocRegisterFunc _globalFuncs[] =
	{
		{"stdException", 1, &_stdException},
		{nullptr, 0, nullptr}
	};

	word loader(CrocThread* t)
	{
		auto t_ = Thread::from(t);

		croc_class_new(t, "Location", 0);
			croc_pushInt(t, Unknown); croc_class_addMethod(t, -2, "Unknown");
			croc_pushInt(t, Native);  croc_class_addMethod(t, -2, "Native");
			croc_pushInt(t, Script);  croc_class_addMethod(t, -2, "Script");

			croc_pushString(t, "");   croc_class_addField(t, -2, "file");
			croc_pushInt(t, 0);       croc_class_addField(t, -2, "line");
			croc_pushInt(t, Unknown); croc_class_addField(t, -2, "col");

			croc_ex_registerMethods(t, _locationMethods);

			t_->vm->location = getClass(t_, -1);
		croc_newGlobal(t, "Location");

		croc_class_new(t, "Throwable", 0);
			croc_pushGlobal(t, "Location");
			croc_pushNull(t);
			croc_call(t, -2, 1);
			croc_class_addField(t, -2, "location");

			croc_pushString(t, ""); croc_class_addField(t, -2, "msg");
			croc_pushNull(t);       croc_class_addField(t, -2, "cause");
			croc_array_new(t, 0);   croc_class_addField(t, -2, "traceback");

			croc_ex_registerMethods(t, _throwableMethods);

			*t_->vm->stdExceptions.insert(t_->vm->mem, String::create(t_->vm, ATODA("Throwable"))) = getClass(t_, -1);
		croc_newGlobal(t, "Throwable");

#define POOP(NAME, _)\
	croc_pushGlobal(t, "Throwable");\
	croc_class_new(t, NAME, 1);\
	*t_->vm->stdExceptions.insert(t_->vm->mem, String::create(t_->vm, atoda(NAME))) = getClass(t_, -1);\
	croc_newGlobal(t, NAME);

		EXDESC_LIST(POOP);
#undef POOP

		croc_pushGlobal(t, "_G");

#define POOP(NAME, _)\
	croc_pushGlobal(t, NAME);\
	croc_fielda(t, -2, NAME);

			EXDESC_LIST(POOP);
#undef POOP

			croc_pushGlobal(t, "Throwable");
			croc_fielda(t, -2, "Throwable");
		croc_popTop(t);

		croc_ex_registerGlobals(t, _globalFuncs);

		return 0;
	}
	}

	void initExceptionsLib(CrocThread* t)
	{
		croc_ex_makeModule(t, "exceptions", &loader);
		croc_ex_import(t, "exceptions");
	}
}