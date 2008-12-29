module tests.interpreter

import tests.common : xfail

function foo(vararg){}

// some debug stuff
debug.currentLine(0)

// calling
{
	local class Frendle
	{
		this() {}
		function opMethod() {}
	}

	Frendle().forble()
	Frendle().forble(with 0)
	xfail$\{ (class{}()).forble() }
	Frendle.opMethod()
	xfail$\{ Frendle.forble() }
	foo(Frendle())
	local x, y, z = Frendle()

	local f = Frendle()
	f.forble = function forble(){}
	f.forble()
}

// wut
{
	xfail$\{ tests.forble() }
	xfail$\{ (class{ constructor = 5 })() }
}

// table stuff
{
	local t = { function forble() {} }
	t.forble()
	t.keys()
	xfail$\{ t.borble() }
}

// calling coroutines
{
	local co = coroutine function()
	{
		yield()
		yield()
	}

	co()
	co()
	co()
	xfail$\{ co() }

	co = coroutine function() { co() }
	xfail$\{ co() }
}

// moar calling
{
	({ function opCall(){} })()
	xfail$\{ ({})() }
}

// toString
{
	toString(null)
	toString(true)
	toString(0)
	toString(4.5)
	toString('x')
	toString({function toString() = ""})
	xfail$\{ toString({function toString(){}}) }
	toString({})
	rawToString([])
	toString(foo)
	toString(write)
	toString(class{})
	toString(class{}())
	toString(_G)
	rawToString(_G)
	toString(coroutine\{})
	toString(weakref({}))
}

// in
{
	local x = 'x' in "x"
	xfail$\{ x = 5 in "x" }
	x = 5 in [1 2 3]
	x = "foo" in _G
	xfail$\{ x = 5 in _G }
	xfail$\{ x = 5 in (class{})() }
	local class Frendle { function opIn() = false }
	x = 5 in Frendle()
}

// idx
{
	local x = [1 2 3][1]
	xfail$\{ x = [1 2 3]['x'] }
	x = [1 2 3][-1]
	xfail$\{ x = [1 2 3][5] }
	local s = "hello"
	x = s[2]
	x = s[-2]
	xfail$\{ x = s['x'] }
	xfail$\{ x = s[9] }
	local class Frendle { function opIndex() = 0 }
	x = Frendle()[4]
	xfail$\{ x = (class{})[4] }
	local t = {x = 5}
	x = t.x
	x = t.y
	t.opIndex = \->0
	x = t.y
	hash.get(t, "y")
}

// idxa
{
	xfail$\{ ([1])['x'] = 5 }
	xfail$\{ ([1])[-3] = 5 }
	xfail$\{ local s = "hi"; s[0] = 6 };
	(class{function opIndexAssign(){}}())[0] = 5
	xfail$\{ ({})[null] = 5 };
	({function opIndexAssign(){}})[null] = 5
}

// field
{
	local x
	xfail$\{ x = (class{}).x }
	xfail$\{ x = (class{}()).x }
	x = (class{function opField() = 0}()).x
	x = (class{x}()).x
	xfail$\{ x = _G.oskfoaksf }
	xfail$\{ x = 5.x }
}

// fielda
{
	(class{function opFieldAssign(){}}()).x = 5;
	(class{x}()).x = 5;
	(class{this():x = 5}()).x = 5
	xfail$\{ 5.x = 5 }
}

// cmp
{
	local x = 5
	local y = x < 3
	y = x < 3.0
	x = 5.0
	y = x < 3
	y = x < 3.0
	x = null
	y = x < null
	x = true
	y = x < false
	x = 'x'
	y = x < 'y'
	x = "x"
	y = x < "y"
	y = x < "x"
	x = {function opCmp() = 0}
	y = x < {}
	y = {} < x
	y = x < 3
	y = 3 < x
	xfail$\{ y = {} < {} }
	xfail$\{ y = [] < [] }
	xfail$\{ y = 3 < {function opCmp() = null} }
}

// switchcmp
{
	local a = 2
	local b = class{}()

	local inst = class{function opCmp() = 1}()

	switch(inst)
	{
		case a: break
		case b: break
		case inst: break
	}
	
	switch(b)
	{
		case a: break
		case inst: break
		case b: break
	}
	
	switch(5)
	{
		case a: break
		default: break
	}
}

