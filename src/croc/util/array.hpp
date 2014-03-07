#ifndef CROC_UTIL_ARRAY_HPP
#define CROC_UTIL_ARRAY_HPP

#include <functional>
#include <stddef.h>
#include <stdint.h>

#include "croc/types/base.hpp"

namespace croc
{
	namespace
	{
		// C++ smoothsort implementation borrowed from
		// http://en.wikibooks.org/wiki/Algorithm_Implementation/Sorting/Smoothsort
		struct LeonardoNumber
		{
			uword b;
			uword c;
			LeonardoNumber() : b(1), c(1) {}
			LeonardoNumber(const LeonardoNumber& other) : b(other.b), c(other.c) {}
			inline uword gap() const { return b - c; }
			inline LeonardoNumber& operator++() { uword s = b; b = b + c + 1; c = s; return *this; }
			inline LeonardoNumber& operator--() { uword s = c; c = b - c - 1; b = s; return *this; }
		};

		template<typename T>
		inline void swap(T& a, T& b)
		{
			auto t = a;
			a = b;
			b = t;
		}

		template<typename T>
		inline void sift(DArray<T> m, uword r, LeonardoNumber b, std::function<bool(T, T)> ge)
		{
			uword r2;

			while(b.b >= 3)
			{
				if(ge(m[r - b.gap()], m[r - 1]))
					r2 = r - b.gap();
				else
				{
					r2 = r - 1;
					--b;
				}

				if(ge(m[r], m[r2]))
					break;
				else
				{
					swap(m[r], m[r2]);
					r = r2;
					--b;
				}
			}
		}

		template<typename T>
		inline void semitrinkle(DArray<T> m, uword r, uint64_t p, LeonardoNumber b, std::function<bool(T, T)> ge)
		{
			if(ge(m[r - b.c], m[r]))
			{
				swap(m[r], m[r - b.c]);
				trinkle(m, r - b.c, p, b, ge);
			}
		}


		template<typename T>
		inline void trinkle(DArray<T> m, uword r, uint64_t p, LeonardoNumber b, std::function<bool(T, T)> ge)
		{
			while(p)
			{
				for( ; (p & 1) == 0; p >>= 1)
					++b;

				if(!--p || ge(m[r], m[r - b.b]))
					break;
				else if(b.b == 1)
				{
					swap(m[r], m[r - b.b]);
					r -= b.b;
				}
				else if(b.b >= 3)
				{
					uword r2 = r - b.gap();
					uword r3 = r - b.b;

					if(ge(m[r - 1], m[r2]))
					{
						r2 = r - 1;
						p <<= 1;
						--b;
					}

					if(ge(m[r3], m[r2]))
					{
						swap(m[r], m[r3]);
						r = r3;
					}
					else
					{
						swap(m[r], m[r2]);
						r = r2;
						--b;
						break;
					}
				}
			}

			sift(m, r, b, ge);
		}
	}

	template<typename T>
	void arrSort(DArray<T> m, std::function<bool(T, T)> ge)
	{
		if(m.length == 0)
			return;

		uint64_t p = 1;
		LeonardoNumber b;

		for(uword q = 0; ++q < m.length; ++p)
		{
			if((p & 7) == 3)
			{
				sift(m, q - 1, b, ge);
				++++b;
				p >>= 2;
			}
			else if((p & 3) == 1)
			{
				if((q + b.c) < m.length)
					sift(m, q - 1, b, ge);
				else
					trinkle(m, q - 1, p, b, ge);

				for(p <<= 1; --b, b.b > 1; p <<= 1)
				{}
			}
		}

		trinkle(m, m.length - 1, p, b, ge);
		auto n = m.length;

		for(--p; n-- > 1; --p)
		{
			if(b.b == 1)
			{
				for( ; (p & 1) == 0; p >>= 1)
					++b;
			}
			else if(b.b >= 3)
			{
				if(p)
					semitrinkle(m, n - b.gap(), p, b, ge);

				--b;
				p <<= 1;
				++p;
				semitrinkle(m, n - 1, p, b, ge);
				--b;
				p <<= 1;
				++p;
			}
		}
	}

	template<typename T>
	void arrSort(DArray<T> m)
	{
		arrSort<T>(m, [](T a, T b) -> bool { return a >= b; });
	}

	template<typename T>
	inline void arrReverse(DArray<T> arr)
	{
		auto mid = arr.length / 2;

		for(size_t i = 0, j = arr.length - 1; i < mid; i++, j--)
		{
			auto tmp = arr.ptr[i];
			arr.ptr[i] = arr.ptr[j];
			arr.ptr[j] = tmp;
		}
	}

