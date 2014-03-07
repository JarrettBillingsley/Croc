Source Layout
=============

croc/api[ex|funcs|types].h define the public C API of Croc. Everything else is internals/private.

ext/ is for code that I didn't write (ext is short for "external") and for any utility programs (like for converting
data files to header files).

General structure of the source, from lowest-level to highest-level:

 * util/ contains useful code that doesn't actually depend on anything in the Croc library, like Unicode handling, array
   manipulation, string utilities etc.
 * base/ contains super low-level stuff like the GC, memory management, low-level data structures etc.
 * types/ contains the types used throughout the library. types/base holds most of the declarations, and the other files
   hold the definitions for the reference types. These are low-level operations, below the level of the interpreter.
 * internal/ contains what you might call the "interpreter", which includes the actual bytecode interpreter as well as
   all the functionality needed to support it. Much of this functionality is also used by the public API.
 * compiler/ contains... the compiler.
 * api/ contains the implementation of the functions defined in croc/apifuncs.h, that is, the basic API.
 * ex/ contains the implementation of the functions defined in croc/apiex.h, which is implemented on top of the public
   croc C API. Ostensibly.
 * stdlib/ contains the standard libraries. Again, these are ostensibly written entirely with the public C API, but in
   reality they dip down into the library internals for better performance.