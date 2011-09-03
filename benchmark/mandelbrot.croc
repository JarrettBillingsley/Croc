module benchmark.mandelbrot

import io: stdout, stderr

if(true)
{
	global function writeHeader(w, h)
		writefln("P4\n{} {}", w, h)

	global function writePixels(val)
		stdout.writeByte(255 - val)
		
	global function finish()
		stdout.flush()
}
else
{
	local width, height, extra

	global function writeHeader(w, h)
	{
		width = w
		extra = (4 - ((w * 3) % 4)) % 4
		height = h

		stdout.writeChars("BM")
			.writeInt(0)
			.writeInt(0)
			.writeInt(54)
			.writeInt(40)
			.writeInt(w)
			.writeInt(h)
			.writeShort(1)
			.writeShort(24)
			.writeInt(0)
			.writeInt(0)
			.writeInt(2834)
			.writeInt(2834)
			.writeInt(0)
			.writeInt(0)
	}

	local count = 0

	global function writePixels(val)
	{
		for(local tmp = 0x80; tmp != 0; tmp >>= 1)
		{
			if(val & tmp)
				stdout.writeByte(0).writeByte(0).writeByte(0)
			else
				stdout.writeByte(255).writeByte(255).writeByte(255)

			count++

			if(count == width)
			{
				for(i: 0 .. extra)
					stdout.writeByte(0)
	
				count = 0
			}
		}
	}

	global function finish()
		stdout.flush()
}

function main(N)
{
	local width = 100

	if(isString(N))
		try width = toInt(N); catch(e) {}
		
	local timer = time.Timer()
	timer.start()

	local height = width
	local wscale = 2.0 / width
	local hscale = 2.0 / height
	local m = 50
	local limit2 = 4.0

	writeHeader(width, height)

	local bitnum = 0
	local bits = 0

	for(y: 0 .. height)
	{
		local Ci = y * hscale - 1

		for(x: 0 .. width)
// 		for(xb: 0 .. width, 8)
		{
			local Zr = 0.0
			local Zi = 0.0
			local Zrq = 0.0
			local Ziq = 0.0
			local Cr = x * wscale - 1.5

			for(i: 0 .. m)
			{
				if(Zrq + Ziq > limit2)
					break;

				local Zri = Zr * Zi
				Zr = Zrq - Ziq + Cr
				Zi = Zri + Zri + Ci
				Zrq = Zr * Zr
				Ziq = Zi * Zi
			}

			bits = (bits << 1) | ((Zrq + Ziq > limit2) ? 0 : 1)
			bitnum++

			if(bitnum == 8)
			{
				writePixels(bits)
				bitnum = 0
				bits = 0
			}
			else if(x == width - 1)
			{
				bits <<= (8 - width % 8)
				writePixels(bits)
				bitnum = 0
				bits = 0
			}

// 			local bits = 0
// 			local xbb = xb + 7
//
// 			for(x: xb .. (xbb < width) ? xbb + 1 : width)
// 			{
// 				bits <<= 1
//
// 				local Zr = 0.0
// 				local Zi = 0.0
// 				local Zrq = 0.0
// 				local Ziq = 0.0
// 				local Cr = x * wscale - 1.5
//
// 				for(i: 0 .. m)
// 				{
// 					local Zri = Zr * Zi
// 					Zr = Zrq - Ziq + Cr
// 					Zi = Zri + Zri + Ci
// 					Zrq = Zr * Zr
// 					Ziq = Zi * Zi
// 
// 					if(Zrq + Ziq > limit2)
// 					{
// 						bits |= 1
// 						break
// 					}
// 				}
// 			}
// 
// 			if(xbb >= width)
// 				for(x: width .. xbb + 1)
// 					bits = (bits << 1) | 1
// 
// 			stdout.writeByte(255 - bits)
		}
	}

	finish()

	timer.stop()
	io.stderr.writefln("Took {} sec", timer.seconds())
}