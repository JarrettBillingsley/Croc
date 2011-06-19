module regexptest

import regexp : Regexp

function main()
{
	writeln(Regexp(@"^\d+$").test("1232131"))
	writeln(Regexp(@"^\d+$").test("abcee"))
	writeln(Regexp(regexp.cnMobile).test("13903113456"))
	writeln(Regexp(regexp.chinese).test("中文为真"))

	writeln()

	foreach(v; Regexp("ab").split("this is ab test, fa ab to."))
		writeln(v)

	writeln()

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
		writeln("T[", k, "] = ", v)

		if(!r.test(v))
			writeln("Error!")
		else
			writeln("OK!")
	}

	writeln()

	foreach(i, m; Regexp("ab").search("abcabcabab"))
		writefln(i, ": {}[{}]{}", m.pre(), m.match(), m.post())

	writeln();

	local phone = Regexp(regexp.usPhone)

	writeln(phone.test("1-800-456-7890"))
	writeln(phone.test("987-654-3210"))
	writeln(phone.test("12-234-345-4567"))
	writeln(phone.test("555-1234"))

	writeln()

	writeln(Regexp(regexp.hexdigit).test("3289Ab920Df"))
}