module confset

_G.cls = function cls()
	os.system("cls")

_G.unset = function unset(vararg)
	for(i: 0 .. #vararg)
		hash.remove(findGlobal(vararg[i]), vararg[i])