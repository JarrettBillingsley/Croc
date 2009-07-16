module samples.simple

import serialization: serializeGraph, deserializeGraph

class A
{
	this(x, y)
		:x, :y = x, y

	function toString() = format("<x = {} y = {}>", :x, :y)
}

class B
{
	this(x, y)
		:x, :y = x, y

	function toString() = format("<x = {} y = {}>", :x, :y)

	function opSerialize(s, f)
	{
		f(:x)
		f(:y)
		s.writeChars("lol")
	}

	function opDeserialize(s, f)
	{
		:x = f()
		:y = f()
		writeln$ s.readChars(3)
	}
}

local obj = [weakref(A(4, 5))]
local trans =
{
	[writeln] = 1,
	[writefln] = 2,
	[Vector] = 3,
	[StringBuffer] = 4,
	[_G] = 5
}

local f = io.outFile("temp.dat")
serializeGraph(obj, trans, f)

f.close()
f = io.inFile("temp.dat")
trans = {[v] = k for k, v in trans}
obj = deserializeGraph(trans, f)

dumpVal$ obj


/+import sdl: event, key
import gl

/*
function cross(a1, a2, a3, b1, b2, b3)
	return  a2 * b3 - a3 * b2,
			a3 * b1 - a1 * b3,
			a1 * b2 - a2 * b1

function normalize(x, y, z)
{
	local len = math.sqrt(x * x + y * y + z * z)
	return x / len, y / len, z / len
}

local f = io.inFile("object.dat")
local numVerts = f.readInt()
local vertData = f.readVector$ "f32", numVerts * 3
local numFaceVerts = f.readInt()
local numFaces = f.readInt()
local faceData = f.readVector$ "u16", numFaceVerts * numFaces
f.close()

// 1. triangulate faces
io.stdout.writeln("triangulating..").flush()

local newFaces = Vector("u16", numFaces * 6)

for(local i = 0, local j = 0; i < #faceData; i += 4, j += 6)
{
	newFaces[j] = faceData[i]
	newFaces[j + 1] = faceData[i + 1]
	newFaces[j + 2] = faceData[i + 2]

	newFaces[j + 3] = faceData[i + 2]
	newFaces[j + 4] = faceData[i + 3]
	newFaces[j + 5] = faceData[i]
}

#faceData = 0
faceData = newFaces
numFaces = #faceData / 3
numFaceVerts = 3

// 2. figure out face normals (ab x bc) and accumulate vertex normals
io.stdout.writeln("calculating normals..").flush()

local vertNormals = Vector("f32", #vertData, 0)

function getVert(idx)
{
	idx *= 3
	return vertData[idx], vertData[idx + 1], vertData[idx + 2]
}

function addVertNormal(idx, x, y, z)
{
	idx *= 3
	vertNormals[idx] += x
	vertNormals[idx + 1] += y
	vertNormals[idx + 2] += z
}

for(i: 0 .. #faceData, 3)
{
	local v1 = faceData[i]
	local x1, y1, z1 = getVert(v1)

	local v2 = faceData[i + 1]
	local x2, y2, z2 = getVert(v2)

	local v3 = faceData[i + 2]
	local x3, y3, z3 = getVert(v3)

	local nx, ny, nz = normalize(cross(x2 - x1, y2 - y1, z2 - z1, x2 - x3, y2 - y3, z2 - z3))

	addVertNormal(v1, nx, ny, nz)
	addVertNormal(v2, nx, ny, nz)
	addVertNormal(v3, nx, ny, nz)
}

// 3. normalize vertex normals
io.stdout.writeln("normalizing vertex normals..").flush()

for(i: 0 .. numVerts * 3, 3)
{
	local nx, ny, nz = normalize(vertNormals[i], vertNormals[i + 1], vertNormals[i + 2])
	vertNormals[i] = nx
	vertNormals[i + 1] = ny
	vertNormals[i + 2] = nz
}

// 4. write it out
io.stdout.writeln("writing data..").flush()

local allVertData = Vector("f32", #vertData + #vertNormals)

for(local i = 0, local j = 0; i < #vertData; i += 3, j += 6)
{
	allVertData[j] = vertData[i]
	allVertData[j + 1] = vertData[i + 1]
	allVertData[j + 2] = vertData[i + 2]

	allVertData[j + 3] = vertNormals[i]
	allVertData[j + 4] = vertNormals[i + 1]
	allVertData[j + 5] = vertNormals[i + 2]
}

vertData = allVertData

f = io.outFile("object2.dat")
f.writeInt(numVerts)
f.writeVector(vertData)
f.writeInt(numFaceVerts)
f.writeInt(numFaces)
f.writeVector(faceData)
f.flush().close()

thread.halt()

// */

