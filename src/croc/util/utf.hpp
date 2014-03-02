#ifndef CROC_UTF_HPP
#define CROC_UTF_HPP

namespace croc
{
	typedef uint8_t uchar;
	typedef uint16_t wchar;
	typedef uint32_t dchar;

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
	size_t utf8SequenceLength(uint8_t firstByte);

	UtfError decodeUtf8Char(const char*& s, const char* end, dchar& out);
	template<bool swap = false>
	UtfError decodeUtf16Char(const wchar*& s, const wchar* end, dchar& out);
	#define decodeUtf16CharBS decodeUtf16Char<true>
	template<bool swap = false>
	UtfError decodeUtf32Char(const dchar*& s, const dchar* end, dchar& out);
	#define decodeUtf32CharBS decodeUtf32Char<true>
	void skipBadUtf8Char(const char*& s, const char* end);
	template<bool swap = false>
	void skipBadUtf16Char(const wchar*& s, const wchar* end);
	#define skipBadUtf16CharBS skipBadUtf16Char<true>
	template<bool swap = false>
	void skipBadUtf32Char(const dchar*& s, const dchar* end);
	#define skipBadUtf32CharBS skipBadUtf32Char<true>
	bool verifyUtf8(DArray<const char> str, size_t& cpLen);
	UtfError Utf16ToUtf8(DArray<const wchar> str, DArray<char> buf, DArray<const wchar>& remaining, DArray<char>& output);
	UtfError Utf32ToUtf8(DArray<const dchar> str, DArray<char> buf, DArray<const dchar>& remaining, DArray<char>& output);
	UtfError Utf16ToUtf8BS(DArray<const wchar> str, DArray<char> buf, DArray<const wchar>& remaining, DArray<char>& output);
	UtfError Utf32ToUtf8BS(DArray<const dchar> str, DArray<char> buf, DArray<const dchar>& remaining, DArray<char>& output);

	UtfError encodeUtf8Char(DArray<char> buf, dchar c, DArray<char>& ret);

	// =================================================================================================================
	// The functions from here on all assume the input string is well-formed -- which is the case with Croc's strings

	dchar fastDecodeUtf8Char(const char*& s);
	dchar fastReverseUtf8Char(const char*& s);
	void fastAlignUtf8(const char*& s);
	template<bool swap = false>
	DArray<wchar> Utf8ToUtf16(DArray<const char> str, DArray<wchar> buf, DArray<const char>& remaining);
	#define Utf8ToUtf16BS Utf8ToUtf16<true>
	template<bool swap = false>
	DArray<dchar> Utf8ToUtf32(DArray<const char> str, DArray<dchar> buf, DArray<const char>& remaining);
	#define Utf8ToUtf32BS Utf8ToUtf32<true>
	DArray<const char> utf8Slice(DArray<const char> str, size_t lo, size_t hi);
	dchar utf8CharAt(DArray<const char> str, size_t idx);
	size_t utf8CPIdxToByte(DArray<const char> str, size_t fake);
	size_t utf8ByteIdxToCP(DArray<const char> str, size_t fake);
	size_t fastUtf8CPLength(DArray<const char> str);
	size_t fastUtf32GetUtf8Size(DArray<const dchar> str);

	struct DcharIterator
	{
	private:
		const char* mPtr;

	public:
		DcharIterator(const char* str) : mPtr(str) {}
		DcharIterator(const DcharIterator& other) : mPtr(other.mPtr) {}
		DcharIterator& operator++() { mPtr += utf8SequenceLength(*mPtr); return *this; }
		DcharIterator operator++(int) { DcharIterator tmp(*this); operator++(); return tmp; }
		bool operator==(const DcharIterator& rhs) { return mPtr == rhs.mPtr; }
		bool operator!=(const DcharIterator& rhs) { return !(*this == rhs); }
		dchar operator*() { const char* tmp = mPtr; return fastDecodeUtf8Char(tmp); }
	};

	struct dcharsOf
	{
	private:
		DArray<const char> mStr;

	public:
		dcharsOf(DArray<const char> str) : mStr(str) {}

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