
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
#ifndef CROC_GLFW_ADDON
void initGlfwLib(CrocThread* t)
{
	croc_eh_throwStd(t, "ApiError", "Attempting to load the GLFW library, but it was not compiled in");
}
#else
namespace
{

#ifdef CROC_BUILTIN_DOCS
const char* moduleDocs = DModule("glfw")
R"()";
#endif

// =====================================================================================================================
// GLFW shared lib loading

int (*glfwInit)(void);
void (*glfwTerminate)(void);
void (*glfwGetVersion)(int* major, int* minor, int* rev);
const char* (*glfwGetVersionString)(void);
GLFWmonitor** (*glfwGetMonitors)(int* count);
GLFWmonitor* (*glfwGetPrimaryMonitor)(void);
void (*glfwGetMonitorPos)(GLFWmonitor* monitor, int* xpos, int* ypos);
void (*glfwGetMonitorPhysicalSize)(GLFWmonitor* monitor, int* width, int* height);
const char* (*glfwGetMonitorName)(GLFWmonitor* monitor);
const GLFWvidmode* (*glfwGetVideoModes)(GLFWmonitor* monitor, int* count);
const GLFWvidmode* (*glfwGetVideoMode)(GLFWmonitor* monitor);
void (*glfwSetGamma)(GLFWmonitor* monitor, float gamma);
const GLFWgammaramp* (*glfwGetGammaRamp)(GLFWmonitor* monitor);
void (*glfwSetGammaRamp)(GLFWmonitor* monitor, const GLFWgammaramp* ramp);
void (*glfwDefaultWindowHints)(void);
void (*glfwWindowHint)(int target, int hint);
GLFWwindow* (*glfwCreateWindow)(int width, int height, const char* title, GLFWmonitor* monitor, GLFWwindow* share);
void (*glfwDestroyWindow)(GLFWwindow* window);
int (*glfwWindowShouldClose)(GLFWwindow* window);
void (*glfwSetWindowShouldClose)(GLFWwindow* window, int value);
void (*glfwSetWindowTitle)(GLFWwindow* window, const char* title);
void (*glfwGetWindowPos)(GLFWwindow* window, int* xpos, int* ypos);
void (*glfwSetWindowPos)(GLFWwindow* window, int xpos, int ypos);
void (*glfwGetWindowSize)(GLFWwindow* window, int* width, int* height);
void (*glfwSetWindowSize)(GLFWwindow* window, int width, int height);
void (*glfwGetFramebufferSize)(GLFWwindow* window, int* width, int* height);
void (*glfwIconifyWindow)(GLFWwindow* window);
void (*glfwRestoreWindow)(GLFWwindow* window);
void (*glfwShowWindow)(GLFWwindow* window);
void (*glfwHideWindow)(GLFWwindow* window);
GLFWmonitor* (*glfwGetWindowMonitor)(GLFWwindow* window);
int (*glfwGetWindowAttrib)(GLFWwindow* window, int attrib);
void (*glfwPollEvents)(void);
void (*glfwWaitEvents)(void);
int (*glfwGetInputMode)(GLFWwindow* window, int mode);
void (*glfwSetInputMode)(GLFWwindow* window, int mode, int value);
int (*glfwGetKey)(GLFWwindow* window, int key);
int (*glfwGetMouseButton)(GLFWwindow* window, int button);
void (*glfwGetCursorPos)(GLFWwindow* window, double* xpos, double* ypos);
void (*glfwSetCursorPos)(GLFWwindow* window, double xpos, double ypos);
int (*glfwJoystickPresent)(int joy);
const float* (*glfwGetJoystickAxes)(int joy, int* count);
const unsigned char* (*glfwGetJoystickButtons)(int joy, int* count);
const char* (*glfwGetJoystickName)(int joy);
void (*glfwSetClipboardString)(GLFWwindow* window, const char* string);
const char* (*glfwGetClipboardString)(GLFWwindow* window);
void (*glfwMakeContextCurrent)(GLFWwindow* window);
GLFWwindow* (*glfwGetCurrentContext)(void);
void (*glfwSwapBuffers)(GLFWwindow* window);
void (*glfwSwapInterval)(int interval);
int (*glfwExtensionSupported)(const char* extension);
GLFWerrorfun (*glfwSetErrorCallback)(GLFWerrorfun cbfun);
GLFWmonitorfun (*glfwSetMonitorCallback)(GLFWmonitorfun cbfun);
GLFWwindowposfun (*glfwSetWindowPosCallback)(GLFWwindow* window, GLFWwindowposfun cbfun);
GLFWwindowsizefun (*glfwSetWindowSizeCallback)(GLFWwindow* window, GLFWwindowsizefun cbfun);
GLFWwindowclosefun (*glfwSetWindowCloseCallback)(GLFWwindow* window, GLFWwindowclosefun cbfun);
GLFWwindowrefreshfun (*glfwSetWindowRefreshCallback)(GLFWwindow* window, GLFWwindowrefreshfun cbfun);
GLFWwindowfocusfun (*glfwSetWindowFocusCallback)(GLFWwindow* window, GLFWwindowfocusfun cbfun);
GLFWwindowiconifyfun (*glfwSetWindowIconifyCallback)(GLFWwindow* window, GLFWwindowiconifyfun cbfun);
GLFWframebuffersizefun (*glfwSetFramebufferSizeCallback)(GLFWwindow* window, GLFWframebuffersizefun cbfun);
GLFWkeyfun (*glfwSetKeyCallback)(GLFWwindow* window, GLFWkeyfun cbfun);
GLFWcharfun (*glfwSetCharCallback)(GLFWwindow* window, GLFWcharfun cbfun);
GLFWmousebuttonfun (*glfwSetMouseButtonCallback)(GLFWwindow* window, GLFWmousebuttonfun cbfun);
GLFWcursorposfun (*glfwSetCursorPosCallback)(GLFWwindow* window, GLFWcursorposfun cbfun);
GLFWcursorenterfun (*glfwSetCursorEnterCallback)(GLFWwindow* window, GLFWcursorenterfun cbfun);
GLFWscrollfun (*glfwSetScrollCallback)(GLFWwindow* window, GLFWscrollfun cbfun);
GLFWglproc (*glfwGetProcAddress)(const char* procname);

// Not wrapped
// double (*glfwGetTime)(void);
// void (*glfwSetTime)(double time);
// void (*glfwSetWindowUserPointer)(GLFWwindow* window, void* pointer);
// void* (*glfwGetWindowUserPointer)(GLFWwindow* window);
// glfwGetProcAddress, at least not publicly

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

int pushEvent(CrocThread* t)
{
	GlfwEvent ev;
	removeEvent(ev);

	croc_pushInt(t, ev.type);

	switch(ev.type)
	{
		case GlfwEvent::WindowPos:
		case GlfwEvent::WindowSize:
		case GlfwEvent::FramebufferSize:
			pushWindowObj(t, ev.window);
			croc_pushInt(t, cast(crocint)ev.ints.a);
			croc_pushInt(t, cast(crocint)ev.ints.b);
			return 4;

		case GlfwEvent::WindowClose:
		case GlfwEvent::WindowRefresh:
			pushWindowObj(t, ev.window);
			return 2;

		case GlfwEvent::WindowFocus:
		case GlfwEvent::WindowIconify:
		case GlfwEvent::CursorEnter:
			pushWindowObj(t, ev.window);
			croc_pushInt(t, cast(crocint)ev.ints.a);
			return 3;

		case GlfwEvent::MouseButton:
			pushWindowObj(t, ev.window);
			croc_pushInt(t, cast(crocint)ev.ints.a);
			croc_pushInt(t, cast(crocint)ev.ints.b);
			croc_pushInt(t, cast(crocint)ev.ints.c);
			return 5;

		case GlfwEvent::CursorPos:
		case GlfwEvent::Scroll:
			pushWindowObj(t, ev.window);
			croc_pushFloat(t, cast(crocfloat)ev.doubles.a);
			croc_pushFloat(t, cast(crocfloat)ev.doubles.b);
			return 4;

		case GlfwEvent::Key:
			pushWindowObj(t, ev.window);
			croc_pushInt(t, cast(crocint)ev.ints.a);
			croc_pushInt(t, cast(crocint)ev.ints.b);
			croc_pushInt(t, cast(crocint)ev.ints.c);
			croc_pushInt(t, cast(crocint)ev.ints.d);
			return 6;

		case GlfwEvent::Char:
			pushWindowObj(t, ev.window);
			croc_pushChar(t, cast(crocchar)ev.ints.a);
			return 3;

		case GlfwEvent::Monitor:
			pushMonitorObj(t, ev.monitor);
			croc_pushInt(t, cast(crocint)ev.ints.a);
			return 3;

		default:
			assert(false);
			return 0; // dummy
	}
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
	R"()"),

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
	else
		CHECK_ERROR(t);