function float4(x, y, z, w) = Vector.fromArray$ "f32", [x, y, z, w]

{
	local tmp = Vector$ gl.GLuint, 1

	function genOneBuffer()
	{
		gl.glGenBuffers(1, tmp)
		return tmp[0]
	}
}

class Mesh
{
	function load(this: class, file: string)
	{
		local f = io.inFile(file)

		local numVerts = f.readInt()
		local vertData = f.readVector$ "f32", numVerts * 6
		local numFaceVerts = f.readInt()
		local numFaces = f.readInt()
		local faceData = f.readVector$ "u16", numFaceVerts * numFaces
		
		f.close()

		local vertBuf = genOneBuffer()
		gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vertBuf)
		gl.glBufferData(gl.GL_ARRAY_BUFFER, #vertData * vertData.itemSize(), vertData, gl.GL_STREAM_DRAW)

		local indexBuf = genOneBuffer()
		gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, indexBuf)
		gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, #faceData * faceData.itemSize(), faceData, gl.GL_STREAM_DRAW)
		
		// can't hurt to deallocate the memory in advance
		#vertData = 0
		#faceData = 0

		return Mesh(vertBuf, indexBuf, numFaces, numFaceVerts == 4)
	}

	this(vertBuf, indexBuf, numFaces, isQuads: bool)
	{
		:mVB = vertBuf
		:mIB = indexBuf
		:mNumElems = numFaces * (isQuads ? 4 : 3)
		:mType = isQuads ? gl.GL_QUADS : gl.GL_TRIANGLES
	}

	function draw()
	{
		gl.glEnableClientState(gl.GL_VERTEX_ARRAY)
		gl.glEnableClientState(gl.GL_NORMAL_ARRAY)
		gl.glBindBuffer(gl.GL_ARRAY_BUFFER, :mVB)
		gl.glVertexPointer(3, gl.GL_FLOAT, 24, 0)
		gl.glNormalPointer(gl.GL_FLOAT, 24, 12)

		gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, :mIB)

		gl.glDrawElements(:mType, :mNumElems, gl.GL_UNSIGNED_SHORT, null)

		gl.glDisableClientState(gl.GL_VERTEX_ARRAY)
		gl.glDisableClientState(gl.GL_NORMAL_ARRAY)
	}
}

function main()
{
	sdl.init(sdl.initEverything)

	scope(exit)
		sdl.quit()

	sdl.gl.setAttribute(sdl.gl.bufferSize, 32)
	sdl.gl.setAttribute(sdl.gl.depthSize, 16)
	sdl.gl.setAttribute(sdl.gl.doubleBuffer, 1)

	local w = 1152
	local h = 864

	if(!sdl.setVideoMode(w, h, 32, sdl.opengl | sdl.hwSurface))
		if(!sdl.setVideoMode(w, h, 32, sdl.opengl | sdl.swSurface))
			throw "Could not set video mode"

	sdl.setCaption("foobar!")
	sdl.showCursor(false)
// 	sdl.grabInput(true)

	gl.load()

	gl.glViewport(0, 0, w, h)
	gl.glShadeModel(gl.GL_SMOOTH)
	gl.glClearColor(0, 0, 0, 1)
	gl.glClearDepth(1)
// 	gl.glEnable(gl.GL_CULL_FACE)
	gl.glEnable(gl.GL_DEPTH_TEST)
// 	gl.glEnable(gl.GL_TEXTURE_2D)

// 	gl.glEnable(gl.GL_BLEND)
// 	gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA)

	gl.glEnable(gl.GL_LIGHTING)
	gl.glEnable(gl.GL_LIGHT0)
	gl.glLightfv(gl.GL_LIGHT0, gl.GL_POSITION, float4(-1, -1, -1, 0))
	gl.glLightfv(gl.GL_LIGHT0, gl.GL_AMBIENT,  float4(0.3, 0.3, 0.3, 1))
// 	gl.glEnable(gl.GL_COLOR_MATERIAL)

	gl.glMatrixMode(gl.GL_PROJECTION)
	gl.glLoadIdentity()
	gl.gluPerspective(45, 800.0 / 600.0, 3, 100000)
	gl.glMatrixMode(gl.GL_MODELVIEW)

	gl.glMaterialfv$ gl.GL_FRONT_AND_BACK, gl.GL_AMBIENT_AND_DIFFUSE, float4(108 / 255.0, 120 / 255.0, 134 / 255.0, 1.0)

	local camx = 0
	local camy = 0
	local camz = 700
	local camxang = 0
	local camyang = 0

	local quitting = false

	event.setHandler$ event.quit, \{ quitting = true }
	
	local keys = array.new(512)

	event.setHandler$ event.key, \pressed, sym, mod
	{
		keys[sym] = pressed
	}

	local first = true
	local numMoves = 0

	event.setHandler$ event.mouseMotion, \x, y, xrel, yrel
	{
		if(first)
		{
			first = false
			return
		}

		camxang -= yrel * 0.05
		camyang -= xrel * 0.05

		numMoves++
	}

	local ang1 = 0

	local mesh = Mesh.load("object2.dat")

	local frames = 0
	local startTime = time.microTime()

	while(!quitting)
	{
		event.poll()

		if(keys[key.escape])
			quitting = true

		if(keys[key.left])
			ang1 = (ang1 + 1) % 360
		else if(keys[key.right])
			ang1 = (ang1 - 1) % 360

		gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT)
			gl.glLoadIdentity()
			gl.glRotatef(-camyang, 0, 1, 0)
			gl.glRotatef(-camxang, 1, 0, 0)
			gl.glTranslatef(-camx, -camy, -camz)

			gl.glPushMatrix()
				gl.glRotatef(15, 1, 0, 0)
				gl.glRotatef(ang1, 0, 1, 0)
				gl.glTranslatef(0, -450, 0)

				mesh.draw()
			gl.glPopMatrix()
		sdl.gl.swapBuffers()

		frames++
// 		for(i: 0 .. 200_000){}
	}

	startTime = (time.microTime() - startTime) / 1_000_000.0
	writefln$ "Rendered {} frames in {:f2} seconds ({:f2} fps)", frames, startTime, frames / startTime
	writefln$ "Received {} move events in that time ({:f2} per second)", numMoves, numMoves / startTime
}

