
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{
// =====================================================================================================================
// Standard exceptions
struct ExDesc
{
	const char* name;
	const char* docs;
} _exDescs[] =
{
	{"LexicalException", Docstr(DClass("LexicalException")
		R"(Thrown for lexical errors in source code. The \tt{location} field is the source location that caused the
		exception to be thrown.)")
	},
	{"SyntaxException", Docstr(DClass("SyntaxException")
		R"(Thrown for syntactic errors in source code. The \tt{location} field is the source location that caused the
		exception to be thrown.)")
	},
	{"SemanticException", Docstr(DClass("SemanticException")
		R"(Thrown for semantic errors in source code. The \tt{location} field is the source location that caused the
		exception to be thrown.)")
	},
	{"ImportException", Docstr(DClass("ImportException")
		R"(Thrown when an import fails; may also have a 'cause' exception in case the import failed because of an
		exception being thrown from the module's top-level function.)")
	},
	{"OSException", Docstr(DClass("OSException")
		R"(OS error APIs are often a poor match for the way Croc does error handling, but unhandled OS errors can lead
		to bad things happening. Therefore Croc libraries are encouraged to translate OS errors into OSExceptions so
		that code won't blindly march on past errors, but they can still be caught and handled appropriately.)")
	},
	{"IOException", Docstr(DClass("IOException")
		R"(Thrown when an IO operation fails or is given invalid inputs. The rationale for this exception type is the
		same as that of \link{OSException}.)")
	},
	{"HaltException", Docstr(DClass("HaltException")
		R"(Thrown when a thread is halted. You \em{can} catch this kind of exception, but in practice you really
		\em{shouldn't} unless you're doing something like writing a CLI.

		This exception type is special in that it never propagates out of the thread that was halted. Instead when this
		exception escapes the thread that was halted, the thread is simply marked as dead and execution resumes in the
		resuming thread as normal.)")
	},
	{"AssertError", Docstr(DClass("AssertError")
		R"(Thrown when an assertion fails.)")
	},
	{"ApiError", Docstr(DClass("ApiError")
		R"(Thrown when the native API is given certain kinds of invalid input, generally inputs which mean the host is
		malfunctioning or incorrectly programmed.)")
	},
	{"ParamError", Docstr(DClass("ParamError")
		R"(Thrown for function calls which are invalid because they were given an improper number of parameters. However
		if a function is given parameters of incorrect type, a \link{TypeError} is thrown instead.)")
	},
	{"FinalizerError", Docstr(DClass("FinalizerError")
		R"(Thrown when an exception is thrown by a class finalizer. This is a big problem as finalizers should never
		fail. The exception that the finalizer threw is set as the 'cause'.)")
	},
	{"NameError", Docstr(DClass("NameError")
		R"(Thrown on invalid global access (either the name doesn't exist or trying to redefine an existing global).
		Also thrown on invalid local names when using the debug library.)")
	},
	{"BoundsError", Docstr(DClass("BoundsError")
		R"(Thrown when trying to access an array-like object out of bounds. You could also use this for other kinds of
		containers.)")
	},
	{"FieldError", Docstr(DClass("FieldError")
		R"(Thrown when trying to access an invalid field from a namespace, class, instance etc., unless it's global
		access, in which case a \link{NameError} is thrown.)")
	},
	{"MethodError", Docstr(DClass("MethodError")
		R"(Thrown when trying to call an invalid method on an object.)")
	},
	{"LookupError", Docstr(DClass("LookupError")
		R"(Thrown when any general kind of lookup has failed. Use one of the more specific types (like
		\link{BoundsError} or \link{NameError} if you can.)")
	},
	{"RuntimeError", Docstr(DClass("RuntimeError")
		R"(Kind of a catchall type for other random runtime errors. Other exceptions will probably grow out of this
		one.)")
	},
	{"NotImplementedError", Docstr(DClass("NotImplementedError")
		R"(An exception type that you can throw in methods that are unimplemented (such as in abstract base class
		methods). This way when an un-overridden method is called, you get an error instead of it silently working.)")
	},
	{"SwitchError", Docstr(DClass("SwitchError")
		R"(Thrown when a switch without a 'default' is given a value not listed in its cases.)")
	},
	{"TypeError", Docstr(DClass("TypeError")
		R"(Thrown when an incorrect type is given to an operation (i.e. trying to add strings, or when invalid types are
		given to function parameters).)")
	},
	{"ValueError", Docstr(DClass("ValueError")
		R"(Generally speaking, indicates that an operation was given a value of the proper type, but the value is
		invalid somehow - not an acceptable value, or incorrectly formed, or in an invalid state. If possible, try to
		use one of the more specific classes like \link{RangeError}, or derive your own.)")
	},
	{"RangeError", Docstr(DClass("RangeError")
		R"(Thrown to indicate that a value is out of a valid range of acceptable values. Typically used for mathematical
		functions, i.e. square root only works on non-negative values. Note that if the error is because a value is out
		of the range of valid indices for a container, you should use a \link{BoundsError} instead.)")
	},
	{"StateError", Docstr(DClass("StateError")
		R"(Thrown to indicate that an object is in an invalid state.)")
	},
	{"UnicodeError", Docstr(DClass("UnicodeError")
		R"(Thrown when Croc is given malformed/invalid Unicode data for a string, or when invalid Unicode data is
		encountered during transcoding.)")
	},
	{"VMError", Docstr(DClass("VMError")
		R"(Thrown for some kinds of internal VM errors.)")
	},

	{nullptr, nullptr}
};

void registerStdEx(CrocThread* t, Thread* t_)
{
	auto _G = croc_vm_pushGlobals(t);
	auto Throwable = croc_pushGlobal(t, "Throwable");

	for(auto d = _exDescs; d->name != nullptr; d++)
	{
		croc_dup(t, Throwable);
		croc_class_new(t, d->name, 1);
		*t_->vm->stdExceptions.insert(t_->vm->mem, String::create(t_->vm, atoda(d->name))) = getClass(t_, -1);
		croc_dupTop(t);
		croc_fielda(t, _G, d->name);
		croc_newGlobal(t, d->name);
	}

	croc_fielda(t, _G, "Throwable");
	croc_popTop(t);
}

#ifdef CROC_BUILTIN_DOCS
void docStdEx(CrocThread* t, CrocDoc* doc)
{
	for(auto d = _exDescs; d->name != nullptr; d++)
	{
		croc_field(t, -1, d->name);
		croc_ex_doc_push(doc, d->docs);
		croc_ex_doc_pop(doc, -1);
		croc_popTop(t);
	}
}
#endif

// =====================================================================================================================
// Location

const crocint Unknown = 0;
const crocint Native = -1;
const crocint Script = -2;

#ifdef CROC_BUILTIN_DOCS
const char* _Location_docs =
	DClass("Location")
	R"(This class holds a source location, which is used in exception tracebacks and compilation errors.

	There two kinds of locations: compile-time and runtime. Compile-time locations have a column number > 0 and indicate
	the exact location within a source file where something went wrong. Runtime locations have a column number <= 0, in
	which case the exact kind of location is encoded in the column number as one of \link{Location.Unknown},
	\link{Location.Native}, or \link{Location.Script}.)";

const char* _Location_fieldDocs[] =
{
	DField("Unknown")
	R"(This is one of the types of locations that can be put in the \tt{col} field. It means that there isn't enough
	information to determine a location for where an error occurred. In this case the file and line will also probably
	meaningless.)",

	DField("Native")
	R"(This is another type of location that can be put in the \tt{col} field. It means that the location is within a
	native function, so there isn't enough information to give a line, but at least the file can be determined.)",

	DField("Script")
	R"(This is the last type of location that can be put in the \tt{col} field. It means that the location is within
	script code, the file and (usually) the line can be determined. The column can never be determined at runtime,
	however.)",

	DFieldV("file", "\"\"")
	R"(This is a string containing the module and function where the error occurred, in the format "module.name.func".
	If \tt{col} is \link{Location.Unknown}, this field will be the empty string.)",

	DFieldV("line", "0")
	R"(This is the line on which the error occurred. If the location type is \link{Location.Script}, this field can be
	-1, which means that no line number could be determined.)",

	DFieldV("col", "Location.Unknown")
	R"(This field serves double duty as either a column number for compilation errors or as a location "type".

	If this field is > 0, it is a compilation error and represents the column where the error occurred. Otherwise, this
	field will be one of the three constants above (which are all <= 0).)",

	nullptr
};
#endif

