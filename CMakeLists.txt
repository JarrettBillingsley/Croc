cmake_minimum_required(VERSION 2.8)

project(croctest CXX)

include_directories("${PROJECT_SOURCE_DIR}/src")
add_subdirectory(src)

add_executable(croctest croctest.cpp)
target_link_libraries(croctest croc)

if(CMAKE_COMPILER_IS_GNUCC)
	set(CMAKE_CXX_FLAGS "-std=c++98 -pedantic-errors -Wall -Wextra -Werror -fno-exceptions")
	set(CMAKE_CXX_FLAGS_DEBUG "-g")
	set(CMAKE_CXX_FLAGS_RELEASE "-fno-rtti")
elseif(MSVC)
	message(FATAL_ERROR "VC not supported yet")
endif()