module regexptest

import regexp : Regexp

function main()
{
	writefln(Regexp(@"^\d+$").test("1232131"))
	writefln(Regexp(@"^\d+$").test("abcee"))
	writefln(Regexp(regexp.cnMobile).test("13903113456"))
	writefln(Regexp(regexp.chinese).test("中文为真"))

	writefln()

	foreach(v; Regexp("ab").split("this is ab test, fa ab to."))
		writefln(v)

	writefln()

	local temail =
	{
		fork = "ideage@gmail.com",
		knife = "abd@12.com",
		spoon = "abd@12.com",
		spatula = "crappy"
	}

	local r = Regexp(regexp.email)

	foreach(k, v; temail)
	{
		writefln("T[", k, "] = ", v)

		if(!r.test(v))
			writefln("Error!")
		else
			writefln("OK!")
	}

	writefln()

	foreach(i, m; Regexp("ab").search("abcabcabab"))
		writefln(i, ": {}[{}]{}", m.pre(), m.match(), m.post())

	writefln();

	local phone = Regexp(regexp.usPhone)

	writefln(phone.test("1-800-456-7890"))
	writefln(phone.test("987-654-3210"))
	writefln(phone.test("12-234-345-4567"))
	writefln(phone.test("555-1234"))

	writefln()

	writefln(Regexp(regexp.hexdigit).test("3289Ab920Df"))
}