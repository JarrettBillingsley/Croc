module samples.missilecommand

import arc.math.collision: boxCircleCollision, circleXYCollision
import arc.draw.color: Color
import arc.window
import arc.input: key, mouse
import arc.time
import arc.draw.shape: drawCircle, drawRectangle, drawLine, drawPixel, drawPolygon
import arc.math.point: Point
import arc.math.size: Size

Color.White = Color(1.0, 1.0, 1.0)
Color.Yellow = Color(1.0, 1.0, 0.0)
Color.Red = Color(1.0, 0.0, 0.0)
Color.Blue = Color(0.0, 0.0, 1.0)

function FreeList(T: class)
{
	T._freelist_ = null
	T._next_ = null
	
	if(hasMethod(T, "initialize"))
	{
		T.alloc = function alloc(this: class, vararg)
		{
			local n

			if(:_freelist_)
			{
				n = :_freelist_
				:_freelist_ = n._next_
			}
			else
				n = this()

			n.initialize(vararg)
			return n
		}
	}
	else
	{
		T.alloc = function alloc(this: class)
		{
			local n

			if(:_freelist_)
			{
				n = :_freelist_
				:_freelist_ = n._next_
			}
			else
				n = this()

			return n
		}
	}

	T.free = function free(this: instance)
	{
		:_next_ = :_freelist_
		:super._freelist_ = this
	}

	return T
}

// @FreeList
// class LinkNode
// {
// 	data
// 	prev
// 	next
// 
// 	function initialize()
// 	{
// 		:data = null
// 		:prev = null
// 		:next = null
// 	}
// }
// 
// class LinkSet
// {
// 	hash
// 	head
// 	tail
// 	shouldRemove = false
// 	
// 	function add(t)
// 	{
// 		if(t in :hash)
// 			return
// 			
// 		local n = LinkNode.alloc()
// 		
// 		if(:head is null)
// 		{
// 			:head = n
// 			:tail = n
// 		}
// 		else
// 		{
// 			:tail.next = n
// 			n.prev = :tail
// 			:tail = n
// 		}
// 		
// 		:tail.data = t
// 		:hash[t] = n
// 	}
// 
// 	function remove(t)
// 	{
// 		if(local node = hash[t])
// 		{
// 			if(node.prev)
// 				node.prev.next = node.next
// 				
// 			if(node.next)
// 				node.next.prev = node.prev
// 				
// 			if(node is :tail)
// 				:tail = node.prev
// 				
// 			if(node is :head)
// 				:head = node.next
// 				
// 			node.free()
// 			:hash[t] = null
// 		}
// 		else
// 			throw "Attempting to remove nonexistent value"
// 	}
// 
// 	function removeCurrent()
// 		:shouldRemove = true
// 
// 
// 	function opApply()
// 	{
// 		if(:head is null)
// 			return null
// 			
// 		function iter(n)
// 		{
// 			local next = n.next
// 			
// 			if(:shouldRemove)
// 			{
// 				:shouldRemove = false
// 				
// 				if(n.prev)
// 					n.prev.next = next
// 					
// 				if(next)
// 					next.prev = n.prev
//
// 				if(n is :tail)
// 					:tail = n.prev
// 					
// 				if(n is :head)
// 					:head = next
// 					
// 				:hash[n.data] = null
// 				n.free()
// 			}
// 		}
// 
// 		:shouldRemove = false
// 		return iter, :head.data, :head
// 	}
// 
// 	public int opApply(int delegate(ref T) dg)
// 	{
// 		if(head is null)
// 			return 0;
// 			
// 		for(auto n = head, next = n.next; n !is null; n = next, next = n ? n.next : null)
// 		{
// 			shouldRemove = false;
// 			
// 			if(auto result = dg(n.data))
// 				return result;
// 				
// 			if(shouldRemove)
// 			{
// 				if(n.prev)
// 					n.prev.next = next;
// 
// 				if(next)
// 					next.prev = n.prev;
// 
// 				if(n is tail)
// 					tail = n.prev;
// 
// 				if(n is head)
// 					head = next;
// 
// 				hash.remove(n.data);
// 				n.free();
// 			}
// 		}
// 
// 		return 0;
// 	}
// 	
// 	public size_t length()
// 	{
// 		return hash.length;
// 	}
// 	
// 	public void clear()
// 	{
// 		foreach(v; *this)
// 			removeCurrent();
// 	}
// 	
// 	public T take()
// 	{
// 		if(head is null)
// 			throw new Exception("Attempting to take item from empty set");
// 
// 		auto n = head;
// 		auto ret = n.data;
// 
// 		if(n.next)
// 			n.next.prev = null;
// 
// 		if(n is tail)
// 			tail = null;
// 
// 		head = n.next;
// 
// 		n.free();
// 		hash.remove(ret);
// 		return ret;
// 	}
// }

