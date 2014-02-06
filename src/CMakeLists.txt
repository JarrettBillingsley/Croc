cmake_minimum_required(VERSION 2.8)

set(croc_SRC
	croc/api/array.cpp
	croc/api/basic.cpp
	croc/api/calls.cpp
	croc/api/class.cpp
	croc/api/eh.cpp
	croc/api/funcdef.cpp
	croc/api/function.cpp
	croc/api/gc.cpp
	croc/api/mem.cpp
	croc/api/memblock.cpp
	croc/api/nativeref.cpp
	croc/api/namespace.cpp
	croc/api/reflection.cpp
	croc/api/stack.cpp
	croc/api/table.cpp
	croc/api/thread.cpp
	croc/api/typequeries.cpp
	croc/api/valuetypes.cpp
	croc/api/variables.cpp
	croc/api/vm.cpp
	croc/api/weakref.cpp
	croc/base/darray.hpp
	croc/base/deque.cpp
	croc/base/deque.hpp
	croc/base/gc.cpp
	croc/base/gc.hpp
	croc/base/gcobject.hpp
	croc/base/hash.hpp
	croc/base/leakdetector.cpp
	croc/base/leakdetector.hpp
	croc/base/memory.cpp
	croc/base/memory.hpp
	croc/base/metamethods.cpp
	croc/base/metamethods.hpp
	croc/base/opcodes.cpp
	croc/base/opcodes.hpp
	croc/base/sanity.hpp
	croc/base/writebarrier.cpp
	croc/base/writebarrier.hpp
	croc/ex/paramchecks.cpp
	croc/ext/jhash.cpp
	croc/ext/jhash.hpp
	croc/internal/apichecks.hpp
	croc/internal/basic.cpp
	croc/internal/basic.hpp
	croc/internal/calls.cpp
	croc/internal/calls.hpp
	croc/internal/class.cpp
	croc/internal/class.hpp
	croc/internal/debug.cpp
	croc/internal/debug.hpp
	croc/internal/eh.cpp
	croc/internal/eh.hpp
	croc/internal/stack.cpp
	croc/internal/stack.hpp
	croc/internal/variables.cpp
	croc/internal/variables.hpp
	croc/stdlib/all.hpp
	croc/stdlib/modules.cpp
	croc/types.cpp
	croc/types.hpp
	croc/types/array.cpp
	croc/types/class.cpp
	croc/types/funcdef.cpp
	croc/types/function.cpp
	croc/types/instance.cpp
	croc/types/memblock.cpp
	croc/types/namespace.cpp
	croc/types/string.cpp
	croc/types/table.cpp
	croc/types/thread.cpp
	croc/types/weakref.cpp
	croc/utf.cpp
	croc/utf.hpp
	croc/utils.cpp
	croc/utils.hpp
)

set(croc_API
	croc/api.h
	croc/apifuncs.h
	croc/apitypes.h
	croc/apiex.h
)

set(croc_ALLSRC
	${croc_SRC}
	${croc_API}
)

if(CMAKE_COMPILER_IS_GNUCXX)
	set(CMAKE_CXX_FLAGS "-std=c++11 -pedantic-errors -Wall -Wextra -Werror -fno-exceptions -Wno-pedantic-ms-format")
	set(CMAKE_CXX_FLAGS_DEBUG "-g -DCROC_STOMP_MEMORY -DCROC_LEAK_DETECTOR")
	set(CMAKE_CXX_FLAGS_RELEASE "-fno-rtti")
elseif(MSVC)
	message(FATAL_ERROR "VC not supported yet")
else()
	message(FATAL_ERROR "Dunno what compiler you have but I don't support it")
endif()

add_library(croc ${croc_ALLSRC})