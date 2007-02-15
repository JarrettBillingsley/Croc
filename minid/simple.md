module simple;

// Testing tailcalls.

global function recurse(x)
{
	writefln("recurse: ", x);

	if(x == 0)
		return toString(x);
	else
		return recurse(x - 1);
}

writefln(recurse(5));
writefln();

// A function which lets us define properties for a class.
// The varargs should be a bunch of tables, each with a 'name' field, and 'getter' and/or 'setter' fields.
local function mixinProperties(classType, vararg)
{
	classType.mProps = { };

	classType.opIndex = function(this, key)
	{
		local prop = this.mProps[key];

		if(prop is null)
			throw format(classType, ":opIndex() - Property '%s' does not exist", key);

		local getter = prop.getter;

		if(getter is null)
			throw format(classType, ":opIndex() - Property '%s' has no getter", key);

		return getter(this);
	};

	classType.opIndexAssign = function(this, key, value)
	{
		local prop = this.mProps[key];

		if(prop is null)
			throw format(classType, ":opIndexAssign() - Property '%s' does not exist", key);
			
		local setter = prop.setter;
		
		if(setter is null)
			throw format(classType, ":opIndexAssign() - Property '%s' has no setter", key);
			
		setter(this, value);
	};

	foreach(k, v; [vararg])
	{
		if(!isTable(v))
			throw "mixinProperties() - properties must be tables";
		
		if(v.name is null)
			throw format("mixinProperties() - property ", k, " has no name");

		if(v.setter is null && v.getter is null)
			throw format("mixinProperties() - property '%s' has no getter or setter", v.name);

		classType.mProps[v.name] = v;
	}
}

// Create a class to test out.
local class PropTest
{
	mX = 0;
	mY = 0;
	mName = "";
	
	method constructor(name)
	{
		this.mName = name;
	}
	
	method toString()
	{
		return format("name = '", this.mName, "' x = ", this.mX, " y = ", this.mY);
	}
}

// Mix in the properties.
mixinProperties(
	PropTest,

	{
		name = "x",
		
		method setter(value)
		{
			this.mX = value;
		}
		
		method getter()
		{
			return this.mX;
		}
	},
	
	{
		name = "y",
		
		method setter(value)
		{
			this.mY = value;
		}
		
		method getter()
		{
			return this.mY;
		}
	},

	{
		name = "name",
		
		method getter()
		{
			return this.mName;
		}
	}
);

// Create an instance and try it out.
local p = PropTest("hello");

writefln(p);
p.x = 46;
p.y = 123;
p.x = p.x + p.y;
writefln(p);

// Try to access a nonexistent property.
try
	p.name = "crap";
catch(e)
{
	writefln("caught: ", e);
	writefln(getTraceback());
}

writefln();

// Some container classes.

