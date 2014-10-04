#include <type_traits>
#include <tuple>

#include "croc/ext/glad/glad.hpp"

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

/*
Problematic APIs
----------------

Following are wrapped, but don't present the nicest API, or can't be used properly:
	// Take output string buffers
	GLuint glGetDebugMessageLog(GLuint, GLsizei, GLenum*, GLenum*, GLuint*, GLenum*, GLsizei*, GLchar*);
	GLuint glGetDebugMessageLogARB(GLuint, GLsizei, GLenum*, GLenum*, GLuint*, GLenum*, GLsizei*, GLchar*);
	void   glGetPerfMonitorCounterStringAMD(GLuint, GLuint, GLsizei, GLsizei*, GLchar*);
	void   glGetPerfMonitorGroupStringAMD(GLuint, GLsizei, GLsizei*, GLchar*);

Following are not wrapped at all:
	// Redundant?
	void glMultiDrawElements(GLenum, const GLsizei*, GLenum, const void**, GLsizei);
	void glMultiDrawElementsBaseVertex(GLenum, const GLsizei*, GLenum, const void**, GLsizei, const GLint*);

	// Return GLsync
	GLsync glFenceSync(GLenum, GLbitfield);
	GLsync glCreateSyncFromCLeventARB(struct _cl_context*, struct _cl_event*, GLbitfield);

	// Return pointers whose size cannot necessarily be determined
	void glGetPointerv(GLenum, void**);
	void glGetPointeri_vEXT(GLenum, GLuint, void**);
	void glGetPointerIndexedvEXT(GLenum, GLuint, void**);
	void glGetVertexArrayPointeri_vEXT(GLuint, GLuint, GLenum, void**);
	void glGetVertexArrayPointervEXT(GLuint, GLenum, void**);
	void glGetBufferPointerv(GLenum, GLenum, void**);
	void glGetNamedBufferPointerv(GLuint, GLenum, void**);
	void glGetNamedBufferPointervEXT(GLuint, GLenum, void**);
	void* glMapTexture2DINTEL(GLuint, GLint, GLbitfield, GLint*, GLenum*);
*/

