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

module minid.addons.sdl;

import tango.stdc.stringz;

import derelict.sdl.sdl;

import minid.api;

void register(MDThread* t, NativeFunc func, char[] name)
{
	newFunction(t, func, name);
	newGlobal(t, name);
}

struct SdlLib
{
static:
	void init(MDThread* t)
	{
		safeCode(t, DerelictSDL.load());

		pushGlobal(t, "modules");
		field(t, -1, "customLoaders");

		newFunction(t, function uword(MDThread* t, uword numParams)
		{
			register(t, &init, "init");
			register(t, &quit, "quit");
			register(t, &wasInit, "wasInit");
			register(t, &initSubSystem, "initSubSystem");
			register(t, &quitSubSystem, "quitSubSystem");
			register(t, &setVideoMode, "setVideoMode");
			register(t, &showCursor, "showCursor");
			register(t, &grabInput, "grabInput");
			register(t, &getCaption, "getCaption");
			register(t, &setCaption, "setCaption");

			pushInt(t, SDL_INIT_AUDIO);      newGlobal(t, "initAudio");
			pushInt(t, SDL_INIT_VIDEO);      newGlobal(t, "initVideo");
			pushInt(t, SDL_INIT_CDROM);      newGlobal(t, "initCDRom");
			pushInt(t, SDL_INIT_JOYSTICK);   newGlobal(t, "initJoystick");
			pushInt(t, SDL_INIT_EVERYTHING); newGlobal(t, "initEverything");

			newNamespace(t, "gl");
				newFunction(t, &glSetAttribute, "setAttribute"); fielda(t, -2, "setAttribute");
				newFunction(t, &glGetAttribute, "getAttribute"); fielda(t, -2, "getAttribute");
				newFunction(t, &glSwapBuffers,  "swapBuffers");  fielda(t, -2, "swapBuffers");

				pushInt(t, SDL_GL_RED_SIZE);         fielda(t, -2, "redSize");
				pushInt(t, SDL_GL_GREEN_SIZE);       fielda(t, -2, "greenSize");
				pushInt(t, SDL_GL_BLUE_SIZE);        fielda(t, -2, "blueSize");
				pushInt(t, SDL_GL_ALPHA_SIZE);       fielda(t, -2, "alphaSize");
				pushInt(t, SDL_GL_DOUBLEBUFFER);     fielda(t, -2, "doubleBuffer");
				pushInt(t, SDL_GL_BUFFER_SIZE);      fielda(t, -2, "bufferSize");
				pushInt(t, SDL_GL_DEPTH_SIZE);       fielda(t, -2, "depthSize");
				pushInt(t, SDL_GL_STENCIL_SIZE);     fielda(t, -2, "stencilSize");
				pushInt(t, SDL_GL_ACCUM_RED_SIZE);   fielda(t, -2, "accumRedSize");
				pushInt(t, SDL_GL_ACCUM_GREEN_SIZE); fielda(t, -2, "accumGreenSize");
				pushInt(t, SDL_GL_ACCUM_BLUE_SIZE);  fielda(t, -2, "accumBlueSize");
				pushInt(t, SDL_GL_ACCUM_ALPHA_SIZE); fielda(t, -2, "accumAlphaSize");
			newGlobal(t, "gl");

			pushInt(t, SDL_SWSURFACE);  newGlobal(t, "swSurface");
			pushInt(t, SDL_HWSURFACE);  newGlobal(t, "hwSurface");
			pushInt(t, SDL_ASYNCBLIT);  newGlobal(t, "asyncBlit");
			pushInt(t, SDL_ANYFORMAT);  newGlobal(t, "anyFormat");
			pushInt(t, SDL_DOUBLEBUF);  newGlobal(t, "doubleBuf");
			pushInt(t, SDL_FULLSCREEN); newGlobal(t, "fullscreen");
			pushInt(t, SDL_OPENGL);     newGlobal(t, "opengl");
			pushInt(t, SDL_OPENGLBLIT); newGlobal(t, "openglBlit");
			pushInt(t, SDL_RESIZABLE);  newGlobal(t, "resizable");
			pushInt(t, SDL_NOFRAME);    newGlobal(t, "noFrame");
			
			newNamespace(t, "event");
				newFunction(t, &evtSetHandler, "setHandler"); fielda(t, -2, "setHandler");
				newFunction(t, &evtGetHandler, "getHandler"); fielda(t, -2, "getHandler");
				newFunction(t, &evtPoll,       "poll");       fielda(t, -2, "poll");
				newFunction(t, &evtWait,       "wait");       fielda(t, -2, "wait");

				pushInt(t, SDL_ACTIVEEVENT);   fielda(t, -2, "active");
				pushInt(t, SDL_KEYUP);         fielda(t, -2, "key");
				pushInt(t, SDL_MOUSEMOTION);   fielda(t, -2, "mouseMotion");
				pushInt(t, SDL_MOUSEBUTTONUP); fielda(t, -2, "mouseButton");
				pushInt(t, SDL_JOYAXISMOTION); fielda(t, -2, "joyAxis");
				pushInt(t, SDL_JOYBALLMOTION); fielda(t, -2, "joyBall");
				pushInt(t, SDL_JOYHATMOTION);  fielda(t, -2, "joyHat");
				pushInt(t, SDL_JOYBUTTONUP);   fielda(t, -2, "joyButton");
				pushInt(t, SDL_QUIT);          fielda(t, -2, "quit");
				pushInt(t, SDL_SYSWMEVENT);    fielda(t, -2, "sysWM");
				pushInt(t, SDL_VIDEORESIZE);   fielda(t, -2, "resize");
				pushInt(t, SDL_VIDEOEXPOSE);   fielda(t, -2, "expose");
				pushInt(t, SDL_USEREVENT);     fielda(t, -2, "user");
			newGlobal(t, "event");
			
			pushKeyNamespace(t);
			newGlobal(t, "key");

			newTable(t);
			setRegistryVar(t, "sdl.eventHandlers");

			return 0;
		}, "sdl");

		fielda(t, -2, "sdl");
		pop(t, 2);
	}
	