local class PQ
{
	mData;
	mLength = 0;

	method constructor()
	{
		this.mData = array.new(15);
	}
	
	method insert(data)
	{
		this:resizeArray();
		
		this.mData[this.mLength] = data;
		
		local index = this.mLength;
		local parentIndex = (index - 1) / 2;
		
		while(index > 0 && this.mData[parentIndex] > this.mData[index])
		{
			local temp = this.mData[parentIndex];
			this.mData[parentIndex] = this.mData[index];
			this.mData[index] = temp;

			index = parentIndex;
			parentIndex = (index - 1) / 2;
		}
		
		this.mLength += 1;
	}
	
	method remove()
	{
		if(this.mLength == 0)
			throw "PQ:remove() - No items to remove";

		local data = this.mData[0];
		this.mLength -= 1;
		this.mData[0] = this.mData[this.mLength];
		
		local index = 0;
		local left = 1;
		local right = 2;

		while(index < this.mLength)
		{
			local smaller;
			
			if(left >= this.mLength)
			{
				if(right >= this.mLength)
					break;
				else
					smaller = right;
			}
			else
			{
				if(right >= this.mLength)
					smaller = left;
				else
				{
					if(this.mData[left] < this.mData[right])
						smaller = left;
					else
						smaller = right;
				}
			}

			if(this.mData[index] > this.mData[smaller])
			{
				local temp = this.mData[index];
				this.mData[index] = this.mData[smaller];
				this.mData[smaller] = temp;
				
				index = smaller;
				left = (index * 2) + 1;
				right = left + 1;
			}
			else
				break;
		}
		
		return data;
	}
	
	method resizeArray()
	{
		if(this.mLength >= #this.mData)
			this.mData:length((#this.mData + 1) * 2 - 1);
	}
	
	method hasData()
	{
		return this.mLength != 0;
	}
}

local class Stack
{
	mHead = null;
	
	method insert(data)
	{
		local t = { data = data, next = this.mHead };
		this.mHead = t;
	}
	
	method remove()
	{
		if(this.mHead is null)
			throw "Stack:remove() - No items to pop";
			
		local item = this.mHead;
		this.mHead = this.mHead.next;
		
		return item.data;
	}

	method hasData()
	{
		return this.mHead !is null;
	}
}

local class Queue
{
	mHead = null;
	mTail = null;

	method insert(data)
	{
		local t = { data = data, next = null };

		if(this.mTail is null)
		{
			this.mHead = t;
			this.mTail = t;
		}
		else
		{
			this.mTail.next = t;
			this.mTail = t;
		}
	}
	
	method remove()
	{
		if(this.mTail is null)
			throw "Queue:pop() - No items to pop";
			
		local item = this.mHead;
		this.mHead = this.mHead.next;
		
		if(this.mHead is null)
			this.mTail = null;
			
		return item.data;
	}
	
	method hasData()
	{
		return this.mHead !is null;
	}
}

local prioQ = PQ();

for(local i = 0; i < 5; ++i)
	prioQ:insert(math.rand(0, 20));

writefln("Priority queue (heap)");

while(prioQ:hasData())
	writefln(prioQ:remove());
	
writefln();

local stack = Stack();

for(local i = 0; i < 5; ++i)
	stack:insert(i + 1);
	
writefln("Stack");

while(stack:hasData())
	writefln(stack:remove());

writefln();

local queue = Queue();

for(local i = 0; i < 5; ++i)
	queue:insert(i + 1);
	
writefln("Queue");

while(queue:hasData())
	writefln(queue:remove());

writefln();

// opApply tests.

local class Test
{
	mData = [4, 5, 6];

	method opApply(extra)
	{
		if(isString(extra) && extra == "reverse")
		{
			local function iterator_reverse(this, index)
			{
				--index;
				
				if(index < 0)
					return;
					
				return index, this.mData[index];
			}

			return iterator_reverse, this, #this.mData;
		}
		else
		{
			local function iterator(this, index)
			{
				++index;
	
				if(index >= #this.mData)
					return;
	
				return index, this.mData[index];
			}

			return iterator, this, -1;
		}
	}
}

local test = Test();

foreach(k, v; test)
	writefln("test[", k, "] = ", v);

writefln();

foreach(k, v; test, "reverse")
	writefln("test[", k, "] = ", v);
	
writefln();

test =
{
	fork = 5,
	knife = 10,
	spoon = "hi"
};

foreach(k, v; test)
	writefln("test[", k, "] = ", v);
	
test = [5, 10, "hi"];

writefln();

foreach(k, v; test)
	writefln("test[", k, "] = ", v);

writefln();

foreach(k, v; test, "reverse")
	writefln("test[", k, "] = ", v);

writefln();

foreach(k, v; "hello")
	writefln("str[", k, "] = ", v);

writefln();

foreach(k, v; "hello", "reverse")
	writefln("str[", k, "] = ", v);

writefln();

// Testing upvalues in for loops.

local arr = array.new(10);

for(local i = 0; i < 10; ++i)
	arr[i] = function() { return i; };

for(local i = 0; i < #arr; ++i)
	writefln(arr[i]());

writefln();

// Testing nested functions.

local function outer()
{
	local x = 3;

	local function inner()
	{
		++x;
		writefln("inner x: ", x);
	}

	writefln("outer x: ", x);
	inner();
	writefln("outer x: ", x);

	return inner;
}

local func = outer();
func();

writefln();

// Testing Exceptions.

local function thrower(x)
{
	if(x >= 3)
		throw "Sorry, x is too big for me!";
}

local function tryCatch(iterations)
{
	try
	{
		for(local i = 0; i < iterations; ++i)
		{
			writefln("tryCatch: ", i);
			thrower(i);
		}
	}
	catch(e)
	{
		writefln("tryCatch caught: ", e);
		throw e;
	}
	finally
	{
		writefln("tryCatch finally");
	}
}

try
{
	tryCatch(2);
	tryCatch(5);
}
catch(e)
{
	writefln("caught: ", e);
}

writefln();

// Testing arrays.

local array = [3, 5, 7];

array:sort();

foreach(i, v; array)
	writefln("arr[", i, "] = ", v);

array ~= ["foo", "far"];

writefln();

foreach(i, v; array)
	writefln("arr[", i, "] = ", v);

writefln();

// Testing vararg functions.

local function vargs(vararg)
{
	local args = [vararg];

	writefln("num varargs: ", #args);

	for(local i = 0; i < #args; ++i)
		writefln("args[", i, "] = ", args[i]);
}

vargs();

writefln();

vargs(2, 3, 5, "foo", "bar");

writefln();

// Testing switches.

for(local switchVar = 0; switchVar < 11; ++switchVar)
{
	switch(switchVar)
	{
		case 1, 2, 3:
			writefln("small");
			break;

		case 4, 5, 6:
			writefln("medium");
			break;
			
		case 7, 8, 9:
			writefln("large");
			break;
			
		default:
			writefln("out of range");
			break;
	}
}

writefln();

foreach(i, v; ["hi", "bye", "foo"])
{
	switch(v)
	{
		case "hi":
			writefln("switched to hi");
			break;
			
		case "bye":
			writefln("switched to bye");
			break;
			
		default:
			writefln("switched to something else");
			break;
	}
}