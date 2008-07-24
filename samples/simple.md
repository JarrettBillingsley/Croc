module simple

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
			return rawGet(this, name)
		else
			return oldField(with this, name)
	}

	T.opFieldAssign = function opFieldAssign(name, value)
	{
		if(local prop = properties[name])
			return prop.set(this, value)

		if(oldFieldAssign is null)
			rawSet(this, name, value)
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
	local function loadMod(name, ns)
	{
		assert(name == "mod")

		ns.x = "I'm x"

		ns.foo = function foo()
			writefln("foo")

		ns.bar = function bar(x) = x[0]

		ns.baz = function baz()
			writefln(x)

		foreach(k, v; ns)
			if(isFunction(v))
				v.environment(ns)
	}

	setModuleLoader("mod", loadMod)

	import mod : foo, bar
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

		function clone(value) = object : this { mValue = value }

		function opCmp(other)
		{
			assert(other as A)
			return :mValue <=> other.mValue
		}
	}

	local a1 = A.clone(1)
	local a2 = A.clone(2)
	local a3 = A.clone(3)

	for(s : 1 .. 4)
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
}