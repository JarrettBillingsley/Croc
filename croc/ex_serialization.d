/******************************************************************************
This module provides a native interface to the Croc 'serialization' standard
library.

License:
Copyright (c) 2013 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module croc.ex_serialization;

import tango.io.model.IConduit;

import croc.api_interpreter;
import croc.api_stack;
import croc.ex;
import croc.types;

// =====================================================================================================================
// Public
// =====================================================================================================================

public:

/**
*/
void serializeGraph(CrocThread* t, word idx, word trans, OutputStream output)
{
	idx = absIndex(t, idx);
	trans = absIndex(t, trans);

	auto func = lookupCT!("serialization.serializeGraph")(t);
	pushNull(t);
	dup(t, idx);
	dup(t, trans);
	_makeOutputStream(t, output);
	rawCall(t, func, 0);
}

/**
*/
word deserializeGraph(CrocThread* t, word trans, InputStream input)
{
	trans = absIndex(t, trans);

	auto func = lookupCT!("serialization.deserializeGraph")(t);
	pushNull(t);
	dup(t, trans);
	_makeInputStream(t, input);
	rawCall(t, func, 1);
	return func;
}

/**
*/
void serializeModule(CrocThread* t, word idx, char[] name, OutputStream output)
{
	idx = absIndex(t, idx);

	auto func = lookupCT!("serialization.serializeModule")(t);
	pushNull(t);
	dup(t, idx);
	pushString(t, name);
	_makeOutputStream(t, output);
	rawCall(t, func, 0);
}

/**
*/
word deserializeModule(CrocThread* t, out char[] name, InputStream input)
{
	auto func = lookupCT!("serialization.deserializeModule")(t);
	pushNull(t);
	_makeInputStream(t, input);
	rawCall(t, func, 2);
	name = getString(t, -1);
	pop(t);
	return func;
}

// =====================================================================================================================
// Private
// =====================================================================================================================

private:

void _makeOutputStream(CrocThread* t, OutputStream output)
{
	auto stream = lookupCT!("stream.NativeStream")(t);
	pushNull(t);
	pushNativeObj(t, cast(Object)output);
	pushBool(t, false);
	pushBool(t, false);
	pushBool(t, true);
	rawCall(t, stream, 1);
}

void _makeInputStream(CrocThread* t, InputStream input)
{
	auto stream = lookupCT!("stream.NativeStream")(t);
	pushNull(t);
	pushNativeObj(t, cast(Object)input);
	pushBool(t, false);
	pushBool(t, true);
	pushBool(t, false);
	rawCall(t, stream, 1);
}