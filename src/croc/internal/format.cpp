
#include <functional>

#include "croc/api.h"
#include "croc/internal/format.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"
#include "croc/util/str.hpp"

/*
{{ escapes open brace; no need to escape closing braces

{[index][,width][:fmt]}
{r[index][,width]}

index is 0-based index into formatted args

width is positive or negative integer that specifies minimum field width; negative means left-alignment; 0 is error

fmt is a type-specific string which specifies output
	for ints:
		[+][#][width][type]
		type:
			u unsigned
			b/B binary (0b0101/0B0101)
			x/X hex
	for floats:
		[+][width][.[precision]][type]
		type:
			e/E
			f
			g/G
	for anything else:
		if it has a toStringFmt method, it is called with fmt as its parameter; otherwise, error.

If no fmt string is given:
	for non-raw output:
		call toString(obj) and place that string into the output field.
	for raw output:
		call toString(obj, true) and place that string into the output field.
*/

namespace croc
{
	const char* Spaces_ = "                                                                ";
	const crocstr Spaces = {Spaces_, 64};

	namespace
	{
		void doSpaces(CrocThread* t, uword n)
		{
			while(n > Spaces.length)
			{
				croc_pushStringn(t, Spaces.ptr, Spaces.length);
				n -= Spaces.length;
			}

			croc_pushStringn(t, Spaces.ptr, n);
		}

		word doInt(CrocThread* t, crocint v, crocstr fmt)
		{
			// Check format string validity
			if(fmt.length > 8)
				croc_eh_throwStd(t, "ValueError", "invalid format string: integer format string too large");

			auto p = fmt.ptr, e = fmt.ptr + fmt.length;
			bool putPrefix = false;
			uword width = 0;
			bool haveFmtType = false;
			char fmtType = 'd';

			// Flags
			if(p < e && *p == '+') p++;
			if(p < e && *p == '#') { p++; putPrefix = true; }

			// Width
			while(p < e && isdigit(*p))
				width = (width * 10) + (*p++ - '0');

			// Type
			if(p < e)
			{
				haveFmtType = true;

				switch(*p)
				{
					case 'u': case 'x': case 'X': case 'b': case 'B': fmtType = *p++; break;
					default: croc_eh_throwStd(t, "ValueError",
						"invalid format string: unknown integer format type '%c'", *p);
				}
			}

			// should be at end by now
			if(p != e)
				croc_eh_throwStd(t, "ValueError", "invalid integer format string");

			auto vm = Thread::from(t)->vm;
			auto outbuf = DArray<char>::n(vm->formatBuf, CROC_FORMAT_BUF_SIZE / 2);

			// conservatively add 2 for 0x, 1 for \0
			if((width + (2 + 1)) > outbuf.length)
				croc_eh_throwStd(t, "ValueError", "invalid format string: output number width is too large");

			if(fmtType == 'b' || fmtType == 'B')
			{
				auto dest = outbuf.ptr + outbuf.length;
				auto x = cast(uint64_t)v;

				uword total = 0;

				do
				{
					*--dest = (x & 1) ? '1' : '0';
					total++;
				}
				while(x >>= cast(uint64_t)1);

				while(total++ < width)
					*--dest = '0';

				if(putPrefix)
				{
					*--dest = fmtType;
					*--dest = '0';
					total += 2;
				}

				return croc_pushStringn(t, dest, total);
			}
			else
			{
				auto cfmt = DArray<char>::n(vm->formatBuf + (CROC_FORMAT_BUF_SIZE / 2), CROC_FORMAT_BUF_SIZE / 2);
				auto ifmt = atoda(CROC_INTEGER_FORMAT);

				auto offs = 0;
				cfmt[offs++] = '%';
				memcpy(cfmt.ptr + offs, fmt.ptr, fmt.length); offs += fmt.length;

				if(haveFmtType)
					offs--; // overwrite format type char

				memcpy(cfmt.ptr + offs, ifmt.ptr, ifmt.length); offs += ifmt.length;
				cfmt[offs - 1] = fmtType;
				cfmt[offs++] = '\0';

				auto len = snprintf(outbuf.ptr, outbuf.length, cfmt.ptr, v);

				if(len < 0 || cast(uword)len >= outbuf.length)
					croc_eh_throwStd(t, "ValueError", "error formatting integer");

				return croc_pushStringn(t, outbuf.ptr, len);
			}
		}

		word doFloat(CrocThread* t, crocfloat v, crocstr fmt)
		{
			// Check format string validity
			if(fmt.length > 8)
				croc_eh_throwStd(t, "ValueError", "invalid format string: float format string too large");

			auto p = fmt.ptr, e = fmt.ptr + fmt.length;
			bool haveFmtType = false;
			char fmtType = 'f';

			// Flags
			if(p < e && *p == '+') p++;

			// Width
			while(p < e && isdigit(*p)) p++;

			// Precision
			if(p < e && *p == '.')
			{
				p++;

				// it's okay to have the string end here, cause then it uses default precision
				while(p < e && isdigit(*p))
					p++;
			}

			// Type
			if(p < e)
			{
				haveFmtType = true;

				switch(*p)
				{
					case 'e': case 'E': case 'f': case 'g': case 'G': fmtType = *p++; break;
					default: croc_eh_throwStd(t, "ValueError",
						"invalid format string: unknown float format type '%c'", *p);
				}
			}

			// should be at end by now
			if(p != e)
				croc_eh_throwStd(t, "ValueError", "invalid float format string");

			auto vm = Thread::from(t)->vm;
			auto outbuf = DArray<char>::n(vm->formatBuf, CROC_FORMAT_BUF_SIZE / 2);
			auto cfmt = DArray<char>::n(vm->formatBuf + (CROC_FORMAT_BUF_SIZE / 2), CROC_FORMAT_BUF_SIZE / 2);

			auto offs = 0;
			cfmt[offs++] = '%';
			memcpy(cfmt.ptr + offs, fmt.ptr, fmt.length); offs += fmt.length;

			if(!haveFmtType)
				cfmt[offs++] = fmtType;

			cfmt[offs++] = '\0';

			auto len = snprintf(outbuf.ptr, outbuf.length, cfmt.ptr, v);

			if(len < 0 || cast(uword)len >= outbuf.length)
				croc_eh_throwStd(t, "ValueError", "error formatting float");

			return croc_pushStringn(t, outbuf.ptr, len);
		}