@FreeList
class City
{
	cities = {}

	mX
	mY

	function initialize(x: int, y: int)
	{
		:mX = x
		:mY = y
		:super.cities[this] = this
	}

	function draw(g: VectorGraphics)
	{
		g.position(:mX, :mY)
		.move(-18, 0)
		.line(-18, -12)
		.line(-12, -12)
		.line(-12, -6)
		.line(-6, -6)
		.line(-6, -20)
		.line(-12, -25)
		.line(-6, -30)
		.line(0, -30)
		.line(6, -25)
		.line(0, -20)
		.line(0, -6)
		.line(6, -6)
		.line(6, -12)
		.line(18, -12)
		.line(18, 0)
		.line(-18, 0)
	}

	function drawAll(this: class, g: VectorGraphics)
	{
		foreach(c; :cities)
			c.draw(g)
	}

	function destroy(this: class, x: int, y: int, r: int)
	{
		local tmp = {}

 		foreach(c; :cities)
 			if(boxCircleCollision(Point(c.mX - 18, c.mY - 30), Size(36.0, 30.0), Point(x, y), r))
				tmp[c] = c

		foreach(c; tmp)
		{
			:cities[c] = null
			c.free()
		}
	}
}

@FreeList
class Gun
{
	guns = {}

	mX
	mY

	function initialize(x: int, y: int)
	{
		:mX = x
		:mY = y
		:super.guns[this] = this
	}

	function draw(g: VectorGraphics, targetX: int, targetY: int)
	{
		g.position(:mX, :mY)
		.move(18, 0)
		.line(15, -9)
		.line(9, -15)
		.line(0, -18)
		.line(-9, -15)
		.line(-15, -9)
		.line(-18, 0)
		.line(18, 0)

		if(targetY > :mY)
			targetY = :mY

		local theta = math.atan2(targetY - :mY, targetX - :mX);
		local s = math.sin(theta)
		local c = math.cos(theta)

		g.move(toInt(c * 18), toInt(s * 18))
		.line(toInt(c * 24), toInt(s * 24))
	}

	function fire(targetX: int, targetY: int)
		Missile.alloc(:mX, :mY, targetX, targetY, Missile.Player, 2.5, false)

	function clear(this: class)
	{
		foreach(g; :guns)
			g.free();

		:guns = {}
	}

	function drawAll(this: class, g: VectorGraphics, targetX: int, targetY: int)
	{
		foreach(gun; :guns)
			gun.draw(g, targetX, targetY);
	}

	function findClosest(this: class, x: int, y: int)
	{
		if(#:guns == 0)
			return null

		local closest

		foreach(g; :guns)
		{
			if(closest is null)
				closest = g
			else
			{
				if(math.hypot(x - g.mX, y - g.mY) < math.hypot(x - closest.mX, y - closest.mY))
					closest = g
			}
		}

		return closest
	}

	function destroy(this: class, x: int, y: int, r: int)
	{
		local tmp = {}

		foreach(g; :guns)

			if(boxCircleCollision(Point(g.mX - 18, g.mY - 18), Size(36.0, 18.0), Point(x, y), r))
				tmp[g] = g

		foreach(g; tmp)
		{
			:guns[g] = null
			g.free()
		}
	}
}

namespace Letter
{
	function drawText(g: VectorGraphics, x: int, y: int, vararg)
	{
		g.position(x, y)

		foreach(c; format(vararg))
			Letter.draw(g, c)
	}

