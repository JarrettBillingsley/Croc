module tests.baselib

import tests.common : xfail

// GC
collectGarbage()
bytesAllocated()

// functional
curry(\x, y -> x + y, 3)(4)
bindContext(\->this, 3)()

// reflection
findGlobal("frendle")
isSet("tests")
isSet("frendle")
typeof(5)
nameOf(_G)
nameOf(nameOf)
nameOf(StringBuffer)
xfail$\{ nameOf(4) }
fieldsOf(class{})
fieldsOf(class{}())
xfail$\{ fieldsOf(4) }
foreach(v; allFieldsOf(class:StringBuffer{ opLength = 4; this() :xx = 4 }())){}
xfail$\{ foreach(v; allFieldsOf(5)){} }
hasField(StringBuffer, "x")
hasMethod(StringBuffer, "x")
findField(StringBuffer, "opLength")
findField(StringBuffer, "forbleborble")
xfail$\{ findField(4, "x") }
rawSetField(class{}(), "x", 5)
rawGetField(class{x}(), "x")
attrs(class{}, {})
hasAttributes(StringBuffer)
attributesOf(StringBuffer)

// conversion
toString(5, 'x')
toString('x')
rawToString(5)
toBool(5)
toInt(false)
toInt(5)
toInt(4.5)
toInt('x')
toInt("5")
xfail$\{ toInt(null) }
toFloat(false)
toFloat(5)
toFloat(4.5)
toFloat('x')
toFloat("5")
xfail$\{ toFloat(null) }
toChar(5)
format()
format(4.5, 'x', {})
format("hello {} world", 3)
format("{")
format("{r}")
format("{0}")

// console
write(4)
writeln(4)
writef(4)
writefln(4)

{
	local t = {}
	t.s = "\'\"\\\a\b\f\n\r\t\vx\u2000\U00100000"
	t.a = [0 1 2 3]
	t.a[0] = t.a
	t.t = t
	t.n = namespace N { x = 5; y = 10 }
	t.n.n = t.n
	t.c = 'x'
	t.w = weakref({})

	dumpVal(t)
}

// dynamic compilation
loadString("")
loadString("", "")
loadString("", namespace N{})
loadString("", "", namespace N{})
eval("1")
eval("1", namespace N{})
loadJSON("{}")
toJSON({})

// function metatable
toJSON.environment();
(\->1).environment(namespace N{})
toJSON.isNative()
toJSON.numParams()
toJSON.isVararg()
toJSON.name()

// weak reference stuff
deref(null)
deref(false)
deref(0)
deref(0.0)
deref('\0')
deref(weakref({}))
xfail$\{ deref({}) }