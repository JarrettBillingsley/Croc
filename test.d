module test;

import tango.io.Stdout;
debug import tango.stdc.stdarg; // To make tango-user-base-debug.lib link correctly

import minid.api;
import minid.bind;

// version = TestArc;

void main()
{
	scope(exit) Stdout.flush;

	MDVM vm;
	auto t = openVM(&vm);
	loadStdlibs(t);

	newFunction(t, function uword(MDThread* t, uword numParams) { pushInt(t, bytesAllocated(getVM(t))); return 1; }, "totalBytes");
	newGlobal(t, "totalBytes");

	version(TestArc)
		ArcLib.init(t);
		
	{
		WrapGlobals!
		(
			WrapType!
			(
				A, "A",
				WrapCtors!(void function(int)),
				WrapProperty!(A.x),
				WrapMethod!(A.fork)
			)
		)(t);
	}

	try
	{
		importModule(t, "samples.simple");
		pushNull(t);
		lookup(t, "modules.runMain");
		swap(t, -3);
		rawCall(t, -3, 0);
	}
	catch(MDException e)
	{
		auto ex = catchException(t);
		Stdout.formatln("Error: {}", e);

		auto tb = getTraceback(t);
		Stdout.formatln("{}", getString(t, tb));
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

class A
{
	int mX;
	
	this(int x)
	{
		mX = x;
	}
	
	int x() { return mX; }
	
	A fork(A a)
	{
		return a;
	}
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
			"arc.draw.color",

			WrapType!
			(
				Color,
				"Color",
				WrapCtors!
				(
					void function(int, int, int),
					void function(int, int, int, int),
					void function(float, float, float),
					void function(float, float, float, float)
				),

				WrapMethod!(Color.setR),
				WrapMethod!(Color.setG),
				WrapMethod!(Color.setB),
				WrapMethod!(Color.setA),
				WrapMethod!(Color.getR),
				WrapMethod!(Color.getG),
				WrapMethod!(Color.getB),
				WrapMethod!(Color.getA),
				WrapMethod!(Color.setGLColor)
			)
		)(t);

		WrapModule!
		(
			"arc.draw.image",
			WrapFunc!(arc.draw.image.drawImage),
			WrapFunc!(arc.draw.image.drawImageTopLeft),
			WrapFunc!(arc.draw.image.drawImageSubsection)
		)(t);

		WrapModule!
		(
			"arc.draw.shape",
			WrapFunc!(arc.draw.shape.drawPixel),
			WrapFunc!(arc.draw.shape.drawLine),
			WrapFunc!(arc.draw.shape.drawCircle),
			WrapFunc!(arc.draw.shape.drawRectangle),
			WrapFunc!(arc.draw.shape.drawPolygon)
		)(t);

		WrapModule!
		(
			"arc.font",
			WrapFunc!(arc.font.open),
			WrapFunc!(arc.font.close),
			
			WrapNamespace!
			(
				"LCDFilter",
				WrapValue!("Standard", LCDFilter.Standard),
				WrapValue!("Crisp", LCDFilter.Crisp),
				WrapValue!("None", LCDFilter.None)
			),

			WrapType!
			(
				Font,
				"Font",
				WrapCtors!(void function(char[], int)),

				WrapMethod!(Font.getWidth!(char)),
				WrapMethod!(Font.getWidthLastLine!(char)),
				WrapMethod!(Font.getHeight),
				WrapMethod!(Font.getLineSkip),
				WrapMethod!(Font.setLineGap),
				WrapMethod!(Font.draw, void function(char[], Point, Color)),
				WrapMethod!(Font.calculateIndex!(char)),
				WrapMethod!(Font.searchIndex!(char)),
				WrapMethod!(Font.lcdFilter)
			)
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

		WrapModule!
		(
			"arc.math.point",

			WrapType!
			(
				Point,
				"Point",
				WrapCtors!
				(
					// only the (float, float) ctor actually exists.
					// we're abusing the binding lib to perform autoconversion of ints to floats for this ctor ;)
					void function(float, float),
					void function(float, int),
					void function(int, float),
					void function(int, int)
				),

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
			"arc.math.rect",
			WrapType!
			(
				Rect,
				"Rect",
				WrapCtors!
				(
					void function(float, float, float, float),
					void function(Point, Size),
					void function(Size),
					void function(float, float)
				),

				WrapMethod!(Rect.getBottomRight),
				WrapMethod!(Rect.getTop),
				WrapMethod!(Rect.getLeft),
				WrapMethod!(Rect.getBottom),
				WrapMethod!(Rect.getRight),
				WrapMethod!(Rect.getPosition),
				WrapMethod!(Rect.getSize),
				WrapMethod!(Rect.move),
				WrapMethod!(Rect.contains),
				WrapMethod!(Rect.intersects)
			)
		)(t);

		WrapModule!
		(
			"arc.math.size",
			WrapType!
			(
				Size, 
				"Size",
				WrapCtors!(void function(float, float)),

				WrapMethod!(Size.set),
				WrapMethod!(Size.toString, "toString"),
				WrapMethod!(Size.maxComponent),
				WrapMethod!(Size.minComponent),
				WrapMethod!(Size.opNeg),
				WrapMethod!(Size.scale),
				WrapMethod!(Size.abs),
				WrapMethod!(Size.absCopy),
				WrapMethod!(Size.clamp),
				WrapMethod!(Size.randomise, "randomize"),
				WrapMethod!(Size.getWidth),
				WrapMethod!(Size.getHeight),
				WrapMethod!(Size.setWidth),
				WrapMethod!(Size.setHeight),
				WrapMethod!(Size.addW),
				WrapMethod!(Size.addH)
			)
		)(t);
		
		WrapModule!
		(
			"arc.sound",
			WrapFunc!(arc.sound.open),
			WrapFunc!(arc.sound.close),
			WrapFunc!(arc.sound.process),
			WrapFunc!(arc.sound.on),
			WrapFunc!(arc.sound.off),
			WrapFunc!(arc.sound.isSoundOn),

			WrapType!
			(
				Sound,
				"Sound",
				WrapCtors!(void function(SoundFile)),

				WrapMethod!(Sound.getSound),
				WrapMethod!(Sound.setSound),
				WrapMethod!(Sound.setGain),
				WrapMethod!(Sound.getPitch),
				WrapMethod!(Sound.setPitch),
				WrapMethod!(Sound.getVolume),
				WrapMethod!(Sound.setVolume),
				WrapMethod!(Sound.getLooping),
				WrapMethod!(Sound.setLoop),
				WrapMethod!(Sound.getPaused),
				WrapMethod!(Sound.setPaused),
				WrapMethod!(Sound.play),
				WrapMethod!(Sound.pause),
				WrapMethod!(Sound.seek),
				WrapMethod!(Sound.tell),
				WrapMethod!(Sound.stop),
				WrapMethod!(Sound.updateBuffers),
				WrapMethod!(Sound.process)
			),

			WrapType!
			(
				SoundFile,
				"SoundFile",
				WrapCtors!(void function(char[])),

				WrapMethod!(SoundFile.getFrequency),
				WrapMethod!(SoundFile.getBuffers, "getBuffersList", uint[] function()),
				WrapMethod!(SoundFile.getBuffersLength),
				WrapMethod!(SoundFile.getBuffersPerSecond),
				WrapMethod!(SoundFile.getLength),
				WrapMethod!(SoundFile.getSize),
				WrapMethod!(SoundFile.getSource),
				WrapMethod!(SoundFile.getBuffers, uint[] function(int, int)),
				WrapMethod!(SoundFile.allocBuffers),
				WrapMethod!(SoundFile.freeBuffers),
				WrapMethod!(SoundFile.print)
			)
		)(t);

		WrapModule!
		(
			"arc.texture",
			WrapFunc!(arc.texture.incrementTextureCount),
			WrapFunc!(arc.texture.assignTextureID),
			WrapFunc!(arc.texture.load),
			WrapFunc!(arc.texture.enableTexturing),

			WrapType!
			(
				arc.texture.Texture,
				"Texture",
				WrapCtors!
				(
					void function(char[]),
					void function(Size, Color)
				),

				WrapMethod!(arc.texture.Texture.getID),
				WrapMethod!(arc.texture.Texture.getFile),
				WrapMethod!(arc.texture.Texture.getSize),
				WrapMethod!(arc.texture.Texture.getTextureSize)
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
			WrapFunc!(arc.window.getSize),
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
				WrapFunc!(arc.window.coordinates.setSize),
				WrapFunc!(arc.window.coordinates.setOrigin),
				WrapFunc!(arc.window.coordinates.getSize),
				WrapFunc!(arc.window.coordinates.getOrigin),
				WrapFunc!(arc.window.coordinates.getWidth),
				WrapFunc!(arc.window.coordinates.getHeight)
			)
		)(t);
	}
}

}