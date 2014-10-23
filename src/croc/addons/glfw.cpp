#ifndef CROC_GLFW_ADDON
#include "croc/api.h"

namespace croc
{
void initGlfwLib(CrocThread* t)
{
	croc_eh_throwStd(t, "ApiError", "Attempting to load the GLFW library, but it was not compiled in");
}
}
#else

#include "croc/ext/glad/glad.hpp"

#include "croc/addons/glfw.hpp"
#include "croc/addons/gl.hpp"
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{

#ifdef CROC_BUILTIN_DOCS
const char* moduleDocs = DModule("glfw")
R"(GLFW is a cross-platform library for creating windows and OpenGL contexts, managing them, and receiving input. This
module presents a Croc-like interface to GLFW 3, and also loads the OpenGL API into the \tt{gl} module.

\b{Prerequisites}

This module loads the GLFW 3 shared library dynamically when it's first imported. On windows, this is \tt{glfw3.dll}; on
Linux, \tt{libglfw3.so} or \tt{libglfw.so.3}; and on OSX \tt{libglfw.3.dylib}.

The loaded library must be \b{GLFW version 3.0.4 or higher.} This library will check that the version of GLFW that was
loaded is at least this version. If the shared library is not suitable, a \link{RuntimeError} will be thrown.

\b{Including this library in the host}

To use this library, the host must have it compiled into it. Compile Croc with the \tt{CROC_GLFW_ADDON} option enabled
in the CMake configuration. Then from your host, when setting up the VM use the \tt{croc_vm_loadAddons} or
\tt{croc_vm_loadAllAvailableAddons} API functions to load this library into the VM. Then from your Croc code, you can
just \tt{import glfw} to access it.

\b{OpenGL}

This library will load the OpenGL API for you into a module called \tt{gl}. It only supports a core context, which means
OpenGL 3.0 and up. It supports all the way up to OpenGL 4.5, as well as a number of extensions.

\b{Windows: A note on extensions and contexts}

The way Windows exposes OpenGL extension API functions is a bit weird, and supposedly different contexts can give
different function addresses for the same extension APIs. This library does not (yet) account for this oddity, but it
seems that this is a fairly unlikely scenario. According to \link[https://www.opengl.org/wiki/Load_OpenGL_Functions]{
this page}, "if two contexts come from the same vendor and refer to the same GPU, then the function pointers pulled from
one will work in another." Chances are this library will eventually support this strangeness, but for the time being, it
doesn't. The OpenGL core and extension APIs are loaded from the first context that you call \link{loadOpenGL} on.

\b{Events}

The native GLFW API uses callbacks to respond to OS events. This API does not work nicely with Croc's exception handling
methods, so instead this library uses a more traditional event API. \link{pollEvents} and \link{waitEvents} will return
event values which you can then dispatch on. If you really want a callback API, it's trivial to implement one on top of
this API.

\b{Errors}

Similarly, the native GLFW API uses an error callback to handle errors. This library instead throws exceptions to signal
errors, and as a result some functions which would return some error value instead throw an exception.
)";
#endif

// =====================================================================================================================
// GLFW shared lib loading

#ifdef _WIN32
const char* sharedLibPaths[] =
{
	"glfw3.dll",
	nullptr
};
#elif defined(__APPLE__) && defined(__MACH__)
const char* sharedLibPaths[] =
{
	"libglfw.3.dylib",
	nullptr;
};
#else
const char* sharedLibPaths[] =
{
	"libglfw3.so",
	"libglfw.so.3",
	"/usr/local/lib/libglfw3.so",
	"/usr/local/lib/libglfw.so.3",
	nullptr;
};
#endif

void loadSharedLib(CrocThread* t)
{
	if(glfwInit != nullptr)
		return;

	auto glfw = oscompat::openLibraryMulti(t, sharedLibPaths);

	if(glfw == nullptr)
		croc_eh_throwStd(t, "OSException", "Cannot find the glfw shared library");

	oscompat::getProc(t, glfw, "glfwInit", glfwInit);
	oscompat::getProc(t, glfw, "glfwTerminate", glfwTerminate);
	oscompat::getProc(t, glfw, "glfwGetVersion", glfwGetVersion);
	oscompat::getProc(t, glfw, "glfwGetVersionString", glfwGetVersionString);
	oscompat::getProc(t, glfw, "glfwGetMonitors", glfwGetMonitors);
	oscompat::getProc(t, glfw, "glfwGetPrimaryMonitor", glfwGetPrimaryMonitor);
	oscompat::getProc(t, glfw, "glfwGetMonitorPos", glfwGetMonitorPos);
	oscompat::getProc(t, glfw, "glfwGetMonitorPhysicalSize", glfwGetMonitorPhysicalSize);
	oscompat::getProc(t, glfw, "glfwGetMonitorName", glfwGetMonitorName);
	oscompat::getProc(t, glfw, "glfwGetVideoModes", glfwGetVideoModes);
	oscompat::getProc(t, glfw, "glfwGetVideoMode", glfwGetVideoMode);
	oscompat::getProc(t, glfw, "glfwSetGamma", glfwSetGamma);
	oscompat::getProc(t, glfw, "glfwGetGammaRamp", glfwGetGammaRamp);
	oscompat::getProc(t, glfw, "glfwSetGammaRamp", glfwSetGammaRamp);
	oscompat::getProc(t, glfw, "glfwDefaultWindowHints", glfwDefaultWindowHints);
	oscompat::getProc(t, glfw, "glfwWindowHint", glfwWindowHint);
	oscompat::getProc(t, glfw, "glfwCreateWindow", glfwCreateWindow);
	oscompat::getProc(t, glfw, "glfwDestroyWindow", glfwDestroyWindow);
	oscompat::getProc(t, glfw, "glfwWindowShouldClose", glfwWindowShouldClose);
	oscompat::getProc(t, glfw, "glfwSetWindowShouldClose", glfwSetWindowShouldClose);
	oscompat::getProc(t, glfw, "glfwSetWindowTitle", glfwSetWindowTitle);
	oscompat::getProc(t, glfw, "glfwGetWindowPos", glfwGetWindowPos);
	oscompat::getProc(t, glfw, "glfwSetWindowPos", glfwSetWindowPos);
	oscompat::getProc(t, glfw, "glfwGetWindowSize", glfwGetWindowSize);
	oscompat::getProc(t, glfw, "glfwSetWindowSize", glfwSetWindowSize);
	oscompat::getProc(t, glfw, "glfwGetFramebufferSize", glfwGetFramebufferSize);
	oscompat::getProc(t, glfw, "glfwIconifyWindow", glfwIconifyWindow);
	oscompat::getProc(t, glfw, "glfwRestoreWindow", glfwRestoreWindow);
	oscompat::getProc(t, glfw, "glfwShowWindow", glfwShowWindow);
	oscompat::getProc(t, glfw, "glfwHideWindow", glfwHideWindow);
	oscompat::getProc(t, glfw, "glfwGetWindowMonitor", glfwGetWindowMonitor);
	oscompat::getProc(t, glfw, "glfwGetWindowAttrib", glfwGetWindowAttrib);
	oscompat::getProc(t, glfw, "glfwPollEvents", glfwPollEvents);
	oscompat::getProc(t, glfw, "glfwWaitEvents", glfwWaitEvents);
	oscompat::getProc(t, glfw, "glfwGetInputMode", glfwGetInputMode);
	oscompat::getProc(t, glfw, "glfwSetInputMode", glfwSetInputMode);
	oscompat::getProc(t, glfw, "glfwGetKey", glfwGetKey);
	oscompat::getProc(t, glfw, "glfwGetMouseButton", glfwGetMouseButton);
	oscompat::getProc(t, glfw, "glfwGetCursorPos", glfwGetCursorPos);
	oscompat::getProc(t, glfw, "glfwSetCursorPos", glfwSetCursorPos);
	oscompat::getProc(t, glfw, "glfwJoystickPresent", glfwJoystickPresent);
	oscompat::getProc(t, glfw, "glfwGetJoystickAxes", glfwGetJoystickAxes);
	oscompat::getProc(t, glfw, "glfwGetJoystickButtons", glfwGetJoystickButtons);
	oscompat::getProc(t, glfw, "glfwGetJoystickName", glfwGetJoystickName);
	oscompat::getProc(t, glfw, "glfwSetClipboardString", glfwSetClipboardString);
	oscompat::getProc(t, glfw, "glfwGetClipboardString", glfwGetClipboardString);
	oscompat::getProc(t, glfw, "glfwMakeContextCurrent", glfwMakeContextCurrent);
	oscompat::getProc(t, glfw, "glfwGetCurrentContext", glfwGetCurrentContext);
	oscompat::getProc(t, glfw, "glfwSwapBuffers", glfwSwapBuffers);
	oscompat::getProc(t, glfw, "glfwSwapInterval", glfwSwapInterval);
	oscompat::getProc(t, glfw, "glfwExtensionSupported", glfwExtensionSupported);
	oscompat::getProc(t, glfw, "glfwGetProcAddress", glfwGetProcAddress);
	oscompat::getProc(t, glfw, "glfwSetErrorCallback", glfwSetErrorCallback);
	oscompat::getProc(t, glfw, "glfwSetMonitorCallback", glfwSetMonitorCallback);
	oscompat::getProc(t, glfw, "glfwSetWindowPosCallback", glfwSetWindowPosCallback);
	oscompat::getProc(t, glfw, "glfwSetWindowSizeCallback", glfwSetWindowSizeCallback);
	oscompat::getProc(t, glfw, "glfwSetWindowCloseCallback", glfwSetWindowCloseCallback);
	oscompat::getProc(t, glfw, "glfwSetWindowRefreshCallback", glfwSetWindowRefreshCallback);
	oscompat::getProc(t, glfw, "glfwSetWindowFocusCallback", glfwSetWindowFocusCallback);
	oscompat::getProc(t, glfw, "glfwSetWindowIconifyCallback", glfwSetWindowIconifyCallback);
	oscompat::getProc(t, glfw, "glfwSetFramebufferSizeCallback", glfwSetFramebufferSizeCallback);
	oscompat::getProc(t, glfw, "glfwSetKeyCallback", glfwSetKeyCallback);
	oscompat::getProc(t, glfw, "glfwSetCharCallback", glfwSetCharCallback);
	oscompat::getProc(t, glfw, "glfwSetMouseButtonCallback", glfwSetMouseButtonCallback);
	oscompat::getProc(t, glfw, "glfwSetCursorPosCallback", glfwSetCursorPosCallback);
	oscompat::getProc(t, glfw, "glfwSetCursorEnterCallback", glfwSetCursorEnterCallback);
	oscompat::getProc(t, glfw, "glfwSetScrollCallback", glfwSetScrollCallback);
	oscompat::getProc(t, glfw, "glfwGetTime", glfwGetTime);
	oscompat::getProc(t, glfw, "glfwSetTime", glfwSetTime);
}

// =====================================================================================================================
// Helpers

inline crocstr checkCrocstrParam(CrocThread* t, word_t slot)
{
	crocstr ret;
	ret.ptr = cast(const uchar*)croc_ex_checkStringParamn(t, slot, &ret.length);
	return ret;
}

const char* HandleMap = "glfw.HandleMap";
const char* Monitor_handle = "Monitor_handle";
const char* Window_handle = "Window_handle";

GLFWmonitor* Monitor_getThis(CrocThread* t, word slot = 0)
{
	croc_hfield(t, slot, Monitor_handle);

	if(!croc_isNativeobj(t, -1))
		croc_eh_throwStd(t, "StateError", "Attempting to access a Monitor that has not been initialized");

	auto ret = croc_getNativeobj(t, -1);
	croc_popTop(t);
	return cast(GLFWmonitor*)ret;
}

void pushMonitorObj(CrocThread* t, GLFWmonitor* mon)
{
	assert(mon != nullptr);
	croc_ex_pushRegistryVar(t, HandleMap);
	croc_pushNativeobj(t, mon);
	croc_idx(t, -2);
	croc_insertAndPop(t, -2);

	if(croc_isNull(t, -1))
	{
		croc_popTop(t);
		croc_pushGlobal(t, "Monitor");
		croc_pushNull(t);
		croc_pushNativeobj(t, mon);
		croc_call(t, -3, 1);
	}
}

GLFWwindow* Window_getThis(CrocThread* t, word slot = 0)
{
	croc_hfield(t, slot, Window_handle);

	if(!croc_isNativeobj(t, -1))
		croc_eh_throwStd(t, "StateError", "Attempting to access a Window that has not been initialized or has been destroyed");

	auto ret = croc_getNativeobj(t, -1);
	croc_popTop(t);
	return cast(GLFWwindow*)ret;
}

void pushWindowObj(CrocThread* t, GLFWwindow* win)
{
	assert(win != nullptr);
	croc_ex_pushRegistryVar(t, HandleMap);
	croc_pushNativeobj(t, win);
	croc_idx(t, -2);
	croc_insertAndPop(t, -2);

	if(croc_isNull(t, -1))
	{
		croc_popTop(t);
		croc_pushGlobal(t, "Window");
		croc_pushNull(t);
		croc_pushNativeobj(t, win);
		croc_call(t, -3, 1);
	}
}

