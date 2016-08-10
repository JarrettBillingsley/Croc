#ifndef CROC_COMPILER_TYPES_HPP
#define CROC_COMPILER_TYPES_HPP

#include <functional>
#include <stdarg.h>

#include "croc/types/base.hpp"

#define CROC_INTERNAL_NAME(s) ("$" s)

namespace croc
{
	extern const char* CompilerRegistryFlags;

	struct CompileLoc
	{
		crocstr file;
		uword line;
		uword col;
	};

	// Little bump allocator.
	template<uword PageSize>
	struct BumpAllocator
	{
	private:
		Memory* mMem;
		DArray<DArray<uint8_t> > mData;
		uword mPage;
		uword mOffset;

	public:
		void init(Memory& mem)
		{
			mMem = &mem;
			mData = DArray<DArray<uint8_t> >::alloc(*mMem, 4);
		}

		void free()
		{
			for(auto &arr: mData.slice(0, mPage + 1))
				arr.free(*mMem);

			mData.free(*mMem);
		}

		void* alloc(uword size)
		{
			assert(size <= PageSize);

		_again:
			if(mPage >= mData.length)
				mData.resize(*mMem, mData.length * 2);

			if(mData[mPage].length == 0)
				mData[mPage] = DArray<uint8_t>::alloc(*mMem, PageSize);

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
		Thread* t;
		uword mFlags;
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
		Compiler(Thread* t);
		Compiler(CrocThread* t);
		~Compiler();

		inline bool asserts()         { return (mFlags & CrocCompilerFlags_Asserts) != 0; }
		inline bool typeConstraints() { return (mFlags & CrocCompilerFlags_TypeConstraints) != 0; }
		inline bool docComments()     { return mLeaveDocTable || (mFlags & CrocCompilerFlags_Docs) != 0; }
		inline bool docTable()        { return mLeaveDocTable; }
		inline bool docDecorators()   { return (mFlags & CrocCompilerFlags_Docs) != 0; }
		inline void leaveDocTable(bool l) { mLeaveDocTable = l; }

		void lexException(CompileLoc loc, const char* msg, ...) CROCPRINT(3, 4);
		void synException(CompileLoc loc, const char* msg, ...) CROCPRINT(3, 4);
		void semException(CompileLoc loc, const char* msg, ...) CROCPRINT(3, 4);
		void eofException(CompileLoc loc, const char* msg, ...) CROCPRINT(3, 4);
		void loneStmtException(CompileLoc loc, const char* msg, ...) CROCPRINT(3, 4);
		void danglingDocException(CompileLoc loc, const char* msg, ...) CROCPRINT(3, 4);
		Thread* thread();
		Memory& mem();
		crocstr newString(crocstr s);
		crocstr newString(const char* s);
		void* allocNode(uword size);
		void addArray(DArray<uint8_t> arr, DArray<uint8_t> old);
		void addTempArray(DArray<uint8_t> arr);
		void updateTempArray(DArray<uint8_t> old, DArray<uint8_t> new_);
		void removeTempArray(DArray<uint8_t> arr);
		DArray<uint8_t> copyArray(DArray<uint8_t> arr);
		int compileModule(crocstr src, crocstr name, crocstr& modName);
		int compileStmts(crocstr src, crocstr name);
		int compileExpr(crocstr src, crocstr name);

	private:
		void vexception(CompileLoc loc, const char* exType, const char* msg, va_list args);
		word commonCompile(std::function<void()> dg);
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
				mData.resize(c.mem(), mIndex);
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
				mData.free(c.mem());
			}

			mData = DArray<T>::n(mOwnData, Len);
			mIndex = 0;
		}

	private:
		void resize(uword newSize)
		{
			if(mData.ptr == mOwnData)
			{
				auto newData = DArray<T>::alloc(c.mem(), newSize);
				newData.slicea(0, mData.length, mData);
				mData = newData;
				c.addTempArray(mData.template as<uint8_t>());
			}
			else
			{
				auto old = mData;
				mData.resize(c.mem(), newSize);
				c.updateTempArray(old.template as<uint8_t>(), mData.template as<uint8_t>());
			}
		}
	};
}

#endif