const StdlibRegisterInfo _Location_constructor_info =
{
	Docstr(DFunc("constructor") DParamD("file", "string", "null") DParamD("line", "int", "-1")
		DParamD("col", "int", "Location.Script")
	R"(Constructor. All parameters are optional. When passed \tt{null} for \tt{file}, the \tt{line} and \tt{col}
	parameters are ignored, constructing an "Unknown" location.)"),

	"constructor", 3
};

word_t _Location_constructor(CrocThread* t)
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

const StdlibRegisterInfo _Location_toString_info =
{
	Docstr(DFunc("toString")
	R"x(Gives a string representation of the location, in the following formats:
	\blist
		\li Unknown - \tt{"<unknown location>"}
		\li Native - \tt{"file(native)"}
		\li Script - \tt{"file(line)"} (if \tt{line < 1} then the line will be '?' instead)
		\li otherwise - \tt{"file(line:col)"}
	\endlist)x"),

	"toString", 0
};

word_t _Location_toString(CrocThread* t)
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

			if(croc_getInt(t, -1) < 0)
				croc_pushString(t, "?");
			else
				croc_pushToStringRaw(t, -1);

			croc_insertAndPop(t, -2);

			croc_pushString(t, ")");
			croc_cat(t, croc_getStackSize(t) - first);
			break;
		}
	}

	return 1;
}