	croc_pushBool(t, ret);
	return 1;
}

const StdlibRegisterInfo _terminate_info =
{
	Docstr(DFunc("terminate")
	R"()"),

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
	R"()"),

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
	R"()"),

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
	R"()"),

	"loadOpenGL", 0
};

word_t _loadOpenGL(CrocThread* t)
{
	checkVM(t);

	if(GLAD_GL_VERSION_1_0)
		return 0;

	gladLoadGLLoader(glfwGetProcAddress);

	if(!GLAD_GL_VERSION_1_0)
		croc_eh_throwStd(t, "OSException", "Could not load OpenGL");

	if(!GLAD_GL_VERSION_3_0)
		croc_eh_throwStd(t, "OSException", "OpenGL 3.0+ support needed; this computer only has OpenGL %d.%d",
			GLVersion.major, GLVersion.minor);

	loadOpenGL(t);
	return 0;
}

const StdlibRegisterInfo _getMonitors_info =
{
	Docstr(DFunc("getMonitors")
	R"()"),

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
	R"()"),

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

const StdlibRegisterInfo _defaultWindowHints_info =
{
	Docstr(DFunc("defaultWindowHints")
	R"()"),

	"defaultWindowHints", 0
};

word_t _defaultWindowHints(CrocThread* t)
{
	checkVM(t);
	glfwDefaultWindowHints();
	CHECK_ERROR(t);
	return 0;
}

