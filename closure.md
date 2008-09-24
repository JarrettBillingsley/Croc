module closure

function testMe()
{
    local x = 10

    writefln("testMe: x = {}", x)

    function f()
    {
        x++
        writefln("f: x = {}", x)
    }

    function g()
        writefln("g: x = {}", x)

    f()
    g()

    writefln("testMe: x = {}", x)
    return f
}

function main()
{
    local f = testMe()
    f()
}