		void output(CrocThread* t, bool isRaw, word slot, word alignment, bool haveFmt, crocstr fmt)
		{
			word pushed;

			if(haveFmt)
			{
				switch(croc_type(t, slot))
				{
					case CrocType_Int: pushed = doInt(t, croc_getInt(t, slot), fmt); break;
					case CrocType_Float: pushed = doFloat(t, croc_getFloat(t, slot), fmt); break;

					default:
						if(!croc_hasMethod(t, slot, "toStringFmt"))
							croc_eh_throwStd(t, "ValueError",
								"Format string specified a custom format, but value has no toStringFmt method");

						pushed = croc_dup(t, slot);
						croc_pushNull(t);
						croc_pushStringn(t, fmt.ptr, fmt.length);
						croc_methodCall(t, -3, "toStringFmt", 1);
				}
			}
			else if(isRaw)
				pushed = croc_pushToStringRaw(t, slot);
			else
				pushed = croc_pushToString(t, slot);

			auto len = croc_len(t, pushed);

			if(alignment > 0 && alignment > len)
			{
				doSpaces(t, alignment - len);
				croc_moveToTop(t, pushed);
			}

			if(alignment < 0 && -alignment > len)
				doSpaces(t, -alignment - len);
		}
	}

	uword formatImpl(CrocThread* t, uword numParams)
	{
		return formatImpl(t, 1, numParams);
	}

	uword formatImpl(CrocThread* t, uword startIndex, uword numParams)
	{
		auto startSize = croc_getStackSize(t);
		auto formatStr = getCrocstr(Thread::from(t), startIndex);
		uword autoIndex = startIndex + 1;
		uword endIndex = autoIndex + numParams;
		uword begin = 0;

		while(begin < formatStr.length)
		{
			// output anything outside the {}
			auto fmtBegin = strLocateChar(formatStr, '{', begin);

			if(fmtBegin > begin)
			{
				croc_pushStringn(t, formatStr.ptr + begin, fmtBegin - begin);
				begin = fmtBegin;
			}

			// did we run out of string?
			if(fmtBegin == formatStr.length)
				break;

			// Check if it's an escaped {
			if(fmtBegin + 1 < formatStr.length && formatStr[fmtBegin + 1] == '{')
			{
				begin = fmtBegin + 2;
				croc_pushString(t, "{");
				continue;
			}

			// find the end of the {}
			auto fmtEnd = strLocateChar(formatStr, '}', fmtBegin + 1);

			// onoz, unmatched {}
			if(fmtEnd == formatStr.length)
				croc_eh_throwStd(t, "ValueError", "invalid format string: missing or misplaced right bracket");

			auto fmtSpec = formatStr.slice(fmtBegin + 1, fmtEnd);
			bool isRaw = false;
			uword index = 0;
			word alignment = 0;
			bool haveFmt = false;
			auto fmt = crocstr();

			auto p = fmtSpec.ptr, e = fmtSpec.ptr + fmtSpec.length;

			// raw
			if(p < e && *p == 'r')
			{
				isRaw = true;
				p++;
			}

			// param idx
			if(p < e && isdigit(*p))
			{
				while(p < e && isdigit(*p))
					index = (index * 10) + (*p++ - '0');

				index += startIndex + 1;
			}
			else
				index = autoIndex++;

			if(index >= endIndex)
				croc_eh_throwStd(t, "ValueError", "invalid format string: parameter index (%u) is out of bounds",
					index - startIndex - 1);

			// check for alignment
			if(p < e && *p == ',')
			{
				p++;

				if(p == e)
					croc_eh_throwStd(t, "ValueError", "invalid format string: alignment expected");

				bool neg = false;

				if(*p == '-')
				{
					p++;
					neg = true;
				}

				if(p == e || !isdigit(*p))
					croc_eh_throwStd(t, "ValueError", "invalid format string: alignment expected");

				while(p < e && isdigit(*p))
					alignment = (alignment * 10) + (*p++ - '0');

				if(neg)
					alignment = -alignment;
			}

			// check for format string
			if(p < e)
			{
				if(*p != ':')
					croc_eh_throwStd(t, "ValueError", "invalid format string: expected ':', not '%c'", *p);

				p++;

				haveFmt = true;
				fmt = crocstr::n(p, e - p);
			}

			// output it (or see if it's an invalid index)
			output(t, isRaw, index, alignment, haveFmt, fmt);
			begin = fmtEnd + 1;
		}

		return croc_getStackSize(t) - startSize;
	}
}