const StdlibRegisterInfo _windowHint_info =
{
	Docstr(DFunc("windowHint")
	R"()"),

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

const StdlibRegisterInfo _createWindow_info =
{
	Docstr(DFunc("createWindow")
	R"()"),

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
	R"()"),

	"pollEvents", 1
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
	R"()"),

	"waitEvents", 1
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
	Docstr(DFunc("joystickPresent")
	R"()"),

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
	Docstr(DFunc("getJoystickAxes")
	R"()"),

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
	Docstr(DFunc("getJoystickButtons")
	R"()"),

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
	Docstr(DFunc("getJoystickName")
	R"()"),

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
	Docstr(DFunc("makeContextCurrent")
	R"()"),

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
	R"()"),

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
	Docstr(DFunc("swapInterval")
	R"()"),

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
	Docstr(DFunc("extensionSupported")
	R"()"),

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
	Docstr(DFunc("setMonitorEventsEnabled")
	R"()"),

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

const StdlibRegister _globalFuncs[] =
{
	_DListItem(_init),
	_DListItem(_terminate),
	_DListItem(_getVersion),
	_DListItem(_getVersionString),
	_DListItem(_loadOpenGL),
	_DListItem(_getMonitors),
	_DListItem(_getPrimaryMonitor),
	_DListItem(_defaultWindowHints),
	_DListItem(_windowHint),
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
	_DListEnd
};

// =====================================================================================================================
// Monitor class

const StdlibRegisterInfo Monitor_constructor_info =
{
	Docstr(DFunc("constructor")
	R"()"),

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
	R"()"),

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
	R"()"),

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
	R"()"),

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
	R"()"),

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
	R"()"),

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
	Docstr(DFunc("setGamma")
	R"()"),

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
	R"()"),

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
	Docstr(DFunc("setGammaRamp")
	R"()"),

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

	if(rlen != glen || glen != blen || rlen == 0 || rlen > 256)
		return 0; // TODO: ?

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
			return 0; // TODO: ?

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
// Window

const StdlibRegisterInfo Window_constructor_info =
{
	Docstr(DFunc("constructor")
	R"()"),

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
	R"()"),

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
	R"()"),

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
	Docstr(DFunc("setShouldClose")
	R"()"),

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
	Docstr(DFunc("setTitle")
	R"()"),

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
	R"()"),

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
	Docstr(DFunc("setPos")
	R"()"),

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
	R"()"),

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
	Docstr(DFunc("setSize")
	R"()"),

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
	R"()"),

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
	R"()"),

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
	R"()"),

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
	R"()"),

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
	R"()"),

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
	R"()"),

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
	R"()"),

	"getMonitor", 0
};

word_t Window_getMonitor(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	auto ret = glfwGetWindowMonitor(self);
	CHECK_ERROR(t);
	pushMonitorObj(t, ret);
	return 1;
}

const StdlibRegisterInfo Window_setCursorMode_info =
{
	Docstr(DFunc("setCursorMode")
	R"()"),

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
	R"()"),

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
	Docstr(DFunc("setStickyKeys")
	R"()"),

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
	R"()"),

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
	Docstr(DFunc("setStickyMouseButtons")
	R"()"),

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
	R"()"),

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
	Docstr(DFunc("getKey")
	R"()"),

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
	Docstr(DFunc("getMouseButton")
	R"()"),

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
	R"()"),

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
	Docstr(DFunc("setCursorPos")
	R"()"),

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
	Docstr(DFunc("setClipboardString")
	R"()"),

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
	R"()"),

	"getClipboardString", 0
};

