cmake_minimum_required(VERSION 2.8)

set(croc_SRC
	croc/base/alloc.hpp
	croc/base/darray.hpp
	croc/base/deque.cpp
	croc/base/deque.hpp
	croc/base/hash.hpp
	croc/base/metamethods.cpp
	croc/base/metamethods.hpp
	croc/base/opcodes.cpp
	croc/base/opcodes.hpp
	croc/base/sanity.hpp
	croc/ext/jhash.cpp
	croc/ext/jhash.hpp
	croc/types/array.cpp
	croc/types/array.hpp
	croc/types.cpp
	croc/types.hpp
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

if(CMAKE_COMPILER_IS_GNUCC)
	set(CMAKE_CXX_FLAGS "-std=c++98 -pedantic-errors -Wall -Wextra -Werror -fno-exceptions")
	set(CMAKE_CXX_FLAGS_DEBUG "-g -DCROC_STOMP_MEMORY -DCROC_LEAK_DETECTOR")
	set(CMAKE_CXX_FLAGS_RELEASE "-fno-rtti")
elseif(MSVC)
	message(FATAL_ERROR "VC not supported yet")
endif()

add_library(croc ${croc_ALLSRC})