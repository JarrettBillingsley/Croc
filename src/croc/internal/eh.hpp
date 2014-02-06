#ifndef CROC_INTERNAL_EH_HPP
#define CROC_INTERNAL_EH_HPP

#include <functional>

#include "croc/types.hpp"

namespace croc
{
	word defaultUnhandledEx(CrocThread* t);
	EHFrame* pushEHFrame(Thread* t);
	void pushNativeEHFrame(Thread* t, RelStack slot, jmp_buf& buf);
	void pushScriptEHFrame(Thread* t, bool isCatch, RelStack slot, word pcOffset);
	void popEHFrame(Thread* t);
	void unwindThisFramesEH(Thread* t);
	bool tryCode(Thread* t, RelStack slot, std::function<void()> dg);
	word pushTraceback(Thread* t);
	void continueTraceback(Thread* t, Value ex);
	void addLocationInfo(Thread* t, Value ex);
	void throwImpl(Thread* t, Value ex, bool rethrowing);
	void unwind(Thread* t);
}

#endif