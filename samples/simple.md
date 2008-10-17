module samples.simple

local t = time.Timer.clone()
t.start()

local x = 5

for(i: 0 .. 10_000_000)
	x += 3

t.stop()
writefln("Took {:f6} seconds", t.seconds())

/*
function enum(name: string, vararg)
{
	local sb = StringBuffer.clone()

	sb.append("namespace ", name, "\n{\n")

	for(i: 0 .. #vararg)
		sb.append("\t", vararg[i], " = ", i, "\n")

	sb.append("}")

	loadString(sb.toString())()
}

enum("NodeType",
	"Add",
	"Mul",
	"Var",
	"Num"
)

object ExpNode
{
	function clone(type: int)
	{
		local ret = super.clone()
		ret.type = type
		return ret
	}

	function opCall(vararg) = :clone(vararg)
	function opAdd(other: ExpNode) = AddNode(this, other)
	function opMul(other: ExpNode) = MulNode(this, other)
}

object Var : ExpNode
{
	function clone(name: string)
	{
		local ret = super.clone(NodeType.Var)
		ret.name = name
		return ret
	}

	function toString() = :name
}

object Num : ExpNode
{
	function clone(val: int|float)
	{
		local ret = super.clone(NodeType.Num)
		ret.val = toFloat(val)
		return ret
	}

	function toString() = toString(:val)
}

object BinNode : ExpNode
{
	function clone(type: int, left: ExpNode, right: ExpNode)
	{
		local ret = super.clone(type)
		ret.left = left
		ret.right = right
		return ret
	}
}

object AddNode : BinNode
{
	function clone(left: ExpNode, right: ExpNode) = super.clone(NodeType.Add, left, right)
	function toString() = format("({} + {})", :left, :right)
}

object MulNode : BinNode
{
	function clone(left: ExpNode, right: ExpNode) = super.clone(NodeType.Mul, left, right)
	function toString() = format("({} * {})", :left, :right)
}

function searchVars(n: ExpNode, vars: table)
{
	switch(n.type)
	{
		case NodeType.Var:
			vars[n.name] = true;
			break;

		case NodeType.Add, NodeType.Mul:
			searchVars(n.left, vars)
			searchVars(n.right, vars)
			break;

		default:
			break;
	}
}

function compileExp(root: ExpNode)
{
	local vars = {}
	searchVars(root, vars)
	local params = string.join(vars.keys().sort(), ", ")
	return eval("\\" ~ params ~ " -> " ~ root.toString())
}

local exp = (Num(4) + Var("x")) * (Var("y") + Num(3))
writeln(exp)

local f = compileExp(exp)
writeln(f(3, 4))

*/

// object Foo
// {
// 	x = 0
// 	y = 0
//
// 	function clone(x: int, y: int)
// 	{
// 		local ret = super.clone()
// 		ret.clone = null
// 		ret.x = x
// 		ret.y = y
// 		return ret
// 	}
// 
// 	function write()
// 	{
// 		assert(this !is Foo, "Method may not be called on the class that holds it")
// 		writefln("Foo: {}, {}", :x, :y)
// 	}
//
// 	function opAdd(other: Foo)
// 	{
// 		assert(this !is Foo && other !is Foo, "Method may not be called on the class that holds it")
// 		return Foo.clone(:x + other.x, :y + other.y)
// 	}
// }
//
// object Bar : Foo
// {
// 	z = 1337
//
// 	function clone() = super.clone(-1, -10)
//
// 	function write()
// 	{
// 		assert(this !is Bar, "method may not be called on the class that holds it")
// 		writefln("Bar: {}, {}, {}", :x, :y, :z)
// 	}
// }
//
// local f = Foo.clone(5, 10)
// f.write();
// (f + Foo.clone(15, 20)).write()
// local b = Bar.clone()
// b.write();
// (f + b).write()

/+
// import arc.draw.color: Color
// import arc.draw.image: drawImage, drawImageTopLeft
// import arc.draw.shape: drawCircle, drawRectangle, drawLine, drawPixel
// import arc.font: Font
import arc.input: key, mouse
// import arc.math.point: Point
// import arc.math.size: Size
// import arc.sound: Sound, SoundFile
// import arc.texture: Texture
import arc.time
import arc.window

import time: microTime

object ParticleGen
{
	mParticles = null
	mFreeParticles = null
	mRate
	mGravity
	mLife
	mLast