const StdlibRegister _Location_methods[] =
{
	_DListItem(_Location_constructor),
	_DListItem(_Location_toString),
	_DListEnd
};

void initLocationClass(CrocThread* t, Thread* t_)
{
	croc_class_new(t, "Location", 0);
		// add these as methods so they don't get unnecessarily duplicated into every instance
		croc_pushInt(t, Unknown); croc_class_addMethod(t, -2, "Unknown");
		croc_pushInt(t, Native);  croc_class_addMethod(t, -2, "Native");
		croc_pushInt(t, Script);  croc_class_addMethod(t, -2, "Script");

		croc_pushString(t, "");   croc_class_addField(t, -2, "file");
		croc_pushInt(t, 0);       croc_class_addField(t, -2, "line");
		croc_pushInt(t, Unknown); croc_class_addField(t, -2, "col");

		registerMethods(t, _Location_methods);

		t_->vm->location = getClass(t_, -1);
	croc_newGlobal(t, "Location");
}

#ifdef CROC_BUILTIN_DOCS
void docLocationClass(CrocThread* t, CrocDoc* doc)
{
	croc_field(t, -1, "Location");
	croc_ex_doc_push(doc, _Location_docs);
	croc_ex_docFields(doc, _Location_fieldDocs);
	docFields(doc, _Location_methods);
	croc_ex_doc_pop(doc, -1);
	croc_popTop(t);
}
#endif

// =====================================================================================================================
// Throwable

#ifdef CROC_BUILTIN_DOCS
const char* _Throwable_docs =
	DClass("Throwable")
	R"(This class defines the interface that the VM expects throwable exception types to have, along with some useful
	methods. You can throw instances of any class type in Croc, but you can save a lot of time writing your own
	exception classes by just deriving from this class.

	This class is also exported into the global namespace, so you can access it without having to import it from this
	module.)";

