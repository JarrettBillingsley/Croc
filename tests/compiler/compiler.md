#!/usr/bin/mdcl
module tests.compiler.compiler;
import tests.dummy : XXX, YYY;

loadString("");
loadString("return 0;");
try loadString("return"); catch(e){}
loadJSON("[]");
loadJSON("{}");
local x = 0;
x += 5;
try loadString("f(4 5)"); catch(e){}
try import("tests.compiler.badshebang"); catch(e){}
x = 0b0011;
x = 0x5f;
x = 0c37;
x = '\u00f1';
x = "hey"[0.. 1];
x = .5;
try loadString("x = 0b2;"); catch(e){}
try loadString("x = 0b1111111111111111111111111111111111111111111111111111;"); catch(e){}
try loadString("x = 0c8;"); catch(e){}
try loadString("x = 0c777777777777777777777777777777;"); catch(e){}
try loadString("x = 999999999999999999999999999;"); catch(e){}
try loadString("x = 0xfffffffffffffffffffffffffffff;"); catch(e){}
try loadString("x = 0x_f;"); catch(e){}
try loadString("x = 0xh;"); catch(e){}
x = 4._5_5;
try loadString("x = 4.;"); catch(e){}
x = 4e10;
x = 4e-10;
x = 4e_10;
try loadString("x = 4e;"); catch(e){}
try loadString("x = 999999999999e9999999999999999;"); catch(e){}
try loadString("x = 1.0e10000;"); catch(e){}
try loadString(`x = '\uzzzz';`); catch(e){}
x = "\a\b\f\n\r\t\v\\\"\'";
x = "\x4a\u1111\U00001111\123";
try loadString(`x = "\/";`); catch(e){}
try loadString(`x = "\xff`); catch(e){}
try loadString(`x = "\uffff";`); catch(e){}
try loadString(`x = "\U0000ffff";`); catch(e){}
try loadString(`x = "\Uffffffff";`); catch(e){}
try loadString(`x = "\255";`); catch(e){}
x = "a really long string a really long string a really long string a really long string a really long string a really long string a really long string a really long string a really long string a really long string ";
loadJSON(`["\/"]`);
try loadString(`x = "hello`); catch(e){}
x = "hi
there";try loadString(`x = '`); catch(e){}
try loadString(`x = 'h`); catch(e){}
local y = array.new(10);
function foobar() { return 4, 5; }
x = 0;
y[x], x = foobar();
x = 4 + 5;
x++;
x -= 1;
x = 4 - 5;
x--;
x = "hi" ~ "there";
x ~= "guys";
x = 4 * 5;
x *= 2;
x = 4 / 5;
x /= 2;
// hi
/* there * blah
 */