void pushVideoMode(CrocThread* t, const GLFWvidmode* mode)
{
	croc_table_new(t, 6);
	croc_pushInt(t, mode->width);       croc_fielda(t, -2, "width");
	croc_pushInt(t, mode->height);      croc_fielda(t, -2, "height");
	croc_pushInt(t, mode->redBits);     croc_fielda(t, -2, "redBits");
	croc_pushInt(t, mode->greenBits);   croc_fielda(t, -2, "greenBits");
	croc_pushInt(t, mode->blueBits);    croc_fielda(t, -2, "blueBits");
	croc_pushInt(t, mode->refreshRate); croc_fielda(t, -2, "refreshRate");
}

struct GlfwEvent
{
	enum
	{
		WindowPos,
		WindowSize,
		WindowClose,
		WindowRefresh,
		WindowFocus,
		WindowIconify,
		FramebufferSize,
		MouseButton,
		CursorPos,
		CursorEnter,
		Scroll,
		Key,
		Char,
		Monitor
	} type;

	union
	{
		GLFWwindow* window;
		GLFWmonitor* monitor;
	};

	union
	{
		struct { int a, b, c, d; } ints;
		struct { double a, b; } doubles;
	};
};

// static! global state! aaaaaaa!
CrocThread* boundVM = nullptr;
GlfwEvent eventQueue[256];
uword queueStart, queueEnd, queueSize;
#define QUEUE_LENGTH (sizeof(eventQueue) / sizeof(GlfwEvent))

inline void checkVM(CrocThread* t)
{
	if(boundVM == nullptr)
		croc_eh_throwStd(t, "StateError", "Attempting to access GLFW before initializing");

	if(croc_vm_getMainThread(t) != boundVM)
		croc_eh_throwStd(t, "StateError", "Attempting to access GLFW from the wrong Croc VM");
}

void initEventQueue()
{
	queueStart = queueEnd = queueSize = 0;
}

void addEvent(const GlfwEvent& ev)
{
	if(queueSize == QUEUE_LENGTH)
		return;

	eventQueue[queueEnd++] = ev;

	if(queueEnd == QUEUE_LENGTH)
		queueEnd = 0;

	queueSize++;
}

void removeEvent(GlfwEvent& ev)
{
	assert(queueSize != 0);
	ev = eventQueue[queueStart++];

	if(queueStart == QUEUE_LENGTH)
		queueStart = 0;

	queueSize--;
}

void windowPosCallback(GLFWwindow* w, int a, int b)          { addEvent({GlfwEvent::WindowPos, {w}, {a, b, 0, 0}}); }
void windowSizeCallback(GLFWwindow* w, int a, int b)         { addEvent({GlfwEvent::WindowSize, {w}, {a, b, 0, 0}}); }
void windowCloseCallback(GLFWwindow* w)                      { addEvent({GlfwEvent::WindowClose, {w}, {0, 0, 0, 0}}); }
void windowRefreshCallback(GLFWwindow* w)                    { addEvent({GlfwEvent::WindowRefresh, {w}, {0, 0, 0, 0}}); }
void windowFocusCallback(GLFWwindow* w, int a)               { addEvent({GlfwEvent::WindowFocus, {w}, {a, 0, 0, 0}}); }
void windowIconifyCallback(GLFWwindow* w, int a)             { addEvent({GlfwEvent::WindowIconify, {w}, {a, 0, 0, 0}}); }
void framebufferSizeCallback(GLFWwindow* w, int a, int b)    { addEvent({GlfwEvent::FramebufferSize, {w}, {a, b, 0, 0}}); }
void mouseButtonCallback(GLFWwindow* w, int a, int b, int c) { addEvent({GlfwEvent::MouseButton, {w}, {a, b, c, 0}}); }
void cursorEnterCallback(GLFWwindow* w, int a)               { addEvent({GlfwEvent::CursorEnter, {w}, {a, 0, 0, 0}}); }
void keyCallback(GLFWwindow* w, int a, int b, int c, int d)  { addEvent({GlfwEvent::Key, {w}, {a, b, c, d}}); }
void charCallback(GLFWwindow* w, unsigned int a)             { addEvent({GlfwEvent::Char, {w}, {cast(int)a, 0, 0, 0}}); }

void monitorCallback(GLFWmonitor* m, int a)
{
	GlfwEvent ev;
	ev.type = GlfwEvent::Monitor;
	ev.monitor = m;
	ev.ints.a = a;
	addEvent(ev);
}

void cursorPosCallback(GLFWwindow* w, double a, double b)
{
	GlfwEvent ev;
	ev.type = GlfwEvent::CursorPos;
	ev.window = w;
	ev.doubles.a = a;
	ev.doubles.b = b;
	addEvent(ev);
}

void scrollCallback(GLFWwindow* w, double a, double b)
{
	GlfwEvent ev;
	ev.type = GlfwEvent::Scroll;
	ev.window = w;
	ev.doubles.a = a;
	ev.doubles.b = b;
	addEvent(ev);
}

int checkEventName(CrocThread* t, word_t slot)
{
	auto ev = checkCrocstrParam(t, slot);

	if(ev.length > 0)
	{
		switch(ev[0])
		{
			case 'c':
				if(ev == ATODA("close"))       return GlfwEvent::WindowClose; else
				if(ev == ATODA("curpos"))      return GlfwEvent::CursorPos; else
				if(ev == ATODA("curenter"))    return GlfwEvent::CursorEnter; else
				if(ev == ATODA("char"))        return GlfwEvent::Char; else break;
			case 'f':
				if(ev == ATODA("focus"))       return GlfwEvent::WindowFocus; else
				if(ev == ATODA("fbsize"))      return GlfwEvent::FramebufferSize; else break;
			case 'i':
				if(ev == ATODA("iconify"))     return GlfwEvent::WindowIconify; else break;
			case 'k':
				if(ev == ATODA("key"))         return GlfwEvent::Key; else break;
			case 'm':
				if(ev == ATODA("mousebutton")) return GlfwEvent::MouseButton; else
				if(ev == ATODA("monconnect"))  return GlfwEvent::Monitor; else break;
			case 'r':
				if(ev == ATODA("refresh"))     return GlfwEvent::WindowRefresh; else break;
			case 's':
				if(ev == ATODA("scroll"))      return GlfwEvent::Scroll; else break;
			case 'w':
				if(ev == ATODA("winpos"))      return GlfwEvent::WindowPos; else
				if(ev == ATODA("winsize"))     return GlfwEvent::WindowSize; else break;
			default:
				break;
		}
	}

	croc_eh_throwStd(t, "ValueError", "Invalid event name");
	return 0; // dummy
}

void pushEventName(CrocThread* t, decltype(GlfwEvent::type) type)
{
	switch(type)
	{
		case GlfwEvent::WindowPos:       croc_pushStringn(t, "winpos", 6);       return;
		case GlfwEvent::WindowSize:      croc_pushStringn(t, "winsize", 7);      return;
		case GlfwEvent::WindowClose:     croc_pushStringn(t, "close", 5);        return;
		case GlfwEvent::WindowRefresh:   croc_pushStringn(t, "refresh", 7);      return;
		case GlfwEvent::WindowFocus:     croc_pushStringn(t, "focus", 5);        return;
		case GlfwEvent::WindowIconify:   croc_pushStringn(t, "iconify", 7);      return;
		case GlfwEvent::FramebufferSize: croc_pushStringn(t, "fbsize", 6);       return;
		case GlfwEvent::MouseButton:     croc_pushStringn(t, "mousebutton", 11); return;
		case GlfwEvent::CursorPos:       croc_pushStringn(t, "curpos", 6);       return;
		case GlfwEvent::CursorEnter:     croc_pushStringn(t, "curenter", 8);     return;
		case GlfwEvent::Scroll:          croc_pushStringn(t, "scroll", 6);       return;
		case GlfwEvent::Key:             croc_pushStringn(t, "key", 3);          return;
		case GlfwEvent::Char:            croc_pushStringn(t, "char", 4);         return;
		case GlfwEvent::Monitor:         croc_pushStringn(t, "monconnect", 10);  return;
		default: assert(false);
	}
}

void pushPress(CrocThread* t, int p)
{
	if(p == GLFW_PRESS)
		croc_pushStringn(t, "press", 5);
	else if(p == GLFW_RELEASE)
		croc_pushStringn(t, "release", 7);
	else
		croc_pushStringn(t, "repeat", 6);
}

int pushEvent(CrocThread* t)
{
	GlfwEvent ev;
	removeEvent(ev);
	auto startSize = croc_getStackSize(t);
	pushEventName(t, ev.type);

	switch(ev.type)
	{
		case GlfwEvent::WindowPos:
		case GlfwEvent::WindowSize:
		case GlfwEvent::FramebufferSize:
			pushWindowObj(t, ev.window);
			croc_pushInt(t, cast(crocint)ev.ints.a); // x
			croc_pushInt(t, cast(crocint)ev.ints.b); // y
			break;

		case GlfwEvent::WindowClose:
		case GlfwEvent::WindowRefresh:
			pushWindowObj(t, ev.window);
			break;

		case GlfwEvent::WindowFocus:
		case GlfwEvent::WindowIconify:
		case GlfwEvent::CursorEnter:
			pushWindowObj(t, ev.window);
			croc_pushBool(t, ev.ints.a == GL_TRUE ? true : false);
			break;

		case GlfwEvent::MouseButton:
			pushWindowObj(t, ev.window);
			croc_pushInt(t, cast(crocint)ev.ints.a); // button
			pushPress(t, ev.ints.b);
			croc_pushInt(t, cast(crocint)ev.ints.c); // modifiers
			break;

		case GlfwEvent::CursorPos:
		case GlfwEvent::Scroll:
			pushWindowObj(t, ev.window);
			croc_pushFloat(t, cast(crocfloat)ev.doubles.a); // x
			croc_pushFloat(t, cast(crocfloat)ev.doubles.b); // y
			break;

		case GlfwEvent::Key:
			pushWindowObj(t, ev.window);
			croc_pushInt(t, cast(crocint)ev.ints.a); // key enum
			croc_pushInt(t, cast(crocint)ev.ints.b); // scancode
			pushPress(t, ev.ints.c);
			croc_pushInt(t, cast(crocint)ev.ints.d); // modifiers
			break;

		case GlfwEvent::Char:
			pushWindowObj(t, ev.window);
			croc_pushChar(t, cast(crocchar)ev.ints.a);
			break;

		case GlfwEvent::Monitor:
			pushMonitorObj(t, ev.monitor);
			croc_pushBool(t, ev.ints.a == GLFW_CONNECTED ? true : false);
			break;

		default:
			assert(false);
			break;
	}

	return croc_getStackSize(t) - startSize;
}

const char* ErrorInProgress = "glfw.ErrorInProgress";

// static! global state! aaaaaaa!
bool errorOccurred = false;

void errorCallback(int code, const char* msg)
{
	if(errorOccurred)
		return; // is this even possible?

	auto t = croc_vm_getCurrentThread(boundVM);
	croc_vm_pushRegistry(t);

	switch(code)
	{
		case GLFW_NOT_INITIALIZED:
		case GLFW_NO_CURRENT_CONTEXT:
			croc_eh_pushStd(t, "StateError");
			break;

		case GLFW_INVALID_ENUM:
		case GLFW_INVALID_VALUE:
			croc_eh_pushStd(t, "ValueError");
			break;

		case GLFW_OUT_OF_MEMORY:
			croc_eh_pushStd(t, "RuntimeError");
			break;

		case GLFW_API_UNAVAILABLE:
		case GLFW_VERSION_UNAVAILABLE:
		case GLFW_PLATFORM_ERROR:
		case GLFW_FORMAT_UNAVAILABLE:
			croc_eh_pushStd(t, "OSException");
			break;

		default: assert(false);
	}

	croc_pushNull(t);
	croc_pushString(t, msg);
	croc_call(t, -3, 1);
	croc_fielda(t, -2, ErrorInProgress);
	croc_popTop(t);
	errorOccurred = true;
}

void clearError(CrocThread* t)
{
	if(errorOccurred)
	{
		croc_vm_pushRegistry(t);
		croc_pushNull(t);
		croc_fielda(t, -2, ErrorInProgress);
		croc_popTop(t);
		errorOccurred = false;
	}
}

void throwError(CrocThread* t)
{
	assert(errorOccurred);
	auto reg = croc_vm_pushRegistry(t);
	croc_field(t, reg, ErrorInProgress);
	croc_pushNull(t);
	croc_fielda(t, reg, ErrorInProgress);
	errorOccurred = false;
	croc_eh_throw(t);
}

#define CHECK_ERROR(t) do { if(errorOccurred) throwError(t); } while(false)

// =====================================================================================================================
// Global funcs