const char* _Throwable_fieldDocs[] =
{
	DFieldV("location", "Location()")
	R"(The location where this exception was thrown. See the \link{exceptions.Location} class documentation for more
	info. Defaults to an unknown location.)",

	DFieldV("msg", "\"\"")
	R"(The human-readable message associated with the exception. Defaults to the empty string.)",

	DFieldV("cause", "null")
	R"(An optional field. Sometimes an exception can cause a cascade of other exceptions; for instance, an exception
	thrown while importing a module will cause the module import to fail and throw an exception of its own. In these
	cases, the \tt{cause} field is used to hold the exception that caused this exception to be thrown. There can be
	arbitrarily many exceptions nested in this linked list of causes. It is up to the user, however, to provide the
	\tt{cause} exception when throwing a second exception; there is no built-in mechanism to ensure that this field is
	filled in. You can use the \link{setCause} function for this purpose.

	The default value is null, which means this exception had no cause.)",

	DFieldV("traceback", "[]")
	R"(This is an array of Location instances that shows the call stack as it was when the exception was thrown,
	allowing you to pinpoint the exact codepath that caused the error. This array starts at the location where the
	exception was thrown; that is, element 0 is the same as the \tt{location} field. After that, it gives the function
	that called the function where the exception was thrown and goes up the call stack. Tailcalls are represented as
	script locations. You can get a string representation of this traceback with the \tt{tracebackString} method. This
	field defaults to an empty array.)",

	nullptr
};
#endif

const StdlibRegisterInfo _Throwable_constructor_info =
{
	Docstr(DFunc("constructor") DParamD("msg", "string", "\"\"") DParamD("cause", "Throwable", "null")
	R"(Constructor. All parameters are optional.

	\param[msg] A descriptive message of the exception being thrown. This is meant to be human-readable, and is not used
		by the EH mechanism in any way. Defaults to the empty string.
	\param[cause] The exception that caused this exception to be thrown. Defaults to none (null).)"),

	"constructor", 2
};

word_t _Throwable_constructor(CrocThread* t)
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

const StdlibRegisterInfo _Throwable_toString_info =
{
	Docstr(DFunc("toString")
	R"(Gives a string representation of the exception. It is in the format \tt{"<exception type> at <location>: <msg>"}.

	If the message is the empty string, there will be no colon after the location. If \tt{cause} is non-null, this will
	be followed by a newline, \tt{"Caused by:"}, another newline, and the string representation of \tt{cause}. This will
	continue recursively, meaning there may be several layers of causes in one representation.)"),

	"toString", 0
};

