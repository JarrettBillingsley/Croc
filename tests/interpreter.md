module tests.interpreter;

class A
{
	foo;

	function opAdd() { return this; }
	function opNeg() { return this; }
	function opAddAssign() {}
	function opAnd() { return this; }
	function opCom() { return this; }
	function opAndAssign() {}
	function opCmp() { return 0; }
	function opIn() { return true; }
	function opLength() { return 0; }
	function opSlice() { return this; }
	function opSliceAssign() {}
	function opCat() { return this; }
	function opCatAssign() {}
}

class B
{
	function opCmp() { return "NOWAI"; }
}

class C {}

// binOp
local x = 5;
local y = 10;
local z = x + y;
z = x - y;
z = x * y;
z = x / y;
z = x % y;
z = x + 1.0;
z = x - 1.0;
z = x * 1.0;
z = x / 1.0;
z = x % 1.0;
z = 1.0 * x;
z = toFloat(x) * 1.0;
try z = x / 0; catch(e){}
try z = x % 0; catch(e){}
z = A() + x;
try z = B() + x; catch(e){}

// unOp
z = -x;
z = -toFloat(x);
z = -A();
try z = -B(); catch(e){}

// reflOp
z = 0;
z += y;
z -= y;
z *= y;
z /= y;
z %= y;
z += 1.0;
z -= 1.0;
z *= 1.0;
z /= 1.0;
z %= 1.0;
z = 1.0;
z *= x;
z *= 1.0;
z = 1;
try z /= 0; catch(e){}
try z %= 0; catch(e){}
z = A();
z += 3;
z = B();
try z += x; catch(e){}

// binaryBinOp
x = 5;
y = 10;
z = x & y;
z = x | y;
z = x ^ y;
z = x << y;
z = x >> y;
z = x >>> y;
z = A() & x;
try z = B() & x; catch(e){}

// binaryUnOp
z = ~x;
z = ~A();
try z = ~B(); catch(e){}

// reflOp
z = 0;
z &= y;
z |= y;
z ^= y;
z <<= y;
z >>= y;
z >>>= y;
z = A();
z &= 3;
z = B();
try z &= x; catch(e){}

// comparison
x = 3;
y = 4.5;
z = x < 3;
z = x < y;
z = y < 3;
z = y < 3.5;
x = null;
z = x == null;
x = true;
z = x == true;
x = 'h';
z = x == 'h';
x = "hi";
z = x == "hi";
y = (x ~ "bye")[0 .. 2];
z = y == "hi";
x = A();
z = x == A();
z = x == 5;
x = B();
try z = x == B(); catch(e){}
try z = x == 5; catch(e){}
try z = C() == 5; catch(e){}

// in
x = "hello";
z = 'h' in x;
z = 'h' !in x;
try z = 5 in x; catch(e){}
x = [1, 2, 3];
z = 2 in x;
x = {x = 5};
z = "x" in x;
x = namespace foo { x = 5; };
z = "x" in x;
try z = 5 in x; catch(e){}
z = 5 in A();
try z = 5 in B(); catch(e){}

// length
x = "hi";
z = #x;
x = [1, 2, 3];
z = #x;
x = A();
z = #x;
try z = #A; catch(e){}

// index
x = [1, 2, 3];
z = x[0];
z = x[-1];
try z = x[10]; catch(e){}
try z = x['h']; catch(e){}
x = "hi";
z = x[0];
z = x[-1];
z = x[-1];
try z = x[10]; catch(e){}
try z = x['h']; catch(e){}
x = {x = 5};
z = x.x;
z = x.y;
x.opIndex = function(){};
z = x.y;
try z = x[null]; catch(e){}
x = A();
z = x.foo;
try z = x['h']; catch(e){}
try z = x.y; catch(e){}
x = A;
z = x.foo;
try z = x['h']; catch(e){}
try z = x.y; catch(e){}
x = namespace X { foo; };
z = x.foo;
try z = x['h']; catch(e){}
try z = x.y; catch(e){}
x = 5;
try z = x[5]; catch(e){}

