
#include <functional>

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/format.hpp"
#include "croc/types/base.hpp"
#include "croc/util/str.hpp"

/*
{{ escapes open brace; no need to escape closing braces

{[index][,width][:fmt]}
{r[index][,width]}

index is 0-based index into formatted args

width is positive or negative integer that specifies minimum field width; negative means left-alignment; 0 is error

fmt is a type-specific string which specifies output
	for ints:
		[+| ][#][width][type]
		type:
			d/i signed (this is the default)
			u unsigned
			b/B binary
			x/X hex
	for floats:
		[+| ][width][.[precision]][type]
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
	const uchar* Spaces_ = cast(const uchar*)"                                                                ";
	const crocstr Spaces = {Spaces_, 64};
	const uchar* Lowercase = cast(const uchar*)"0123456789abcdef";
	const uchar* Uppercase = cast(const uchar*)"0123456789ABCDEF";

	namespace
	{
		void doSpaces(CrocThread* t, uword n)
		{
			while(n > Spaces.length)
			{
				croc_pushStringn(t, cast(const char*)Spaces.ptr, Spaces.length);
				n -= Spaces.length;
			}

			croc_pushStringn(t, cast(const char*)Spaces.ptr, n);
		}

		word doInt(CrocThread* t, crocint v, crocstr fmt)
		{
			// Check format string validity
			if(fmt.length > 8)
				croc_eh_throwStd(t, "ValueError", "invalid format string: integer format string too large");

			auto p = fmt.ptr, e = fmt.ptr + fmt.length;
			bool putPlus = false;
			bool putSpace = false;
			bool putPrefix = false;
			uword width = 0;
			// bool haveFmtType = false;
			char fmtType = 'd';
			int radix = 10;

			// Flags
			if(p < e)
			{
				if(*p == '+') { p++; putPlus = true; }
				else if(*p == ' ') { p++; putSpace = true; }
			}

			if(p < e && *p == '#') { p++; putPrefix = true; }

			// Width
			while(p < e && isdigit(*p))
				width = (width * 10) + (*p++ - '0');

			// Type
			if(p < e)
			{
				// haveFmtType = true;

				switch(*p)
				{
					case 'd': case 'i': p++; break; // just leave fmtType as 'd'
					case 'u': fmtType = *p++; break;
					case 'x': case 'X': radix = 16; fmtType = *p++; break;
					case 'b': case 'B': radix = 2; fmtType = *p++; break;
					default: croc_eh_throwStd(t, "ValueError", "invalid format string: unknown integer format type");
				}
			}

			// should be at end by now
			if(p != e)
				croc_eh_throwStd(t, "ValueError", "invalid integer format string");

			auto vm = Thread::from(t)->vm;
			auto outbuf = ustring::n(vm->formatBuf, CROC_FORMAT_BUF_SIZE / 2);

			// conservatively add 2 for 0x
			if((width + 2) > outbuf.length)
				croc_eh_throwStd(t, "ValueError", "invalid format string: output number width is too large");

			auto neg = (fmtType == 'd') && v < 0;

			if(neg)
				v = -v; // note for -max, this will still give correct output

			auto dest = outbuf.ptr + outbuf.length;
			auto x = cast(uint64_t)v;
			auto chars = (fmtType == 'X') ? Uppercase : Lowercase;

			uword total = 0;

			do
			{
				*--dest = chars[cast(uword)(x % radix)];
				total++;
			} while(x /= radix);

			while(total < width)
			{
				*--dest = '0';
				total++;
			}

			if(neg)
			{
				*--dest = '-';
				total++;
			}
			else if(fmtType == 'd')
			{
				if(putPlus)
				{
					*--dest = '+';
					total++;
				}
				else if(putSpace)
				{
					*--dest = ' ';
					total++;
				}
			}
			else if(fmtType != 'u' && putPrefix)
			{
				*--dest = fmtType;
				*--dest = '0';
				total += 2;
			}

			return croc_pushStringn(t, cast(const char*)dest, total);
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
			if(p < e)
			{
				if(*p == '+') p++;
				else if(*p == ' ') p++;
			}


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
					default: croc_eh_throwStd(t, "ValueError", "invalid format string: unknown float format type");
				}
			}

			// should be at end by now
			if(p != e)
				croc_eh_throwStd(t, "ValueError", "invalid float format string");

			auto vm = Thread::from(t)->vm;
			auto outbuf = ustring::n(vm->formatBuf, CROC_FORMAT_BUF_SIZE / 2);
			auto cfmt = ustring::n(vm->formatBuf + (CROC_FORMAT_BUF_SIZE / 2), CROC_FORMAT_BUF_SIZE / 2);

			auto offs = 0;
			cfmt[offs++] = '%';
			memcpy(cfmt.ptr + offs, fmt.ptr, fmt.length); offs += fmt.length;

			if(!haveFmtType)
				cfmt[offs++] = fmtType;

			cfmt[offs++] = '\0';

			auto len = snprintf(cast(char*)outbuf.ptr, outbuf.length, cast(const char*)cfmt.ptr, v);

			if(len < 0 || cast(uword)len >= outbuf.length)
				croc_eh_throwStd(t, "ValueError", "error formatting float");

			return croc_pushStringn(t, cast(const char*)outbuf.ptr, len);
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
						croc_pushStringn(t, cast(const char*)fmt.ptr, fmt.length);
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
				croc_pushStringn(t, cast(const char*)(formatStr.ptr + begin), fmtBegin - begin);
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
					croc_eh_throwStd(t, "ValueError", "invalid format string: expected ':'");

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