namespace croc
{
namespace
{

#ifdef CROC_BUILTIN_DOCS
const char* moduleDocs = DModule("gl")
R"(OpenGL is a popular cross-platform API for rendering real-time 3D graphics. This module provides a relatively thin,
unsafe wrapper over an OpenGL Core context, as well as a number of extensions.

Core contexts require OpenGL 3.0+ hardware (roughly equivalent to DirectX 10+). The choice to support only core contexts
was made partly because the entire OpenGL Compatibility API is enormous and partly because let's be honest, it's been
the better part of a decade since pre-OpenGL 3.0 hardware was manufactured. It's time to let go.

If it didn't sink in before: \b{this library is very unsafe!} In order to preserve as much performance as possible, no
parameter validation (beyond typechecking) is performed. Furthermore, pointer parameters are very free in what they will
accept and you can pass arbitrary integers to them. For some functions, this is necessary, but for others, this will
just crash the host. Lastly, if you destroy the context from which the functions were loaded, chances are that calling
them will \em{also} cause crashes.

\b{Prerequisites}

This module is currently loaded by the \link{glfw} addon by initializing it, creating a window, making that window's
context current, and then calling \link{glfw.loadOpenGL}. There is currently no other way to load this library.

Once the above has been done, it can be accessed like any other module.

\b{OpenGL Versions}

This library supports up to and including OpenGL 4.5. It also supports many forward-compatibility ("Core Extensions").
A list of supported extensions is given \link[ext]{here}.

\b{Type Constants}

Many OpenGL APIs take blobs of typed memory. The most obvious Croc type to use for this is the \link{Vector} class. To
make it easier to create \tt{Vectors} with the right types of values, there are string constants which hold \tt{Vector}
type codes for each of the OpenGL basic types. These include \tt{GLenum}, \tt{GLboolean}, \tt{GLbitfield}, \tt{GLbyte},
tt{GLshort}, \tt{GLint}, \tt{GLubyte}, \tt{GLushort}, \tt{GLuint}, \tt{GLsizei}, \tt{GLfloat}, \tt{GLclampf},
\tt{GLdouble}, and \tt{GLclampd}. To use, just pass them as the type code when creating a \tt{Vector}:

\code
// creates a Vector to be used as a 4x4 matrix
local matrix = Vector(gl.GLfloat, 16)
// here we'd fill the matrix with values...
// now we can pass the matrix to OpenGL by using its getMemblock method
gl.glUniformMatrix4fv(myUniform, 1, false, matrix.getMemblock())
\endcode

In addition, there are integer constants for the byte size of each OpenGL basic type. These are named \tt{sizeof<type>},
like \tt{sizeofGLenum}, \tt{sizeofGLboolean}, and so on.

\b{\tt{glGen*} and \tt{glDelete*} functions}

The native versions of these functions (such as \tt{glGenBuffers}, \tt{glDeleteBuffers} etc.) take arrays of GLuints
which will be filled with names or which contain names to be deleted. This way of doing things would be awkward in Croc,
so instead these families of functions have been wrapped to be more Croc-friendly.

All the \tt{glGen*} functions effectively have the signature \tt{glGenWhatever(num: int, arr: array = null)}. \tt{num}
indicates how many names to generate. \tt{arr} is an optional array to put the names into. If you pass nothing for
\tt{arr}, \tt{num} cannot exceed 20, and the generated names will be returned as multiple values. If you pass an array
for \tt{arr}, \tt{num} cannot exceed 1024, \tt{arr} will be resized to \tt{num} elements, the names will be placed in
\tt{arr}, and \tt{arr} will be returned. For example:

\code
// generate 1 buffer
local buf = gl.glGenBuffers(1)

// generate 3 buffers
local b1, b2, b3 = gl.glGenBuffers(3)

// generate 10 buffers, put them in the given array, and put that array in 'names'
local names = gl.glGenBuffers(10, [])
\endcode

All the \tt{glDelete*} functions can be called one of two ways. One, you can pass a single array containing the names
to delete; this array cannot exceed 1024 elements and all the elements must be integers. Two, you can pass between 1 and
1024 names as separate parameters to the function. To continue the above example:

\code
// delete the array of names
gl.glDeleteBuffers(names)

// delete 4 buffers at once
gl.glDeleteBuffers(b1, b2, b3, buf)
\endcode

The following pairs of \tt{glGen*}/\tt{glDelete*} functions work like this:

\blist
	\li \tt{glGenTextures}/\tt{glDeleteTextures}
	\li \tt{glGenQueries}/\tt{glDeleteQueries}
	\li \tt{glGenBuffers}/\tt{glDeleteBuffers}
	\li \tt{glGenRenderbuffers}/\tt{glDeleteRenderbuffers}
	\li \tt{glGenFramebuffers}/\tt{glDeleteFramebuffers}
	\li \tt{glGenVertexArrays}/\tt{glDeleteVertexArrays}
	\li \tt{glGenSamplers}/\tt{glDeleteSamplers}
	\li \tt{glGenTransformFeedbacks}/\tt{glDeleteTransformFeedbacks}
	\li \tt{glGenProgramPipelines}/\tt{glDeleteProgramPipelines}
	\li \tt{glGenPerfMonitorsAMD}/\tt{glDeletePerfMonitorsAMD}
	\li \tt{glGenSamplers}/\tt{glDeleteSamplers}
	\li \tt{glGenProgramPipelines}/\tt{glDeleteProgramPipelines}
	\li \tt{glGenTransformFeedbacks}/\tt{glDeleteTransformFeedbacks}
\endlist

\b{Ugly APIs}

At present there are only a handful of APIs which are ugly to use from Croc, and they're all ugly since they take an
output string buffer. You can use these by passing an appropriately-sized memblock and then decoding the text with the
\tt{text} library, but it's not the prettiest interface. It's recommended that you wrap these functions in your own.

\blist
	\li \tt{glGetDebugMessageLog}
	\li \tt{glGetDebugMessageLogARB}
	\li \tt{glGetPerfMonitorCounterStringAMD}
	\li \tt{glGetPerfMonitorGroupStringAMD}
\endlist

\b{Unsupported APIs}

At present there are a number of APIs which are not available for one reason or another.

\tt{glMultiDrawElements} and \tt{glMultiDrawElementsBaseVertex} are not wrapped because they take arrays of pointers
(tricky to deal with), and all they're likely to do is just iterate over those arrays and call \tt{glDrawElements} and
\tt{glDrawElementsBaseVertex} anyway. And you can do that yourself.

\tt{glFenceSync} and \tt{glCreateSyncFromCLeventARB} are not wrapped because they return \tt{GLsync*} and I don't really
know what that is. Is it treated as an opaque pointer? Please let me know!

Lastly we have functions which return pointers whose size cannot be determined. Several functions return pointers, but
the size of the memory block they point to can be determined, and so those functions return memblocks. No such luck with
these functions. I'm not sure how to handle these (and for that matter, some of these seem to have zero documentation
anywhere, so I don't even know how to begin).

\blist
	\li \tt{glGetPointerv}
	\li \tt{glGetPointeri_vEXT}
	\li \tt{glGetPointerIndexedvEXT}
	\li \tt{glGetVertexArrayPointeri_vEXT}
	\li \tt{glGetVertexArrayPointervEXT}
	\li \tt{glGetBufferPointerv}
	\li \tt{glGetNamedBufferPointerv}
	\li \tt{glGetNamedBufferPointervEXT}
	\li \tt{glMapTexture2DINTEL}
\endlist

\b{Most APIs}

Most APIs look and act exactly like their native counterparts. I'm not going to list every wrapped function and its
signature; you can look at \link[https://www.opengl.org/sdk/docs/man/]{the OpenGL reference} for that. What you need to
know is how the parameter and return types of these functions map to Croc.

For parameters:

\table
	\row
		\cell \b{Original OpenGL Type}
		\cell \b{Croc Type}
	\row
		\cell \tt{GLboolean}
		\cell \tt{bool}
	\row
		\cell \tt{GLenum}, \tt{GLbitfield}, \tt{GLbyte}, \tt{GLshort}, \tt{GLushort}, \tt{GLint}, \tt{GLuint},
			\tt{GLsizei}
		\cell \tt{int}
	\row
		\cell \tt{GLfloat}, \tt{GLclampf}, \tt{GLdouble}, \tt{GLclampd}
		\cell \tt{int|float}
	\row
		\cell \tt{const GLchar*}
		\cell \tt{string}
	\row
		\cell Any other pointer
		\cell \tt{null|int|memblock}
\endtable

The last row bears explanation. For non-string pointer parameters, you can pass \tt{null} (which means... null), a
memblock, or an integer. Some APIs, like \tt{glVertexAttribPointer}, double up the meaning of their pointer parameters
and allow integers instead of "actual" pointers.

If you pass a memblock, keep in mind that OpenGL \em{will not keep a reference to your memblock}, so you are responsible
for making sure it doesn't get collected while OpenGL is still using it. Most of the time this isn't a problem, since a
lot of APIs which take pointers copy the data out of them, but it's something to keep in mind.

For return types: mostly the same. Some OpenGL APIs take output string buffers; these functions have instead been
wrapped so they return a string (all other parameters are unaffected), or \tt{null} if an error occurs. These functions
include:

\blist
	\li \tt{glGetProgramInfoLog}
	\li \tt{glGetShaderInfoLog}
	\li \tt{glGetShaderSource}
	\li \tt{glGetActiveUniformName}
	\li \tt{glGetActiveUniformBlockName}
	\li \tt{glGetActiveSubroutineUniformName}
	\li \tt{glGetActiveSubroutineName}
	\li \tt{glGetProgramPipelineInfoLog}
	\li \tt{glGetProgramResourceName}
	\li \tt{glGetObjectLabel}
	\li \tt{glGetObjectPtrLabel}
	\li \tt{glGetNamedStringARB}
\endlist

Any other functions whose signatures are different will be explained on a function-by-function basis.
)";
#endif

template<typename T, typename Enable = void>
struct GLTypeString
{};

template<typename T>
struct GLTypeString<T, typename std::enable_if<std::is_integral<T>::value && std::is_unsigned<T>::value>::type>
{
	static constexpr const char* value =
		(sizeof(T) == 1) ? "u8" :
		(sizeof(T) == 2) ? "u16" :
		(sizeof(T) == 4) ? "u32" :
		"u64";
};

template<typename T>
struct GLTypeString<T, typename std::enable_if<std::is_integral<T>::value && std::is_signed<T>::value>::type>
{
	static constexpr const char* value =
		(sizeof(T) == 1) ? "i8" :
		(sizeof(T) == 2) ? "i16" :
		(sizeof(T) == 4) ? "i32" :
		"i64";
};

template<typename T>
struct GLTypeString<T, typename std::enable_if<std::is_floating_point<T>::value>::type>
{
	static constexpr const char* value =
		(sizeof(T) == 4) ? "f32" :
		"f64";
};

#define GLCONST(c) croc_pushInt(t, c); croc_newGlobal(t, #c);

void loadConstants(CrocThread* t)
{
	croc_pushString(t, GLTypeString<GLenum>::value);     croc_newGlobal(t, "GLenum");
	croc_pushString(t, GLTypeString<GLboolean>::value);  croc_newGlobal(t, "GLboolean");
	croc_pushString(t, GLTypeString<GLbitfield>::value); croc_newGlobal(t, "GLbitfield");
	croc_pushString(t, GLTypeString<GLbyte>::value);     croc_newGlobal(t, "GLbyte");
	croc_pushString(t, GLTypeString<GLshort>::value);    croc_newGlobal(t, "GLshort");
	croc_pushString(t, GLTypeString<GLint>::value);      croc_newGlobal(t, "GLint");
	croc_pushString(t, GLTypeString<GLubyte>::value);    croc_newGlobal(t, "GLubyte");
	croc_pushString(t, GLTypeString<GLushort>::value);   croc_newGlobal(t, "GLushort");
	croc_pushString(t, GLTypeString<GLuint>::value);     croc_newGlobal(t, "GLuint");
	croc_pushString(t, GLTypeString<GLsizei>::value);    croc_newGlobal(t, "GLsizei");
	croc_pushString(t, GLTypeString<GLfloat>::value);    croc_newGlobal(t, "GLfloat");
	croc_pushString(t, GLTypeString<GLclampf>::value);   croc_newGlobal(t, "GLclampf");
	croc_pushString(t, GLTypeString<GLdouble>::value);   croc_newGlobal(t, "GLdouble");
	croc_pushString(t, GLTypeString<GLclampd>::value);   croc_newGlobal(t, "GLclampd");

	croc_pushInt(t, sizeof(GLenum));     croc_newGlobal(t, "sizeofGLenum");
	croc_pushInt(t, sizeof(GLboolean));  croc_newGlobal(t, "sizeofGLboolean");
	croc_pushInt(t, sizeof(GLbitfield)); croc_newGlobal(t, "sizeofGLbitfield");
	croc_pushInt(t, sizeof(GLbyte));     croc_newGlobal(t, "sizeofGLbyte");
	croc_pushInt(t, sizeof(GLshort));    croc_newGlobal(t, "sizeofGLshort");
	croc_pushInt(t, sizeof(GLint));      croc_newGlobal(t, "sizeofGLint");
	croc_pushInt(t, sizeof(GLubyte));    croc_newGlobal(t, "sizeofGLubyte");
	croc_pushInt(t, sizeof(GLushort));   croc_newGlobal(t, "sizeofGLushort");
	croc_pushInt(t, sizeof(GLuint));     croc_newGlobal(t, "sizeofGLuint");
	croc_pushInt(t, sizeof(GLsizei));    croc_newGlobal(t, "sizeofGLsizei");
	croc_pushInt(t, sizeof(GLfloat));    croc_newGlobal(t, "sizeofGLfloat");
	croc_pushInt(t, sizeof(GLclampf));   croc_newGlobal(t, "sizeofGLclampf");
	croc_pushInt(t, sizeof(GLdouble));   croc_newGlobal(t, "sizeofGLdouble");
	croc_pushInt(t, sizeof(GLclampd));   croc_newGlobal(t, "sizeofGLclampd");

	croc_pushBool(t, GL_TRUE);  croc_newGlobal(t, "GL_TRUE");
	croc_pushBool(t, GL_FALSE); croc_newGlobal(t, "GL_FALSE");

	GLCONST(GL_DEPTH_BUFFER_BIT);                                           GLCONST(GL_STENCIL_BUFFER_BIT);
	GLCONST(GL_COLOR_BUFFER_BIT);                                           GLCONST(GL_POINTS);
	GLCONST(GL_LINES);                                                      GLCONST(GL_LINE_LOOP);
	GLCONST(GL_LINE_STRIP);                                                 GLCONST(GL_TRIANGLES);
	GLCONST(GL_TRIANGLE_STRIP);                                             GLCONST(GL_TRIANGLE_FAN);
	GLCONST(GL_NEVER);                                                      GLCONST(GL_LESS);
	GLCONST(GL_EQUAL);                                                      GLCONST(GL_LEQUAL);
	GLCONST(GL_GREATER);                                                    GLCONST(GL_NOTEQUAL);
	GLCONST(GL_GEQUAL);                                                     GLCONST(GL_ALWAYS);
	GLCONST(GL_ZERO);                                                       GLCONST(GL_ONE);
	GLCONST(GL_SRC_COLOR);                                                  GLCONST(GL_ONE_MINUS_SRC_COLOR);
	GLCONST(GL_SRC_ALPHA);                                                  GLCONST(GL_ONE_MINUS_SRC_ALPHA);
	GLCONST(GL_DST_ALPHA);                                                  GLCONST(GL_ONE_MINUS_DST_ALPHA);
	GLCONST(GL_DST_COLOR);                                                  GLCONST(GL_ONE_MINUS_DST_COLOR);
	GLCONST(GL_SRC_ALPHA_SATURATE);                                         GLCONST(GL_NONE);
	GLCONST(GL_FRONT_LEFT);                                                 GLCONST(GL_FRONT_RIGHT);
	GLCONST(GL_BACK_LEFT);                                                  GLCONST(GL_BACK_RIGHT);
	GLCONST(GL_FRONT);                                                      GLCONST(GL_BACK);
	GLCONST(GL_LEFT);                                                       GLCONST(GL_RIGHT);
	GLCONST(GL_FRONT_AND_BACK);                                             GLCONST(GL_NO_ERROR);
	GLCONST(GL_INVALID_ENUM);                                               GLCONST(GL_INVALID_VALUE);
	GLCONST(GL_INVALID_OPERATION);                                          GLCONST(GL_OUT_OF_MEMORY);
	GLCONST(GL_CW);                                                         GLCONST(GL_CCW);
	GLCONST(GL_POINT_SIZE);                                                 GLCONST(GL_POINT_SIZE_RANGE);
	GLCONST(GL_POINT_SIZE_GRANULARITY);                                     GLCONST(GL_LINE_SMOOTH);
	GLCONST(GL_LINE_WIDTH);                                                 GLCONST(GL_LINE_WIDTH_RANGE);
	GLCONST(GL_LINE_WIDTH_GRANULARITY);                                     GLCONST(GL_POLYGON_MODE);
	GLCONST(GL_POLYGON_SMOOTH);                                             GLCONST(GL_CULL_FACE);
	GLCONST(GL_CULL_FACE_MODE);                                             GLCONST(GL_FRONT_FACE);
	GLCONST(GL_DEPTH_RANGE);                                                GLCONST(GL_DEPTH_TEST);
	GLCONST(GL_DEPTH_WRITEMASK);                                            GLCONST(GL_DEPTH_CLEAR_VALUE);
	GLCONST(GL_DEPTH_FUNC);                                                 GLCONST(GL_STENCIL_TEST);
	GLCONST(GL_STENCIL_CLEAR_VALUE);                                        GLCONST(GL_STENCIL_FUNC);
	GLCONST(GL_STENCIL_VALUE_MASK);                                         GLCONST(GL_STENCIL_FAIL);
	GLCONST(GL_STENCIL_PASS_DEPTH_FAIL);                                    GLCONST(GL_STENCIL_PASS_DEPTH_PASS);
	GLCONST(GL_STENCIL_REF);                                                GLCONST(GL_STENCIL_WRITEMASK);
	GLCONST(GL_VIEWPORT);                                                   GLCONST(GL_DITHER);
	GLCONST(GL_BLEND_DST);                                                  GLCONST(GL_BLEND_SRC);
	GLCONST(GL_BLEND);                                                      GLCONST(GL_LOGIC_OP_MODE);
	GLCONST(GL_COLOR_LOGIC_OP);                                             GLCONST(GL_DRAW_BUFFER);
	GLCONST(GL_READ_BUFFER);                                                GLCONST(GL_SCISSOR_BOX);
	GLCONST(GL_SCISSOR_TEST);                                               GLCONST(GL_COLOR_CLEAR_VALUE);
	GLCONST(GL_COLOR_WRITEMASK);                                            GLCONST(GL_DOUBLEBUFFER);
	GLCONST(GL_STEREO);                                                     GLCONST(GL_LINE_SMOOTH_HINT);
	GLCONST(GL_POLYGON_SMOOTH_HINT);                                        GLCONST(GL_UNPACK_SWAP_BYTES);
	GLCONST(GL_UNPACK_LSB_FIRST);                                           GLCONST(GL_UNPACK_ROW_LENGTH);
	GLCONST(GL_UNPACK_SKIP_ROWS);                                           GLCONST(GL_UNPACK_SKIP_PIXELS);
	GLCONST(GL_UNPACK_ALIGNMENT);                                           GLCONST(GL_PACK_SWAP_BYTES);
	GLCONST(GL_PACK_LSB_FIRST);                                             GLCONST(GL_PACK_ROW_LENGTH);
	GLCONST(GL_PACK_SKIP_ROWS);                                             GLCONST(GL_PACK_SKIP_PIXELS);
	GLCONST(GL_PACK_ALIGNMENT);                                             GLCONST(GL_MAX_TEXTURE_SIZE);
	GLCONST(GL_MAX_VIEWPORT_DIMS);                                          GLCONST(GL_SUBPIXEL_BITS);
	GLCONST(GL_TEXTURE_1D);                                                 GLCONST(GL_TEXTURE_2D);
	GLCONST(GL_POLYGON_OFFSET_UNITS);                                       GLCONST(GL_POLYGON_OFFSET_POINT);
	GLCONST(GL_POLYGON_OFFSET_LINE);                                        GLCONST(GL_POLYGON_OFFSET_FILL);
	GLCONST(GL_POLYGON_OFFSET_FACTOR);                                      GLCONST(GL_TEXTURE_BINDING_1D);
	GLCONST(GL_TEXTURE_BINDING_2D);                                         GLCONST(GL_TEXTURE_WIDTH);
	GLCONST(GL_TEXTURE_HEIGHT);                                             GLCONST(GL_TEXTURE_INTERNAL_FORMAT);
	GLCONST(GL_TEXTURE_BORDER_COLOR);                                       GLCONST(GL_TEXTURE_RED_SIZE);
	GLCONST(GL_TEXTURE_GREEN_SIZE);                                         GLCONST(GL_TEXTURE_BLUE_SIZE);
	GLCONST(GL_TEXTURE_ALPHA_SIZE);                                         GLCONST(GL_DONT_CARE);
	GLCONST(GL_FASTEST);                                                    GLCONST(GL_NICEST);
	GLCONST(GL_BYTE);                                                       GLCONST(GL_UNSIGNED_BYTE);
	GLCONST(GL_SHORT);                                                      GLCONST(GL_UNSIGNED_SHORT);
	GLCONST(GL_INT);                                                        GLCONST(GL_UNSIGNED_INT);
	GLCONST(GL_FLOAT);                                                      GLCONST(GL_DOUBLE);
	GLCONST(GL_CLEAR);                                                      GLCONST(GL_AND);
	GLCONST(GL_AND_REVERSE);                                                GLCONST(GL_COPY);
	GLCONST(GL_AND_INVERTED);                                               GLCONST(GL_NOOP);
	GLCONST(GL_XOR);                                                        GLCONST(GL_OR);
	GLCONST(GL_NOR);                                                        GLCONST(GL_EQUIV);
	GLCONST(GL_INVERT);                                                     GLCONST(GL_OR_REVERSE);
	GLCONST(GL_COPY_INVERTED);                                              GLCONST(GL_OR_INVERTED);
	GLCONST(GL_NAND);                                                       GLCONST(GL_SET);
	GLCONST(GL_TEXTURE);                                                    GLCONST(GL_COLOR);
	GLCONST(GL_DEPTH);                                                      GLCONST(GL_STENCIL);
	GLCONST(GL_STENCIL_INDEX);                                              GLCONST(GL_DEPTH_COMPONENT);
	GLCONST(GL_RED);                                                        GLCONST(GL_GREEN);
	GLCONST(GL_BLUE);                                                       GLCONST(GL_ALPHA);
	GLCONST(GL_RGB);                                                        GLCONST(GL_RGBA);
	GLCONST(GL_POINT);                                                      GLCONST(GL_LINE);
	GLCONST(GL_FILL);                                                       GLCONST(GL_KEEP);
	GLCONST(GL_REPLACE);                                                    GLCONST(GL_INCR);
	GLCONST(GL_DECR);                                                       GLCONST(GL_VENDOR);
	GLCONST(GL_RENDERER);                                                   GLCONST(GL_VERSION);
	GLCONST(GL_EXTENSIONS);                                                 GLCONST(GL_NEAREST);
	GLCONST(GL_LINEAR);                                                     GLCONST(GL_NEAREST_MIPMAP_NEAREST);
	GLCONST(GL_LINEAR_MIPMAP_NEAREST);                                      GLCONST(GL_NEAREST_MIPMAP_LINEAR);
	GLCONST(GL_LINEAR_MIPMAP_LINEAR);                                       GLCONST(GL_TEXTURE_MAG_FILTER);
	GLCONST(GL_TEXTURE_MIN_FILTER);                                         GLCONST(GL_TEXTURE_WRAP_S);
	GLCONST(GL_TEXTURE_WRAP_T);                                             GLCONST(GL_PROXY_TEXTURE_1D);
	GLCONST(GL_PROXY_TEXTURE_2D);                                           GLCONST(GL_REPEAT);
	GLCONST(GL_R3_G3_B2);                                                   GLCONST(GL_RGB4);
	GLCONST(GL_RGB5);                                                       GLCONST(GL_RGB8);
	GLCONST(GL_RGB10);                                                      GLCONST(GL_RGB12);
	GLCONST(GL_RGB16);                                                      GLCONST(GL_RGBA2);
	GLCONST(GL_RGBA4);                                                      GLCONST(GL_RGB5_A1);
	GLCONST(GL_RGBA8);                                                      GLCONST(GL_RGB10_A2);
	GLCONST(GL_RGBA12);                                                     GLCONST(GL_RGBA16);
	GLCONST(GL_UNSIGNED_BYTE_3_3_2);                                        GLCONST(GL_UNSIGNED_SHORT_4_4_4_4);
	GLCONST(GL_UNSIGNED_SHORT_5_5_5_1);                                     GLCONST(GL_UNSIGNED_INT_8_8_8_8);
	GLCONST(GL_UNSIGNED_INT_10_10_10_2);                                    GLCONST(GL_TEXTURE_BINDING_3D);
	GLCONST(GL_PACK_SKIP_IMAGES);                                           GLCONST(GL_PACK_IMAGE_HEIGHT);
	GLCONST(GL_UNPACK_SKIP_IMAGES);                                         GLCONST(GL_UNPACK_IMAGE_HEIGHT);
	GLCONST(GL_TEXTURE_3D);                                                 GLCONST(GL_PROXY_TEXTURE_3D);
	GLCONST(GL_TEXTURE_DEPTH);                                              GLCONST(GL_TEXTURE_WRAP_R);
	GLCONST(GL_MAX_3D_TEXTURE_SIZE);                                        GLCONST(GL_UNSIGNED_BYTE_2_3_3_REV);
	GLCONST(GL_UNSIGNED_SHORT_5_6_5);                                       GLCONST(GL_UNSIGNED_SHORT_5_6_5_REV);
	GLCONST(GL_UNSIGNED_SHORT_4_4_4_4_REV);                                 GLCONST(GL_UNSIGNED_SHORT_1_5_5_5_REV);
	GLCONST(GL_UNSIGNED_INT_8_8_8_8_REV);                                   GLCONST(GL_UNSIGNED_INT_2_10_10_10_REV);
	GLCONST(GL_BGR);                                                        GLCONST(GL_BGRA);
	GLCONST(GL_MAX_ELEMENTS_VERTICES);                                      GLCONST(GL_MAX_ELEMENTS_INDICES);
	GLCONST(GL_CLAMP_TO_EDGE);                                              GLCONST(GL_TEXTURE_MIN_LOD);
	GLCONST(GL_TEXTURE_MAX_LOD);                                            GLCONST(GL_TEXTURE_BASE_LEVEL);
	GLCONST(GL_TEXTURE_MAX_LEVEL);                                          GLCONST(GL_SMOOTH_POINT_SIZE_RANGE);
	GLCONST(GL_SMOOTH_POINT_SIZE_GRANULARITY);                              GLCONST(GL_SMOOTH_LINE_WIDTH_RANGE);
	GLCONST(GL_SMOOTH_LINE_WIDTH_GRANULARITY);                              GLCONST(GL_ALIASED_LINE_WIDTH_RANGE);
	GLCONST(GL_TEXTURE0);                                                   GLCONST(GL_TEXTURE1);
	GLCONST(GL_TEXTURE2);                                                   GLCONST(GL_TEXTURE3);
	GLCONST(GL_TEXTURE4);                                                   GLCONST(GL_TEXTURE5);
	GLCONST(GL_TEXTURE6);                                                   GLCONST(GL_TEXTURE7);
	GLCONST(GL_TEXTURE8);                                                   GLCONST(GL_TEXTURE9);
	GLCONST(GL_TEXTURE10);                                                  GLCONST(GL_TEXTURE11);
	GLCONST(GL_TEXTURE12);                                                  GLCONST(GL_TEXTURE13);
	GLCONST(GL_TEXTURE14);                                                  GLCONST(GL_TEXTURE15);
	GLCONST(GL_TEXTURE16);                                                  GLCONST(GL_TEXTURE17);
	GLCONST(GL_TEXTURE18);                                                  GLCONST(GL_TEXTURE19);
	GLCONST(GL_TEXTURE20);                                                  GLCONST(GL_TEXTURE21);
	GLCONST(GL_TEXTURE22);                                                  GLCONST(GL_TEXTURE23);
	GLCONST(GL_TEXTURE24);                                                  GLCONST(GL_TEXTURE25);
	GLCONST(GL_TEXTURE26);                                                  GLCONST(GL_TEXTURE27);
	GLCONST(GL_TEXTURE28);                                                  GLCONST(GL_TEXTURE29);
	GLCONST(GL_TEXTURE30);                                                  GLCONST(GL_TEXTURE31);
	GLCONST(GL_ACTIVE_TEXTURE);                                             GLCONST(GL_MULTISAMPLE);
	GLCONST(GL_SAMPLE_ALPHA_TO_COVERAGE);                                   GLCONST(GL_SAMPLE_ALPHA_TO_ONE);
	GLCONST(GL_SAMPLE_COVERAGE);                                            GLCONST(GL_SAMPLE_BUFFERS);
	GLCONST(GL_SAMPLES);                                                    GLCONST(GL_SAMPLE_COVERAGE_VALUE);
	GLCONST(GL_SAMPLE_COVERAGE_INVERT);                                     GLCONST(GL_TEXTURE_CUBE_MAP);
	GLCONST(GL_TEXTURE_BINDING_CUBE_MAP);                                   GLCONST(GL_TEXTURE_CUBE_MAP_POSITIVE_X);
	GLCONST(GL_TEXTURE_CUBE_MAP_NEGATIVE_X);                                GLCONST(GL_TEXTURE_CUBE_MAP_POSITIVE_Y);
	GLCONST(GL_TEXTURE_CUBE_MAP_NEGATIVE_Y);                                GLCONST(GL_TEXTURE_CUBE_MAP_POSITIVE_Z);
	GLCONST(GL_TEXTURE_CUBE_MAP_NEGATIVE_Z);                                GLCONST(GL_PROXY_TEXTURE_CUBE_MAP);
	GLCONST(GL_MAX_CUBE_MAP_TEXTURE_SIZE);                                  GLCONST(GL_COMPRESSED_RGB);
	GLCONST(GL_COMPRESSED_RGBA);                                            GLCONST(GL_TEXTURE_COMPRESSION_HINT);
	GLCONST(GL_TEXTURE_COMPRESSED_IMAGE_SIZE);                              GLCONST(GL_TEXTURE_COMPRESSED);
	GLCONST(GL_NUM_COMPRESSED_TEXTURE_FORMATS);                             GLCONST(GL_COMPRESSED_TEXTURE_FORMATS);
	GLCONST(GL_CLAMP_TO_BORDER);                                            GLCONST(GL_BLEND_DST_RGB);
	GLCONST(GL_BLEND_SRC_RGB);                                              GLCONST(GL_BLEND_DST_ALPHA);
	GLCONST(GL_BLEND_SRC_ALPHA);                                            GLCONST(GL_POINT_FADE_THRESHOLD_SIZE);
	GLCONST(GL_DEPTH_COMPONENT16);                                          GLCONST(GL_DEPTH_COMPONENT24);
	GLCONST(GL_DEPTH_COMPONENT32);                                          GLCONST(GL_MIRRORED_REPEAT);
	GLCONST(GL_MAX_TEXTURE_LOD_BIAS);                                       GLCONST(GL_TEXTURE_LOD_BIAS);
	GLCONST(GL_INCR_WRAP);                                                  GLCONST(GL_DECR_WRAP);
	GLCONST(GL_TEXTURE_DEPTH_SIZE);                                         GLCONST(GL_TEXTURE_COMPARE_MODE);
	GLCONST(GL_TEXTURE_COMPARE_FUNC);                                       GLCONST(GL_FUNC_ADD);
	GLCONST(GL_FUNC_SUBTRACT);                                              GLCONST(GL_FUNC_REVERSE_SUBTRACT);
	GLCONST(GL_MIN);                                                        GLCONST(GL_MAX);
	GLCONST(GL_CONSTANT_COLOR);                                             GLCONST(GL_ONE_MINUS_CONSTANT_COLOR);
	GLCONST(GL_CONSTANT_ALPHA);                                             GLCONST(GL_ONE_MINUS_CONSTANT_ALPHA);
	GLCONST(GL_BUFFER_SIZE);                                                GLCONST(GL_BUFFER_USAGE);
	GLCONST(GL_QUERY_COUNTER_BITS);                                         GLCONST(GL_CURRENT_QUERY);
	GLCONST(GL_QUERY_RESULT);                                               GLCONST(GL_QUERY_RESULT_AVAILABLE);
	GLCONST(GL_ARRAY_BUFFER);                                               GLCONST(GL_ELEMENT_ARRAY_BUFFER);
	GLCONST(GL_ARRAY_BUFFER_BINDING);                                       GLCONST(GL_ELEMENT_ARRAY_BUFFER_BINDING);
	GLCONST(GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING);                         GLCONST(GL_READ_ONLY);
	GLCONST(GL_WRITE_ONLY);                                                 GLCONST(GL_READ_WRITE);
	GLCONST(GL_BUFFER_ACCESS);                                              GLCONST(GL_BUFFER_MAPPED);
	GLCONST(GL_BUFFER_MAP_POINTER);                                         GLCONST(GL_STREAM_DRAW);
	GLCONST(GL_STREAM_READ);                                                GLCONST(GL_STREAM_COPY);
	GLCONST(GL_STATIC_DRAW);                                                GLCONST(GL_STATIC_READ);
	GLCONST(GL_STATIC_COPY);                                                GLCONST(GL_DYNAMIC_DRAW);
	GLCONST(GL_DYNAMIC_READ);                                               GLCONST(GL_DYNAMIC_COPY);
	GLCONST(GL_SAMPLES_PASSED);                                             GLCONST(GL_SRC1_ALPHA);
	GLCONST(GL_BLEND_EQUATION_RGB);                                         GLCONST(GL_VERTEX_ATTRIB_ARRAY_ENABLED);
	GLCONST(GL_VERTEX_ATTRIB_ARRAY_SIZE);                                   GLCONST(GL_VERTEX_ATTRIB_ARRAY_STRIDE);
	GLCONST(GL_VERTEX_ATTRIB_ARRAY_TYPE);                                   GLCONST(GL_CURRENT_VERTEX_ATTRIB);
	GLCONST(GL_VERTEX_PROGRAM_POINT_SIZE);                                  GLCONST(GL_VERTEX_ATTRIB_ARRAY_POINTER);
	GLCONST(GL_STENCIL_BACK_FUNC);                                          GLCONST(GL_STENCIL_BACK_FAIL);
	GLCONST(GL_STENCIL_BACK_PASS_DEPTH_FAIL);                               GLCONST(GL_STENCIL_BACK_PASS_DEPTH_PASS);
	GLCONST(GL_MAX_DRAW_BUFFERS);                                           GLCONST(GL_DRAW_BUFFER0);
	GLCONST(GL_DRAW_BUFFER1);                                               GLCONST(GL_DRAW_BUFFER2);
	GLCONST(GL_DRAW_BUFFER3);                                               GLCONST(GL_DRAW_BUFFER4);
	GLCONST(GL_DRAW_BUFFER5);                                               GLCONST(GL_DRAW_BUFFER6);
	GLCONST(GL_DRAW_BUFFER7);                                               GLCONST(GL_DRAW_BUFFER8);
	GLCONST(GL_DRAW_BUFFER9);                                               GLCONST(GL_DRAW_BUFFER10);
	GLCONST(GL_DRAW_BUFFER11);                                              GLCONST(GL_DRAW_BUFFER12);
	GLCONST(GL_DRAW_BUFFER13);                                              GLCONST(GL_DRAW_BUFFER14);
	GLCONST(GL_DRAW_BUFFER15);                                              GLCONST(GL_BLEND_EQUATION_ALPHA);
	GLCONST(GL_MAX_VERTEX_ATTRIBS);                                         GLCONST(GL_VERTEX_ATTRIB_ARRAY_NORMALIZED);
	GLCONST(GL_MAX_TEXTURE_IMAGE_UNITS);                                    GLCONST(GL_FRAGMENT_SHADER);
	GLCONST(GL_VERTEX_SHADER);                                              GLCONST(GL_MAX_FRAGMENT_UNIFORM_COMPONENTS);
	GLCONST(GL_MAX_VERTEX_UNIFORM_COMPONENTS);                              GLCONST(GL_MAX_VARYING_FLOATS);
	GLCONST(GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS);                             GLCONST(GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS);
	GLCONST(GL_SHADER_TYPE);                                                GLCONST(GL_FLOAT_VEC2);
	GLCONST(GL_FLOAT_VEC3);                                                 GLCONST(GL_FLOAT_VEC4);
	GLCONST(GL_INT_VEC2);                                                   GLCONST(GL_INT_VEC3);
	GLCONST(GL_INT_VEC4);                                                   GLCONST(GL_BOOL);
	GLCONST(GL_BOOL_VEC2);                                                  GLCONST(GL_BOOL_VEC3);
	GLCONST(GL_BOOL_VEC4);                                                  GLCONST(GL_FLOAT_MAT2);
	GLCONST(GL_FLOAT_MAT3);                                                 GLCONST(GL_FLOAT_MAT4);
	GLCONST(GL_SAMPLER_1D);                                                 GLCONST(GL_SAMPLER_2D);
	GLCONST(GL_SAMPLER_3D);                                                 GLCONST(GL_SAMPLER_CUBE);
	GLCONST(GL_SAMPLER_1D_SHADOW);                                          GLCONST(GL_SAMPLER_2D_SHADOW);
	GLCONST(GL_DELETE_STATUS);                                              GLCONST(GL_COMPILE_STATUS);
	GLCONST(GL_LINK_STATUS);                                                GLCONST(GL_VALIDATE_STATUS);
	GLCONST(GL_INFO_LOG_LENGTH);                                            GLCONST(GL_ATTACHED_SHADERS);
	GLCONST(GL_ACTIVE_UNIFORMS);                                            GLCONST(GL_ACTIVE_UNIFORM_MAX_LENGTH);
	GLCONST(GL_SHADER_SOURCE_LENGTH);                                       GLCONST(GL_ACTIVE_ATTRIBUTES);
	GLCONST(GL_ACTIVE_ATTRIBUTE_MAX_LENGTH);                                GLCONST(GL_FRAGMENT_SHADER_DERIVATIVE_HINT);
	GLCONST(GL_SHADING_LANGUAGE_VERSION);                                   GLCONST(GL_CURRENT_PROGRAM);
	GLCONST(GL_POINT_SPRITE_COORD_ORIGIN);                                  GLCONST(GL_LOWER_LEFT);
	GLCONST(GL_UPPER_LEFT);                                                 GLCONST(GL_STENCIL_BACK_REF);
	GLCONST(GL_STENCIL_BACK_VALUE_MASK);                                    GLCONST(GL_STENCIL_BACK_WRITEMASK);
	GLCONST(GL_PIXEL_PACK_BUFFER);                                          GLCONST(GL_PIXEL_UNPACK_BUFFER);
	GLCONST(GL_PIXEL_PACK_BUFFER_BINDING);                                  GLCONST(GL_PIXEL_UNPACK_BUFFER_BINDING);
	GLCONST(GL_FLOAT_MAT2x3);                                               GLCONST(GL_FLOAT_MAT2x4);
	GLCONST(GL_FLOAT_MAT3x2);                                               GLCONST(GL_FLOAT_MAT3x4);
	GLCONST(GL_FLOAT_MAT4x2);                                               GLCONST(GL_FLOAT_MAT4x3);
	GLCONST(GL_SRGB);                                                       GLCONST(GL_SRGB8);
	GLCONST(GL_SRGB_ALPHA);                                                 GLCONST(GL_SRGB8_ALPHA8);
	GLCONST(GL_COMPRESSED_SRGB);                                            GLCONST(GL_COMPRESSED_SRGB_ALPHA);
	GLCONST(GL_COMPARE_REF_TO_TEXTURE);                                     GLCONST(GL_CLIP_DISTANCE0);
	GLCONST(GL_CLIP_DISTANCE1);                                             GLCONST(GL_CLIP_DISTANCE2);
	GLCONST(GL_CLIP_DISTANCE3);                                             GLCONST(GL_CLIP_DISTANCE4);
	GLCONST(GL_CLIP_DISTANCE5);                                             GLCONST(GL_CLIP_DISTANCE6);
	GLCONST(GL_CLIP_DISTANCE7);                                             GLCONST(GL_MAX_CLIP_DISTANCES);
	GLCONST(GL_MAJOR_VERSION);                                              GLCONST(GL_MINOR_VERSION);
	GLCONST(GL_NUM_EXTENSIONS);                                             GLCONST(GL_CONTEXT_FLAGS);
	GLCONST(GL_COMPRESSED_RED);                                             GLCONST(GL_COMPRESSED_RG);
	GLCONST(GL_CONTEXT_FLAG_FORWARD_COMPATIBLE_BIT);                        GLCONST(GL_RGBA32F);
	GLCONST(GL_RGB32F);                                                     GLCONST(GL_RGBA16F);
	GLCONST(GL_RGB16F);                                                     GLCONST(GL_VERTEX_ATTRIB_ARRAY_INTEGER);
	GLCONST(GL_MAX_ARRAY_TEXTURE_LAYERS);                                   GLCONST(GL_MIN_PROGRAM_TEXEL_OFFSET);
	GLCONST(GL_MAX_PROGRAM_TEXEL_OFFSET);                                   GLCONST(GL_CLAMP_READ_COLOR);
	GLCONST(GL_FIXED_ONLY);                                                 GLCONST(GL_MAX_VARYING_COMPONENTS);
	GLCONST(GL_TEXTURE_1D_ARRAY);                                           GLCONST(GL_PROXY_TEXTURE_1D_ARRAY);
	GLCONST(GL_TEXTURE_2D_ARRAY);                                           GLCONST(GL_PROXY_TEXTURE_2D_ARRAY);
	GLCONST(GL_TEXTURE_BINDING_1D_ARRAY);                                   GLCONST(GL_TEXTURE_BINDING_2D_ARRAY);
	GLCONST(GL_R11F_G11F_B10F);                                             GLCONST(GL_UNSIGNED_INT_10F_11F_11F_REV);
	GLCONST(GL_RGB9_E5);                                                    GLCONST(GL_UNSIGNED_INT_5_9_9_9_REV);
	GLCONST(GL_TEXTURE_SHARED_SIZE);                                        GLCONST(GL_TRANSFORM_FEEDBACK_VARYING_MAX_LENGTH);
	GLCONST(GL_TRANSFORM_FEEDBACK_BUFFER_MODE);                             GLCONST(GL_MAX_TRANSFORM_FEEDBACK_SEPARATE_COMPONENTS);
	GLCONST(GL_TRANSFORM_FEEDBACK_VARYINGS);                                GLCONST(GL_TRANSFORM_FEEDBACK_BUFFER_START);
	GLCONST(GL_TRANSFORM_FEEDBACK_BUFFER_SIZE);                             GLCONST(GL_PRIMITIVES_GENERATED);
	GLCONST(GL_TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN);                      GLCONST(GL_RASTERIZER_DISCARD);
	GLCONST(GL_MAX_TRANSFORM_FEEDBACK_INTERLEAVED_COMPONENTS);              GLCONST(GL_MAX_TRANSFORM_FEEDBACK_SEPARATE_ATTRIBS);
	GLCONST(GL_INTERLEAVED_ATTRIBS);                                        GLCONST(GL_SEPARATE_ATTRIBS);
	GLCONST(GL_TRANSFORM_FEEDBACK_BUFFER);                                  GLCONST(GL_TRANSFORM_FEEDBACK_BUFFER_BINDING);
	GLCONST(GL_RGBA32UI);                                                   GLCONST(GL_RGB32UI);
	GLCONST(GL_RGBA16UI);                                                   GLCONST(GL_RGB16UI);
	GLCONST(GL_RGBA8UI);                                                    GLCONST(GL_RGB8UI);
	GLCONST(GL_RGBA32I);                                                    GLCONST(GL_RGB32I);
	GLCONST(GL_RGBA16I);                                                    GLCONST(GL_RGB16I);
	GLCONST(GL_RGBA8I);                                                     GLCONST(GL_RGB8I);
	GLCONST(GL_RED_INTEGER);                                                GLCONST(GL_GREEN_INTEGER);
	GLCONST(GL_BLUE_INTEGER);                                               GLCONST(GL_RGB_INTEGER);
	GLCONST(GL_RGBA_INTEGER);                                               GLCONST(GL_BGR_INTEGER);
	GLCONST(GL_BGRA_INTEGER);                                               GLCONST(GL_SAMPLER_1D_ARRAY);
	GLCONST(GL_SAMPLER_2D_ARRAY);                                           GLCONST(GL_SAMPLER_1D_ARRAY_SHADOW);
	GLCONST(GL_SAMPLER_2D_ARRAY_SHADOW);                                    GLCONST(GL_SAMPLER_CUBE_SHADOW);
	GLCONST(GL_UNSIGNED_INT_VEC2);                                          GLCONST(GL_UNSIGNED_INT_VEC3);
	GLCONST(GL_UNSIGNED_INT_VEC4);                                          GLCONST(GL_INT_SAMPLER_1D);
	GLCONST(GL_INT_SAMPLER_2D);                                             GLCONST(GL_INT_SAMPLER_3D);
	GLCONST(GL_INT_SAMPLER_CUBE);                                           GLCONST(GL_INT_SAMPLER_1D_ARRAY);
	GLCONST(GL_INT_SAMPLER_2D_ARRAY);                                       GLCONST(GL_UNSIGNED_INT_SAMPLER_1D);
	GLCONST(GL_UNSIGNED_INT_SAMPLER_2D);                                    GLCONST(GL_UNSIGNED_INT_SAMPLER_3D);
	GLCONST(GL_UNSIGNED_INT_SAMPLER_CUBE);                                  GLCONST(GL_UNSIGNED_INT_SAMPLER_1D_ARRAY);
	GLCONST(GL_UNSIGNED_INT_SAMPLER_2D_ARRAY);                              GLCONST(GL_QUERY_WAIT);
	GLCONST(GL_QUERY_NO_WAIT);                                              GLCONST(GL_QUERY_BY_REGION_WAIT);
	GLCONST(GL_QUERY_BY_REGION_NO_WAIT);                                    GLCONST(GL_BUFFER_ACCESS_FLAGS);
	GLCONST(GL_BUFFER_MAP_LENGTH);                                          GLCONST(GL_BUFFER_MAP_OFFSET);
	GLCONST(GL_DEPTH_COMPONENT32F);                                         GLCONST(GL_DEPTH32F_STENCIL8);
	GLCONST(GL_FLOAT_32_UNSIGNED_INT_24_8_REV);                             GLCONST(GL_INVALID_FRAMEBUFFER_OPERATION);
	GLCONST(GL_FRAMEBUFFER_ATTACHMENT_COLOR_ENCODING);                      GLCONST(GL_FRAMEBUFFER_ATTACHMENT_COMPONENT_TYPE);
	GLCONST(GL_FRAMEBUFFER_ATTACHMENT_RED_SIZE);                            GLCONST(GL_FRAMEBUFFER_ATTACHMENT_GREEN_SIZE);
	GLCONST(GL_FRAMEBUFFER_ATTACHMENT_BLUE_SIZE);                           GLCONST(GL_FRAMEBUFFER_ATTACHMENT_ALPHA_SIZE);
	GLCONST(GL_FRAMEBUFFER_ATTACHMENT_DEPTH_SIZE);                          GLCONST(GL_FRAMEBUFFER_ATTACHMENT_STENCIL_SIZE);
	GLCONST(GL_FRAMEBUFFER_DEFAULT);                                        GLCONST(GL_FRAMEBUFFER_UNDEFINED);
	GLCONST(GL_DEPTH_STENCIL_ATTACHMENT);                                   GLCONST(GL_MAX_RENDERBUFFER_SIZE);
	GLCONST(GL_DEPTH_STENCIL);                                              GLCONST(GL_UNSIGNED_INT_24_8);
	GLCONST(GL_DEPTH24_STENCIL8);                                           GLCONST(GL_TEXTURE_STENCIL_SIZE);
	GLCONST(GL_TEXTURE_RED_TYPE);                                           GLCONST(GL_TEXTURE_GREEN_TYPE);
	GLCONST(GL_TEXTURE_BLUE_TYPE);                                          GLCONST(GL_TEXTURE_ALPHA_TYPE);
	GLCONST(GL_TEXTURE_DEPTH_TYPE);                                         GLCONST(GL_UNSIGNED_NORMALIZED);
	GLCONST(GL_FRAMEBUFFER_BINDING);                                        GLCONST(GL_DRAW_FRAMEBUFFER_BINDING);
	GLCONST(GL_RENDERBUFFER_BINDING);                                       GLCONST(GL_READ_FRAMEBUFFER);
	GLCONST(GL_DRAW_FRAMEBUFFER);                                           GLCONST(GL_READ_FRAMEBUFFER_BINDING);
	GLCONST(GL_RENDERBUFFER_SAMPLES);                                       GLCONST(GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE);
	GLCONST(GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME);                         GLCONST(GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_LEVEL);
	GLCONST(GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_CUBE_MAP_FACE);               GLCONST(GL_FRAMEBUFFER_ATTACHMENT_TEXTURE_LAYER);
	GLCONST(GL_FRAMEBUFFER_COMPLETE);                                       GLCONST(GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT);
	GLCONST(GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT);                  GLCONST(GL_FRAMEBUFFER_INCOMPLETE_DRAW_BUFFER);
	GLCONST(GL_FRAMEBUFFER_INCOMPLETE_READ_BUFFER);                         GLCONST(GL_FRAMEBUFFER_UNSUPPORTED);
	GLCONST(GL_MAX_COLOR_ATTACHMENTS);                                      GLCONST(GL_COLOR_ATTACHMENT0);
	GLCONST(GL_COLOR_ATTACHMENT1);                                          GLCONST(GL_COLOR_ATTACHMENT2);
	GLCONST(GL_COLOR_ATTACHMENT3);                                          GLCONST(GL_COLOR_ATTACHMENT4);
	GLCONST(GL_COLOR_ATTACHMENT5);                                          GLCONST(GL_COLOR_ATTACHMENT6);
	GLCONST(GL_COLOR_ATTACHMENT7);                                          GLCONST(GL_COLOR_ATTACHMENT8);
	GLCONST(GL_COLOR_ATTACHMENT9);                                          GLCONST(GL_COLOR_ATTACHMENT10);
	GLCONST(GL_COLOR_ATTACHMENT11);                                         GLCONST(GL_COLOR_ATTACHMENT12);
	GLCONST(GL_COLOR_ATTACHMENT13);                                         GLCONST(GL_COLOR_ATTACHMENT14);
	GLCONST(GL_COLOR_ATTACHMENT15);                                         GLCONST(GL_DEPTH_ATTACHMENT);
	GLCONST(GL_STENCIL_ATTACHMENT);                                         GLCONST(GL_FRAMEBUFFER);
	GLCONST(GL_RENDERBUFFER);                                               GLCONST(GL_RENDERBUFFER_WIDTH);
	GLCONST(GL_RENDERBUFFER_HEIGHT);                                        GLCONST(GL_RENDERBUFFER_INTERNAL_FORMAT);
	GLCONST(GL_STENCIL_INDEX1);                                             GLCONST(GL_STENCIL_INDEX4);
	GLCONST(GL_STENCIL_INDEX8);                                             GLCONST(GL_STENCIL_INDEX16);
	GLCONST(GL_RENDERBUFFER_RED_SIZE);                                      GLCONST(GL_RENDERBUFFER_GREEN_SIZE);
	GLCONST(GL_RENDERBUFFER_BLUE_SIZE);                                     GLCONST(GL_RENDERBUFFER_ALPHA_SIZE);
	GLCONST(GL_RENDERBUFFER_DEPTH_SIZE);                                    GLCONST(GL_RENDERBUFFER_STENCIL_SIZE);
	GLCONST(GL_FRAMEBUFFER_INCOMPLETE_MULTISAMPLE);                         GLCONST(GL_MAX_SAMPLES);
	GLCONST(GL_INDEX);                                                      GLCONST(GL_FRAMEBUFFER_SRGB);
	GLCONST(GL_HALF_FLOAT);                                                 GLCONST(GL_MAP_READ_BIT);
	GLCONST(GL_MAP_WRITE_BIT);                                              GLCONST(GL_MAP_INVALIDATE_RANGE_BIT);
	GLCONST(GL_MAP_INVALIDATE_BUFFER_BIT);                                  GLCONST(GL_MAP_FLUSH_EXPLICIT_BIT);
	GLCONST(GL_MAP_UNSYNCHRONIZED_BIT);                                     GLCONST(GL_COMPRESSED_RED_RGTC1);
	GLCONST(GL_COMPRESSED_SIGNED_RED_RGTC1);                                GLCONST(GL_COMPRESSED_RG_RGTC2);
	GLCONST(GL_COMPRESSED_SIGNED_RG_RGTC2);                                 GLCONST(GL_RG);
	GLCONST(GL_RG_INTEGER);                                                 GLCONST(GL_R8);
	GLCONST(GL_R16);                                                        GLCONST(GL_RG8);
	GLCONST(GL_RG16);                                                       GLCONST(GL_R16F);
	GLCONST(GL_R32F);                                                       GLCONST(GL_RG16F);
	GLCONST(GL_RG32F);                                                      GLCONST(GL_R8I);
	GLCONST(GL_R8UI);                                                       GLCONST(GL_R16I);
	GLCONST(GL_R16UI);                                                      GLCONST(GL_R32I);
	GLCONST(GL_R32UI);                                                      GLCONST(GL_RG8I);
	GLCONST(GL_RG8UI);                                                      GLCONST(GL_RG16I);
	GLCONST(GL_RG16UI);                                                     GLCONST(GL_RG32I);
	GLCONST(GL_RG32UI);                                                     GLCONST(GL_VERTEX_ARRAY_BINDING);
	GLCONST(GL_SAMPLER_2D_RECT);                                            GLCONST(GL_SAMPLER_2D_RECT_SHADOW);
	GLCONST(GL_SAMPLER_BUFFER);                                             GLCONST(GL_INT_SAMPLER_2D_RECT);
	GLCONST(GL_INT_SAMPLER_BUFFER);                                         GLCONST(GL_UNSIGNED_INT_SAMPLER_2D_RECT);
	GLCONST(GL_UNSIGNED_INT_SAMPLER_BUFFER);                                GLCONST(GL_TEXTURE_BUFFER);
	GLCONST(GL_MAX_TEXTURE_BUFFER_SIZE);                                    GLCONST(GL_TEXTURE_BINDING_BUFFER);
	GLCONST(GL_TEXTURE_BUFFER_DATA_STORE_BINDING);                          GLCONST(GL_TEXTURE_RECTANGLE);
	GLCONST(GL_TEXTURE_BINDING_RECTANGLE);                                  GLCONST(GL_PROXY_TEXTURE_RECTANGLE);
	GLCONST(GL_MAX_RECTANGLE_TEXTURE_SIZE);                                 GLCONST(GL_R8_SNORM);
	GLCONST(GL_RG8_SNORM);                                                  GLCONST(GL_RGB8_SNORM);
	GLCONST(GL_RGBA8_SNORM);                                                GLCONST(GL_R16_SNORM);
	GLCONST(GL_RG16_SNORM);                                                 GLCONST(GL_RGB16_SNORM);
	GLCONST(GL_RGBA16_SNORM);                                               GLCONST(GL_SIGNED_NORMALIZED);
	GLCONST(GL_PRIMITIVE_RESTART);                                          GLCONST(GL_PRIMITIVE_RESTART_INDEX);
	GLCONST(GL_COPY_READ_BUFFER);                                           GLCONST(GL_COPY_WRITE_BUFFER);
	GLCONST(GL_UNIFORM_BUFFER);                                             GLCONST(GL_UNIFORM_BUFFER_BINDING);
	GLCONST(GL_UNIFORM_BUFFER_START);                                       GLCONST(GL_UNIFORM_BUFFER_SIZE);
	GLCONST(GL_MAX_VERTEX_UNIFORM_BLOCKS);                                  GLCONST(GL_MAX_GEOMETRY_UNIFORM_BLOCKS);
	GLCONST(GL_MAX_FRAGMENT_UNIFORM_BLOCKS);                                GLCONST(GL_MAX_COMBINED_UNIFORM_BLOCKS);
	GLCONST(GL_MAX_UNIFORM_BUFFER_BINDINGS);                                GLCONST(GL_MAX_UNIFORM_BLOCK_SIZE);
	GLCONST(GL_MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS);                     GLCONST(GL_MAX_COMBINED_GEOMETRY_UNIFORM_COMPONENTS);
	GLCONST(GL_MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS);                   GLCONST(GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT);
	GLCONST(GL_ACTIVE_UNIFORM_BLOCK_MAX_NAME_LENGTH);                       GLCONST(GL_ACTIVE_UNIFORM_BLOCKS);
	GLCONST(GL_UNIFORM_TYPE);                                               GLCONST(GL_UNIFORM_SIZE);
	GLCONST(GL_UNIFORM_NAME_LENGTH);                                        GLCONST(GL_UNIFORM_BLOCK_INDEX);
	GLCONST(GL_UNIFORM_OFFSET);                                             GLCONST(GL_UNIFORM_ARRAY_STRIDE);
	GLCONST(GL_UNIFORM_MATRIX_STRIDE);                                      GLCONST(GL_UNIFORM_IS_ROW_MAJOR);
	GLCONST(GL_UNIFORM_BLOCK_BINDING);                                      GLCONST(GL_UNIFORM_BLOCK_DATA_SIZE);
	GLCONST(GL_UNIFORM_BLOCK_NAME_LENGTH);                                  GLCONST(GL_UNIFORM_BLOCK_ACTIVE_UNIFORMS);
	GLCONST(GL_UNIFORM_BLOCK_ACTIVE_UNIFORM_INDICES);                       GLCONST(GL_UNIFORM_BLOCK_REFERENCED_BY_VERTEX_SHADER);
	GLCONST(GL_UNIFORM_BLOCK_REFERENCED_BY_GEOMETRY_SHADER);                GLCONST(GL_UNIFORM_BLOCK_REFERENCED_BY_FRAGMENT_SHADER);
	GLCONST(GL_INVALID_INDEX);                                              GLCONST(GL_CONTEXT_CORE_PROFILE_BIT);
	GLCONST(GL_CONTEXT_COMPATIBILITY_PROFILE_BIT);                          GLCONST(GL_LINES_ADJACENCY);
	GLCONST(GL_LINE_STRIP_ADJACENCY);                                       GLCONST(GL_TRIANGLES_ADJACENCY);
	GLCONST(GL_TRIANGLE_STRIP_ADJACENCY);                                   GLCONST(GL_PROGRAM_POINT_SIZE);
	GLCONST(GL_MAX_GEOMETRY_TEXTURE_IMAGE_UNITS);                           GLCONST(GL_FRAMEBUFFER_ATTACHMENT_LAYERED);
	GLCONST(GL_FRAMEBUFFER_INCOMPLETE_LAYER_TARGETS);                       GLCONST(GL_GEOMETRY_SHADER);
	GLCONST(GL_GEOMETRY_VERTICES_OUT);                                      GLCONST(GL_GEOMETRY_INPUT_TYPE);
	GLCONST(GL_GEOMETRY_OUTPUT_TYPE);                                       GLCONST(GL_MAX_GEOMETRY_UNIFORM_COMPONENTS);
	GLCONST(GL_MAX_GEOMETRY_OUTPUT_VERTICES);                               GLCONST(GL_MAX_GEOMETRY_TOTAL_OUTPUT_COMPONENTS);
	GLCONST(GL_MAX_VERTEX_OUTPUT_COMPONENTS);                               GLCONST(GL_MAX_GEOMETRY_INPUT_COMPONENTS);
	GLCONST(GL_MAX_GEOMETRY_OUTPUT_COMPONENTS);                             GLCONST(GL_MAX_FRAGMENT_INPUT_COMPONENTS);
	GLCONST(GL_CONTEXT_PROFILE_MASK);                                       GLCONST(GL_DEPTH_CLAMP);
	GLCONST(GL_QUADS_FOLLOW_PROVOKING_VERTEX_CONVENTION);                   GLCONST(GL_FIRST_VERTEX_CONVENTION);
	GLCONST(GL_LAST_VERTEX_CONVENTION);                                     GLCONST(GL_PROVOKING_VERTEX);
	GLCONST(GL_TEXTURE_CUBE_MAP_SEAMLESS);                                  GLCONST(GL_MAX_SERVER_WAIT_TIMEOUT);
	GLCONST(GL_OBJECT_TYPE);                                                GLCONST(GL_SYNC_CONDITION);
	GLCONST(GL_SYNC_STATUS);                                                GLCONST(GL_SYNC_FLAGS);
	GLCONST(GL_SYNC_FENCE);                                                 GLCONST(GL_SYNC_GPU_COMMANDS_COMPLETE);
	GLCONST(GL_UNSIGNALED);                                                 GLCONST(GL_SIGNALED);
	GLCONST(GL_ALREADY_SIGNALED);                                           GLCONST(GL_TIMEOUT_EXPIRED);
	GLCONST(GL_CONDITION_SATISFIED);                                        GLCONST(GL_WAIT_FAILED);
	GLCONST(GL_TIMEOUT_IGNORED);                                            GLCONST(GL_SYNC_FLUSH_COMMANDS_BIT);
	GLCONST(GL_SAMPLE_POSITION);                                            GLCONST(GL_SAMPLE_MASK);
	GLCONST(GL_SAMPLE_MASK_VALUE);                                          GLCONST(GL_MAX_SAMPLE_MASK_WORDS);
	GLCONST(GL_TEXTURE_2D_MULTISAMPLE);                                     GLCONST(GL_PROXY_TEXTURE_2D_MULTISAMPLE);
	GLCONST(GL_TEXTURE_2D_MULTISAMPLE_ARRAY);                               GLCONST(GL_PROXY_TEXTURE_2D_MULTISAMPLE_ARRAY);
	GLCONST(GL_TEXTURE_BINDING_2D_MULTISAMPLE);                             GLCONST(GL_TEXTURE_BINDING_2D_MULTISAMPLE_ARRAY);
	GLCONST(GL_TEXTURE_SAMPLES);                                            GLCONST(GL_TEXTURE_FIXED_SAMPLE_LOCATIONS);
	GLCONST(GL_SAMPLER_2D_MULTISAMPLE);                                     GLCONST(GL_INT_SAMPLER_2D_MULTISAMPLE);
	GLCONST(GL_UNSIGNED_INT_SAMPLER_2D_MULTISAMPLE);                        GLCONST(GL_SAMPLER_2D_MULTISAMPLE_ARRAY);
	GLCONST(GL_INT_SAMPLER_2D_MULTISAMPLE_ARRAY);                           GLCONST(GL_UNSIGNED_INT_SAMPLER_2D_MULTISAMPLE_ARRAY);
	GLCONST(GL_MAX_COLOR_TEXTURE_SAMPLES);                                  GLCONST(GL_MAX_DEPTH_TEXTURE_SAMPLES);
	GLCONST(GL_MAX_INTEGER_SAMPLES);                                        GLCONST(GL_VERTEX_ATTRIB_ARRAY_DIVISOR);
	GLCONST(GL_SRC1_COLOR);                                                 GLCONST(GL_ONE_MINUS_SRC1_COLOR);
	GLCONST(GL_ONE_MINUS_SRC1_ALPHA);                                       GLCONST(GL_MAX_DUAL_SOURCE_DRAW_BUFFERS);
	GLCONST(GL_ANY_SAMPLES_PASSED);                                         GLCONST(GL_SAMPLER_BINDING);
	GLCONST(GL_RGB10_A2UI);                                                 GLCONST(GL_TEXTURE_SWIZZLE_R);
	GLCONST(GL_TEXTURE_SWIZZLE_G);                                          GLCONST(GL_TEXTURE_SWIZZLE_B);
	GLCONST(GL_TEXTURE_SWIZZLE_A);                                          GLCONST(GL_TEXTURE_SWIZZLE_RGBA);
	GLCONST(GL_TIME_ELAPSED);                                               GLCONST(GL_TIMESTAMP);
	GLCONST(GL_INT_2_10_10_10_REV);                                         GLCONST(GL_SAMPLE_SHADING);
	GLCONST(GL_MIN_SAMPLE_SHADING_VALUE);                                   GLCONST(GL_MIN_PROGRAM_TEXTURE_GATHER_OFFSET);
	GLCONST(GL_MAX_PROGRAM_TEXTURE_GATHER_OFFSET);                          GLCONST(GL_TEXTURE_CUBE_MAP_ARRAY);
	GLCONST(GL_TEXTURE_BINDING_CUBE_MAP_ARRAY);                             GLCONST(GL_PROXY_TEXTURE_CUBE_MAP_ARRAY);
	GLCONST(GL_SAMPLER_CUBE_MAP_ARRAY);                                     GLCONST(GL_SAMPLER_CUBE_MAP_ARRAY_SHADOW);
	GLCONST(GL_INT_SAMPLER_CUBE_MAP_ARRAY);                                 GLCONST(GL_UNSIGNED_INT_SAMPLER_CUBE_MAP_ARRAY);
	GLCONST(GL_DRAW_INDIRECT_BUFFER);                                       GLCONST(GL_DRAW_INDIRECT_BUFFER_BINDING);
	GLCONST(GL_GEOMETRY_SHADER_INVOCATIONS);                                GLCONST(GL_MAX_GEOMETRY_SHADER_INVOCATIONS);
	GLCONST(GL_MIN_FRAGMENT_INTERPOLATION_OFFSET);                          GLCONST(GL_MAX_FRAGMENT_INTERPOLATION_OFFSET);
	GLCONST(GL_FRAGMENT_INTERPOLATION_OFFSET_BITS);                         GLCONST(GL_MAX_VERTEX_STREAMS);
	GLCONST(GL_DOUBLE_VEC2);                                                GLCONST(GL_DOUBLE_VEC3);
	GLCONST(GL_DOUBLE_VEC4);                                                GLCONST(GL_DOUBLE_MAT2);
	GLCONST(GL_DOUBLE_MAT3);                                                GLCONST(GL_DOUBLE_MAT4);
	GLCONST(GL_DOUBLE_MAT2x3);                                              GLCONST(GL_DOUBLE_MAT2x4);
	GLCONST(GL_DOUBLE_MAT3x2);                                              GLCONST(GL_DOUBLE_MAT3x4);
	GLCONST(GL_DOUBLE_MAT4x2);                                              GLCONST(GL_DOUBLE_MAT4x3);
	GLCONST(GL_ACTIVE_SUBROUTINES);                                         GLCONST(GL_ACTIVE_SUBROUTINE_UNIFORMS);
	GLCONST(GL_ACTIVE_SUBROUTINE_UNIFORM_LOCATIONS);                        GLCONST(GL_ACTIVE_SUBROUTINE_MAX_LENGTH);
	GLCONST(GL_ACTIVE_SUBROUTINE_UNIFORM_MAX_LENGTH);                       GLCONST(GL_MAX_SUBROUTINES);
	GLCONST(GL_MAX_SUBROUTINE_UNIFORM_LOCATIONS);                           GLCONST(GL_NUM_COMPATIBLE_SUBROUTINES);
	GLCONST(GL_COMPATIBLE_SUBROUTINES);                                     GLCONST(GL_PATCHES);
	GLCONST(GL_PATCH_VERTICES);                                             GLCONST(GL_PATCH_DEFAULT_INNER_LEVEL);
	GLCONST(GL_PATCH_DEFAULT_OUTER_LEVEL);                                  GLCONST(GL_TESS_CONTROL_OUTPUT_VERTICES);
	GLCONST(GL_TESS_GEN_MODE);                                              GLCONST(GL_TESS_GEN_SPACING);
	GLCONST(GL_TESS_GEN_VERTEX_ORDER);                                      GLCONST(GL_TESS_GEN_POINT_MODE);
	GLCONST(GL_ISOLINES);                                                   GLCONST(GL_FRACTIONAL_ODD);
	GLCONST(GL_FRACTIONAL_EVEN);                                            GLCONST(GL_MAX_PATCH_VERTICES);
	GLCONST(GL_MAX_TESS_GEN_LEVEL);                                         GLCONST(GL_MAX_TESS_CONTROL_UNIFORM_COMPONENTS);
	GLCONST(GL_MAX_TESS_EVALUATION_UNIFORM_COMPONENTS);                     GLCONST(GL_MAX_TESS_CONTROL_TEXTURE_IMAGE_UNITS);
	GLCONST(GL_MAX_TESS_EVALUATION_TEXTURE_IMAGE_UNITS);                    GLCONST(GL_MAX_TESS_CONTROL_OUTPUT_COMPONENTS);
	GLCONST(GL_MAX_TESS_PATCH_COMPONENTS);                                  GLCONST(GL_MAX_TESS_CONTROL_TOTAL_OUTPUT_COMPONENTS);
	GLCONST(GL_MAX_TESS_EVALUATION_OUTPUT_COMPONENTS);                      GLCONST(GL_MAX_TESS_CONTROL_UNIFORM_BLOCKS);
	GLCONST(GL_MAX_TESS_EVALUATION_UNIFORM_BLOCKS);                         GLCONST(GL_MAX_TESS_CONTROL_INPUT_COMPONENTS);
	GLCONST(GL_MAX_TESS_EVALUATION_INPUT_COMPONENTS);                       GLCONST(GL_MAX_COMBINED_TESS_CONTROL_UNIFORM_COMPONENTS);
	GLCONST(GL_MAX_COMBINED_TESS_EVALUATION_UNIFORM_COMPONENTS);            GLCONST(GL_UNIFORM_BLOCK_REFERENCED_BY_TESS_CONTROL_SHADER);
	GLCONST(GL_UNIFORM_BLOCK_REFERENCED_BY_TESS_EVALUATION_SHADER);         GLCONST(GL_TESS_EVALUATION_SHADER);
	GLCONST(GL_TESS_CONTROL_SHADER);                                        GLCONST(GL_TRANSFORM_FEEDBACK);
	GLCONST(GL_TRANSFORM_FEEDBACK_BUFFER_PAUSED);                           GLCONST(GL_TRANSFORM_FEEDBACK_BUFFER_ACTIVE);
	GLCONST(GL_TRANSFORM_FEEDBACK_BINDING);                                 GLCONST(GL_MAX_TRANSFORM_FEEDBACK_BUFFERS);
	GLCONST(GL_FIXED);                                                      GLCONST(GL_IMPLEMENTATION_COLOR_READ_TYPE);
	GLCONST(GL_IMPLEMENTATION_COLOR_READ_FORMAT);                           GLCONST(GL_LOW_FLOAT);
	GLCONST(GL_MEDIUM_FLOAT);                                               GLCONST(GL_HIGH_FLOAT);
	GLCONST(GL_LOW_INT);                                                    GLCONST(GL_MEDIUM_INT);
	GLCONST(GL_HIGH_INT);                                                   GLCONST(GL_SHADER_COMPILER);
	GLCONST(GL_SHADER_BINARY_FORMATS);                                      GLCONST(GL_NUM_SHADER_BINARY_FORMATS);
	GLCONST(GL_MAX_VERTEX_UNIFORM_VECTORS);                                 GLCONST(GL_MAX_VARYING_VECTORS);
	GLCONST(GL_MAX_FRAGMENT_UNIFORM_VECTORS);                               GLCONST(GL_RGB565);
	GLCONST(GL_PROGRAM_BINARY_RETRIEVABLE_HINT);                            GLCONST(GL_PROGRAM_BINARY_LENGTH);
	GLCONST(GL_NUM_PROGRAM_BINARY_FORMATS);                                 GLCONST(GL_PROGRAM_BINARY_FORMATS);
	GLCONST(GL_VERTEX_SHADER_BIT);                                          GLCONST(GL_FRAGMENT_SHADER_BIT);
	GLCONST(GL_GEOMETRY_SHADER_BIT);                                        GLCONST(GL_TESS_CONTROL_SHADER_BIT);
	GLCONST(GL_TESS_EVALUATION_SHADER_BIT);                                 GLCONST(GL_ALL_SHADER_BITS);
	GLCONST(GL_PROGRAM_SEPARABLE);                                          GLCONST(GL_ACTIVE_PROGRAM);
	GLCONST(GL_PROGRAM_PIPELINE_BINDING);                                   GLCONST(GL_MAX_VIEWPORTS);
	GLCONST(GL_VIEWPORT_SUBPIXEL_BITS);                                     GLCONST(GL_VIEWPORT_BOUNDS_RANGE);
	GLCONST(GL_LAYER_PROVOKING_VERTEX);                                     GLCONST(GL_VIEWPORT_INDEX_PROVOKING_VERTEX);
	GLCONST(GL_UNDEFINED_VERTEX);                                           GLCONST(GL_UNPACK_COMPRESSED_BLOCK_WIDTH);
	GLCONST(GL_UNPACK_COMPRESSED_BLOCK_HEIGHT);                             GLCONST(GL_UNPACK_COMPRESSED_BLOCK_DEPTH);
	GLCONST(GL_UNPACK_COMPRESSED_BLOCK_SIZE);                               GLCONST(GL_PACK_COMPRESSED_BLOCK_WIDTH);
	GLCONST(GL_PACK_COMPRESSED_BLOCK_HEIGHT);                               GLCONST(GL_PACK_COMPRESSED_BLOCK_DEPTH);
	GLCONST(GL_PACK_COMPRESSED_BLOCK_SIZE);                                 GLCONST(GL_NUM_SAMPLE_COUNTS);
	GLCONST(GL_MIN_MAP_BUFFER_ALIGNMENT);                                   GLCONST(GL_ATOMIC_COUNTER_BUFFER);
	GLCONST(GL_ATOMIC_COUNTER_BUFFER_BINDING);                              GLCONST(GL_ATOMIC_COUNTER_BUFFER_START);
	GLCONST(GL_ATOMIC_COUNTER_BUFFER_SIZE);                                 GLCONST(GL_ATOMIC_COUNTER_BUFFER_DATA_SIZE);
	GLCONST(GL_ATOMIC_COUNTER_BUFFER_ACTIVE_ATOMIC_COUNTERS);               GLCONST(GL_ATOMIC_COUNTER_BUFFER_ACTIVE_ATOMIC_COUNTER_INDICES);
	GLCONST(GL_ATOMIC_COUNTER_BUFFER_REFERENCED_BY_VERTEX_SHADER);          GLCONST(GL_ATOMIC_COUNTER_BUFFER_REFERENCED_BY_TESS_CONTROL_SHADER);
	GLCONST(GL_ATOMIC_COUNTER_BUFFER_REFERENCED_BY_TESS_EVALUATION_SHADER); GLCONST(GL_ATOMIC_COUNTER_BUFFER_REFERENCED_BY_GEOMETRY_SHADER);
	GLCONST(GL_ATOMIC_COUNTER_BUFFER_REFERENCED_BY_FRAGMENT_SHADER);        GLCONST(GL_MAX_VERTEX_ATOMIC_COUNTER_BUFFERS);
	GLCONST(GL_MAX_TESS_CONTROL_ATOMIC_COUNTER_BUFFERS);                    GLCONST(GL_MAX_TESS_EVALUATION_ATOMIC_COUNTER_BUFFERS);
	GLCONST(GL_MAX_GEOMETRY_ATOMIC_COUNTER_BUFFERS);                        GLCONST(GL_MAX_FRAGMENT_ATOMIC_COUNTER_BUFFERS);
	GLCONST(GL_MAX_COMBINED_ATOMIC_COUNTER_BUFFERS);                        GLCONST(GL_MAX_VERTEX_ATOMIC_COUNTERS);
	GLCONST(GL_MAX_TESS_CONTROL_ATOMIC_COUNTERS);                           GLCONST(GL_MAX_TESS_EVALUATION_ATOMIC_COUNTERS);
	GLCONST(GL_MAX_GEOMETRY_ATOMIC_COUNTERS);                               GLCONST(GL_MAX_FRAGMENT_ATOMIC_COUNTERS);
	GLCONST(GL_MAX_COMBINED_ATOMIC_COUNTERS);                               GLCONST(GL_MAX_ATOMIC_COUNTER_BUFFER_SIZE);
	GLCONST(GL_MAX_ATOMIC_COUNTER_BUFFER_BINDINGS);                         GLCONST(GL_ACTIVE_ATOMIC_COUNTER_BUFFERS);
	GLCONST(GL_UNIFORM_ATOMIC_COUNTER_BUFFER_INDEX);                        GLCONST(GL_UNSIGNED_INT_ATOMIC_COUNTER);
	GLCONST(GL_VERTEX_ATTRIB_ARRAY_BARRIER_BIT);                            GLCONST(GL_ELEMENT_ARRAY_BARRIER_BIT);
	GLCONST(GL_UNIFORM_BARRIER_BIT);                                        GLCONST(GL_TEXTURE_FETCH_BARRIER_BIT);
	GLCONST(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);                            GLCONST(GL_COMMAND_BARRIER_BIT);
	GLCONST(GL_PIXEL_BUFFER_BARRIER_BIT);                                   GLCONST(GL_TEXTURE_UPDATE_BARRIER_BIT);
	GLCONST(GL_BUFFER_UPDATE_BARRIER_BIT);                                  GLCONST(GL_FRAMEBUFFER_BARRIER_BIT);
	GLCONST(GL_TRANSFORM_FEEDBACK_BARRIER_BIT);                             GLCONST(GL_ATOMIC_COUNTER_BARRIER_BIT);
	GLCONST(GL_ALL_BARRIER_BITS);                                           GLCONST(GL_MAX_IMAGE_UNITS);
	GLCONST(GL_MAX_COMBINED_IMAGE_UNITS_AND_FRAGMENT_OUTPUTS);              GLCONST(GL_IMAGE_BINDING_NAME);
	GLCONST(GL_IMAGE_BINDING_LEVEL);                                        GLCONST(GL_IMAGE_BINDING_LAYERED);
	GLCONST(GL_IMAGE_BINDING_LAYER);                                        GLCONST(GL_IMAGE_BINDING_ACCESS);
	GLCONST(GL_IMAGE_1D);                                                   GLCONST(GL_IMAGE_2D);
	GLCONST(GL_IMAGE_3D);                                                   GLCONST(GL_IMAGE_2D_RECT);
	GLCONST(GL_IMAGE_CUBE);                                                 GLCONST(GL_IMAGE_BUFFER);
	GLCONST(GL_IMAGE_1D_ARRAY);                                             GLCONST(GL_IMAGE_2D_ARRAY);
	GLCONST(GL_IMAGE_CUBE_MAP_ARRAY);                                       GLCONST(GL_IMAGE_2D_MULTISAMPLE);
	GLCONST(GL_IMAGE_2D_MULTISAMPLE_ARRAY);                                 GLCONST(GL_INT_IMAGE_1D);
	GLCONST(GL_INT_IMAGE_2D);                                               GLCONST(GL_INT_IMAGE_3D);
	GLCONST(GL_INT_IMAGE_2D_RECT);                                          GLCONST(GL_INT_IMAGE_CUBE);
	GLCONST(GL_INT_IMAGE_BUFFER);                                           GLCONST(GL_INT_IMAGE_1D_ARRAY);
	GLCONST(GL_INT_IMAGE_2D_ARRAY);                                         GLCONST(GL_INT_IMAGE_CUBE_MAP_ARRAY);
	GLCONST(GL_INT_IMAGE_2D_MULTISAMPLE);                                   GLCONST(GL_INT_IMAGE_2D_MULTISAMPLE_ARRAY);
	GLCONST(GL_UNSIGNED_INT_IMAGE_1D);                                      GLCONST(GL_UNSIGNED_INT_IMAGE_2D);
	GLCONST(GL_UNSIGNED_INT_IMAGE_3D);                                      GLCONST(GL_UNSIGNED_INT_IMAGE_2D_RECT);
	GLCONST(GL_UNSIGNED_INT_IMAGE_CUBE);                                    GLCONST(GL_UNSIGNED_INT_IMAGE_BUFFER);
	GLCONST(GL_UNSIGNED_INT_IMAGE_1D_ARRAY);                                GLCONST(GL_UNSIGNED_INT_IMAGE_2D_ARRAY);
	GLCONST(GL_UNSIGNED_INT_IMAGE_CUBE_MAP_ARRAY);                          GLCONST(GL_UNSIGNED_INT_IMAGE_2D_MULTISAMPLE);
	GLCONST(GL_UNSIGNED_INT_IMAGE_2D_MULTISAMPLE_ARRAY);                    GLCONST(GL_MAX_IMAGE_SAMPLES);
	GLCONST(GL_IMAGE_BINDING_FORMAT);                                       GLCONST(GL_IMAGE_FORMAT_COMPATIBILITY_TYPE);
	GLCONST(GL_IMAGE_FORMAT_COMPATIBILITY_BY_SIZE);                         GLCONST(GL_IMAGE_FORMAT_COMPATIBILITY_BY_CLASS);
	GLCONST(GL_MAX_VERTEX_IMAGE_UNIFORMS);                                  GLCONST(GL_MAX_TESS_CONTROL_IMAGE_UNIFORMS);
	GLCONST(GL_MAX_TESS_EVALUATION_IMAGE_UNIFORMS);                         GLCONST(GL_MAX_GEOMETRY_IMAGE_UNIFORMS);
	GLCONST(GL_MAX_FRAGMENT_IMAGE_UNIFORMS);                                GLCONST(GL_MAX_COMBINED_IMAGE_UNIFORMS);
	GLCONST(GL_COMPRESSED_RGBA_BPTC_UNORM);                                 GLCONST(GL_COMPRESSED_SRGB_ALPHA_BPTC_UNORM);
	GLCONST(GL_COMPRESSED_RGB_BPTC_SIGNED_FLOAT);                           GLCONST(GL_COMPRESSED_RGB_BPTC_UNSIGNED_FLOAT);
	GLCONST(GL_TEXTURE_IMMUTABLE_FORMAT);                                   GLCONST(GL_NUM_SHADING_LANGUAGE_VERSIONS);
	GLCONST(GL_VERTEX_ATTRIB_ARRAY_LONG);                                   GLCONST(GL_COMPRESSED_RGB8_ETC2);
	GLCONST(GL_COMPRESSED_SRGB8_ETC2);                                      GLCONST(GL_COMPRESSED_RGB8_PUNCHTHROUGH_ALPHA1_ETC2);
	GLCONST(GL_COMPRESSED_SRGB8_PUNCHTHROUGH_ALPHA1_ETC2);                  GLCONST(GL_COMPRESSED_RGBA8_ETC2_EAC);
	GLCONST(GL_COMPRESSED_SRGB8_ALPHA8_ETC2_EAC);                           GLCONST(GL_COMPRESSED_R11_EAC);
	GLCONST(GL_COMPRESSED_SIGNED_R11_EAC);                                  GLCONST(GL_COMPRESSED_RG11_EAC);
	GLCONST(GL_COMPRESSED_SIGNED_RG11_EAC);                                 GLCONST(GL_PRIMITIVE_RESTART_FIXED_INDEX);
	GLCONST(GL_ANY_SAMPLES_PASSED_CONSERVATIVE);                            GLCONST(GL_MAX_ELEMENT_INDEX);
	GLCONST(GL_COMPUTE_SHADER);                                             GLCONST(GL_MAX_COMPUTE_UNIFORM_BLOCKS);
	GLCONST(GL_MAX_COMPUTE_TEXTURE_IMAGE_UNITS);                            GLCONST(GL_MAX_COMPUTE_IMAGE_UNIFORMS);
	GLCONST(GL_MAX_COMPUTE_SHARED_MEMORY_SIZE);                             GLCONST(GL_MAX_COMPUTE_UNIFORM_COMPONENTS);
	GLCONST(GL_MAX_COMPUTE_ATOMIC_COUNTER_BUFFERS);                         GLCONST(GL_MAX_COMPUTE_ATOMIC_COUNTERS);
	GLCONST(GL_MAX_COMBINED_COMPUTE_UNIFORM_COMPONENTS);                    GLCONST(GL_MAX_COMPUTE_WORK_GROUP_INVOCATIONS);
	GLCONST(GL_MAX_COMPUTE_WORK_GROUP_COUNT);                               GLCONST(GL_MAX_COMPUTE_WORK_GROUP_SIZE);
	GLCONST(GL_COMPUTE_WORK_GROUP_SIZE);                                    GLCONST(GL_UNIFORM_BLOCK_REFERENCED_BY_COMPUTE_SHADER);
	GLCONST(GL_ATOMIC_COUNTER_BUFFER_REFERENCED_BY_COMPUTE_SHADER);         GLCONST(GL_DISPATCH_INDIRECT_BUFFER);
	GLCONST(GL_DISPATCH_INDIRECT_BUFFER_BINDING);                           GLCONST(GL_COMPUTE_SHADER_BIT);
	GLCONST(GL_DEBUG_OUTPUT_SYNCHRONOUS);                                   GLCONST(GL_DEBUG_NEXT_LOGGED_MESSAGE_LENGTH);
	GLCONST(GL_DEBUG_CALLBACK_FUNCTION);                                    GLCONST(GL_DEBUG_CALLBACK_USER_PARAM);
	GLCONST(GL_DEBUG_SOURCE_API);                                           GLCONST(GL_DEBUG_SOURCE_WINDOW_SYSTEM);
	GLCONST(GL_DEBUG_SOURCE_SHADER_COMPILER);                               GLCONST(GL_DEBUG_SOURCE_THIRD_PARTY);
	GLCONST(GL_DEBUG_SOURCE_APPLICATION);                                   GLCONST(GL_DEBUG_SOURCE_OTHER);
	GLCONST(GL_DEBUG_TYPE_ERROR);                                           GLCONST(GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR);
	GLCONST(GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR);                              GLCONST(GL_DEBUG_TYPE_PORTABILITY);
	GLCONST(GL_DEBUG_TYPE_PERFORMANCE);                                     GLCONST(GL_DEBUG_TYPE_OTHER);
	GLCONST(GL_MAX_DEBUG_MESSAGE_LENGTH);                                   GLCONST(GL_MAX_DEBUG_LOGGED_MESSAGES);
	GLCONST(GL_DEBUG_LOGGED_MESSAGES);                                      GLCONST(GL_DEBUG_SEVERITY_HIGH);
	GLCONST(GL_DEBUG_SEVERITY_MEDIUM);                                      GLCONST(GL_DEBUG_SEVERITY_LOW);
	GLCONST(GL_DEBUG_TYPE_MARKER);                                          GLCONST(GL_DEBUG_TYPE_PUSH_GROUP);
	GLCONST(GL_DEBUG_TYPE_POP_GROUP);                                       GLCONST(GL_DEBUG_SEVERITY_NOTIFICATION);
	GLCONST(GL_MAX_DEBUG_GROUP_STACK_DEPTH);                                GLCONST(GL_DEBUG_GROUP_STACK_DEPTH);
	GLCONST(GL_BUFFER);                                                     GLCONST(GL_SHADER);
	GLCONST(GL_PROGRAM);                                                    GLCONST(GL_QUERY);
	GLCONST(GL_PROGRAM_PIPELINE);                                           GLCONST(GL_SAMPLER);
	GLCONST(GL_MAX_LABEL_LENGTH);                                           GLCONST(GL_DEBUG_OUTPUT);
	GLCONST(GL_CONTEXT_FLAG_DEBUG_BIT);                                     GLCONST(GL_MAX_UNIFORM_LOCATIONS);
	GLCONST(GL_FRAMEBUFFER_DEFAULT_WIDTH);                                  GLCONST(GL_FRAMEBUFFER_DEFAULT_HEIGHT);
	GLCONST(GL_FRAMEBUFFER_DEFAULT_LAYERS);                                 GLCONST(GL_FRAMEBUFFER_DEFAULT_SAMPLES);
	GLCONST(GL_FRAMEBUFFER_DEFAULT_FIXED_SAMPLE_LOCATIONS);                 GLCONST(GL_MAX_FRAMEBUFFER_WIDTH);
	GLCONST(GL_MAX_FRAMEBUFFER_HEIGHT);                                     GLCONST(GL_MAX_FRAMEBUFFER_LAYERS);
	GLCONST(GL_MAX_FRAMEBUFFER_SAMPLES);                                    GLCONST(GL_INTERNALFORMAT_SUPPORTED);
	GLCONST(GL_INTERNALFORMAT_PREFERRED);                                   GLCONST(GL_INTERNALFORMAT_RED_SIZE);
	GLCONST(GL_INTERNALFORMAT_GREEN_SIZE);                                  GLCONST(GL_INTERNALFORMAT_BLUE_SIZE);
	GLCONST(GL_INTERNALFORMAT_ALPHA_SIZE);                                  GLCONST(GL_INTERNALFORMAT_DEPTH_SIZE);
	GLCONST(GL_INTERNALFORMAT_STENCIL_SIZE);                                GLCONST(GL_INTERNALFORMAT_SHARED_SIZE);
	GLCONST(GL_INTERNALFORMAT_RED_TYPE);                                    GLCONST(GL_INTERNALFORMAT_GREEN_TYPE);
	GLCONST(GL_INTERNALFORMAT_BLUE_TYPE);                                   GLCONST(GL_INTERNALFORMAT_ALPHA_TYPE);
	GLCONST(GL_INTERNALFORMAT_DEPTH_TYPE);                                  GLCONST(GL_INTERNALFORMAT_STENCIL_TYPE);
	GLCONST(GL_MAX_WIDTH);                                                  GLCONST(GL_MAX_HEIGHT);
	GLCONST(GL_MAX_DEPTH);                                                  GLCONST(GL_MAX_LAYERS);
	GLCONST(GL_MAX_COMBINED_DIMENSIONS);                                    GLCONST(GL_COLOR_COMPONENTS);
	GLCONST(GL_DEPTH_COMPONENTS);                                           GLCONST(GL_STENCIL_COMPONENTS);
	GLCONST(GL_COLOR_RENDERABLE);                                           GLCONST(GL_DEPTH_RENDERABLE);
	GLCONST(GL_STENCIL_RENDERABLE);                                         GLCONST(GL_FRAMEBUFFER_RENDERABLE);
	GLCONST(GL_FRAMEBUFFER_RENDERABLE_LAYERED);                             GLCONST(GL_FRAMEBUFFER_BLEND);
	GLCONST(GL_READ_PIXELS);                                                GLCONST(GL_READ_PIXELS_FORMAT);
	GLCONST(GL_READ_PIXELS_TYPE);                                           GLCONST(GL_TEXTURE_IMAGE_FORMAT);
	GLCONST(GL_TEXTURE_IMAGE_TYPE);                                         GLCONST(GL_GET_TEXTURE_IMAGE_FORMAT);
	GLCONST(GL_GET_TEXTURE_IMAGE_TYPE);                                     GLCONST(GL_MIPMAP);
	GLCONST(GL_MANUAL_GENERATE_MIPMAP);                                     GLCONST(GL_AUTO_GENERATE_MIPMAP);
	GLCONST(GL_COLOR_ENCODING);                                             GLCONST(GL_SRGB_READ);
	GLCONST(GL_SRGB_WRITE);                                                 GLCONST(GL_FILTER);
	GLCONST(GL_VERTEX_TEXTURE);                                             GLCONST(GL_TESS_CONTROL_TEXTURE);
	GLCONST(GL_TESS_EVALUATION_TEXTURE);                                    GLCONST(GL_GEOMETRY_TEXTURE);
	GLCONST(GL_FRAGMENT_TEXTURE);                                           GLCONST(GL_COMPUTE_TEXTURE);
	GLCONST(GL_TEXTURE_SHADOW);                                             GLCONST(GL_TEXTURE_GATHER);
	GLCONST(GL_TEXTURE_GATHER_SHADOW);                                      GLCONST(GL_SHADER_IMAGE_LOAD);
	GLCONST(GL_SHADER_IMAGE_STORE);                                         GLCONST(GL_SHADER_IMAGE_ATOMIC);
	GLCONST(GL_IMAGE_TEXEL_SIZE);                                           GLCONST(GL_IMAGE_COMPATIBILITY_CLASS);
	GLCONST(GL_IMAGE_PIXEL_FORMAT);                                         GLCONST(GL_IMAGE_PIXEL_TYPE);
	GLCONST(GL_SIMULTANEOUS_TEXTURE_AND_DEPTH_TEST);                        GLCONST(GL_SIMULTANEOUS_TEXTURE_AND_STENCIL_TEST);
	GLCONST(GL_SIMULTANEOUS_TEXTURE_AND_DEPTH_WRITE);                       GLCONST(GL_SIMULTANEOUS_TEXTURE_AND_STENCIL_WRITE);
	GLCONST(GL_TEXTURE_COMPRESSED_BLOCK_WIDTH);                             GLCONST(GL_TEXTURE_COMPRESSED_BLOCK_HEIGHT);
	GLCONST(GL_TEXTURE_COMPRESSED_BLOCK_SIZE);                              GLCONST(GL_CLEAR_BUFFER);
	GLCONST(GL_TEXTURE_VIEW);                                               GLCONST(GL_VIEW_COMPATIBILITY_CLASS);
	GLCONST(GL_FULL_SUPPORT);                                               GLCONST(GL_CAVEAT_SUPPORT);
	GLCONST(GL_IMAGE_CLASS_4_X_32);                                         GLCONST(GL_IMAGE_CLASS_2_X_32);
	GLCONST(GL_IMAGE_CLASS_1_X_32);                                         GLCONST(GL_IMAGE_CLASS_4_X_16);
	GLCONST(GL_IMAGE_CLASS_2_X_16);                                         GLCONST(GL_IMAGE_CLASS_1_X_16);
	GLCONST(GL_IMAGE_CLASS_4_X_8);                                          GLCONST(GL_IMAGE_CLASS_2_X_8);
	GLCONST(GL_IMAGE_CLASS_1_X_8);                                          GLCONST(GL_IMAGE_CLASS_11_11_10);
	GLCONST(GL_IMAGE_CLASS_10_10_10_2);                                     GLCONST(GL_VIEW_CLASS_128_BITS);
	GLCONST(GL_VIEW_CLASS_96_BITS);                                         GLCONST(GL_VIEW_CLASS_64_BITS);
	GLCONST(GL_VIEW_CLASS_48_BITS);                                         GLCONST(GL_VIEW_CLASS_32_BITS);
	GLCONST(GL_VIEW_CLASS_24_BITS);                                         GLCONST(GL_VIEW_CLASS_16_BITS);
	GLCONST(GL_VIEW_CLASS_8_BITS);                                          GLCONST(GL_VIEW_CLASS_S3TC_DXT1_RGB);
	GLCONST(GL_VIEW_CLASS_S3TC_DXT1_RGBA);                                  GLCONST(GL_VIEW_CLASS_S3TC_DXT3_RGBA);
	GLCONST(GL_VIEW_CLASS_S3TC_DXT5_RGBA);                                  GLCONST(GL_VIEW_CLASS_RGTC1_RED);
	GLCONST(GL_VIEW_CLASS_RGTC2_RG);                                        GLCONST(GL_VIEW_CLASS_BPTC_UNORM);
	GLCONST(GL_VIEW_CLASS_BPTC_FLOAT);                                      GLCONST(GL_UNIFORM);
	GLCONST(GL_UNIFORM_BLOCK);                                              GLCONST(GL_PROGRAM_INPUT);
	GLCONST(GL_PROGRAM_OUTPUT);                                             GLCONST(GL_BUFFER_VARIABLE);
	GLCONST(GL_SHADER_STORAGE_BLOCK);                                       GLCONST(GL_VERTEX_SUBROUTINE);
	GLCONST(GL_TESS_CONTROL_SUBROUTINE);                                    GLCONST(GL_TESS_EVALUATION_SUBROUTINE);
	GLCONST(GL_GEOMETRY_SUBROUTINE);                                        GLCONST(GL_FRAGMENT_SUBROUTINE);
	GLCONST(GL_COMPUTE_SUBROUTINE);                                         GLCONST(GL_VERTEX_SUBROUTINE_UNIFORM);
	GLCONST(GL_TESS_CONTROL_SUBROUTINE_UNIFORM);                            GLCONST(GL_TESS_EVALUATION_SUBROUTINE_UNIFORM);
	GLCONST(GL_GEOMETRY_SUBROUTINE_UNIFORM);                                GLCONST(GL_FRAGMENT_SUBROUTINE_UNIFORM);
	GLCONST(GL_COMPUTE_SUBROUTINE_UNIFORM);                                 GLCONST(GL_TRANSFORM_FEEDBACK_VARYING);
	GLCONST(GL_ACTIVE_RESOURCES);                                           GLCONST(GL_MAX_NAME_LENGTH);
	GLCONST(GL_MAX_NUM_ACTIVE_VARIABLES);                                   GLCONST(GL_MAX_NUM_COMPATIBLE_SUBROUTINES);
	GLCONST(GL_NAME_LENGTH);                                                GLCONST(GL_TYPE);
	GLCONST(GL_ARRAY_SIZE);                                                 GLCONST(GL_OFFSET);
	GLCONST(GL_BLOCK_INDEX);                                                GLCONST(GL_ARRAY_STRIDE);
	GLCONST(GL_MATRIX_STRIDE);                                              GLCONST(GL_IS_ROW_MAJOR);
	GLCONST(GL_ATOMIC_COUNTER_BUFFER_INDEX);                                GLCONST(GL_BUFFER_BINDING);
	GLCONST(GL_BUFFER_DATA_SIZE);                                           GLCONST(GL_NUM_ACTIVE_VARIABLES);
	GLCONST(GL_ACTIVE_VARIABLES);                                           GLCONST(GL_REFERENCED_BY_VERTEX_SHADER);
	GLCONST(GL_REFERENCED_BY_TESS_CONTROL_SHADER);                          GLCONST(GL_REFERENCED_BY_TESS_EVALUATION_SHADER);
	GLCONST(GL_REFERENCED_BY_GEOMETRY_SHADER);                              GLCONST(GL_REFERENCED_BY_FRAGMENT_SHADER);
	GLCONST(GL_REFERENCED_BY_COMPUTE_SHADER);                               GLCONST(GL_TOP_LEVEL_ARRAY_SIZE);
	GLCONST(GL_TOP_LEVEL_ARRAY_STRIDE);                                     GLCONST(GL_LOCATION);
	GLCONST(GL_LOCATION_INDEX);                                             GLCONST(GL_IS_PER_PATCH);
	GLCONST(GL_SHADER_STORAGE_BUFFER);                                      GLCONST(GL_SHADER_STORAGE_BUFFER_BINDING);
	GLCONST(GL_SHADER_STORAGE_BUFFER_START);                                GLCONST(GL_SHADER_STORAGE_BUFFER_SIZE);
	GLCONST(GL_MAX_VERTEX_SHADER_STORAGE_BLOCKS);                           GLCONST(GL_MAX_GEOMETRY_SHADER_STORAGE_BLOCKS);
	GLCONST(GL_MAX_TESS_CONTROL_SHADER_STORAGE_BLOCKS);                     GLCONST(GL_MAX_TESS_EVALUATION_SHADER_STORAGE_BLOCKS);
	GLCONST(GL_MAX_FRAGMENT_SHADER_STORAGE_BLOCKS);                         GLCONST(GL_MAX_COMPUTE_SHADER_STORAGE_BLOCKS);
	GLCONST(GL_MAX_COMBINED_SHADER_STORAGE_BLOCKS);                         GLCONST(GL_MAX_SHADER_STORAGE_BUFFER_BINDINGS);
	GLCONST(GL_MAX_SHADER_STORAGE_BLOCK_SIZE);                              GLCONST(GL_SHADER_STORAGE_BUFFER_OFFSET_ALIGNMENT);
	GLCONST(GL_SHADER_STORAGE_BARRIER_BIT);                                 GLCONST(GL_MAX_COMBINED_SHADER_OUTPUT_RESOURCES);
	GLCONST(GL_DEPTH_STENCIL_TEXTURE_MODE);                                 GLCONST(GL_TEXTURE_BUFFER_OFFSET);
	GLCONST(GL_TEXTURE_BUFFER_SIZE);                                        GLCONST(GL_TEXTURE_BUFFER_OFFSET_ALIGNMENT);
	GLCONST(GL_TEXTURE_VIEW_MIN_LEVEL);                                     GLCONST(GL_TEXTURE_VIEW_NUM_LEVELS);
	GLCONST(GL_TEXTURE_VIEW_MIN_LAYER);                                     GLCONST(GL_TEXTURE_VIEW_NUM_LAYERS);
	GLCONST(GL_TEXTURE_IMMUTABLE_LEVELS);                                   GLCONST(GL_VERTEX_ATTRIB_BINDING);
	GLCONST(GL_VERTEX_ATTRIB_RELATIVE_OFFSET);                              GLCONST(GL_VERTEX_BINDING_DIVISOR);
	GLCONST(GL_VERTEX_BINDING_OFFSET);                                      GLCONST(GL_VERTEX_BINDING_STRIDE);
	GLCONST(GL_MAX_VERTEX_ATTRIB_RELATIVE_OFFSET);                          GLCONST(GL_MAX_VERTEX_ATTRIB_BINDINGS);
	GLCONST(GL_VERTEX_BINDING_BUFFER);                                      GLCONST(GL_DISPLAY_LIST);
	GLCONST(GL_MAX_VERTEX_ATTRIB_STRIDE);                                   GLCONST(GL_PRIMITIVE_RESTART_FOR_PATCHES_SUPPORTED);
	GLCONST(GL_TEXTURE_BUFFER_BINDING);                                     GLCONST(GL_MAP_PERSISTENT_BIT);
	GLCONST(GL_MAP_COHERENT_BIT);                                           GLCONST(GL_DYNAMIC_STORAGE_BIT);
	GLCONST(GL_CLIENT_STORAGE_BIT);                                         GLCONST(GL_CLIENT_MAPPED_BUFFER_BARRIER_BIT);
	GLCONST(GL_BUFFER_IMMUTABLE_STORAGE);                                   GLCONST(GL_BUFFER_STORAGE_FLAGS);
	GLCONST(GL_CLEAR_TEXTURE);                                              GLCONST(GL_LOCATION_COMPONENT);
	GLCONST(GL_TRANSFORM_FEEDBACK_BUFFER_INDEX);                            GLCONST(GL_TRANSFORM_FEEDBACK_BUFFER_STRIDE);
	GLCONST(GL_QUERY_BUFFER);                                               GLCONST(GL_QUERY_BUFFER_BARRIER_BIT);
	GLCONST(GL_QUERY_BUFFER_BINDING);                                       GLCONST(GL_QUERY_RESULT_NO_WAIT);
	GLCONST(GL_MIRROR_CLAMP_TO_EDGE);                                       GLCONST(GL_CONTEXT_LOST);
	GLCONST(GL_NEGATIVE_ONE_TO_ONE);                                        GLCONST(GL_ZERO_TO_ONE);
	GLCONST(GL_CLIP_ORIGIN);                                                GLCONST(GL_CLIP_DEPTH_MODE);
	GLCONST(GL_QUERY_WAIT_INVERTED);                                        GLCONST(GL_QUERY_NO_WAIT_INVERTED);
	GLCONST(GL_QUERY_BY_REGION_WAIT_INVERTED);                              GLCONST(GL_QUERY_BY_REGION_NO_WAIT_INVERTED);
	GLCONST(GL_MAX_CULL_DISTANCES);                                         GLCONST(GL_MAX_COMBINED_CLIP_AND_CULL_DISTANCES);
	GLCONST(GL_TEXTURE_TARGET);                                             GLCONST(GL_QUERY_TARGET);
	GLCONST(GL_TEXTURE_BINDING);                                            GLCONST(GL_GUILTY_CONTEXT_RESET);
	GLCONST(GL_INNOCENT_CONTEXT_RESET);                                     GLCONST(GL_UNKNOWN_CONTEXT_RESET);
	GLCONST(GL_RESET_NOTIFICATION_STRATEGY);                                GLCONST(GL_LOSE_CONTEXT_ON_RESET);
	GLCONST(GL_NO_RESET_NOTIFICATION);                                      GLCONST(GL_CONTEXT_FLAG_ROBUST_ACCESS_BIT);
	GLCONST(GL_CONTEXT_RELEASE_BEHAVIOR);                                   GLCONST(GL_CONTEXT_RELEASE_BEHAVIOR_FLUSH);
}

template<typename T>
struct function_traits;

template<typename R, typename ...Args>
struct function_traits<R(Args...)>
{
	typedef R result_type;
	typedef std::tuple<Args...> arg_types;
};

template<typename R, typename ...Args>
struct function_traits<R (*)(Args...)>
{
	typedef R result_type;
	typedef std::tuple<Args...> arg_types;
};

template<typename R, typename ...Args>
struct function_traits<R (APIENTRY *)(Args...)>
{
	typedef R result_type;
	typedef std::tuple<Args...> arg_types;
};

namespace detail
{
	template<typename F, typename Tuple, bool Done, int Total, int... N>
	struct call_impl
	{
		static typename function_traits<F>::result_type call(F f, Tuple&& t)
		{
			return call_impl<F, Tuple, Total == 1 + sizeof...(N), Total, N..., sizeof...(N)>::call(f, std::forward<Tuple>(t));
		}
	};