	function clone(rate: int|float, gravity: int|float = 0.05, life: int|float = 2.5)
	{
		local ret = super.clone()

		ret.mRate = toFloat(rate)
		ret.mGravity = toFloat(gravity)
		ret.mLife = toInt(life * 1_000_000)
		ret.mLast = microTime()

		return ret
	}

	function generate(pos)
	{
		local time = microTime()

		if((time - :mLast) < :mRate)
			return

		local ang = math.rand(360)

		local part

		if(:mFreeParticles is null)
			part = { color = Color(1.0, 1.0, 1.0) }
		else
		{
			part = :mFreeParticles
			:mFreeParticles = part.next
		}

		part.pos = pos
		part.vx = math.sin(ang) * math.frand(1.5)
		part.vy = math.cos(ang) * math.frand(1.5)
		part.color.setR(1.0)
		part.color.setG(0.0)
		part.color.setB(0.0)
		part.color.setA(1.0)
		part.start = time
		part.next = :mParticles
		:mParticles = part

		:mLast = time;
	}

	function process()
	{
		if(:mParticles is null)
			return;

		local time = microTime()

		for(local v = :mParticles, local old = null; v !is null; )
		{
			local t = time - v.start

			if((time - v.start) > :mLife)
			{
				if(old is null)
					:mParticles = v.next
				else
					old.next = v.next

				local temp = v.next
				v.next = :mFreeParticles
				:mFreeParticles = v
				v = temp
				continue
			}

			v.color.setA(1.0 - (t / toFloat(:mLife)))

			v.vy -= :mGravity;
			v.pos.y -= v.vy;
			v.pos.x += v.vx;

			if(v.pos.x < 0 || v.pos.x > arc.window.getWidth() || v.pos.y > arc.window.getHeight())
			{
				if(old is null)
					:mParticles = v.next
				else
					old.next = v.next

				local temp = v.next
				v.next = :mFreeParticles
				:mFreeParticles = v
				v = temp
				continue
			}

			drawCircle(v.pos, 2, 8, v.color, true)
			old = v
			v = v.next
		}
	}
}

function main()
{
	writefln("hi!")

	arc.window.open("Hello world", 800, 600, false)
	arc.input.open()
// 	arc.font.open()
	arc.time.open()
// 	arc.sound.open()

// 	local font = Font.clone("arial.ttf", 12)
// 	local font2 = Font.clone("arial.ttf", 32)
// 	local origin = Point.clone(0.0, 0.0)
// 	local white = Color.clone(255, 255, 255)

// 	local pg = ParticleGen.clone(1000)

// 	arc.input.defaultCursorVisible(false)

	while(!arc.input.keyDown(key.Quit) && !arc.input.keyDown(key.Esc))
	{
		arc.input.process()
		arc.window.clear()
		arc.time.process()
// 		arc.sound.process()

// 		if(arc.input.mouseButtonDown(mouse.Left))
// 			pg.generate(arc.input.mousePos())

// 		pg.process()

// 		drawCircle(arc.input.mousePos(), 6, 10, white, false)

// 		font.draw(toString(arc.time.fps()), origin, white)
// 		font.draw(toString(pg.mParticles is null), Point.clone(0.0, 16.0), white)
		arc.time.limitFPS(60)
		arc.window.swap()
	}

// 	arc.sound.close()
	arc.time.close()
// 	arc.font.close()
	arc.input.close()
	arc.window.close()

	writefln("bye!")
}
/+
/*
object BaseProp
{
	function get()
		throw "No get implemented"

	function set()
		throw "No set implemented"
}

object Bah : BaseProp
{
	function get(owner)
		writefln("Getting bah's value.")

	function set(owner, value)
		writefln("Setting bah's value to ", value, ".")
}

function getMethod(T, name) = name in fieldsOf(T) ? T.(name) : null

function mixinProperties(T, vararg)
{
	if(#vararg == 0)
		return;

	local properties = {}
	local oldField = getMethod(T, "opField")
	local oldFieldAssign = getMethod(T, "opFieldAssign")

	T.opField = function opField(name)
	{
		if(local prop = properties[name])
			return prop.get(this)

		if(oldField is null)
			return rawGetField(this, name)
		else
			return oldField(with this, name)
	}

	T.opFieldAssign = function opFieldAssign(name, value)
	{
		if(local prop = properties[name])
			return prop.set(this, value)

		if(oldFieldAssign is null)
			rawSetField(this, name, value)
		else
			return oldFieldAssign(with this, name, value)
	}

	for(i: 0 .. #vararg, 2)
		properties[vararg[i]] = vararg[i + 1]
}

object Test
{
	function opField(name) = format("property {}", name)
	//x = 0
}

mixinProperties(Test, "bah", Bah.clone())

local t = Test.clone()
writeln(t.bah)
t.bah = 5
writeln(t.x)
t.x = 10
writeln(t.x)

/*
function shuffle(arr)
	for(i: 0 .. #arr)
	{
		local idx = math.rand(#arr)
		local tmp = arr[i]
		arr[i] = arr[idx]
		arr[idx] = tmp
	}

object Deck
{
	function init()
	{
		:cards = []

		foreach(suit; ["H", "D", "C", "S"])
			for(val: 2 .. 14)
			{
				local tmp = toString(val) ~ suit
				:cards ~= tmp
			}
	}

	function shuffle() shuffle(:cards)
	function dealCard() = :cards.pop()

	function show()
	{
		foreach(card; :cards)
			write(card, " ")

		writeln()
	}
}

Deck.init()
Deck.show()
Deck.shuffle()
Deck.show()

writeln(Deck.dealCard())
writeln(Deck.dealCard())
writeln(Deck.dealCard())
*/

