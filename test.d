module test;

import tango.io.Stdout;
debug import tango.stdc.stdarg; // To make tango-user-base-debug.lib link correctly

import minid.api;

// version = TestArc;

void main()
{
	scope(exit) Stdout.flush;

	MDVM vm;
	auto t = openVM(&vm);
	loadStdlibs(t);

	version(TestArc)
		ArcLib.init(t);

	try
	{
		importModule(t, "tests.compiler.compiler");
		pushNull(t);
		lookup(t, "modules.runMain");
		swap(t, -3);
		rawCall(t, -3, 0);
	}
	catch(MDException e)
	{
		auto ex = catchException(t);
		Stdout.formatln("Error: {}", e);
	}
	catch(Exception e)
	{
		Stdout.formatln("Bad error ({}, {}): {}", e.file, e.line, e);
		return;
	}

	Stdout.newline.format("MiniD using {} bytes before GC, ", bytesAllocated(&vm)).flush;
	gc(t);
	Stdout.formatln("{} bytes after.", bytesAllocated(&vm)).flush;

	closeVM(&vm);
}

version(TestArc)
{

import minid.bind;

import arc.draw.color;
import arc.draw.image;
import arc.draw.shape;
import arc.font;
import arc.input;
import arc.math.point;
import arc.math.rect;
import arc.math.size;
import arc.sound;
import arc.texture;
import arc.time;
static import arc.window;

struct ArcLib
{
static:
	public void init(MDThread* t)
	{
		WrapModule!
		(
			"arc.draw.shape"
// 			WrapFunc!(arc.draw.shape.drawPixel),
// 			WrapFunc!(arc.draw.shape.drawLine),
// 			WrapFunc!(arc.draw.shape.drawCircle),
// 			WrapFunc!(arc.draw.shape.drawRectangle)
// 			WrapFunc!(arc.draw.shape.drawPolygon)
		)(t);

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
// 			WrapFunc!(arc.input.mousePos),
			WrapFunc!(arc.input.mouseOldX),
			WrapFunc!(arc.input.mouseOldY),
// 			WrapFunc!(arc.input.mouseOldPos),
			WrapFunc!(arc.input.mouseMotion),
			WrapFunc!(arc.input.defaultCursorVisible),
			WrapFunc!(arc.input.wheelUp),
			WrapFunc!(arc.input.wheelDown),
// 			.type(WrapClass!(JoystickException, void function(char[]))())
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
				WrapValue!("Esc", ARC_ESCAPE)
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
		
		WrapModule!
		(
			"arc.math.point",

			WrapClass!
			(
				Point,
				WrapCtors!(void function(float, float)),

				WrapMethod!(Point.set),
				WrapMethod!(Point.angle),
				WrapMethod!(Point.length),
				WrapMethod!(Point.toString, "toString"),
				WrapMethod!(Point.maxComponent),
				WrapMethod!(Point.minComponent),
				WrapMethod!(Point.opNeg),
				WrapMethod!(Point.cross),
				WrapMethod!(Point.dot),
				WrapMethod!(Point.scale),
				// apply
				WrapMethod!(Point.lengthSquared),
				WrapMethod!(Point.normalise, "normalize"),
				WrapMethod!(Point.normaliseCopy, "normalizeCopy"),
				WrapMethod!(Point.rotate),
				WrapMethod!(Point.rotateCopy),
				WrapMethod!(Point.abs),
				WrapMethod!(Point.absCopy),
				WrapMethod!(Point.clamp),
				WrapMethod!(Point.randomise, "randomize"),
				WrapMethod!(Point.distance),
				WrapMethod!(Point.distanceSquared),
				WrapMethod!(Point.getX),
				WrapMethod!(Point.getY),
				WrapMethod!(Point.setX),
				WrapMethod!(Point.setY),
				WrapMethod!(Point.addX),
				WrapMethod!(Point.addY),
				WrapMethod!(Point.above),
				WrapMethod!(Point.below),
				WrapMethod!(Point.left),
				WrapMethod!(Point.right)
			)
		)(t);

		WrapModule!
		(
			"arc.time",
			WrapFunc!(arc.time.open),
			WrapFunc!(arc.time.close),
			WrapFunc!(arc.time.process),
			WrapFunc!(arc.time.sleep),
			WrapFunc!(arc.time.elapsedMilliseconds),
			WrapFunc!(arc.time.elapsedSeconds),
			WrapFunc!(arc.time.fps),
			WrapFunc!(arc.time.limitFPS),
			WrapFunc!(arc.time.getTime)
		)(t);

		WrapModule!
		(
			"arc.window",
			WrapFunc!(arc.window.open),
			WrapFunc!(arc.window.close),
			WrapFunc!(arc.window.getWidth),
			WrapFunc!(arc.window.getHeight),
// 			WrapFunc!(arc.window.getSize),
			WrapFunc!(arc.window.isFullScreen),
			WrapFunc!(arc.window.resize),
			WrapFunc!(arc.window.toggleFullScreen),
			WrapFunc!(arc.window.clear),
			WrapFunc!(arc.window.swap),
			WrapFunc!(arc.window.swapClear),
			WrapFunc!(arc.window.screenshot),

			WrapNamespace!
			(
				"coordinates",
// 				WrapFunc!(arc.window.coordinates.setSize),
// 				WrapFunc!(arc.window.coordinates.setOrigin),
// 				WrapFunc!(arc.window.coordinates.getSize),
// 				WrapFunc!(arc.window.coordinates.getOrigin),
				WrapFunc!(arc.window.coordinates.getWidth),
				WrapFunc!(arc.window.coordinates.getHeight)
			)
		)(t);
	}
}

}