	template<typename F, typename Tuple, int Total, int... N>
	struct call_impl<F, Tuple, true, Total, N...>
	{
		static typename function_traits<F>::result_type call(F f, Tuple&& t)
		{
			return f(std::get<N>(std::forward<Tuple>(t))...);
		}
	};
}

template<typename F, typename Tuple>
typename function_traits<F>::result_type call(F f, Tuple&& t)
{
	typedef typename std::decay<Tuple>::type ttype;
	return detail::call_impl<F, Tuple, 0 == std::tuple_size<ttype>::value, std::tuple_size<ttype>::value>::call(f, std::forward<Tuple>(t));
}

template<typename T, typename Enable = void>
struct is_actual_integral
{
	static const bool value = std::is_integral<T>::value;
};

template<typename T>
struct is_actual_integral<T, typename std::enable_if<std::is_same<T, GLboolean>::value>::type>
{
	static const bool value = false;
};

template<typename T>
struct is_actual_integral<T, typename std::enable_if<std::is_same<T, GLchar>::value>::type>
{
	static const bool value = false;
};

template<typename T, typename Enable = void>
struct is_nonstring_pointer
{
	static const bool value = std::is_pointer<T>::value;
};

template<typename T>
struct is_nonstring_pointer<T, typename std::enable_if<std::is_same<T, const GLchar*>::value>::type>
{
	static const bool value = false;
};

template <int N, typename... T>
struct tuple_element;

template <typename T0, typename... T>
struct tuple_element<0, T0, T...>
{
	typedef T0 type;
};

template <int N, typename T0, typename... T>
struct tuple_element<N, T0, T...>
{
	typedef typename tuple_element<N-1, T...>::type type;
};

template<typename T>
typename std::enable_if<is_actual_integral<T>::value, T>::type
getGLParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkIntParam(t, slot);
}

template<typename T>
typename std::enable_if<std::is_same<T, GLboolean>::value, T>::type
getGLParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkBoolParam(t, slot);
}

