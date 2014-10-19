
#include <string.h>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/json.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{
const StdlibRegisterInfo _fromJSON_info =
{
	Docstr(DFunc("fromJSON") DParam("j", "string")
	R"(Parses the JSON \tt{j} into a Croc representation using null, bool, int, float, string, table, and array.

	The string must contain well-formed JSON, and the root object must be a JSON object or array. There must be no extra
	data after the root object either.

	This parser is strictly conforming; all object keys must be quoted and there can be no spurious commas. Sadly.

	\returns the root object.

	\throws[LexicalException] if there are lexical errors in \tt{j}.
	\throws[SyntaxException] if there are syntactic errors in \tt{j}.)"),

	"fromJSON", 1
};

word_t _fromJSON(CrocThread* t)
{
	croc_ex_checkParam(t, 1, CrocType_String);
	fromJSON(t, getCrocstr(t, 1));
	return 1;
}

const StdlibRegisterInfo _toJSON_info =
{
	Docstr(DFunc("toJSON") DParamAny("root") DParamD("pretty", "bool", "false")
	R"(Converts \tt{root} to a JSON string representation and returns that string.

	If you want to send JSON to a stream of some kind, have a look at \link{writeJSON}.

	\param[root] must (currently) be a table or array, and must recursively contain only null, bool, int, float, string,
		table, and array values. Any circularly-referenced objects will be detected and throw an exception.
	\param[pretty] controls whether or not whitespace and newlines are inserted into the output. If it's \tt{false},
		there will be as little whitespace as possible and no newlines. If it's \tt{true}, newlines, whitespace, and
		indentation will be inserted to make it at least somewhat human-readable.

	\throws[TypeError] if \tt{root} is not a table or array, or if any non-convertible types are found during
		conversion.
	\throws[ValueError] if the object graph is invalid somehow.)"),

	"toJSON", 2
};

word_t _toJSON(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 1);
	auto pretty = croc_ex_optBoolParam(t, 2, false);

	CrocStrBuffer buf;
	croc_ex_buffer_init(t, &buf);

	auto output = [&](crocstr s) { croc_ex_buffer_addStringn(&buf, cast(const char*)s.ptr, s.length); };
	auto newline = [&]() { croc_ex_buffer_addString(&buf, "\n"); };

	toJSON(t, 1, pretty, output, newline);
	croc_ex_buffer_finish(&buf);
	return 1;
}

const StdlibRegisterInfo _writeJSON_info =
{
	Docstr(DFunc("writeJSON") DParamAny("dest") DParamAny("root") DParamD("pretty", "bool", "false")
	R"(Like \link{toJSON}, but instead of returning a string, it calls methods of \tt{dest} to output the JSON.

	\tt{dest} can be any type which satisfies this interface:

	\blist
		\li It must have a method \tt{write} which will always be called with a single string parameter.
		\li It must have a method \tt{writeln} which will always be called without any parameters. This will only
			be called if the \tt{pretty} parameter is \tt{true}.
	\endlist

	The \link{stream.TextWriter} class satisfies this interface, but you can use any object which does.)"),

	"writeJSON", 3
};

word_t _writeJSON(CrocThread* t)
{
	croc_ex_checkAnyParam(t, 2);
	auto pretty = croc_ex_optBoolParam(t, 3, false);

	auto output = [&](crocstr s)
	{
		croc_dup(t, 1);
		croc_pushNull(t);
		pushCrocstr(t, s);
		croc_methodCall(t, -3, "write", 0);
	};

	auto newline = [&]()
	{
		croc_dup(t, 1);
		croc_pushNull(t);
		croc_methodCall(t, -2, "writeln", 0);
	};

	toJSON(t, 2, pretty, output, newline);
	return 0;
}

const StdlibRegister _globalFuncs[] =
{
	_DListItem(_fromJSON),
	_DListItem(_toJSON),
	_DListItem(_writeJSON),
	_DListEnd
};

word loader(CrocThread* t)
{
	registerGlobals(t, _globalFuncs);
	return 0;
}
}

void initJSONLib(CrocThread* t)
{
	registerModule(t, "json", &loader);
	croc_pushGlobal(t, "json");
#ifdef CROC_BUILTIN_DOCS
	CrocDoc doc;
	croc_ex_doc_init(t, &doc, __FILE__);
	croc_ex_doc_push(&doc,
	DModule("json")
	R"(\link[http://en.wikipedia.org/wiki/JSON]{JSON} is a standard for structured data interchange based on the
	JavaScript object notation. This library allows you to convert to and from JSON.)");
		docFields(&doc, _globalFuncs);
	croc_ex_doc_pop(&doc, -1);
	croc_ex_doc_finish(&doc);
#endif
	croc_popTop(t);
}
}