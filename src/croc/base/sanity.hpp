/**
A few little things that help me keep my sanity when developing in such a.. primitive language.
*/

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

#endif