word_t Window_getClipboardString(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	croc_pushString(t, glfwGetClipboardString(self));
	CHECK_ERROR(t);
	return 1;
}

const StdlibRegisterInfo Window_getAttrib_info =
{
	Docstr(DFunc("getAttrib")
	R"()"),

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
	Docstr(DFunc("enableEvents")
	R"()"),

	"enableEvents", -1
};

word_t Window_enableEvents(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	auto stackSize = croc_getStackSize(t);

	for(uword i = 1; i < stackSize; i++)
	{
		switch(croc_ex_checkIntParam(t, i))
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
			default:
				croc_eh_throwStd(t, "ValueError", "Invalid event type");
		}

		CHECK_ERROR(t);
	}

	return 0;
}

const StdlibRegisterInfo Window_disableEvents_info =
{
	Docstr(DFunc("disableEvents")
	R"()"),

	"disableEvents", -1
};

word_t Window_disableEvents(CrocThread* t)
{
	checkVM(t);
	auto self = Window_getThis(t);
	auto stackSize = croc_getStackSize(t);

	for(uword i = 1; i < stackSize; i++)
	{
		switch(croc_ex_checkIntParam(t, i))
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
			default:
				croc_eh_throwStd(t, "ValueError", "Invalid event type");
		}

		CHECK_ERROR(t);
	}

	return 0;
}

