

/*class Container
{
	method insert(data) { }
	method remove() { }
	method hasData() { return false; }
}

class PQ : Container
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

class Stack : Container
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

class Queue : Container
{
	mHead = null;
	mTail = null;

	method insert(data)
	{
		local t = { data = data };

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

local pq = PQ();

for(local i = 0; i < 5; ++i)
	pq:insert(math.rand(0, 20));

writefln("Priority queue (heap)");

while(pq:hasData())
	writefln(pq:remove());
	
writefln();

local s = Stack();

for(local i = 0; i < 5; ++i)
	s:insert(i + 1);
	
writefln("Stack");

while(s:hasData())
	writefln(s:remove());

writefln();

local q = Queue();

for(local i = 0; i < 5; ++i)
	q:insert(i + 1);
	
writefln("Queue");

while(q:hasData())
	writefln(q:remove());

writefln();*/

/*class Test
{
	mData = [4, 5, 6];

	method opApply(extra)
	{
		function iterator(this, index)
		{
			++index;
			
			if(index >= #this.mData)
				return;

			return index, this.mData[index];
		}
		
		function iterator_reverse(this, index)
		{
			--index;
			
			if(index < 0)
				return;
				
			return index, this.mData[index];
		}

		if(isString(extra) && extra == "reverse")
			return iterator_reverse, this, #this.mData;
		else
			return iterator, this, -1;
	}
}

local t = Test();

foreach(local k, local v; t)
	writefln("t[", k, "] = ", v);

writefln();

foreach(local k, local v; t, "reverse")
	writefln("t[", k, "] = ", v);
	
t =
{
	fork = 5,
	knife = 10,
	spoon = "hi"
};

writefln();

foreach(local k, local v; t)
	writefln("t[", k, "] = ", v);
	
t = [5, 10, "hi"];

writefln();

foreach(local k, local v; t)
	writefln("t[", k, "] = ", v);

writefln();

foreach(local k, local v; t, "reverse")
	writefln("t[", k, "] = ", v);
	
writefln();

local s = "hello";

foreach(local k, local v; s)
	writefln("s[", k, "] = ", v);
	
writefln();

foreach(local k, local v; s, "reverse")
	writefln("s[", k, "] = ", v);*/

/*local a = array.new(10);

for(local i = 0; i < 10; ++i)
	a[i] = function() { return i; };

for(local i = 0; i < #a; ++i)
	writefln(a[i]());*/

/*writefln();

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

local arr = [3, 5, 7];

arr:sort();

foreach(local i, local v; arr)
	writefln("arr[", i, "] = ", v);

arr ~= ["foo", "far"];

writefln();

foreach(local i, local v; arr)
	writefln("arr[", i, "] = ", v);

writefln();

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

local stringArray = ["hi", "bye", "foo"];

foreach(local i, local v; stringArray)
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
}*/