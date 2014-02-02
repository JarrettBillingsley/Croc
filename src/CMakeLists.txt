cmake_minimum_required(VERSION 2.8)

set(croc_SRC
	croc/base/darray.hpp
	croc/base/deque.cpp
	croc/base/deque.hpp
	croc/base/hash.hpp
	croc/base/leakdetector.hpp
	croc/base/leakdetector.cpp
	croc/base/memory.hpp
	croc/base/memory.cpp
	croc/base/metamethods.cpp
	croc/base/metamethods.hpp
	croc/base/opcodes.cpp
	croc/base/opcodes.hpp
	croc/base/writebarrier.cpp
	croc/base/writebarrier.hpp
	croc/base/sanity.hpp
	croc/ext/jhash.cpp
	croc/ext/jhash.hpp
	croc/types/array.cpp
	croc/types/array.hpp
	croc/types/class.cpp
	croc/types/class.hpp
	croc/types/funcdef.cpp
	croc/types/funcdef.hpp
	croc/types/function.cpp
	croc/types/function.hpp
	croc/types/instance.cpp
	croc/types/instance.hpp
	croc/types/memblock.cpp
	croc/types/memblock.hpp
	croc/types/namespace.cpp
	croc/types/namespace.hpp
	croc/types/string.cpp
	croc/types/string.hpp
	croc/types/table.cpp
	croc/types/table.hpp
	croc/types/thread.cpp
	croc/types/thread.hpp
	croc/types.cpp
	croc/types.hpp
	croc/utf.cpp
	croc/utf.hpp
	croc/utils.cpp
	croc/utils.hpp
)

set(croc_API
	croc/apitypes.h
)

set(croc_ALLSRC
	${croc_SRC}
	${croc_API}
)

if(CMAKE_COMPILER_IS_GNUCXX)
	message(status "wtf")
	set(CMAKE_CXX_FLAGS "-std=c++11 -pedantic-errors -Wall -Wextra -Werror -fno-exceptions")
	set(CMAKE_CXX_FLAGS_DEBUG "-g -DCROC_STOMP_MEMORY -DCROC_LEAK_DETECTOR")
	set(CMAKE_CXX_FLAGS_RELEASE "-fno-rtti")
elseif(MSVC)
	message(FATAL_ERROR "VC not supported yet")
else()
	message(FATAL_ERROR "Dunno what compiler you have but I don't support it")
endif()

add_library(croc ${croc_ALLSRC})