const StdlibRegisterInfo _init_info =
{
	Docstr(DFunc("init")
	R"(Initialize the entire library. You must call this before any other functions!

	\b{Bound VM:} due to the way GLFW does error handling, this library can only be initialized in one Croc VM at any
	time. Once you call this function, the VM that called it is "bound" to the library. Attempting to call this function
	again - from the same VM or from another - will throw a \link{StateError}. It is currently not possible to switch
	which VM is bound, short of calling \link{terminate} in the bound VM and then this function in another.

	\throws[StateError] in the situation described above.
	\returns a boolean indicating whether or not initialization succeeded. If \tt{false}, initialization failed and you
	should terminate your program.)"),

	"init", 0
};

word_t _init(CrocThread* t)
{
	if(boundVM != nullptr)
		croc_eh_throwStd(t, "StateError", "Attempting to re-initialize the GLFW library");

	auto ret = glfwInit();

	if(ret)
	{
		boundVM = croc_vm_getMainThread(t);
		glfwSetErrorCallback(&errorCallback);
	}

	croc_pushBool(t, ret);
	return 1;
}

const StdlibRegisterInfo _terminate_info =
{
	Docstr(DFunc("terminate")
	R"(Deinitializes the entire library. If you successfully initialized it before, you must call this at the end of
	your program.

	\b{Bound VM:} this unbinds the current VM from the library as explained in \link{init}.)"),

	"terminate", 0
};

word_t _terminate(CrocThread* t)
{
	checkVM(t);
	glfwTerminate();
	boundVM = nullptr;
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo _getVersion_info =
{
	Docstr(DFunc("getVersion")
	R"(\returns three integers: the major, minor, and release version numbers of the GLFW shared library. For example,
	if the library is version 3.0.4, this will return \tt{3, 0, 4} in that order.)"),

	"getVersion", 0
};

word_t _getVersion(CrocThread* t)
{
	// no VM check here, it's safe to call this outside init/terminate
	int major, minor, release;
	glfwGetVersion(&major, &minor, &release);
	croc_pushInt(t, major);
	croc_pushInt(t, minor);
	croc_pushInt(t, release);
	return 3;
}

const StdlibRegisterInfo _getVersionString_info =
{
	Docstr(DFunc("getVersionString")
	R"(\returns a string representing the version of the GLFW shared library.)"),

	"getVersionString", 0
};

word_t _getVersionString(CrocThread* t)
{
	// no VM check here, it's safe to call this outside init/terminate
	croc_pushString(t, glfwGetVersionString());
	return 1;
}

const StdlibRegisterInfo _loadOpenGL_info =
{
	Docstr(DFunc("loadOpenGL")
	R"(With a current context (see \link{makeContextCurrent}), creates a module named \tt{gl} and loads the OpenGL core
	API and any supported extensions into it.

	If called a second time, does nothing.

	\throws[OSException] if OpenGL could not be loaded, or if the computer does not support at least OpenGL 3.0.)"),

	"loadOpenGL", 0
};

word_t _loadOpenGL(CrocThread* t)
{
	checkVM(t);
	loadOpenGL(t, glfwGetProcAddress);
	return 0;
}

const StdlibRegisterInfo _getMonitors_info =
{
	Docstr(DFunc("getMonitors")
	R"(\returns an array of \link{Monitor} instances, one for each monitor attached to the system.)"),

	"getMonitors", 0
};

word_t _getMonitors(CrocThread* t)
{
	checkVM(t);
	int size;
	auto arr = glfwGetMonitors(&size);
	CHECK_ERROR(t);

	croc_array_new(t, size);

	for(int i = 0; i < size; i++)
	{
		pushMonitorObj(t, arr[i]);
		croc_idxai(t, -2, i);
	}

	return 1;
}

const StdlibRegisterInfo _getPrimaryMonitor_info =
{
	Docstr(DFunc("getPrimaryMonitor")
	R"(\returns an instance of \link{Monitor} which represents the system's primary monitor (usually the one with the
	taskbar/menubar/panel).)"),

	"getPrimaryMonitor", 0
};

word_t _getPrimaryMonitor(CrocThread* t)
{
	checkVM(t);
	auto ret = glfwGetPrimaryMonitor();
	CHECK_ERROR(t);
	pushMonitorObj(t, ret);
	return 1;
}

const StdlibRegisterInfo _windowHint_info =
{
	Docstr(DFunc("windowHint") DParam("hint", "int") DParam("value", "int")
	R"(Sets a window hint for the next call to \link{createWindow}. These hints retain their values until the next call
	to \tt{windowHint} or \link{defaultWindowHints}.

	The best reference for these hints is \link[http://www.glfw.org/docs/3.0.4/window.html#window_hints]{the official
	GLFW documentation}. Note that where these docs say \tt{GL_TRUE}, this library uses \tt{1}, and for \tt{GL_FALSE},
	\tt{0}.)"),

	"windowHint", 2
};