word_t _Throwable_toString(CrocThread* t)
{
	auto first = croc_superOf(t, 0);
	croc_pushString(t, croc_getNameOf(t, first));
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

const StdlibRegisterInfo _Throwable_setLocation_info =
{
	Docstr(DFunc("setLocation") DParam("loc", "Location")
	R"(Acts as a setter for the \tt{location} field. This is occasionally useful when programmatically building
	exception objects such as in the compiler.)"),

	"setLocation", 1
};

word_t _Throwable_setLocation(CrocThread* t)
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

const StdlibRegisterInfo _Throwable_setCause_info =
{
	Docstr(DFunc("setCause") DParam("cause", "instance")
	R"x(Acts as a setter for the \tt{cause} field. This can be useful when throwing an exception that is caused by
	another exception. Rather than forcing an exception constructor to take the cause as a parameter, you can simply use
	\tt{"throw SomeException().setCause(ex)"} instead.)x"),

	"setCause", 1
};

word_t _Throwable_setCause(CrocThread* t)
{
	croc_ex_checkParam(t, 1, CrocType_Instance);
	croc_dup(t, 1);
	croc_fielda(t, 0, "cause");
	croc_dup(t, 0);
	return 1;
}

const StdlibRegisterInfo _Throwable_tracebackString_info =
{
	Docstr(DFunc("tracebackString")
	R"(Gets a string representation of the \tt{traceback} field. The first entry is preceded by "Traceback: ". Each
	subsequent entry is preceded by a newline, some whitespace, and "at: ".)"),

	"tracebackString", 0
};

word_t _Throwable_tracebackString(CrocThread* t)
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

const StdlibRegister _Throwable_methods[] =
{
	_DListItem(_Throwable_constructor),
	_DListItem(_Throwable_toString),
	_DListItem(_Throwable_setLocation),
	_DListItem(_Throwable_setCause),
	_DListItem(_Throwable_tracebackString),
	_DListEnd
};

void initThrowableClass(CrocThread* t, Thread* t_)
{
	croc_class_new(t, "Throwable", 0);
		croc_pushGlobal(t, "Location");
		croc_pushNull(t);
		croc_call(t, -2, 1);
		croc_class_addField(t, -2, "location");

		croc_pushString(t, ""); croc_class_addField(t, -2, "msg");
		croc_pushNull(t);       croc_class_addField(t, -2, "cause");
		croc_array_new(t, 0);   croc_class_addField(t, -2, "traceback");

		registerMethods(t, _Throwable_methods);

		*t_->vm->stdExceptions.insert(t_->vm->mem, String::create(t_->vm, ATODA("Throwable"))) = getClass(t_, -1);
	croc_newGlobal(t, "Throwable");
}

#ifdef CROC_BUILTIN_DOCS
void docThrowableClass(CrocThread* t, CrocDoc* doc)
{
	croc_field(t, -1, "Throwable");
	croc_ex_doc_push(doc, _Throwable_docs);
	croc_ex_docFields(doc, _Throwable_fieldDocs);
	docFields(doc, _Throwable_methods);
	croc_ex_doc_pop(doc, -1);
	croc_popTop(t);
}
#endif

// =====================================================================================================================
// Globals

const StdlibRegisterInfo _stdException_info =
{
	Docstr(DFunc("stdException") DParam("name", "string")
	R"(Gets one of the standard exception types by name.

	\returns one of the standard exception classes.
	\throws[NameError] if the given name does not name a standard exception type.)"),

	"stdException", 1
};

word_t _stdException(CrocThread* t)
{
	croc_eh_pushStd(t, croc_ex_checkStringParam(t, 1));
	return 1;
}

const StdlibRegisterInfo _rethrow_info =
{
	Docstr(DFunc("rethrow") DParam("ex", "instance")
	R"(Rethrows the exception \tt{ex}. This is the same as throwing it normally, except the traceback is not
	modified.)"),

	"rethrow", 1
};

word_t _rethrow(CrocThread* t)
{
	croc_ex_checkParam(t, 1, CrocType_Instance);
	croc_dup(t, 1);
	return croc_eh_rethrow(t);
}

const StdlibRegister _globalFuncs[] =
{
	_DListItem(_stdException),
	_DListItem(_rethrow),
	_DListEnd
};

// =====================================================================================================================
// Loader

word loader(CrocThread* t)
{
	auto t_ = Thread::from(t);
	initLocationClass(t, t_);
	initThrowableClass(t, t_);
	registerGlobals(t, _globalFuncs);
	registerStdEx(t, t_);
	return 0;
}
}

void initExceptionsLib(CrocThread* t)
{
	croc_ex_makeModule(t, "exceptions", &loader);
	croc_ex_import(t, "exceptions");
}

#ifdef CROC_BUILTIN_DOCS
void docExceptionsLib(CrocThread* t)
{
	CrocDoc doc;
	croc_ex_doc_init(t, &doc, __FILE__);
	croc_ex_doc_push(&doc,
	DModule("exceptions")
	R"x(This library defines the standard exception types. These types are used by the standard libraries and by the
	VM itself. You are encouraged to use these types as well in your own code, though there is no requirement to do
	so.

	Exception types ending in "Exception" are for generally "non-fatal" exceptions, and those ending in "Error" are
	for generally fatal errors which mean consistency has failed and the program needs to be fixed.

	All the standard exception types are also exported into the global namespace, so they can be accessed
	without having to import them from this module.)x");
	croc_pushGlobal(t, "exceptions");
	docLocationClass(t, &doc);
	docThrowableClass(t, &doc);
	docFields(&doc, _globalFuncs);
	docStdEx(t, &doc);
	croc_ex_doc_pop(&doc, -1);
	croc_popTop(t);
	croc_ex_doc_finish(&doc);
}
#endif
}