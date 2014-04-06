#ifndef CROC_BASE_SANITY_HPP
#define CROC_BASE_SANITY_HPP

// Really basic stdlibs used everywhere.
#include <stddef.h>
#include <stdint.h>
#include <assert.h>

#define cast(x) (x)
#define TEST_FLAG(o, f)  (((o) & (f)) != 0)
#define SET_FLAG(o, f)   ((o) |= (f))
#define CLEAR_FLAG(o, f) ((o) &= ~(f))

#ifndef NDEBUG
#include <stdio.h>
#define DBGPRINT(...) printf(__VA_ARGS__)
#else
#define DBGPRINT(...)
#endif

// TODO: make a config header file, like Lua
#ifdef _WIN32
#define CROC_INTEGER_FORMAT "I64d"
#define CROC_UINTEGER_FORMAT "I64u"
#define CROC_HEX64_FORMAT "I64x"

#ifdef _WIN64
# define CROC_SIZE_T_FORMAT "I64u"
# define CROC_SSIZE_T_FORMAT "I64d"
#else
# define CROC_SIZE_T_FORMAT "u"
# define CROC_SSIZE_T_FORMAT "d"
#endif

#else
// Who thought "yeah let's make the same integer type use different print specifiers depending on your platform" made
// any
// fucking
// sense
// whatsoever
#if CROC_BUILD_BITS == 64
#define CROC_INTEGER_FORMAT "ld"
#define CROC_UINTEGER_FORMAT "lu"
#define CROC_HEX64_FORMAT "lx"
#else
#define CROC_INTEGER_FORMAT "lld"
#define CROC_UINTEGER_FORMAT "llu"
#define CROC_HEX64_FORMAT "llx"
#endif

#define CROC_SIZE_T_FORMAT "zu"
#define CROC_SSIZE_T_FORMAT "zd"
// #define CROC_SIZE_T_FORMAT "u"
// #define CROC_SSIZE_T_FORMAT "d"
#endif

#define CROC_FORMAT_BUF_SIZE 256

#endif