	function drawCenterText(g: VectorGraphics, x: int, y: int, vararg)
	{
		local str = format(vararg)
		g.position(x - (#str * 24) / 2, y)

		foreach(c; str)
			Letter.draw(g, c)
	}

	function draw(g: VectorGraphics, c: char)
	{
		if(!(c.isLower() || c.isUpper() || c.isDigit() || c == ':' || c == '!'))
			c = ' '

		switch(c)
		{
			case 'A', 'a':
				g.move(0, 0)
				.line(0, -10)
				.line(8, -20)
				.line(16, -10)
				.line(16, 0)
				.move(0, -10)
				.line(16, -10)
				break

			case 'B', 'b':
				g.move(0, 0)
				.line(0, -20)
				.line(16, -10)
				.line(0, -10)
				.line(16, 0)
				.line(0, 0)
				break

			case 'C', 'c':
				g.move(16, -20)
				.line(0, -20)
				.line(0, 0)
				.line(16, 0)
				break

			case 'D', 'd':
				g.move(0, 0)
				.line(0, -20)
				.line(16, -10)
				.line(16, 0)
				.line(0, 0)
				break

			case 'E', 'e':
				g.move(16, -20)
				.line(0, -20)
				.line(0, 0)
				.line(16, 0)
				.move(0, -10)
				.line(10, -10)
				break

			case 'F', 'f':
				g.move(16, -20)
				.line(0, -20)
				.line(0, 0)
				.move(0, -10)
				.line(10, -10)
				break

			case 'G', 'g':
				g.move(16, -20)
				.line(0, -20)
				.line(0, 0)
				.line(16, 0)
				.line(16, -10)
				.line(10, -10)
				break

			case 'H', 'h':
				g.move(0, 0)
				.line(0, -20)
				.move(0, -10)
				.line(16, -10)
				.move(16, 0)
				.line(16, -20)
				break

			case 'I', 'i':
				g.move(0, 0)
				.line(16, 0)
				.move(8, 0)
				.line(8, -20)
				.move(0, -20)
				.line(16, -20)
				break

			case 'J', 'j':
				g.move(0, -20)
				.line(16, -20)
				.move(12, -20)
				.line(12, 0)
				.line(0, 0)
				.line(0, -5)
				break

			case 'K', 'k':
				g.move(0, 0)
				.line(0, -20)
				.move(16, -20)
				.line(0, -10)
				.line(16, 0)
				break

			case 'L', 'l':
				g.move(0, -20)
				.line(0, 0)
				.line(16, 0)
				break

			case 'M', 'm':
				g.move(0, 0)
				.line(0, -20)
				.line(8, -10)
				.line(16, -20)
				.line(16, 0)
				break

			case 'N', 'n':
				g.move(0, 0)
				.line(0, -20)
				.line(16, 0)
				.line(16, -20)
				break

			case 'O', 'o':
				g.move(0, 0)
				.line(0, -20)
				.line(16, -20)
				.line(16, 0)
				.line(0, 0)
				break

			case 'P', 'p':
				g.move(0, 0)
				.line(0, -20)
				.line(16, -20)
				.line(16, -10)
				.line(0, -10)
				break

			case 'Q', 'q':
				g.move(8, -10)
				.line(16, 0)
				.line(0, 0)
				.line(0, -20)
				.line(16, -20)
				.line(16, 0)
				break

			case 'R', 'r':
				g.move(0, 0)
				.line(0, -20)
				.line(16, -20)
				.line(16, -10)
				.line(0, -10)
				.line(16, 0)
				break

			case 'S', 's':
				g.move(16, -20)
				.line(0, -20)
				.line(0, -10)
				.line(16, -10)
				.line(16, 0)
				.line(0, 0)
				break

			case 'T', 't':
				g.move(0, -20)
				.line(16, -20)
				.move(8, 0)
				.line(8, -20)
				break

			case 'U', 'u':
				g.move(0, -20)
				.line(0, 0)
				.line(16, 0)
				.line(16, -20)
				break

			case 'V', 'v':
				g.move(0, -20)
				.line(0, -10)
				.line(8, 0)
				.line(16, -10)
				.line(16, -20)
				break

			case 'W', 'w':
				g.move(0, -20)
				.line(0, 0)
				.line(8, -10)
				.line(16, 0)
				.line(16, -20)
				break

			case 'X', 'x':
				g.move(0, -20)
				.line(16, 0)
				.move(0, 0)
				.line(16, -20)
				break

			case 'Y', 'y':
				g.move(0, -20)
				.line(8, -10)
				.line(8, 0)
				.move(8, -10)
				.line(16, -20)
				break

			case 'Z', 'z':
				g.move(0, -20)
				.line(16, -20)
				.line(0, 0)
				.line(16, 0)
				break

			case '0':
				g.move(16, -20)
				.line(0, 0)
				.line(0, -20)
				.line(16, -20)
				.line(16, 0)
				.line(0, 0)
				break

			case '1':
				g.move(0, 0)
				.line(16, 0)
				.move(8, 0)
				.line(8, -20)
				.line(4, -15)
				break

			case '2':
				g.move(0, -20)
				.line(16, -20)
				.line(16, -10)
				.line(0, -10)
				.line(0, 0)
				.line(16, 0)
				break

			case '3':
				g.move(0, 0)
				.line(16, 0)
				.line(16, -20)
				.line(0, -20)
				.move(16, -10)
				.line(0, -10)
				break

			case '4':
				g.move(16, 0)
				.line(16, -20)
				.line(0, -10)
				.line(16, -10)
				break

			case '5':
				g.move(16, -20)
				.line(0, -20)
				.line(0, -10)
				.line(16, -10)
				.line(16, 0)
				.line(0, 0)
				break

			case '6':
				g.move(16, -20)
				.line(0, -20)
				.line(0, 0)
				.line(16, 0)
				.line(16, -10)
				.line(0, -10)
				break

			case '7':
				g.move(0, -20)
				.line(16, -20)
				.line(16, 0)
				break

			case '8':
				g.move(0, 0)
				.line(0, -20)
				.line(16, -20)
				.line(16, 0)
				.line(0, 0)
				.move(0, -10)
				.line(16, -10)
				break

			case '9':
				g.move(0, 0)
				.line(16, 0)
				.line(16, -20)
				.line(0, -20)
				.line(0, -10)
				.line(16, -10)
				break

			case ':':
				g.move(8, -18)
				.line(8, -14)
				.move(8, -6)
				.line(8, -2)
				break

			case '!':
				g.move(8, -20)
				.line(8, -8)
				.move(8, -3)
				.line(8, 0)
				break

			case ' ': break
		}

		g.translate(24, 0)
	}
}

@FreeList
class Missile
{
	Player = 0
	Enemy = 1

	missiles = {}
	numMissilesKilled = 0

	function numKilled(this: class)
	{
		local ret = :numMissilesKilled
		:numMissilesKilled = 0
		return ret
	}

	mStartX
	mStartY
	mDestX
	mDestY
	mCurX = 0
	mCurY = 0
	mSide
	mTheta
	mAlive = true
	mExploding = false
	mHit = false
	mPosition = 0
	mMaxPosition
	mSpeed
	mIsMIRV = false
	mMIRVPos = 0

	function initialize(startX: int, startY: int, destX: int, destY: int, side: int, speed: float, allowMIRV: bool)
	{
		:mStartX = startX
		:mStartY = startY
		:mDestX = destX
		:mDestY = destY
		:mCurX = 0
		:mCurY = 0
		:mSide = side
		:mTheta = math.atan2(destY - startY, destX - startX)
		:mAlive = true
		:mExploding = false
		:mHit = false
		:mPosition = 0
		:mMaxPosition = math.hypot(destY - startY, destX - startX)
		:mSpeed = speed
		:mIsMIRV = false

		if(allowMIRV && side == Missile.Enemy)
		{
			if(math.rand(15) == 0)
			{
				:mIsMIRV = true
				:mMIRVPos = (:mMaxPosition / 3) + math.frand(1.0) * (:mMaxPosition / 3)
			}
		}

		:super.missiles[this] = this
	}

	function run()
	{
		if(!:mAlive)
			return false

		if(:mExploding)
		{
			if(:mPosition < 30)
			{
				if(:mHit)
				{
					local ex = :mStartX + :mCurX
					local ey = :mStartY + :mCurY

					if(:mSide == Missile.Player)
						Missile.destroy(ex, ey, toInt(:mPosition))
					else
					{
						City.destroy(ex, ey, toInt(:mPosition))
						Gun.destroy(ex, ey, toInt(:mPosition))
					}
				}

				:mPosition++
				return true
			}
			else
			{
				:mAlive = false
				return false
			}
		}
		else
		{
			:mPosition += :mSpeed

			if(:mPosition >= :mMaxPosition)
			{
				:mCurX = :mDestX - :mStartX
				:mCurY = :mDestY - :mStartY
				:blowUp(true)
			}
			else if(:mIsMIRV && :mPosition >= :mMIRVPos)
			{
				local startX = :mStartX + toInt(math.cos(:mTheta) * :mMIRVPos)
    			local startY = :mStartY + toInt(math.sin(:mTheta) * :mMIRVPos)

    			for(i: 0 .. 3)
					Missile.alloc(startX, startY, startX + math.rand(200) - 100, 545, Missile.Enemy, :mSpeed, false)

				:blowUp(false)
			}
			else
			{
    			:mCurX = toInt(math.cos(:mTheta) * :mPosition)
    			:mCurY = toInt(math.sin(:mTheta) * :mPosition)
			}

			return true
		}
	}

	function blowUp(hit: bool)
	{
		:mPosition = 0
		:mExploding = true
		:mHit = hit
		:mPosition = 0
	}

	function draw(g: VectorGraphics)
	{
		if(:mSide == Missile.Player)
			g.color(Color.Blue)
		else
			g.color(Color.Red)

		g.position(:mStartX, :mStartY)
		.line(:mCurX, :mCurY)

		if(:mExploding)
			g.circle(:mPosition)
	}

	function drawAll(this: class, g: VectorGraphics)
	{
		foreach(m; :missiles)
			m.draw(g)
	}

	function update(this: class)
	{
		local tmp = {}

		foreach(m; :missiles)
			if(!m.run())
				tmp[m] = m
				
		foreach(m; tmp)
		{
			:missiles[m] = null
			m.free()
		}
	}

	function destroy(x: int, y: int, r: int)
	{
		foreach(m; :missiles)
		{
			if(m.mSide == Missile.Enemy && !m.mExploding && circleXYCollision(Point(m.mStartX + m.mCurX, m.mStartY + m.mCurY), Point(x, y), r))
			{
				:numMissilesKilled++
				m.blowUp(false)
			}
		}
	}
}

class VectorGraphics
{
	mBaseX = 0
	mBaseY = 0
	mX = 0
	mY = 0
	mColor = Color.White

	function move(x: int, y: int)
	{
		:mX = x
		:mY = y
		return this
	}

	function line(x: int, y: int)
	{
		drawLine(Point(:mBaseX + :mX, :mBaseY + :mY), Point(:mBaseX + x, :mBaseY + y), :mColor)
		:mX = x
		:mY = y
		return this
	}

	function translate(x: int, y: int)
	{
		:mBaseX += x
		:mBaseY += y
		return :move(0, 0)
	}

	function position(x: int, y: int)
	{
		:mBaseX = x
		:mBaseY = y
		return :move(0, 0)
	}

	function color(c: Color)
	{
		:mColor = c
		return this
	}

	function circle(r: int)
	{
		drawCircle(Point(:mBaseX + :mX, :mBaseY + :mY), r, 20, :mColor, true)
		return this
	}
}

function enum(name: string, vararg)
{
	local sb = StringBuffer()

	sb.append("namespace ", name, "\n{\n")

	for(i: 0 .. #vararg)
		sb.append("\t", vararg[i], " = ", i, "\n")

	sb.append("}")

	loadString(sb.toString())()
}


enum("GameState",
	"Waiting",
	"Playing",
	"RoundOver",
	"GameOver",
	"EnterInitials",
	"HiScores"
)

class Game
{
	mRound = 0
	mMissiles = 0
	mScore = 0
	mVG
	mState = GameState.Waiting
	mInitials
	mHiScores
	mCityBonus = 0
	mAttacker
// 	mSocket

	this()
	{
		arc.window.open("Missile Command", 600, 600, false)
		arc.input.open()
		arc.time.open()
		arc.input.defaultCursorVisible(false)

		:mVG = VectorGraphics()
	}

	function onClick()
	{
		switch(:mState)
		{
			case GameState.Waiting:
			case GameState.HiScores:
				City.alloc(85, 560);
				City.alloc(165, 560);
				City.alloc(245, 560);
				City.alloc(355, 560);
				City.alloc(435, 560);
				City.alloc(515, 560);

				:newRound(1)
				break;

			case GameState.Playing:
				local x = toInt(arc.input.mouseX())
				local y = math.min(math.max(toInt(arc.input.mouseY()), 30), 560)

				local g = Gun.findClosest(x, y)

				if(g !is null)
					g.fire(x, y)

				break

			case GameState.RoundOver:
				:newRound(:mRound + 1)
				break

			case GameState.GameOver:
				if(#Missile.missiles == 0)
				{
// 					:mSocket = SocketStream()
// 					:mSocket.socket().blocking(true)
// 					:mSocket.connect(InternetAddress("localhost", 8844))
// 
// 					try
// 					{
// 						:mSocket.formatln("{}", :mScore)
// 
// 						if(:mSocket.readln() == "WINNER")
// 						{
// 							:mInitials = ""
// 							:mState = GameState.EnterInitials
// 						}
// 						else
						{
							:getHiScores()
							:mState = GameState.HiScores
						}
// 					}
// 					finally
// 						:mSocket.close()
				}

				break

			case GameState.EnterInitials:
// 				if(#:mInitials == 3)
// 				{
// 					:mSocket.formatln("{}", :mInitials)
// 					:getHiScores()
// 					:mState = GameState.HiScores
// 				}
				break
		}
	}

	function newRound(round: int)
	{
		:mRound = round
		:mMissiles = :mRound * 2 + 1

		if(:mRound == 1)
			:mScore = 0

		Gun.clear()
		Gun.alloc(30, 560)
		Gun.alloc(300, 560)
		Gun.alloc(570, 560)

		:mState = GameState.Playing

		if(:mAttacker is null)
			:mAttacker = coroutine :attacker
		else
		{
			assert(:mAttacker.isDead())
			:mAttacker.reset()
		}
	}

	function getHiScores()
	{
		:mHiScores = []
		
// 		try
// 		{
// 			foreach(line; :mSocketIn)
// 			{
// 				if(line == "DONE")
// 					break
// 
// 				auto spacePos = line.find(' ')
// 				:mHiScores ~= [line[.. spacePos], line[spacePos + 1 ..]]
// 			}
// 		}
// 		finally
// 			:mSocket.close()
	}

	function draw()
	{
		arc.window.clear()
		:mVG.color(Color.White)

		local mouseX = toInt(arc.input.mouseX())
		local mouseY = toInt(arc.input.mouseY())

		switch(:mState)
		{
			case GameState.Waiting:
				Letter.drawCenterText(:mVG, 300, 300, "Missile Command")
				Letter.drawCenterText(:mVG, 300, 330, "Insert Coin")
				break

			case GameState.Playing:
			case GameState.GameOver:
				Letter.drawText(:mVG, 10, 590, "Score:{}", :mScore)
				Letter.drawText(:mVG, 10, 30, "Missiles:{}", :mMissiles)
				Letter.drawText(:mVG, 380, 590, "Round:{}", :mRound)

				if(:mState == GameState.Playing && #City.cities == 0)
					:mState = GameState.GameOver

				City.drawAll(:mVG)
				Gun.drawAll(:mVG, mouseX, mouseY)

				local noMissilesLeft = #Missile.missiles == 0
				Missile.drawAll(:mVG)

				:mScore += Missile.numKilled() * 25

				if(:mState == GameState.Playing && :mMissiles == 0 && noMissilesLeft)
				{
					:mState = GameState.RoundOver
					:mCityBonus = #City.cities * 50
					:mScore += :mCityBonus
				}

				if(:mState == GameState.GameOver)
				{
					:mVG.color(Color.White);
					Letter.drawCenterText(:mVG, 300, 300, "Game Over")
				}
				break

			case GameState.RoundOver:
				Letter.drawCenterText(:mVG, 300, 300, "Round Over")
				Letter.drawCenterText(:mVG, 300, 330, "City bonus:{}", :mCityBonus)
				break

			case GameState.EnterInitials:
				:mVG.color(Color.Yellow)
				Letter.drawCenterText(:mVG, 300, 200, "You have a")
				Letter.drawCenterText(:mVG, 300, 230, "high score!")
				Letter.drawCenterText(:mVG, 300, 260, "Enter your initials:")
				Letter.drawCenterText(:mVG, 300, 300, :mInitials)
				break

			case GameState.HiScores:
				:mVG.color(Color.Yellow)
				Letter.drawCenterText(:mVG, 300, 100, "High Scores")

				:mVG.color(Color.White)

				foreach(i, score; :mHiScores)
				{
					local y = 160 + i * 30

					Letter.drawText(:mVG, 216, y, score[0])
					Letter.drawText(:mVG, 312, y, score[1])
				}
				break
		}

		:mVG.color(Color.White)
		.position(mouseX, mouseY)
		.move(0, -10)
		.line(0, 10)
		.move(-10, 0)
		.line(10, 0)

		arc.window.swap()
	}

	function updateInitials()
	{
		foreach(c; arc.input.lastChars())
		{
			if(c.isAlpha())
			{
				if(#:mInitials)
					:mInitials ~= c
			}
			else if(c == '\b')
			{
				if(#:mInitials)
					:mInitials = :mInitials[.. -1]
			}
		}
	}

	function update()
	{
		arc.input.process()
		arc.time.process()

		switch(:mState)
		{
			case GameState.Waiting:
				break

			case GameState.Playing:
			case GameState.GameOver:
				if(!:mAttacker.isDead())
					:mAttacker()

				Missile.update()
				break

			case GameState.RoundOver:
				break

			case GameState.EnterInitials:
				:updateInitials()
				break

			case GameState.HiScores:
				break
		}

		if(arc.input.mouseButtonPressed(mouse.Left))
			:onClick()
	}

	function run()
	{
		while(!arc.input.keyDown(key.Quit))
		{
			:update()
			:draw()
			arc.time.limitFPS(60)
		}

		arc.time.close()
		arc.input.close()
		arc.window.close()
	}

	function attacker()
	{
		local speed = 0.6 + 0.15 * :mRound
		local time = arc.time.getTime()

		while(:mMissiles > 0)
		{
			local ms = arc.time.getTime()

			if(ms - time >= 2000)
			{
				time = ms
				Missile.alloc(math.rand(600), 30, math.rand(600), 545, Missile.Enemy, speed, :mRound >= 4)
				:mMissiles--
			}

			yield()
		}
	}
}

function main()
{
	Game().run()
}