word_t _windowHint(CrocThread* t)
{
	checkVM(t);
	auto hint = croc_ex_checkIntParam(t, 1);
	auto val = croc_ex_checkIntParam(t, 2);
	glfwWindowHint(hint, val);
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo _defaultWindowHints_info =
{
	Docstr(DFunc("defaultWindowHints")
	R"(Resets all window hints (those set with \link{windowHint}) to their default values.)"),

	"defaultWindowHints", 0
};

word_t _defaultWindowHints(CrocThread* t)
{
	checkVM(t);
	glfwDefaultWindowHints();
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo _createWindow_info =
{
	Docstr(DFunc("createWindow") DParam("width", "int") DParam("height", "int") DParam("title", "string")
		DParamD("monitor", "Monitor", "null") DParamD("share", "Window", "null")
	R"(Create a new window, and a new OpenGL context associated with that window.

	\param[width] is the width in pixels of the window.
	\param[height] is the height in pixels of the window.
	\param[title] will be the window's title, shown in the title bar (if any) or in the task switcher.
	\param[monitor] is the optional monitor on which this window will be made fullscreen. If \tt{null}, the window will
		instead be windowed.

		Note that "traditional" fullscreening is not always the best option thanks to modern window managers. If you
		want your app to go full screen, at least provide an option to use a borderless window the size of the monitor.
		Your users will thank you.
	\param[share] is an existing window with whom this new window will share OpenGL resources. If \tt{null}, the new
		context will not share resources.

	\returns a new \link{Window} instance.)"),

	"createWindow", 5
};

word_t _createWindow(CrocThread* t)
{
	checkVM(t);
	auto w = croc_ex_checkIntParam(t, 1);
	auto h = croc_ex_checkIntParam(t, 2);
	auto title = croc_ex_checkStringParam(t, 3);
	GLFWmonitor* monitor = nullptr;
	GLFWwindow* share = nullptr;

	if(croc_ex_optParam(t, 4, CrocType_Instance))
		monitor = Monitor_getThis(t, 4);

	if(croc_ex_optParam(t, 5, CrocType_Instance))
		share = Window_getThis(t, 5);

	auto ret = glfwCreateWindow(w, h, title, monitor, share);
	CHECK_ERROR(t);
	pushWindowObj(t, ret);
	return 1;
}

const StdlibRegisterInfo _pollEvents_info =
{
	Docstr(DFunc("pollEvents")
	R"(Sees if there are any events on the application's event queue.

	For all the window events, you must enable them per-window with \link{Window.enableEvents}. If you don't, you'll
	never get any events for them.

	\returns the first event on the queue, or nothing if there are no pending events.

	The event will be returned as an event name, followed by the window or monitor it's for, and then up to four data
	values.

	Because of the way this function returns its values, you can actually use it (without parentheses) as the container
	in a foreach loop. Your application's main loop might look something like:

\code
while(not window.shouldClose())
{
	foreach(ev, wm, a, b, c, d; glfw.pollEvents)
	{
		// switch on ev; wm contains the window or monitor, and a-d are the event values
	}

	// update window and present
}
\endcode

	The following table explains what each type of event means, and what values will follow it.

	\table
		\row
			\cell \b{Type}
			\cell \b{Description}
			\cell \b{Values}
			\cell \b{Value Description}
		\row
			\cell \b{\tt{"winpos"}}
			\cell A window was moved to a new position on the desktop.
			\cell \tt{window: Window, x: int, y: int}
			\cell \tt{window} is the window; \tt{(x, y)} is its new position on the desktop.
		\row
			\cell \b{\tt{"winsize"}}
			\cell A window was resized. This gives the new size in \em{screen pixels}, which can differ from the actual
				size of the framebufer for high-DPI displays. See the \tt{"fbsize"} event.
			\cell \tt{window: Window, w: int, h: int}
			\cell \tt{window} is the window; \tt{(w, h)} is its new size.
		\row
			\cell \b{\tt{"close"}}
			\cell The user has requested a window to close. This doesn't mean the window has been closed, it's up to you
				to decide how to respond to the user's request to close the window.
			\cell \tt{window: Window}
			\cell \tt{window} is the window that the user wants to close.
		\row
			\cell \b{\tt{"refresh"}}
			\cell The window manager has drawn over part of a window, and the window's contents must be redrawn.
			\cell \tt{window: Window}
			\cell \tt{window} is the window that needs to be redrawn.
		\row
			\cell \b{\tt{"focus"}}
			\cell A window has either gained or lost foreground focus.
			\cell \tt{window: Window, focused: bool}
			\cell \tt{window} is the window; \tt{focused} is \tt{true} for focus gained, and \tt{false} for lost.
		\row
			\cell \b{\tt{"iconify"}}
			\cell A window has been minimized or un-minimized.
			\cell \tt{window: Window, iconified: bool}
			\cell \tt{window} is the window; \tt{iconified} is \tt{true} for minimized, and \tt{false} for un-minimized.
		\row
			\cell \b{\tt{"fbsize"}}
			\cell A window was resized. This gives the new size in \em{framebuffer pixels}, which  can differ from the
				window's screen size for high-DPI displays.
			\cell \tt{window: Window, w: int, h: int}
			\cell \tt{window} is the window; \tt{(w, h)} is its new framebuffer size.
		\row
			\cell \b{\tt{"mousebutton"}}
			\cell A mouse button was either pressed or released.
			\cell \tt{window: Window, button: int, action: string, mods: int}
			\cell \tt{window} is the window; \tt{button} is the mouse button (0-7); \tt{action} is either \tt{"press"}
				or \tt{"release"}; and \tt{mods} is a bitfield of the modifier keys that were pressed at the time.
		\row
			\cell \b{\tt{"curpos"}}
			\cell The mouse cursor moved to a new position.
			\cell \tt{window: Window, x: float, y: float}
			\cell \tt{window} is the window; \tt{(x, y)} are the \em{floating point} coordinates of the cursor, relative
				to the top-left of \tt{window}'s client area. If the cursor is above or to the left of the window, the
				coordinates can be negative, and if it's to the right or below the window, they can be larger than the
				window size.
		\row
			\cell \b{\tt{"curenter"}}
			\cell The mouse cursor has either entered or left a window.
			\cell \tt{window: Window, entered: bool}
			\cell \tt{window} is the window; \tt{entered} is \tt{true} if the cursor entered the window, and \tt{false}
				if it left the window.
		\row
			\cell \b{\tt{"scroll"}}
			\cell The mouse scroll wheel or scroll ball moved.
			\cell \tt{window: Window, x: float, y: float}
			\cell \tt{window} is the window; \tt{x} is the change in the x scroll axis (usually only applicable to
				scroll balls); \tt{y} is the change in the y scroll axis (most scroll wheels).
		\row
			\cell \b{\tt{"key"}}
			\cell A keyboard key was pressed, repeated, or released. Key repeat uses the user's OS settings. All
				non-modifier keys will repeat, but if you don't care about repeats, you can just ignore them.
			\cell \tt{window: Window, key: int, scancode: int, action: string, mods: int}
			\cell \tt{window} is the window; \tt{key} is one of the \tt{glfw.KEY_*} enumeration values; \tt{scancode} is
				the raw keyboard scancode of the key; \tt{action} is one of \tt{"press"}, \tt{"release"}, and
				\tt{"repeat"}; and \tt{mods} is a bitfield of the modifier keys that were pressed at the time.
		\row
			\cell \b{\tt{"char"}}
			\cell The window received a Unicode character. This isn't the same thing as a keypress since it may have
				come from an IME of some sort. Use this event to collect proper text input.
			\cell \tt{window: Window, ch: string}
			\cell \tt{window} is the window; \tt{ch} is the character that was input.
		\row
			\cell \b{\tt{"monconnect"}}
			\cell A monitor was connected to or disconnected from the system.
			\cell \tt{monitor: Monitor, connected: bool}
			\cell \tt{monitor} is the monitor; \tt{connected} is \tt{true} for connected, \tt{false} for diseconnected.
	\endtable)"),

	"pollEvents", 1 // 1 so it can be used as an "opApply"
};

word_t _pollEvents(CrocThread* t)
{
	checkVM(t);

	if(queueSize == 0)
	{
		glfwPollEvents();
		CHECK_ERROR(t);
	}

	if(queueSize > 0)
		return pushEvent(t);

	return 0;
}

const StdlibRegisterInfo _waitEvents_info =
{
	Docstr(DFunc("waitEvents")
	R"(Similar to \link{pollEvents}, except this will wait for an event to occur if there is none on the application's
	event queue.

	Whereas \link{pollEvents} is better suited for realtime applications (like games), this function is better for
	event-driven applications, like editors and such. Typically these applications don't need to render a new screen
	every frame, so they can just idle waiting for a \tt{"refresh"} event or user input.

	In this case the application's main loop will look more like this:

\code
while(not window.shouldClose())
{
	local ev, wm, a, b, c, d = glfw.waitEvents()
	// switch on ev here; present only when needed
}
\endcode

	\returns an event as specified in the docs for \link{pollEvents}.)"),

	"waitEvents", 0
};

word_t _waitEvents(CrocThread* t)
{
	checkVM(t);

	while(queueSize == 0)
	{
		glfwWaitEvents();
		CHECK_ERROR(t);
	}

	return pushEvent(t);
}

const StdlibRegisterInfo _joystickPresent_info =
{
	Docstr(DFunc("joystickPresent") DParam("joy", "int")
	R"(Sees if a joystick is connected.

	\param[joy] is the index of the joystick to check, in the range 0 to 15 inclusive.
	\returns a boolean indicating whether or not a joystick is present at that index.)"),

	"joystickPresent", 1
};

word_t _joystickPresent(CrocThread* t)
{
	checkVM(t);
	auto joy = croc_ex_checkIntParam(t, 1);
	croc_pushBool(t, glfwJoystickPresent(joy));
	CHECK_ERROR(t);
	return 1;
}

const StdlibRegisterInfo _getJoystickAxes_info =
{
	Docstr(DFunc("getJoystickAxes") DParam("joy", "int") DParam("axes", "array")
	R"(Gets the values of all the axes of a joystick.

	\param[joy] is the index of the joystick to check, in the range 0 to 15 inclusive.
	\param[axes] is the array where the values will be stored. \tt{axes} will be resized to the number of axes and will
		be filled with floats.

	\returns \tt{axes} for convenience.)"),

	"getJoystickAxes", 2
};

word_t _getJoystickAxes(CrocThread* t)
{
	checkVM(t);
	auto joy = croc_ex_checkIntParam(t, 1);
	croc_ex_checkParam(t, 2, CrocType_Array);
	int size;
	auto axes = glfwGetJoystickAxes(joy, &size);
	CHECK_ERROR(t);
	croc_lenai(t, 2, size);

	for(int i = 0; i < size; i++)
	{
		croc_pushFloat(t, axes[i]);
		croc_idxai(t, 2, i);
	}

	croc_dup(t, 2);
	return 1;
}

const StdlibRegisterInfo _getJoystickButtons_info =
{
	Docstr(DFunc("getJoystickButtons") DParam("joy", "int") DParam("buttons", "array")
	R"(Gets the state of all the buttons of a joystick.

	\param[joy] is the index of the joystick to check, in the range 0 to 15 inclusive.
	\param[buttons] is the array where the values will be stored. \tt{buttons} will be resized to the number of buttons
		and will be filled with bools.

	\returns \tt{buttons} for convenience.)"),

	"getJoystickButtons", 2
};

word_t _getJoystickButtons(CrocThread* t)
{
	checkVM(t);
	auto joy = croc_ex_checkIntParam(t, 1);
	croc_ex_checkParam(t, 2, CrocType_Array);
	int size;
	auto buttons = glfwGetJoystickButtons(joy, &size);
	CHECK_ERROR(t);
	croc_lenai(t, 2, size);

	for(int i = 0; i < size; i++)
	{
		croc_pushBool(t, buttons[i]);
		croc_idxai(t, 2, i);
	}

	croc_dup(t, 2);
	return 1;
}

const StdlibRegisterInfo _getJoystickName_info =
{
	Docstr(DFunc("getJoystickName") DParam("joy", "int")
	R"(Gets a nice name of a joystick.

	\param[joy] is the index of the joystick to check, in the range 0 to 15 inclusive.
	\returns its name.)"),

	"getJoystickName", 1
};

word_t _getJoystickName(CrocThread* t)
{
	checkVM(t);
	auto joy = croc_ex_checkIntParam(t, 1);
	croc_pushString(t, glfwGetJoystickName(joy));
	CHECK_ERROR(t);
	return 1;
}

const StdlibRegisterInfo _makeContextCurrent_info =
{
	Docstr(DFunc("makeContextCurrent") DParam("window", "Window")
	R"(Makes a given window's OpenGL context the current one.

	OpenGL supports multiple contexts, but only one can be active ("current") at any time. You set which one is current
	with this function. You must make a context current before you can load the OpenGL API (with \link{loadOpenGL}) or
	use any of the OpenGL API functions.

	\param[window] is the window to make current.)"),

	"makeContextCurrent", 1
};

word_t _makeContextCurrent(CrocThread* t)
{
	checkVM(t);
	croc_ex_checkParam(t, 1, CrocType_Instance);
	glfwMakeContextCurrent(Window_getThis(t, 1));
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo _getCurrentContext_info =
{
	Docstr(DFunc("getCurrentContext")
	R"(\returns the \tt{Window} object whose context is the currently-selected one.)"),

	"getCurrentContext", 0
};

word_t _getCurrentContext(CrocThread* t)
{
	checkVM(t);
	auto ret = glfwGetCurrentContext();
	CHECK_ERROR(t);
	pushWindowObj(t, ret);
	return 1;
}

const StdlibRegisterInfo _swapInterval_info =
{
	Docstr(DFunc("swapInterval") DParam("interval", "int")
	R"(Sets the swap interval for the current context, which is the number of screen updates to wait before swapping a
	window's buffer, also known as "vertical sync" or "vsync."

	\param[interval] is the number of frames to wait before swapping. 0 means no vsync, 1 means normal vsync, and so on.
		Can be negative on platforms that support the \tt{WGL_EXT_swap_control_tear} or \tt{GLX_EXT_swap_control_tear}
		context extensions, which can be tested for with \link{extensionSupported}.)"),

	"swapInterval", 1
};

word_t _swapInterval(CrocThread* t)
{
	checkVM(t);
	glfwSwapInterval(croc_ex_checkIntParam(t, 1));
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo _extensionSupported_info =
{
	Docstr(DFunc("extensionSupported") DParam("name", "string")
	R"(Tests if an OpenGL or platform-specific context extension is supported.

	\param[name] is the name of the extension to query.
	\returns a boolean indicating whether or not it is supported.)"),

	"extensionSupported", 1
};

word_t _extensionSupported(CrocThread* t)
{
	checkVM(t);
	auto name = croc_ex_checkStringParam(t, 1);
	croc_pushBool(t, glfwExtensionSupported(name));
	CHECK_ERROR(t);
	return 1;
}

const StdlibRegisterInfo _setMonitorEventsEnabled_info =
{
	Docstr(DFunc("setMonitorEventsEnabled") DParam("enable", "bool")
	R"(Enables or disables the \tt{"monconnect"} events. By default they are disabled, but if you enable them you will
	receive them through \link{pollEvents} and \link{waitEvents}.

	\param[enable] is \tt{true} to enable these events, and \tt{false} to disable them.)"),

	"setMonitorEventsEnabled", 1
};

word_t _setMonitorEventsEnabled(CrocThread* t)
{
	checkVM(t);

	if(croc_ex_checkBoolParam(t, 1))
		glfwSetMonitorCallback(&monitorCallback);
	else
		glfwSetMonitorCallback(nullptr);

	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo _getTime_info =
{
	Docstr(DFunc("getTime")
	R"(\returns the number of seconds elapsed since GLFW was initialized as a float, unless the time has been set with
	\link{setTime}. This is a very high-resolution timer.)"),

	"getTime", 0
};

word_t _getTime(CrocThread* t)
{
	croc_pushFloat(t, glfwGetTime());
	return 1;
}

const StdlibRegisterInfo _setTime_info =
{
	Docstr(DFunc("setTime") DParam("time", "int|float")
	R"(Sets the GLFW time to \tt{time}, in seconds. It then continues to tick up from this value.)"),

	"setTime", 1
};

word_t _setTime(CrocThread* t)
{
	glfwSetTime(croc_ex_checkNumParam(t, 1));
	return 0;
}

const StdlibRegister _globalFuncs[] =
{
	_DListItem(_init),
	_DListItem(_terminate),
	_DListItem(_getVersion),
	_DListItem(_getVersionString),
	_DListItem(_loadOpenGL),
	_DListItem(_getMonitors),
	_DListItem(_getPrimaryMonitor),
	_DListItem(_windowHint),
	_DListItem(_defaultWindowHints),
	_DListItem(_createWindow),
	_DListItem(_pollEvents),
	_DListItem(_waitEvents),
	_DListItem(_joystickPresent),
	_DListItem(_getJoystickAxes),
	_DListItem(_getJoystickButtons),
	_DListItem(_getJoystickName),
	_DListItem(_makeContextCurrent),
	_DListItem(_getCurrentContext),
	_DListItem(_swapInterval),
	_DListItem(_extensionSupported),
	_DListItem(_setMonitorEventsEnabled),
	_DListItem(_getTime),
	_DListItem(_setTime),
	_DListEnd
};

// =====================================================================================================================
// Monitor class

#ifdef CROC_BUILTIN_DOCS
const char* MonitorDocs = DClass("Monitor")
R"(Represents a monitor attached to the system. You don't create instances of this class, instances are given to you by
the \link{getMonitors} and \link{getPrimaryMonitor} functions.)";
#endif

const StdlibRegisterInfo Monitor_constructor_info =
{
	Docstr(DFunc("constructor") DParam("handle", "nativeobj")
	R"(Constructor for use internally.)"),

	"constructor", 1
};

word_t Monitor_constructor(CrocThread* t)
{
	checkVM(t);
	// Check for double-init
	croc_hfield(t, 0, Monitor_handle);
	if(!croc_isNull(t, -1))
		croc_eh_throwStd(t, "StateError", "Attempting to call constructor on already-initialized instance");
	croc_popTop(t);

	// Set handle
	croc_ex_checkParam(t, 1, CrocType_Nativeobj);
	croc_dup(t, 1);
	croc_hfielda(t, 0, Monitor_handle);

	// Insert this instance into the handle map
	croc_ex_pushRegistryVar(t, HandleMap);
	croc_dup(t, 1);
	croc_dup(t, 0);
	croc_idxa(t, -3);

	return 0;
}

const StdlibRegisterInfo Monitor_getPos_info =
{
	Docstr(DFunc("getPos")
	R"(\returns the position of the top-left corner of this monitor with respect to the "virtual desktop" that spans
	across all monitors. The position is returned as two integers, x and y.)"),

	"getPos", 0
};

word_t Monitor_getPos(CrocThread* t)
{
	checkVM(t);
	auto self = Monitor_getThis(t);
	int x, y;
	glfwGetMonitorPos(self, &x, &y);
	CHECK_ERROR(t);
	croc_pushInt(t, x);
	croc_pushInt(t, y);
	return 2;
}

const StdlibRegisterInfo Monitor_getPhysicalSize_info =
{
	Docstr(DFunc("getPhysicalSize")
	R"(\returns the width and height of this monitor in millimeters as two integers, x and y.

	The size returned from this function may be inaccurate due to faulty drivers or EDID data.)"),

	"getPhysicalSize", 0
};

word_t Monitor_getPhysicalSize(CrocThread* t)
{
	checkVM(t);
	auto self = Monitor_getThis(t);
	int w, h;
	glfwGetMonitorPhysicalSize(self, &w, &h);
	CHECK_ERROR(t);
	croc_pushInt(t, w);
	croc_pushInt(t, h);
	return 2;
}

const StdlibRegisterInfo Monitor_getName_info =
{
	Docstr(DFunc("getName")
	R"(\returns the name of this monitor.)"),

	"getName", 0
};

word_t Monitor_getName(CrocThread* t)
{
	checkVM(t);
	auto self = Monitor_getThis(t);
	auto ret = glfwGetMonitorName(self);
	CHECK_ERROR(t);
	croc_pushString(t, ret);
	return 1;
}

const StdlibRegisterInfo Monitor_getVideoModes_info =
{
	Docstr(DFunc("getVideoModes")
	R"(\returns an array of supported fullscreen video modes.

	Each video mode is a table containing the following members:
	\blist
		\li \b{\tt{width}}: pixel width of the video mode
		\li \b{\tt{height}}: pixel height of the video mode
		\li \b{\tt{redBits}}: bits for the red channel
		\li \b{\tt{greenBits}}: bits for the green channel
		\li \b{\tt{blueBits}}: bits for the blue channel
		\li \b{\tt{refreshRate}}: refresh rate in Hz (as an integer)
	\endlist)"),

	"getVideoModes", 0
};

word_t Monitor_getVideoModes(CrocThread* t)
{
	checkVM(t);
	auto self = Monitor_getThis(t);

	int size;
	auto arr = glfwGetVideoModes(self, &size);
	CHECK_ERROR(t);

	if(arr == nullptr)
		croc_pushNull(t);
	else
	{
		croc_array_new(t, size);

		for(int i = 0; i < size; i++)
		{
			pushVideoMode(t, &arr[i]);
			croc_idxai(t, -2, i);
		}
	}

	return 1;
}

const StdlibRegisterInfo Monitor_getVideoMode_info =
{
	Docstr(DFunc("getVideoMode")
	R"(\returns the monitor's current video mode as a table as described in \link{getVideoModes}.)"),

	"getVideoMode", 0
};

word_t Monitor_getVideoMode(CrocThread* t)
{
	checkVM(t);
	auto self = Monitor_getThis(t);
	auto ret = glfwGetVideoMode(self);
	CHECK_ERROR(t);
	pushVideoMode(t, ret);
	return 1;
}

const StdlibRegisterInfo Monitor_setGamma_info =
{
	Docstr(DFunc("setGamma") DParam("gamma", "int|float")
	R"(Generates a gamma ramp using \tt{gamma} as an exponent and sets the monitor's gamma to the new ramp. A gamma of
	1.0 is the default; higher values make things brighter and lower values make things darker.)"),

	"setGamma", 1
};

word_t Monitor_setGamma(CrocThread* t)
{
	checkVM(t);
	auto self = Monitor_getThis(t);
	auto gamma = croc_ex_checkNumParam(t, 1);
	glfwSetGamma(self, gamma);
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Monitor_getGammaRamp_info =
{
	Docstr(DFunc("getGammaRamp")
	R"(\returns three arrays of integers, all the same length, which represent the monitor's current red, green, and
	blue gamma ramps.)"),

	"getGammaRamp", 0
};

word_t Monitor_getGammaRamp(CrocThread* t)
{
	checkVM(t);
	auto self = Monitor_getThis(t);

	auto ret = glfwGetGammaRamp(self);
	CHECK_ERROR(t);
	croc_array_new(t, ret->size);
	croc_array_new(t, ret->size);
	croc_array_new(t, ret->size);

	for(unsigned int i = 0; i < ret->size; i++)
	{
		croc_pushInt(t, ret->red[i]);
		croc_idxai(t, -4, i);
		croc_pushInt(t, ret->green[i]);
		croc_idxai(t, -3, i);
		croc_pushInt(t, ret->blue[i]);
		croc_idxai(t, -2, i);
	}

	return 3;
}

const StdlibRegisterInfo Monitor_setGammaRamp_info =
{
	Docstr(DFunc("setGammaRamp") DParam("r", "array") DParam("g", "array") DParam("b", "array")
	R"(Takes the red, green, and blue gamma ramps as arrays of integers and sets the monitor's gamma to these new
	ramps.

	All three ramp arrays must be the same length, and they have a maximum length of 256 elements.

	\throws[ValueError] if \tt{r}, \tt{g}, and \tt{b} are not all the same length, or if they are 0 elements or more
		than 256 elements.
	\throws[TypeError] if any of the values in the gamma ramps are not integers.)"),

	"setGammaRamp", 3
};

word_t Monitor_setGammaRamp(CrocThread* t)
{
	checkVM(t);
	auto self = Monitor_getThis(t);
	croc_ex_checkParam(t, 1, CrocType_Array);
	croc_ex_checkParam(t, 2, CrocType_Array);
	croc_ex_checkParam(t, 3, CrocType_Array);

	auto rlen = croc_len(t, 1);
	auto glen = croc_len(t, 2);
	auto blen = croc_len(t, 3);

	if(rlen != glen || glen != blen)
		croc_eh_throwStd(t, "ValueError", "All three ramps must be the same length");
	else if(rlen == 0 || rlen > 256)
		croc_eh_throwStd(t, "ValueError", "Invalid ramp length %" CROC_INTEGER_FORMAT, rlen);

	unsigned short r[256], g[256], b[256];
	GLFWgammaramp ramp;
	ramp.size = rlen;
	ramp.red = r;
	ramp.green = g;
	ramp.blue = b;

	for(int i = 0; i < rlen; i++)
	{
		croc_idxi(t, 1, i);
		croc_idxi(t, 2, i);
		croc_idxi(t, 3, i);

		if(!croc_isInt(t, -3) || !croc_isInt(t, -2) || !croc_isInt(t, -1))
			croc_eh_throwStd(t, "TypeError", "All ramp values must be integers");

		r[i] = croc_getInt(t, -3);
		g[i] = croc_getInt(t, -2);
		b[i] = croc_getInt(t, -1);

		croc_pop(t, 3);
	}

	glfwSetGammaRamp(self, &ramp);
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegister Monitor_methods[] =
{
	_DListItem(Monitor_constructor),
	_DListItem(Monitor_getPos),
	_DListItem(Monitor_getPhysicalSize),
	_DListItem(Monitor_getName),
	_DListItem(Monitor_getVideoModes),
	_DListItem(Monitor_getVideoMode),
	_DListItem(Monitor_setGamma),
	_DListItem(Monitor_getGammaRamp),
	_DListItem(Monitor_setGammaRamp),
	_DListEnd
};

// =====================================================================================================================
// Window class

#ifdef CROC_BUILTIN_DOCS
const char* WindowDocs = DClass("Window")
R"(Represents a window and its associated OpenGL context. You don't create instances of this class, instances are given
to you by the \link{createWindow} function.)";
#endif

const StdlibRegisterInfo Window_constructor_info =
{
	Docstr(DFunc("constructor") DParam("handle", "nativeobj")
	R"(Constructor for use internally.)"),

	"constructor", 1
};

word_t Window_constructor(CrocThread* t)
{
	checkVM(t);
	// Check for double-init
	croc_hfield(t, 0, Window_handle);
	if(!croc_isNull(t, -1))
		croc_eh_throwStd(t, "StateError", "Attempting to call constructor on already-initialized Window");
	croc_popTop(t);

	// Set handle
	croc_ex_checkParam(t, 1, CrocType_Nativeobj);
	croc_dup(t, 1);
	croc_hfielda(t, 0, Window_handle);

	// Insert this instance into the handle map
	croc_ex_pushRegistryVar(t, HandleMap);
	croc_dup(t, 1);
	croc_dup(t, 0);
	croc_idxa(t, -3);

	return 0;
}

const StdlibRegisterInfo Window_destroy_info =
{
	Docstr(DFunc("destroy")
	R"(Destroys this window and its associated OpenGL context. No more events will be generated for this window.

	\throws[StateError] if you call this method more than once.)"),

	"destroy", 0
};

word_t Window_destroy(CrocThread* t)
{
	checkVM(t);
	// Check for double-destroy
	croc_hfield(t, 0, Window_handle);

	if(!croc_isNativeobj(t, -1))
		croc_eh_throwStd(t, "StateError", "Attempting to destroy a Window that is either uninitialized or already destroyed");

	// Destroy
	glfwDestroyWindow(cast(GLFWwindow*)croc_getNativeobj(t, -1));
	CHECK_ERROR(t);
	croc_popTop(t);

	// Clear handle
	croc_pushNull(t);
	croc_hfielda(t, 0, Window_handle);

	return 0;
}

const StdlibRegisterInfo Window_shouldClose_info =
{
	Docstr(DFunc("shouldClose")
	R"(\returns a bool indicating whether this window should close. This flag is set to true when the user tries to
	close the window, and can also be set to \tt{true} or \tt{false} with \link{setShouldClose}.)"),

	"shouldClose", 0
};

word_t Window_shouldClose(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	croc_pushBool(t, glfwWindowShouldClose(self));
	CHECK_ERROR(t);
	return 1;
}

const StdlibRegisterInfo Window_setShouldClose_info =
{
	Docstr(DFunc("setShouldClose") DParam("should", "bool")
	R"(Sets the "should close" flag on this window to \tt{should}.)"),

	"setShouldClose", 1
};

word_t Window_setShouldClose(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	glfwSetWindowShouldClose(self, croc_ex_checkBoolParam(t, 1));
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_setTitle_info =
{
	Docstr(DFunc("setTitle") DParam("title", "string")
	R"(Sets this window's title to \tt{title}.)"),

	"setTitle", 1
};

word_t Window_setTitle(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	auto title = croc_ex_checkStringParam(t, 1);
	glfwSetWindowTitle(self, title);
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_getPos_info =
{
	Docstr(DFunc("getPos")
	R"(\returns the desktop position of this window as two ints, x and y.)"),

	"getPos", 0
};

word_t Window_getPos(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	int x, y;
	glfwGetWindowPos(self, &x, &y);
	CHECK_ERROR(t);
	croc_pushInt(t, x);
	croc_pushInt(t, y);
	return 2;
}

const StdlibRegisterInfo Window_setPos_info =
{
	Docstr(DFunc("setPos") DParam("x", "int") DParam("y", "int")
	R"(Sets this window's desktop position to \tt{(x, y)}.)"),

	"setPos", 2
};

word_t Window_setPos(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	auto x = croc_ex_checkIntParam(t, 1);
	auto y = croc_ex_checkIntParam(t, 2);
	glfwSetWindowPos(self, x, y);
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_getSize_info =
{
	Docstr(DFunc("getSize")
	R"(\returns the size of this window in \em{screen pixels} as two integers, width and height.

	The screen size can differ from the actual size of the framebufer for high-DPI displays. See
	\link{getFramebufferSize}.)"),

	"getSize", 0
};

word_t Window_getSize(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	int w, h;
	glfwGetWindowSize(self, &w, &h);
	CHECK_ERROR(t);
	croc_pushInt(t, w);
	croc_pushInt(t, h);
	return 2;
}

const StdlibRegisterInfo Window_setSize_info =
{
	Docstr(DFunc("setSize") DParam("w", "int") DParam("h", "int")
	R"(Sets the window's screen size to \tt{(w, h)}.)"),

	"setSize", 2
};

word_t Window_setSize(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	auto w = croc_ex_checkIntParam(t, 1);
	auto h = croc_ex_checkIntParam(t, 2);
	glfwSetWindowSize(self, w, h);
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_getFramebufferSize_info =
{
	Docstr(DFunc("getFramebufferSize")
	R"(\returns the size of the window's framebuffer as two integers, width and height.

	The framebuffer size can differ from the window's screen size for high-DPI displays.)"),

	"getFramebufferSize", 0
};

word_t Window_getFramebufferSize(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	int w, h;
	glfwGetFramebufferSize(self, &w, &h);
	CHECK_ERROR(t);
	croc_pushInt(t, w);
	croc_pushInt(t, h);
	return 2;
}

const StdlibRegisterInfo Window_iconify_info =
{
	Docstr(DFunc("iconify")
	R"(Minimizes this window.)"),

	"iconify", 0
};

word_t Window_iconify(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	glfwIconifyWindow(self);
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_restore_info =
{
	Docstr(DFunc("restore")
	R"(Un-minimizes this window.)"),

	"restore", 0
};

word_t Window_restore(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	glfwRestoreWindow(self);
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_show_info =
{
	Docstr(DFunc("show")
	R"(Makes this window visible.)"),

	"show", 0
};

word_t Window_show(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	glfwShowWindow(self);
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_hide_info =
{
	Docstr(DFunc("hide")
	R"(Makes this window invisible. It doesn't minimize it, it really makes it disappear from view entirely.)"),

	"hide", 0
};

word_t Window_hide(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	glfwHideWindow(self);
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_swapBuffers_info =
{
	Docstr(DFunc("swapBuffers")
	R"(After drawing to the framebuffer through OpenGL, you must call this method to display anything.)"),

	"swapBuffers", 0
};

word_t Window_swapBuffers(CrocThread* t)
{
	checkVM(t);
	glfwSwapBuffers(Window_getThis(t));
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_getMonitor_info =
{
	Docstr(DFunc("getMonitor")
	R"(\returns the \link{Monitor} object that this window is fullscreened on, or \tt{null} if this window is in
	windowed mode.)"),

	"getMonitor", 0
};

word_t Window_getMonitor(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	auto ret = glfwGetWindowMonitor(self);
	CHECK_ERROR(t);

	if(ret == nullptr)
		croc_pushNull(t);
	else
		pushMonitorObj(t, ret);
	return 1;
}

const StdlibRegisterInfo Window_setCursorMode_info =
{
	Docstr(DFunc("setCursorMode") DParam("mode", "string")
	R"(Sets this window's cursor handling mode.

	\param[mode] must be one of the following values:
	\blist
		\li \b{\tt{"normal"}}: the cursor appears over this window as usual.
		\li \b{\tt{"hidden"}}: the cursor will be invisible when over this window, but it can still be moved freely.
		\li \b{\tt{"disabled"}}: the cursor will be hidden and also disallowed from leaving this window. This is useful
			for "mouselook" camera controls and the like.
	\endlist)"),

	"setCursorMode", 1
};

word_t Window_setCursorMode(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	auto mode = checkCrocstrParam(t, 1);

	if(mode == ATODA("normal"))
		glfwSetInputMode(self, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
	else if(mode == ATODA("hidden"))
		glfwSetInputMode(self, GLFW_CURSOR, GLFW_CURSOR_HIDDEN);
	else if(mode == ATODA("disabled"))
		glfwSetInputMode(self, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
	else
		croc_eh_throwStd(t, "ValueError", "Mode must be one of 'normal', 'hidden', or 'disabled'");

	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_getCursorMode_info =
{
	Docstr(DFunc("getCursorMode")
	R"(\returns this window's cursor mode as a string, as described in \link{setCursorMode}.)"),

	"getCursorMode", 0
};

word_t Window_getCursorMode(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);

	switch(glfwGetInputMode(self, GLFW_CURSOR))
	{
		case GLFW_CURSOR_NORMAL:   croc_pushString(t, "normal");   break;
		case GLFW_CURSOR_HIDDEN:   croc_pushString(t, "hidden");   break;
		case GLFW_CURSOR_DISABLED: croc_pushString(t, "disabled"); break;
		default: assert(false);
	}

	CHECK_ERROR(t);
	return 1;
}

const StdlibRegisterInfo Window_setStickyKeys_info =
{
	Docstr(DFunc("setStickyKeys") DParam("enable", "bool")
	R"(Sets whether or not this window uses "sticky keys".

	If sticky keys are enabled, calls to \link{getKey} will return \tt{true} even if the key in question has been
	released since it was last pressed. This is useful if you only care \em{if} keys have been pressed, but don't care
	about \em{when}.)"),

	"setStickyKeys", 1
};

word_t Window_setStickyKeys(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	glfwSetInputMode(self, GLFW_STICKY_KEYS, croc_ex_checkBoolParam(t, 1));
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_getStickyKeys_info =
{
	Docstr(DFunc("getStickyKeys")
	R"(\returns this window's sticky keys mode. See \link{setStickyKeys}.)"),

	"getStickyKeys", 0
};

word_t Window_getStickyKeys(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	croc_pushBool(t, glfwGetInputMode(self, GLFW_STICKY_KEYS));
	CHECK_ERROR(t);
	return 1;
}

const StdlibRegisterInfo Window_setStickyMouseButtons_info =
{
	Docstr(DFunc("setStickyMouseButtons") DParam("enable", "bool")
	R"(Sets whether or not this window uses "sticky mouse buttons".

	This is the same as \link{setStickyKeys} except for mouse buttons and the \link{getMouseButton} method.)"),

	"setStickyMouseButtons", 1
};

word_t Window_setStickyMouseButtons(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	glfwSetInputMode(self, GLFW_STICKY_MOUSE_BUTTONS, croc_ex_checkBoolParam(t, 1));
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_getStickyMouseButtons_info =
{
	Docstr(DFunc("getStickyMouseButtons")
	R"(\returns whis window's sticky mouse buttons mode. See \link{setStickyMouseButtons}.)"),

	"getStickyMouseButtons", 0
};

word_t Window_getStickyMouseButtons(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	croc_pushBool(t, glfwGetInputMode(self, GLFW_STICKY_MOUSE_BUTTONS));
	CHECK_ERROR(t);
	return 1;
}

const StdlibRegisterInfo Window_getKey_info =
{
	Docstr(DFunc("getKey") DParam("key", "int")
	R"(Checks whether a key is currently being held down in this window.

	\param[key] should be one of the key enumerations.
	\returns \tt{true} if the key is being held down and \tt{false} if not.)"),

	"getKey", 1
};

word_t Window_getKey(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	croc_pushBool(t, glfwGetKey(self, croc_ex_checkIntParam(t, 1)) == GLFW_PRESS ? true : false);
	CHECK_ERROR(t);
	return 1;
}

const StdlibRegisterInfo Window_getMouseButton_info =
{
	Docstr(DFunc("getMouseButton") DParam("button", "int")
	R"(Checks whether a mouse button is currently being held down in this window.

	\param[button] should be a mouse button in the range 0 to 7 inclusive.
	\returns \tt{true} if the button is being held down and \tt{false} if not.)"),

	"getMouseButton", 1
};

word_t Window_getMouseButton(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	croc_pushBool(t, glfwGetMouseButton(self, croc_ex_checkIntParam(t, 1)) == GLFW_PRESS ? true : false);
	CHECK_ERROR(t);
	return 1;
}

const StdlibRegisterInfo Window_getCursorPos_info =
{
	Docstr(DFunc("getCursorPos")
	R"(\returns the position of the cursor relative to the top-left corner of this window as two doubles, x and y.)"),

	"getCursorPos", 0
};

word_t Window_getCursorPos(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	double x, y;
	glfwGetCursorPos(self, &x, &y);
	CHECK_ERROR(t);
	croc_pushFloat(t, x);
	croc_pushFloat(t, y);
	return 2;
}

const StdlibRegisterInfo Window_setCursorPos_info =
{
	Docstr(DFunc("setCursorPos") DParam("x", "int|float") DParam("y", "int|float")
	R"(Moves the cursor to the screen position \tt{(x, y)} relative to the top-left corner of this window.)"),

	"setCursorPos", 2
};

word_t Window_setCursorPos(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	auto x = croc_ex_checkNumParam(t, 1);
	auto y = croc_ex_checkNumParam(t, 2);
	glfwSetCursorPos(self, x, y);
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_setClipboardString_info =
{
	Docstr(DFunc("setClipboardString") DParam("data", "string")
	R"(Puts the string \tt{data} on the OS clipboard.

	This function can only be called from the main thread of your host application.)"),

	"setClipboardString", 1
};

word_t Window_setClipboardString(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	glfwSetClipboardString(self, croc_ex_checkStringParam(t, 1));
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_getClipboardString_info =
{
	Docstr(DFunc("getClipboardString")
	R"(\returns the contents of the clipboard as a string, or \tt{null} if the contents are not a string.

	This method does \em{not} throw any exceptions, unlike many others.)"),

	"getClipboardString", 0
};

word_t Window_getClipboardString(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	auto clip = glfwGetClipboardString(self);
	clearError(t);

	if(clip == nullptr)
		croc_pushNull(t);
	else
		croc_pushString(t, clip);
	return 1;
}

const StdlibRegisterInfo Window_getAttrib_info =
{
	Docstr(DFunc("getAttrib") DParam("attrib", "int")
	R"(Gets one of the window's attributes.

	The best reference for these attributes is the \link[http://www.glfw.org/docs/3.0.4/window.html#window_attribs]{
	official docs}. Note that where these docs say \tt{GL_TRUE}, this library uses \tt{1}, and for \tt{GL_FALSE},
	\tt{0}.)"),

	"getAttrib", 1
};

word_t Window_getAttrib(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	croc_pushInt(t, glfwGetWindowAttrib(self, croc_ex_checkIntParam(t, 1)));
	CHECK_ERROR(t);
	return 1;
}

const StdlibRegisterInfo Window_enableEvents_info =
{
	Docstr(DFunc("enableEvents") DVararg
	R"(Enables any number of events on this window by name.

	After creation, windows will not produce any events until you enable them with this method. You enable them by name,
	which are listed in the docs for \link{pollEvents}. For example, if you want to receive key, mouse button, and
	cursor position events, you might call:

\code
window.enableEvents("key", "mousebutton", "curpos")
\endcode

	Now these events will be generated for this window.)"),

	"enableEvents", -1
};

word_t Window_enableEvents(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	auto stackSize = croc_getStackSize(t);

	for(uword i = 1; i < stackSize; i++)
	{
		switch(checkEventName(t, i))
		{
			case GlfwEvent::WindowPos:       glfwSetWindowPosCallback      (self, &windowPosCallback);       break;
			case GlfwEvent::WindowSize:      glfwSetWindowSizeCallback     (self, &windowSizeCallback);      break;
			case GlfwEvent::WindowClose:     glfwSetWindowCloseCallback    (self, &windowCloseCallback);     break;
			case GlfwEvent::WindowRefresh:   glfwSetWindowRefreshCallback  (self, &windowRefreshCallback);   break;
			case GlfwEvent::WindowFocus:     glfwSetWindowFocusCallback    (self, &windowFocusCallback);     break;
			case GlfwEvent::WindowIconify:   glfwSetWindowIconifyCallback  (self, &windowIconifyCallback);   break;
			case GlfwEvent::FramebufferSize: glfwSetFramebufferSizeCallback(self, &framebufferSizeCallback); break;
			case GlfwEvent::MouseButton:     glfwSetMouseButtonCallback    (self, &mouseButtonCallback);     break;
			case GlfwEvent::CursorPos:       glfwSetCursorPosCallback      (self, &cursorPosCallback);       break;
			case GlfwEvent::CursorEnter:     glfwSetCursorEnterCallback    (self, &cursorEnterCallback);     break;
			case GlfwEvent::Scroll:          glfwSetScrollCallback         (self, &scrollCallback);          break;
			case GlfwEvent::Key:             glfwSetKeyCallback            (self, &keyCallback);             break;
			case GlfwEvent::Char:            glfwSetCharCallback           (self, &charCallback);            break;
			default: assert(false);
		}

		CHECK_ERROR(t);
	}

	return 0;
}

const StdlibRegisterInfo Window_disableEvents_info =
{
	Docstr(DFunc("disableEvents") DVararg
	R"(The opposite of \link{enableEvents}. Takes any number of event names just like it.)"),

	"disableEvents", -1
};

word_t Window_disableEvents(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	auto stackSize = croc_getStackSize(t);

	for(uword i = 1; i < stackSize; i++)
	{
		switch(checkEventName(t, i))
		{
			case GlfwEvent::WindowPos:       glfwSetWindowPosCallback      (self, nullptr); break;
			case GlfwEvent::WindowSize:      glfwSetWindowSizeCallback     (self, nullptr); break;
			case GlfwEvent::WindowClose:     glfwSetWindowCloseCallback    (self, nullptr); break;
			case GlfwEvent::WindowRefresh:   glfwSetWindowRefreshCallback  (self, nullptr); break;
			case GlfwEvent::WindowFocus:     glfwSetWindowFocusCallback    (self, nullptr); break;
			case GlfwEvent::WindowIconify:   glfwSetWindowIconifyCallback  (self, nullptr); break;
			case GlfwEvent::FramebufferSize: glfwSetFramebufferSizeCallback(self, nullptr); break;
			case GlfwEvent::MouseButton:     glfwSetMouseButtonCallback    (self, nullptr); break;
			case GlfwEvent::CursorPos:       glfwSetCursorPosCallback      (self, nullptr); break;
			case GlfwEvent::CursorEnter:     glfwSetCursorEnterCallback    (self, nullptr); break;
			case GlfwEvent::Scroll:          glfwSetScrollCallback         (self, nullptr); break;
			case GlfwEvent::Key:             glfwSetKeyCallback            (self, nullptr); break;
			case GlfwEvent::Char:            glfwSetCharCallback           (self, nullptr); break;
			default: assert(false);
		}

		CHECK_ERROR(t);
	}

	return 0;
}

const StdlibRegisterInfo Window_enableAllEvents_info =
{
	Docstr(DFunc("enableAllEvents")
	R"(Enables ALL types of events for this window.)"),

	"enableAllEvents", 0
};

word_t Window_enableAllEvents(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	glfwSetWindowPosCallback      (self, &windowPosCallback);       CHECK_ERROR(t);
	glfwSetWindowSizeCallback     (self, &windowSizeCallback);      CHECK_ERROR(t);
	glfwSetWindowCloseCallback    (self, &windowCloseCallback);     CHECK_ERROR(t);
	glfwSetWindowRefreshCallback  (self, &windowRefreshCallback);   CHECK_ERROR(t);
	glfwSetWindowFocusCallback    (self, &windowFocusCallback);     CHECK_ERROR(t);
	glfwSetWindowIconifyCallback  (self, &windowIconifyCallback);   CHECK_ERROR(t);
	glfwSetFramebufferSizeCallback(self, &framebufferSizeCallback); CHECK_ERROR(t);
	glfwSetMouseButtonCallback    (self, &mouseButtonCallback);     CHECK_ERROR(t);
	glfwSetCursorPosCallback      (self, &cursorPosCallback);       CHECK_ERROR(t);
	glfwSetCursorEnterCallback    (self, &cursorEnterCallback);     CHECK_ERROR(t);
	glfwSetScrollCallback         (self, &scrollCallback);          CHECK_ERROR(t);
	glfwSetKeyCallback            (self, &keyCallback);             CHECK_ERROR(t);
	glfwSetCharCallback           (self, &charCallback);            CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo Window_disableAllEvents_info =
{
	Docstr(DFunc("disableAllEvents")
	R"(Disables ALL types of events for this window.)"),

	"disableAllEvents", 0
};

word_t Window_disableAllEvents(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	glfwSetWindowPosCallback      (self, nullptr); CHECK_ERROR(t);
	glfwSetWindowSizeCallback     (self, nullptr); CHECK_ERROR(t);
	glfwSetWindowCloseCallback    (self, nullptr); CHECK_ERROR(t);
	glfwSetWindowRefreshCallback  (self, nullptr); CHECK_ERROR(t);
	glfwSetWindowFocusCallback    (self, nullptr); CHECK_ERROR(t);
	glfwSetWindowIconifyCallback  (self, nullptr); CHECK_ERROR(t);
	glfwSetFramebufferSizeCallback(self, nullptr); CHECK_ERROR(t);
	glfwSetMouseButtonCallback    (self, nullptr); CHECK_ERROR(t);
	glfwSetCursorPosCallback      (self, nullptr); CHECK_ERROR(t);
	glfwSetCursorEnterCallback    (self, nullptr); CHECK_ERROR(t);
	glfwSetScrollCallback         (self, nullptr); CHECK_ERROR(t);
	glfwSetKeyCallback            (self, nullptr); CHECK_ERROR(t);
	glfwSetCharCallback           (self, nullptr); CHECK_ERROR(t);
	return 0;
}

const StdlibRegister Window_methods[] =
{
	_DListItem(Window_constructor),
	_DListItem(Window_destroy),
	_DListItem(Window_shouldClose),
	_DListItem(Window_setShouldClose),
	_DListItem(Window_setTitle),
	_DListItem(Window_getPos),
	_DListItem(Window_setPos),
	_DListItem(Window_getSize),
	_DListItem(Window_setSize),
	_DListItem(Window_getFramebufferSize),
	_DListItem(Window_iconify),
	_DListItem(Window_restore),
	_DListItem(Window_show),
	_DListItem(Window_hide),
	_DListItem(Window_swapBuffers),
	_DListItem(Window_getMonitor),
	_DListItem(Window_setCursorMode),
	_DListItem(Window_getCursorMode),
	_DListItem(Window_setStickyKeys),
	_DListItem(Window_getStickyKeys),
	_DListItem(Window_getStickyMouseButtons),
	_DListItem(Window_setStickyMouseButtons),
	_DListItem(Window_getKey),
	_DListItem(Window_getMouseButton),
	_DListItem(Window_getCursorPos),
	_DListItem(Window_setCursorPos),
	_DListItem(Window_setClipboardString),
	_DListItem(Window_getClipboardString),
	_DListItem(Window_getAttrib),
	_DListItem(Window_enableEvents),
	_DListItem(Window_disableEvents),
	_DListItem(Window_enableAllEvents),
	_DListItem(Window_disableAllEvents),
	_DListEnd
};

// =====================================================================================================================
// Constants

void registerConstants(CrocThread* t)
{
	// Keys
	croc_pushInt(t, GLFW_KEY_UNKNOWN);           croc_newGlobal(t, "KEY_UNKNOWN");
	croc_pushInt(t, GLFW_KEY_SPACE);             croc_newGlobal(t, "KEY_SPACE");
	croc_pushInt(t, GLFW_KEY_APOSTROPHE);        croc_newGlobal(t, "KEY_APOSTROPHE");
	croc_pushInt(t, GLFW_KEY_COMMA);             croc_newGlobal(t, "KEY_COMMA");
	croc_pushInt(t, GLFW_KEY_MINUS);             croc_newGlobal(t, "KEY_MINUS");
	croc_pushInt(t, GLFW_KEY_PERIOD);            croc_newGlobal(t, "KEY_PERIOD");
	croc_pushInt(t, GLFW_KEY_SLASH);             croc_newGlobal(t, "KEY_SLASH");
	croc_pushInt(t, GLFW_KEY_0);                 croc_newGlobal(t, "KEY_0");
	croc_pushInt(t, GLFW_KEY_1);                 croc_newGlobal(t, "KEY_1");
	croc_pushInt(t, GLFW_KEY_2);                 croc_newGlobal(t, "KEY_2");
	croc_pushInt(t, GLFW_KEY_3);                 croc_newGlobal(t, "KEY_3");
	croc_pushInt(t, GLFW_KEY_4);                 croc_newGlobal(t, "KEY_4");
	croc_pushInt(t, GLFW_KEY_5);                 croc_newGlobal(t, "KEY_5");
	croc_pushInt(t, GLFW_KEY_6);                 croc_newGlobal(t, "KEY_6");
	croc_pushInt(t, GLFW_KEY_7);                 croc_newGlobal(t, "KEY_7");
	croc_pushInt(t, GLFW_KEY_8);                 croc_newGlobal(t, "KEY_8");
	croc_pushInt(t, GLFW_KEY_9);                 croc_newGlobal(t, "KEY_9");
	croc_pushInt(t, GLFW_KEY_SEMICOLON);         croc_newGlobal(t, "KEY_SEMICOLON");
	croc_pushInt(t, GLFW_KEY_EQUAL);             croc_newGlobal(t, "KEY_EQUAL");
	croc_pushInt(t, GLFW_KEY_A);                 croc_newGlobal(t, "KEY_A");
	croc_pushInt(t, GLFW_KEY_B);                 croc_newGlobal(t, "KEY_B");
	croc_pushInt(t, GLFW_KEY_C);                 croc_newGlobal(t, "KEY_C");
	croc_pushInt(t, GLFW_KEY_D);                 croc_newGlobal(t, "KEY_D");
	croc_pushInt(t, GLFW_KEY_E);                 croc_newGlobal(t, "KEY_E");
	croc_pushInt(t, GLFW_KEY_F);                 croc_newGlobal(t, "KEY_F");
	croc_pushInt(t, GLFW_KEY_G);                 croc_newGlobal(t, "KEY_G");
	croc_pushInt(t, GLFW_KEY_H);                 croc_newGlobal(t, "KEY_H");
	croc_pushInt(t, GLFW_KEY_I);                 croc_newGlobal(t, "KEY_I");
	croc_pushInt(t, GLFW_KEY_J);                 croc_newGlobal(t, "KEY_J");
	croc_pushInt(t, GLFW_KEY_K);                 croc_newGlobal(t, "KEY_K");
	croc_pushInt(t, GLFW_KEY_L);                 croc_newGlobal(t, "KEY_L");
	croc_pushInt(t, GLFW_KEY_M);                 croc_newGlobal(t, "KEY_M");
	croc_pushInt(t, GLFW_KEY_N);                 croc_newGlobal(t, "KEY_N");
	croc_pushInt(t, GLFW_KEY_O);                 croc_newGlobal(t, "KEY_O");
	croc_pushInt(t, GLFW_KEY_P);                 croc_newGlobal(t, "KEY_P");
	croc_pushInt(t, GLFW_KEY_Q);                 croc_newGlobal(t, "KEY_Q");
	croc_pushInt(t, GLFW_KEY_R);                 croc_newGlobal(t, "KEY_R");
	croc_pushInt(t, GLFW_KEY_S);                 croc_newGlobal(t, "KEY_S");
	croc_pushInt(t, GLFW_KEY_T);                 croc_newGlobal(t, "KEY_T");
	croc_pushInt(t, GLFW_KEY_U);                 croc_newGlobal(t, "KEY_U");
	croc_pushInt(t, GLFW_KEY_V);                 croc_newGlobal(t, "KEY_V");
	croc_pushInt(t, GLFW_KEY_W);                 croc_newGlobal(t, "KEY_W");
	croc_pushInt(t, GLFW_KEY_X);                 croc_newGlobal(t, "KEY_X");
	croc_pushInt(t, GLFW_KEY_Y);                 croc_newGlobal(t, "KEY_Y");
	croc_pushInt(t, GLFW_KEY_Z);                 croc_newGlobal(t, "KEY_Z");
	croc_pushInt(t, GLFW_KEY_LEFT_BRACKET);      croc_newGlobal(t, "KEY_LEFT_BRACKET");
	croc_pushInt(t, GLFW_KEY_BACKSLASH);         croc_newGlobal(t, "KEY_BACKSLASH");
	croc_pushInt(t, GLFW_KEY_RIGHT_BRACKET);     croc_newGlobal(t, "KEY_RIGHT_BRACKET");
	croc_pushInt(t, GLFW_KEY_GRAVE_ACCENT);      croc_newGlobal(t, "KEY_GRAVE_ACCENT");
	croc_pushInt(t, GLFW_KEY_WORLD_1);           croc_newGlobal(t, "KEY_WORLD_1");
	croc_pushInt(t, GLFW_KEY_WORLD_2);           croc_newGlobal(t, "KEY_WORLD_2");
	croc_pushInt(t, GLFW_KEY_ESCAPE);            croc_newGlobal(t, "KEY_ESCAPE");
	croc_pushInt(t, GLFW_KEY_ENTER);             croc_newGlobal(t, "KEY_ENTER");
	croc_pushInt(t, GLFW_KEY_TAB);               croc_newGlobal(t, "KEY_TAB");
	croc_pushInt(t, GLFW_KEY_BACKSPACE);         croc_newGlobal(t, "KEY_BACKSPACE");
	croc_pushInt(t, GLFW_KEY_INSERT);            croc_newGlobal(t, "KEY_INSERT");
	croc_pushInt(t, GLFW_KEY_DELETE);            croc_newGlobal(t, "KEY_DELETE");
	croc_pushInt(t, GLFW_KEY_RIGHT);             croc_newGlobal(t, "KEY_RIGHT");
	croc_pushInt(t, GLFW_KEY_LEFT);              croc_newGlobal(t, "KEY_LEFT");
	croc_pushInt(t, GLFW_KEY_DOWN);              croc_newGlobal(t, "KEY_DOWN");
	croc_pushInt(t, GLFW_KEY_UP);                croc_newGlobal(t, "KEY_UP");
	croc_pushInt(t, GLFW_KEY_PAGE_UP);           croc_newGlobal(t, "KEY_PAGE_UP");
	croc_pushInt(t, GLFW_KEY_PAGE_DOWN);         croc_newGlobal(t, "KEY_PAGE_DOWN");
	croc_pushInt(t, GLFW_KEY_HOME);              croc_newGlobal(t, "KEY_HOME");
	croc_pushInt(t, GLFW_KEY_END);               croc_newGlobal(t, "KEY_END");
	croc_pushInt(t, GLFW_KEY_CAPS_LOCK);         croc_newGlobal(t, "KEY_CAPS_LOCK");
	croc_pushInt(t, GLFW_KEY_SCROLL_LOCK);       croc_newGlobal(t, "KEY_SCROLL_LOCK");
	croc_pushInt(t, GLFW_KEY_NUM_LOCK);          croc_newGlobal(t, "KEY_NUM_LOCK");
	croc_pushInt(t, GLFW_KEY_PRINT_SCREEN);      croc_newGlobal(t, "KEY_PRINT_SCREEN");
	croc_pushInt(t, GLFW_KEY_PAUSE);             croc_newGlobal(t, "KEY_PAUSE");
	croc_pushInt(t, GLFW_KEY_F1);                croc_newGlobal(t, "KEY_F1");
	croc_pushInt(t, GLFW_KEY_F2);                croc_newGlobal(t, "KEY_F2");
	croc_pushInt(t, GLFW_KEY_F3);                croc_newGlobal(t, "KEY_F3");
	croc_pushInt(t, GLFW_KEY_F4);                croc_newGlobal(t, "KEY_F4");
	croc_pushInt(t, GLFW_KEY_F5);                croc_newGlobal(t, "KEY_F5");
	croc_pushInt(t, GLFW_KEY_F6);                croc_newGlobal(t, "KEY_F6");
	croc_pushInt(t, GLFW_KEY_F7);                croc_newGlobal(t, "KEY_F7");
	croc_pushInt(t, GLFW_KEY_F8);                croc_newGlobal(t, "KEY_F8");
	croc_pushInt(t, GLFW_KEY_F9);                croc_newGlobal(t, "KEY_F9");
	croc_pushInt(t, GLFW_KEY_F10);               croc_newGlobal(t, "KEY_F10");
	croc_pushInt(t, GLFW_KEY_F11);               croc_newGlobal(t, "KEY_F11");
	croc_pushInt(t, GLFW_KEY_F12);               croc_newGlobal(t, "KEY_F12");
	croc_pushInt(t, GLFW_KEY_F13);               croc_newGlobal(t, "KEY_F13");
	croc_pushInt(t, GLFW_KEY_F14);               croc_newGlobal(t, "KEY_F14");
	croc_pushInt(t, GLFW_KEY_F15);               croc_newGlobal(t, "KEY_F15");
	croc_pushInt(t, GLFW_KEY_F16);               croc_newGlobal(t, "KEY_F16");
	croc_pushInt(t, GLFW_KEY_F17);               croc_newGlobal(t, "KEY_F17");
	croc_pushInt(t, GLFW_KEY_F18);               croc_newGlobal(t, "KEY_F18");
	croc_pushInt(t, GLFW_KEY_F19);               croc_newGlobal(t, "KEY_F19");
	croc_pushInt(t, GLFW_KEY_F20);               croc_newGlobal(t, "KEY_F20");
	croc_pushInt(t, GLFW_KEY_F21);               croc_newGlobal(t, "KEY_F21");
	croc_pushInt(t, GLFW_KEY_F22);               croc_newGlobal(t, "KEY_F22");
	croc_pushInt(t, GLFW_KEY_F23);               croc_newGlobal(t, "KEY_F23");
	croc_pushInt(t, GLFW_KEY_F24);               croc_newGlobal(t, "KEY_F24");
	croc_pushInt(t, GLFW_KEY_F25);               croc_newGlobal(t, "KEY_F25");
	croc_pushInt(t, GLFW_KEY_KP_0);              croc_newGlobal(t, "KEY_KP_0");
	croc_pushInt(t, GLFW_KEY_KP_1);              croc_newGlobal(t, "KEY_KP_1");
	croc_pushInt(t, GLFW_KEY_KP_2);              croc_newGlobal(t, "KEY_KP_2");
	croc_pushInt(t, GLFW_KEY_KP_3);              croc_newGlobal(t, "KEY_KP_3");
	croc_pushInt(t, GLFW_KEY_KP_4);              croc_newGlobal(t, "KEY_KP_4");
	croc_pushInt(t, GLFW_KEY_KP_5);              croc_newGlobal(t, "KEY_KP_5");
	croc_pushInt(t, GLFW_KEY_KP_6);              croc_newGlobal(t, "KEY_KP_6");
	croc_pushInt(t, GLFW_KEY_KP_7);              croc_newGlobal(t, "KEY_KP_7");
	croc_pushInt(t, GLFW_KEY_KP_8);              croc_newGlobal(t, "KEY_KP_8");
	croc_pushInt(t, GLFW_KEY_KP_9);              croc_newGlobal(t, "KEY_KP_9");
	croc_pushInt(t, GLFW_KEY_KP_DECIMAL);        croc_newGlobal(t, "KEY_KP_DECIMAL");
	croc_pushInt(t, GLFW_KEY_KP_DIVIDE);         croc_newGlobal(t, "KEY_KP_DIVIDE");
	croc_pushInt(t, GLFW_KEY_KP_MULTIPLY);       croc_newGlobal(t, "KEY_KP_MULTIPLY");
	croc_pushInt(t, GLFW_KEY_KP_SUBTRACT);       croc_newGlobal(t, "KEY_KP_SUBTRACT");
	croc_pushInt(t, GLFW_KEY_KP_ADD);            croc_newGlobal(t, "KEY_KP_ADD");
	croc_pushInt(t, GLFW_KEY_KP_ENTER);          croc_newGlobal(t, "KEY_KP_ENTER");
	croc_pushInt(t, GLFW_KEY_KP_EQUAL);          croc_newGlobal(t, "KEY_KP_EQUAL");
	croc_pushInt(t, GLFW_KEY_LEFT_SHIFT);        croc_newGlobal(t, "KEY_LEFT_SHIFT");
	croc_pushInt(t, GLFW_KEY_LEFT_CONTROL);      croc_newGlobal(t, "KEY_LEFT_CONTROL");
	croc_pushInt(t, GLFW_KEY_LEFT_ALT);          croc_newGlobal(t, "KEY_LEFT_ALT");
	croc_pushInt(t, GLFW_KEY_LEFT_SUPER);        croc_newGlobal(t, "KEY_LEFT_SUPER");
	croc_pushInt(t, GLFW_KEY_RIGHT_SHIFT);       croc_newGlobal(t, "KEY_RIGHT_SHIFT");
	croc_pushInt(t, GLFW_KEY_RIGHT_CONTROL);     croc_newGlobal(t, "KEY_RIGHT_CONTROL");
	croc_pushInt(t, GLFW_KEY_RIGHT_ALT);         croc_newGlobal(t, "KEY_RIGHT_ALT");
	croc_pushInt(t, GLFW_KEY_RIGHT_SUPER);       croc_newGlobal(t, "KEY_RIGHT_SUPER");
	croc_pushInt(t, GLFW_KEY_MENU);              croc_newGlobal(t, "KEY_MENU");
	croc_pushInt(t, GLFW_KEY_LAST);              croc_newGlobal(t, "KEY_LAST");

	// Modifier keys
	croc_pushInt(t, GLFW_MOD_SHIFT);             croc_newGlobal(t, "MOD_SHIFT");
	croc_pushInt(t, GLFW_MOD_CONTROL);           croc_newGlobal(t, "MOD_CONTROL");
	croc_pushInt(t, GLFW_MOD_ALT);               croc_newGlobal(t, "MOD_ALT");
	croc_pushInt(t, GLFW_MOD_SUPER);             croc_newGlobal(t, "MOD_SUPER");

	// Mouse buttons
	croc_pushInt(t, GLFW_MOUSE_BUTTON_1);        croc_newGlobal(t, "MOUSE_BUTTON_1");
	croc_pushInt(t, GLFW_MOUSE_BUTTON_2);        croc_newGlobal(t, "MOUSE_BUTTON_2");
	croc_pushInt(t, GLFW_MOUSE_BUTTON_3);        croc_newGlobal(t, "MOUSE_BUTTON_3");
	croc_pushInt(t, GLFW_MOUSE_BUTTON_4);        croc_newGlobal(t, "MOUSE_BUTTON_4");
	croc_pushInt(t, GLFW_MOUSE_BUTTON_5);        croc_newGlobal(t, "MOUSE_BUTTON_5");
	croc_pushInt(t, GLFW_MOUSE_BUTTON_6);        croc_newGlobal(t, "MOUSE_BUTTON_6");
	croc_pushInt(t, GLFW_MOUSE_BUTTON_7);        croc_newGlobal(t, "MOUSE_BUTTON_7");
	croc_pushInt(t, GLFW_MOUSE_BUTTON_8);        croc_newGlobal(t, "MOUSE_BUTTON_8");
	croc_pushInt(t, GLFW_MOUSE_BUTTON_LAST);     croc_newGlobal(t, "MOUSE_BUTTON_LAST");
	croc_pushInt(t, GLFW_MOUSE_BUTTON_LEFT);     croc_newGlobal(t, "MOUSE_BUTTON_LEFT");
	croc_pushInt(t, GLFW_MOUSE_BUTTON_RIGHT);    croc_newGlobal(t, "MOUSE_BUTTON_RIGHT");
	croc_pushInt(t, GLFW_MOUSE_BUTTON_MIDDLE);   croc_newGlobal(t, "MOUSE_BUTTON_MIDDLE");

	// Window hints and context info
	croc_pushInt(t, GLFW_FOCUSED);               croc_newGlobal(t, "FOCUSED");
	croc_pushInt(t, GLFW_ICONIFIED);             croc_newGlobal(t, "ICONIFIED");
	croc_pushInt(t, GLFW_RESIZABLE);             croc_newGlobal(t, "RESIZABLE");
	croc_pushInt(t, GLFW_VISIBLE);               croc_newGlobal(t, "VISIBLE");
	croc_pushInt(t, GLFW_DECORATED);             croc_newGlobal(t, "DECORATED");
	croc_pushInt(t, GLFW_RED_BITS);              croc_newGlobal(t, "RED_BITS");
	croc_pushInt(t, GLFW_GREEN_BITS);            croc_newGlobal(t, "GREEN_BITS");
	croc_pushInt(t, GLFW_BLUE_BITS);             croc_newGlobal(t, "BLUE_BITS");
	croc_pushInt(t, GLFW_ALPHA_BITS);            croc_newGlobal(t, "ALPHA_BITS");
	croc_pushInt(t, GLFW_DEPTH_BITS);            croc_newGlobal(t, "DEPTH_BITS");
	croc_pushInt(t, GLFW_STENCIL_BITS);          croc_newGlobal(t, "STENCIL_BITS");
	croc_pushInt(t, GLFW_ACCUM_RED_BITS);        croc_newGlobal(t, "ACCUM_RED_BITS");
	croc_pushInt(t, GLFW_ACCUM_GREEN_BITS);      croc_newGlobal(t, "ACCUM_GREEN_BITS");
	croc_pushInt(t, GLFW_ACCUM_BLUE_BITS);       croc_newGlobal(t, "ACCUM_BLUE_BITS");
	croc_pushInt(t, GLFW_ACCUM_ALPHA_BITS);      croc_newGlobal(t, "ACCUM_ALPHA_BITS");
	croc_pushInt(t, GLFW_AUX_BUFFERS);           croc_newGlobal(t, "AUX_BUFFERS");
	croc_pushInt(t, GLFW_STEREO);                croc_newGlobal(t, "STEREO");
	croc_pushInt(t, GLFW_SAMPLES);               croc_newGlobal(t, "SAMPLES");
	croc_pushInt(t, GLFW_SRGB_CAPABLE);          croc_newGlobal(t, "SRGB_CAPABLE");
	croc_pushInt(t, GLFW_REFRESH_RATE);          croc_newGlobal(t, "REFRESH_RATE");
	croc_pushInt(t, GLFW_CLIENT_API);            croc_newGlobal(t, "CLIENT_API");
	croc_pushInt(t, GLFW_CONTEXT_VERSION_MAJOR); croc_newGlobal(t, "CONTEXT_VERSION_MAJOR");
	croc_pushInt(t, GLFW_CONTEXT_VERSION_MINOR); croc_newGlobal(t, "CONTEXT_VERSION_MINOR");
	croc_pushInt(t, GLFW_CONTEXT_REVISION);      croc_newGlobal(t, "CONTEXT_REVISION");
	croc_pushInt(t, GLFW_CONTEXT_ROBUSTNESS);    croc_newGlobal(t, "CONTEXT_ROBUSTNESS");
	croc_pushInt(t, GLFW_OPENGL_FORWARD_COMPAT); croc_newGlobal(t, "OPENGL_FORWARD_COMPAT");
	croc_pushInt(t, GLFW_OPENGL_DEBUG_CONTEXT);  croc_newGlobal(t, "OPENGL_DEBUG_CONTEXT");
	croc_pushInt(t, GLFW_OPENGL_PROFILE);        croc_newGlobal(t, "OPENGL_PROFILE");
	croc_pushInt(t, GLFW_OPENGL_API);            croc_newGlobal(t, "OPENGL_API");
	croc_pushInt(t, GLFW_OPENGL_ES_API);         croc_newGlobal(t, "OPENGL_ES_API");
	croc_pushInt(t, GLFW_NO_ROBUSTNESS);         croc_newGlobal(t, "NO_ROBUSTNESS");
	croc_pushInt(t, GLFW_NO_RESET_NOTIFICATION); croc_newGlobal(t, "NO_RESET_NOTIFICATION");
	croc_pushInt(t, GLFW_LOSE_CONTEXT_ON_RESET); croc_newGlobal(t, "LOSE_CONTEXT_ON_RESET");
	croc_pushInt(t, GLFW_OPENGL_ANY_PROFILE);    croc_newGlobal(t, "OPENGL_ANY_PROFILE");
	croc_pushInt(t, GLFW_OPENGL_CORE_PROFILE);   croc_newGlobal(t, "OPENGL_CORE_PROFILE");
	croc_pushInt(t, GLFW_OPENGL_COMPAT_PROFILE); croc_newGlobal(t, "OPENGL_COMPAT_PROFILE");
}

// =====================================================================================================================
// Loader

word loader(CrocThread* t)
{
	loadSharedLib(t);

	// Check the version
	{
		int major, minor, release;
		glfwGetVersion(&major, &minor, &release);

		if(major < 3 || (major == 3 && minor == 0 && release < 4))
		{
			croc_eh_throwStd(t, "RuntimeError", "GLFW library found is version %d.%d.%d. You need 3.0.4 or higher.",
				major, minor, release);
		}
	}

	registerGlobals(t, _globalFuncs);
	registerConstants(t);

	croc_ex_lookup(t, "hash.WeakValTable");
	croc_pushNull(t);
	croc_call(t, -2, 1);
	croc_ex_setRegistryVar(t, HandleMap);

	croc_class_new(t, "Monitor", 0);
		croc_pushNull(t); croc_class_addHField(t, -2, Monitor_handle);
		registerMethods(t, Monitor_methods);
	croc_newGlobal(t, "Monitor");

	croc_class_new(t, "Window", 0);
		croc_pushNull(t); croc_class_addHField(t, -2, Window_handle);
		registerMethods(t, Window_methods);
	croc_newGlobal(t, "Window");

#ifdef CROC_BUILTIN_DOCS
	CrocDoc doc;
	croc_ex_doc_init(t, &doc, __FILE__);
	croc_dup(t, 0);
	croc_ex_doc_push(&doc, moduleDocs);
		docGlobals(&doc, _globalFuncs);

		croc_field(t, -1, "Monitor");
			croc_ex_doc_push(&doc, MonitorDocs);
			docFields(&doc, Monitor_methods);
			croc_ex_doc_pop(&doc, -1);
		croc_popTop(t);

		croc_field(t, -1, "Window");
			croc_ex_doc_push(&doc, WindowDocs);
			docFields(&doc, Window_methods);
			croc_ex_doc_pop(&doc, -1);
		croc_popTop(t);
	croc_ex_doc_pop(&doc, -1);
	croc_ex_doc_finish(&doc);
	croc_popTop(t);
#endif

	return 0;
}
}

void initGlfwLib(CrocThread* t)
{
	croc_ex_makeModule(t, "glfw", &loader);
}
}
#endif