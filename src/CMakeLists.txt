cmake_minimum_required(VERSION 2.8)

set(croc_SRC
	croc/api/array.cpp
	croc/api/basic.cpp
	croc/api/calls.cpp
	croc/api/class.cpp
	croc/api/compiler.cpp
	croc/api/debug.cpp
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
	croc/compiler/ast.cpp
	croc/compiler/ast.hpp
	croc/compiler/astvisitor.cpp
	croc/compiler/astvisitor.hpp
	croc/compiler/builder.cpp
	croc/compiler/builder.hpp
	croc/compiler/codegen.cpp
	croc/compiler/codegen.hpp
	croc/compiler/lexer.cpp
	croc/compiler/lexer.hpp
	croc/compiler/parser.cpp
	croc/compiler/parser.hpp
	croc/compiler/semantic.cpp
	croc/compiler/semantic.hpp
	croc/compiler/types.hpp
	croc/compiler/types.cpp
	croc/ex/common.cpp
	croc/ex/imports.cpp
	croc/ex/library.cpp
	croc/ex/paramchecks.cpp
	croc/ex/strbuffer.cpp
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
	croc/internal/format.cpp
	croc/internal/format.hpp
	croc/internal/gc.cpp
	croc/internal/gc.hpp
	croc/internal/interpreter.cpp
	croc/internal/interpreter.hpp
	croc/internal/stack.cpp
	croc/internal/stack.hpp
	croc/internal/thread.cpp
	croc/internal/thread.hpp
	croc/internal/variables.cpp
	croc/internal/variables.hpp
	croc/stdlib/all.hpp
	croc/stdlib/misc.cpp
	croc/stdlib/misc_vector.cpp
	croc/stdlib/exceptions.cpp
	croc/stdlib/gc.cpp
	croc/stdlib/hash.cpp
	croc/stdlib/math.cpp
	croc/stdlib/modules.cpp
	croc/stdlib/object.cpp
	croc/stdlib/string.cpp
	croc/stdlib/string_stringbuffer.cpp
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
	croc/util/misc.cpp
	croc/util/misc.hpp
	croc/util/rng.cpp
	croc/util/rng.hpp
	croc/util/str.cpp
	croc/util/str.hpp
	croc/util/utf.cpp
	croc/util/utf.hpp
)

set(croc_CROCSRC
	croc/stdlib/hash_weaktables.croc
)

set(croc_API
	croc/api.h
	croc/apifuncs.h
	croc/apitypes.h
	croc/apiex.h
)

set(croc_CROCSRC_CONVERTED)

add_executable(convert croc/ext/convert.cpp)

foreach(crocsrc ${croc_CROCSRC})
	set(infile "${CMAKE_CURRENT_SOURCE_DIR}/${crocsrc}")
	set(outfile "${CMAKE_CURRENT_BINARY_DIR}/${crocsrc}.hpp")

	if(MINGW)
		# CMake bug 5939: http://www.cmake.org/Bug/view.php?id=5939
		string(REGEX REPLACE "/" "\\\\" infileNative "${infile}")
		string(REGEX REPLACE "/" "\\\\" outfileNative "${outfile}")
	else()
		set(infileNative "${infile}")
		set(outfileNative "${outfile}")
	endif()

	get_filename_component(outpath "${outfileNative}" PATH)
	message("outpath: ${outpath}")
	file(MAKE_DIRECTORY "${outpath}")

	# message("in: ${infileNative}, out: ${outfileNative}")
	add_custom_command(
		OUTPUT ${outfile}
		COMMAND convert ${infileNative} > ${outfileNative}
		DEPENDS ${infile} convert
		COMMENT "Converting ${infileNative}, output ${outfileNative}"
	)
	list(APPEND croc_CROCSRC_CONVERTED "${outfile}")
endforeach()

include_directories("${CMAKE_CURRENT_BINARY_DIR}")
add_custom_target(ConvertCrocFiles ALL DEPENDS ${croc_CROCSRC_CONVERTED})

set(croc_ALLSRC
	${croc_SRC}
	${croc_API}
	${croc_CROCSRC_CONVERTED}
)

if(CMAKE_COMPILER_IS_GNUCXX)
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11 -pedantic-errors -Wall -Wextra -Werror -fno-exceptions -Wno-pedantic-ms-format -fmax-errors=2")
	set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -DCROC_STOMP_MEMORY -DCROC_LEAK_DETECTOR")
	set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -fno-rtti -O3")
elseif(MSVC)
	message(FATAL_ERROR "VC not supported yet")
else()
	message(FATAL_ERROR "Dunno what compiler you have but I don't support it")
endif()

add_library(croc ${croc_ALLSRC})