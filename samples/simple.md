module samples.simple

/+import sdl: event, key
import gl

/*
function cross(a1, a2, a3, b1, b2, b3)
	return	a2 * b3 - a3 * b2,
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
+/
