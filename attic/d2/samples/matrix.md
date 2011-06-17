module matrix

local SIZE = 30

function mkmatrix(rows, cols)
{
	local count = 1
	local m = array.new(rows)

	for(i: 0 .. rows)
	{
		m[i] = array.new(cols)

		for(j: 0 .. cols)
		{
			++count
			m[i][j] = count
		}
	}

	return m
}

function mmult(rows, cols, m1, m2, m3)
{
	for(i: 0 .. rows)
	{
		for(j: 0 .. cols)
		{
			local val = 0

			for(k: 0 .. cols)
				val += m1[i][k] * m2[k][j]

			m3[i][j] = val
		}
	}

	return m3
}

function main(N)
{
	local n = 1

	if(isString(N))
		n = toInt(N)

	local m1 = mkmatrix(SIZE, SIZE)
	local m2 = mkmatrix(SIZE, SIZE)
	local mm = mkmatrix(SIZE, SIZE)

	for(i: 0 .. n)
		mmult(SIZE, SIZE, m1, m2, mm)

	writeln(mm[0][0], " ", mm[2][3], " ", mm[3][2], " ", mm[4][4])
}