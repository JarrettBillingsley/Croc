/******************************************************************************
A binding to SDL through Derelict.

License:
Copyright (c) 2009 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module croc.addons.sdl;

version(CrocAllAddons)
	version = CrocSdlAddon;

version(CrocSdlAddon)
{

import tango.stdc.stringz;
import Utf = tango.text.convert.Utf;

import derelict.sdl.sdl;
import derelict.sdl.image;

import croc.api;

private void register(CrocThread* t, NativeFunc func, char[] name)
{
	newFunction(t, func, name);
	newGlobal(t, name);
}

private void constGlobal(CrocThread* t, int x, char[] name)
{
	pushInt(t, x);
	newGlobal(t, name);
}

private void regField(CrocThread* t, NativeFunc func, char[] name)
{
	newFunction(t, func, name);
	fielda(t, -2, name);
}

private void constField(CrocThread* t, int x, char[] name)
{
	pushInt(t, x);
	fielda(t, -2, name);
}

struct SdlLib
{
static:
	void init(CrocThread* t)
	{
		makeModule(t, "sdl", function uword(CrocThread* t)
		{
			safeCode(t, DerelictSDL.load());
			safeCode(t, DerelictSDLImage.load());

			register(t, &sdlinit,       "init");
			register(t, &quit,          "quit");
			register(t, &wasInit,       "wasInit");
			register(t, &getError,      "getError");
			register(t, &initSubSystem, "initSubSystem");
			register(t, &quitSubSystem, "quitSubSystem");
			register(t, &videoModeOK,   "videoModeOK");
			register(t, &setVideoMode,  "setVideoMode");

			register(t, &showCursor, "showCursor");
			register(t, &grabInput,  "grabInput");
			register(t, &warpMouse,  "warpMouse");
			register(t, &caption,    "caption");

			constGlobal(t, SDL_INIT_AUDIO,    "initAudio");
			constGlobal(t, SDL_INIT_VIDEO,    "initVideo");
			constGlobal(t, SDL_INIT_JOYSTICK, "initJoystick");
			constGlobal(t, SDL_INIT_AUDIO | SDL_INIT_VIDEO | SDL_INIT_JOYSTICK, "initEverything");

			constGlobal(t, SDL_SWSURFACE,  "swSurface");
			constGlobal(t, SDL_HWSURFACE,  "hwSurface");
			constGlobal(t, SDL_ASYNCBLIT,  "asyncBlit");
			constGlobal(t, SDL_ANYFORMAT,  "anyFormat");
			constGlobal(t, SDL_DOUBLEBUF,  "doubleBuf");
			constGlobal(t, SDL_FULLSCREEN, "fullscreen");
			constGlobal(t, SDL_OPENGL,     "opengl");
			constGlobal(t, SDL_OPENGLBLIT, "openglBlit");
			constGlobal(t, SDL_RESIZABLE,  "resizable");
			constGlobal(t, SDL_NOFRAME,    "noFrame");

			newNamespace(t, "gl");
				regField(t, &glSetAttribute, "setAttribute");
				regField(t, &glGetAttribute, "getAttribute");
				regField(t, &glSwapBuffers,  "swapBuffers");

				constField(t, SDL_GL_RED_SIZE,           "redSize");
				constField(t, SDL_GL_GREEN_SIZE,         "greenSize");
				constField(t, SDL_GL_BLUE_SIZE,          "blueSize");
				constField(t, SDL_GL_ALPHA_SIZE,         "alphaSize");
				constField(t, SDL_GL_DOUBLEBUFFER,       "doubleBuffer");
				constField(t, SDL_GL_BUFFER_SIZE,        "bufferSize");
				constField(t, SDL_GL_DEPTH_SIZE,         "depthSize");
				constField(t, SDL_GL_STENCIL_SIZE,       "stencilSize");
				constField(t, SDL_GL_ACCUM_RED_SIZE,     "accumRedSize");
				constField(t, SDL_GL_ACCUM_GREEN_SIZE,   "accumGreenSize");
				constField(t, SDL_GL_ACCUM_BLUE_SIZE,    "accumBlueSize");
				constField(t, SDL_GL_ACCUM_ALPHA_SIZE,   "accumAlphaSize");
				constField(t, SDL_GL_STEREO,             "stereo");
				constField(t, SDL_GL_MULTISAMPLEBUFFERS, "multiSampleBuffers");
				constField(t, SDL_GL_MULTISAMPLESAMPLES, "multiSampleSamples");
				constField(t, SDL_GL_ACCELERATED_VISUAL, "acceleratedVisual");
				constField(t, SDL_GL_SWAP_CONTROL,       "swapControl");
			newGlobal(t, "gl");

			newNamespace(t, "event");
				constField(t, SDL_APPMOUSEFOCUS, "mouseFocus");
				constField(t, SDL_APPINPUTFOCUS, "inputFocus");
				constField(t, SDL_APPACTIVE,     "active");

				regField(t, &evtPump,          "pump");
				regField(t, &evtPoll,          "poll");
				regField(t, &evtWait,          "wait");
				regField(t, &evtPush,          "push");
				regField(t, &evtEnableUnicode, "enableUnicode");
				regField(t, &evtKeyRepeat,     "keyRepeat");
			newGlobal(t, "event");

			newNamespace(t, "joystick");
				regField(t, &joyCount,        "count");
				regField(t, &joyOpen,         "open");
				regField(t, &joyClose,        "close");
				regField(t, &joyIsOpen,       "isOpen");
				regField(t, &joyInfo,         "info");
				regField(t, &joyEnableEvents, "enableEvents");
			newGlobal(t, "joystick");

			newNamespace(t, "image");
				pushFormat(t, "{}.{}.{}", SDL_IMAGE_MAJOR_VERSION, SDL_IMAGE_MINOR_VERSION, SDL_IMAGE_PATCHLEVEL); fielda(t, -2, "version");
				constField(t, IMG_INIT_JPG, "initJPG");
				constField(t, IMG_INIT_PNG, "initPNG");
				constField(t, IMG_INIT_TIF, "initTIF");
				constField(t, IMG_INIT_JPG | IMG_INIT_PNG | IMG_INIT_TIF, "initAll");

				regField(t, &imgInit, "init");
				regField(t, &imgQuit, "quit");
				regField(t, &imgLoad, "load");
			newGlobal(t, "image");

			pushKeyNamespace(t);
			dup(t);
			newGlobal(t, "key");

			auto rev = newTable(t);
			dup(t, -2);

			foreach(word k, word v; foreachLoop(t, 1))
			{
				dup(t, v);
				dup(t, k);
				idxa(t, rev);
			}

			newGlobal(t, "niceKey");
			pop(t);

			SdlSurfaceObj.init(t);

			return 0;
		});
	}

	void checkError(CrocThread* t, lazy int dg, char[] msg)
	{
		if(dg() == -1)
			throwException(t, "{}: {}", msg, fromStringz(SDL_GetError()));
	}

	uword sdlinit(CrocThread* t)
	{
		auto flags = cast(uword)checkIntParam(t, 1);
		checkError(t, SDL_Init(flags), "Could not initialize SDL");
		SDL_EventState(SDL_SYSWMEVENT, SDL_IGNORE);
		return 0;
	}

	uword quit(CrocThread* t)
	{
		SDL_Quit();
		return 0;
	}

	uword wasInit(CrocThread* t)
	{
		pushInt(t, SDL_WasInit(cast(uword)checkIntParam(t, 1)));
		return 1;
	}

	uword getError(CrocThread* t)
	{
		pushString(t, fromStringz(SDL_GetError()));
		return 1;
	}

	uword initSubSystem(CrocThread* t)
	{
		auto flags = cast(uword)checkIntParam(t, 1);
		checkError(t, SDL_InitSubSystem(flags), "Could not initialize subsystem");
		return 0;
	}

	uword quitSubSystem(CrocThread* t)
	{
		auto flags = cast(uword)checkIntParam(t, 1);
		SDL_QuitSubSystem(flags);
		return 0;
	}

	uword videoModeOK(CrocThread* t)
	{
		auto w = cast(word)checkIntParam(t, 1);
		auto h = cast(word)checkIntParam(t, 2);
		auto bpp = cast(word)checkIntParam(t, 3);
		auto flags = cast(uword)checkIntParam(t, 4);

		pushBool(t, SDL_VideoModeOK(w, h, bpp, flags) >= 16);
		return 1;
	}

	uword setVideoMode(CrocThread* t)
	{
		auto w = cast(word)checkIntParam(t, 1);
		auto h = cast(word)checkIntParam(t, 2);
		auto bpp = cast(word)checkIntParam(t, 3);
		auto flags = cast(uword)checkIntParam(t, 4);

		pushBool(t, SDL_SetVideoMode(w, h, bpp, flags) !is null);
		return 1;
	}

	uword showCursor(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		if(numParams == 0)
		{
			pushBool(t, SDL_ShowCursor(SDL_QUERY) == SDL_ENABLE);
			return 1;
		}
		else
		{
			if(checkBoolParam(t, 1))
				SDL_ShowCursor(SDL_ENABLE);
			else
				SDL_ShowCursor(SDL_DISABLE);
		}

		return 0;
	}

	uword grabInput(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		if(numParams == 0)
		{
			pushInt(t, SDL_WM_GrabInput(SDL_GRAB_QUERY));
			return 1;
		}
		else
		{
			if(checkBoolParam(t, 1))
				SDL_WM_GrabInput(SDL_GRAB_ON);
			else
				SDL_WM_GrabInput(SDL_GRAB_OFF);
		}

		return 0;
	}
	
	uword warpMouse(CrocThread* t)
	{
		auto x = cast(Uint16)checkIntParam(t, 1);
		auto y = cast(Uint16)checkIntParam(t, 2);
		SDL_WarpMouse(x, y);
		return 0;
	}

	uword caption(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		
		if(numParams == 0)
		{
			char* cap;
			SDL_WM_GetCaption(&cap, null);
			pushString(t, fromStringz(cap));
			return 1;
		}
		else
		{
			auto cap = checkStringParam(t, 1);
			SDL_WM_SetCaption(toStringz(cap), null);
			return 0;
		}
	}

	uword glGetAttribute(CrocThread* t)
	{
		auto attr = cast(word)checkIntParam(t, 1);
		int val;
		checkError(t, SDL_GL_GetAttribute(attr, &val), "Could not get attribute");
		pushInt(t, val);
		return 1;
	}

	uword glSetAttribute(CrocThread* t)
	{
		auto attr = cast(word)checkIntParam(t, 1);
		auto val = cast(word)checkIntParam(t, 2);
		checkError(t, SDL_GL_SetAttribute(attr, val), "Could not set attribute");
		return 0;
	}

	uword glSwapBuffers(CrocThread* t)
	{
		SDL_GL_SwapBuffers();
		return 0;
	}

	uword pushEvent(CrocThread* t, ref SDL_Event ev)
	{
		switch(ev.type)
		{
			case SDL_ACTIVEEVENT:
				pushString(t, "active");
				pushBool(t, cast(bool)ev.active.gain);
				pushInt(t, ev.active.state);
				return 3;

			case SDL_KEYDOWN:
				pushString(t, "keyDown");
				pushInt(t, ev.key.keysym.sym);
				pushInt(t, ev.key.keysym.mod);

				if(Utf.isValid(cast(dchar)ev.key.keysym.unicode))
					pushChar(t, cast(dchar)ev.key.keysym.unicode);
				else
					pushChar(t, '\0');

				return 4;

			case SDL_KEYUP:
				pushString(t, "keyUp");
				pushInt(t, ev.key.keysym.sym);
				pushInt(t, ev.key.keysym.mod);
				return 3;

			case SDL_MOUSEMOTION:
				pushString(t, "mouseMotion");
				pushInt(t, ev.motion.x);
				pushInt(t, ev.motion.y);
				pushInt(t, ev.motion.xrel);
				pushInt(t, ev.motion.yrel);
				return 5;

			case SDL_MOUSEBUTTONDOWN:
				pushString(t, "mouseDown");
				pushInt(t, ev.button.button);
				return 2;

			case SDL_MOUSEBUTTONUP:
				pushString(t, "mouseUp");
				pushInt(t, ev.button.button);
				return 2;

			case SDL_JOYAXISMOTION:
				pushString(t, "joyAxis");
				pushInt(t, ev.jaxis.which);
				pushInt(t, ev.jaxis.axis);
				pushInt(t, ev.jaxis.value);
				return 4;

			case SDL_JOYBALLMOTION:
				pushString(t, "joyBall");
				pushInt(t, ev.jball.which);
				pushInt(t, ev.jball.ball);
				pushInt(t, ev.jball.xrel);
				pushInt(t, ev.jball.yrel);
				return 5;

			case SDL_JOYHATMOTION:
				pushString(t, "joyHat");
				pushInt(t, ev.jhat.which);
				pushInt(t, ev.jhat.hat);
				pushInt(t, ev.jhat.value);
				return 4;

			case SDL_JOYBUTTONDOWN:
				pushString(t, "joyButtonDown");
				pushInt(t, ev.jbutton.which);
				pushInt(t, ev.jbutton.button);
				return 3;

			case SDL_JOYBUTTONUP:
				pushString(t, "joyButtonUp");
				pushInt(t, ev.jbutton.which);
				pushInt(t, ev.jbutton.button);
				return 3;

			case SDL_QUIT:
				pushString(t, "quit");
				return 1;

			case SDL_VIDEORESIZE:
				pushString(t, "resize");
				pushInt(t, ev.resize.w);
				pushInt(t, ev.resize.h);
				return 3;

			case SDL_VIDEOEXPOSE:
				pushString(t, "expose");
				return 1;

			default:
				return 0;
		}
	}

	void popEvent(CrocThread* t, ref SDL_Event ev)
	{
		auto name = checkStringParam(t, 1);

		switch(name)
		{
			case "active":
				ev.type = SDL_ACTIVEEVENT;
				ev.active.gain = checkBoolParam(t, 2);
				ev.active.state = cast(ubyte)checkIntParam(t, 3);
				return;

			case "keyDown":
				ev.type = SDL_KEYDOWN;
				ev.key.keysym.sym = cast(int)checkIntParam(t, 2);
				ev.key.keysym.mod = cast(int)checkIntParam(t, 3);
				ev.key.keysym.unicode = optCharParam(t, 4, '\0');
				return;

			case "keyUp":
				ev.type = SDL_KEYUP;
				ev.key.keysym.sym = cast(int)checkIntParam(t, 2);
				ev.key.keysym.mod = cast(int)checkIntParam(t, 3);
				return;

			case "mouseMotion":
				ev.type = SDL_MOUSEMOTION;
				ev.motion.x = cast(ushort)checkIntParam(t, 2);
				ev.motion.y = cast(ushort)checkIntParam(t, 3);
				ev.motion.xrel = cast(short)checkIntParam(t, 4);
				ev.motion.yrel = cast(short)checkIntParam(t, 5);
				return;

			case "mouseDown":
				ev.type = SDL_MOUSEBUTTONDOWN;
				ev.button.button = cast(ubyte)checkIntParam(t, 2);
				return;

			case "mouseUp":
				ev.type = SDL_MOUSEBUTTONUP;
				ev.button.button = cast(ubyte)checkIntParam(t, 2);
				return;

			case "joyAxis":
				ev.type = SDL_JOYAXISMOTION;
				ev.jaxis.which = cast(ubyte)checkIntParam(t, 2);
				ev.jaxis.axis = cast(ubyte)checkIntParam(t, 3);
				ev.jaxis.value = cast(short)checkIntParam(t, 4);
				return;

			case "joyBall":
				ev.type = SDL_JOYBALLMOTION;
				ev.jball.which = cast(ubyte)checkIntParam(t, 2);
				ev.jball.ball = cast(ubyte)checkIntParam(t, 3);
				ev.jball.xrel = cast(short)checkIntParam(t, 4);
				ev.jball.yrel = cast(short)checkIntParam(t, 5);
				return;

			case "joyHat":
				ev.type = SDL_JOYHATMOTION;
				ev.jhat.which = cast(ubyte)checkIntParam(t, 2);
				ev.jhat.hat = cast(ubyte)checkIntParam(t, 3);
				ev.jhat.value = cast(ubyte)checkIntParam(t, 4);
				return;

			case "joyButtonDown":
				ev.type = SDL_JOYBUTTONDOWN;
				ev.jbutton.which = cast(ubyte)checkIntParam(t, 2);
				ev.jbutton.button = cast(ubyte)checkIntParam(t, 3);
				return;

			case "joyButtonUp":
				ev.type = SDL_JOYBUTTONUP;
				ev.jbutton.which = cast(ubyte)checkIntParam(t, 2);
				ev.jbutton.button = cast(ubyte)checkIntParam(t, 3);
				return;

			case "quit":
				ev.type = SDL_QUIT;
				return;

			case "resize":
				ev.type = SDL_VIDEORESIZE;
				ev.resize.w = cast(int)checkIntParam(t, 2);
				ev.resize.h = cast(int)checkIntParam(t, 3);
				return;

			case "expose":
				ev.type = SDL_VIDEOEXPOSE;
				return;

			default:
				throwException(t, "Invalid event");
		}
	}

	uword evtPump(CrocThread* t)
	{
		SDL_PumpEvents();
		return 0;
	}

	uword evtPoll(CrocThread* t)
	{
		SDL_Event ev = void;

		while(SDL_PollEvent(&ev))
		{
			if(auto ret = pushEvent(t, ev))
				return ret;
		}

		return 0;
	}

	uword evtWait(CrocThread* t)
	{
		SDL_Event ev = void;

		while(SDL_WaitEvent(&ev) != 0)
		{
			if(auto ret = pushEvent(t, ev))
				return ret;
		}

		throwException(t, "Error waiting for event: {}", fromStringz(SDL_GetError()));
		return 0;
	}

	uword evtPush(CrocThread* t)
	{
		SDL_Event ev;
		popEvent(t, ev);
		checkError(t, SDL_PushEvent(&ev), "Could not push event");
		return 0;
	}

	uword evtEnableUnicode(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		
		if(numParams == 0)
		{
			pushInt(t, SDL_EnableUNICODE(-1));
			return 1;
		}
		else
		{
			SDL_EnableUNICODE(cast(int)checkBoolParam(t, 1));
			return 0;
		}
	}

	uword evtKeyRepeat(CrocThread* t)
	{
		auto delay = optIntParam(t, 1, SDL_DEFAULT_REPEAT_DELAY);
		auto interval = optIntParam(t, 2, SDL_DEFAULT_REPEAT_INTERVAL);
		checkError(t, SDL_EnableKeyRepeat(cast(int)delay, cast(int)interval), "Could not set key repeat");
		return 0;
	}
	
	uword joyCount(CrocThread* t)
	{
		pushInt(t, SDL_NumJoysticks());
		return 1;
	}
	
	uword joyOpen(CrocThread* t)
	{
		auto idx = cast(int)checkIntParam(t, 1);
		
		if(SDL_JoystickOpened(idx))
			return 0;

		if(SDL_JoystickOpen(idx) is null)
			throwException(t, "Could not open joystick {}: {}", idx, fromStringz(SDL_GetError()));

		return 0;
	}

	uword joyClose(CrocThread* t)
	{
		auto idx = cast(int)checkIntParam(t, 1);

		if(SDL_JoystickOpened(idx))
		{
			auto j = SDL_JoystickOpen(idx);
			
			// Yes, twice. Why? Cause SDL seems to keep a ref count of how many times you've opened a joystick, and since we
			// called open on this stick before, it's ref was already at 1, and now it's at 2. So we close it twice.
			SDL_JoystickClose(j);
			SDL_JoystickClose(j);
		}

		return 0;
	}

	uword joyIsOpen(CrocThread* t)
	{
		auto idx = cast(int)checkIntParam(t, 1);
		pushBool(t, cast(bool)SDL_JoystickOpened(idx));
		return 1;
	}
	
	uword joyInfo(CrocThread* t)
	{
		auto idx = cast(int)checkIntParam(t, 1);

		if(auto ret = SDL_JoystickName(idx))
		{
			pushString(t, fromStringz(ret));
			
			auto j = SDL_JoystickOpen(idx);
			pushInt(t, SDL_JoystickNumAxes(j));
			pushInt(t, SDL_JoystickNumButtons(j));
			pushInt(t, SDL_JoystickNumHats(j));
			pushInt(t, SDL_JoystickNumBalls(j));
			SDL_JoystickClose(j);

			return 5;
		}

		throwException(t, "Could not get info of joystick {}: {}", idx, fromStringz(SDL_GetError()));
		return 0;
	}

	uword joyEnableEvents(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;

		if(numParams == 0)
		{
			pushBool(t, SDL_JoystickEventState(SDL_QUERY) == SDL_ENABLE);
			return 1;
		}
		else
		{
			SDL_JoystickEventState(checkBoolParam(t, 1) ? SDL_ENABLE : SDL_DISABLE);
			return 0;
		}
	}

	uword imgInit(CrocThread* t)
	{
		auto flags = cast(int)checkIntParam(t, 1);
		IMG_Init(flags);
		return 0;
	}

	uword imgQuit(CrocThread* t)
	{
		IMG_Quit();
		return 0;
	}

	uword imgLoad(CrocThread* t)
	{
		auto name = checkStringParam(t, 1);
		auto sfc = IMG_Load(toStringz(name));

		if(sfc is null)
			throwException(t, "Error loading image '{}': {}", name, fromStringz(SDL_GetError()));

		lookup(t, "SdlSurface");
		pushNull(t);
		rawCall(t, -2, 1);

		auto psfc = cast(SDL_Surface**)getExtraBytes(t, -1).ptr;
		*psfc = sfc;

		return 1;
	}
}

struct SdlSurfaceObj
{
static:
	void init(CrocThread* t)
	{
		CreateClass(t, "SdlSurface", (CreateClass* c)
		{
			c.method("constructor", &constructor);
			c.method("width",       &width);
			c.method("height",      &height);
			c.method("pitch",       &pitch);
			c.method("format",      &format);
			c.method("pixels",      &pixels);
			c.method("lock",        &lock);
			c.method("unlock",      &unlock);
			c.method("free",        &free);
		});

		newFunction(t, &allocator, "SdlSurface.allocator");
		setAllocator(t, -2);

		newFunction(t, &finalizer, "SdlSurface.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "SdlSurface");
	}

	private SDL_Surface* getThis(CrocThread* t)
	{
		checkInstParam(t, 0, "SdlSurface");
		auto ret = *(cast(SDL_Surface**)getExtraBytes(t, 0).ptr);

		if(ret is null)
			throwException(t, "Attempting to call a method on a freed surface");

		return ret;
	}

	uword allocator(CrocThread* t)
	{
		newInstance(t, 0, 0, (SDL_Surface*).sizeof);
		*(cast(SDL_Surface**)getExtraBytes(t, -1).ptr) = null;

		dup(t);
		pushNull(t);
		rotateAll(t, 3);
		methodCall(t, 2, "constructor", 0);
		return 1;
	}

	uword finalizer(CrocThread* t)
	{
		auto psfc = cast(SDL_Surface**)getExtraBytes(t, 0).ptr;

		if(*psfc)
		{
			SDL_FreeSurface(*psfc);
			*psfc = null;
		}

		return 0;
	}

	uword constructor(CrocThread* t)
	{
		return 0;
	}

	uword width(CrocThread* t)
	{
		pushInt(t, getThis(t).w);
		return 1;
	}

	uword height(CrocThread* t)
	{
		pushInt(t, getThis(t).h);
		return 1;
	}

	uword pitch(CrocThread* t)
	{
		pushInt(t, getThis(t).pitch);
		return 1;
	}

	uword format(CrocThread* t)
	{
		auto f = getThis(t).format;

		newTable(t);
		pushInt(t, f.BytesPerPixel); fielda(t, -2, "bpp");
		pushInt(t, f.Rshift);        fielda(t, -2, "rshift");
		pushInt(t, f.Gshift);        fielda(t, -2, "gshift");
		pushInt(t, f.Bshift);        fielda(t, -2, "bshift");
		pushInt(t, f.Ashift);        fielda(t, -2, "ashift");
		pushInt(t, f.Rmask);         fielda(t, -2, "rmask");
		pushInt(t, f.Gmask);         fielda(t, -2, "gmask");
		pushInt(t, f.Bmask);         fielda(t, -2, "bmask");
		pushInt(t, f.Amask);         fielda(t, -2, "amask");
		return 1;
	}

	uword pixels(CrocThread* t)
	{
		pushInt(t, cast(crocint)getThis(t).pixels);
		return 1;
	}
	
	uword lock(CrocThread* t)
	{
		auto s = getThis(t);
		
		if(SDL_LockSurface(s) < 0)
			throwException(t, "Could not lock surface: {}", fromStringz(SDL_GetError()));
		
		memblockViewDArray(t, (cast(ubyte*)s.pixels)[0 .. s.w * s.h * s.format.BytesPerPixel]);
		return 1;
	}

	uword unlock(CrocThread* t)
	{
		SDL_UnlockSurface(getThis(t));
		return 0;
	}

	uword free(CrocThread* t)
	{
		checkInstParam(t, 0, "SdlSurface");
		auto psfc = cast(SDL_Surface**)getExtraBytes(t, 0).ptr;

		if(*psfc)
		{
			SDL_FreeSurface(*psfc);
			*psfc = null;
		}
		
		return 0;
	}
}

private void pushKeyNamespace(CrocThread* t)
{
	newNamespace(t, "key");

	pushInt(t, SDLK_UNKNOWN);      fielda(t, -2, "unknown");
	pushInt(t, SDLK_FIRST);        fielda(t, -2, "first");
	pushInt(t, SDLK_BACKSPACE);    fielda(t, -2, "backspace");
	pushInt(t, SDLK_TAB);          fielda(t, -2, "tab");
	pushInt(t, SDLK_CLEAR);        fielda(t, -2, "clear");
	pushInt(t, SDLK_RETURN);       fielda(t, -2, "return");
	pushInt(t, SDLK_PAUSE);        fielda(t, -2, "pause");
	pushInt(t, SDLK_ESCAPE);       fielda(t, -2, "escape");
	pushInt(t, SDLK_SPACE);        fielda(t, -2, "space");
	pushInt(t, SDLK_EXCLAIM);      fielda(t, -2, "exclaim");
	pushInt(t, SDLK_QUOTEDBL);     fielda(t, -2, "quotedbl");
	pushInt(t, SDLK_HASH);         fielda(t, -2, "hash");
	pushInt(t, SDLK_DOLLAR);       fielda(t, -2, "dollar");
	pushInt(t, SDLK_AMPERSAND);    fielda(t, -2, "ampersand");
	pushInt(t, SDLK_QUOTE);        fielda(t, -2, "quote");
	pushInt(t, SDLK_LEFTPAREN);    fielda(t, -2, "leftparen");
	pushInt(t, SDLK_RIGHTPAREN);   fielda(t, -2, "rightparen");
	pushInt(t, SDLK_ASTERISK);     fielda(t, -2, "asterisk");
	pushInt(t, SDLK_PLUS);         fielda(t, -2, "plus");
	pushInt(t, SDLK_COMMA);        fielda(t, -2, "comma");
	pushInt(t, SDLK_MINUS);        fielda(t, -2, "minus");
	pushInt(t, SDLK_PERIOD);       fielda(t, -2, "period");
	pushInt(t, SDLK_SLASH);        fielda(t, -2, "slash");
	pushInt(t, SDLK_0);            fielda(t, -2, "_0");
	pushInt(t, SDLK_1);            fielda(t, -2, "_1");
	pushInt(t, SDLK_2);            fielda(t, -2, "_2");
	pushInt(t, SDLK_3);            fielda(t, -2, "_3");
	pushInt(t, SDLK_4);            fielda(t, -2, "_4");
	pushInt(t, SDLK_5);            fielda(t, -2, "_5");
	pushInt(t, SDLK_6);            fielda(t, -2, "_6");
	pushInt(t, SDLK_7);            fielda(t, -2, "_7");
	pushInt(t, SDLK_8);            fielda(t, -2, "_8");
	pushInt(t, SDLK_9);            fielda(t, -2, "_9");
	pushInt(t, SDLK_COLON);        fielda(t, -2, "colon");
	pushInt(t, SDLK_SEMICOLON);    fielda(t, -2, "semicolon");
	pushInt(t, SDLK_LESS);         fielda(t, -2, "less");
	pushInt(t, SDLK_EQUALS);       fielda(t, -2, "equals");
	pushInt(t, SDLK_GREATER);      fielda(t, -2, "greater");
	pushInt(t, SDLK_QUESTION);     fielda(t, -2, "question");
	pushInt(t, SDLK_AT);           fielda(t, -2, "at");
	pushInt(t, SDLK_LEFTBRACKET);  fielda(t, -2, "leftbracket");
	pushInt(t, SDLK_BACKSLASH);    fielda(t, -2, "backslash");
	pushInt(t, SDLK_RIGHTBRACKET); fielda(t, -2, "rightbracket");
	pushInt(t, SDLK_CARET);        fielda(t, -2, "caret");
	pushInt(t, SDLK_UNDERSCORE);   fielda(t, -2, "underscore");
	pushInt(t, SDLK_BACKQUOTE);    fielda(t, -2, "backquote");
	pushInt(t, SDLK_a);            fielda(t, -2, "a");
	pushInt(t, SDLK_b);            fielda(t, -2, "b");
	pushInt(t, SDLK_c);            fielda(t, -2, "c");
	pushInt(t, SDLK_d);            fielda(t, -2, "d");
	pushInt(t, SDLK_e);            fielda(t, -2, "e");
	pushInt(t, SDLK_f);            fielda(t, -2, "f");
	pushInt(t, SDLK_g);            fielda(t, -2, "g");
	pushInt(t, SDLK_h);            fielda(t, -2, "h");
	pushInt(t, SDLK_i);            fielda(t, -2, "i");
	pushInt(t, SDLK_j);            fielda(t, -2, "j");
	pushInt(t, SDLK_k);            fielda(t, -2, "k");
	pushInt(t, SDLK_l);            fielda(t, -2, "l");
	pushInt(t, SDLK_m);            fielda(t, -2, "m");
	pushInt(t, SDLK_n);            fielda(t, -2, "n");
	pushInt(t, SDLK_o);            fielda(t, -2, "o");
	pushInt(t, SDLK_p);            fielda(t, -2, "p");
	pushInt(t, SDLK_q);            fielda(t, -2, "q");
	pushInt(t, SDLK_r);            fielda(t, -2, "r");
	pushInt(t, SDLK_s);            fielda(t, -2, "s");
	pushInt(t, SDLK_t);            fielda(t, -2, "t");
	pushInt(t, SDLK_u);            fielda(t, -2, "u");
	pushInt(t, SDLK_v);            fielda(t, -2, "v");
	pushInt(t, SDLK_w);            fielda(t, -2, "w");
	pushInt(t, SDLK_x);            fielda(t, -2, "x");
	pushInt(t, SDLK_y);            fielda(t, -2, "y");
	pushInt(t, SDLK_z);            fielda(t, -2, "z");
	pushInt(t, SDLK_DELETE);       fielda(t, -2, "delete");
	pushInt(t, SDLK_WORLD_0);      fielda(t, -2, "world_0");
	pushInt(t, SDLK_WORLD_1);      fielda(t, -2, "world_1");
	pushInt(t, SDLK_WORLD_2);      fielda(t, -2, "world_2");
	pushInt(t, SDLK_WORLD_3);      fielda(t, -2, "world_3");
	pushInt(t, SDLK_WORLD_4);      fielda(t, -2, "world_4");
	pushInt(t, SDLK_WORLD_5);      fielda(t, -2, "world_5");
	pushInt(t, SDLK_WORLD_6);      fielda(t, -2, "world_6");
	pushInt(t, SDLK_WORLD_7);      fielda(t, -2, "world_7");
	pushInt(t, SDLK_WORLD_8);      fielda(t, -2, "world_8");
	pushInt(t, SDLK_WORLD_9);      fielda(t, -2, "world_9");
	pushInt(t, SDLK_WORLD_10);     fielda(t, -2, "world_10");
	pushInt(t, SDLK_WORLD_11);     fielda(t, -2, "world_11");
	pushInt(t, SDLK_WORLD_12);     fielda(t, -2, "world_12");
	pushInt(t, SDLK_WORLD_13);     fielda(t, -2, "world_13");
	pushInt(t, SDLK_WORLD_14);     fielda(t, -2, "world_14");
	pushInt(t, SDLK_WORLD_15);     fielda(t, -2, "world_15");
	pushInt(t, SDLK_WORLD_16);     fielda(t, -2, "world_16");
	pushInt(t, SDLK_WORLD_17);     fielda(t, -2, "world_17");
	pushInt(t, SDLK_WORLD_18);     fielda(t, -2, "world_18");
	pushInt(t, SDLK_WORLD_19);     fielda(t, -2, "world_19");
	pushInt(t, SDLK_WORLD_20);     fielda(t, -2, "world_20");
	pushInt(t, SDLK_WORLD_21);     fielda(t, -2, "world_21");
	pushInt(t, SDLK_WORLD_22);     fielda(t, -2, "world_22");
	pushInt(t, SDLK_WORLD_23);     fielda(t, -2, "world_23");
	pushInt(t, SDLK_WORLD_24);     fielda(t, -2, "world_24");
	pushInt(t, SDLK_WORLD_25);     fielda(t, -2, "world_25");
	pushInt(t, SDLK_WORLD_26);     fielda(t, -2, "world_26");
	pushInt(t, SDLK_WORLD_27);     fielda(t, -2, "world_27");
	pushInt(t, SDLK_WORLD_28);     fielda(t, -2, "world_28");
	pushInt(t, SDLK_WORLD_29);     fielda(t, -2, "world_29");
	pushInt(t, SDLK_WORLD_30);     fielda(t, -2, "world_30");
	pushInt(t, SDLK_WORLD_31);     fielda(t, -2, "world_31");
	pushInt(t, SDLK_WORLD_32);     fielda(t, -2, "world_32");
	pushInt(t, SDLK_WORLD_33);     fielda(t, -2, "world_33");
	pushInt(t, SDLK_WORLD_34);     fielda(t, -2, "world_34");
	pushInt(t, SDLK_WORLD_35);     fielda(t, -2, "world_35");
	pushInt(t, SDLK_WORLD_36);     fielda(t, -2, "world_36");
	pushInt(t, SDLK_WORLD_37);     fielda(t, -2, "world_37");
	pushInt(t, SDLK_WORLD_38);     fielda(t, -2, "world_38");
	pushInt(t, SDLK_WORLD_39);     fielda(t, -2, "world_39");
	pushInt(t, SDLK_WORLD_40);     fielda(t, -2, "world_40");
	pushInt(t, SDLK_WORLD_41);     fielda(t, -2, "world_41");
	pushInt(t, SDLK_WORLD_42);     fielda(t, -2, "world_42");
	pushInt(t, SDLK_WORLD_43);     fielda(t, -2, "world_43");
	pushInt(t, SDLK_WORLD_44);     fielda(t, -2, "world_44");
	pushInt(t, SDLK_WORLD_45);     fielda(t, -2, "world_45");
	pushInt(t, SDLK_WORLD_46);     fielda(t, -2, "world_46");
	pushInt(t, SDLK_WORLD_47);     fielda(t, -2, "world_47");
	pushInt(t, SDLK_WORLD_48);     fielda(t, -2, "world_48");
	pushInt(t, SDLK_WORLD_49);     fielda(t, -2, "world_49");
	pushInt(t, SDLK_WORLD_50);     fielda(t, -2, "world_50");
	pushInt(t, SDLK_WORLD_51);     fielda(t, -2, "world_51");
	pushInt(t, SDLK_WORLD_52);     fielda(t, -2, "world_52");
	pushInt(t, SDLK_WORLD_53);     fielda(t, -2, "world_53");
	pushInt(t, SDLK_WORLD_54);     fielda(t, -2, "world_54");
	pushInt(t, SDLK_WORLD_55);     fielda(t, -2, "world_55");
	pushInt(t, SDLK_WORLD_56);     fielda(t, -2, "world_56");
	pushInt(t, SDLK_WORLD_57);     fielda(t, -2, "world_57");
	pushInt(t, SDLK_WORLD_58);     fielda(t, -2, "world_58");
	pushInt(t, SDLK_WORLD_59);     fielda(t, -2, "world_59");
	pushInt(t, SDLK_WORLD_60);     fielda(t, -2, "world_60");
	pushInt(t, SDLK_WORLD_61);     fielda(t, -2, "world_61");
	pushInt(t, SDLK_WORLD_62);     fielda(t, -2, "world_62");
	pushInt(t, SDLK_WORLD_63);     fielda(t, -2, "world_63");
	pushInt(t, SDLK_WORLD_64);     fielda(t, -2, "world_64");
	pushInt(t, SDLK_WORLD_65);     fielda(t, -2, "world_65");
	pushInt(t, SDLK_WORLD_66);     fielda(t, -2, "world_66");
	pushInt(t, SDLK_WORLD_67);     fielda(t, -2, "world_67");
	pushInt(t, SDLK_WORLD_68);     fielda(t, -2, "world_68");
	pushInt(t, SDLK_WORLD_69);     fielda(t, -2, "world_69");
	pushInt(t, SDLK_WORLD_70);     fielda(t, -2, "world_70");
	pushInt(t, SDLK_WORLD_71);     fielda(t, -2, "world_71");
	pushInt(t, SDLK_WORLD_72);     fielda(t, -2, "world_72");
	pushInt(t, SDLK_WORLD_73);     fielda(t, -2, "world_73");
	pushInt(t, SDLK_WORLD_74);     fielda(t, -2, "world_74");
	pushInt(t, SDLK_WORLD_75);     fielda(t, -2, "world_75");
	pushInt(t, SDLK_WORLD_76);     fielda(t, -2, "world_76");
	pushInt(t, SDLK_WORLD_77);     fielda(t, -2, "world_77");
	pushInt(t, SDLK_WORLD_78);     fielda(t, -2, "world_78");
	pushInt(t, SDLK_WORLD_79);     fielda(t, -2, "world_79");
	pushInt(t, SDLK_WORLD_80);     fielda(t, -2, "world_80");
	pushInt(t, SDLK_WORLD_81);     fielda(t, -2, "world_81");
	pushInt(t, SDLK_WORLD_82);     fielda(t, -2, "world_82");
	pushInt(t, SDLK_WORLD_83);     fielda(t, -2, "world_83");
	pushInt(t, SDLK_WORLD_84);     fielda(t, -2, "world_84");
	pushInt(t, SDLK_WORLD_85);     fielda(t, -2, "world_85");
	pushInt(t, SDLK_WORLD_86);     fielda(t, -2, "world_86");
	pushInt(t, SDLK_WORLD_87);     fielda(t, -2, "world_87");
	pushInt(t, SDLK_WORLD_88);     fielda(t, -2, "world_88");
	pushInt(t, SDLK_WORLD_89);     fielda(t, -2, "world_89");
	pushInt(t, SDLK_WORLD_90);     fielda(t, -2, "world_90");
	pushInt(t, SDLK_WORLD_91);     fielda(t, -2, "world_91");
	pushInt(t, SDLK_WORLD_92);     fielda(t, -2, "world_92");
	pushInt(t, SDLK_WORLD_93);     fielda(t, -2, "world_93");
	pushInt(t, SDLK_WORLD_94);     fielda(t, -2, "world_94");
	pushInt(t, SDLK_WORLD_95);     fielda(t, -2, "world_95");
	pushInt(t, SDLK_KP0);          fielda(t, -2, "kp0");
	pushInt(t, SDLK_KP1);          fielda(t, -2, "kp1");
	pushInt(t, SDLK_KP2);          fielda(t, -2, "kp2");
	pushInt(t, SDLK_KP3);          fielda(t, -2, "kp3");
	pushInt(t, SDLK_KP4);          fielda(t, -2, "kp4");
	pushInt(t, SDLK_KP5);          fielda(t, -2, "kp5");
	pushInt(t, SDLK_KP6);          fielda(t, -2, "kp6");
	pushInt(t, SDLK_KP7);          fielda(t, -2, "kp7");
	pushInt(t, SDLK_KP8);          fielda(t, -2, "kp8");
	pushInt(t, SDLK_KP9);          fielda(t, -2, "kp9");
	pushInt(t, SDLK_KP_PERIOD);    fielda(t, -2, "kpPeriod");
	pushInt(t, SDLK_KP_DIVIDE);    fielda(t, -2, "kpDivide");
	pushInt(t, SDLK_KP_MULTIPLY);  fielda(t, -2, "kpMultiply");
	pushInt(t, SDLK_KP_MINUS);     fielda(t, -2, "kpMinus");
	pushInt(t, SDLK_KP_PLUS);      fielda(t, -2, "kpPlus");
	pushInt(t, SDLK_KP_ENTER);     fielda(t, -2, "kpEnter");
	pushInt(t, SDLK_KP_EQUALS);    fielda(t, -2, "kpEquals");
	pushInt(t, SDLK_UP);           fielda(t, -2, "up");
	pushInt(t, SDLK_DOWN);         fielda(t, -2, "down");
	pushInt(t, SDLK_RIGHT);        fielda(t, -2, "right");
	pushInt(t, SDLK_LEFT);         fielda(t, -2, "left");
	pushInt(t, SDLK_INSERT);       fielda(t, -2, "insert");
	pushInt(t, SDLK_HOME);         fielda(t, -2, "home");
	pushInt(t, SDLK_END);          fielda(t, -2, "end");
	pushInt(t, SDLK_PAGEUP);       fielda(t, -2, "pageup");
	pushInt(t, SDLK_PAGEDOWN);     fielda(t, -2, "pagedown");
	pushInt(t, SDLK_F1);           fielda(t, -2, "F1");
	pushInt(t, SDLK_F2);           fielda(t, -2, "F2");
	pushInt(t, SDLK_F3);           fielda(t, -2, "F3");
	pushInt(t, SDLK_F4);           fielda(t, -2, "F4");
	pushInt(t, SDLK_F5);           fielda(t, -2, "F5");
	pushInt(t, SDLK_F6);           fielda(t, -2, "F6");
	pushInt(t, SDLK_F7);           fielda(t, -2, "F7");
	pushInt(t, SDLK_F8);           fielda(t, -2, "F8");
	pushInt(t, SDLK_F9);           fielda(t, -2, "F9");
	pushInt(t, SDLK_F10);          fielda(t, -2, "F10");
	pushInt(t, SDLK_F11);          fielda(t, -2, "F11");
	pushInt(t, SDLK_F12);          fielda(t, -2, "F12");
	pushInt(t, SDLK_F13);          fielda(t, -2, "F13");
	pushInt(t, SDLK_F14);          fielda(t, -2, "F14");
	pushInt(t, SDLK_F15);          fielda(t, -2, "F15");
	pushInt(t, SDLK_NUMLOCK);      fielda(t, -2, "numlock");
	pushInt(t, SDLK_CAPSLOCK);     fielda(t, -2, "capslock");
	pushInt(t, SDLK_SCROLLOCK);    fielda(t, -2, "scrollock");
	pushInt(t, SDLK_RSHIFT);       fielda(t, -2, "rshift");
	pushInt(t, SDLK_LSHIFT);       fielda(t, -2, "lshift");
	pushInt(t, SDLK_RCTRL);        fielda(t, -2, "rctrl");
	pushInt(t, SDLK_LCTRL);        fielda(t, -2, "lctrl");
	pushInt(t, SDLK_RALT);         fielda(t, -2, "ralt");
	pushInt(t, SDLK_LALT);         fielda(t, -2, "lalt");
	pushInt(t, SDLK_RMETA);        fielda(t, -2, "rmeta");
	pushInt(t, SDLK_LMETA);        fielda(t, -2, "lmeta");
	pushInt(t, SDLK_LSUPER);       fielda(t, -2, "lsuper");
	pushInt(t, SDLK_RSUPER);       fielda(t, -2, "rsuper");
	pushInt(t, SDLK_MODE);         fielda(t, -2, "mode");
	pushInt(t, SDLK_COMPOSE);      fielda(t, -2, "compose");
	pushInt(t, SDLK_HELP);         fielda(t, -2, "help");
	pushInt(t, SDLK_PRINT);        fielda(t, -2, "print");
	pushInt(t, SDLK_SYSREQ);       fielda(t, -2, "sysreq");
	pushInt(t, SDLK_BREAK);        fielda(t, -2, "break");
	pushInt(t, SDLK_MENU);         fielda(t, -2, "menu");
	pushInt(t, SDLK_POWER);        fielda(t, -2, "power");
	pushInt(t, SDLK_EURO);         fielda(t, -2, "euro");
	pushInt(t, SDLK_UNDO);         fielda(t, -2, "undo");

	newNamespace(t, "mod");
		pushInt(t, KMOD_NONE);   fielda(t, -2, "none");
		pushInt(t, KMOD_NUM);    fielda(t, -2, "numlock");
		pushInt(t, KMOD_CAPS);   fielda(t, -2, "caps");
		pushInt(t, KMOD_LCTRL);  fielda(t, -2, "lctrl");
		pushInt(t, KMOD_RCTRL);  fielda(t, -2, "rctrl");
		pushInt(t, KMOD_RSHIFT); fielda(t, -2, "rshift");
		pushInt(t, KMOD_LSHIFT); fielda(t, -2, "lshift");
		pushInt(t, KMOD_RALT);   fielda(t, -2, "ralt");
		pushInt(t, KMOD_LALT);   fielda(t, -2, "lalt");
		pushInt(t, KMOD_CTRL);   fielda(t, -2, "ctrl");
		pushInt(t, KMOD_SHIFT);  fielda(t, -2, "shift");
		pushInt(t, KMOD_ALT);    fielda(t, -2, "alt");
	fielda(t, -2, "mod");
}

}