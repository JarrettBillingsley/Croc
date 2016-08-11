cmake_minimum_required(VERSION 2.8)

if(NOT DEFINED CROC_BUILD_BITS)
	if(CMAKE_SIZEOF_VOID_P EQUAL 8)
		set(CROC_BUILD_BITS 64)
	else()
		set(CROC_BUILD_BITS 32)
	endif()
endif()

set(croc_SRC
	croc/base/darray.hpp
	croc/base/sanity.hpp
	croc/compiler/ast.cpp
	croc/compiler/ast.hpp
	croc/compiler/astvisitor.cpp
	croc/compiler/astvisitor.hpp
	croc/compiler/lexer.cpp
	croc/compiler/lexer.hpp
	croc/compiler/luagenvisitor.cpp
	croc/compiler/luagenvisitor.hpp
	croc/compiler/parser.cpp
	croc/compiler/parser.hpp
	croc/compiler/types.hpp
	croc/compiler/types.cpp
	croc/util/misc.cpp
	croc/util/misc.hpp
	croc/util/utf.cpp
	croc/util/utf.hpp
)

if(CMAKE_COMPILER_IS_GNUCXX)
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11 -pedantic-errors -Wall -Wextra -Werror")
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fmax-errors=2 -m${CROC_BUILD_BITS}")
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DCROC_BUILD_BITS=${CROC_BUILD_BITS}")

	if(CROC_BUILD_SHARED AND WIN32)
		set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DCROCAPI=__declspec(dllexport)")
	else()
		set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DCROCAPI=extern")
	endif()

	if(CROC_BUILD_BITS EQUAL 32 AND CMAKE_SIZEOF_VOID_P EQUAL 8)
		set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Xlinker \"-melf_i386\" -Xlinker \"--oformat=elf32-i386\"")
	endif()

	if(MINGW)
		set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-pedantic-ms-format")
	endif()

	set(CROC_ADDON_FLAGS "")

	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${CROC_ADDON_FLAGS}")
	set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3")
elseif(MSVC)
	message(FATAL_ERROR "VC not supported yet")
else()
	message(FATAL_ERROR "Dunno what compiler you have but I don't support it")
endif()

if(CROC_BUILD_SHARED)
	add_library(croc SHARED ${croc_SRC})
else()
	add_library(croc STATIC ${croc_SRC})
endif()

# TODO: post-build step that copies the shared lib into the executable directory?