module test;

import minid.minid;
import minid.types;
import minid.bind;
import tango.io.Stdout;

//version = Arc;

void main()
{
	MDContext ctx;

	try
	{
		ctx = NewContext();

		version(Arc)
			LoadArc(ctx);

		ctx.addImportPath(`samples`);
		ctx.importModule("speed");
	}
	catch(MDException e)
	{
		Stdout.formatln("Error: {}", e.toString());
		Stdout.formatln("{}", ctx.getTracebackString());
	}
	catch(Exception e)
	{
		Stdout.formatln("Bad error ({}, {}): {}", e.file, e.line, e.toString());
		Stdout.formatln("{}", ctx.getTracebackString());
	}
}

version(Arc)
{

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
import arc.window;

void LoadArc(MDContext ctx)
{
	static class MyTexture
	{
		private arc.texture.Texture mTex;

		public this(char[] filename)
		{
			mTex = Texture(filename);
		}

		public this(Size size, Color color)
		{
			mTex = Texture(size, color);
		}

		public Size getSize()
		{
			return mTex.getSize();
		}
		
		public Size getTextureSize()
		{
			return mTex.getTextureSize();
		}

		uint getID()
		{
			return mTex.getID();
		}

		char[] getFile()
		{
			return mTex.getFile();
		}
	}

	static void myEnableTexturing(MyTexture t)
	{
		arc.texture.enableTexturing(t.mTex);
	}
	
	static void myDrawImage(MyTexture t, Point pos, Size size = Size(float.nan, float.nan), Point piv = Point(0, 0), float angle = 0, Color color = Color.White)
	{
		arc.draw.image.drawImage(t.mTex, pos, size, piv, angle, color);
	}

	static void myDrawImageTopLeft(MyTexture t, Point pos, Size size = Size(float.nan, float.nan), Color color = Color.White)
	{
		arc.draw.image.drawImageTopLeft(t.mTex, pos, size, color);
	}

	static void myDrawImageSubsection(MyTexture t, Point pos, Point rightBottom, Color color = Color.White)
	{
		arc.draw.image.drawImageSubsection(t.mTex, pos, rightBottom, color);
	}

	WrapModule("arc.draw.color", ctx)
		.type(WrapClass!(Color,
				void function(int, int, int),
				void function(int, int, int, int),
				void function(float, float, float),
				void function(float, float, float, float))()
			.method!(Color.setR)()
			.method!(Color.setG)()
			.method!(Color.setB)()
			.method!(Color.setA)()
			.method!(Color.getR)()
			.method!(Color.getG)()
			.method!(Color.getB)()
			.method!(Color.getA)()
			.method!(Color.setGLColor)());
			
	WrapModule("arc.draw.image", ctx)
		.func!(myDrawImage, "drawImage")()
		.func!(myDrawImageTopLeft, "drawImageTopLeft")()
		.func!(myDrawImageSubsection, "drawImageSubsection")();
		
	WrapModule("arc.draw.shape", ctx)
		.func!(arc.draw.shape.drawPixel)()
		.func!(arc.draw.shape.drawLine)()
		.func!(arc.draw.shape.drawCircle)()
		.func!(arc.draw.shape.drawRectangle)();
		//.func!(arc.draw.shape.drawPolygon)();

	WrapModule("arc.font", ctx)
		.func!(arc.font.open)()
		.func!(arc.font.close)()
		.type(WrapClass!(Font, void function(char[], int))()
			.method!(Font.getWidth!(dchar))()
			.method!(Font.getWidthLastLine!(dchar))()
			.method!(Font.getHeight)()
			.method!(Font.getLineSkip)()
			.method!(Font.setLineGap)()
			.method!(Font.draw, void function(dchar[], Point, Color))()
			.method!(Font.calculateIndex!(dchar))());

	WrapModule("arc.input", ctx)
		.func!(arc.input.open)()
		.func!(arc.input.close)()
		.func!(arc.input.process)()
		.func!(arc.input.setKeyboardRepeat)()
		.func!(arc.input.keyPressed)()
		.func!(arc.input.keyReleased)()
		.func!(arc.input.keyDown)()
		.func!(arc.input.keyUp)()
		.func!(arc.input.charHit)()
		.func!(arc.input.lastChars)()
		.func!(arc.input.mouseButtonPressed)()
		.func!(arc.input.mouseButtonReleased)()
		.func!(arc.input.mouseButtonDown)()
		.func!(arc.input.mouseButtonUp)()
		.func!(arc.input.mouseX)()
		.func!(arc.input.mouseY)()
		.func!(arc.input.mousePos)()
		.func!(arc.input.mouseOldX)()
		.func!(arc.input.mouseOldY)()
		.func!(arc.input.mouseOldPos)()
		.func!(arc.input.mouseMotion)()
		.func!(arc.input.defaultCursorVisible)()
		.func!(arc.input.wheelUp)()
		.func!(arc.input.wheelDown)()
		.type(WrapClass!(JoystickException, void function(char[]))())
		.func!(arc.input.numJoysticks)()
		.func!(arc.input.openJoysticks)()
		.func!(arc.input.closeJoysticks)()
		.func!(arc.input.joyButtonDown)()
		.func!(arc.input.joyButtonUp)()
		.func!(arc.input.joyButtonPressed)()
		.func!(arc.input.joyButtonReleased)()
		.func!(arc.input.joyAxisMoved)()
		.func!(arc.input.numJoystickButtons)()
		.func!(arc.input.numJoystickAxes)()
		.func!(arc.input.joystickName)()
		.func!(arc.input.isJoystickOpen)()
		.func!(arc.input.setAxisThreshold)()
		.func!(arc.input.lostFocus)()
		.func!(arc.input.quit)()
		.func!(arc.input.isQuit)()
		.custom("key", MDTable.create
		(
			"Quit", ARC_QUIT,
			"Up", ARC_UP,
			"Down", ARC_DOWN,
			"Left", ARC_LEFT,
			"Right", ARC_RIGHT,
			"Esc", ARC_ESCAPE
		))
		.custom("mouse", MDTable.create
		(
			"Any", ANYBUTTON,
			"Left", LEFT,
			"Middle", MIDDLE,
			"Right", RIGHT,
			"WheelUp", WHEELUP,
			"WheelDown", WHEELDOWN
		));

	WrapModule("arc.math.point", ctx)
		.type(WrapClass!(Point, void function(float, float))()
			.method!(Point.set)()
			.method!(Point.angle)()
			.method!(Point.length)()
			.method!(Point.toString, "toString")()
			.method!(Point.maxComponent)()
			.method!(Point.minComponent)()
			.method!(Point.opNeg)()
			.method!(Point.cross)()
			.method!(Point.dot)()
			.method!(Point.scale)()
			// apply
			.method!(Point.lengthSquared)()
			.method!(Point.normalise, "normalize")()
			.method!(Point.normaliseCopy, "normalizeCopy")()
			.method!(Point.rotate)()
			.method!(Point.rotateCopy)()
			.method!(Point.abs)()
			.method!(Point.absCopy)()
			.method!(Point.clamp)()
			.method!(Point.randomise, "randomize")()
			.method!(Point.distance)()
			.method!(Point.distanceSquared)()
			.method!(Point.getX)()
			.method!(Point.getY)()
			.method!(Point.setX)()
			.method!(Point.setY)()
			.method!(Point.addX)()
			.method!(Point.addY)()
			.method!(Point.above)()
			.method!(Point.below)()
			.method!(Point.left)()
			.method!(Point.right)());
			
	WrapModule("arc.math.rect", ctx)
		.type(WrapClass!(Rect,
				void function(float, float, float, float),
				void function(Point, Size),
				void function(Size),
				void function(float, float))()
			.method!(Rect.getBottomRight)()
			.method!(Rect.getTop)()
			.method!(Rect.getLeft)()
			.method!(Rect.getBottom)()
			.method!(Rect.getRight)()
			.method!(Rect.getPosition)()
			.method!(Rect.getSize)()
			.method!(Rect.move)()
			.method!(Rect.contains)()
			.method!(Rect.intersects)());

	WrapModule("arc.math.size", ctx)
		.type(WrapClass!(Size, void function(float, float))()
			.method!(Size.set)()
			.method!(Size.toString, "toString")()
			.method!(Size.maxComponent)()
			.method!(Size.minComponent)()
			.method!(Size.opNeg)()
			.method!(Size.scale)()
			.method!(Size.abs)()
			.method!(Size.absCopy)()
			.method!(Size.clamp)()
			.method!(Size.randomise, "randomize")()
			.method!(Size.getWidth)()
			.method!(Size.getHeight)()
			.method!(Size.setWidth)()
			.method!(Size.setHeight)()
			.method!(Size.addW)()
			.method!(Size.addH)());

	WrapModule("arc.sound", ctx)
		.func!(arc.sound.open)()
		.func!(arc.sound.close)()
		.func!(arc.sound.process)()
		.func!(arc.sound.on)()
		.func!(arc.sound.off)()
		.func!(arc.sound.isSoundOn)()
		.type(WrapClass!(Sound, void function(SoundFile))()
			.method!(Sound.getSound)()
			.method!(Sound.setSound)()
			.method!(Sound.setGain)()
			.method!(Sound.getPitch)()
			.method!(Sound.setPitch)()
			.method!(Sound.getVolume)()
			.method!(Sound.setVolume)()
			.method!(Sound.getLooping)()
			.method!(Sound.setLoop)()
			.method!(Sound.getPaused)()
			.method!(Sound.setPaused)()
			.method!(Sound.play)()
			.method!(Sound.pause)()
			.method!(Sound.seek)()
			.method!(Sound.tell)()
			.method!(Sound.stop)()
			.method!(Sound.updateBuffers)()
			.method!(Sound.process)())
		.type(WrapClass!(SoundFile, void function(char[]))()
			.method!(SoundFile.getFrequency)()
			.method!(SoundFile.getBuffers, "getBuffersList", uint[] function())()
			.method!(SoundFile.getBuffersLength)()
			.method!(SoundFile.getBuffersPerSecond)()
			.method!(SoundFile.getLength)()
			.method!(SoundFile.getSize)()
			.method!(SoundFile.getSource)()
			.method!(SoundFile.getBuffers, uint[] function(int, int))()
			.method!(SoundFile.allocBuffers)()
			.method!(SoundFile.freeBuffers)()
			.method!(SoundFile.print)());

	WrapModule("arc.texture", ctx)
		.func!(arc.texture.incrementTextureCount)()
		.func!(arc.texture.assignTextureID)()
		.func!(arc.texture.load)()
		.func!(myEnableTexturing, "enableTexturing")()
		.type("Texture", WrapClass!(MyTexture,
				void function(char[]),
				void function(Size, Color))()
			.method!(MyTexture.getID)()
			.method!(MyTexture.getFile)()
			.method!(MyTexture.getSize)()
			.method!(MyTexture.getTextureSize)());

	WrapModule("arc.time", ctx)
		.func!(arc.time.open)()
		.func!(arc.time.close)()
		.func!(arc.time.process)()
		.func!(arc.time.sleep)()
		.func!(arc.time.elapsedMilliseconds)()
		.func!(arc.time.elapsedSeconds)()
		.func!(arc.time.fps)()
		.func!(arc.time.limitFPS)()
		.func!(arc.time.getTime)();

	MDNamespace coordinates = new MDNamespace("coordinates");
	
	with(arc.window.coordinates)
	{
		WrapFunc!(setSize)(coordinates);
		WrapFunc!(setOrigin)(coordinates);
		WrapFunc!(getSize)(coordinates);
		WrapFunc!(getWidth)(coordinates);
		WrapFunc!(getHeight)(coordinates);
		WrapFunc!(getOrigin)(coordinates);
	}

	WrapModule("arc.window", ctx)
		.func!(arc.window.open)()
		.func!(arc.window.close)()
		.func!(arc.window.getWidth)()
		.func!(arc.window.getHeight)()
		.func!(arc.window.getSize)()
		.func!(arc.window.isFullScreen)()
		.func!(arc.window.resize)()
		.func!(arc.window.toggleFullScreen)()
		.func!(arc.window.clear)()
		.func!(arc.window.swap)()
		.func!(arc.window.swapClear)()
		.func!(arc.window.screenshot)()
		.custom("coordinates", coordinates);
}

}