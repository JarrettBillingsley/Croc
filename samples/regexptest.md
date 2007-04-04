module regexptest;

writefln(regexp.test(@"^\d+$","1232131"));
writefln(regexp.test(@"^\d+$","abcee"));
writefln(regexp.test(regexp.cnMobile,"13903113456"));
writefln(regexp.test(regexp.chinese,"中文为真"));

writefln();

foreach(v; regexp.split("ab","this is ab test, fa ab to."))
	writefln(v);
	
writefln();

local temail =
{
	fork = "ideage@gmail.com",
	knife = "abd@12.com",
	spoon = "abd@12.com",
	spatula = "crappy"
};

local r = regexp.compile(regexp.email);

foreach(k, v; temail)
{
	writefln("T[", k, "] = ", v);
	
	if(!r.test(v))
		writefln("Error!");
	else 
		writefln("OK!" );
}

writefln();

foreach(i, m; regexp.compile("ab").search("abcabcabab"))
	writefln(i, ": %s[%s]%s", m.pre(), m.match(0), m.post());
	
writefln();

writefln(regexp.test(regexp.usPhone, "1-800-456-7890"));
writefln(regexp.test(regexp.usPhone, "987-654-3210"));
writefln(regexp.test(regexp.usPhone, "12-234-345-4567"));
writefln(regexp.test(regexp.usPhone, "555-1234"));

writefln();

writefln(regexp.test(regexp.hexdigit, "3289Ab920Df"));