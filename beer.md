module beer

/*
function bottleStr(num) = num == 1 ? "bottle" : "bottles"
function num(num) = num == 0 ? "no more" : num == -1 ? "99" : toString(num)
function action(num) = num == 0 ? "Go to the store and buy some more" : "Take one down and pass it around"
function cap(str) = str[0].toUpper() ~ str[1..]

function sing(i = 99)
{
	writefln("{} {} of beer on the wall, {} {1} of beer.", cap(num(i)), bottleStr(i), num(i))
	writefln("{}, {} {} of beer on the wall.\n", action(i), num(i - 1), bottleStr(i - 1))

	if(i != 0)
		return sing(i - 1)
}

sing()

array.range(9, -1).apply(\v->format("{} {} of beer on the wall, {} {1} of beer.
{}, {} {} of beer on the wall.\n",v==0?"No more":toString(v),v==1?"bottle":"bottles",
v==0?"no more":toString(v),v==0?"Go to the store and buy some more":
"Take one down and pass it around",v==0?"99":v==1?"no more":toString(v-1),v==2?"bottle":
"bottles")).each(\(_,v)->writeln(v))*/

[format("{} {} of beer on the wall, {} {1} of beer.\n{}, {} {} of beer on the wall.\n",
v==0?"No more":toString(v),v==1?"bottle":"bottles",v==0?"no more":toString(v),
v==0?"Go to the store and buy some more":"Take one down and pass it around",
v==0?"99":v==1?"no more":toString(v-1),v==2?"bottle":"bottles") for v in 100 .. 0]
.each(\(_,v)->writeln(v))