template<typename T>
typename std::enable_if<std::is_floating_point<T>::value, T>::type
getGLParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkNumParam(t, slot);
}

template<typename T>
typename std::enable_if<std::is_same<T, const GLchar*>::value, T>::type
getGLParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkStringParam(t, slot);
}

template<typename T>
typename std::enable_if<is_nonstring_pointer<T>::value, T>::type
getGLParam(CrocThread* t, word_t slot)
{
	croc_ex_checkAnyParam(t, slot);

	if(croc_isMemblock(t, slot))
		return (T)croc_memblock_getData(t, slot);
	else if(croc_isInt(t, slot))
		return (T)croc_getInt(t, slot);
	else if(croc_isNull(t, slot))
		return nullptr;
	else
		croc_ex_paramTypeError(t, slot, "memblock|int|nullptr");

	return nullptr; // dummy
}

template<int Idx = 0, typename... T>
typename std::enable_if<Idx == sizeof...(T), void>::type
getGLParams(CrocThread* t, std::tuple<T...>& params)
{
	(void)t;
	(void)params;
}

template<int Idx = 0, typename... T>
typename std::enable_if<Idx < sizeof...(T), void>::type
getGLParams(CrocThread* t, std::tuple<T...>& params)
{
	std::get<Idx>(params) = getGLParam<typename tuple_element<Idx, T...>::type>(t, Idx + 1);
	getGLParams<Idx + 1, T...>(t, params);
}

template<typename T>
typename std::enable_if<std::is_void<T>::value, void>::type
pushGL(CrocThread* t, std::function<T()> func)
{
	(void)t;
	func();
}

template<typename T>
typename std::enable_if<is_actual_integral<T>::value, void>::type
pushGL(CrocThread* t, T val)
{
	croc_pushInt(t, val);
}

template<typename T>
typename std::enable_if<std::is_same<T, GLboolean>::value, void>::type
pushGL(CrocThread* t, T val)
{
	croc_pushBool(t, val);
}

template<typename T>
typename std::enable_if<std::is_floating_point<T>::value, void>::type
pushGL(CrocThread* t, T val)
{
	croc_pushFloat(t, val);
}

template<typename R, typename... Args>
struct wrapgl;

template<typename... Args>
struct wrapgl<void, std::tuple<Args...>>
{
	static const uword_t numParams = sizeof...(Args);

	template<void (* APIENTRYP Fun)(Args...)>
	struct func_holder
	{
		static word_t func(CrocThread* t)
		{
			std::tuple<Args...> _params;
			getGLParams(t, _params);
			call(*Fun, _params);
			return 0;
		}
	};
};

template<typename R, typename... Args>
struct wrapgl<R, std::tuple<Args...>>
{
	static const uword_t numParams = sizeof...(Args);

	template<R (* APIENTRYP Fun)(Args...)>
	struct func_holder
	{
		static word_t func(CrocThread* t)
		{
			std::tuple<Args...> _params;
			getGLParams(t, _params);
			pushGL(t, call(*Fun, _params));
			return 1;
		}
	};
};

#define NUMPARAMS(FUNC) wrapgl<function_traits<decltype(FUNC)>::result_type, function_traits<decltype(FUNC)>::arg_types>::numParams
#define WRAPGL(FUNC) wrapgl<function_traits<decltype(FUNC)>::result_type, function_traits<decltype(FUNC)>::arg_types>::func_holder<&FUNC>::func
#define WRAP(FUNC) {#FUNC, NUMPARAMS(FUNC), &WRAPGL(FUNC)}

word_t crocglGetString(CrocThread* t)
{
	auto val = cast(GLenum)croc_ex_checkIntParam(t, 1);
	croc_pushString(t, cast(const char*)glGetString(val));
	return 1;
}

const CrocRegisterFunc _gl1_0[] =
{
	WRAP(glCullFace),
	WRAP(glFrontFace),
	WRAP(glHint),
	WRAP(glLineWidth),
	WRAP(glPointSize),
	WRAP(glPolygonMode),
	WRAP(glScissor),
	WRAP(glTexParameterf),
	WRAP(glTexParameterfv),
	WRAP(glTexParameteri),
	WRAP(glTexParameteriv),
	WRAP(glTexImage1D),
	WRAP(glTexImage2D),
	WRAP(glDrawBuffer),
	WRAP(glClear),
	WRAP(glClearColor),
	WRAP(glClearStencil),
	WRAP(glClearDepth),
	WRAP(glStencilMask),
	WRAP(glColorMask),
	WRAP(glDepthMask),
	WRAP(glDisable),
	WRAP(glEnable),
	WRAP(glFinish),
	WRAP(glFlush),
	WRAP(glBlendFunc),
	WRAP(glLogicOp),
	WRAP(glStencilFunc),
	WRAP(glStencilOp),
	WRAP(glDepthFunc),
	WRAP(glPixelStoref),
	WRAP(glPixelStorei),
	WRAP(glReadBuffer),
	WRAP(glReadPixels),
	WRAP(glGetBooleanv),
	WRAP(glGetDoublev),
	WRAP(glGetError),
	WRAP(glGetFloatv),
	WRAP(glGetIntegerv),
	{"glGetString", 1, &crocglGetString},
	WRAP(glGetTexImage),
	WRAP(glGetTexParameterfv),
	WRAP(glGetTexParameteriv),
	WRAP(glGetTexLevelParameterfv),
	WRAP(glGetTexLevelParameteriv),
	WRAP(glIsEnabled),
	WRAP(glDepthRange),
	WRAP(glViewport),
	{nullptr, 0, nullptr}
};

void loadGL1_0(CrocThread* t)
{
	if(!GLAD_GL_VERSION_1_0) return;
	croc_ex_registerGlobals(t, _gl1_0);
}

template<void(* APIENTRYP Fun)(GLsizei, GLuint*)>
struct wrapGen
{
	static word_t func(CrocThread* t)
	{
		auto num = croc_ex_checkIntParam(t, 1);
		auto haveArr = croc_ex_optParam(t, 2, CrocType_Array);

		if(num < 1 || (!haveArr && num > 20) || (haveArr && num > 1024))
			croc_eh_throwStd(t, "RangeError", "Invalid number of names to generate");

		GLuint names[1024];
		(*Fun)(cast(GLsizei)num, names);

		if(haveArr)
		{
			croc_lenai(t, 2, num);

			for(word i = 0; i < num; i++)
			{
				croc_pushInt(t, names[i]);
				croc_idxai(t, 2, i);
			}

			croc_dup(t, 2);
			return 1;
		}
		else
		{
			for(word i = 0; i < num; i++)
				croc_pushInt(t, names[i]);

			return num;
		}
	}
};

#define WRAPGEN(FUNC) {#FUNC, 2, &wrapGen<&FUNC>::func}

template<void(* APIENTRYP Fun)(GLsizei, const GLuint*)>
struct wrapDelete
{
	static word_t func(CrocThread* t)
	{
		croc_ex_checkAnyParam(t, 1);
		auto numParams = croc_getStackSize(t) - 1;
		GLsizei num;
		GLuint names[1024];

		if(croc_isArray(t, 1))
		{
			if(numParams > 1)
				croc_eh_throwStd(t, "ParamError", "Expected at most 1 parameter, but was given %d", numParams);

			auto len = croc_len(t, 1);

			if(len > 1024)
				croc_eh_throwStd(t, "ValueError", "Array too long (> 1024 elements)");

			for(word i = 0; i < len; i++)
			{
				croc_idxi(t, 1, i);

				if(!croc_isInt(t, -1))
					croc_eh_throwStd(t, "TypeError", "Array element %d is not an integer", i);

				names[i] = croc_getInt(t, -1);
				croc_popTop(t);
			}

			num = cast(GLsizei)len;
		}
		else
		{
			if(numParams > 1024)
				croc_eh_throwStd(t, "ParamError", "Expected at most 1024 parameters, but was given %d", numParams);

			for(word i = 1; i <= numParams; i++)
				names[i] = croc_ex_checkIntParam(t, i);

			num = cast(GLsizei)numParams;
		}

		(*Fun)(num, names);
		return 0;
	}
};

#define WRAPDELETE(FUNC) {#FUNC, -1, &wrapDelete<&FUNC>::func}

const CrocRegisterFunc _gl1_1[] =
{
	WRAP(glDrawArrays),
	WRAP(glDrawElements),
	WRAP(glPolygonOffset),
	WRAP(glCopyTexImage1D),
	WRAP(glCopyTexImage2D),
	WRAP(glCopyTexSubImage1D),
	WRAP(glCopyTexSubImage2D),
	WRAP(glTexSubImage1D),
	WRAP(glTexSubImage2D),
	WRAP(glBindTexture),
	WRAPDELETE(glDeleteTextures),
	WRAPGEN(glGenTextures),
	WRAP(glIsTexture),
	{nullptr, 0, nullptr}
};

void loadGL1_1(CrocThread* t)
{
	if(!GLAD_GL_VERSION_1_1) return;
	croc_ex_registerGlobals(t, _gl1_1);
}

const CrocRegisterFunc _gl1_2[] =
{
	WRAP(glDrawRangeElements),
	WRAP(glTexImage3D),
	WRAP(glTexSubImage3D),
	WRAP(glCopyTexSubImage3D),
	{nullptr, 0, nullptr}
};

void loadGL1_2(CrocThread* t)
{
	if(!GLAD_GL_VERSION_1_2) return;
	croc_ex_registerGlobals(t, _gl1_2);
}

const CrocRegisterFunc _gl1_3[] =
{
	WRAP(glActiveTexture),
	WRAP(glSampleCoverage),
	WRAP(glCompressedTexImage3D),
	WRAP(glCompressedTexImage2D),
	WRAP(glCompressedTexImage1D),
	WRAP(glCompressedTexSubImage3D),
	WRAP(glCompressedTexSubImage2D),
	WRAP(glCompressedTexSubImage1D),
	WRAP(glGetCompressedTexImage),
	{nullptr, 0, nullptr}
};

void loadGL1_3(CrocThread* t)
{
	if(!GLAD_GL_VERSION_1_3) return;
	croc_ex_registerGlobals(t, _gl1_3);
}

const CrocRegisterFunc _gl1_4[] =
{
	WRAP(glBlendFuncSeparate),
	WRAP(glMultiDrawArrays),
	// WRAP(glMultiDrawElements),
	WRAP(glPointParameterf),
	WRAP(glPointParameterfv),
	WRAP(glPointParameteri),
	WRAP(glPointParameteriv),
	WRAP(glBlendColor),
	WRAP(glBlendEquation),
	{nullptr, 0, nullptr}
};

void loadGL1_4(CrocThread* t)
{
	if(!GLAD_GL_VERSION_1_4) return;
	croc_ex_registerGlobals(t, _gl1_4);
}

const char* crocglMapBuffer_docs
= Docstr(DFunc("glMapBuffer") DParam("target", "int") DParam("access", "int") DParamD("mb", "memblock", "null")
R"(This function returns a pointer. Since we can determine the buffer's size, we can return the mapped buffer data as a
memblock. You can pass a memblock to be used for this purpose as \tt{mb}, but if not, one will be created for you. If
you pass one, its data (if any) will be freed and it will become a view of the buffer data. In either case the resulting
memblock will not own its data.)");

word_t crocglMapBuffer(CrocThread* t)
{
	auto target = cast(GLenum)croc_ex_checkIntParam(t, 1);
	auto access = cast(GLenum)croc_ex_checkIntParam(t, 2);
	auto haveMemblock = croc_ex_optParam(t, 3, CrocType_Memblock);

	GLint size;
	glGetBufferParameteriv(target, GL_BUFFER_SIZE, &size);

	if(auto ptr = glMapBuffer(target, access))
	{
		if(haveMemblock)
		{
			croc_memblock_reviewNativeArray(t, 3, ptr, size);
			croc_dup(t, 3);
		}
		else
			croc_memblock_viewNativeArray(t, ptr, size);
	}
	else
		croc_pushNull(t);

	return 1;
}

const CrocRegisterFunc _gl1_5[] =
{
	WRAPGEN(glGenQueries),
	WRAPDELETE(glDeleteQueries),
	WRAP(glIsQuery),
	WRAP(glBeginQuery),
	WRAP(glEndQuery),
	WRAP(glGetQueryiv),
	WRAP(glGetQueryObjectiv),
	WRAP(glGetQueryObjectuiv),
	WRAP(glBindBuffer),
	WRAPDELETE(glDeleteBuffers),
	WRAPGEN(glGenBuffers),
	WRAP(glIsBuffer),
	WRAP(glBufferData),
	WRAP(glBufferSubData),
	WRAP(glGetBufferSubData),
	{"glMapBuffer", 3, &crocglMapBuffer},
	WRAP(glUnmapBuffer),
	WRAP(glGetBufferParameteriv),
	// WRAP(glGetBufferPointerv),
	{nullptr, 0, nullptr}
};

void loadGL1_5(CrocThread* t)
{
	if(!GLAD_GL_VERSION_1_5) return;
	croc_ex_registerGlobals(t, _gl1_5);
}

const char* crocglShaderSource_docs
= Docstr(DFunc("glShaderSource") DParam("shader", "int") DParam("source", "string")
R"(This only differs from the native function in that the native function takes an array of strings whereas this takes a
single string. You can join strings easily in Croc, so why bother!)");

word_t crocglShaderSource(CrocThread* t)
{
	auto shader = cast(GLuint)croc_ex_checkIntParam(t, 1);
	uword_t length;
	auto src = croc_ex_checkStringParamn(t, 2, &length);

	auto str = cast(const GLchar*)src;
	GLint len = length;

	glShaderSource(shader, 1, &str, &len);

	return 0;
}

const char* crocglGetVertexAttribPointerv_docs
= Docstr(DFunc("glGetVertexAttribPointerv") DParam("index", "int") DParam("name", "int")
R"(\returns the pointer as an integer rather than taking a pointer-to-pointer parameter.)");

word_t crocglGetVertexAttribPointerv(CrocThread* t)
{
	auto index = cast(GLuint)croc_ex_checkIntParam(t, 1);
	auto name = cast(GLenum)croc_ex_checkIntParam(t, 2);
	GLvoid* ptr;
	glGetVertexAttribPointerv(index, name, &ptr);
	croc_pushInt(t, cast(crocint)ptr);
	return 1;
}