	void checkError(MDThread* t, lazy int dg, char[] msg)
	{
		if(dg() == -1)
			throwException(t, "{}: {}", msg, fromStringz(SDL_GetError()));
	}

	uword init(MDThread* t, uword numParams)
	{
		auto flags = cast(uword)checkIntParam(t, 1);
		checkError(t, SDL_Init(flags), "Could not initialize SDL");
		return 0;
	}

	uword quit(MDThread* t, uword numParams)
	{
		SDL_Quit();
		return 0;
	}

	uword wasInit(MDThread* t, uword numParams)
	{
		pushInt(t, SDL_WasInit(cast(uword)checkIntParam(t, 1)));
		return 1;
	}

	uword initSubSystem(MDThread* t, uword numParams)
	{
		auto flags = cast(uword)checkIntParam(t, 1);
		checkError(t, SDL_InitSubSystem(flags), "Could not initialize subsystem");
		return 0;
	}

	uword quitSubSystem(MDThread* t, uword numParams)
	{
		auto flags = cast(uword)checkIntParam(t, 1);
		checkError(t, SDL_QuitSubSystem(flags), "Could not quit subsystem");
		return 0;
	}

	uword setVideoMode(MDThread* t, uword numParams)
	{
		auto w = cast(word)checkIntParam(t, 1);
		auto h = cast(word)checkIntParam(t, 2);
		auto bpp = cast(word)checkIntParam(t, 3);
		auto flags = cast(uword)checkIntParam(t, 4);

		pushBool(t, SDL_SetVideoMode(w, h, bpp, flags) !is null);
		return 1;
	}
	