	template<typename T>
	uword arrFindElem(DArray<T> arr, T v, uword start = 0)
	{
		uword i = start;

		for(auto &val: arr.slice(start, arr.length))
		{
			if(val == v)
				return i;
			i++;
		}

		return arr.length;
	}

	template<typename T>
	uword arrFindElem(DArray<T> arr, T v, std::function<bool(T, T)> eq, uword start = 0)
	{
		uword i = start;

		for(auto &val: arr.slice(start, arr.length))
		{
			if(eq(val, v))
				return i;
			i++;
		}

		return arr.length;
	}

	template<typename T>
	uword arrFindElemRev(DArray<T> arr, T v, uword start)
	{
		uword i = start;

		for(auto &val: arr.slice(0, start + 1).reverse())
		{
			if(val == v)
				return i;
			i--;
		}

		return arr.length;
	}

	template<typename T>
	uword arrFindElemRev(DArray<T> arr, T v, std::function<bool(T, T)> eq, uword start)
	{
		uword i = start;

		for(auto &val: arr.slice(0, start + 1).reverse())
		{
			if(eq(val, v))
				return i;
			i--;
		}

		return arr.length;
	}

	template<typename T>
	inline uword arrFindElemRev(DArray<T> arr, T v)
	{
		return arrFindElemRev(arr, v, arr.length);
	}

	template<typename T>
	inline uword arrFindElemRev(DArray<T> arr, T v, std::function<bool(T, T)> eq)
	{
		return arrFindElemRev(arr, v, eq, arr.length);
	}

	template<typename T>
	uword arrFindSub(DArray<T> arr, DArray<T> sub, uword start = 0)
	{
		if(arr.length == 0 || sub.length == 0 || sub.length > arr.length)
			return arr.length;

		auto maxPos = arr.length - sub.length;

		if(start > maxPos)
			return arr.length;

		for(auto pos = arrFindElem(arr, sub[0], start);
			pos <= maxPos;
			pos = arrFindElem(arr, sub[0], pos + 1))
		{
			if(arr.slice(pos, pos + sub.length) == sub)
				return pos;
		}

		return arr.length;
	}

	template<typename T>
	uword arrFindSub(DArray<T> arr, DArray<T> sub, std::function<bool(T, T)> eq, uword start = 0)
	{
		if(arr.length == 0 || sub.length == 0 || sub.length > arr.length)
			return arr.length;

		auto maxPos = arr.length - sub.length;

		if(start > maxPos)
			return arr.length;

		for(auto pos = arrFindElem(arr, sub[0], eq, start);
			pos <= maxPos;
			pos = arrFindElem(arr, sub[0], eq, pos + 1))
		{
			uword i = 0;
			for(auto &l: arr.slice(pos, pos + sub.length))
			{
				if(!eq(l, sub[i++]))
					goto _notEquals;
			}
			return pos;
		_notEquals:;
		}

		return arr.length;
	}

	template<typename T>
	uword arrFindSubRev(DArray<T> arr, DArray<T> sub, uword start)
	{
		if(arr.length == 0 || sub.length == 0 || sub.length > arr.length)
			return arr.length;

		auto maxPos = arr.length - sub.length;

		if(start > maxPos)
			start = maxPos;

		for(auto pos = arrFindElemRev(arr, sub[0], start);
			pos != arr.length;
			pos = arrFindElemRev(arr, sub[0], pos - 1))
		{
			if(arr.slice(pos, pos + sub.length) == sub)
				return pos;
		}

		return arr.length;
	}

	template<typename T>
	uword arrFindSubRev(DArray<T> arr, DArray<T> sub, std::function<bool(T, T)> eq, uword start)
	{
		if(arr.length == 0 || sub.length == 0 || sub.length > arr.length)
			return arr.length;

		auto maxPos = arr.length - sub.length;

		if(start > maxPos)
			start = maxPos;

		for(auto pos = arrFindElemRev(arr, sub[0], eq, start);
			pos != arr.length;
			pos = arrFindElemRev(arr, sub[0], eq, pos - 1))
		{
			uword i = 0;
			for(auto &l: arr.slice(pos, pos + sub.length))
			{
				if(!eq(l, sub[i++]))
					goto _notEquals;
			}
			return pos;
		_notEquals:;
		}

		return arr.length;
	}

	template<typename T>
	inline uword arrFindSubRev(DArray<T> arr, DArray<T> sub)
	{
		return arrFindSubRev(arr, sub, arr.length);
	}

	template<typename T>
	inline uword arrFindSubRev(DArray<T> arr, DArray<T> sub, std::function<bool(T, T)> eq)
	{
		return arrFindSubRev(arr, sub, eq, arr.length);
	}
}

#endif