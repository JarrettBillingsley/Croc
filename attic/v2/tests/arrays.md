module tests.arrays;

local a = array.new(5);
array.new(10, 0);
try array.new(-3); catch(e){}

a = array.range(10);
array.range(3, 8);
array.range(2, 10, 3);
try array.range(1, 10, -2); catch(e){}
array.range(10, 2);

a[..] = 5;
a.sort();
a.reverse();
a.dup();
a.length(6);
try a.length(-3); catch(e){}

foreach(i, v; a){}
foreach(i, v; a, "reverse"){}
a.expand();
a.toString();
(["hi"]).toString();
a.apply(function(x) x);
a.map(function(x) x);
a.reduce(function(x, y) x);
([]).reduce(function(x, y) x);
a.each(function(i, v){ return false; });
array.range(100).filter(function(i, v) { return true; });
a.find(5);
a.find(0);
a = array.range(50);
a.bsearch(3);
a.bsearch(-54);
a.bsearch(24);
a.bsearch(50);
a.pop();
a.pop(0);
a.pop(-1);
try a.pop(-500000); catch(e){}
try ([]).pop(); catch(e){}