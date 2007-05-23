module tests.tab;

local t = {x = 1};
t.dup();
t.keys();
t.values();
foreach(v; t){}
t.each(function(){});
table.dup(t);
table.keys(t);
table.values(t);
table.each(t, function(){});
table.set(t, 0, 1);
table.get(t, 0);
foreach(v; table.apply(t)){}