// Making sure finally blocks are executed.
{
	local function f()
	{
		try
		{
			try
			{
				writefln("hi 1")
				return "foo", "bar"
			}
			finally
				writefln("bye 1")

			writefln("no use 1")
		}
		finally
			writefln("bye 2")

		writefln("no use 2")
	}

	local a, b = f()
	writefln(a, ", ", b)

	writefln()
}

// Importing stuff.
{
	modules.customLoaders.mod = function loadMod(name: string)
	{
		assert(name == "mod")

		global x = "I'm x"

		global function foo()
			writefln("foo")

		global function bar(x) = x[0]

		global function baz()
			writefln(x)
	}

	import mod: foo, bar
	foo()
	writefln(bar([5]))
	mod.baz()

	writefln()
}

// Super calls.
{
	local object Base
	{
		function fork()
			writefln("Base fork.")
	}

	local object Derived : Base
	{
		function fork()
		{
			writefln("Derived fork!")
			super.fork()
		}
	}

	local d = Derived.clone()
	d.fork()

	writefln()
}

// Coroutines and coroutine iteration.
{
	local countDown = coroutine function countDown(x)
	{
		yield()

		while(x > 0)
		{
			yield(x)
			x--
		}
	}

	foreach(v; countDown, 5)
		writefln(v)

	writefln()

	local forEach = coroutine function forEach(t)
	{
		yield()

		foreach(k, v; t)
			yield(k, v)
	}
	
	foreach(_, k, v; forEach, {hi = 1, bye = 2})
		writefln("key: ", k, ", value: ", v)

	writefln()
}

// Testing tailcalls.
{
	local function recurse(x)
	{
		writefln("recurse: ", x)
	
		if(x == 0)
			return toString(x)
		else
			return recurse(x - 1)
	}

	writefln(recurse(5))
	writefln()

	local object A
	{
		function f(x)
		{
			writefln("A.f: ", x)

			if(x == 0)
				return toString(x)
			else
				return :f(x - 1)
		}
	}

	writefln(A.f(5))
	writefln()
}