	uword showCursor(MDThread* t, uword numParams)
	{
		if(numParams == 0)
		{
			pushInt(t, SDL_ShowCursor(SDL_QUERY));
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
	
	uword grabInput(MDThread* t, uword numParams)
	{
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

	uword setCaption(MDThread* t, uword numParams)
	{
		auto cap = checkStringParam(t, 1);
		SDL_WM_SetCaption(toStringz(cap), null);
		return 0;
	}
	
	uword getCaption(MDThread* t, uword numParams)
	{
		char* cap;
		SDL_WM_GetCaption(&cap, null);
		pushString(t, fromStringz(cap));
		return 1;
	}

	uword glGetAttribute(MDThread* t, uword numParams)
	{
		auto attr = cast(word)checkIntParam(t, 1);
		int val;
		checkError(t, SDL_GL_GetAttribute(attr, &val), "Could not get attribute");
		pushInt(t, val);
		return 1;
	}

	uword glSetAttribute(MDThread* t, uword numParams)
	{
		auto attr = cast(word)checkIntParam(t, 1);
		auto val = cast(word)checkIntParam(t, 2);
		checkError(t, SDL_GL_SetAttribute(attr, val), "Could not set attribute");
		return 0;
	}

	uword glSwapBuffers(MDThread* t, uword numParams)
	{
		SDL_GL_SwapBuffers();
		return 0;
	}

	void dispatchEvent(MDThread* t, ref SDL_Event ev, word handlers)
	{
		bool getHandler(ubyte type)
		{
			pushInt(t, type);
			idx(t, handlers);

			if(isNull(t, -1))
			{
				pop(t);
				return false;
			}

			return true;
		}

		switch(ev.type)
		{
			case SDL_ACTIVEEVENT:
				if(!getHandler(SDL_ACTIVEEVENT))
					return;
				
				pushNull(t);
				pushInt(t, ev.active.gain);
				pushInt(t, ev.active.state);
				rawCall(t, -4, 0);
				return;

			case SDL_KEYUP, SDL_KEYDOWN:
				if(!getHandler(SDL_KEYUP))
					return;
					
				pushNull(t);
				pushBool(t, ev.key.state == SDL_PRESSED);
				pushInt(t, ev.key.keysym.sym);
				pushInt(t, ev.key.keysym.mod);
				rawCall(t, -5, 0);
				return;

			case SDL_MOUSEMOTION:
				if(!getHandler(SDL_MOUSEMOTION))
					return;
					
				pushNull(t);
				pushInt(t, ev.motion.x);
				pushInt(t, ev.motion.y);
				pushInt(t, ev.motion.xrel);
				pushInt(t, ev.motion.yrel);
				rawCall(t, -6, 0);
				return;

			case SDL_MOUSEBUTTONUP, SDL_MOUSEBUTTONDOWN:
				if(!getHandler(SDL_MOUSEBUTTONUP))
					return;
					
				pushNull(t);
				pushBool(t, ev.button.state == SDL_PRESSED);
				pushInt(t, ev.button.button);
				rawCall(t, -4, 0);
				return;

			case SDL_JOYAXISMOTION: return;
			case SDL_JOYBALLMOTION: return;
			case SDL_JOYHATMOTION: return;
			case SDL_JOYBUTTONUP: return;
			case SDL_JOYBUTTONDOWN: return;

			case SDL_QUIT:
				if(!getHandler(SDL_QUIT))
					return;

				pushNull(t);
				rawCall(t, -2, 0);
				return;

			case SDL_SYSWMEVENT: return;

			case SDL_VIDEORESIZE:
				if(!getHandler(SDL_VIDEORESIZE))
					return;

				pushNull(t);
				pushInt(t, ev.resize.w);
				pushInt(t, ev.resize.h);
				rawCall(t, -4, 0);
				return;

			case SDL_VIDEOEXPOSE:
				if(!getHandler(SDL_VIDEOEXPOSE))
					return;
					
				pushNull(t);
				rawCall(t, -2, 0);
				return;

			case SDL_USEREVENT: return;

			default:
				assert(false);
		}
	}

	uword evtSetHandler(MDThread* t, uword numParams)
	{
		auto type = checkIntParam(t, 1);
		checkAnyParam(t, 2);
		
		if(!isNull(t, 2) && !isFunction(t, 2))
			paramTypeError(t, 2, "null|function");

		switch(type)
		{
			case
				SDL_ACTIVEEVENT,
				SDL_KEYUP,
				SDL_MOUSEMOTION,
				SDL_MOUSEBUTTONUP,
				SDL_JOYAXISMOTION,
				SDL_JOYBALLMOTION,
				SDL_JOYHATMOTION,
				SDL_JOYBUTTONUP,
				SDL_QUIT,
				SDL_SYSWMEVENT,
				SDL_VIDEORESIZE,
				SDL_VIDEOEXPOSE,
				SDL_USEREVENT:
				break;

			default:
				throwException(t, "Invalid event type '{}'", type);
		}

		getRegistryVar(t, "sdl.eventHandlers");
		dup(t, 1);
		dup(t, 2);
		idxa(t, -3);
		pop(t);

		return 0;
	}

	uword evtGetHandler(MDThread* t, uword numParams)
	{
		auto type = checkIntParam(t, 1);

		switch(type)
		{
			case
				SDL_ACTIVEEVENT,
				SDL_KEYUP,
				SDL_MOUSEMOTION,
				SDL_MOUSEBUTTONUP,
				SDL_JOYAXISMOTION,
				SDL_JOYBALLMOTION,
				SDL_JOYHATMOTION,
				SDL_JOYBUTTONUP,
				SDL_QUIT,
				SDL_SYSWMEVENT,
				SDL_VIDEORESIZE,
				SDL_VIDEOEXPOSE,
				SDL_USEREVENT:
				break;

			default:
				throwException(t, "Invalid event type '{}'", type);
		}

		getRegistryVar(t, "sdl.eventHandlers");
		dup(t, 1);
		idx(t, -2);
		return 1;
	}

	uword evtPoll(MDThread* t, uword numParams)
	{
		auto handlers = getRegistryVar(t, "sdl.eventHandlers");
		SDL_Event ev = void;

		while(SDL_PollEvent(&ev))
			dispatchEvent(t, ev, handlers);

		pop(t);
		return 0;
	}

	uword evtWait(MDThread* t, uword numParams)
	{
		SDL_Event ev = void;

		if(SDL_WaitEvent(&ev) == 0)
			throwException(t, "Error waiting for event: {}", fromStringz(SDL_GetError()));

		auto handlers = getRegistryVar(t, "sdl.eventHandlers");
		dispatchEvent(t, ev, handlers);
		pop(t);
		return 0;
	}
}

private void pushKeyNamespace(MDThread* t)
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