/+ guys /+ in +/
comments +/
try loadString(`/*`); catch(e){}
try loadString(`/+`); catch(e){}
x = 4 % 5;
x %= 5;
x = 4 < 5;
x = 4 << 5;
x <<= 5;
x = 4 <= 5;
x = 4 <=> 5;
x = 4 > 5;
x = 4 >= 5;
x = 4 >> 5;
x >>= 5;
x = 4 >>> 5;
x >>>= 5;
x = 4 & 5;
x = 4 && 5;
x &= 5;
x = 4 | 5;
x = 4 || 5;
x |= 5;
x = 4 ^ 5;
x ^= 5;
x = 4 == 5;
x = !x;
x = 4 != 5;
x ?= 4;
x = true ? 4 : 5;
x = false ? 4 : 5;
x = @"hello";
x = x ? 1 : 2;
if(x ? 1 : 2) {}
try loadString(`x = @y;`); catch(e){}
try loadString(`__x = 5;`); catch(e){}
try loadString("$"); catch(e){}
try loadString("class A{this(){super();}}"); catch(e){}
try loadString("super();"); catch(e){}
class A{}
function f() { local x; function g(){ x = 5; x = 10; } }
loadString("for(;;){}");
switch(5)
{
	case null: break;
	case true: break;
	case 5: break;
	case 4.5: break;
	case 'h': break;
	case "hi": break;
	case x: break;
	default: break;
}
try loadString("switch(x){case 5, 5: break;}"); catch(e){}
try loadString("local x; local x;"); catch(e){}
global fee = 5;
loadString("writefln(this); writefln(vararg); x[0 .. 3] = 4; x[0] = 5; x = y[0]; x = y[0 .. 3];");
loadString("local x = vararg; y = vararg; x = f(); y = f(); y = {};");
x = null;
loadString("local x, y, z = yield();");
x = function() { return g(); };
global x, y, z = f();
loadString("local x; x, y[0], z[0 .. 1] = f(); z, y = f(); x.y = 10;");
loadString("global x = true; global x = false; global x = y[0]; global x = y[0 .. 1]; global x = y + x; global x = yield();");
loadString("local y = 0; global x = function(){y = 10;}; global x = vararg;");
loadString("for(local x;;){ function f(){ x = 5;} continue;}");
loadString("for(i:0..10){continue;}");
loadString("if(x == y || x == y && x == y){}else{}");
loadString("while(x == 1){ local x; function f(){x = 1;} break;continue;}");
loadString("try{}catch(e){}finally{}");
try loadString("continue;"); catch(e){}
try loadString("break;"); catch(e){}
x = 'h'; x = 'h';
x = class{mX = 5; mY = 10;function f(){}};
try loadString("class A{function f(){} function f(){}}"); catch(e){}
loadString("global x = null; global x = null; global x = true; global x = true;");
try loadString("class A{mY; mX = 5; mX = 5;}"); catch(e){}
try loadString("class A{"); catch(e){}
try loadString("class A{&&"); catch(e){}
loadString("class A:B{}");
x = function f(){};
x = function f()3;
x = function(vararg){};
x = function(x, vararg){};
x = function(x = 5){};
do{}while(false)
loadString("foreach(k;c){}");
loadString("throw 5;");
try loadString(";"); catch(e){}
try loadString("[]"); catch(e){}
loadString("local function f(){} global function g(){}");
loadString("global class A{} local class B{}");
try loadString("local while"); catch(e){}
try loadString("local x, x;"); catch(e){}
loadString("global x, y, z;");
loadString("if(x == 5){} if(true){}else{} if(false){}else{} if(false){}");
loadString("while(true){} while(false){}");
loadString("do{}while(true) do{}while(false) do{}while(x == 5)");
loadString("for(x = 5, y = 10;x<10;x++, y++){} for(i:1..10,1){} for(;true;){} for(;false;){}");
loadString("for(local x = 4, y = 10;false;){}");
try loadString("for(i:'h' .. 'k'){}"); catch(e){}
try loadString("for(i:1 .. 'k'){}"); catch(e){}
try loadString("for(i:1..3, 'h'){}"); catch(e){}
try loadString("for(i:1..3, 0){}"); catch(e){}
loadString("foreach(i; a){} foreach(i; f()){}");
loadString("foreach(k; a, b){} foreach(k; a, b()){}");
loadString("foreach(k, v; a, b, c){}");
try loadString("foreach(k; a, b, c, d){}"); catch(e){}
try loadString("switch(5){}"); catch(e){}
loadString("return; return 1, 2, 3; return 1, f();");
try loadString("try{}"); catch(e){}
try{}finally{}
x = 5;
++x;
--x;
loadString("f(1, 2, 3, 4, 5, 6, 7);");
try loadString("x, y = 45;"); catch(e){}
try loadString("this = 5;"); catch(e){}
try loadString("if(x = 5){}"); catch(e){}
loadString("x ~= f(); x ~= y ~ z; if(x + y){} f() || g(); (false) || f(); f() && g(); (false) && f();");
loadString("if(x + 5){} x = y | z; x = y ^ z; x = y & z;");
try loadString("if(x += 5){}"); catch(e){}
try loadString("x = 4.5 | 6;"); catch(e){}
try loadString("x = 4.5 ^ 6;"); catch(e){}
try loadString("x = 4.5 & 6;"); catch(e){}
loadString("if(x is 5){} if(x != 5){} if(x !is 5){} if(x !in 5){} x = y == z;");
if(null == null){} if(4 == 4){} if(4.5 == 4.5){} if('h' == 'h'){} if(true == true){} if("hi" == "hi"){}
try loadString("if('h' == 5){}"); catch(e){}
loadString("x = y as z; x = y in z; x = y < z; x = y > z; x = y <= z; x = y >= z;");
loadString("x = null < null; x = 4 < 5; x = 4.5 < 5; x = 5 > 4.5; x = 4.5 <= 4.5; x = 'a' < 'h'; x = `hi` < `bye`;");
try loadString("x = true < false;"); catch(e){}
try loadString("x = 4 as 5;"); catch(e){}
try loadString("x = 'a' << 'b';"); catch(e){}
loadString("x = y << z; x = 4.5 + 4.5; x = 4.5 - 4.5;");
try loadString("x = 'h' + 'c';"); catch(e){}
loadString("x = y ~ z; x = y ~ f(); x = y ~ z ~ w;");
x = 'h' ~ 'c'; x = 'h' ~ "e"; x = "h" ~ 'c';
try loadString("x = 4 % 0;"); catch(e){}
try loadString("x = 4 / 0;"); catch(e){}
loadString("x = 4.0 / 5.0; x = 4.0 * 5.0; x = 4.0 % 5.0; x = x / y;");
try loadString("x = 4.0 % 0.0;"); catch(e){}
try loadString("x = 4.0 / 0.0;"); catch(e){}
try loadString("x = 'h' * 'c';"); catch(e){}
loadString("x = -x; x = -4; x = -4.0; x = !y; x = !true; x = ~y; x = ~0; x = #y; x = #`hello`; x = coroutine y;");
loadString("if(!x){}");
try loadString("x = -'h';"); catch(e){}
loadString("if(!(x < y)){} if(!(x <= y)){} if(!(x > y)){} if(!(x >= y)){} if(!(x == y)){}");
try loadString("x = ~'h';"); catch(e){}
try loadString("x = #'h';"); catch(e){}
loadString("x = y.super; x = y.class; f(with x); x = y[0 .. 1]; x = y[..1]; x = y[..]; x = y[0..];");
loadString("o.f(); o.f(g()); o.f(1);");
try loadString("x = 4[0];"); catch(e){}
try loadString("x = `hello`[-10];"); catch(e){}
loadString("x = `hello`[0];");
try loadString("x = 4[0 .. 1];"); catch(e){}
try loadString("x = `hi`[-10 .. -9];"); catch(e){}
loadString("x = [1];");
loadJSON("[null, true, 4, 4.5, {}, []]");
try loadJSON("[heyhey]"); catch(e){}
loadString("if(x){} if(this){} if(null){}");
try loadString("function f(){ x = vararg; }"); catch(e){}
try loadString("if(vararg){}"); catch(e){}
loadString("if('h'){} if(4.0){} if(`hi`){}");
try loadString("if(function(){}){}"); catch(e){}
loadString("x = class A{}; if((f())){} writefln((f()));");
try loadString("if(class{}){}"); catch(e){}
x = {x = 1, y = 2, z = 3, a = 4, b = 5, c = 6, d = 7, e = 8, f = 9, ["g"] = 10, function h(){}, i = 11};
loadJSON(`{"a" : 1, "b" : 2, "c" : 3, "d" : 4, "e" : 5, "f" : 6, "g" : 7, "h" : 8, "i" : 9}`);
try loadString("if({}){}"); catch(e){}
x = [1, 2, 3];
loadString("x = [f()];");
try loadString("if([]){}"); catch(e){}
loadString("yield(1); yield(f()); class A : B { this() { super(); } function f() { super.f(2); x = [super.f()]; }}");
try import("tests.compiler.dupimportlocals"); catch(e){}
import("tests.compiler.noimportlocals");
loadString("namespace a : b { function foo(){} bar = 5; baz; } local namespace b {} namespace c{} global namespace d {} ");
loadString("x = namespace x{};");
try loadString("namespace a{"); catch(e){}
try loadString("namespace a { x; x; }"); catch(e){}
try loadString("namespace a { #### }"); catch(e){}
try loadString(`x = "hello\`); catch(e){}