{
	// A function which lets us define properties for an object.
	// The varargs should be a bunch of tables, each with a 'name' field, and 'getter' and/or 'setter' fields.
	local function mixinProperties(T, vararg)
	{
		T._props = { }
	
		T.opField = function opField(key)
		{
			local prop = :_props[key]

			if(prop is null)
				throw format("Property '{}' does not exist in {r}", key, T)

			local getter = prop.getter

			if(getter is null)
				throw format("Property '{}' has no getter in {r}", key, T)

			return getter(with this)
		}

		T.opFieldAssign = function opFieldAssign(key, value)
		{
			local prop = :_props[key]

			if(prop is null)
				throw format("Property '{}' does not exist in {r}", key, T)

			local setter = prop.setter

			if(setter is null)
				throw format("Property '{}' has no setter in {r}", key, T)

			setter(with this, value)
		}
	
		foreach(i, prop; [vararg])
		{
			if(!isTable(prop))
				throw format("Property ", i, " is not a table")

			if(prop.name is null)
				throw format("Property ", i, " has no name")

			if(prop.setter is null && prop.getter is null)
				throw format("Property '{}' has no getter or setter", prop.name)
	
			T._props[prop.name] = prop
		}
	}
	
	// Create an object to test out.
	local object PropTest
	{
		mX = 0
		mY = 0
		mName = ""

		function clone(name) = object : this { mName = name }
		function toString() = format("name = '", :mName, "' x = ", :mX, " y = ", :mY)
	}

	// Mix in the properties.
	mixinProperties(
		PropTest,

		{
			name = "x",
			function setter(value) :mX = value
			function getter() = :mX
		},

		{
			name = "y",
			function setter(value) :mY = value
			function getter() = :mY
		},

		{
			name = "name",
			function getter() = :mName
		}
	)
	
	// Create an instance and try it out.
	local p = PropTest.clone("hello")
	
	writefln(p)
	p.x = 46
	p.y = 123
	p.x = p.x + p.y
	writefln(p)
	
	// Try to access a nonexistent property.
	try
		p.name = "crap"
	catch(e)
		writefln("caught: ", e)

	writefln()
}

