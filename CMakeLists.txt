cmake_minimum_required(VERSION 2.8)

project(croctest CXX)

include_directories("${PROJECT_SOURCE_DIR}/src")
add_subdirectory(src)

add_executable(croctest croctest.cpp)
target_link_libraries(croctest croc)

if(CMAKE_COMPILER_IS_GNUCXX)
	set(CMAKE_CXX_FLAGS "-std=c++11 -pedantic-errors -Wall -Wextra -Werror -fno-exceptions -Wno-pedantic-ms-format -fmax-errors=2")
	set(CMAKE_CXX_FLAGS_DEBUG "-g -DCROC_STOMP_MEMORY -DCROC_LEAK_DETECTOR")
	set(CMAKE_CXX_FLAGS_RELEASE "-fno-rtti")
elseif(MSVC)
	message(FATAL_ERROR "VC not supported yet")
else()
	message(FATAL_ERROR "Dunno what compiler you have but I don't support it")
endif()