const StdlibRegisterInfo Window_enableAllEvents_info =
{
	Docstr(DFunc("enableAllEvents")
	R"()"),

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
	R"()"),

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
	croc_pushInt(t, GLFW_RELEASE);               croc_newGlobal(t, "RELEASE");
	croc_pushInt(t, GLFW_PRESS);                 croc_newGlobal(t, "PRESS");
	croc_pushInt(t, GLFW_REPEAT);                croc_newGlobal(t, "REPEAT");
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
	croc_pushInt(t, GLFW_KEY_MENU);              croc_newGlobal(t, "KEY_MENU    ");
	croc_pushInt(t, GLFW_KEY_LAST);              croc_newGlobal(t, "KEY_LAST");
	croc_pushInt(t, GLFW_MOD_SHIFT);             croc_newGlobal(t, "MOD_SHIFT");
	croc_pushInt(t, GLFW_MOD_CONTROL);           croc_newGlobal(t, "MOD_CONTROL");
	croc_pushInt(t, GLFW_MOD_ALT);               croc_newGlobal(t, "MOD_ALT");
	croc_pushInt(t, GLFW_MOD_SUPER);             croc_newGlobal(t, "MOD_SUPER");
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
	croc_pushInt(t, GLFW_JOYSTICK_1);            croc_newGlobal(t, "JOYSTICK_1");
	croc_pushInt(t, GLFW_JOYSTICK_2);            croc_newGlobal(t, "JOYSTICK_2");
	croc_pushInt(t, GLFW_JOYSTICK_3);            croc_newGlobal(t, "JOYSTICK_3");
	croc_pushInt(t, GLFW_JOYSTICK_4);            croc_newGlobal(t, "JOYSTICK_4");
	croc_pushInt(t, GLFW_JOYSTICK_5);            croc_newGlobal(t, "JOYSTICK_5");
	croc_pushInt(t, GLFW_JOYSTICK_6);            croc_newGlobal(t, "JOYSTICK_6");
	croc_pushInt(t, GLFW_JOYSTICK_7);            croc_newGlobal(t, "JOYSTICK_7");
	croc_pushInt(t, GLFW_JOYSTICK_8);            croc_newGlobal(t, "JOYSTICK_8");
	croc_pushInt(t, GLFW_JOYSTICK_9);            croc_newGlobal(t, "JOYSTICK_9");
	croc_pushInt(t, GLFW_JOYSTICK_10);           croc_newGlobal(t, "JOYSTICK_10");
	croc_pushInt(t, GLFW_JOYSTICK_11);           croc_newGlobal(t, "JOYSTICK_11");
	croc_pushInt(t, GLFW_JOYSTICK_12);           croc_newGlobal(t, "JOYSTICK_12");
	croc_pushInt(t, GLFW_JOYSTICK_13);           croc_newGlobal(t, "JOYSTICK_13");
	croc_pushInt(t, GLFW_JOYSTICK_14);           croc_newGlobal(t, "JOYSTICK_14");
	croc_pushInt(t, GLFW_JOYSTICK_15);           croc_newGlobal(t, "JOYSTICK_15");
	croc_pushInt(t, GLFW_JOYSTICK_16);           croc_newGlobal(t, "JOYSTICK_16");
	croc_pushInt(t, GLFW_JOYSTICK_LAST);         croc_newGlobal(t, "JOYSTICK_LAST");
	croc_pushInt(t, GLFW_NOT_INITIALIZED);       croc_newGlobal(t, "NOT_INITIALIZED");
	croc_pushInt(t, GLFW_NO_CURRENT_CONTEXT);    croc_newGlobal(t, "NO_CURRENT_CONTEXT");
	croc_pushInt(t, GLFW_INVALID_ENUM);          croc_newGlobal(t, "INVALID_ENUM");
	croc_pushInt(t, GLFW_INVALID_VALUE);         croc_newGlobal(t, "INVALID_VALUE");
	croc_pushInt(t, GLFW_OUT_OF_MEMORY);         croc_newGlobal(t, "OUT_OF_MEMORY");
	croc_pushInt(t, GLFW_API_UNAVAILABLE);       croc_newGlobal(t, "API_UNAVAILABLE");
	croc_pushInt(t, GLFW_VERSION_UNAVAILABLE);   croc_newGlobal(t, "VERSION_UNAVAILABLE");
	croc_pushInt(t, GLFW_PLATFORM_ERROR);        croc_newGlobal(t, "PLATFORM_ERROR");
	croc_pushInt(t, GLFW_FORMAT_UNAVAILABLE);    croc_newGlobal(t, "FORMAT_UNAVAILABLE");
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
	croc_pushInt(t, GLFW_CURSOR);                croc_newGlobal(t, "CURSOR");
	croc_pushInt(t, GLFW_STICKY_KEYS);           croc_newGlobal(t, "STICKY_KEYS");
	croc_pushInt(t, GLFW_STICKY_MOUSE_BUTTONS);  croc_newGlobal(t, "STICKY_MOUSE_BUTTONS");
	croc_pushInt(t, GLFW_CURSOR_NORMAL);         croc_newGlobal(t, "CURSOR_NORMAL");
	croc_pushInt(t, GLFW_CURSOR_HIDDEN);         croc_newGlobal(t, "CURSOR_HIDDEN");
	croc_pushInt(t, GLFW_CURSOR_DISABLED);       croc_newGlobal(t, "CURSOR_DISABLED");
	croc_pushInt(t, GLFW_CONNECTED);             croc_newGlobal(t, "CONNECTED");
	croc_pushInt(t, GLFW_DISCONNECTED);          croc_newGlobal(t, "DISCONNECTED");

	croc_pushInt(t, GlfwEvent::WindowPos);       croc_newGlobal(t, "Event_WindowPos");
	croc_pushInt(t, GlfwEvent::WindowSize);      croc_newGlobal(t, "Event_WindowSize");
	croc_pushInt(t, GlfwEvent::WindowClose);     croc_newGlobal(t, "Event_WindowClose");
	croc_pushInt(t, GlfwEvent::WindowRefresh);   croc_newGlobal(t, "Event_WindowRefresh");
	croc_pushInt(t, GlfwEvent::WindowFocus);     croc_newGlobal(t, "Event_WindowFocus");
	croc_pushInt(t, GlfwEvent::WindowIconify);   croc_newGlobal(t, "Event_WindowIconify");
	croc_pushInt(t, GlfwEvent::FramebufferSize); croc_newGlobal(t, "Event_FramebufferSize");
	croc_pushInt(t, GlfwEvent::MouseButton);     croc_newGlobal(t, "Event_MouseButton");
	croc_pushInt(t, GlfwEvent::CursorPos);       croc_newGlobal(t, "Event_CursorPos");
	croc_pushInt(t, GlfwEvent::CursorEnter);     croc_newGlobal(t, "Event_CursorEnter");
	croc_pushInt(t, GlfwEvent::Scroll);          croc_newGlobal(t, "Event_Scroll");
	croc_pushInt(t, GlfwEvent::Key);             croc_newGlobal(t, "Event_Key");
	croc_pushInt(t, GlfwEvent::Char);            croc_newGlobal(t, "Event_Char");
	croc_pushInt(t, GlfwEvent::Monitor);         croc_newGlobal(t, "Event_Monitor");
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
		// croc_field(t, -1, "Regex");
		// 	croc_ex_doc_push(&doc, RegexDocs);
		// 	docFields(&doc, Regex_methodFuncs);
		// 	docFieldUV(&doc, Regex_opApplyFunc);

		// 	docField(&doc, {Regex_opIndex_info, nullptr});
		// 	croc_ex_doc_pop(&doc, -1);
		// croc_popTop(t);
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
#endif
}