const char* crocglGetActiveAttrib_docs
= Docstr(DFunc("glGetActiveAttrib") DParam("program", "int") DParam("index", "int")
R"(\returns three values: an int of the type of the active attribute, an int of the size of the active attribute, and a
string of the attribute's name.)");

word_t crocglGetActiveAttrib(CrocThread* t)
{
	auto program = cast(GLuint)croc_ex_checkIntParam(t, 1);
	auto index = cast(GLuint)croc_ex_checkIntParam(t, 2);
	GLchar buf[512];
	GLsizei length;
	GLint size;
	GLenum type;

	glGetActiveAttrib(program, index, sizeof(buf) / sizeof(GLchar), &length, &size, &type, buf);

	if(length == 0)
		return 0;

	croc_pushInt(t, type);
	croc_pushInt(t, size);
	croc_pushStringn(t, buf, length);
	return 3;
}

const char* crocglGetActiveUniform_docs
= Docstr(DFunc("glGetActiveUniform") DParam("program", "int") DParam("index", "int")
R"(\returns three values: an int of the type of the active uniform, an int of the size of the active uniform, and a
string of the uniform's name.)");

word_t crocglGetActiveUniform(CrocThread* t)
{
	auto program = cast(GLuint)croc_ex_checkIntParam(t, 1);
	auto index = cast(GLuint)croc_ex_checkIntParam(t, 2);
	GLchar buf[512];
	GLsizei length;
	GLint size;
	GLenum type;

	glGetActiveUniform(program, index, sizeof(buf) / sizeof(GLchar), &length, &size, &type, buf);

	if(length == 0)
		return 0;

	croc_pushInt(t, type);
	croc_pushInt(t, size);
	croc_pushStringn(t, buf, length);
	return 3;
}

word_t crocglGetProgramInfoLog(CrocThread* t)
{
	auto program = cast(GLuint)croc_ex_checkIntParam(t, 1);
	GLint length = -1;
	glGetProgramiv(program, GL_INFO_LOG_LENGTH, &length);

	if(length == -1)
		return 0;

	uword_t size = length * sizeof(GLchar);
	auto buf = cast(GLchar*)croc_mem_alloc(t, size);
	GLsizei realLength = 0;
	glGetProgramInfoLog(program, length, &realLength, buf);
	auto ok = croc_tryPushStringn(t, buf, realLength);
	croc_mem_free(t, cast(void**)&buf, &size);

	if(!ok)
		croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

	return 1;
}

word_t crocglGetShaderInfoLog(CrocThread* t)
{
	auto shader = cast(GLuint)croc_ex_checkIntParam(t, 1);
	GLint length = -1;
	glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &length);

	if(length == -1)
		return 0;

	uword_t size = length * sizeof(GLchar);
	auto buf = cast(GLchar*)croc_mem_alloc(t, size);
	GLsizei realLength = 0;
	glGetShaderInfoLog(shader, length, &realLength, buf);
	auto ok = croc_tryPushStringn(t, buf, realLength);
	croc_mem_free(t, cast(void**)&buf, &size);

	if(!ok)
		croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

	return 1;
}

word_t crocglGetShaderSource(CrocThread* t)
{
	auto shader = cast(GLuint)croc_ex_checkIntParam(t, 1);
	GLint length = -1;
	glGetShaderiv(shader, GL_SHADER_SOURCE_LENGTH, &length);

	if(length == -1)
		return 0;

	uword_t size = length * sizeof(GLchar);
	auto buf = cast(GLchar*)croc_mem_alloc(t, size);
	GLsizei realLength = 0;
	glGetShaderSource(shader, length, &realLength, buf);
	auto ok = croc_tryPushStringn(t, buf, realLength);
	croc_mem_free(t, cast(void**)&buf, &size);

	if(!ok)
		croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

	return 1;
}

const CrocRegisterFunc _gl2_0[] =
{
	WRAP(glBlendEquationSeparate),
	WRAP(glDrawBuffers),
	WRAP(glStencilOpSeparate),
	WRAP(glStencilFuncSeparate),
	WRAP(glStencilMaskSeparate),
	WRAP(glAttachShader),
	WRAP(glBindAttribLocation),
	WRAP(glCompileShader),
	WRAP(glCreateProgram),
	WRAP(glCreateShader),
	WRAP(glDeleteProgram),
	WRAP(glDeleteShader),
	WRAP(glDetachShader),
	WRAP(glDisableVertexAttribArray),
	WRAP(glEnableVertexAttribArray),
	{"glGetActiveAttrib", 2, crocglGetActiveAttrib},
	{"glGetActiveUniform", 2, crocglGetActiveUniform},
	WRAP(glGetAttachedShaders),
	WRAP(glGetAttribLocation),
	WRAP(glGetProgramiv),
	{"glGetProgramInfoLog", 1, crocglGetProgramInfoLog},
	WRAP(glGetShaderiv),
	{"glGetShaderInfoLog", 1, crocglGetShaderInfoLog},
	{"glGetShaderSource", 1, crocglGetShaderSource},
	WRAP(glGetUniformLocation),
	WRAP(glGetUniformfv),
	WRAP(glGetUniformiv),
	WRAP(glGetVertexAttribdv),
	WRAP(glGetVertexAttribfv),
	WRAP(glGetVertexAttribiv),
	{"glGetVertexAttribPointerv", 2, &crocglGetVertexAttribPointerv},
	WRAP(glIsProgram),
	WRAP(glIsShader),
	WRAP(glLinkProgram),
	{"glShaderSource", 2, &crocglShaderSource},
	WRAP(glUseProgram),
	WRAP(glUniform1f),
	WRAP(glUniform2f),
	WRAP(glUniform3f),
	WRAP(glUniform4f),
	WRAP(glUniform1i),
	WRAP(glUniform2i),
	WRAP(glUniform3i),
	WRAP(glUniform4i),
	WRAP(glUniform1fv),
	WRAP(glUniform2fv),
	WRAP(glUniform3fv),
	WRAP(glUniform4fv),
	WRAP(glUniform1iv),
	WRAP(glUniform2iv),
	WRAP(glUniform3iv),
	WRAP(glUniform4iv),
	WRAP(glUniformMatrix2fv),
	WRAP(glUniformMatrix3fv),
	WRAP(glUniformMatrix4fv),
	WRAP(glValidateProgram),
	WRAP(glVertexAttrib1d),
	WRAP(glVertexAttrib1dv),
	WRAP(glVertexAttrib1f),
	WRAP(glVertexAttrib1fv),
	WRAP(glVertexAttrib1s),
	WRAP(glVertexAttrib1sv),
	WRAP(glVertexAttrib2d),
	WRAP(glVertexAttrib2dv),
	WRAP(glVertexAttrib2f),
	WRAP(glVertexAttrib2fv),
	WRAP(glVertexAttrib2s),
	WRAP(glVertexAttrib2sv),
	WRAP(glVertexAttrib3d),
	WRAP(glVertexAttrib3dv),
	WRAP(glVertexAttrib3f),
	WRAP(glVertexAttrib3fv),
	WRAP(glVertexAttrib3s),
	WRAP(glVertexAttrib3sv),
	WRAP(glVertexAttrib4Nbv),
	WRAP(glVertexAttrib4Niv),
	WRAP(glVertexAttrib4Nsv),
	WRAP(glVertexAttrib4Nub),
	WRAP(glVertexAttrib4Nubv),
	WRAP(glVertexAttrib4Nuiv),
	WRAP(glVertexAttrib4Nusv),
	WRAP(glVertexAttrib4bv),
	WRAP(glVertexAttrib4d),
	WRAP(glVertexAttrib4dv),
	WRAP(glVertexAttrib4f),
	WRAP(glVertexAttrib4fv),
	WRAP(glVertexAttrib4iv),
	WRAP(glVertexAttrib4s),
	WRAP(glVertexAttrib4sv),
	WRAP(glVertexAttrib4ubv),
	WRAP(glVertexAttrib4uiv),
	WRAP(glVertexAttrib4usv),
	WRAP(glVertexAttribPointer),
	{nullptr, 0, nullptr}
};

void loadGL2_0(CrocThread* t)
{
	if(!GLAD_GL_VERSION_2_0) return;
	croc_ex_registerGlobals(t, _gl2_0);
}

const CrocRegisterFunc _gl2_1[] =
{
	WRAP(glUniformMatrix2x3fv),
	WRAP(glUniformMatrix3x2fv),
	WRAP(glUniformMatrix2x4fv),
	WRAP(glUniformMatrix4x2fv),
	WRAP(glUniformMatrix3x4fv),
	WRAP(glUniformMatrix4x3fv),
	{nullptr, 0, nullptr}
};

void loadGL2_1(CrocThread* t)
{
	if(!GLAD_GL_VERSION_2_1) return;
	croc_ex_registerGlobals(t, _gl2_1);
}

word_t crocglGetStringi(CrocThread* t)
{
	auto val = cast(GLenum)croc_ex_checkIntParam(t, 1);
	auto idx = cast(GLuint)croc_ex_checkIntParam(t, 2);
	croc_pushString(t, cast(const char*)glGetStringi(val, idx));
	return 1;
}

const char* crocglMapBufferRange_docs
= Docstr(DFunc("glMapBufferRange") DParam("target", "int") DParam("offset", "int") DParam("length", "int") DParam(
	"access", "int") DParamD("mb", "memblock", "null")
R"(Works very similarly to \link{glMapBuffer}.)");

word_t crocglMapBufferRange(CrocThread* t)
{
	auto target = cast(GLenum)croc_ex_checkIntParam(t, 1);
	auto offset = cast(GLintptr)croc_ex_checkIntParam(t, 2);
	auto length = cast(GLsizeiptr)croc_ex_checkIntParam(t, 3);
	auto access = cast(GLenum)croc_ex_checkIntParam(t, 4);
	auto haveMemblock = croc_ex_optParam(t, 5, CrocType_Memblock);

	if(auto ptr = glMapBufferRange(target, offset, length, access))
	{
		if(haveMemblock)
		{
			croc_memblock_reviewNativeArray(t, 5, ptr, length);
			croc_dup(t, 5);
		}
		else
			croc_memblock_viewNativeArray(t, ptr, length);
	}
	else
		croc_pushNull(t);

	return 1;
}

const char* crocglTransformFeedbackVaryings_docs
= Docstr(DFunc("glTransformFeedbackVaryings") DParam("program", "int") DParam("varyings", "array") DParam("mode", "int")
R"(The \tt{varyings} parameter must be an array of strings. That's it.)");

word_t crocglTransformFeedbackVaryings(CrocThread* t)
{
	auto program = cast(GLuint)croc_ex_checkIntParam(t, 1);
	croc_ex_checkParam(t, 2, CrocType_Array);
	auto mode = cast(GLenum)croc_ex_checkIntParam(t, 3);
	auto varyingsLen = croc_len(t, 2);

	for(word i = 0; i < varyingsLen; i++)
	{
		croc_idxi(t, 2, i);

		if(!croc_isString(t, -1))
			croc_eh_throwStd(t, "TypeError", "Array element %d is not a string", i);

		croc_popTop(t);
	}

	const GLchar* varyings_[128];
	const GLchar** varyings;
	uword_t varyingsSize;

	if(varyingsLen < 128)
		varyings = varyings_;
	else
	{
		varyingsSize = varyingsLen * sizeof(GLchar*);
		varyings = cast(const GLchar**)croc_mem_alloc(t, varyingsSize);
	}

	for(word i = 0; i < varyingsLen; i++)
	{
		croc_idxi(t, 2, i);
		varyings[i] = croc_getString(t, -1);
		croc_popTop(t);
	}

	glTransformFeedbackVaryings(program, varyingsLen, varyings, mode);

	if(varyings != varyings_)
		croc_mem_free(t, cast(void**)&varyings, &varyingsSize);

	return 0;
}

const char* crocglGetTransformFeedbackVarying_docs
= Docstr(DFunc("glGetTransformFeedbackVarying") DParam("program", "int") DParam("index", "int")
R"(\returns nothing if an error occurred. Otherwise, returns three values: an int of the type of the varying, an int of
the size of the varying, and a string of the varying's name.)");

word_t crocglGetTransformFeedbackVarying(CrocThread* t)
{
	auto program = cast(GLuint)croc_ex_checkIntParam(t, 1);
	auto index = cast(GLuint)croc_ex_checkIntParam(t, 2);

	GLint length = -1;
	glGetProgramiv(program, GL_TRANSFORM_FEEDBACK_VARYING_MAX_LENGTH, &length);

	if(length == -1)
		return 0;

	uword_t size = length * sizeof(GLchar);
	auto buf = cast(GLchar*)croc_mem_alloc(t, size);
	GLsizei realLength = 0;
	GLint varyingSize;
	GLenum type;
	glGetTransformFeedbackVarying(program, index, length, &realLength, &varyingSize, &type, buf);
	auto ok = croc_tryPushStringn(t, buf, realLength);
	croc_mem_free(t, cast(void**)&buf, &size);

	if(!ok)
		croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

	croc_pushInt(t, type);
	croc_pushInt(t, varyingSize);
	croc_moveToTop(t, -3);
	return 3;
}

const CrocRegisterFunc _gl3_0[] =
{
	WRAP(glColorMaski),
	WRAP(glGetBooleani_v),
	WRAP(glGetIntegeri_v),
	WRAP(glEnablei),
	WRAP(glDisablei),
	WRAP(glIsEnabledi),
	WRAP(glBeginTransformFeedback),
	WRAP(glEndTransformFeedback),
	WRAP(glBindBufferRange),
	WRAP(glBindBufferBase),
	{"glTransformFeedbackVaryings", 3, &crocglTransformFeedbackVaryings},
	{"glGetTransformFeedbackVarying", 2, &crocglGetTransformFeedbackVarying},
	WRAP(glClampColor),
	WRAP(glBeginConditionalRender),
	WRAP(glEndConditionalRender),
	WRAP(glVertexAttribIPointer),
	WRAP(glGetVertexAttribIiv),
	WRAP(glGetVertexAttribIuiv),
	WRAP(glVertexAttribI1i),
	WRAP(glVertexAttribI2i),
	WRAP(glVertexAttribI3i),
	WRAP(glVertexAttribI4i),
	WRAP(glVertexAttribI1ui),
	WRAP(glVertexAttribI2ui),
	WRAP(glVertexAttribI3ui),
	WRAP(glVertexAttribI4ui),
	WRAP(glVertexAttribI1iv),
	WRAP(glVertexAttribI2iv),
	WRAP(glVertexAttribI3iv),
	WRAP(glVertexAttribI4iv),
	WRAP(glVertexAttribI1uiv),
	WRAP(glVertexAttribI2uiv),
	WRAP(glVertexAttribI3uiv),
	WRAP(glVertexAttribI4uiv),
	WRAP(glVertexAttribI4bv),
	WRAP(glVertexAttribI4sv),
	WRAP(glVertexAttribI4ubv),
	WRAP(glVertexAttribI4usv),
	WRAP(glGetUniformuiv),
	WRAP(glBindFragDataLocation),
	WRAP(glGetFragDataLocation),
	WRAP(glUniform1ui),
	WRAP(glUniform2ui),
	WRAP(glUniform3ui),
	WRAP(glUniform4ui),
	WRAP(glUniform1uiv),
	WRAP(glUniform2uiv),
	WRAP(glUniform3uiv),
	WRAP(glUniform4uiv),
	WRAP(glTexParameterIiv),
	WRAP(glTexParameterIuiv),
	WRAP(glGetTexParameterIiv),
	WRAP(glGetTexParameterIuiv),
	WRAP(glClearBufferiv),
	WRAP(glClearBufferuiv),
	WRAP(glClearBufferfv),
	WRAP(glClearBufferfi),
	{"glGetStringi", 2, &crocglGetStringi},
	WRAP(glIsRenderbuffer),
	WRAP(glBindRenderbuffer),
	WRAPDELETE(glDeleteRenderbuffers),
	WRAPGEN(glGenRenderbuffers),
	WRAP(glRenderbufferStorage),
	WRAP(glGetRenderbufferParameteriv),
	WRAP(glIsFramebuffer),
	WRAP(glBindFramebuffer),
	WRAPDELETE(glDeleteFramebuffers),
	WRAPGEN(glGenFramebuffers),
	WRAP(glCheckFramebufferStatus),
	WRAP(glFramebufferTexture1D),
	WRAP(glFramebufferTexture2D),
	WRAP(glFramebufferTexture3D),
	WRAP(glFramebufferRenderbuffer),
	WRAP(glGetFramebufferAttachmentParameteriv),
	WRAP(glGenerateMipmap),
	WRAP(glBlitFramebuffer),
	WRAP(glRenderbufferStorageMultisample),
	WRAP(glFramebufferTextureLayer),
	{"glMapBufferRange", 5, &crocglMapBufferRange},
	WRAP(glFlushMappedBufferRange),
	WRAP(glBindVertexArray),
	WRAPDELETE(glDeleteVertexArrays),
	WRAPGEN(glGenVertexArrays),
	WRAP(glIsVertexArray),
	{nullptr, 0, nullptr}
};

void loadGL3_0(CrocThread* t)
{
	if(!GLAD_GL_VERSION_3_0) return;
	croc_ex_registerGlobals(t, _gl3_0);
}

const char* crocglGetUniformIndices_docs
= Docstr(DFunc("glGetUniformIndices") DParam("program", "int") DParam("names", "array") DParam("indices", "array")
R"(The \tt{names} parameter must be an array of strings of names of uniforms. The \tt{indices} array will be used as the
output; it will be set to the same length as \tt{names}, and will be filled with the uniform indices.)");

word_t crocglGetUniformIndices(CrocThread* t)
{
	auto program = cast(GLuint)croc_ex_checkIntParam(t, 1);
	croc_ex_checkParam(t, 2, CrocType_Array);
	croc_ex_checkParam(t, 3, CrocType_Array);
	auto size = croc_len(t, 2);

	for(word i = 0; i < size; i++)
	{
		croc_idxi(t, 2, i);

		if(!croc_isString(t, -1))
			croc_eh_throwStd(t, "TypeError", "All uniform names must be strings");

		croc_popTop(t);
	}

	croc_lenai(t, 3, size);

	const GLchar* names_[32];
	GLuint indices_[32];
	const GLchar** names;
	GLuint* indices;

	if(size < 32)
	{
		names = names_;
		indices = indices_;
	}
	else
	{
		names = cast(const GLchar**)croc_mem_alloc(t, sizeof(GLchar*) * size);
		indices = cast(GLuint*)croc_mem_alloc(t, sizeof(GLuint) * size);
	}

	for(word i = 0; i < size; i++)
	{
		croc_idxi(t, 2, i);
		names[i] = croc_getString(t, -1);
		croc_popTop(t);
	}

	glGetUniformIndices(program, size, names, indices);

	for(word i = 0; i < size; i++)
	{
		croc_pushInt(t, indices[i]);
		croc_idxai(t, 3, i);
	}

	if(names != names_)
	{
		auto size_ = cast(uword_t)size;
		croc_mem_free(t, cast(void**)&names, &size_);
		size_ = cast(uword_t)size;
		croc_mem_free(t, cast(void**)&indices, &size_);
	}

	return 0;
}

word_t crocglGetActiveUniformName(CrocThread* t)
{
	auto program = cast(GLuint)croc_ex_checkIntParam(t, 1);
	auto index = cast(GLuint)croc_ex_checkIntParam(t, 2);

	GLint length = -1;
	glGetProgramiv(program, GL_ACTIVE_UNIFORM_MAX_LENGTH, &length);

	if(length == -1)
		return 0;

	uword_t size = length * sizeof(GLchar);
	auto buf = cast(GLchar*)croc_mem_alloc(t, size);
	GLsizei realLength = 0;
	glGetActiveUniformName(program, index, length, &realLength, buf);
	auto ok = croc_tryPushStringn(t, buf, realLength);
	croc_mem_free(t, cast(void**)&buf, &size);

	if(!ok)
		croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

	return 1;
}

word_t crocglGetActiveUniformBlockName(CrocThread* t)
{
	auto program = cast(GLuint)croc_ex_checkIntParam(t, 1);
	auto index = cast(GLuint)croc_ex_checkIntParam(t, 2);

	GLint length = -1;
	glGetProgramiv(program, GL_ACTIVE_UNIFORM_BLOCK_MAX_NAME_LENGTH, &length);

	if(length == -1)
		return 0;

	uword_t size = length * sizeof(GLchar);
	auto buf = cast(GLchar*)croc_mem_alloc(t, size);
	GLsizei realLength = 0;
	glGetActiveUniformBlockName(program, index, length, &realLength, buf);
	auto ok = croc_tryPushStringn(t, buf, realLength);
	croc_mem_free(t, cast(void**)&buf, &size);

	if(!ok)
		croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

	return 1;
}

const CrocRegisterFunc _gl3_1[] =
{
	WRAP(glDrawArraysInstanced),
	WRAP(glDrawElementsInstanced),
	WRAP(glTexBuffer),
	WRAP(glPrimitiveRestartIndex),
	WRAP(glCopyBufferSubData),
	{"glGetUniformIndices", 3, &crocglGetUniformIndices},
	WRAP(glGetActiveUniformsiv),
	{"glGetActiveUniformName", 2, &crocglGetActiveUniformName},
	WRAP(glGetUniformBlockIndex),
	WRAP(glGetActiveUniformBlockiv),
	{"glGetActiveUniformBlockName", 2, &crocglGetActiveUniformBlockName},
	WRAP(glUniformBlockBinding),
	{nullptr, 0, nullptr}
};

void loadGL3_1(CrocThread* t)
{
	if(!GLAD_GL_VERSION_3_1) return;
	croc_ex_registerGlobals(t, _gl3_1);
}

const CrocRegisterFunc _gl3_2[] =
{
	WRAP(glDrawElementsBaseVertex),
	WRAP(glDrawRangeElementsBaseVertex),
	WRAP(glDrawElementsInstancedBaseVertex),
	// WRAP(glMultiDrawElementsBaseVertex),
	WRAP(glProvokingVertex),
	// WRAP(glFenceSync),
	WRAP(glIsSync),
	WRAP(glDeleteSync),
	WRAP(glClientWaitSync),
	WRAP(glWaitSync),
	WRAP(glGetInteger64v),
	WRAP(glGetSynciv),
	WRAP(glGetInteger64i_v),
	WRAP(glGetBufferParameteri64v),
	WRAP(glFramebufferTexture),
	WRAP(glTexImage2DMultisample),
	WRAP(glTexImage3DMultisample),
	WRAP(glGetMultisamplefv),
	WRAP(glSampleMaski),
	{nullptr, 0, nullptr}
};

void loadGL3_2(CrocThread* t)
{
	if(!GLAD_GL_VERSION_3_2) return;
	croc_ex_registerGlobals(t, _gl3_2);
}

const CrocRegisterFunc _gl3_3[] =
{
	WRAP(glBindFragDataLocationIndexed),
	WRAP(glGetFragDataIndex),
	WRAPGEN(glGenSamplers),
	WRAPDELETE(glDeleteSamplers),
	WRAP(glIsSampler),
	WRAP(glBindSampler),
	WRAP(glSamplerParameteri),
	WRAP(glSamplerParameteriv),
	WRAP(glSamplerParameterf),
	WRAP(glSamplerParameterfv),
	WRAP(glSamplerParameterIiv),
	WRAP(glSamplerParameterIuiv),
	WRAP(glGetSamplerParameteriv),
	WRAP(glGetSamplerParameterIiv),
	WRAP(glGetSamplerParameterfv),
	WRAP(glGetSamplerParameterIuiv),
	WRAP(glQueryCounter),
	WRAP(glGetQueryObjecti64v),
	WRAP(glGetQueryObjectui64v),
	WRAP(glVertexAttribDivisor),
	WRAP(glVertexAttribP1ui),
	WRAP(glVertexAttribP1uiv),
	WRAP(glVertexAttribP2ui),
	WRAP(glVertexAttribP2uiv),
	WRAP(glVertexAttribP3ui),
	WRAP(glVertexAttribP3uiv),
	WRAP(glVertexAttribP4ui),
	WRAP(glVertexAttribP4uiv),
	WRAP(glVertexP2ui),
	WRAP(glVertexP2uiv),
	WRAP(glVertexP3ui),
	WRAP(glVertexP3uiv),
	WRAP(glVertexP4ui),
	WRAP(glVertexP4uiv),
	WRAP(glTexCoordP1ui),
	WRAP(glTexCoordP1uiv),
	WRAP(glTexCoordP2ui),
	WRAP(glTexCoordP2uiv),
	WRAP(glTexCoordP3ui),
	WRAP(glTexCoordP3uiv),
	WRAP(glTexCoordP4ui),
	WRAP(glTexCoordP4uiv),
	WRAP(glMultiTexCoordP1ui),
	WRAP(glMultiTexCoordP1uiv),
	WRAP(glMultiTexCoordP2ui),
	WRAP(glMultiTexCoordP2uiv),
	WRAP(glMultiTexCoordP3ui),
	WRAP(glMultiTexCoordP3uiv),
	WRAP(glMultiTexCoordP4ui),
	WRAP(glMultiTexCoordP4uiv),
	WRAP(glNormalP3ui),
	WRAP(glNormalP3uiv),
	WRAP(glColorP3ui),
	WRAP(glColorP3uiv),
	WRAP(glColorP4ui),
	WRAP(glColorP4uiv),
	WRAP(glSecondaryColorP3ui),
	WRAP(glSecondaryColorP3uiv),
	{nullptr, 0, nullptr}
};

void loadGL3_3(CrocThread* t)
{
	if(!GLAD_GL_VERSION_3_3) return;
	croc_ex_registerGlobals(t, _gl3_3);
}

word_t crocglGetActiveSubroutineUniformName(CrocThread* t)
{
	auto program = cast(GLuint)croc_ex_checkIntParam(t, 1);
	auto shaderType = cast(GLenum)croc_ex_checkIntParam(t, 2);
	auto index = cast(GLuint)croc_ex_checkIntParam(t, 3);

	GLint length = -1;
	glGetProgramStageiv(program, shaderType, GL_ACTIVE_SUBROUTINE_UNIFORM_MAX_LENGTH, &length);

	if(length == -1)
		return 0;

	uword_t size = length * sizeof(GLchar);
	auto buf = cast(GLchar*)croc_mem_alloc(t, size);
	GLsizei realLength = 0;
	glGetActiveSubroutineUniformName(program, shaderType, index, length, &realLength, buf);
	auto ok = croc_tryPushStringn(t, buf, realLength);
	croc_mem_free(t, cast(void**)&buf, &size);

	if(!ok)
		croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

	return 1;
}

word_t crocglGetActiveSubroutineName(CrocThread* t)
{
	auto program = cast(GLuint)croc_ex_checkIntParam(t, 1);
	auto shaderType = cast(GLenum)croc_ex_checkIntParam(t, 2);
	auto index = cast(GLuint)croc_ex_checkIntParam(t, 3);

	GLint length = -1;
	glGetProgramStageiv(program, shaderType, GL_ACTIVE_SUBROUTINE_MAX_LENGTH, &length);

	if(length == -1)
		return 0;

	uword_t size = length * sizeof(GLchar);
	auto buf = cast(GLchar*)croc_mem_alloc(t, size);
	GLsizei realLength = 0;
	glGetActiveSubroutineName(program, shaderType, index, length, &realLength, buf);
	auto ok = croc_tryPushStringn(t, buf, realLength);
	croc_mem_free(t, cast(void**)&buf, &size);

	if(!ok)
		croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

	return 1;
}

const CrocRegisterFunc _gl4_0[] =
{
	WRAP(glMinSampleShading),
	WRAP(glBlendEquationi),
	WRAP(glBlendEquationSeparatei),
	WRAP(glBlendFunci),
	WRAP(glBlendFuncSeparatei),
	WRAP(glDrawArraysIndirect),
	WRAP(glDrawElementsIndirect),
	WRAP(glUniform1d),
	WRAP(glUniform2d),
	WRAP(glUniform3d),
	WRAP(glUniform4d),
	WRAP(glUniform1dv),
	WRAP(glUniform2dv),
	WRAP(glUniform3dv),
	WRAP(glUniform4dv),
	WRAP(glUniformMatrix2dv),
	WRAP(glUniformMatrix3dv),
	WRAP(glUniformMatrix4dv),
	WRAP(glUniformMatrix2x3dv),
	WRAP(glUniformMatrix2x4dv),
	WRAP(glUniformMatrix3x2dv),
	WRAP(glUniformMatrix3x4dv),
	WRAP(glUniformMatrix4x2dv),
	WRAP(glUniformMatrix4x3dv),
	WRAP(glGetUniformdv),
	WRAP(glGetSubroutineUniformLocation),
	WRAP(glGetSubroutineIndex),
	WRAP(glGetActiveSubroutineUniformiv),
	{"glGetActiveSubroutineUniformName", 3, &crocglGetActiveSubroutineUniformName},
	{"glGetActiveSubroutineName", 3, &crocglGetActiveSubroutineName},
	WRAP(glUniformSubroutinesuiv),
	WRAP(glGetUniformSubroutineuiv),
	WRAP(glGetProgramStageiv),
	WRAP(glPatchParameteri),
	WRAP(glPatchParameterfv),
	WRAP(glBindTransformFeedback),
	WRAPDELETE(glDeleteTransformFeedbacks),
	WRAPGEN(glGenTransformFeedbacks),
	WRAP(glIsTransformFeedback),
	WRAP(glPauseTransformFeedback),
	WRAP(glResumeTransformFeedback),
	WRAP(glDrawTransformFeedback),
	WRAP(glDrawTransformFeedbackStream),
	WRAP(glBeginQueryIndexed),
	WRAP(glEndQueryIndexed),
	WRAP(glGetQueryIndexediv),
	{nullptr, 0, nullptr}
};

void loadGL4_0(CrocThread* t)
{
	if(!GLAD_GL_VERSION_4_0) return;
	croc_ex_registerGlobals(t, _gl4_0);
}

const char* crocglCreateShaderProgramv_docs
= Docstr(DFunc("glCreateShaderProgramv") DParam("type", "int") DParam("source", "string")
R"(Like \link{glShaderSource}, takes a single string instead of an array of strings.)");

word_t crocglCreateShaderProgramv(CrocThread* t)
{
	auto type = cast(GLenum)croc_ex_checkIntParam(t, 1);
	auto src = cast(const GLchar*)croc_ex_checkStringParam(t, 2);
	croc_pushInt(t, cast(crocint)glCreateShaderProgramv(type, 1, &src));
	return 1;
}

word_t crocglGetProgramPipelineInfoLog(CrocThread* t)
{
	auto pipeline = cast(GLuint)croc_ex_checkIntParam(t, 1);
	GLint length = -1;
	glGetProgramPipelineiv(pipeline, GL_INFO_LOG_LENGTH, &length);

	if(length == -1)
		return 0;

	uword_t size = length * sizeof(GLchar);
	auto buf = cast(GLchar*)croc_mem_alloc(t, size);
	GLsizei realLength = 0;
	glGetProgramPipelineInfoLog(pipeline, length, &realLength, buf);
	auto ok = croc_tryPushStringn(t, buf, realLength);
	croc_mem_free(t, cast(void**)&buf, &size);

	if(!ok)
		croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

	return 1;
}

const CrocRegisterFunc _gl4_1[] =
{
	WRAP(glReleaseShaderCompiler),
	WRAP(glShaderBinary),
	WRAP(glGetShaderPrecisionFormat),
	WRAP(glDepthRangef),
	WRAP(glClearDepthf),
	WRAP(glGetProgramBinary),
	WRAP(glProgramBinary),
	WRAP(glProgramParameteri),
	WRAP(glUseProgramStages),
	WRAP(glActiveShaderProgram),
	{"glCreateShaderProgramv", 2, &crocglCreateShaderProgramv},
	WRAP(glBindProgramPipeline),
	WRAPDELETE(glDeleteProgramPipelines),
	WRAPGEN(glGenProgramPipelines),
	WRAP(glIsProgramPipeline),
	WRAP(glGetProgramPipelineiv),
	WRAP(glProgramUniform1i),
	WRAP(glProgramUniform1iv),
	WRAP(glProgramUniform1f),
	WRAP(glProgramUniform1fv),
	WRAP(glProgramUniform1d),
	WRAP(glProgramUniform1dv),
	WRAP(glProgramUniform1ui),
	WRAP(glProgramUniform1uiv),
	WRAP(glProgramUniform2i),
	WRAP(glProgramUniform2iv),
	WRAP(glProgramUniform2f),
	WRAP(glProgramUniform2fv),
	WRAP(glProgramUniform2d),
	WRAP(glProgramUniform2dv),
	WRAP(glProgramUniform2ui),
	WRAP(glProgramUniform2uiv),
	WRAP(glProgramUniform3i),
	WRAP(glProgramUniform3iv),
	WRAP(glProgramUniform3f),
	WRAP(glProgramUniform3fv),
	WRAP(glProgramUniform3d),
	WRAP(glProgramUniform3dv),
	WRAP(glProgramUniform3ui),
	WRAP(glProgramUniform3uiv),
	WRAP(glProgramUniform4i),
	WRAP(glProgramUniform4iv),
	WRAP(glProgramUniform4f),
	WRAP(glProgramUniform4fv),
	WRAP(glProgramUniform4d),
	WRAP(glProgramUniform4dv),
	WRAP(glProgramUniform4ui),
	WRAP(glProgramUniform4uiv),
	WRAP(glProgramUniformMatrix2fv),
	WRAP(glProgramUniformMatrix3fv),
	WRAP(glProgramUniformMatrix4fv),
	WRAP(glProgramUniformMatrix2dv),
	WRAP(glProgramUniformMatrix3dv),
	WRAP(glProgramUniformMatrix4dv),
	WRAP(glProgramUniformMatrix2x3fv),
	WRAP(glProgramUniformMatrix3x2fv),
	WRAP(glProgramUniformMatrix2x4fv),
	WRAP(glProgramUniformMatrix4x2fv),
	WRAP(glProgramUniformMatrix3x4fv),
	WRAP(glProgramUniformMatrix4x3fv),
	WRAP(glProgramUniformMatrix2x3dv),
	WRAP(glProgramUniformMatrix3x2dv),
	WRAP(glProgramUniformMatrix2x4dv),
	WRAP(glProgramUniformMatrix4x2dv),
	WRAP(glProgramUniformMatrix3x4dv),
	WRAP(glProgramUniformMatrix4x3dv),
	WRAP(glValidateProgramPipeline),
	{"glGetProgramPipelineInfoLog", 1, &crocglGetProgramPipelineInfoLog},
	WRAP(glVertexAttribL1d),
	WRAP(glVertexAttribL2d),
	WRAP(glVertexAttribL3d),
	WRAP(glVertexAttribL4d),
	WRAP(glVertexAttribL1dv),
	WRAP(glVertexAttribL2dv),
	WRAP(glVertexAttribL3dv),
	WRAP(glVertexAttribL4dv),
	WRAP(glVertexAttribLPointer),
	WRAP(glGetVertexAttribLdv),
	WRAP(glViewportArrayv),
	WRAP(glViewportIndexedf),
	WRAP(glViewportIndexedfv),
	WRAP(glScissorArrayv),
	WRAP(glScissorIndexed),
	WRAP(glScissorIndexedv),
	WRAP(glDepthRangeArrayv),
	WRAP(glDepthRangeIndexed),
	WRAP(glGetFloati_v),
	WRAP(glGetDoublei_v),
	{nullptr, 0, nullptr}
};

void loadGL4_1(CrocThread* t)
{
	if(!GLAD_GL_VERSION_4_1) return;
	croc_ex_registerGlobals(t, _gl4_1);
}

const CrocRegisterFunc _gl4_2[] =
{
	WRAP(glDrawArraysInstancedBaseInstance),
	WRAP(glDrawElementsInstancedBaseInstance),
	WRAP(glDrawElementsInstancedBaseVertexBaseInstance),
	WRAP(glGetInternalformativ),
	WRAP(glGetActiveAtomicCounterBufferiv),
	WRAP(glBindImageTexture),
	WRAP(glMemoryBarrier),
	WRAP(glTexStorage1D),
	WRAP(glTexStorage2D),
	WRAP(glTexStorage3D),
	WRAP(glDrawTransformFeedbackInstanced),
	WRAP(glDrawTransformFeedbackStreamInstanced),
	{nullptr, 0, nullptr}
};

void loadGL4_2(CrocThread* t)
{
	if(!GLAD_GL_VERSION_4_2) return;
	croc_ex_registerGlobals(t, _gl4_2);
}

word_t crocglGetProgramResourceName(CrocThread* t)
{
	auto program = cast(GLuint)croc_ex_checkIntParam(t, 1);
	auto programInterface = cast(GLenum)croc_ex_checkIntParam(t, 2);
	auto index = cast(GLuint)croc_ex_checkIntParam(t, 3);

	GLint length = -1;
	glGetProgramInterfaceiv(program, programInterface, GL_MAX_NAME_LENGTH, &length);

	if(length == -1)
		return 0;

	uword_t size = length * sizeof(GLchar);
	auto buf = cast(GLchar*)croc_mem_alloc(t, size);
	GLsizei realLength = 0;
	glGetProgramResourceName(program, programInterface, index, length, &realLength, buf);
	auto ok = croc_tryPushStringn(t, buf, realLength);
	croc_mem_free(t, cast(void**)&buf, &size);

	if(!ok)
		croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

	return 1;
}

word_t crocglGetObjectLabel(CrocThread* t)
{
	auto identifier = cast(GLenum)croc_ex_checkIntParam(t, 1);
	auto name = cast(GLuint)croc_ex_checkIntParam(t, 2);

	GLint length = -1;
	glGetIntegerv(GL_MAX_LABEL_LENGTH, &length);

	if(length == -1)
		return 0;

	uword_t size = length * sizeof(GLchar);
	auto buf = cast(GLchar*)croc_mem_alloc(t, size);
	GLsizei realLength = 0;
	glGetObjectLabel(identifier, name, length, &realLength, buf);
	auto ok = croc_tryPushStringn(t, buf, realLength);
	croc_mem_free(t, cast(void**)&buf, &size);

	if(!ok)
		croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

	return 1;
}

word_t crocglGetObjectPtrLabel(CrocThread* t)
{
	auto sync = getGLParam<void*>(t, 1);

	GLint length = -1;
	glGetIntegerv(GL_MAX_LABEL_LENGTH, &length);

	if(length == -1)
		return 0;

	uword_t size = length * sizeof(GLchar);
	auto buf = cast(GLchar*)croc_mem_alloc(t, size);
	GLsizei realLength = 0;
	glGetObjectPtrLabel(sync, length, &realLength, buf);
	auto ok = croc_tryPushStringn(t, buf, realLength);
	croc_mem_free(t, cast(void**)&buf, &size);

	if(!ok)
		croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

	return 1;
}

void APIENTRY debugMessageCallback(GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei length,
	const GLchar* message, const void* vm)
{
	auto t = croc_vm_getCurrentThread(cast(CrocThread*)vm);

	auto f = croc_ex_pushRegistryVar(t, "gl.DebugCallback");
	croc_pushNull(t);
	croc_pushInt(t, source);
	croc_pushInt(t, type);
	croc_pushInt(t, id);
	croc_pushInt(t, severity);
	croc_pushStringn(t, message, length);
	croc_tryCall(t, f, 0);
}

const char* crocglDebugMessageCallback_docs
= Docstr(DFunc("glDebugMessageCallback") DParam("callback", "null|function")
R"(Sets or unsets the OpenGL debug message callback. Passing \tt{null} for \tt{callback} unsets it.

The callback function will be called with five parameters: the source (int), type (int), ID (int), severity (int), and
the message (string).)");

word_t crocglDebugMessageCallback(CrocThread* t)
{
	if(croc_ex_optParam(t, 1, CrocType_Function))
	{
		croc_vm_pushRegistry(t);
		croc_dup(t, 1);
		croc_fielda(t, -2, "gl.DebugCallback");
		glDebugMessageCallback(&debugMessageCallback, croc_vm_getMainThread(t));
	}
	else
	{
		croc_vm_pushRegistry(t);
		croc_pushNull(t);
		croc_fielda(t, -2, "gl.DebugCallback");
		glDebugMessageCallback(nullptr, nullptr);
	}

	return 0;
}

const CrocRegisterFunc _gl4_3[] =
{
	WRAP(glClearBufferData),
	WRAP(glClearBufferSubData),
	WRAP(glDispatchCompute),
	WRAP(glDispatchComputeIndirect),
	WRAP(glCopyImageSubData),
	WRAP(glFramebufferParameteri),
	WRAP(glGetFramebufferParameteriv),
	WRAP(glGetInternalformati64v),
	WRAP(glInvalidateTexSubImage),
	WRAP(glInvalidateTexImage),
	WRAP(glInvalidateBufferSubData),
	WRAP(glInvalidateBufferData),
	WRAP(glInvalidateFramebuffer),
	WRAP(glInvalidateSubFramebuffer),
	WRAP(glMultiDrawArraysIndirect),
	WRAP(glMultiDrawElementsIndirect),
	WRAP(glGetProgramInterfaceiv),
	WRAP(glGetProgramResourceIndex),
	{"glGetProgramResourceName", 3, &crocglGetProgramResourceName},
	WRAP(glGetProgramResourceiv),
	WRAP(glGetProgramResourceLocation),
	WRAP(glGetProgramResourceLocationIndex),
	WRAP(glShaderStorageBlockBinding),
	WRAP(glTexBufferRange),
	WRAP(glTexStorage2DMultisample),
	WRAP(glTexStorage3DMultisample),
	WRAP(glTextureView),
	WRAP(glBindVertexBuffer),
	WRAP(glVertexAttribFormat),
	WRAP(glVertexAttribIFormat),
	WRAP(glVertexAttribLFormat),
	WRAP(glVertexAttribBinding),
	WRAP(glVertexBindingDivisor),
	WRAP(glDebugMessageControl),
	WRAP(glDebugMessageInsert),
	{"glDebugMessageCallback", 1, &crocglDebugMessageCallback},
	WRAP(glGetDebugMessageLog),
	WRAP(glPushDebugGroup),
	WRAP(glPopDebugGroup),
	WRAP(glObjectLabel),
	{"glGetObjectLabel", 2, &crocglGetObjectLabel},
	{"glObjectPtrLabel", 1, &crocglGetObjectPtrLabel},
	WRAP(glGetObjectPtrLabel),
	// WRAP(glGetPointerv),
	{nullptr, 0, nullptr}
};

void loadGL4_3(CrocThread* t)
{
	if(!GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _gl4_3);
}

const CrocRegisterFunc _gl4_4[] =
{
	WRAP(glBufferStorage),
	WRAP(glClearTexImage),
	WRAP(glClearTexSubImage),
	WRAP(glBindBuffersBase),
	WRAP(glBindBuffersRange),
	WRAP(glBindTextures),
	WRAP(glBindSamplers),
	WRAP(glBindImageTextures),
	WRAP(glBindVertexBuffers),
	{nullptr, 0, nullptr}
};

void loadGL4_4(CrocThread* t)
{
	if(!GLAD_GL_VERSION_4_4) return;
	croc_ex_registerGlobals(t, _gl4_4);
}

const char* crocglMapNamedBuffer_docs
= Docstr(DFunc("glMapNamedBuffer") DParam("name", "int") DParam("access", "int") DParamD("mb", "memblock", "null")
R"(Works just like \link{glMapBuffer}.)");

word_t crocglMapNamedBuffer(CrocThread* t)
{
	auto name = cast(GLuint)croc_ex_checkIntParam(t, 1);
	auto access = cast(GLenum)croc_ex_checkIntParam(t, 2);
	auto haveMemblock = croc_ex_optParam(t, 3, CrocType_Memblock);

	GLint size;
	glGetNamedBufferParameteriv(name, GL_BUFFER_SIZE, &size);

	if(auto ptr = glMapNamedBuffer(name, access))
	{
		if(haveMemblock)
		{
			croc_memblock_reviewNativeArray(t, 3, ptr, size);
			croc_dup(t, 3);
		}
		else
			croc_memblock_viewNativeArray(t, ptr, size);
	}
	else
		croc_pushNull(t);

	return 1;
}

const char* crocglMapNamedBufferRange_docs
= Docstr(DFunc("glMapNamedBufferRange") DParam("name", "int") DParam("offset", "int") DParam("length", "int") DParam(
	"access", "int") DParamD("mb", "memblock", "null")
R"(Works just like \link{glMapBufferRange}.)");

word_t crocglMapNamedBufferRange(CrocThread* t)
{
	auto name = cast(GLuint)croc_ex_checkIntParam(t, 1);
	auto offset = cast(GLintptr)croc_ex_checkIntParam(t, 2);
	auto length = cast(GLsizeiptr)croc_ex_checkIntParam(t, 3);
	auto access = cast(GLenum)croc_ex_checkIntParam(t, 4);
	auto haveMemblock = croc_ex_optParam(t, 5, CrocType_Memblock);

	if(auto ptr = glMapNamedBufferRange(name, offset, length, access))
	{
		if(haveMemblock)
		{
			croc_memblock_reviewNativeArray(t, 5, ptr, length);
			croc_dup(t, 5);
		}
		else
			croc_memblock_viewNativeArray(t, ptr, length);
	}
	else
		croc_pushNull(t);

	return 1;
}

const CrocRegisterFunc _gl4_5[] =
{
	WRAP(glClipControl),
	WRAP(glCreateTransformFeedbacks),
	WRAP(glTransformFeedbackBufferBase),
	WRAP(glTransformFeedbackBufferRange),
	WRAP(glGetTransformFeedbackiv),
	WRAP(glGetTransformFeedbacki_v),
	WRAP(glGetTransformFeedbacki64_v),
	WRAP(glCreateBuffers),
	WRAP(glNamedBufferStorage),
	WRAP(glNamedBufferData),
	WRAP(glNamedBufferSubData),
	WRAP(glCopyNamedBufferSubData),
	WRAP(glClearNamedBufferData),
	WRAP(glClearNamedBufferSubData),
	{"glMapNamedBuffer", 3, &crocglMapNamedBuffer},
	{"glMapNamedBufferRange", 5, &crocglMapNamedBufferRange},
	WRAP(glUnmapNamedBuffer),
	WRAP(glFlushMappedNamedBufferRange),
	WRAP(glGetNamedBufferParameteriv),
	WRAP(glGetNamedBufferParameteri64v),
	// WRAP(glGetNamedBufferPointerv),
	WRAP(glGetNamedBufferSubData),
	WRAP(glCreateFramebuffers),
	WRAP(glNamedFramebufferRenderbuffer),
	WRAP(glNamedFramebufferParameteri),
	WRAP(glNamedFramebufferTexture),
	WRAP(glNamedFramebufferTextureLayer),
	WRAP(glNamedFramebufferDrawBuffer),
	WRAP(glNamedFramebufferDrawBuffers),
	WRAP(glNamedFramebufferReadBuffer),
	WRAP(glInvalidateNamedFramebufferData),
	WRAP(glInvalidateNamedFramebufferSubData),
	WRAP(glClearNamedFramebufferiv),
	WRAP(glClearNamedFramebufferuiv),
	WRAP(glClearNamedFramebufferfv),
	WRAP(glClearNamedFramebufferfi),
	WRAP(glBlitNamedFramebuffer),
	WRAP(glCheckNamedFramebufferStatus),
	WRAP(glGetNamedFramebufferParameteriv),
	WRAP(glGetNamedFramebufferAttachmentParameteriv),
	WRAP(glCreateRenderbuffers),
	WRAP(glNamedRenderbufferStorage),
	WRAP(glNamedRenderbufferStorageMultisample),
	WRAP(glGetNamedRenderbufferParameteriv),
	WRAP(glCreateTextures),
	WRAP(glTextureBuffer),
	WRAP(glTextureBufferRange),
	WRAP(glTextureStorage1D),
	WRAP(glTextureStorage2D),
	WRAP(glTextureStorage3D),
	WRAP(glTextureStorage2DMultisample),
	WRAP(glTextureStorage3DMultisample),
	WRAP(glTextureSubImage1D),
	WRAP(glTextureSubImage2D),
	WRAP(glTextureSubImage3D),
	WRAP(glCompressedTextureSubImage1D),
	WRAP(glCompressedTextureSubImage2D),
	WRAP(glCompressedTextureSubImage3D),
	WRAP(glCopyTextureSubImage1D),
	WRAP(glCopyTextureSubImage2D),
	WRAP(glCopyTextureSubImage3D),
	WRAP(glTextureParameterf),
	WRAP(glTextureParameterfv),
	WRAP(glTextureParameteri),
	WRAP(glTextureParameterIiv),
	WRAP(glTextureParameterIuiv),
	WRAP(glTextureParameteriv),
	WRAP(glGenerateTextureMipmap),
	WRAP(glBindTextureUnit),
	WRAP(glGetTextureImage),
	WRAP(glGetCompressedTextureImage),
	WRAP(glGetTextureLevelParameterfv),
	WRAP(glGetTextureLevelParameteriv),
	WRAP(glGetTextureParameterfv),
	WRAP(glGetTextureParameterIiv),
	WRAP(glGetTextureParameterIuiv),
	WRAP(glGetTextureParameteriv),
	WRAP(glCreateVertexArrays),
	WRAP(glDisableVertexArrayAttrib),
	WRAP(glEnableVertexArrayAttrib),
	WRAP(glVertexArrayElementBuffer),
	WRAP(glVertexArrayVertexBuffer),
	WRAP(glVertexArrayVertexBuffers),
	WRAP(glVertexArrayAttribBinding),
	WRAP(glVertexArrayAttribFormat),
	WRAP(glVertexArrayAttribIFormat),
	WRAP(glVertexArrayAttribLFormat),
	WRAP(glVertexArrayBindingDivisor),
	WRAP(glGetVertexArrayiv),
	WRAP(glGetVertexArrayIndexediv),
	WRAP(glGetVertexArrayIndexed64iv),
	WRAP(glCreateSamplers),
	WRAP(glCreateProgramPipelines),
	WRAP(glCreateQueries),
	WRAP(glMemoryBarrierByRegion),
	WRAP(glGetTextureSubImage),
	WRAP(glGetCompressedTextureSubImage),
	WRAP(glGetGraphicsResetStatus),
	WRAP(glGetnCompressedTexImage),
	WRAP(glGetnTexImage),
	WRAP(glGetnUniformdv),
	WRAP(glGetnUniformfv),
	WRAP(glGetnUniformiv),
	WRAP(glGetnUniformuiv),
	WRAP(glReadnPixels),
	WRAP(glGetnMapdv),
	WRAP(glGetnMapfv),
	WRAP(glGetnMapiv),
	WRAP(glGetnPixelMapfv),
	WRAP(glGetnPixelMapuiv),
	WRAP(glGetnPixelMapusv),
	WRAP(glGetnPolygonStipple),
	WRAP(glGetnColorTable),
	WRAP(glGetnConvolutionFilter),
	WRAP(glGetnSeparableFilter),
	WRAP(glGetnHistogram),
	WRAP(glGetnMinmax),
	WRAP(glTextureBarrier),
	{nullptr, 0, nullptr}
};

void loadGL4_5(CrocThread* t)
{
	if(!GLAD_GL_VERSION_4_5) return;
	croc_ex_registerGlobals(t, _gl4_5);
}

const CrocRegisterFunc _AMD_gpu_shader_int64[] =
{
	WRAP(glUniform1i64NV),
	WRAP(glUniform2i64NV),
	WRAP(glUniform3i64NV),
	WRAP(glUniform4i64NV),
	WRAP(glUniform1i64vNV),
	WRAP(glUniform2i64vNV),
	WRAP(glUniform3i64vNV),
	WRAP(glUniform4i64vNV),
	WRAP(glUniform1ui64NV),
	WRAP(glUniform2ui64NV),
	WRAP(glUniform3ui64NV),
	WRAP(glUniform4ui64NV),
	WRAP(glUniform1ui64vNV),
	WRAP(glUniform2ui64vNV),
	WRAP(glUniform3ui64vNV),
	WRAP(glUniform4ui64vNV),
	WRAP(glGetUniformi64vNV),
	WRAP(glGetUniformui64vNV),
	WRAP(glProgramUniform1i64NV),
	WRAP(glProgramUniform2i64NV),
	WRAP(glProgramUniform3i64NV),
	WRAP(glProgramUniform4i64NV),
	WRAP(glProgramUniform1i64vNV),
	WRAP(glProgramUniform2i64vNV),
	WRAP(glProgramUniform3i64vNV),
	WRAP(glProgramUniform4i64vNV),
	WRAP(glProgramUniform1ui64NV),
	WRAP(glProgramUniform2ui64NV),
	WRAP(glProgramUniform3ui64NV),
	WRAP(glProgramUniform4ui64NV),
	WRAP(glProgramUniform1ui64vNV),
	WRAP(glProgramUniform2ui64vNV),
	WRAP(glProgramUniform3ui64vNV),
	WRAP(glProgramUniform4ui64vNV),
	{nullptr, 0, nullptr}
};

void load_AMD_gpu_shader_int64(CrocThread* t)
{
	if(!GLAD_GL_AMD_gpu_shader_int64) return;
	croc_ex_registerGlobals(t, _AMD_gpu_shader_int64);
}

const CrocRegisterFunc _AMD_interleaved_elements[] =
{
	WRAP(glVertexAttribParameteriAMD),
	{nullptr, 0, nullptr}
};

void load_AMD_interleaved_elements(CrocThread* t)
{
	if(!GLAD_GL_AMD_interleaved_elements) return;
	croc_ex_registerGlobals(t, _AMD_interleaved_elements);
}

const CrocRegisterFunc _AMD_occlusion_query_event[] =
{
	WRAP(glQueryObjectParameteruiAMD),
	{nullptr, 0, nullptr}
};

void load_AMD_occlusion_query_event(CrocThread* t)
{
	if(!GLAD_GL_AMD_occlusion_query_event) return;
	croc_ex_registerGlobals(t, _AMD_occlusion_query_event);
}

// stupid shim because glDeletePerfMonitorsAMD doesn't use a const GLuint* like EVERY OTHER glDelete* function
void APIENTRY glDeletePerfMonitorsAMD_shim(GLsizei num, const GLuint* names)
{
	glDeletePerfMonitorsAMD(num, cast(GLuint*)names);
}

void (APIENTRYP glDeletePerfMonitorsAMD_ptr)(GLsizei, const GLuint*) = &glDeletePerfMonitorsAMD_shim;

const CrocRegisterFunc _AMD_performance_monitor[] =
{
	WRAP(glGetPerfMonitorGroupsAMD),
	WRAP(glGetPerfMonitorCountersAMD),
	WRAP(glGetPerfMonitorGroupStringAMD),
	WRAP(glGetPerfMonitorCounterStringAMD),
	WRAP(glGetPerfMonitorCounterInfoAMD),
	WRAPGEN(glGenPerfMonitorsAMD),
	{"glDeletePerfMonitorsAMD", -1, &wrapDelete<&glDeletePerfMonitorsAMD_ptr>::func},
	WRAP(glSelectPerfMonitorCountersAMD),
	WRAP(glBeginPerfMonitorAMD),
	WRAP(glEndPerfMonitorAMD),
	WRAP(glGetPerfMonitorCounterDataAMD),
	{nullptr, 0, nullptr}
};

void load_AMD_performance_monitor(CrocThread* t)
{
	if(!GLAD_GL_AMD_performance_monitor) return;
	croc_ex_registerGlobals(t, _AMD_performance_monitor);
}

const CrocRegisterFunc _AMD_sample_positions[] =
{
	WRAP(glSetMultisamplefvAMD),
	{nullptr, 0, nullptr}
};

void load_AMD_sample_positions(CrocThread* t)
{
	if(!GLAD_GL_AMD_sample_positions) return;
	croc_ex_registerGlobals(t, _AMD_sample_positions);
}

const CrocRegisterFunc _AMD_sparse_texture[] =
{
	WRAP(glTexStorageSparseAMD),
	WRAP(glTextureStorageSparseAMD),
	{nullptr, 0, nullptr}
};

void load_AMD_sparse_texture(CrocThread* t)
{
	if(!GLAD_GL_AMD_sparse_texture) return;
	croc_ex_registerGlobals(t, _AMD_sparse_texture);
}

const CrocRegisterFunc _AMD_stencil_operation_extended[] =
{
	WRAP(glStencilOpValueAMD),
	{nullptr, 0, nullptr}
};

void load_AMD_stencil_operation_extended(CrocThread* t)
{
	if(!GLAD_GL_AMD_stencil_operation_extended) return;
	croc_ex_registerGlobals(t, _AMD_stencil_operation_extended);
}

const CrocRegisterFunc _ARB_base_instance[] =
{
	WRAP(glDrawArraysInstancedBaseInstance),
	WRAP(glDrawElementsInstancedBaseInstance),
	WRAP(glDrawElementsInstancedBaseVertexBaseInstance),
	{nullptr, 0, nullptr}
};

void load_ARB_base_instance(CrocThread* t)
{
	if(!GLAD_GL_ARB_base_instance || GLAD_GL_VERSION_4_2) return;
	croc_ex_registerGlobals(t, _ARB_base_instance);
}

const CrocRegisterFunc _ARB_bindless_texture[] =
{
	WRAP(glGetTextureHandleARB),
	WRAP(glGetTextureSamplerHandleARB),
	WRAP(glMakeTextureHandleResidentARB),
	WRAP(glMakeTextureHandleNonResidentARB),
	WRAP(glGetImageHandleARB),
	WRAP(glMakeImageHandleResidentARB),
	WRAP(glMakeImageHandleNonResidentARB),
	WRAP(glUniformHandleui64ARB),
	WRAP(glUniformHandleui64vARB),
	WRAP(glProgramUniformHandleui64ARB),
	WRAP(glProgramUniformHandleui64vARB),
	WRAP(glIsTextureHandleResidentARB),
	WRAP(glIsImageHandleResidentARB),
	WRAP(glVertexAttribL1ui64ARB),
	WRAP(glVertexAttribL1ui64vARB),
	WRAP(glGetVertexAttribLui64vARB),
	{nullptr, 0, nullptr}
};

void load_ARB_bindless_texture(CrocThread* t)
{
	if(!GLAD_GL_ARB_bindless_texture) return;
	croc_ex_registerGlobals(t, _ARB_bindless_texture);
}

const CrocRegisterFunc _ARB_blend_func_extended[] =
{
	WRAP(glBindFragDataLocationIndexed),
	WRAP(glGetFragDataIndex),
	{nullptr, 0, nullptr}
};

void load_ARB_blend_func_extended(CrocThread* t)
{
	if(!GLAD_GL_ARB_blend_func_extended || GLAD_GL_VERSION_3_3) return;
	croc_ex_registerGlobals(t, _ARB_blend_func_extended);
}

const CrocRegisterFunc _ARB_buffer_storage[] =
{
	WRAP(glBufferStorage),
	{nullptr, 0, nullptr}
};

void load_ARB_buffer_storage(CrocThread* t)
{
	if(!GLAD_GL_ARB_buffer_storage || GLAD_GL_VERSION_4_4) return;
	croc_ex_registerGlobals(t, _ARB_buffer_storage);
}

const CrocRegisterFunc _ARB_cl_event[] =
{
	// WRAP(glCreateSyncFromCLeventARB),
	{nullptr, 0, nullptr}
};

void load_ARB_cl_event(CrocThread* t)
{
	if(!GLAD_GL_ARB_cl_event) return;
	croc_ex_registerGlobals(t, _ARB_cl_event);
}

const CrocRegisterFunc _ARB_clear_buffer_object[] =
{
	WRAP(glClearBufferData),
	WRAP(glClearBufferSubData),
	{nullptr, 0, nullptr}
};

void load_ARB_clear_buffer_object(CrocThread* t)
{
	if(!GLAD_GL_ARB_clear_buffer_object || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _ARB_clear_buffer_object);
}

const CrocRegisterFunc _ARB_clear_texture[] =
{
	WRAP(glClearTexImage),
	WRAP(glClearTexSubImage),
	{nullptr, 0, nullptr}
};

void load_ARB_clear_texture(CrocThread* t)
{
	if(!GLAD_GL_ARB_clear_texture || GLAD_GL_VERSION_4_4) return;
	croc_ex_registerGlobals(t, _ARB_clear_texture);
}

const CrocRegisterFunc _ARB_compute_shader[] =
{
	WRAP(glDispatchCompute),
	WRAP(glDispatchComputeIndirect),
	{nullptr, 0, nullptr}
};

void load_ARB_compute_shader(CrocThread* t)
{
	if(!GLAD_GL_ARB_compute_shader || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _ARB_compute_shader);
}

const CrocRegisterFunc _ARB_compute_variable_group_size[] =
{
	WRAP(glDispatchComputeGroupSizeARB),
	{nullptr, 0, nullptr}
};

void load_ARB_compute_variable_group_size(CrocThread* t)
{
	if(!GLAD_GL_ARB_compute_variable_group_size) return;
	croc_ex_registerGlobals(t, _ARB_compute_variable_group_size);
}

const CrocRegisterFunc _ARB_copy_image[] =
{
	WRAP(glCopyImageSubData),
	{nullptr, 0, nullptr}
};

void load_ARB_copy_image(CrocThread* t)
{
	if(!GLAD_GL_ARB_copy_image || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _ARB_copy_image);
}

void APIENTRY debugMessageCallbackARB(GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei length,
	const GLchar* message, const void* vm)
{
	auto t = croc_vm_getCurrentThread(cast(CrocThread*)vm);

	auto f = croc_ex_pushRegistryVar(t, "gl.DebugCallbackARB");
	croc_pushNull(t);
	croc_pushInt(t, source);
	croc_pushInt(t, type);
	croc_pushInt(t, id);
	croc_pushInt(t, severity);
	croc_pushStringn(t, message, length);
	croc_tryCall(t, f, 0);
}

const char* crocglDebugMessageCallbackARB_docs
= Docstr(DFunc("glDebugMessageCallbackARB") DParam("callback", "null|function")
R"(Works just like \link{glDebugMessageCallback}. This is a separate callback function and won't overlap with that.)");

word_t crocglDebugMessageCallbackARB(CrocThread* t)
{
	if(croc_ex_optParam(t, 1, CrocType_Function))
	{
		croc_vm_pushRegistry(t);
		croc_dup(t, 1);
		croc_fielda(t, -2, "gl.DebugCallbackARB");
		glDebugMessageCallbackARB(&debugMessageCallbackARB, croc_vm_getMainThread(t));
	}
	else
	{
		croc_vm_pushRegistry(t);
		croc_pushNull(t);
		croc_fielda(t, -2, "gl.DebugCallbackARB");
		glDebugMessageCallbackARB(nullptr, nullptr);
	}

	return 0;
}

const CrocRegisterFunc _ARB_debug_output[] =
{
	WRAP(glDebugMessageControlARB),
	WRAP(glDebugMessageInsertARB),
	{"glDebugMessageCallbackARB", 1, &crocglDebugMessageCallbackARB},
	WRAP(glGetDebugMessageLogARB),
	{nullptr, 0, nullptr}
};

void load_ARB_debug_output(CrocThread* t)
{
	if(!GLAD_GL_ARB_debug_output) return;
	croc_ex_registerGlobals(t, _ARB_debug_output);
}

const CrocRegisterFunc _ARB_draw_buffers_blend[] =
{
	WRAP(glBlendEquationiARB),
	WRAP(glBlendEquationSeparateiARB),
	WRAP(glBlendFunciARB),
	WRAP(glBlendFuncSeparateiARB),
	{nullptr, 0, nullptr}
};

void load_ARB_draw_buffers_blend(CrocThread* t)
{
	if(!GLAD_GL_ARB_draw_buffers_blend) return;
	croc_ex_registerGlobals(t, _ARB_draw_buffers_blend);
}

const CrocRegisterFunc _ARB_draw_elements_base_vertex[] =
{
	WRAP(glDrawElementsBaseVertex),
	WRAP(glDrawRangeElementsBaseVertex),
	WRAP(glDrawElementsInstancedBaseVertex),
	// WRAP(glMultiDrawElementsBaseVertex),
	{nullptr, 0, nullptr}
};

void load_ARB_draw_elements_base_vertex(CrocThread* t)
{
	if(!GLAD_GL_ARB_draw_elements_base_vertex || GLAD_GL_VERSION_3_2) return;
	croc_ex_registerGlobals(t, _ARB_draw_elements_base_vertex);
}

const CrocRegisterFunc _ARB_draw_indirect[] =
{
	WRAP(glDrawArraysIndirect),
	WRAP(glDrawElementsIndirect),
	{nullptr, 0, nullptr}
};

void load_ARB_draw_indirect(CrocThread* t)
{
	if(!GLAD_GL_ARB_draw_indirect || GLAD_GL_VERSION_4_0) return;
	croc_ex_registerGlobals(t, _ARB_draw_indirect);
}

const CrocRegisterFunc _ARB_ES2_compatibility[] =
{
	WRAP(glReleaseShaderCompiler),
	WRAP(glShaderBinary),
	WRAP(glGetShaderPrecisionFormat),
	WRAP(glDepthRangef),
	WRAP(glClearDepthf),
	{nullptr, 0, nullptr}
};

void load_ARB_ES2_compatibility(CrocThread* t)
{
	if(!GLAD_GL_ARB_ES2_compatibility || GLAD_GL_VERSION_4_1) return;
	croc_ex_registerGlobals(t, _ARB_ES2_compatibility);
}

const CrocRegisterFunc _ARB_framebuffer_no_attachments[] =
{
	WRAP(glFramebufferParameteri),
	WRAP(glGetFramebufferParameteriv),
	{nullptr, 0, nullptr}
};

void load_ARB_framebuffer_no_attachments(CrocThread* t)
{
	if(!GLAD_GL_ARB_framebuffer_no_attachments || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _ARB_framebuffer_no_attachments);
}

const CrocRegisterFunc _ARB_geometry_shader4[] =
{
	WRAP(glProgramParameteriARB),
	WRAP(glFramebufferTextureARB),
	WRAP(glFramebufferTextureLayerARB),
	WRAP(glFramebufferTextureFaceARB),
	{nullptr, 0, nullptr}
};

void load_ARB_geometry_shader4(CrocThread* t)
{
	if(!GLAD_GL_ARB_geometry_shader4) return;
	croc_ex_registerGlobals(t, _ARB_geometry_shader4);
}

const CrocRegisterFunc _ARB_get_program_binary[] =
{
	WRAP(glGetProgramBinary),
	WRAP(glProgramBinary),
	WRAP(glProgramParameteri),
	{nullptr, 0, nullptr}
};

void load_ARB_get_program_binary(CrocThread* t)
{
	if(!GLAD_GL_ARB_get_program_binary || GLAD_GL_VERSION_4_1) return;
	croc_ex_registerGlobals(t, _ARB_get_program_binary);
}

const CrocRegisterFunc _ARB_gpu_shader_fp64[] =
{
	WRAP(glUniform1d),
	WRAP(glUniform2d),
	WRAP(glUniform3d),
	WRAP(glUniform4d),
	WRAP(glUniform1dv),
	WRAP(glUniform2dv),
	WRAP(glUniform3dv),
	WRAP(glUniform4dv),
	WRAP(glUniformMatrix2dv),
	WRAP(glUniformMatrix3dv),
	WRAP(glUniformMatrix4dv),
	WRAP(glUniformMatrix2x3dv),
	WRAP(glUniformMatrix2x4dv),
	WRAP(glUniformMatrix3x2dv),
	WRAP(glUniformMatrix3x4dv),
	WRAP(glUniformMatrix4x2dv),
	WRAP(glUniformMatrix4x3dv),
	WRAP(glGetUniformdv),
	{nullptr, 0, nullptr}
};

void load_ARB_gpu_shader_fp64(CrocThread* t)
{
	if(!GLAD_GL_ARB_gpu_shader_fp64 || GLAD_GL_VERSION_4_0) return;
	croc_ex_registerGlobals(t, _ARB_gpu_shader_fp64);
}

const CrocRegisterFunc _ARB_indirect_parameters[] =
{
	WRAP(glMultiDrawArraysIndirectCountARB),
	WRAP(glMultiDrawElementsIndirectCountARB),
	{nullptr, 0, nullptr}
};

void load_ARB_indirect_parameters(CrocThread* t)
{
	if(!GLAD_GL_ARB_indirect_parameters) return;
	croc_ex_registerGlobals(t, _ARB_indirect_parameters);
}

const CrocRegisterFunc _ARB_instanced_arrays[] =
{
	WRAP(glVertexAttribDivisorARB),
	{nullptr, 0, nullptr}
};

void load_ARB_instanced_arrays(CrocThread* t)
{
	if(!GLAD_GL_ARB_instanced_arrays) return;
	croc_ex_registerGlobals(t, _ARB_instanced_arrays);
}

const CrocRegisterFunc _ARB_internalformat_query[] =
{
	WRAP(glGetInternalformativ),
	{nullptr, 0, nullptr}
};

void load_ARB_internalformat_query(CrocThread* t)
{
	if(!GLAD_GL_ARB_internalformat_query || GLAD_GL_VERSION_4_2) return;
	croc_ex_registerGlobals(t, _ARB_internalformat_query);
}

const CrocRegisterFunc _ARB_internalformat_query2[] =
{
	WRAP(glGetInternalformati64v),
	{nullptr, 0, nullptr}
};

void load_ARB_internalformat_query2(CrocThread* t)
{
	if(!GLAD_GL_ARB_internalformat_query2 || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _ARB_internalformat_query2);
}

const CrocRegisterFunc _ARB_invalidate_subdata[] =
{
	WRAP(glInvalidateTexSubImage),
	WRAP(glInvalidateTexImage),
	WRAP(glInvalidateBufferSubData),
	WRAP(glInvalidateBufferData),
	WRAP(glInvalidateFramebuffer),
	WRAP(glInvalidateSubFramebuffer),
	{nullptr, 0, nullptr}
};

void load_ARB_invalidate_subdata(CrocThread* t)
{
	if(!GLAD_GL_ARB_invalidate_subdata || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _ARB_invalidate_subdata);
}

const CrocRegisterFunc _ARB_multi_bind[] =
{
	WRAP(glBindBuffersBase),
	WRAP(glBindBuffersRange),
	WRAP(glBindTextures),
	WRAP(glBindSamplers),
	WRAP(glBindImageTextures),
	WRAP(glBindVertexBuffers),
	{nullptr, 0, nullptr}
};

void load_ARB_multi_bind(CrocThread* t)
{
	if(!GLAD_GL_ARB_multi_bind || GLAD_GL_VERSION_4_4) return;
	croc_ex_registerGlobals(t, _ARB_multi_bind);
}

const CrocRegisterFunc _ARB_multi_draw_indirect[] =
{
	WRAP(glMultiDrawArraysIndirect),
	WRAP(glMultiDrawElementsIndirect),
	{nullptr, 0, nullptr}
};

void load_ARB_multi_draw_indirect(CrocThread* t)
{
	if(!GLAD_GL_ARB_multi_draw_indirect || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _ARB_multi_draw_indirect);
}

const CrocRegisterFunc _ARB_program_interface_query[] =
{
	WRAP(glGetProgramInterfaceiv),
	WRAP(glGetProgramResourceIndex),
	{"glGetProgramResourceName", 3, &crocglGetProgramResourceName},
	WRAP(glGetProgramResourceiv),
	WRAP(glGetProgramResourceLocation),
	WRAP(glGetProgramResourceLocationIndex),
	{nullptr, 0, nullptr}
};

void load_ARB_program_interface_query(CrocThread* t)
{
	if(!GLAD_GL_ARB_program_interface_query || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _ARB_program_interface_query);
}

const CrocRegisterFunc _ARB_provoking_vertex[] =
{
	WRAP(glProvokingVertex),
	{nullptr, 0, nullptr}
};

void load_ARB_provoking_vertex(CrocThread* t)
{
	if(!GLAD_GL_ARB_provoking_vertex || GLAD_GL_VERSION_3_2) return;
	croc_ex_registerGlobals(t, _ARB_provoking_vertex);
}

const CrocRegisterFunc _ARB_robustness[] =
{
	WRAP(glGetGraphicsResetStatusARB),
	WRAP(glGetnTexImageARB),
	WRAP(glReadnPixelsARB),
	WRAP(glGetnCompressedTexImageARB),
	WRAP(glGetnUniformfvARB),
	WRAP(glGetnUniformivARB),
	WRAP(glGetnUniformuivARB),
	WRAP(glGetnUniformdvARB),
	WRAP(glGetnMapdvARB),
	WRAP(glGetnMapfvARB),
	WRAP(glGetnMapivARB),
	WRAP(glGetnPixelMapfvARB),
	WRAP(glGetnPixelMapuivARB),
	WRAP(glGetnPixelMapusvARB),
	WRAP(glGetnPolygonStippleARB),
	WRAP(glGetnColorTableARB),
	WRAP(glGetnConvolutionFilterARB),
	WRAP(glGetnSeparableFilterARB),
	WRAP(glGetnHistogramARB),
	WRAP(glGetnMinmaxARB),
	{nullptr, 0, nullptr}
};

void load_ARB_robustness(CrocThread* t)
{
	if(!GLAD_GL_ARB_robustness) return;
	croc_ex_registerGlobals(t, _ARB_robustness);
}

const CrocRegisterFunc _ARB_sample_shading[] =
{
	WRAP(glMinSampleShadingARB),
	{nullptr, 0, nullptr}
};

void load_ARB_sample_shading(CrocThread* t)
{
	if(!GLAD_GL_ARB_sample_shading) return;
	croc_ex_registerGlobals(t, _ARB_sample_shading);
}

const CrocRegisterFunc _ARB_sampler_objects[] =
{
	WRAPGEN(glGenSamplers),
	WRAPDELETE(glDeleteSamplers),
	WRAP(glIsSampler),
	WRAP(glBindSampler),
	WRAP(glSamplerParameteri),
	WRAP(glSamplerParameteriv),
	WRAP(glSamplerParameterf),
	WRAP(glSamplerParameterfv),
	WRAP(glSamplerParameterIiv),
	WRAP(glSamplerParameterIuiv),
	WRAP(glGetSamplerParameteriv),
	WRAP(glGetSamplerParameterIiv),
	WRAP(glGetSamplerParameterfv),
	WRAP(glGetSamplerParameterIuiv),
	{nullptr, 0, nullptr}
};

void load_ARB_sampler_objects(CrocThread* t)
{
	if(!GLAD_GL_ARB_sampler_objects || GLAD_GL_VERSION_3_3) return;
	croc_ex_registerGlobals(t, _ARB_sampler_objects);
}

const CrocRegisterFunc _ARB_separate_shader_objects[] =
{
	WRAP(glUseProgramStages),
	WRAP(glActiveShaderProgram),
	{"glCreateShaderProgramv", 2, &crocglCreateShaderProgramv},
	WRAP(glBindProgramPipeline),
	WRAPDELETE(glDeleteProgramPipelines),
	WRAPGEN(glGenProgramPipelines),
	WRAP(glIsProgramPipeline),
	WRAP(glGetProgramPipelineiv),
	WRAP(glProgramUniform1i),
	WRAP(glProgramUniform1iv),
	WRAP(glProgramUniform1f),
	WRAP(glProgramUniform1fv),
	WRAP(glProgramUniform1d),
	WRAP(glProgramUniform1dv),
	WRAP(glProgramUniform1ui),
	WRAP(glProgramUniform1uiv),
	WRAP(glProgramUniform2i),
	WRAP(glProgramUniform2iv),
	WRAP(glProgramUniform2f),
	WRAP(glProgramUniform2fv),
	WRAP(glProgramUniform2d),
	WRAP(glProgramUniform2dv),
	WRAP(glProgramUniform2ui),
	WRAP(glProgramUniform2uiv),
	WRAP(glProgramUniform3i),
	WRAP(glProgramUniform3iv),
	WRAP(glProgramUniform3f),
	WRAP(glProgramUniform3fv),
	WRAP(glProgramUniform3d),
	WRAP(glProgramUniform3dv),
	WRAP(glProgramUniform3ui),
	WRAP(glProgramUniform3uiv),
	WRAP(glProgramUniform4i),
	WRAP(glProgramUniform4iv),
	WRAP(glProgramUniform4f),
	WRAP(glProgramUniform4fv),
	WRAP(glProgramUniform4d),
	WRAP(glProgramUniform4dv),
	WRAP(glProgramUniform4ui),
	WRAP(glProgramUniform4uiv),
	WRAP(glProgramUniformMatrix2fv),
	WRAP(glProgramUniformMatrix3fv),
	WRAP(glProgramUniformMatrix4fv),
	WRAP(glProgramUniformMatrix2dv),
	WRAP(glProgramUniformMatrix3dv),
	WRAP(glProgramUniformMatrix4dv),
	WRAP(glProgramUniformMatrix2x3fv),
	WRAP(glProgramUniformMatrix3x2fv),
	WRAP(glProgramUniformMatrix2x4fv),
	WRAP(glProgramUniformMatrix4x2fv),
	WRAP(glProgramUniformMatrix3x4fv),
	WRAP(glProgramUniformMatrix4x3fv),
	WRAP(glProgramUniformMatrix2x3dv),
	WRAP(glProgramUniformMatrix3x2dv),
	WRAP(glProgramUniformMatrix2x4dv),
	WRAP(glProgramUniformMatrix4x2dv),
	WRAP(glProgramUniformMatrix3x4dv),
	WRAP(glProgramUniformMatrix4x3dv),
	WRAP(glValidateProgramPipeline),
	{"glGetProgramPipelineInfoLog", 1, &crocglGetProgramPipelineInfoLog},
	{nullptr, 0, nullptr}
};

void load_ARB_separate_shader_objects(CrocThread* t)
{
	if(!GLAD_GL_ARB_separate_shader_objects || GLAD_GL_VERSION_4_1) return;
	croc_ex_registerGlobals(t, _ARB_separate_shader_objects);
}

const CrocRegisterFunc _ARB_shader_atomic_counters[] =
{
	WRAP(glGetActiveAtomicCounterBufferiv),
	{nullptr, 0, nullptr}
};

void load_ARB_shader_atomic_counters(CrocThread* t)
{
	if(!GLAD_GL_ARB_shader_atomic_counters || GLAD_GL_VERSION_4_2) return;
	croc_ex_registerGlobals(t, _ARB_shader_atomic_counters);
}

const CrocRegisterFunc _ARB_shader_image_load_store[] =
{
	WRAP(glBindImageTexture),
	WRAP(glMemoryBarrier),
	{nullptr, 0, nullptr}
};

void load_ARB_shader_image_load_store(CrocThread* t)
{
	if(!GLAD_GL_ARB_shader_image_load_store || GLAD_GL_VERSION_4_2) return;
	croc_ex_registerGlobals(t, _ARB_shader_image_load_store);
}

const CrocRegisterFunc _ARB_shader_storage_buffer_object[] =
{
	WRAP(glShaderStorageBlockBinding),
	{nullptr, 0, nullptr}
};

void load_ARB_shader_storage_buffer_object(CrocThread* t)
{
	if(!GLAD_GL_ARB_shader_storage_buffer_object || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _ARB_shader_storage_buffer_object);
}

const CrocRegisterFunc _ARB_shader_subroutine[] =
{
	WRAP(glGetSubroutineUniformLocation),
	WRAP(glGetSubroutineIndex),
	WRAP(glGetActiveSubroutineUniformiv),
	{"glGetActiveSubroutineUniformName", 3, &crocglGetActiveSubroutineUniformName},
	{"glGetActiveSubroutineName", 3, &crocglGetActiveSubroutineName},
	WRAP(glUniformSubroutinesuiv),
	WRAP(glGetUniformSubroutineuiv),
	WRAP(glGetProgramStageiv),
	{nullptr, 0, nullptr}
};

void load_ARB_shader_subroutine(CrocThread* t)
{
	if(!GLAD_GL_ARB_shader_subroutine || GLAD_GL_VERSION_4_0) return;
	croc_ex_registerGlobals(t, _ARB_shader_subroutine);
}

const char* crocglCompileShaderIncludeARB_docs
= Docstr(DFunc("glCompileShaderIncludeARB") DParam("shader", "int") DParam("paths", "array")
R"(Takes an array of include paths in \tt{paths}, which must be an array of strings.)");

word_t crocglCompileShaderIncludeARB(CrocThread* t)
{
	auto shader = cast(GLuint)croc_ex_checkIntParam(t, 1);
	croc_ex_checkParam(t, 2, CrocType_Array);
	auto pathsLen = croc_len(t, 2);

	for(word i = 0; i < pathsLen; i++)
	{
		croc_idxi(t, 2, i);

		if(!croc_isString(t, -1))
			croc_eh_throwStd(t, "TypeError", "Array element %d is not a string", i);

		croc_popTop(t);
	}

	const GLchar* paths_[128];
	const GLchar** paths;
	uword_t pathsSize;

	if(pathsLen < 128)
		paths = paths_;
	else
	{
		pathsSize = pathsLen * sizeof(GLchar*);
		paths = cast(const GLchar**)croc_mem_alloc(t, pathsSize);
	}

	for(word i = 0; i < pathsLen; i++)
	{
		croc_idxi(t, 2, i);
		paths[i] = croc_getString(t, -1);
		croc_popTop(t);
	}

	glCompileShaderIncludeARB(shader, pathsLen, paths, nullptr);

	if(paths != paths_)
		croc_mem_free(t, cast(void**)&paths, &pathsSize);

	return 0;
}

word_t crocglGetNamedStringARB(CrocThread* t)
{
	auto name = croc_ex_checkStringParam(t, 1);

	GLint length = -1;
	glGetNamedStringivARB(-1, name, GL_NAMED_STRING_LENGTH_ARB, &length);

	if(length == -1)
		return 0;

	uword_t size = length * sizeof(GLchar);
	auto buf = cast(GLchar*)croc_mem_alloc(t, size);
	GLsizei realLength = 0;
	glGetNamedStringARB(-1, name, length, &realLength, buf);
	auto ok = croc_tryPushStringn(t, buf, realLength);
	croc_mem_free(t, cast(void**)&buf, &size);

	if(!ok)
		croc_eh_throwStd(t, "UnicodeError", "Invalid UTF-8 sequence");

	return 1;
}

const CrocRegisterFunc _ARB_shading_language_include[] =
{
	WRAP(glNamedStringARB),
	WRAP(glDeleteNamedStringARB),
	{"glCompileShaderIncludeARB", 2, &crocglCompileShaderIncludeARB},
	WRAP(glIsNamedStringARB),
	{"glGetNamedStringARB", 1, &crocglGetNamedStringARB},
	WRAP(glGetNamedStringivARB),
	{nullptr, 0, nullptr}
};

void load_ARB_shading_language_include(CrocThread* t)
{
	if(!GLAD_GL_ARB_shading_language_include) return;
	croc_ex_registerGlobals(t, _ARB_shading_language_include);
}

const CrocRegisterFunc _ARB_sparse_texture[] =
{
	WRAP(glTexPageCommitmentARB),
	{nullptr, 0, nullptr}
};

void load_ARB_sparse_texture(CrocThread* t)
{
	if(!GLAD_GL_ARB_sparse_texture) return;
	croc_ex_registerGlobals(t, _ARB_sparse_texture);
}

const CrocRegisterFunc _ARB_sync[] =
{
	// WRAP(glFenceSync),
	WRAP(glIsSync),
	WRAP(glDeleteSync),
	WRAP(glClientWaitSync),
	WRAP(glWaitSync),
	WRAP(glGetInteger64v),
	WRAP(glGetSynciv),
	{nullptr, 0, nullptr}
};

void load_ARB_sync(CrocThread* t)
{
	if(!GLAD_GL_ARB_sync || GLAD_GL_VERSION_3_2) return;
	croc_ex_registerGlobals(t, _ARB_sync);
}

const CrocRegisterFunc _ARB_tessellation_shader[] =
{
	WRAP(glPatchParameteri),
	WRAP(glPatchParameterfv),
	{nullptr, 0, nullptr}
};

void load_ARB_tessellation_shader(CrocThread* t)
{
	if(!GLAD_GL_ARB_tessellation_shader || GLAD_GL_VERSION_4_0) return;
	croc_ex_registerGlobals(t, _ARB_tessellation_shader);
}

const CrocRegisterFunc _ARB_texture_buffer_range[] =
{
	WRAP(glTexBufferRange),
	{nullptr, 0, nullptr}
};

void load_ARB_texture_buffer_range(CrocThread* t)
{
	if(!GLAD_GL_ARB_texture_buffer_range || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _ARB_texture_buffer_range);
}

const CrocRegisterFunc _ARB_texture_multisample[] =
{
	WRAP(glTexImage2DMultisample),
	WRAP(glTexImage3DMultisample),
	WRAP(glGetMultisamplefv),
	WRAP(glSampleMaski),
	{nullptr, 0, nullptr}
};

void load_ARB_texture_multisample(CrocThread* t)
{
	if(!GLAD_GL_ARB_texture_multisample || GLAD_GL_VERSION_3_2) return;
	croc_ex_registerGlobals(t, _ARB_texture_multisample);
}

const CrocRegisterFunc _ARB_texture_storage[] =
{
	WRAP(glTexStorage1D),
	WRAP(glTexStorage2D),
	WRAP(glTexStorage3D),
	{nullptr, 0, nullptr}
};

void load_ARB_texture_storage(CrocThread* t)
{
	if(!GLAD_GL_ARB_texture_storage || GLAD_GL_VERSION_4_2) return;
	croc_ex_registerGlobals(t, _ARB_texture_storage);
}

const CrocRegisterFunc _ARB_texture_storage_multisample[] =
{
	WRAP(glTexStorage2DMultisample),
	WRAP(glTexStorage3DMultisample),
	{nullptr, 0, nullptr}
};

void load_ARB_texture_storage_multisample(CrocThread* t)
{
	if(!GLAD_GL_ARB_texture_storage_multisample || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _ARB_texture_storage_multisample);
}

const CrocRegisterFunc _ARB_texture_view[] =
{
	WRAP(glTextureView),
	{nullptr, 0, nullptr}
};

void load_ARB_texture_view(CrocThread* t)
{
	if(!GLAD_GL_ARB_texture_view || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _ARB_texture_view);
}

const CrocRegisterFunc _ARB_timer_query[] =
{
	WRAP(glQueryCounter),
	WRAP(glGetQueryObjecti64v),
	WRAP(glGetQueryObjectui64v),
	{nullptr, 0, nullptr}
};

void load_ARB_timer_query(CrocThread* t)
{
	if(!GLAD_GL_ARB_timer_query || GLAD_GL_VERSION_3_3) return;
	croc_ex_registerGlobals(t, _ARB_timer_query);
}

const CrocRegisterFunc _ARB_transform_feedback2[] =
{
	WRAP(glBindTransformFeedback),
	WRAPDELETE(glDeleteTransformFeedbacks),
	WRAPGEN(glGenTransformFeedbacks),
	WRAP(glIsTransformFeedback),
	WRAP(glPauseTransformFeedback),
	WRAP(glResumeTransformFeedback),
	WRAP(glDrawTransformFeedback),
	{nullptr, 0, nullptr}
};

void load_ARB_transform_feedback2(CrocThread* t)
{
	if(!GLAD_GL_ARB_transform_feedback2 || GLAD_GL_VERSION_4_0) return;
	croc_ex_registerGlobals(t, _ARB_transform_feedback2);
}

const CrocRegisterFunc _ARB_transform_feedback3[] =
{
	WRAP(glDrawTransformFeedbackStream),
	WRAP(glBeginQueryIndexed),
	WRAP(glEndQueryIndexed),
	WRAP(glGetQueryIndexediv),
	{nullptr, 0, nullptr}
};

void load_ARB_transform_feedback3(CrocThread* t)
{
	if(!GLAD_GL_ARB_transform_feedback3 || GLAD_GL_VERSION_4_0) return;
	croc_ex_registerGlobals(t, _ARB_transform_feedback3);
}

const CrocRegisterFunc _ARB_transform_feedback_instanced[] =
{
	WRAP(glDrawTransformFeedbackInstanced),
	WRAP(glDrawTransformFeedbackStreamInstanced),
	{nullptr, 0, nullptr}
};

void load_ARB_transform_feedback_instanced(CrocThread* t)
{
	if(!GLAD_GL_ARB_transform_feedback_instanced || GLAD_GL_VERSION_4_2) return;
	croc_ex_registerGlobals(t, _ARB_transform_feedback_instanced);
}

const CrocRegisterFunc _ARB_vertex_attrib_64bit[] =
{
	WRAP(glVertexAttribL1d),
	WRAP(glVertexAttribL2d),
	WRAP(glVertexAttribL3d),
	WRAP(glVertexAttribL4d),
	WRAP(glVertexAttribL1dv),
	WRAP(glVertexAttribL2dv),
	WRAP(glVertexAttribL3dv),
	WRAP(glVertexAttribL4dv),
	WRAP(glVertexAttribLPointer),
	WRAP(glGetVertexAttribLdv),
	{nullptr, 0, nullptr}
};

void load_ARB_vertex_attrib_64bit(CrocThread* t)
{
	if(!GLAD_GL_ARB_vertex_attrib_64bit || GLAD_GL_VERSION_4_1) return;
	croc_ex_registerGlobals(t, _ARB_vertex_attrib_64bit);
}

const CrocRegisterFunc _ARB_vertex_attrib_binding[] =
{
	WRAP(glBindVertexBuffer),
	WRAP(glVertexAttribFormat),
	WRAP(glVertexAttribIFormat),
	WRAP(glVertexAttribLFormat),
	WRAP(glVertexAttribBinding),
	WRAP(glVertexBindingDivisor),
	{nullptr, 0, nullptr}
};

void load_ARB_vertex_attrib_binding(CrocThread* t)
{
	if(!GLAD_GL_ARB_vertex_attrib_binding || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _ARB_vertex_attrib_binding);
}

const CrocRegisterFunc _ARB_vertex_type_2_10_10_10_rev[] =
{
	WRAP(glVertexAttribP1ui),
	WRAP(glVertexAttribP1uiv),
	WRAP(glVertexAttribP2ui),
	WRAP(glVertexAttribP2uiv),
	WRAP(glVertexAttribP3ui),
	WRAP(glVertexAttribP3uiv),
	WRAP(glVertexAttribP4ui),
	WRAP(glVertexAttribP4uiv),
	WRAP(glVertexP2ui),
	WRAP(glVertexP2uiv),
	WRAP(glVertexP3ui),
	WRAP(glVertexP3uiv),
	WRAP(glVertexP4ui),
	WRAP(glVertexP4uiv),
	WRAP(glTexCoordP1ui),
	WRAP(glTexCoordP1uiv),
	WRAP(glTexCoordP2ui),
	WRAP(glTexCoordP2uiv),
	WRAP(glTexCoordP3ui),
	WRAP(glTexCoordP3uiv),
	WRAP(glTexCoordP4ui),
	WRAP(glTexCoordP4uiv),
	WRAP(glMultiTexCoordP1ui),
	WRAP(glMultiTexCoordP1uiv),
	WRAP(glMultiTexCoordP2ui),
	WRAP(glMultiTexCoordP2uiv),
	WRAP(glMultiTexCoordP3ui),
	WRAP(glMultiTexCoordP3uiv),
	WRAP(glMultiTexCoordP4ui),
	WRAP(glMultiTexCoordP4uiv),
	WRAP(glNormalP3ui),
	WRAP(glNormalP3uiv),
	WRAP(glColorP3ui),
	WRAP(glColorP3uiv),
	WRAP(glColorP4ui),
	WRAP(glColorP4uiv),
	WRAP(glSecondaryColorP3ui),
	WRAP(glSecondaryColorP3uiv),
	{nullptr, 0, nullptr}
};

void load_ARB_vertex_type_2_10_10_10_rev(CrocThread* t)
{
	if(!GLAD_GL_ARB_vertex_type_2_10_10_10_rev || GLAD_GL_VERSION_3_3) return;
	croc_ex_registerGlobals(t, _ARB_vertex_type_2_10_10_10_rev);
}

const CrocRegisterFunc _ARB_viewport_array[] =
{
	WRAP(glViewportArrayv),
	WRAP(glViewportIndexedf),
	WRAP(glViewportIndexedfv),
	WRAP(glScissorArrayv),
	WRAP(glScissorIndexed),
	WRAP(glScissorIndexedv),
	WRAP(glDepthRangeArrayv),
	WRAP(glDepthRangeIndexed),
	WRAP(glGetFloati_v),
	WRAP(glGetDoublei_v),
	{nullptr, 0, nullptr}
};

void load_ARB_viewport_array(CrocThread* t)
{
	if(!GLAD_GL_ARB_viewport_array || GLAD_GL_VERSION_4_1) return;
	croc_ex_registerGlobals(t, _ARB_viewport_array);
}

const CrocRegisterFunc _EXT_depth_bounds_test[] =
{
	WRAP(glDepthBoundsEXT),
	{nullptr, 0, nullptr}
};

void load_EXT_depth_bounds_test(CrocThread* t)
{
	if(!GLAD_GL_EXT_depth_bounds_test) return;
	croc_ex_registerGlobals(t, _EXT_depth_bounds_test);
}

const char* crocglMapNamedBufferEXT_docs
= Docstr(DFunc("glMapNamedBufferEXT") DParam("name", "int") DParam("access", "int") DParamD("mb", "memblock", "null")
R"(Works just like \link{glMapNamedBuffer}.)");

word_t crocglMapNamedBufferEXT(CrocThread* t)
{
	auto name = cast(GLuint)croc_ex_checkIntParam(t, 1);
	auto access = cast(GLenum)croc_ex_checkIntParam(t, 2);
	auto haveMemblock = croc_ex_optParam(t, 3, CrocType_Memblock);

	GLint size;
	glGetNamedBufferParameterivEXT(name, GL_BUFFER_SIZE, &size);

	if(auto ptr = glMapNamedBufferEXT(name, access))
	{
		if(haveMemblock)
		{
			croc_memblock_reviewNativeArray(t, 3, ptr, size);
			croc_dup(t, 3);
		}
		else
			croc_memblock_viewNativeArray(t, ptr, size);
	}
	else
		croc_pushNull(t);

	return 1;
}

const char* crocglMapNamedBufferRangeEXT_docs
= Docstr(DFunc("glMapNamedBufferRangeEXT") DParam("name", "int") DParam("offset", "int") DParam("length", "int") DParam(
	"access", "int") DParamD("mb", "memblock", "null")
R"(Works just like \link{glMapNamedBufferRange}.)");

word_t crocglMapNamedBufferRangeEXT(CrocThread* t)
{
	auto name = cast(GLuint)croc_ex_checkIntParam(t, 1);
	auto offset = cast(GLintptr)croc_ex_checkIntParam(t, 2);
	auto length = cast(GLsizeiptr)croc_ex_checkIntParam(t, 3);
	auto access = cast(GLenum)croc_ex_checkIntParam(t, 4);
	auto haveMemblock = croc_ex_optParam(t, 5, CrocType_Memblock);

	if(auto ptr = glMapNamedBufferRangeEXT(name, offset, length, access))
	{
		if(haveMemblock)
		{
			croc_memblock_reviewNativeArray(t, 5, ptr, length);
			croc_dup(t, 5);
		}
		else
			croc_memblock_viewNativeArray(t, ptr, length);
	}
	else
		croc_pushNull(t);

	return 1;
}

const CrocRegisterFunc _EXT_direct_state_access[] =
{
	WRAP(glMatrixLoadfEXT),
	WRAP(glMatrixLoaddEXT),
	WRAP(glMatrixMultfEXT),
	WRAP(glMatrixMultdEXT),
	WRAP(glMatrixLoadIdentityEXT),
	WRAP(glMatrixRotatefEXT),
	WRAP(glMatrixRotatedEXT),
	WRAP(glMatrixScalefEXT),
	WRAP(glMatrixScaledEXT),
	WRAP(glMatrixTranslatefEXT),
	WRAP(glMatrixTranslatedEXT),
	WRAP(glMatrixFrustumEXT),
	WRAP(glMatrixOrthoEXT),
	WRAP(glMatrixPopEXT),
	WRAP(glMatrixPushEXT),
	WRAP(glClientAttribDefaultEXT),
	WRAP(glPushClientAttribDefaultEXT),
	WRAP(glTextureParameterfEXT),
	WRAP(glTextureParameterfvEXT),
	WRAP(glTextureParameteriEXT),
	WRAP(glTextureParameterivEXT),
	WRAP(glTextureImage1DEXT),
	WRAP(glTextureImage2DEXT),
	WRAP(glTextureSubImage1DEXT),
	WRAP(glTextureSubImage2DEXT),
	WRAP(glCopyTextureImage1DEXT),
	WRAP(glCopyTextureImage2DEXT),
	WRAP(glCopyTextureSubImage1DEXT),
	WRAP(glCopyTextureSubImage2DEXT),
	WRAP(glGetTextureImageEXT),
	WRAP(glGetTextureParameterfvEXT),
	WRAP(glGetTextureParameterivEXT),
	WRAP(glGetTextureLevelParameterfvEXT),
	WRAP(glGetTextureLevelParameterivEXT),
	WRAP(glTextureImage3DEXT),
	WRAP(glTextureSubImage3DEXT),
	WRAP(glCopyTextureSubImage3DEXT),
	WRAP(glBindMultiTextureEXT),
	WRAP(glMultiTexCoordPointerEXT),
	WRAP(glMultiTexEnvfEXT),
	WRAP(glMultiTexEnvfvEXT),
	WRAP(glMultiTexEnviEXT),
	WRAP(glMultiTexEnvivEXT),
	WRAP(glMultiTexGendEXT),
	WRAP(glMultiTexGendvEXT),
	WRAP(glMultiTexGenfEXT),
	WRAP(glMultiTexGenfvEXT),
	WRAP(glMultiTexGeniEXT),
	WRAP(glMultiTexGenivEXT),
	WRAP(glGetMultiTexEnvfvEXT),
	WRAP(glGetMultiTexEnvivEXT),
	WRAP(glGetMultiTexGendvEXT),
	WRAP(glGetMultiTexGenfvEXT),
	WRAP(glGetMultiTexGenivEXT),
	WRAP(glMultiTexParameteriEXT),
	WRAP(glMultiTexParameterivEXT),
	WRAP(glMultiTexParameterfEXT),
	WRAP(glMultiTexParameterfvEXT),
	WRAP(glMultiTexImage1DEXT),
	WRAP(glMultiTexImage2DEXT),
	WRAP(glMultiTexSubImage1DEXT),
	WRAP(glMultiTexSubImage2DEXT),
	WRAP(glCopyMultiTexImage1DEXT),
	WRAP(glCopyMultiTexImage2DEXT),
	WRAP(glCopyMultiTexSubImage1DEXT),
	WRAP(glCopyMultiTexSubImage2DEXT),
	WRAP(glGetMultiTexImageEXT),
	WRAP(glGetMultiTexParameterfvEXT),
	WRAP(glGetMultiTexParameterivEXT),
	WRAP(glGetMultiTexLevelParameterfvEXT),
	WRAP(glGetMultiTexLevelParameterivEXT),
	WRAP(glMultiTexImage3DEXT),
	WRAP(glMultiTexSubImage3DEXT),
	WRAP(glCopyMultiTexSubImage3DEXT),
	WRAP(glEnableClientStateIndexedEXT),
	WRAP(glDisableClientStateIndexedEXT),
	WRAP(glGetFloatIndexedvEXT),
	WRAP(glGetDoubleIndexedvEXT),
	// WRAP(glGetPointerIndexedvEXT),
	WRAP(glEnableIndexedEXT),
	WRAP(glDisableIndexedEXT),
	WRAP(glIsEnabledIndexedEXT),
	WRAP(glGetIntegerIndexedvEXT),
	WRAP(glGetBooleanIndexedvEXT),
	WRAP(glCompressedTextureImage3DEXT),
	WRAP(glCompressedTextureImage2DEXT),
	WRAP(glCompressedTextureImage1DEXT),
	WRAP(glCompressedTextureSubImage3DEXT),
	WRAP(glCompressedTextureSubImage2DEXT),
	WRAP(glCompressedTextureSubImage1DEXT),
	WRAP(glGetCompressedTextureImageEXT),
	WRAP(glCompressedMultiTexImage3DEXT),
	WRAP(glCompressedMultiTexImage2DEXT),
	WRAP(glCompressedMultiTexImage1DEXT),
	WRAP(glCompressedMultiTexSubImage3DEXT),
	WRAP(glCompressedMultiTexSubImage2DEXT),
	WRAP(glCompressedMultiTexSubImage1DEXT),
	WRAP(glGetCompressedMultiTexImageEXT),
	WRAP(glMatrixLoadTransposefEXT),
	WRAP(glMatrixLoadTransposedEXT),
	WRAP(glMatrixMultTransposefEXT),
	WRAP(glMatrixMultTransposedEXT),
	WRAP(glNamedBufferDataEXT),
	WRAP(glNamedBufferSubDataEXT),
	{"glMapNamedBufferEXT", 3, &crocglMapNamedBufferEXT},
	WRAP(glUnmapNamedBufferEXT),
	WRAP(glGetNamedBufferParameterivEXT),
	// WRAP(glGetNamedBufferPointervEXT),
	WRAP(glGetNamedBufferSubDataEXT),
	WRAP(glProgramUniform1fEXT),
	WRAP(glProgramUniform2fEXT),
	WRAP(glProgramUniform3fEXT),
	WRAP(glProgramUniform4fEXT),
	WRAP(glProgramUniform1iEXT),
	WRAP(glProgramUniform2iEXT),
	WRAP(glProgramUniform3iEXT),
	WRAP(glProgramUniform4iEXT),
	WRAP(glProgramUniform1fvEXT),
	WRAP(glProgramUniform2fvEXT),
	WRAP(glProgramUniform3fvEXT),
	WRAP(glProgramUniform4fvEXT),
	WRAP(glProgramUniform1ivEXT),
	WRAP(glProgramUniform2ivEXT),
	WRAP(glProgramUniform3ivEXT),
	WRAP(glProgramUniform4ivEXT),
	WRAP(glProgramUniformMatrix2fvEXT),
	WRAP(glProgramUniformMatrix3fvEXT),
	WRAP(glProgramUniformMatrix4fvEXT),
	WRAP(glProgramUniformMatrix2x3fvEXT),
	WRAP(glProgramUniformMatrix3x2fvEXT),
	WRAP(glProgramUniformMatrix2x4fvEXT),
	WRAP(glProgramUniformMatrix4x2fvEXT),
	WRAP(glProgramUniformMatrix3x4fvEXT),
	WRAP(glProgramUniformMatrix4x3fvEXT),
	WRAP(glTextureBufferEXT),
	WRAP(glMultiTexBufferEXT),
	WRAP(glTextureParameterIivEXT),
	WRAP(glTextureParameterIuivEXT),
	WRAP(glGetTextureParameterIivEXT),
	WRAP(glGetTextureParameterIuivEXT),
	WRAP(glMultiTexParameterIivEXT),
	WRAP(glMultiTexParameterIuivEXT),
	WRAP(glGetMultiTexParameterIivEXT),
	WRAP(glGetMultiTexParameterIuivEXT),
	WRAP(glProgramUniform1uiEXT),
	WRAP(glProgramUniform2uiEXT),
	WRAP(glProgramUniform3uiEXT),
	WRAP(glProgramUniform4uiEXT),
	WRAP(glProgramUniform1uivEXT),
	WRAP(glProgramUniform2uivEXT),
	WRAP(glProgramUniform3uivEXT),
	WRAP(glProgramUniform4uivEXT),
	WRAP(glNamedProgramLocalParameters4fvEXT),
	WRAP(glNamedProgramLocalParameterI4iEXT),
	WRAP(glNamedProgramLocalParameterI4ivEXT),
	WRAP(glNamedProgramLocalParametersI4ivEXT),
	WRAP(glNamedProgramLocalParameterI4uiEXT),
	WRAP(glNamedProgramLocalParameterI4uivEXT),
	WRAP(glNamedProgramLocalParametersI4uivEXT),
	WRAP(glGetNamedProgramLocalParameterIivEXT),
	WRAP(glGetNamedProgramLocalParameterIuivEXT),
	WRAP(glEnableClientStateiEXT),
	WRAP(glDisableClientStateiEXT),
	WRAP(glGetFloati_vEXT),
	WRAP(glGetDoublei_vEXT),
	// WRAP(glGetPointeri_vEXT),
	WRAP(glNamedProgramStringEXT),
	WRAP(glNamedProgramLocalParameter4dEXT),
	WRAP(glNamedProgramLocalParameter4dvEXT),
	WRAP(glNamedProgramLocalParameter4fEXT),
	WRAP(glNamedProgramLocalParameter4fvEXT),
	WRAP(glGetNamedProgramLocalParameterdvEXT),
	WRAP(glGetNamedProgramLocalParameterfvEXT),
	WRAP(glGetNamedProgramivEXT),
	WRAP(glGetNamedProgramStringEXT),
	WRAP(glNamedRenderbufferStorageEXT),
	WRAP(glGetNamedRenderbufferParameterivEXT),
	WRAP(glNamedRenderbufferStorageMultisampleEXT),
	WRAP(glNamedRenderbufferStorageMultisampleCoverageEXT),
	WRAP(glCheckNamedFramebufferStatusEXT),
	WRAP(glNamedFramebufferTexture1DEXT),
	WRAP(glNamedFramebufferTexture2DEXT),
	WRAP(glNamedFramebufferTexture3DEXT),
	WRAP(glNamedFramebufferRenderbufferEXT),
	WRAP(glGetNamedFramebufferAttachmentParameterivEXT),
	WRAP(glGenerateTextureMipmapEXT),
	WRAP(glGenerateMultiTexMipmapEXT),
	WRAP(glFramebufferDrawBufferEXT),
	WRAP(glFramebufferDrawBuffersEXT),
	WRAP(glFramebufferReadBufferEXT),
	WRAP(glGetFramebufferParameterivEXT),
	WRAP(glNamedCopyBufferSubDataEXT),
	WRAP(glNamedFramebufferTextureEXT),
	WRAP(glNamedFramebufferTextureLayerEXT),
	WRAP(glNamedFramebufferTextureFaceEXT),
	WRAP(glTextureRenderbufferEXT),
	WRAP(glMultiTexRenderbufferEXT),
	WRAP(glVertexArrayVertexOffsetEXT),
	WRAP(glVertexArrayColorOffsetEXT),
	WRAP(glVertexArrayEdgeFlagOffsetEXT),
	WRAP(glVertexArrayIndexOffsetEXT),
	WRAP(glVertexArrayNormalOffsetEXT),
	WRAP(glVertexArrayTexCoordOffsetEXT),
	WRAP(glVertexArrayMultiTexCoordOffsetEXT),
	WRAP(glVertexArrayFogCoordOffsetEXT),
	WRAP(glVertexArraySecondaryColorOffsetEXT),
	WRAP(glVertexArrayVertexAttribOffsetEXT),
	WRAP(glVertexArrayVertexAttribIOffsetEXT),
	WRAP(glEnableVertexArrayEXT),
	WRAP(glDisableVertexArrayEXT),
	WRAP(glEnableVertexArrayAttribEXT),
	WRAP(glDisableVertexArrayAttribEXT),
	WRAP(glGetVertexArrayIntegervEXT),
	// WRAP(glGetVertexArrayPointervEXT),
	WRAP(glGetVertexArrayIntegeri_vEXT),
	// WRAP(glGetVertexArrayPointeri_vEXT),
	{"glMapNamedBufferRangeEXT", 5, &crocglMapNamedBufferRangeEXT},
	WRAP(glFlushMappedNamedBufferRangeEXT),
	WRAP(glNamedBufferStorageEXT),
	WRAP(glClearNamedBufferDataEXT),
	WRAP(glClearNamedBufferSubDataEXT),
	WRAP(glNamedFramebufferParameteriEXT),
	WRAP(glGetNamedFramebufferParameterivEXT),
	WRAP(glProgramUniform1dEXT),
	WRAP(glProgramUniform2dEXT),
	WRAP(glProgramUniform3dEXT),
	WRAP(glProgramUniform4dEXT),
	WRAP(glProgramUniform1dvEXT),
	WRAP(glProgramUniform2dvEXT),
	WRAP(glProgramUniform3dvEXT),
	WRAP(glProgramUniform4dvEXT),
	WRAP(glProgramUniformMatrix2dvEXT),
	WRAP(glProgramUniformMatrix3dvEXT),
	WRAP(glProgramUniformMatrix4dvEXT),
	WRAP(glProgramUniformMatrix2x3dvEXT),
	WRAP(glProgramUniformMatrix2x4dvEXT),
	WRAP(glProgramUniformMatrix3x2dvEXT),
	WRAP(glProgramUniformMatrix3x4dvEXT),
	WRAP(glProgramUniformMatrix4x2dvEXT),
	WRAP(glProgramUniformMatrix4x3dvEXT),
	WRAP(glTextureBufferRangeEXT),
	WRAP(glTextureStorage1DEXT),
	WRAP(glTextureStorage2DEXT),
	WRAP(glTextureStorage3DEXT),
	WRAP(glTextureStorage2DMultisampleEXT),
	WRAP(glTextureStorage3DMultisampleEXT),
	WRAP(glVertexArrayBindVertexBufferEXT),
	WRAP(glVertexArrayVertexAttribFormatEXT),
	WRAP(glVertexArrayVertexAttribIFormatEXT),
	WRAP(glVertexArrayVertexAttribLFormatEXT),
	WRAP(glVertexArrayVertexAttribBindingEXT),
	WRAP(glVertexArrayVertexBindingDivisorEXT),
	WRAP(glVertexArrayVertexAttribLOffsetEXT),
	WRAP(glTexturePageCommitmentEXT),
	WRAP(glVertexArrayVertexAttribDivisorEXT),
	{nullptr, 0, nullptr}
};

void load_EXT_direct_state_access(CrocThread* t)
{
	if(!GLAD_GL_EXT_direct_state_access) return;
	croc_ex_registerGlobals(t, _EXT_direct_state_access);
}

const CrocRegisterFunc _INTEL_map_texture[] =
{
	WRAP(glSyncTextureINTEL),
	WRAP(glUnmapTexture2DINTEL),
	// WRAP(glMapTexture2DINTEL),
	{nullptr, 0, nullptr}
};

void load_INTEL_map_texture(CrocThread* t)
{
	if(!GLAD_GL_INTEL_map_texture) return;
	croc_ex_registerGlobals(t, _INTEL_map_texture);
}

const CrocRegisterFunc _KHR_blend_equation_advanced[] =
{
	WRAP(glBlendBarrierKHR),
	{nullptr, 0, nullptr}
};

void load_KHR_blend_equation_advanced(CrocThread* t)
{
	if(!GLAD_GL_KHR_blend_equation_advanced) return;
	croc_ex_registerGlobals(t, _KHR_blend_equation_advanced);
}

const CrocRegisterFunc _KHR_debug[] =
{
	WRAP(glDebugMessageControl),
	WRAP(glDebugMessageInsert),
	{"glDebugMessageCallback", 1, &crocglDebugMessageCallback},
	WRAP(glGetDebugMessageLog),
	WRAP(glPushDebugGroup),
	WRAP(glPopDebugGroup),
	WRAP(glObjectLabel),
	{"glGetObjectLabel", 2, &crocglGetObjectLabel},
	{"glObjectPtrLabel", 1, &crocglGetObjectPtrLabel},
	WRAP(glGetObjectPtrLabel),
	// WRAP(glGetPointerv),
	{nullptr, 0, nullptr}
};

void load_KHR_debug(CrocThread* t)
{
	if(!GLAD_GL_KHR_debug || GLAD_GL_VERSION_4_3) return;
	croc_ex_registerGlobals(t, _KHR_debug);
}

const CrocRegisterFunc _NV_bindless_multi_draw_indirect[] =
{
	WRAP(glMultiDrawArraysIndirectBindlessNV),
	WRAP(glMultiDrawElementsIndirectBindlessNV),
	{nullptr, 0, nullptr}
};

void load_NV_bindless_multi_draw_indirect(CrocThread* t)
{
	if(!GLAD_GL_NV_bindless_multi_draw_indirect) return;
	croc_ex_registerGlobals(t, _NV_bindless_multi_draw_indirect);
}

const CrocRegisterFunc _NV_bindless_multi_draw_indirect_count[] =
{
	WRAP(glMultiDrawArraysIndirectBindlessCountNV),
	WRAP(glMultiDrawElementsIndirectBindlessCountNV),
	{nullptr, 0, nullptr}
};

void load_NV_bindless_multi_draw_indirect_count(CrocThread* t)
{
	if(!GLAD_GL_NV_bindless_multi_draw_indirect_count) return;
	croc_ex_registerGlobals(t, _NV_bindless_multi_draw_indirect_count);
}

const CrocRegisterFunc _NV_bindless_texture[] =
{
	WRAP(glGetTextureHandleNV),
	WRAP(glGetTextureSamplerHandleNV),
	WRAP(glMakeTextureHandleResidentNV),
	WRAP(glMakeTextureHandleNonResidentNV),
	WRAP(glGetImageHandleNV),
	WRAP(glMakeImageHandleResidentNV),
	WRAP(glMakeImageHandleNonResidentNV),
	WRAP(glUniformHandleui64NV),
	WRAP(glUniformHandleui64vNV),
	WRAP(glProgramUniformHandleui64NV),
	WRAP(glProgramUniformHandleui64vNV),
	WRAP(glIsTextureHandleResidentNV),
	WRAP(glIsImageHandleResidentNV),
	{nullptr, 0, nullptr}
};

void load_NV_bindless_texture(CrocThread* t)
{
	if(!GLAD_GL_NV_bindless_texture) return;
	croc_ex_registerGlobals(t, _NV_bindless_texture);
}

const CrocRegisterFunc _NV_blend_equation_advanced[] =
{
	WRAP(glBlendParameteriNV),
	WRAP(glBlendBarrierNV),
	{nullptr, 0, nullptr}
};

void load_NV_blend_equation_advanced(CrocThread* t)
{
	if(!GLAD_GL_NV_blend_equation_advanced) return;
	croc_ex_registerGlobals(t, _NV_blend_equation_advanced);
}

const CrocRegisterFunc _NV_copy_image[] =
{
	WRAP(glCopyImageSubDataNV),
	{nullptr, 0, nullptr}
};

void load_NV_copy_image(CrocThread* t)
{
	if(!GLAD_GL_NV_copy_image) return;
	croc_ex_registerGlobals(t, _NV_copy_image);
}

const CrocRegisterFunc _NV_depth_buffer_float[] =
{
	WRAP(glDepthRangedNV),
	WRAP(glClearDepthdNV),
	WRAP(glDepthBoundsdNV),
	{nullptr, 0, nullptr}
};

void load_NV_depth_buffer_float(CrocThread* t)
{
	if(!GLAD_GL_NV_depth_buffer_float) return;
	croc_ex_registerGlobals(t, _NV_depth_buffer_float);
}

const CrocRegisterFunc _NV_explicit_multisample[] =
{
	WRAP(glGetMultisamplefvNV),
	WRAP(glSampleMaskIndexedNV),
	WRAP(glTexRenderbufferNV),
	{nullptr, 0, nullptr}
};

void load_NV_explicit_multisample(CrocThread* t)
{
	if(!GLAD_GL_NV_explicit_multisample) return;
	croc_ex_registerGlobals(t, _NV_explicit_multisample);
}

const CrocRegisterFunc _NV_shader_buffer_load[] =
{
	WRAP(glMakeBufferResidentNV),
	WRAP(glMakeBufferNonResidentNV),
	WRAP(glIsBufferResidentNV),
	WRAP(glMakeNamedBufferResidentNV),
	WRAP(glMakeNamedBufferNonResidentNV),
	WRAP(glIsNamedBufferResidentNV),
	WRAP(glGetBufferParameterui64vNV),
	WRAP(glGetNamedBufferParameterui64vNV),
	WRAP(glGetIntegerui64vNV),
	WRAP(glUniformui64NV),
	WRAP(glUniformui64vNV),
	// WRAP(glGetUniformui64vNV), shared with AMD_gpu_shader_int64
	WRAP(glProgramUniformui64NV),
	WRAP(glProgramUniformui64vNV),
	{nullptr, 0, nullptr}
};

void load_NV_shader_buffer_load(CrocThread* t)
{
	if(!GLAD_GL_NV_shader_buffer_load) return;
	croc_ex_registerGlobals(t, _NV_shader_buffer_load);
}

const CrocRegisterFunc _NV_texture_barrier[] =
{
	WRAP(glTextureBarrierNV),
	{nullptr, 0, nullptr}
};

void load_NV_texture_barrier(CrocThread* t)
{
	if(!GLAD_GL_NV_texture_barrier) return;
	croc_ex_registerGlobals(t, _NV_texture_barrier);
}

const CrocRegisterFunc _NV_texture_multisample[] =
{
	WRAP(glTexImage2DMultisampleCoverageNV),
	WRAP(glTexImage3DMultisampleCoverageNV),
	WRAP(glTextureImage2DMultisampleNV),
	WRAP(glTextureImage3DMultisampleNV),
	WRAP(glTextureImage2DMultisampleCoverageNV),
	WRAP(glTextureImage3DMultisampleCoverageNV),
	{nullptr, 0, nullptr}
};

void load_NV_texture_multisample(CrocThread* t)
{
	if(!GLAD_GL_NV_texture_multisample) return;
	croc_ex_registerGlobals(t, _NV_texture_multisample);
}

const CrocRegisterFunc _NV_vertex_buffer_unified_memory[] =
{
	WRAP(glBufferAddressRangeNV),
	WRAP(glVertexFormatNV),
	WRAP(glNormalFormatNV),
	WRAP(glColorFormatNV),
	WRAP(glIndexFormatNV),
	WRAP(glTexCoordFormatNV),
	WRAP(glEdgeFlagFormatNV),
	WRAP(glSecondaryColorFormatNV),
	WRAP(glFogCoordFormatNV),
	WRAP(glVertexAttribFormatNV),
	WRAP(glVertexAttribIFormatNV),
	WRAP(glGetIntegerui64i_vNV),
	{nullptr, 0, nullptr}
};

void load_NV_vertex_buffer_unified_memory(CrocThread* t)
{
	if(!GLAD_GL_NV_vertex_buffer_unified_memory) return;
	croc_ex_registerGlobals(t, _NV_vertex_buffer_unified_memory);
}

const char* _extFlags_docs = Docstr(DNs("ext")
R"(This namespace contains a boolean constant for each extension that this library supports. A \tt{true} means this
computer supports that extension, and a \tt{false} means it doesn't. So if you want to know if the \tt{ARB_debug_output}
extension is supported, you just have to test for \tt{gl.ext.ARB_debug_output}.

The following non-core extensions are supported:

\blist
	\li \tt{AMD_gpu_shader_int64}
	\li \tt{AMD_interleaved_elements}
	\li \tt{AMD_occlusion_query_event}
	\li \tt{AMD_performance_monitor}
	\li \tt{AMD_sample_positions}
	\li \tt{AMD_sparse_texture}
	\li \tt{AMD_stencil_operation_extended}
	\li \tt{ARB_bindless_texture}
	\li \tt{ARB_cl_event}
	\li \tt{ARB_compute_variable_group_size}
	\li \tt{ARB_debug_output}
	\li \tt{ARB_draw_buffers_blend}
	\li \tt{ARB_geometry_shader4}
	\li \tt{ARB_indirect_parameters}
	\li \tt{ARB_instanced_arrays}
	\li \tt{ARB_robustness}
	\li \tt{ARB_sample_shading}
	\li \tt{ARB_shading_language_include}
	\li \tt{ARB_sparse_texture}
	\li \tt{EXT_depth_bounds_test}
	\li \tt{EXT_direct_state_access}
	\li \tt{INTEL_map_texture}
	\li \tt{KHR_blend_equation_advanced}
	\li \tt{NV_bindless_multi_draw_indirect}
	\li \tt{NV_bindless_multi_draw_indirect_count}
	\li \tt{NV_bindless_texture}
	\li \tt{NV_blend_equation_advanced}
	\li \tt{NV_copy_image}
	\li \tt{NV_depth_buffer_float}
	\li \tt{NV_explicit_multisample}
	\li \tt{NV_shader_buffer_load}
	\li \tt{NV_texture_barrier}
	\li \tt{NV_texture_multisample}
	\li \tt{NV_vertex_buffer_unified_memory}
\endlist

In addition, a number of "core" or "forward compatibility" extensions are supported. These are extensions which backport
functionality from newer OpenGL versions to older hardware which can support them. For example, some OpenGL 4.0-class
hardware might not support all the features necessary for OpenGL 4.5, but it might support a small subset. These
extensions will let those older cards access the newer functionality.

Note that these extensions are only loaded if the OpenGL context is older than the version in which they were folded
into core. The following lists the extensions and the version they became core functions (so any version lower than
that, they may be supported):

\table
	\row \cell \tt{GL_ARB_base_instance}                \cell 4.2
	\row \cell \tt{GL_ARB_blend_func_extended}          \cell 3.3
	\row \cell \tt{GL_ARB_buffer_storage}               \cell 4.4
	\row \cell \tt{GL_ARB_clear_buffer_object}          \cell 4.3
	\row \cell \tt{GL_ARB_clear_texture}                \cell 4.4
	\row \cell \tt{GL_ARB_compute_shader}               \cell 4.3
	\row \cell \tt{GL_ARB_copy_image}                   \cell 4.3
	\row \cell \tt{GL_ARB_draw_elements_base_vertex}    \cell 3.2
	\row \cell \tt{GL_ARB_draw_indirect}                \cell 4.0
	\row \cell \tt{GL_ARB_ES2_compatibility}            \cell 4.1
	\row \cell \tt{GL_ARB_framebuffer_no_attachments}   \cell 4.3
	\row \cell \tt{GL_ARB_get_program_binary}           \cell 4.1
	\row \cell \tt{GL_ARB_gpu_shader_fp64}              \cell 4.0
	\row \cell \tt{GL_ARB_internalformat_query}         \cell 4.2
	\row \cell \tt{GL_ARB_internalformat_query2}        \cell 4.3
	\row \cell \tt{GL_ARB_invalidate_subdata}           \cell 4.3
	\row \cell \tt{GL_ARB_multi_bind}                   \cell 4.4
	\row \cell \tt{GL_ARB_multi_draw_indirect}          \cell 4.3
	\row \cell \tt{GL_ARB_program_interface_query}      \cell 4.3
	\row \cell \tt{GL_ARB_provoking_vertex}             \cell 3.2
	\row \cell \tt{GL_ARB_sampler_objects}              \cell 3.3
	\row \cell \tt{GL_ARB_separate_shader_objects}      \cell 4.1
	\row \cell \tt{GL_ARB_shader_atomic_counters}       \cell 4.2
	\row \cell \tt{GL_ARB_shader_image_load_store}      \cell 4.2
	\row \cell \tt{GL_ARB_shader_storage_buffer_object} \cell 4.3
	\row \cell \tt{GL_ARB_shader_subroutine}            \cell 4.0
	\row \cell \tt{GL_ARB_sync}                         \cell 3.2
	\row \cell \tt{GL_ARB_tessellation_shader}          \cell 4.0
	\row \cell \tt{GL_ARB_texture_buffer_range}         \cell 4.3
	\row \cell \tt{GL_ARB_texture_multisample}          \cell 3.2
	\row \cell \tt{GL_ARB_texture_storage}              \cell 4.2
	\row \cell \tt{GL_ARB_texture_storage_multisample}  \cell 4.3
	\row \cell \tt{GL_ARB_texture_view}                 \cell 4.3
	\row \cell \tt{GL_ARB_timer_query}                  \cell 3.3
	\row \cell \tt{GL_ARB_transform_feedback2}          \cell 4.0
	\row \cell \tt{GL_ARB_transform_feedback3}          \cell 4.0
	\row \cell \tt{GL_ARB_transform_feedback_instanced} \cell 4.2
	\row \cell \tt{GL_ARB_vertex_attrib_64bit}          \cell 4.1
	\row \cell \tt{GL_ARB_vertex_attrib_binding}        \cell 4.3
	\row \cell \tt{GL_ARB_vertex_type_2_10_10_10_rev}   \cell 3.3
	\row \cell \tt{GL_ARB_viewport_array}               \cell 4.1
	\row \cell \tt{GL_KHR_debug}                        \cell 4.3
\endtable
)");

void loadExtFlags(CrocThread* t)
{
	croc_namespace_new(t, "ext");
	croc_pushBool(t, GLAD_GL_AMD_gpu_shader_int64);                  croc_fielda(t, -2, "AMD_gpu_shader_int64");
	croc_pushBool(t, GLAD_GL_AMD_interleaved_elements);              croc_fielda(t, -2, "AMD_interleaved_elements");
	croc_pushBool(t, GLAD_GL_AMD_occlusion_query_event);             croc_fielda(t, -2, "AMD_occlusion_query_event");
	croc_pushBool(t, GLAD_GL_AMD_performance_monitor);               croc_fielda(t, -2, "AMD_performance_monitor");
	croc_pushBool(t, GLAD_GL_AMD_sample_positions);                  croc_fielda(t, -2, "AMD_sample_positions");
	croc_pushBool(t, GLAD_GL_AMD_sparse_texture);                    croc_fielda(t, -2, "AMD_sparse_texture");
	croc_pushBool(t, GLAD_GL_AMD_stencil_operation_extended);        croc_fielda(t, -2, "AMD_stencil_operation_extended");
	croc_pushBool(t, GLAD_GL_ARB_bindless_texture);                  croc_fielda(t, -2, "ARB_bindless_texture");
	croc_pushBool(t, GLAD_GL_ARB_cl_event);                          croc_fielda(t, -2, "ARB_cl_event");
	croc_pushBool(t, GLAD_GL_ARB_compute_variable_group_size);       croc_fielda(t, -2, "ARB_compute_variable_group_size");
	croc_pushBool(t, GLAD_GL_ARB_debug_output);                      croc_fielda(t, -2, "ARB_debug_output");
	croc_pushBool(t, GLAD_GL_ARB_draw_buffers_blend);                croc_fielda(t, -2, "ARB_draw_buffers_blend");
	croc_pushBool(t, GLAD_GL_ARB_geometry_shader4);                  croc_fielda(t, -2, "ARB_geometry_shader4");
	croc_pushBool(t, GLAD_GL_ARB_indirect_parameters);               croc_fielda(t, -2, "ARB_indirect_parameters");
	croc_pushBool(t, GLAD_GL_ARB_instanced_arrays);                  croc_fielda(t, -2, "ARB_instanced_arrays");
	croc_pushBool(t, GLAD_GL_ARB_robustness);                        croc_fielda(t, -2, "ARB_robustness");
	croc_pushBool(t, GLAD_GL_ARB_sample_shading);                    croc_fielda(t, -2, "ARB_sample_shading");
	croc_pushBool(t, GLAD_GL_ARB_shading_language_include);          croc_fielda(t, -2, "ARB_shading_language_include");
	croc_pushBool(t, GLAD_GL_ARB_sparse_texture);                    croc_fielda(t, -2, "ARB_sparse_texture");
	croc_pushBool(t, GLAD_GL_EXT_depth_bounds_test);                 croc_fielda(t, -2, "EXT_depth_bounds_test");
	croc_pushBool(t, GLAD_GL_EXT_direct_state_access);               croc_fielda(t, -2, "EXT_direct_state_access");
	croc_pushBool(t, GLAD_GL_INTEL_map_texture);                     croc_fielda(t, -2, "INTEL_map_texture");
	croc_pushBool(t, GLAD_GL_KHR_blend_equation_advanced);           croc_fielda(t, -2, "KHR_blend_equation_advanced");
	croc_pushBool(t, GLAD_GL_NV_bindless_multi_draw_indirect);       croc_fielda(t, -2, "NV_bindless_multi_draw_indirect");
	croc_pushBool(t, GLAD_GL_NV_bindless_multi_draw_indirect_count); croc_fielda(t, -2, "NV_bindless_multi_draw_indirect_count");
	croc_pushBool(t, GLAD_GL_NV_bindless_texture);                   croc_fielda(t, -2, "NV_bindless_texture");
	croc_pushBool(t, GLAD_GL_NV_blend_equation_advanced);            croc_fielda(t, -2, "NV_blend_equation_advanced");
	croc_pushBool(t, GLAD_GL_NV_copy_image);                         croc_fielda(t, -2, "NV_copy_image");
	croc_pushBool(t, GLAD_GL_NV_depth_buffer_float);                 croc_fielda(t, -2, "NV_depth_buffer_float");
	croc_pushBool(t, GLAD_GL_NV_explicit_multisample);               croc_fielda(t, -2, "NV_explicit_multisample");
	croc_pushBool(t, GLAD_GL_NV_shader_buffer_load);                 croc_fielda(t, -2, "NV_shader_buffer_load");
	croc_pushBool(t, GLAD_GL_NV_texture_barrier);                    croc_fielda(t, -2, "NV_texture_barrier");
	croc_pushBool(t, GLAD_GL_NV_texture_multisample);                croc_fielda(t, -2, "NV_texture_multisample");
	croc_pushBool(t, GLAD_GL_NV_vertex_buffer_unified_memory);       croc_fielda(t, -2, "NV_vertex_buffer_unified_memory");
	croc_pushBool(t, GLAD_GL_ARB_base_instance);                     croc_fielda(t, -2, "ARB_base_instance");
	croc_pushBool(t, GLAD_GL_ARB_blend_func_extended);               croc_fielda(t, -2, "ARB_blend_func_extended");
	croc_pushBool(t, GLAD_GL_ARB_buffer_storage);                    croc_fielda(t, -2, "ARB_buffer_storage");
	croc_pushBool(t, GLAD_GL_ARB_clear_buffer_object);               croc_fielda(t, -2, "ARB_clear_buffer_object");
	croc_pushBool(t, GLAD_GL_ARB_clear_texture);                     croc_fielda(t, -2, "ARB_clear_texture");
	croc_pushBool(t, GLAD_GL_ARB_compute_shader);                    croc_fielda(t, -2, "ARB_compute_shader");
	croc_pushBool(t, GLAD_GL_ARB_copy_image);                        croc_fielda(t, -2, "ARB_copy_image");
	croc_pushBool(t, GLAD_GL_ARB_draw_elements_base_vertex);         croc_fielda(t, -2, "ARB_draw_elements_base_vertex");
	croc_pushBool(t, GLAD_GL_ARB_draw_indirect);                     croc_fielda(t, -2, "ARB_draw_indirect");
	croc_pushBool(t, GLAD_GL_ARB_ES2_compatibility);                 croc_fielda(t, -2, "ARB_ES2_compatibility");
	croc_pushBool(t, GLAD_GL_ARB_framebuffer_no_attachments);        croc_fielda(t, -2, "ARB_framebuffer_no_attachments");
	croc_pushBool(t, GLAD_GL_ARB_get_program_binary);                croc_fielda(t, -2, "ARB_get_program_binary");
	croc_pushBool(t, GLAD_GL_ARB_gpu_shader_fp64);                   croc_fielda(t, -2, "ARB_gpu_shader_fp64");
	croc_pushBool(t, GLAD_GL_ARB_internalformat_query);              croc_fielda(t, -2, "ARB_internalformat_query");
	croc_pushBool(t, GLAD_GL_ARB_internalformat_query2);             croc_fielda(t, -2, "ARB_internalformat_query2");
	croc_pushBool(t, GLAD_GL_ARB_invalidate_subdata);                croc_fielda(t, -2, "ARB_invalidate_subdata");
	croc_pushBool(t, GLAD_GL_ARB_multi_bind);                        croc_fielda(t, -2, "ARB_multi_bind");
	croc_pushBool(t, GLAD_GL_ARB_multi_draw_indirect);               croc_fielda(t, -2, "ARB_multi_draw_indirect");
	croc_pushBool(t, GLAD_GL_ARB_program_interface_query);           croc_fielda(t, -2, "ARB_program_interface_query");
	croc_pushBool(t, GLAD_GL_ARB_provoking_vertex);                  croc_fielda(t, -2, "ARB_provoking_vertex");
	croc_pushBool(t, GLAD_GL_ARB_sampler_objects);                   croc_fielda(t, -2, "ARB_sampler_objects");
	croc_pushBool(t, GLAD_GL_ARB_separate_shader_objects);           croc_fielda(t, -2, "ARB_separate_shader_objects");
	croc_pushBool(t, GLAD_GL_ARB_shader_atomic_counters);            croc_fielda(t, -2, "ARB_shader_atomic_counters");
	croc_pushBool(t, GLAD_GL_ARB_shader_image_load_store);           croc_fielda(t, -2, "ARB_shader_image_load_store");
	croc_pushBool(t, GLAD_GL_ARB_shader_storage_buffer_object);      croc_fielda(t, -2, "ARB_shader_storage_buffer_object");
	croc_pushBool(t, GLAD_GL_ARB_shader_subroutine);                 croc_fielda(t, -2, "ARB_shader_subroutine");
	croc_pushBool(t, GLAD_GL_ARB_sync);                              croc_fielda(t, -2, "ARB_sync");
	croc_pushBool(t, GLAD_GL_ARB_tessellation_shader);               croc_fielda(t, -2, "ARB_tessellation_shader");
	croc_pushBool(t, GLAD_GL_ARB_texture_buffer_range);              croc_fielda(t, -2, "ARB_texture_buffer_range");
	croc_pushBool(t, GLAD_GL_ARB_texture_multisample);               croc_fielda(t, -2, "ARB_texture_multisample");
	croc_pushBool(t, GLAD_GL_ARB_texture_storage);                   croc_fielda(t, -2, "ARB_texture_storage");
	croc_pushBool(t, GLAD_GL_ARB_texture_storage_multisample);       croc_fielda(t, -2, "ARB_texture_storage_multisample");
	croc_pushBool(t, GLAD_GL_ARB_texture_view);                      croc_fielda(t, -2, "ARB_texture_view");
	croc_pushBool(t, GLAD_GL_ARB_timer_query);                       croc_fielda(t, -2, "ARB_timer_query");
	croc_pushBool(t, GLAD_GL_ARB_transform_feedback2);               croc_fielda(t, -2, "ARB_transform_feedback2");
	croc_pushBool(t, GLAD_GL_ARB_transform_feedback3);               croc_fielda(t, -2, "ARB_transform_feedback3");
	croc_pushBool(t, GLAD_GL_ARB_transform_feedback_instanced);      croc_fielda(t, -2, "ARB_transform_feedback_instanced");
	croc_pushBool(t, GLAD_GL_ARB_vertex_attrib_64bit);               croc_fielda(t, -2, "ARB_vertex_attrib_64bit");
	croc_pushBool(t, GLAD_GL_ARB_vertex_attrib_binding);             croc_fielda(t, -2, "ARB_vertex_attrib_binding");
	croc_pushBool(t, GLAD_GL_ARB_vertex_type_2_10_10_10_rev);        croc_fielda(t, -2, "ARB_vertex_type_2_10_10_10_rev");
	croc_pushBool(t, GLAD_GL_ARB_viewport_array);                    croc_fielda(t, -2, "ARB_viewport_array");
	croc_pushBool(t, GLAD_GL_KHR_debug);                             croc_fielda(t, -2, "KHR_debug");
	croc_newGlobal(t, "ext");
}

const char* _version_docs = Docstr(DFunc("version")
R"(\returns the loaded OpenGL version as two integers, major and minor.)");

word_t _version(CrocThread* t)
{
	croc_pushInt(t, GLVersion.major);
	croc_pushInt(t, GLVersion.minor);
	return 2;
}

const CrocRegisterFunc _version_info = {"version", 0, &_version};

const struct
{
	const char* name;
	const char* docs;
} _funcDocs[] =
{
	{"version",                       _version_docs},
	{"glMapBuffer",                   crocglMapBuffer_docs},
	{"glShaderSource",                crocglShaderSource_docs},
	{"glGetVertexAttribPointerv",     crocglGetVertexAttribPointerv_docs},
	{"glGetActiveAttrib",             crocglGetActiveAttrib_docs},
	{"glGetActiveUniform",            crocglGetActiveUniform_docs},
	{"glMapBufferRange",              crocglMapBufferRange_docs},
	{"glTransformFeedbackVaryings",   crocglTransformFeedbackVaryings_docs},
	{"glGetTransformFeedbackVarying", crocglGetTransformFeedbackVarying_docs},
	{"glGetUniformIndices",           crocglGetUniformIndices_docs},
	{"glCreateShaderProgramv",        crocglCreateShaderProgramv_docs},
	{"glDebugMessageCallback",        crocglDebugMessageCallback_docs},
	{"glMapNamedBuffer",              crocglMapNamedBuffer_docs},
	{"glMapNamedBufferRange",         crocglMapNamedBufferRange_docs},
	{"glDebugMessageCallbackARB",     crocglDebugMessageCallbackARB_docs},
	{"glCompileShaderIncludeARB",     crocglCompileShaderIncludeARB_docs},
	{"glMapNamedBufferEXT",           crocglMapNamedBufferEXT_docs},
	{"glMapNamedBufferRangeEXT",      crocglMapNamedBufferRangeEXT_docs},
	{"ext",                           _extFlags_docs},
	{nullptr, nullptr}
};

word_t loader(CrocThread* t)
{
	croc_ex_registerGlobal(t, _version_info);

	loadConstants(t);

	loadGL1_0(t);
	loadGL1_1(t);
	loadGL1_2(t);
	loadGL1_3(t);
	loadGL1_4(t);
	loadGL1_5(t);
	loadGL2_0(t);
	loadGL2_1(t);
	loadGL3_0(t);
	loadGL3_1(t);
	loadGL3_2(t);
	loadGL3_3(t);
	loadGL4_0(t);
	loadGL4_1(t);
	loadGL4_2(t);
	loadGL4_3(t);
	loadGL4_4(t);
	loadGL4_5(t);

	loadExtFlags(t);

	load_AMD_gpu_shader_int64(t);
	load_AMD_interleaved_elements(t);
	load_AMD_occlusion_query_event(t);
	load_AMD_performance_monitor(t);
	load_AMD_sample_positions(t);
	load_AMD_sparse_texture(t);
	load_AMD_stencil_operation_extended(t);
	load_ARB_bindless_texture(t);
	load_ARB_cl_event(t);
	load_ARB_compute_variable_group_size(t);
	load_ARB_debug_output(t);
	load_ARB_draw_buffers_blend(t);
	load_ARB_geometry_shader4(t);
	load_ARB_indirect_parameters(t);
	load_ARB_instanced_arrays(t);
	load_ARB_robustness(t);
	load_ARB_sample_shading(t);
	load_ARB_shading_language_include(t);
	load_ARB_sparse_texture(t);
	load_EXT_depth_bounds_test(t);
	load_EXT_direct_state_access(t);
	load_INTEL_map_texture(t);
	load_KHR_blend_equation_advanced(t);
	load_NV_bindless_multi_draw_indirect(t);
	load_NV_bindless_multi_draw_indirect_count(t);
	load_NV_bindless_texture(t);
	load_NV_blend_equation_advanced(t);
	load_NV_copy_image(t);
	load_NV_depth_buffer_float(t);
	load_NV_explicit_multisample(t);
	load_NV_shader_buffer_load(t);
	load_NV_texture_barrier(t);
	load_NV_texture_multisample(t);
	load_NV_vertex_buffer_unified_memory(t);

	// Forward-compat extensions

	load_ARB_base_instance(t);
	load_ARB_blend_func_extended(t);
	load_ARB_buffer_storage(t);
	load_ARB_clear_buffer_object(t);
	load_ARB_clear_texture(t);
	load_ARB_compute_shader(t);
	load_ARB_copy_image(t);
	load_ARB_draw_elements_base_vertex(t);
	load_ARB_draw_indirect(t);
	load_ARB_ES2_compatibility(t);
	load_ARB_framebuffer_no_attachments(t);
	load_ARB_get_program_binary(t);
	load_ARB_gpu_shader_fp64(t);
	load_ARB_internalformat_query(t);
	load_ARB_internalformat_query2(t);
	load_ARB_invalidate_subdata(t);
	load_ARB_multi_bind(t);
	load_ARB_multi_draw_indirect(t);
	load_ARB_program_interface_query(t);
	load_ARB_provoking_vertex(t);
	load_ARB_sampler_objects(t);
	load_ARB_separate_shader_objects(t);
	load_ARB_shader_atomic_counters(t);
	load_ARB_shader_image_load_store(t);
	load_ARB_shader_storage_buffer_object(t);
	load_ARB_shader_subroutine(t);
	load_ARB_sync(t);
	load_ARB_tessellation_shader(t);
	load_ARB_texture_buffer_range(t);
	load_ARB_texture_multisample(t);
	load_ARB_texture_storage(t);
	load_ARB_texture_storage_multisample(t);
	load_ARB_texture_view(t);
	load_ARB_timer_query(t);
	load_ARB_transform_feedback2(t);
	load_ARB_transform_feedback3(t);
	load_ARB_transform_feedback_instanced(t);
	load_ARB_vertex_attrib_64bit(t);
	load_ARB_vertex_attrib_binding(t);
	load_ARB_vertex_type_2_10_10_10_rev(t);
	load_ARB_viewport_array(t);
	load_KHR_debug(t);

#ifdef CROC_BUILTIN_DOCS
	CrocDoc doc;
	croc_ex_doc_init(t, &doc, __FILE__);
	auto modNS = croc_dup(t, 0);
	croc_ex_doc_push(&doc, moduleDocs);

	// Have to do it like this since not all these functions may be available!
	for(auto fd = &_funcDocs[0]; fd->name != nullptr; fd++)
	{
		if(croc_hasField(t, modNS, fd->name))
			croc_field(t, modNS, fd->name);
		else
			croc_pushNull(t);

		croc_ex_doc_push(&doc, fd->docs);
		croc_ex_doc_pop(&doc, -1);
		croc_popTop(t);
	}

	croc_ex_doc_pop(&doc, -1);
	croc_ex_doc_finish(&doc);
	croc_popTop(t);
#endif

	return 0;
}
}

void loadOpenGL(CrocThread* t, GLADloadproc loadproc)
{
	if(GLAD_GL_VERSION_1_0)
		return;

	gladLoadGLLoader(loadproc);

	if(!GLAD_GL_VERSION_1_0)
		croc_eh_throwStd(t, "OSException", "Could not load OpenGL");

	if(!GLAD_GL_VERSION_3_0)
		croc_eh_throwStd(t, "OSException", "OpenGL 3.0+ support needed; this computer only has OpenGL %d.%d",
			GLVersion.major, GLVersion.minor);

	croc_ex_makeModule(t, "gl", &loader);
	croc_ex_import(t, "gl");
}
}