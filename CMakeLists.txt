cmake_minimum_required(VERSION 2.8)

project(croctest CXX)

include_directories("${PROJECT_SOURCE_DIR}/src")
add_subdirectory(src)

add_executable(croctest croctest.cpp)
target_link_libraries(croctest croc)

add_executable(croci croc.cpp)
target_link_libraries(croci croc)
set_property(TARGET croci PROPERTY OUTPUT_NAME "croc")

if(NOT DEFINED CROC_BUILD_BITS)
	set(CROC_BUILD_BITS 32)
endif()

if(CMAKE_COMPILER_IS_GNUCXX)
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11 -pedantic-errors -Wall -Wextra -Werror -fno-exceptions")
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fmax-errors=2 -m${CROC_BUILD_BITS}")

	if(CROC_BUILD_BITS EQUAL 32 AND CMAKE_SIZEOF_VOID_P EQUAL 8)
		set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Xlinker \"-melf_i386\" -Xlinker \"--oformat=elf32-i386\"")
	endif()

	if(MINGW)
		set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-pedantic-ms-format")
	endif()

	set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -fno-rtti -O3")
elseif(MSVC)
	message(FATAL_ERROR "VC not supported yet")
else()
	message(FATAL_ERROR "Dunno what compiler you have but I don't support it")
endif()