#!/usr/bin/mdcl
@attrs({})
module tests.compiler.compiler
import FRACK = tests.dummy: xxx = XXX, YYY
import("tests.dummy")

function xpass(s: string)
{
	try
	{
		loadString(s)
		return
	}
	catch(e)
		throw "Expected to pass but failed"
}

function xfail(s: string)
{
	try
		loadString(s)
	catch(e)
		return

	throw "Expected to fail but passed"
}

function xfailex(s: string)
{
	try
		loadString(s)()
	catch(e)
		return

	throw "Expected to fail but passed"
}

// ast
class O {}
function foo(x = null, y = true, z = 'x') { return 1, 2, 3 }
namespace N {}
assert(true, "foo")
assert(true)
foo()
while(false){}
do{}while(false)
for(;false;){}
for(i: 0 .. 1){continue}
foreach(c; "x"){}
switch(4){case 4, 5: foo(); foo(); case true: default: break}
try{}catch(e){}finally{}
O = 4
O += 1
O -= 1
O *= 2
O /= 2
O %= 2
O |= O
O ^= O
O &= 1
O <<= 1
O >>= 1
O >>>= 1
O = O | 5
O = O & 5
O = O ^ 5
O = O << 5
O = O >> 5
O = O >>> 5
O = O - 5
O = O * 5
O = O / 5
O = O % 5
O = -O
O = ~O
O = !O
O = #"hi"
O++
O--
++O
--O
O = O + 5
xfail("O = 4 + 'x'")
xfailex("O = `hi` ~ 5")
O = "hi"
O ~= 'x'
O = O ~ 'x'
O ?= 0
O = namespace Neener{}
O = [i for i in 0 .. 3]
O[0] = O[0]
O[0 .. 1] = O[0 .. 1]
#O = 0
xfail("4 + 5")
xfail("x, y = 5")
xfail("5 += 6")
O = true ? 4 : 5
true ? foo() : foo()
true && foo()
false || foo()
O = 4 == 5
O = 4 != 5
O = 4 is 5
O = 4 !is 5
O = 4 < 5
O = 4 <= 5
O = 4 > 5
O = 4 >= 5
O = 4 <=> 5
O = Object as Object
O = 'x' in "hello"
O = 'x' !in "hello"
O = coroutine foo
O = class{}
O.x = 5
O.x = O.x
N = O.super
O, N = foo()
O = class{ function f(){ return this } }
O.f()
O.("f")()
O, N = O.f()
O = null
if(null){}
function bar(vararg){ local x, y = vararg; x = #vararg; x = vararg[0]; vararg[0] = x; x, y = vararg[] }
if(5){}
O = 5 + 4.5
if(4.5){}
if('x'){}
O = 'x' <=> 'y'
if("hi"){}
O = (4 + 5)
O = {}
function coro() { local x, y = yield(5); yield() }
O = [c for c in "hello"]
O = [c for c in "hello" if c < 'x']
O = [x for x in [1, 2, 3] for y in [1, 2, 3]]
O = [x for x in [1, 2, 3] for y in [1, 2, 3] if y == 1]
O = [i for i in 0 .. 10 for j in 0 .. 1]
O = [i for i in 0 .. 10 if i & 1]
O = {[k] = v for k, v in {}}

// lexer
xfail(`local x = {`)
O = "\u0fF9"
xfail("x = 11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111")
O = .3
O = 0b10_10
xfail("O = 0b3")
O = 0c247_72
xfail("O = 0c9")
O = 0x9_3502
xfail("O = 0xg")
O = [1, 2, 3][0..2]
O = 34_54
O = 0._4
O = 0.2
O = 0.3_3e-4_5
xfail("O = 0.3e")
xfail(`O = "\ugggg"`)
xfail(`O = "\`) /+ ` +/
O = "\a\b\f\n\r\t\v\\\"\'\x34\u0034\U00000034"
xfail(`O = "\/"`)
loadJSON(`["\/"]`)
xfail(`O = "\xFF"`)
xfail(`O = "\uFFFF`)
xfail(`O = "\U0000FFFF"`)
xfail(`O = "\UFFFFFFFF"`)
O = "\110"
xfail(`O = "\189"`)
xfail(`O = "`)
O = "o hai
there"
O = `hi ``there`
xfail("O = '")
xfail("O = 'x")
O = '\x34'
O = \->4
/*
aosfk*
*/
xfail("/*")
xfail("f() g()")
/+
aoskf /
/+ aoskf + aaskf +/
+/
xfail("/+")
@attrs({}) function brak() {}
O = @"hello"
xfail("__x = 5")

// parser
foo = function() {}
foo(1, 2, 3)
eval("4 + 5")
xfailex(`eval("4 + 5 5")`)
loadJSON("{}")
xfail("for(;;);")
xfail("while(false)")
xpass("@foo.bar.baz @quux function f() {}")
xpass("@foo(with 5, 2, 3) function f() {}")
xfail("@foo local x")
xpass("local function f(){} local class O{} local namespace N{}")
xfail("local for")
xfail("@foo for")
global function BRAK(){}
xfail("f = function(x, y) { greep }")
foo = function(this: int, x, vararg) = 5
xfail("f = function(x: int|int){}")
foo = function(x: instance A.B.C, y: null|function|namespace|class|instance){}
foo = function(x: instance(A), y: A.B, z: instance A){}
xfail("f = function(x: instance 4){}")
foo = function(x: bool|float|char|table|array|thread|nativeobj|weakref, y: A){}
foo = function freep(x: !null, y: any){}
xfail(`f = \x -> yield`)
xpass("global class O:I{ @foo function foo() {} }")
xfail("class O { x = 5; x }")
xfail("class O {")
xfail("class O {5}")
xpass("global namespace N:M{x; function y(){}}")
xfail("namespace N { x = 5; x }")
xfail("namespace N {")
xfail("namespace N {5}")
for(local x = 5, O = 0; false; x++, O++){}
for(i: 0 .. 10, 2){}
foreach(k, v; {}){}
xfail("foreach(k, v; {}){")
foreach(k, v; [], "reverse"){}
xfail("foreach(v; 1, 2, 3, 4){}")
if(local x = true){}else{}
xfail("return 3 return")
xfail("try{}")
while(local x = false){}
xpass(`x = super.foo(); super.("foo")(3); super.f $ 5, 5; y = :y`)
xpass(`:("x") = 5; :super.x = 5`)
xfail("++for")
loadJSON(`[null, true, false, 4, 4.5, [], {"x":5, "y":10}]`)
xfailex(`loadJSON("[freep]")`)
O = { function foo() {}, x = 5 }
O.foo $ 5, 10;
(O.foo) $ 5, 10
xfail("foo()
(bar)()")
O.foo(with 5, 20)
local A = [1, 2, 3, 4, 5]
A[] = A[..]
A[0..] = A[..5]
xfail("x = [x for x, y in 0 .. 10]")
A = [x for x in 0 .. 10, 3]
xfail("x = [x for x in `hello`, 4, 43, 2]")

// semantic
foo = function(x = freep(), y: int = 5, z = 4.5, w = "hai"){}
xfail("function foo(x: int = 'x'){}")
xfail("import(5)")
if(false){}else{}
if(foo is foo){}
while(true){break}
do{break}while(true)
for(;true;){break}
xfail("for(i: 4.5 .. 5){}")
xfail("for(i: 4 .. 5.5){}")
xfail("for(i: 4 .. 5, 4.5){}")
xfail("for(i: 4 .. 5, 0){}")
O ?= null
O = "hi"
O ~= 'x' ~ O
O = false ? 1 : 2
O = O ? O : O
O = true || true
O = false || false
O = O || O
O = true && true
O = false && false
O = O && O
O = 3 | 4
xfail("x = 3 | 4.5")
O = 3 ^ 4
xfail("x = 3 ^ 4.5")
O = 3 & 4
xfail("x = 3 & 4.5")
O = null is null
O = true is true
O = 3.4 is 3.4
O = 3.0 == 3
O = 'x' is 'x'
O = "hi" is "hi"
O = 3 is 'x'
xfail("x = 4 == null")
O = null < null
O = 3 < 4
O = 3 < 4.5
O = "x" < "y"
xfail("x = 4 < `u`")
O = O <=> O
O = O as Object
xfail("x = 4 as 5")
O = 3 << 4
xfail("x = 3 << 4.5")
O = 3 >> 4
xfail("x = 3 >> 4.5")
O = 3 >>> 4
xfail("x = 3 >>> 4.5")
O = 3 - 4
O = 3.4 - 4
xfail("x = 3 - 'x'")
O = 'x' ~ 'y' ~ 'z' ~ 'w'
O = 3 * 4
O = 3.4 * 4
xfail("x = 3 * 'x'")
O = 3 / 4
O = 3.4 / 4
xfail("x = 3 / 'x'")
xfail("x = 3 / 0")
O = 3 % 4
O = 3.4 % 4
xfail("x = 3 % 'x'")
xfail("x = 3 % 0")
O = -3
O = -3.4
xfail("x = -'x'")
O = !true
O = 5
A = !(3 < O)
A = !(3 <= O)
A = !(3 > O)
A = !(3 >= O)
A = !(3 == O)
A = !(3 != O)
A = !(3 is O)
A = !(3 !is O)
O = 'x'
A = !(O in "hello")
A = !(O !in "hello")
if(!(A && A)){}
if(!(A || A)){}
O = ~5
xfail("x = ~'x'")
xfail("x = #4")
xfail("x.(4) = 5")
xfail("x.(5)()")
xfail("x = 4[5]")
O = "hello"[3]
O = "hello"[-1]
xfail("x = `hello`[53]")
xfail("x = vararg['x']")
xfail("x = 4[5..6]")
O = "hello"[2 .. 4]
O = "hello"[-3 .. -1]
O = "hello"[]
xfail("x = `hello`[3 .. 235]")
xfail("x = vararg[3.4 ..]")
xfail("x = vararg[.. 3.4]")
O = (function(){}())
A = [x for k, v in {} if k !is null for i in 0 .. 10]
A = [x for k in 0 .. 0 if k !is null for i in 0 .. 10]

// codegen
xfail("local x; local x")
{ local function fork() { local a = []; for(i: 0 .. 10) a ~= \->i  } }
switch(5) { case null, 3.5, 'x', "hi": break; default: break; }
xfail("switch(5) { case 3: case 3: break; }")
{
	local z = 0;

	(function()
	{
		local x, y;
		foo = function() return 1, 2, 3;
		x = [0, 0, 0]
		y = 0
		x[y], y = foo()
		x[z], z = foo()
	})()
}
xpass("global x, y = foo(); x.x, y.x = foo(); vararg[x], vararg[y] = foo()")
xpass("arr[0 .. 10], arr[11 .. 20] = foo(); #arr1, #arr2 = foo()")
xpass("global x = false; global y = vararg[0]; global z = #a; global w = vararg")
xpass("global x = vararg[]; x = a[0]; x = #a; x = vararg; x = vararg[]")
xpass("local x; x = vararg; x = vararg[]; return foo()")
xfail("continue")
for(i: 0 .. 1) { local f = \->i; continue }
xfail("break")
for(i: 0 .. 1) { local f = \->i; break }
xfail("import foo = bar: foo = baz")
xfail("import foo: bar = baz, baz = qus")
xpass("import foo: bar, baz")
xfail("local x, x")
xpass("global x, y")
xpass("if(local x = foo()){}else{}")
xpass("while(local x = true){}while(local x = foo()){}while(foo()){}")
xpass("do{}while(foo())")
xpass("for(local x = 5, foo(); bar(); baz++, quux++){}")
xpass("foreach(k, v; a, b, c){}foreach(k, v; a, b()){}foreach(k, v; a()){}")
xpass("switch(4){case foo(): break;}")
xpass("return x, foo()")
xpass("try{}finally{}")
xfail("function foo() = #vararg")
xpass("foo(bar, baz())")
xfail("function foo() = vararg[0]")
xfail("function foo() = vararg[]")
xfail("function foo() = vararg")
xpass("a = [1, 2, foo()]")
xpass("yield(foo())")
xpass("if(x?y:z){}if(this){}if((foo())){}")
