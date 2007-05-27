module tests.base;

local f = io.File(`tests\foobar.txt`);

try f.readf("%% %0*"); catch(e){}
try f.readf("%3.*"); catch(e){}
writefln(f.readf("%5s %d %c %s %f %.3s"));
try f.readf("%p"); catch(e){}
try f.readf("%"); catch(e){ writefln("BO"); }

writefln("%d %f %c %s", 4, 5.6, 'h', "hi", 7);
writefln("%010.10f", 5);
writefln("%r", []);
writefln("%%");
try writefln("%d"); catch(e){}
try writefln("%d", 'h'); catch(e){}
try writefln("%f"); catch(e){writefln("FO");}
try writefln("%f", 'h'); catch(e){}
try writefln("%c"); catch(e){}
try writefln("%c", 5); catch(e){}
try writefln("%s"); catch(e){}
try writefln("%100000000000000000000000000f", 4); catch(e){}
try writefln("%"); catch(e){}
try writefln("%*"); catch(e){}
try writefln("%.*"); catch(e){}
try writefln("%p"); catch(e){}
write("hi");
writef("hi");
writeln("hi");
format();
typeof(5);
toString(5);
rawToString(5);
getTraceback();
isInt(5);
assert(true);
try assert(false); catch(e){}
try assert(false, "h"); catch(e){}
toInt(true);
toInt(5);
toInt(4.5);
toInt('h');
toInt("45");
try toInt([]); catch(e){}
toFloat(true);
toFloat(4);
toFloat(4.5);
toFloat('h');
toFloat("4.5");
try toFloat([]); catch(e){}
toChar(4);
foreach(k, v; _G){}
fieldsOf(class{});
fieldsOf(class{}());
try fieldsOf(5); catch(e){}
methodsOf(class{});
methodsOf(class{}());
try methodsOf(5); catch(e){}
local t = coroutine function(){};
t.state();
t.isInitial();
t.isRunning();
t.isWaiting();
t.isSuspended();
t.isDead();
foreach(v; coroutine function countDown(x){currentThread(); yield();while(x > 0){yield(x);x--;}}, 5){}
t();
try foreach(c; t){} catch(e){}
currentThread();
curry(function(x, y){}, 3)(4);
try import("blahblah"); catch(e){}
import("tests.dummy");
loadString("");
loadString("", "h");
eval("5");
loadJSON("{}");

local s = StringBuffer("hello");
StringBuffer(5);
StringBuffer();
try StringBuffer([]); catch(e){}
s ~= StringBuffer("h") ~ [] ~ 3;
s.insert(0, StringBuffer("h"));
s.insert(0, []);
s.insert(0, 3);
s.remove(0);
s.remove(0, 1);
s.toString();
s.length(#s + 1);
s[0] = s[1];
foreach(i, v; s){}
foreach(i, v; s, "reverse"){}
s[0 .. 1] = s[2 .. 3];
s.reserve(100);
try s.insert(204059, "h"); catch(e){}
try s.insert(305935, StringBuffer()); catch(e){}
try s.insert(350156, 5); catch(e){}
s.remove(10, 100);
try s.remove(10, 0); catch(e){}
s.length(200);
s[-2] = s[-1];
try s[1049025] = 'h'; catch(e){}
try s[0] = s[95209]; catch(e){}
s[-4 .. -3] = s[-2 .. -1];
try s[0 .. 1] = "hello"; catch(e){}
try s[95091235 .. 5010936] = "h"; catch(e){}
try s[0] = s[230591 .. 019096]; catch(e){ writefln(e);}
try s[-392096 .. 0] = "h"; catch(e){}

{
	function loadMod(name, ns)
	{
		assert(name == "mod");
	
		ns.x = "I'm x";
	
		ns.foo = function foo()
		{
			writefln("foo");
		};
	
		ns.bar = function bar(x)
		{
			return x[0];
		};
	
		ns.baz = function baz()
		{
			writefln(x);
		};
	
		foreach(k, v; ns)
			if(isFunction(v))
				v.environment(ns);
	}
	
	setModuleLoader("mod", loadMod);
	
	import mod : foo, bar;
	foo();
	writefln(bar([5]));
	mod.baz();
	
	writefln();
	
	readf("%d");
}