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

void main()
{
	MDContext ctx;

	try
	{
		ctx = NewContext();

		/+/*
		ctx.globals["Co"d] = new MDClosure(ctx.globals.ns, (MDState s, uint numParams)
		{
			with(s)
			{
				Stdout.formatln("Co has begun with Params: {}, {}", getParam!(int)(0), getParam!(int)(1));
				yield(2, MDValue("I've begun"));

				MDValue r2 = pop();
				MDValue r1 = pop();

				Stdout.formatln("Back in co, main gave me: {}, {}", valueToString(r1), valueToString(r2));
				yield(0, MDValue("Thanks for the values"));
				Stdout.formatln("Co is about to return, bye");
				push("I'm finished");
				return 1;
			}
		}, "Co"d);*/

		WrapModule!
		(
			"bar",
			WrapFunc!(foo),
			WrapFunc!(average),
			WrapFunc!(something),
			WrapFunc!(blah),
			WrapFunc!(over, "overInt", void function(int)),
			WrapFunc!(over, "overFloat", void function(float)),

			WrapClassEx!
			(
				A,
				WrapMethod!(A.foo),
				WrapMethod!(A.takesAnA),
				WrapMethod!(A.returnsAnA),
				WrapProperty!(A.size),
				WrapProperty!(A.ID)
			),

			WrapClass!(B),

			WrapClassEx!
			(
				C,
				WrapCtors!(void function(int), void function(float), void function(char[]), void function(int, float), void function(A))
			)
		)(ctx);

		WrapGlobalFunc!(one, "One")(ctx);
		WrapGlobalFunc!(two, void function(int, int))(ctx);+/

		WrapModule!
		(
			"arc.window",
			WrapFunc!(arc.window.open),
			WrapFunc!(arc.window.close),
			WrapFunc!(arc.window.clear),
			WrapFunc!(arc.window.swap)
		)(ctx);
		
		static MDTable initKey()
		{
			return MDTable.create
			(
				"Quit", ARC_QUIT,
				"Up", ARC_UP,
				"Down", ARC_DOWN,
				"Left", ARC_LEFT,
				"Right", ARC_RIGHT,
				"Esc", ARC_ESCAPE
			);
		}

		WrapModule!
		(
			"arc.input",
			WrapFunc!(arc.input.open),
			WrapFunc!(arc.input.close),
			WrapFunc!(arc.input.process),
			WrapFunc!(arc.input.keyDown),
			WrapFunc!(arc.input.mouseX),
			WrapFunc!(arc.input.mouseY),
			WrapFunc!(arc.input.mousePos),
			WrapCustom!("key", initKey)
		)(ctx);
		
		WrapModule!
		(
			"arc.font",
			WrapFunc!(arc.font.open),
			WrapFunc!(arc.font.close),
			WrapClassEx!
			(
				arc.font.Font,
				WrapCtors!(void function(char[], int)),
				WrapMethod!(Font.draw)
			)
		)(ctx);

		WrapModule!
		(
			"arc.math.point",
			WrapStruct!
			(
				Point, "Point",
				WrapCtors!(void function(float, float)),
				WrapMethod!(Point.set),
				WrapMethod!(Point.angle),
				WrapMethod!(Point.length),
				WrapMethod!(Point.toUtf8, "toString"),
				WrapMethod!(Point.maxComponent),
				WrapMethod!(Point.minComponent),
				WrapMethod!(Point.opNeg),
				// cross, dot
				WrapMethod!(Point.scale),
				// apply
				WrapMethod!(Point.lengthSquared),
				WrapMethod!(Point.normalise, "normalize"),
				WrapMethod!(Point.normaliseCopy, "normalizeCopy"),
				// angle
				WrapMethod!(Point.rotate),
				WrapMethod!(Point.abs),
				WrapMethod!(Point.absCopy),
				// clamp
				WrapMethod!(Point.randomise, "randomize"),
				// distance, distanceSquared
				WrapMethod!(Point.rotateCopy),
				WrapMethod!(Point.getX),
				WrapMethod!(Point.getY),
				WrapMethod!(Point.setX),
				WrapMethod!(Point.setY),
				WrapMethod!(Point.addX),
				WrapMethod!(Point.addY)
			)
		)(ctx);

		WrapModule!
		(
			"arc.draw.color",
			WrapStruct!
			(
				Color, "Color",
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
		)(ctx);

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
		)(ctx);

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

enum E
{
	One,
	Two,
	Three	
}

class A
{
	private int mSize = 10;

	public this()
	{
		Stdout("A ctor!").newline;
	}

	public void foo(int x, int y = 10)
	{
		Stdout.formatln("A foo: {}, {}", x, y);
	}

	public int size()
	{
		return mSize;
	}

	public void size(int s)
	{
		mSize = s;
	}
	
	public void takesAnA(A a)
	{
		if(a is null)
			Stdout.formatln("takesAnA, null");
		else
			Stdout.formatln("takesAnA, ID: {}", a.ID());
	}
	
	public A returnsAnA()
	{
		return new A();
	}

	public int ID()
	{
		return 5;
	}
}

class B : A
{
	public this()
	{
		Stdout("B ctor!").newline;
	}
	
	public int ID()
	{
		return 10;
	}
}

class C
{
	this()
	{
		Stdout.formatln("C nothing");
	}

	this(int x)
	{
		Stdout.formatln("C int: {}", x);
	}

	this(float x)
	{
		Stdout.formatln("C float: {}", x);
	}

	this(char[] s)
	{
		Stdout.formatln("C string: {}", s);
	}
	
	this(int x, float y)
	{
		Stdout.formatln("C int, float: {}, {}", x, y);
	}
	
	this(A a)
	{
		Stdout.formatln("C A: {}", a.ID());
	}
}

void foo(int x, int y = 10)
{
	Stdout.formatln("{}, {}", x, y);
}

int average(int[] values...)
{
	int sum = 0;
	
	foreach(val; values)
		sum += val;
		
	return sum / values.length;
}

void something(MDValue val)
{
	Stdout.formatln("val's type is {} and its value is {}", val.typeString(), val.toUtf8());
}

void* blah()
{
	return null;
}

void over(int x)
{
	Stdout("Int!").newline;
}

void over(float x)
{
	Stdout("Float!").newline;
}

void one(int x)
{
	Stdout.formatln("one!");
}

void two(float x, float y)
{
	Stdout.formatln("wrong two.");	
}

void two(int x, int y)
{
	Stdout.formatln("two!");
}

void three(float x)
{
	Stdout.formatln("three!");
}