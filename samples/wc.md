module wc

function main(vararg)
{
	local w_total = 0
	local l_total = 0
	local c_total = 0
	local dictionary = {}
	
	if(#vararg == 0)
		return

	writeln("   lines   words   bytes  file")

	for(iarg: 0 .. #vararg)
	{
		local arg = vararg[iarg]
	
		local w_cnt = 0
		local l_cnt = 0
		local inword = false
	
		local c_cnt = io.size(arg)
	
		local f = io.readFile(arg)
		local wstart = 0
	
		foreach(j, c; f)
		{
			if(c == '\n')
				++l_cnt
	
			if(c.isDigit())
			{
				//if(inword)
				//	buf ~= c
			}
			else if(c.isAlpha() || c == '\'')
			{
				if(!inword)
				{
					wstart = j
					inword = true
					w_cnt++
				}
				else
					{}//buf ~= c
			}
			else if(inword)
			{
				local word = f[wstart .. j].toLower();
				local val = dictionary[word]
	
				if(val is null)
					dictionary[word] = 1
				else
					dictionary[word] += 1
	
				inword = false
			}
		}
	
		if(inword)
		{
			local word = f[wstart .. j].toLower();
			local val = dictionary[word]
	
			if(val is null)
				dictionary[word] = 1
			else
				dictionary[word] += 1
		}
	
		writefln("{,8}{,8}{,8}  {}\n", l_cnt, w_cnt, c_cnt, arg)
		l_total += l_cnt
		w_total += w_cnt
		c_total += c_cnt
	}
	
	if(#vararg > 1)
		writefln("--------------------------------------\n{,8}{,8}{,8}  total", l_total, w_total, c_total)
	
	writeln("--------------------------------------")
	
	local results = dictionary.keys().apply(function(v) = [v, dictionary[v]]).sort(function(a, b) = b[1] <=> a[1])
	
	foreach(word; results)
		writefln("{,5} {}", word[1], word[0])
}