// Some containers.
{
	local object PQ
	{
		mData
		mLength = 0

		function clone() = object : this { mData = array.new(15) }

		function insert(data)
		{
			:resizeArray()
			:mData[:mLength] = data

			local index = :mLength
			local parentIndex = (index - 1) / 2

			while(index > 0 && :mData[parentIndex] > :mData[index])
			{
				local temp = :mData[parentIndex]
				:mData[parentIndex] = :mData[index]
				:mData[index] = temp

				index = parentIndex
				parentIndex = (index - 1) / 2
			}

			:mLength += 1
		}

		function remove()
		{
			if(:mLength == 0)
				throw "PQ.remove() - No items to remove"

			local data = :mData[0]
			:mLength -= 1
			:mData[0] = :mData[:mLength]

			local index = 0
			local left = 1
			local right = 2
	
			while(index < :mLength)
			{
				local smaller

				if(left >= :mLength)
				{
					if(right >= :mLength)
						break
					else
						smaller = right
				}
				else
				{
					if(right >= :mLength)
						smaller = left
					else
					{
						if(:mData[left] < :mData[right])
							smaller = left
						else
							smaller = right
					}
				}

				if(:mData[index] > :mData[smaller])
				{
					local temp = :mData[index]
					:mData[index] = :mData[smaller]
					:mData[smaller] = temp

					index = smaller
					left = (index * 2) + 1
					right = left + 1
				}
				else
					break
			}

			return data
		}

		function resizeArray()
			if(:mLength >= #:mData)
				#:mData = (#:mData + 1) * 2 - 1

		function hasData() = :mLength != 0
	}

	local object Stack
	{
		mHead = null

		function push(data)
			:mHead = { data = data, next = :mHead }

		function pop()
		{
			if(:mHead is null)
				throw "Stack.pop() - No items to pop"

			local item = :mHead
			:mHead = :mHead.next

			return item.data
		}

		function hasData() = :mHead !is null
	}

	local object Queue
	{
		mHead = null
		mTail = null

		function push(data)
		{
			local t = { data = data, next = null }

			if(:mTail is null)
				:mHead = t
			else
				:mTail.next = t
				
			:mTail = t
		}

		function pop()
		{
			if(:mTail is null)
				throw "Queue.pop() - No items to pop"

			local item = :mHead
			:mHead = :mHead.next

			if(:mHead is null)
				:mTail = null

			return item.data
		}

		function hasData() = :mHead !is null
	}

	writefln("Priority queue (heap)")

	local prioQ = PQ.clone()

	for(i : 0 .. 10)
		prioQ.insert(math.rand(0, 20))

	while(prioQ.hasData())
		writefln(prioQ.remove())

	writefln()
	writefln("Stack")

	local stack = Stack.clone()

	for(i : 0 .. 5)
		stack.push(i + 1)

	while(stack.hasData())
		writefln(stack.pop())

	writefln()
	writefln("Queue")

	local queue = Queue.clone()
	
	for(i : 0 .. 5)
		queue.push(i + 1)
	
	while(queue.hasData())
		writefln(queue.pop())
	
	writefln()
}

// opApply tests.
{
	local object Test
	{
		mData = [4, 5, 6]

		function clone() = object : this { mData = :mData.dup() }

		function opApply(extra)
		{
			if(isString(extra) && extra == "reverse")
			{
				local function iterator_reverse(index)
				{
					index--

					if(index < 0)
						return;

					return index, :mData[index]
				}

				return iterator_reverse, this, #:mData
			}
			else
			{
				local function iterator(index)
				{
					index++

					if(index >= #:mData)
						return;

					return index, :mData[index]
				}

				return iterator, this, -1
			}
		}
	}
	
	local test = Test.clone()
	
	foreach(k, v; test)
		writefln("test[", k, "] = ", v)

	writefln()

	foreach(k, v; test, "reverse")
		writefln("test[", k, "] = ", v)

	writefln()
	
	test =
	{
		fork = 5,
		knife = 10,
		spoon = "hi"
	}
	
	foreach(k, v; test)
		writefln("test[", k, "] = ", v)
	
	test = [5, 10, "hi"]
	
	writefln()
	
	foreach(k, v; test)
		writefln("test[", k, "] = ", v)
	
	writefln()
	
	foreach(k, v; test, "reverse")
		writefln("test[", k, "] = ", v)
	
	writefln()
	
	foreach(k, v; "hello")
		writefln("str[", k, "] = ", v)

	writefln()

	foreach(k, v; "hello", "reverse")
		writefln("str[", k, "] = ", v)
	
	writefln()
}

// Testing upvalues in for loops.
{
	local arr = array.new(10)
	
	for(i : 0 .. 10)
		arr[i] = function() = i

	writefln("This should be the values 0 through 9:")
	
	foreach(func; arr)
		writefln(func())
	
	writefln()
}

// Testing nested functions.
{
	local function outer()
	{
		local x = 3

		function inner()
		{
			x++
			writefln("inner x: ", x)
		}
	
		writefln("outer x: ", x)
		inner()
		writefln("outer x: ", x)
	
		return inner
	}
	
	local func = outer()
	func()
	
	writefln()
}

// Testing Exceptions.
{
	local function thrower(x)
		if(x >= 3)
			throw "Sorry, x is too big for me!"

	local function tryCatch(iterations)
	{
		try
		{
			for(i : 0 .. iterations)
			{
				writefln("tryCatch: ", i)
				thrower(i)
			}
		}
		catch(e)
		{
			writefln("tryCatch caught: ", e)
			throw e
		}
		finally
			writefln("tryCatch finally")
	}
	
	try
	{
		tryCatch(2)
		tryCatch(5)
	}
	catch(e)
		writefln("caught: ", e)

	writefln()
}

// Testing arrays.
{
	local array = [7, 9, 2, 3, 6]
	
	array.sort()

	foreach(i, v; array)
		writefln("arr[", i, "] = ", v)

	array ~= ["foo", "far"]
	
	writefln()
	
	foreach(i, v; array)
		writefln("arr[", i, "] = ", v)

	writefln()
}

// Testing vararg functions.
{
	function vargs(vararg)
	{
		local args = [vararg]
	
		writefln("num varargs: ", #vararg)

		for(i: 0 .. #vararg)
			writefln("args[", i, "] = ", vararg[i])
	}

	vargs()
	writefln()
	vargs(2, 3, 5, "foo", "bar")
	writefln()
}

// Testing switches.
{
	foreach(v; ["hi", "bye", "foo"])
	{
		switch(v)
		{
			case "hi":
				writefln("switched to hi")
				break
				
			case "bye":
				writefln("switched to bye")
				break
				
			default:
				writefln("switched to something else")
				break
		}
	}
	
	writefln()

	foreach(v; [null, false, 1, 2.3, 'x', "hi"])
	{
		switch(v)
		{
			case null: writefln("null"); break
			case false: writefln("false"); break
			case 1: writefln("1"); break
			case 2.3: writefln("2.3"); break
			case 'x': writefln("x"); break
			case "hi": writefln("hi"); break
		}
	}
	
	writefln()

	local object A
	{
		mValue

		function clone(value) =
			object : this { mValue = value }

		function opCmp(other: A) =
			:mValue <=> other.mValue
	}

	local a1 = A.clone(1)
	local a2 = A.clone(2)
	local a3 = A.clone(3)

	for(s: 1 .. 4)
	{
		local ss = A.clone(s)
	
		switch(ss)
		{
			case a1:
				writefln(1)
				break

			case a2:
				writefln(2)
				break
	
			case a3:
				writefln(3)
				break
		}
	}
}+/+/