// equals
{
	local x = 5
	local y = x == 3
	y = x == 3.0
	x = 5.0
	y = x == 3
	y = x == 3.0
	x = null
	y = x == null
	x = true
	y = x == false
	x = 'x'
	y = x == 'y'
	x = "x"
	y = x == "y"
	y = x == "x"
	x = {function opEquals() = false}
	y = x == {}
	y = {} == x
	y = x == 3
	y = 3 == x
	xfail$\{ y = {} == {} }
	xfail$\{ y = [] == [] }
	xfail$\{ y = 3 == {function opEquals() = null} }
}

// len
{
	local s = "hi"
	local x = #s
	x = #{}
	x = #{opLength = \->0}
	xfail$\{ x = #class{} }
}

// lena
{
	local a = []
	#a = 3
	xfail$\{ #a = 'x' }
	xfail$\{ #a = -1 }
	xfail$\{ #{} = 0 }
	#{ function opLengthAssign(){} } = 0
}

// slice
{
	local a = [1 2 3 4 5]
	local b = a[]
	xfail$\{ b = a[100 .. 100] }
	xfail$\{ b = a['x' .. 'y'] }
	b = a[1 .. 4]
	
	a = "hello"
	b = a[]
	xfail$\{ b = a[100 .. 100] }
	xfail$\{ b = a['x' .. 'y'] }
	b = a[1 .. 4]
	
	b = (class{opSlice = \->0}())[]
	xfail$\{ b = {}[] }
}

// slicea
{
	local a = [1 2 3 4 5]
	local b = a.dup()
	b[] = a
	xfail$\{ b[100 .. 100] = a[] }
	xfail$\{ b['x' .. 'y'] = a[] }
	xfail$\{ b[0 .. 3] = a }
	xfail$\{ b[] = 5 };
	(class{function opSliceAssign(){}}())[] = a
	xfail$\{ ({})[] = a }
}

// binop
{
	local x = 5
	local y = x + 3
	y = x - 3
	y = x * 3
	y = x / 3
	y = x % 3
	y = x + 3.0
	y = x - 3.0
	y = x * 3.0
	y = x / 3.0
	y = x % 3.0
	xfail$\{ y = x / 0 }
	xfail$\{ y = x % 0 }
	x = 5.0
	y = x - 3
	y = x * 3
	y = x / 3
	y = x % 3
	y = x + 3.0
	y = x - 3.0
	y = x * 3.0
	y = x / 3.0
	y = x % 3.0
	
	x = class{opAdd = \->0}()
	y = x + 3
	y = 3 + x
	xfail$\{ y = 3 - x }
	x.opAdd_r = \->0
	y = 3 + x
	xfail$\{ y = class{}() + 3 }
}

// reflbinop
{
	local x = 5
	xfail$\{ x /= 0 }
	xfail$\{ x %= 0 }
	x += 3
	x -= 3
	x *= 3
	x /= 3
	x %= 3
	x = 5
	x += 3.0
	x -= 3.0
	x *= 3.0
	x /= 3.0
	x %= 3.0
	x = 5.0
	x += 3
	x -= 3
	x *= 3
	x /= 3
	x %= 3
	x = class{opAddAssign = \{}}()
	x += 3
	xfail$\{ x = class{}(); x += 3 }
}

// neg
{
	local x = 5
	local y = -x
	x = 5.0
	y = -x
	y = -{opNeg = \->0}
	xfail$\{ y = -{} }
}

// binarybinop
{
	local x = 3
	local y = x & 5
	y = x | 5
	y = x ^ 5
	y = x << 5
	y = x >> 5
	y = x >>> 5
	y = (class{opAnd = \->0}()) & 5
}

// reflbinarybinop
{
	local x = 5
	x &= 3
	x |= 3
	x ^= 3
	x <<= 3
	x >>= 3
	x >>>= 3
	x = class{opAndAssign = \{}}()
	x &= 5
	xfail$\{ x = {}; x &= 3 }
}

// com
{
	local x = 5
	local y = ~x
	y = ~{opCom = \->0}
	xfail$\{ y = ~{} }
}

// inc
{
	local x = 5
	x++
	x = 5.0
	x++
	x = {opInc = \{}}
	x++
	xfail$\{ x = {}; x++ }
}

// dec
{
	local x = 5
	x--
	x = 5.0
	x--
	x = {opDec = \{}}
	x--
	xfail$\{ x = {}; x-- }
}