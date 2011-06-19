module samples.sdltest

import sdl: event, key, niceKey, joystick as joy

sdl.init(sdl.initEverything)

scope(exit)
	sdl.quit()

local w = 1152
local h = 864

sdl.setVideoMode(w, h, 32, sdl.hwSurface)
joy.open(0)

local quit = false

while(!quit)
{
	foreach(e, a, b, c, d; event.poll)
	{
// 		writefln("{}: {} {} {} {}", e, a ? a : "", b ? b : "", c ? c : "", d ? d : "")

		if(e == "quit" || (e == "keyDown" && a == key.escape))
			quit = true

		if(e == "joyHat")
			writeln(c)

		if(e == "active")
		{
			write(a ? "Gained " : "Lost ")

			if(b & event.mouseFocus)
				write("mouse ")

			if(b & event.inputFocus)
				write("input ")

			if(b & event.active)
				write("active")

			writeln()
			io.stdout.flush()
		}
	}
}