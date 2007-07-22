module test;

import minid.minid;
import minid.bind;
import tango.io.Stdout;

void main()
{
	try
	{
		MDState s = MDInitialize();
		MDGlobalState().addImportPath(`samples`);

		/*WrapModule!
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
		);

		WrapGlobalFunc!(one, "One");
		WrapGlobalFunc!(two, void function(int, int));*/

		MDGlobalState().importModule("simple");
	}
	catch(MDException e)
	{
		Stdout.formatln("Error: {}", e.toUtf8());
		Stdout.formatln("{}", MDState.getTracebackString());
	}
	catch(Exception e)
	{
		Stdout.formatln("Bad error ({}, {}): {}", e.file, e.line, e.toUtf8());
		Stdout.formatln("{}", MDState.getTracebackString());
	}
}

/*
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
}*/