/+
// Making sure finally blocks are executed.
{
	local function f()
	{
		try
		{
			try
			{
				writeln("hi 1")
				return "foo", "bar"
			}
			finally
				writeln("bye 1")

			writeln("no use 1")
		}
		finally
			writeln("bye 2")

		writeln("no use 2")
	}

	writefln("{}, {}", f())
	writeln()
}

// Importing stuff.
{
	modules.customLoaders.mod = function loadMod(name: string)
	{
		assert(name == "mod")

		global x = "I'm x"

		global function foo()
			writeln("foo")

		global function bar(x) = x[0]

		global function baz()
			writeln(x)
	}

	import mod: foo, bar
	foo()
	writeln(bar([5]))
	mod.baz()

	writeln()
}

// Super calls.
{
	local class Base
	{
		function fork()
			writeln("Base fork.")
	}

	local class Derived : Base
	{
		function fork()
		{
			writeln("Derived fork!")
			super.fork()
		}
	}

	local d = Derived()
	d.fork()

	writeln()
}

// Coroutines and coroutine iteration.
{
	function countDown(x) = coroutine function()
		{
			while(x > 0)
			{
				yield(null, x)
				x--
			}
		}

	foreach(v; countDown(5))
		writeln(v)

	writeln()

	function forEach(t) = coroutine function()
		{
			foreach(k, v; t)
				yield(k, v)
		}

	foreach(k, v; forEach({hi = 1, bye = 2}))
		writefln("key: {}, value: {}", k, v)

	writeln()
}

// Testing tailcalls.
{
	local function recurse(x)
	{
		writeln("recurse: ", x)
	
		if(x == 0)
			return toString(x)
		else
			return recurse(x - 1)
	}

	writeln(recurse(5))
	writeln()

	local class A
	{
		function f(x)
		{
			writeln("A.f: ", x)

			if(x == 0)
				return toString(x)
			else
				return :f(x - 1)
		}
	}

	writeln(A.f(5))
	writeln()
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
				throw format("Property {} is not a table", i)

			if(prop.name is null)
				throw format("Property {} has no name", i)

			if(prop.setter is null && prop.getter is null)
				throw format("Property '{}' has no getter or setter", prop.name)

			T._props[prop.name] = prop
		}
	}
	
	// Create an object to test out.
	local class PropTest
	{
		mX = 0
		mY = 0
		mName = ""

		this(name) :mName = name
		function toString() = format("name = '{}' x = {} y = {}", :mName, :mX, :mY)
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
	local p = PropTest("hello")
	
	writeln(p)
	p.x = 46
	p.y = 123
	p.x = p.x + p.y
	writeln(p)
	
	// Try to access a nonexistent property.
	try
		p.name = "crap"
	catch(e)
		writeln("caught: ", e)

	writeln()
}

