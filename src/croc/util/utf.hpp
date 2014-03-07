#ifndef CROC_UTIL_UTF_HPP
#define CROC_UTIL_UTF_HPP

namespace croc
{
	typedef uint8_t uchar;
	typedef uint16_t wchar;
	typedef uint32_t dchar;

	typedef DArray<uchar> ustring;
	typedef DArray<wchar> wstring;
	typedef DArray<dchar> dstring;

	typedef DArray<const uchar> custring;
	typedef DArray<const wchar> cwstring;
	typedef DArray<const dchar> cdstring;

	/**
	Enumeration of possible return values from certain UTF decoding functions.
	*/
	typedef enum UtfError
	{
		UtfError_OK = 0,          /// Success.
		UtfError_BadEncoding = 1, /// The data is incorrectly encoded. It may or may not be possible to progress past this.
		UtfError_BadChar = 2,     /// The data was encoded properly, but encodes an invalid character.
		UtfError_Truncated = 3,   /// The end of the data comes before the character can be completely decoded.
	} UtfError;

	bool isValidChar(dchar c);
	size_t charUtf8Length(dchar c);
	size_t utf8SequenceLength(uchar firstByte);

	UtfError decodeUtf8Char(const uchar*& s, const uchar* end, dchar& out);
	template<bool swap = false>
	UtfError decodeUtf16Char(const wchar*& s, const wchar* end, dchar& out);
	#define decodeUtf16CharBS decodeUtf16Char<true>
	template<bool swap = false>
	UtfError decodeUtf32Char(const dchar*& s, const dchar* end, dchar& out);
	#define decodeUtf32CharBS decodeUtf32Char<true>
	void skipBadUtf8Char(const uchar*& s, const uchar* end);
	template<bool swap = false>
	void skipBadUtf16Char(const wchar*& s, const wchar* end);
	#define skipBadUtf16CharBS skipBadUtf16Char<true>
	template<bool swap = false>
	void skipBadUtf32Char(const dchar*& s, const dchar* end);
	#define skipBadUtf32CharBS skipBadUtf32Char<true>
	bool verifyUtf8(custring str, size_t& cpLen);
	UtfError Utf16ToUtf8(cwstring str, ustring buf, cwstring& remaining, ustring& output);
	UtfError Utf32ToUtf8(cdstring str, ustring buf, cdstring& remaining, ustring& output);
	UtfError Utf16ToUtf8BS(cwstring str, ustring buf, cwstring& remaining, ustring& output);
	UtfError Utf32ToUtf8BS(cdstring str, ustring buf, cdstring& remaining, ustring& output);
	UtfError encodeUtf8Char(ustring buf, dchar c, ustring& ret);

	// =================================================================================================================
	// The functions from here on all assume the input string is well-formed -- which is the case with Croc's strings

	dchar fastDecodeUtf8Char(const uchar*& s);
	dchar fastReverseUtf8Char(const uchar*& s);
	void fastAlignUtf8(const uchar*& s);
	template<bool swap = false>
	wstring Utf8ToUtf16(custring str, wstring buf, custring& remaining);
	#define Utf8ToUtf16BS Utf8ToUtf16<true>
	template<bool swap = false>
	dstring Utf8ToUtf32(custring str, dstring buf, custring& remaining);
	#define Utf8ToUtf32BS Utf8ToUtf32<true>
	custring utf8Slice(custring str, size_t lo, size_t hi);
	dchar utf8CharAt(custring str, size_t idx);
	size_t utf8CPIdxToByte(custring str, size_t fake);
	size_t utf8ByteIdxToCP(custring str, size_t fake);
	size_t fastUtf8CPLength(custring str);
	size_t fastUtf32GetUtf8Size(cdstring str);

	struct DcharIterator
	{
	private:
		const uchar* mPtr;

	public:
		DcharIterator(const char* str) : mPtr(cast(const uchar*)str) {}
		DcharIterator(const uchar* str) : mPtr(str) {}
		DcharIterator(const DcharIterator& other) : mPtr(other.mPtr) {}
		DcharIterator& operator++() { mPtr += utf8SequenceLength(*mPtr); return *this; }
		DcharIterator operator++(int) { DcharIterator tmp(*this); operator++(); return tmp; }
		bool operator==(const DcharIterator& rhs) { return mPtr == rhs.mPtr; }
		bool operator!=(const DcharIterator& rhs) { return !(*this == rhs); }
		dchar operator*() { const uchar* tmp = mPtr; return fastDecodeUtf8Char(tmp); }
	};

	struct dcharsOf
	{
	private:
		custring mStr;

	public:
		dcharsOf(custring str) : mStr(str) {}

		DcharIterator begin()
		{
			return DcharIterator(mStr.ptr);
		}

		DcharIterator end()
		{
			return DcharIterator(mStr.ptr + mStr.length);
		}
	};
}

#endif