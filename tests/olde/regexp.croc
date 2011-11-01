module tests.rex;

regexp.test("ab", "abc");
regexp.test("ab", "abc", "g");
regexp.replace("ab", "abc", "d");
regexp.replace("ab", "abc", "d", "g");
regexp.replace("ab", "abc", function(x) x.match(0));
regexp.split("ab", "abc");
regexp.split("ab", "abc", "g");
regexp.match("ab", "abc");
regexp.match("ab", "abc", "g");
regexp.compile("ab", "g");
local re = regexp.compile("ab", "g");
re.test("abc");
re.match("abc");
re.replace("abc", "d");
re.split("abc");
re.find("abc");

foreach(m; re.search("ababab"))
{
	m.pre();
	m.post();
}