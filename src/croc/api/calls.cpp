
#include "croc/api.h"
#include "croc/api/apichecks.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types/base.hpp"

#define COMMON_CALL_GUNK()\
	auto t = Thread::from(t_);\
	auto absSlot = fakeToAbs(t, slot);\
	auto numParams = t->stackIndex - (absSlot + 1);\
\
	if(numParams < 1)\
		croc_eh_throwStd(t_, "ApiError", "%s - too few parameters (must have at least 1 for the context)",\
			__FUNCTION__);\
\
	if(numReturns < -1)\
		croc_eh_throwStd(t_, "ApiError", "%s - invalid number of returns (must be >= -1)", __FUNCTION__);

#define TRYCALL_BEGIN\
	COMMON_CALL_GUNK();\
	int results = 0;\
	auto failed = tryCode(t, slot, [&]\
	{

#define TRYCALL_END\
	});\
\
	if(failed)\
		return CrocCallRet_Error;\
	else\
		return results;

using namespace croc;

extern "C"
{
	/** Performs a function call.

	The process of calling a function goes something like this:

	1. Push the function (or other object) that you want to call.
	2. Push the 'this' parameter (or null if it doesn't matter). This is equivalent to 'with' in Croc, except you always
		have to pass it in the native API.
	3. Push any parameters.
	4. Call \c croc_call with the slot of the thing you want to call.
	5. Optionally deal with any return values.

	As an example, let's call the \c toString function on an integer:

	\code{.c}
	croc_pushGlobal(t, "toString");        // push the function
	croc_pushNull(t);                      // push 'this' (null cause we don't care)
	croc_pushInt(t, 5);                    // push parameters
	croc_call(t, -3, 1);                   // call the third-from-top slot (toString), and have it return 1 value
	printf("%s\n", croc_getString(t, -1)); // print out the return value (prints 5)
	croc_popTop(t);                        // stack is now exactly as it was when we started
	\endcode

	When you use \c croc_call, all the slots above \c slot are considered its parameters. All the slots starting at \c
	slot are removed from the stack and replaced with the return values upon return.

	\param slot is the slot to call. There must be at least one slot on the stack above this slot for the 'this'
		parameter.
	\param numReturns is how many return values you want left on the stack. This can be -1, which means "as many values
		as were returned".
	\returns how many values were returned from the call. If \c numReturns >= 0, then this is the same as \c numReturns,
		but if it was -1 this is how you find out how many values are sitting on top of the stack. */
	uword_t croc_call(CrocThread* t_, word_t slot, word_t numReturns)
	{
		COMMON_CALL_GUNK();
		return commonCall(t, absSlot, numReturns, callPrologue(t, absSlot, numReturns, numParams));
	}

	/** Performs a method call.

	The way you use this is almost identical to \ref croc_call, except instead of pushing the thing to call, you push
	the thing to call the method on. For example, let's call the "writeln" method of \c console.stderr:

	\code{.c}
	croc_ex_lookup(t, "console.stderr");        // push the object
	croc_pushNull(t);                           // still have to push something here..
	croc_pushString(t, "Bad things happened!"); // push parameters
	croc_methodCall(t, -3, "writeln", 0);       // call method, expect no results
	// stack is now exactly as it was when we started
	\endcode

	Notice that you still have to push a slot after the object. The value of this slot will always be ignored and
	overwritten with the object. It's just there to make the API the same as \ref croc_call and to simplify the
	implementation of this function (so it doesn't have to shift the parameters up).

	\param slot is the slot holding the object on which the method will be called.
	\param name is the name of the method to call.
	\param numReturns is how many return values you want left on the stack, or -1 to get all values returned.
	\returns how many values were returned from the call, just like \ref croc_call. */
	uword_t croc_methodCall(CrocThread* t_, word_t slot, const char* name, word_t numReturns)
	{
		COMMON_CALL_GUNK();
		auto mname = String::create(t->vm, atoda(name));
		return commonCall(t, absSlot, numReturns,
			methodCallPrologue(t, absSlot, t->stack[absSlot], mname, numReturns, numParams));
	}

	/** Just like \ref croc_call, but sets up an exception frame around the call.

	This is like using a try-catch block in Croc. The way you use it is exactly the same as \ref croc_call, except for
	the return value. If the call completed successfully, the return value will be >= 0. If an exception was thrown
	(and caught by this exception frame), it will return \ref CrocCallRet_Error. In this case, the exception object will
	be sitting on top of the stack (replacing the function and its parameters, just like when it returns values
	normally). You can then do whatever you want, such as handling the exception, or doing some cleanup and rethrowing
	it with \ref croc_eh_rethrow.

	It's also good practice to see if the exception you caught was a \c HaltException. If so, you should rethrow it. You
	can use the \ref croc_ex_isHaltException function to easily see if it is. */
	int croc_tryCall(CrocThread* t_, word_t slot, word_t numReturns)
	{
		TRYCALL_BEGIN
			results = commonCall(t, absSlot, numReturns, callPrologue(t, absSlot, numReturns, numParams));
		TRYCALL_END
	}

	/** Just like \ref croc_methodCall, but sets up an exception frame around the call like \ref croc_tryCall. */
	int croc_tryMethodCall(CrocThread* t_, word_t slot, const char* name, word_t numReturns)
	{
		TRYCALL_BEGIN
			auto mname = String::create(t->vm, atoda(name));
			results = commonCall(t, absSlot, numReturns,
				methodCallPrologue(t, absSlot, t->stack[absSlot], mname, numReturns, numParams));
		TRYCALL_END
	}
}