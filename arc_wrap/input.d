module arc_wrap.input;

import minid.api;
import minid.bind;

import arc.input;

void init(MDThread* t)
{
	WrapModule!
	(
		"arc.input",
		WrapFunc!(arc.input.open),
		WrapFunc!(arc.input.close),
		WrapFunc!(arc.input.process),
		WrapFunc!(arc.input.setKeyboardRepeat),
		WrapFunc!(arc.input.keyPressed),
		WrapFunc!(arc.input.keyReleased),
		WrapFunc!(arc.input.keyDown),
		WrapFunc!(arc.input.keyUp),
		WrapFunc!(arc.input.charHit),
		WrapFunc!(arc.input.lastChars),
		WrapFunc!(arc.input.mouseButtonPressed),
		WrapFunc!(arc.input.mouseButtonReleased),
		WrapFunc!(arc.input.mouseButtonDown),
		WrapFunc!(arc.input.mouseButtonUp),
		WrapFunc!(arc.input.mouseX),
		WrapFunc!(arc.input.mouseY),
		WrapFunc!(arc.input.mousePos),
		WrapFunc!(arc.input.mouseOldX),
		WrapFunc!(arc.input.mouseOldY),
		WrapFunc!(arc.input.mouseOldPos),
		WrapFunc!(arc.input.mouseMotion),
		WrapFunc!(arc.input.defaultCursorVisible),
		WrapFunc!(arc.input.wheelUp),
		WrapFunc!(arc.input.wheelDown),
		WrapType!(JoystickException, "JoystickException", WrapCtors!(void function(char[]))),
		WrapFunc!(arc.input.numJoysticks),
		WrapFunc!(arc.input.openJoysticks),
		WrapFunc!(arc.input.closeJoysticks),
		WrapFunc!(arc.input.joyButtonDown),
		WrapFunc!(arc.input.joyButtonUp),
		WrapFunc!(arc.input.joyButtonPressed),
		WrapFunc!(arc.input.joyButtonReleased),
		WrapFunc!(arc.input.joyAxisMoved),
		WrapFunc!(arc.input.numJoystickButtons),
		WrapFunc!(arc.input.numJoystickAxes),
		WrapFunc!(arc.input.joystickName),
		WrapFunc!(arc.input.isJoystickOpen),
		WrapFunc!(arc.input.setAxisThreshold),
		WrapFunc!(arc.input.lostFocus),
		WrapFunc!(arc.input.quit),
		WrapFunc!(arc.input.isQuit),

		WrapNamespace!
		(
			"key",
			WrapValue!("Quit", ARC_QUIT),
			WrapValue!("Up", ARC_UP),
			WrapValue!("Down", ARC_DOWN),
			WrapValue!("Left", ARC_LEFT),
			WrapValue!("Right", ARC_RIGHT),
			WrapValue!("Esc", ARC_ESCAPE),
			WrapValue!("Space", ARC_SPACE)
		),

		WrapNamespace!
		(
			"mouse",
			WrapValue!("Any", ANYBUTTON),
			WrapValue!("Left", LEFT),
			WrapValue!("Middle", MIDDLE),
			WrapValue!("Right", RIGHT),
			WrapValue!("WheelUp", WHEELUP),
			WrapValue!("WheelDown", WHEELDOWN)
		)
	)(t);
}