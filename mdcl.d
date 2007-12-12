/******************************************************************************
License:
Copyright (c) 2007 Jarrett Billingsley

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

module mdcl;

import minid.commandline;

import tango.io.Stdout;
import tango.io.Console;

void main(char[][] args)
{
	// This seemingly pointless code forces the GC to reserve some extra memory
	// from the start in order to improve performance upon subsequent allocations.
	// This is until the Tango GC gets a .reserve function or the like.
	auto chunk = new ubyte[1024 * 1024 * 4];
	delete chunk;

	(new CommandLine(Stdout, Cin.stream)).run(args);
}