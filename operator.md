module operator

function add(x, y) = x + y
function sub(x, y) = x - y
function cat(x, y) = x ~ y

function mul(x, y) = x * y
function div(x, y) = x / y
function mod(x, y) = x % y

function and(x, y) = x & y
function or(x, y) = x | y
function xor(x, y) = x ^ y

function shl(x, y) = x << y
function shr(x, y) = x >> y
function ushr(x, y) = x >>> y

function addeq(x, y) { x += y; return x }
function subeq(x, y) { x -= y; return x }
function cateq(x, y) { x ~= y; return x }

function muleq(x, y) { x *= y; return x }
function diveq(x, y) { x /= y; return x }
function modeq(x, y) { x %= y; return x }

function andeq(x, y) { x &= y; return x }
function oreq(x, y) { x |= y; return x }
function xoreq(x, y) { x ^= y; return x }

function shleq(x, y) { x <<= y; return x }
function shreq(x, y) { x >>= y; return x }
function ushleq(x, y) { x >>>= y; return x }

function condeq(x, y) { x ?= y; return x }

function eq(x, y) = x == y
function ne(x, y) = x != y
function is_(x, y) = x is y
function notis(x, y) = x !is y

function as_(x, y) = x as y
function in_(x, y) = x in y
function notin(x, y) = x !in y
function lt(x, y) = x < y
function le(x, y) = x <= y
function gt(x, y) = x > y
function ge(x, y) = x >= y
function cmp(x, y) = x <=> y

function neg(x) = -x
function not(x) = !x
function com(x) = ~x
function len(x) = #x

function idx(x, y) = x[y]
function idxa(x, y, z) x[y] = z
function slice(x, y, z) = x[y .. z]
function slicea(x, y, z, w) x[y .. z] = w

function field(x, y) = x.(y)
function fielda(x, y, z) x.(y) = z

function superof(x) = x.super
function classof(x) = x.class

function fieldGetter(name) = function(x) = x.(name)
function fieldSetter(name) = function(x, value) x.(name) = value
function indexer(idx) = function(x) = x[idx]
function indexAssigner(idx) = function(x, value) x[idx] = value