// Some containers.
{
	local class PQ
	{
		mData
		mLength = 0

		this() :mData = array.new(15)

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

	local class Stack
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

	local class Queue
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

	writeln("Priority queue (heap)")

	local prioQ = PQ()

	for(i : 0 .. 10)
		prioQ.insert(math.rand(0, 20))

	while(prioQ.hasData())
		writeln(prioQ.remove())

	writeln()
	writeln("Stack")

	local stack = Stack()

	for(i : 0 .. 5)
		stack.push(i + 1)

	while(stack.hasData())
		writeln(stack.pop())

	writeln()
	writeln("Queue")

	local queue = Queue()

	for(i : 0 .. 5)
		queue.push(i + 1)

	while(queue.hasData())
		writeln(queue.pop())

	writeln()
}

// opApply tests.
{
	local class Test
	{
		mData = [4, 5, 6]

		this() :mData = :mData.dup()

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
	
	local test = Test()
	
	foreach(k, v; test)
		writefln("test[{}] = {}", k, v)

	writeln()

	foreach(k, v; test, "reverse")
		writefln("test[{}] = {}", k, v)

	writeln()

	test =
	{
		fork = 5,
		knife = 10,
		spoon = "hi"
	}

	foreach(k, v; test)
		writefln("test[{}] = {}", k, v)

	test = [5, 10, "hi"]

	writeln()

	foreach(k, v; test)
		writefln("test[{}] = {}", k, v)

	writeln()

	foreach(k, v; test, "reverse")
		writefln("test[{}] = {}", k, v)

	writeln()

	foreach(k, v; "hello")
		writefln("str[{}] = {}", k, v)

	writeln()

	foreach(k, v; "hello", "reverse")
		writefln("str[{}] = {}", k, v)

	writeln()
}

// Testing upvalues in for loops.
{
	local arr = array.new(10)

	for(i : 0 .. 10)
		arr[i] = function() = i

	writeln("This should be the values 0 through 9:")

	foreach(func; arr)
		writeln(func())

	writeln()
}

// Testing nested functions.
{
	local function outer()
	{
		local x = 3

		function inner()
		{
			x++
			writeln("inner x: ", x)
		}

		writeln("outer x: ", x)
		inner()
		writeln("outer x: ", x)

		return inner
	}

	local func = outer()
	func()

	writeln()
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
				writeln("tryCatch: ", i)
				thrower(i)
			}
		}
		catch(e)
		{
			writeln("tryCatch caught: ", e)
			throw e
		}
		finally
			writeln("tryCatch finally")
	}

	try
	{
		tryCatch(2)
		tryCatch(5)
	}
	catch(e)
		writeln("caught: ", e)

	writeln()
}

// Testing arrays.
{
	local array = [7, 9, 2, 3, 6]

	array.sort()

	foreach(i, v; array)
		writefln("arr[{}] = {}", i, v)

	array ~= ["foo", "far"]

	writeln()

	foreach(i, v; array)
		writefln("arr[{}] = {}", i, v)

	writeln()
}

// Testing vararg functions.
{
	function vargs(vararg)
	{
		local args = [vararg]

		writeln("num varargs: ", #vararg)

		for(i: 0 .. #vararg)
			writefln("args[{}] = {}", i, vararg[i])
	}

	vargs()
	writeln()
	vargs(2, 3, 5, "foo", "bar")
	writeln()
}

// Testing switches.
{
	foreach(v; ["hi", "bye", "foo"])
	{
		switch(v)
		{
			case "hi":
				writeln("switched to hi")
				break

			case "bye":
				writeln("switched to bye")
				break

			default:
				writeln("switched to something else")
				break
		}
	}

	writeln()

	foreach(v; [null, false, 1, 2.3, 'x', "hi"])
	{
		switch(v)
		{
			case null: writeln("null"); break
			case false: writeln("false"); break
			case 1: writeln("1"); break
			case 2.3: writeln("2.3"); break
			case 'x': writeln("x"); break
			case "hi": writeln("hi"); break
		}
	}

	writeln()

	local class A
	{
		mValue

		this(value)
			:mValue = value

		function opCmp(other: A) =
			:mValue <=> other.mValue
	}

	local a1 = A(1)
	local a2 = A(2)
	local a3 = A(3)

	for(s: 1 .. 4)
	{
		local ss = A(s)

		switch(ss)
		{
			case a1:
				writeln(1)
				break

			case a2:
				writeln(2)
				break

			case a3:
				writeln(3)
				break
		}
	}
}+/+/