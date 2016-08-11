#ifndef CROC_COMPILER_TYPES_HPP
#define CROC_COMPILER_TYPES_HPP

#include <functional>
#include <stdarg.h>

#include "croc/base/darray.hpp"

#define CROCPRINT(a, b) __attribute__((format(printf, a, b)))
#define CROC_INTERNAL_NAME(s) ("$" s)

typedef int64_t crocint_t;
typedef double crocfloat_t;
typedef size_t uword_t;
typedef ptrdiff_t word_t;
typedef uint64_t crocref_t;
typedef uint32_t crocchar_t;
typedef ptrdiff_t word;
typedef size_t uword;
typedef crocint_t crocint;
typedef crocfloat_t crocfloat;
typedef crocchar_t crocchar;
typedef DArray<const unsigned char> crocstr;
typedef DArray<unsigned char> mcrocstr;

struct CompileLoc
{
	crocstr file;
	uword line;
	uword col;
};

struct CompileEx : public std::exception
{
	const char msg[512];
	CompileLoc loc;

	CompileEx(const char* m, CompileLoc loc) : msg(), loc(loc)
	{
		strncpy((char*)msg, m, 512);
	}

	const char* what() const noexcept
	{
		return msg;
	}
};

// Little bump allocator.
template<uword PageSize>
struct BumpAllocator
{
private:
	DArray<DArray<uint8_t> > mData;
	uword mPage;
	uword mOffset;

public:
	void init()
	{
		mData = DArray<DArray<uint8_t> >::alloc(4);
	}

	void free()
	{
		for(auto &arr: mData.slice(0, mPage + 1))
			arr.free();

		mData.free();
	}

	void* alloc(uword size)
	{
		assert(size <= PageSize);

	_again:
		if(mPage >= mData.length)
			mData.resize(mData.length * 2);

		if(mData[mPage].length == 0)
			mData[mPage] = DArray<uint8_t>::alloc(PageSize);

		auto roundedSize = (size + (sizeof(uword) - 1)) & ~(sizeof(uword) - 1);

		if(roundedSize > (PageSize - mOffset))
		{
			mPage++;
			mOffset = 0;
			goto _again;
		}

		auto ret = cast(void*)(cast(char*)mData[mPage].ptr + mOffset);
		mOffset += roundedSize;
		return ret;
	}

	uword size()
	{
		return mOffset + (mPage > 0 ? mPage * PageSize : 0);
	}
};

#define CROC_COMPILER_PAGE_SIZE 8192

class Compiler
{
private:
	bool mIsEof;
	bool mIsLoneStmt;
	bool mDanglingDoc;
	bool mLeaveDocTable;
	word mStringTab;

	BumpAllocator<CROC_COMPILER_PAGE_SIZE> mNodes;
	BumpAllocator<CROC_COMPILER_PAGE_SIZE> mArrays;
	DArray<DArray<uint8_t> > mHeapArrays;
	uword mHeapArrayIdx;
	DArray<DArray<uint8_t> > mTempArrays;
	uword mTempArrayIdx;

public:
	Compiler();
	~Compiler();

	inline bool docComments()     { return false; }
	inline bool docTable()        { return false; }
	inline bool docDecorators()   { return false; }
	inline void leaveDocTable(bool l) { mLeaveDocTable = l; }

	void lexException(CompileLoc loc, const char* msg, ...) CROCPRINT(3, 4);
	void synException(CompileLoc loc, const char* msg, ...) CROCPRINT(3, 4);
	void semException(CompileLoc loc, const char* msg, ...) CROCPRINT(3, 4);
	void eofException(CompileLoc loc, const char* msg, ...) CROCPRINT(3, 4);
	void loneStmtException(CompileLoc loc, const char* msg, ...) CROCPRINT(3, 4);
	void danglingDocException(CompileLoc loc, const char* msg, ...) CROCPRINT(3, 4);
	crocstr newString(crocstr s);
	crocstr newString(const char* s);
	void* allocNode(uword size);
	void addArray(DArray<uint8_t> arr, DArray<uint8_t> old);
	void addTempArray(DArray<uint8_t> arr);
	void updateTempArray(DArray<uint8_t> old, DArray<uint8_t> new_);
	void removeTempArray(DArray<uint8_t> arr);
	DArray<uint8_t> copyArray(DArray<uint8_t> arr);
	int compileModule(crocstr src, crocstr name);

private:
	void vexception(CompileLoc loc, const char* exType, const char* msg, va_list args);
};

// Dynamically-sized list.
template<typename T, uword Len = 8>
class List
{
private:
	Compiler& c;
	T mOwnData[Len];
	DArray<T> mData;
	uword mIndex;

public:
	List(Compiler& co) : c(co), mIndex(0)
	{
		mData = DArray<T>::n(mOwnData, Len);
	}

	~List()
	{
		reset();
	}

	void add(T item)
	{
		if(mIndex >= mData.length)
			resize(mData.length * 2);

		mData[mIndex] = item;
		mIndex++;
	}

	void add(DArray<T> items)
	{
		for(auto &i: items)
			add(i);
	}

	void add(DArray<const T> items)
	{
		for(auto &i: items)
			add(i);
	}

	T operator[](uword index) const
	{
		assert(index < mIndex);
		return mData[index];
	}

	T& operator[](uword index)
	{
		assert(index < mIndex);
		return mData[index];
	}

	T& last()
	{
		assert(mIndex > 0);
		return mData[mIndex - 1];
	}

	void length(uword l)
	{
		mIndex = l;

		if(mIndex > mData.length)
			resize(mIndex);
	}

	uword length()
	{
		return mIndex;
	}

	DArray<T> toArray()
	{
		DArray<T> ret;

		if(mData.ptr == mOwnData)
			ret = c.copyArray(mData.slice(0, mIndex).template as<uint8_t>()).template as<T>();
		else
		{
			auto old = mData;
			mData.resize(mIndex);
			c.addArray(mData.template as<uint8_t>(), old.template as<uint8_t>());
			ret = mData;
		}

		mData = DArray<T>::n(mOwnData, Len);
		mIndex = 0;
		return ret;
	}

	DArray<T> toArrayView()
	{
		return mData.slice(0, mIndex);
	}

	T* begin()
	{
		return mData.ptr;
	}

	T* end()
	{
		return mData.ptr + mIndex;
	}

	void reset()
	{
		if(mData.length && mData.ptr != mOwnData)
		{
			c.removeTempArray(mData.template as<uint8_t>());
			mData.free();
		}

		mData = DArray<T>::n(mOwnData, Len);
		mIndex = 0;
	}

private:
	void resize(uword newSize)
	{
		if(mData.ptr == mOwnData)
		{
			auto newData = DArray<T>::alloc(newSize);
			newData.slicea(0, mData.length, mData);
			mData = newData;
			c.addTempArray(mData.template as<uint8_t>());
		}
		else
		{
			auto old = mData;
			mData.resize(newSize);
			c.updateTempArray(old.template as<uint8_t>(), mData.template as<uint8_t>());
		}
	}
};

#endif