// index assign
x = [1, 2, 3];
x[0] = 5;
x[-1] = 5;
try x[10] = 5; catch(e){}
try x['h'] = 5; catch(e){}
x = {x = 5};
x.x = 5;
x.y = 5;
x.y = null;
x.opIndexAssign = function(){};
x.y = 5;
try x[null] = 5; catch(e){}
x = A();
x.foo = 5;
try x['h'] = 5; catch(e){}
try x.y = 5; catch(e){}
x = A;
x.foo = 5;
try x['h'] = 5; catch(e){}
x = namespace X { foo; };
x.foo = 5;
try x['h'] = 5; catch(e){}
x = 5;
try x[5] = 5; catch(e){}

// slice
x = [1, 2, 3];
z = x[..];
z = x[..1];
z = x[-1..];
z = x[..-1];
try z = x['a'..]; catch(e){}
try z = x[..'a']; catch(e){}
try z = x[101259 .. 12058901]; catch(e){}
x = "hello";
z = x[..];
z = x[..1];
z = x[-1..];
z = x[..-1];
try z = x['a'..]; catch(e){}
try z = x[..'a']; catch(e){}
try z = x[101259 .. 12058901]; catch(e){}
x = A();
z = x[..];

// slice assign
x = [1, 2, 3];
x[..] = 5;
x[..1] = 5;
x[-1..] = 5;
x[..-1] = 5;
x[..] = [4, 5, 6];
try x['a'..] = 5; catch(e){}
try x[..'a'] = 5; catch(e){}
try x[101259 .. 12058901] = 5; catch(e){}
try x[..] = []; catch(e){}
x = A();
x[..] = 5;

// method lookup
x = A();
x.opIn();
try x.oasf(); catch(e){}
x = { function foo(){} };
x.foo();
try x.oasf(); catch(e){}
x = namespace X { function foo(){} };
x.foo();
try x.oasf(); catch(e){}
x = A;
x.opIn();
try x.oasf(); catch(e){}
x = 5;
try x.foo(); catch(e){}
x = [];
x.sort();

// cat
x = [1, 2, 3];
z = x ~ 5;
x = "hi";
try z = x ~ 5; catch(e){}
z = 3 ~ 4;
x = A();
z = x ~ 5;

// cat assign
x = [1, 2, 3];
x ~= 5;
x = "hi";
x ~= 'c';
try x ~= 5; catch(e){}
x = A();
x ~= 5;
x = B();
try x ~= 5; catch(e){}

// etc
global XX = 5;
XX = 10;
z = null;
z ?= 5;
z ?= 5;
try global XX = 10; catch(e){}
z = !x;
x = 5;
z = x < 10;
z = x <= 10;
z = x == 10;
z = x > 10;
z = x >= 10;
z = x != 10;
z = x <=> 10;
z = x is 10;
z = x !is 10;
if(x){}else{}
if(!x){}else{}

for(i: 0 .. 10, 3){}
for(i: 0 .. 10, -3){}
for(i: 10 .. 0){}
x = 0;
try for(i: 0 .. 10, x){} catch(e){}
x = null;
try for(i: x .. x){} catch(e){}

switch(5) { case 5: break; }
switch(5) { case 0: default: break; }
try switch(5) { case 3: break; } catch(e){}

try{}catch(e){}finally{}
try try throw "hi!"; finally{} catch(e){}

(function()
{
	try
		return 5;
	finally {}
})();

(function()
{
	try
		try
			return 5;
		finally {}
	finally {}
})();

function F(vararg)
{
	local x, y = vararg;
	return vararg;
}

A.opIn(F());
F(F(5));
F(with null);

x = [1, F(5)];
x = 5 ~ F(5);
x = [];
x ~= F(5);

x = class : A{};
try x = class : 5 {}; catch(e){}

x = namespace X {};
z = namespace Z : x {};
try z = namespace Z : 5 {}; catch(e){}

x = A();
z = x as A;
z = x as B;
y = 0;
try z = x as y; catch(e){}
z = x.super;
z = A.super;
try z = "hi".super; catch(e){}
z = x.class;
try z = "hi".class; catch(e){}

function Foo()
{
	local asf = x;

	function bar()
	{
		return asf + x;
	}

	return bar;
}

Foo();

x = coroutine function()
{
	yield(5);
	yield(F());
};

x();
x();

try y = coroutine 5; catch(e){}

x = coroutine function()
{
	(class
	{
		function opIndexAssign()
		{
			yield(5);
		}
	})()[5] = 10;
};

try x(); catch(e){}

try
	return;
finally {}