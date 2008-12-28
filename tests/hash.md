module tests.hash

import hash = hash

// minid.table
local t = {}
local x = 'x' in t
x = #t
foreach(k, v; t) {}
t.x = weakref({})
collectGarbage()

// minid.namespace
foreach(k, v; namespace N {x}){}
hash.remove(namespace N {x}, "x")
hash.clear(namespace N {})

// minid.hashlib
