module samples.arctest

import arc.draw.color: Color
import arc.draw.image: drawImage, drawImageTopLeft
import arc.draw.shape: drawCircle, drawRectangle, drawLine, drawPixel, drawPolygon
import arc.font: Font
import arc.input: key, mouse
import arc.math.point: Point
import arc.math.size: Size
import arc.sound: Sound, SoundFile
import arc.texture: Texture
import arc.time
import arc.window

import time: microTime

Point.Origin = Point(0, 0)
Color.White = Color(1.0, 1.0, 1.0, 1.0)

class ParticleGen
{
	mSize = Size(math.nan, math.nan)
	mParticles
	mFreeParticles
	mRate
	mGravity
	mLife
	mLast

	this(rate: int|float, gravity: int|float = 0.05, life: int|float = 2.5)
	{
		:mRate = toFloat(rate)
		:mGravity = toFloat(gravity)
		:mLife = toInt(life * 1_000_000)
		:mLast = microTime()
	}

	function generate(pos)
	{
		local time = microTime()

		if((time - :mLast) < :mRate)
			return

		local part

		if(:mFreeParticles is null)
			part = { color = Color(1.0, 1.0, 1.0) }
		else
		{
			part = :mFreeParticles
			:mFreeParticles = part.next
		}

		local ang = math.rand(360)
		part.pos = pos
		part.vx = math.sin(ang) * math.frand(1.5)
		part.vy = math.cos(ang) * math.frand(1.5)
		part.va = math.frand(-0.1, 0.1)
		part.ang = ang
		part.color.r = 1.0
		part.color.g = 1.0
		part.color.b = 1.0
		part.color.a = 1.0
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

			v.color.a = 1.0 - (t / toFloat(:mLife))

			v.vy -= :mGravity;
			v.pos.y -= v.vy;
			v.pos.x += v.vx;
			v.ang += v.va

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

			//drawCircle(v.pos, 2, 8, v.color, true)
			drawImage(:mImage, v.pos, :mSize, Point.Origin, v.ang, v.color)
			old = v
			v = v.next
		}
	}
}

function main()
{
	arc.window.open("Hello world", 1024, 768, false)
	arc.input.open()
	arc.font.open()
	arc.time.open()
	arc.sound.open()

	local font = Font("arial.ttf", 12)
// 	local font2 = Font("arial.ttf", 32)

	local pg = ParticleGen(1000, 0.3, 1)
	pg.mImage = Texture("explode.png")
	pg.mSize = Size(32.0, 32.0)

	arc.input.defaultCursorVisible(false)

	while(!arc.input.keyDown(key.Quit) && !arc.input.keyDown(key.Esc))
	{
		arc.input.process()
		arc.window.clear()
		arc.time.process()
		arc.sound.process()

		if(arc.input.mouseButtonDown(mouse.Left))
			pg.generate(arc.input.mousePos())

		pg.process()

		drawCircle(arc.input.mousePos(), 6, 10, Color.White, false)

		font.draw(format("{}\n{}\n{}", arc.time.fps(), pg.mParticles is null, gc.allocated()), Point.Origin, Color.White)

// 		font.draw(toString(arc.time.fps()), origin, Color.White)
// 		font.draw(toString(pg.mParticles is null), Point(0, 16), Color.White)
// 		font.draw(toString(totalBytes()), Point(0, 32), Color.White)
		arc.time.limitFPS(60)
		arc.window.swap()
	}

	arc.sound.close()
	arc.time.close()
	arc.font.close()
	arc.input.close()
	arc.window.close()
}