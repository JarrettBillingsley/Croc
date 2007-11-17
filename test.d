module test;

import minid.minid;
import minid.types;
import minid.bind;
import tango.io.Stdout;

import arc.draw.color;
import arc.window;
import arc.font;
import arc.input;
import arc.time;
import arc.math.point;

void printFoo()
{
	Stdout.formatln("foo!");
}

void main()
{
	MDContext ctx;

	try
	{
		ctx = NewContext();
		LoadArc(ctx);
		WrapGlobalFunc!(printFoo)(ctx);

		ctx.addImportPath(`samples`);
		ctx.importModule("simple");
	}
	catch(MDException e)
	{
		Stdout.formatln("Error: {}", e.toUtf8());
		Stdout.formatln("{}", ctx.getTracebackString());
	}
	catch(Exception e)
	{
		Stdout.formatln("Bad error ({}, {}): {}", e.file, e.line, e.toUtf8());
		Stdout.formatln("{}", ctx.getTracebackString());
	}
}

void LoadArc(MDContext ctx)
{
	WrapModule("arc.window", ctx)
		.func!(arc.window.open)()
		.func!(arc.window.close)()
		.func!(arc.window.clear)()
		.func!(arc.window.swap)();

	WrapModule("arc.input", ctx)
		.func!(arc.input.open)()
		.func!(arc.input.close)()
		.func!(arc.input.process)()
		.func!(arc.input.keyDown)()
		.func!(arc.input.mouseX)()
		.func!(arc.input.mouseY)()
		.func!(arc.input.mousePos)()
		.custom("key", MDTable.create
		(
			"Quit", ARC_QUIT,
			"Up", ARC_UP,
			"Down", ARC_DOWN,
			"Left", ARC_LEFT,
			"Right", ARC_RIGHT,
			"Esc", ARC_ESCAPE
		));

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

	WrapModule("arc.math.point", ctx)
		.type(WrapClass!(Point, void function(float, float))()
			.method!(Point.set)()
			.method!(Point.angle)()
			.method!(Point.length)()
			.method!(Point.toUtf8, "toString")()
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
}