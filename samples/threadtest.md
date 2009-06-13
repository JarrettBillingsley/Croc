module threadtest

function Set(vararg) = {[vararg[i]] = vararg[i] for i in 0 .. #vararg}

// A class which encapsulates a thread's body, a message queue, and timed wait
// functionality.
class Thread
{
	mBody
	mWaitTime
	mNeedMessage = false
	mMessageHead
	mMessageTail

	// Construct a thread with a coroutine body.
	this(body: thread)
		:mBody = body

	// Begin a timed wait.  Duration is in seconds (int or float).  This may
	// not work right for long durations.
	function beginWait(duration: int|float)
		:mWaitTime = time.microTime() + toInt(duration * 1000000)

	// Add a message to this thread's message queue.
	function send(value)
	{
		local n = { value = value }

		if(:mMessageTail is null)
			:mMessageHead = n
		else
			:mMessageTail.next = n

		:mMessageTail = n
	}

	// Try to pop a message off this thread's message queue.  Returns 'false' if there
	// was no available message, in which case it sets its status to "waiting for message".
	// Returns (true, message) if there was a message.
	function receive()
	{
		if(:mMessageHead is null)
		{
			:mNeedMessage = true
			return false
		}

		local item = :mMessageHead
		:mMessageHead = :mMessageHead.next

		if(:mMessageHead is null)
			:mMessageTail = null

		return true, item.value
	}

	// Resume the thread's body.  This should only be called when isWaiting() returns
	// false.  This will give the thread any message that it's waiting for, and if none
	// is waiting, will give it the varargs to this function instead.
	function resume(vararg)
		if(:mNeedMessage)
		{
			assert(:mMessageHead !is null)
			:mNeedMessage = false
			local ok, value = :receive()
			assert(ok)
			return (:mBody)(value)
		}
		else
			return (:mBody)(vararg)

	// Returns a bool, whether this thread is waiting, either on a message or on a timer.
	function isWaiting()
		if(:mNeedMessage)
			return :mMessageHead is null
		else if(:mWaitTime is null)
			return false
		else
			return time.microTime() < :mWaitTime

	// Returns whether the thread has completed or not.
	function isDead() = :mBody.isDead()
}

// Pass this function a set of Threads (i.e. a table where the keys == values).
// This function only returns when all the threads have exited.
function scheduler(threads)
{
	// Very clever function.  It handles "system calls", which are yielded values
	// from coroutines.  It then can resume the threads and tailcall itself, making
	// itself into a sort of loop that will only break when the thread dies or enters
	// a waiting state.
	function handleCall(thread, type, vararg)
	{
		if(thread.isDead())
			return true

		switch(type)
		{
			case "Yield":
				return false

			case "Wait":
				thread.beginWait(vararg)
				return false

			case "Send":
				local dest, value = vararg
				assert(dest in threads)
				dest.send(value)
				return handleCall(thread, thread.resume())

			case "Receive":
				local ok, value = thread.receive()

				if(!ok)
					return false

				return handleCall(thread, thread.resume(value))

			default:
				throw "Unknown call"
		}
	}

	while(#threads > 0)
	{
		foreach(thread; threads, "modify")
		{
			if(thread.isWaiting())
				continue

			if(handleCall(thread, thread.resume()))
				threads[thread] = null
		}
	}
}

// Wait for 'duration' seconds.  Can be float or int.
function wait(duration)
	yield("Wait", duration)

// Send the message 'value' to Thread 'dest'.
function send(dest, value)
	yield("Send", dest, value)

// Receive a message from any thread.
function receive() = yield("Receive")

// Example producer-consumer code with message-passing for synchronization.
function main()
{
	local N = 100

	local producer, consumer

	producer = Thread$ coroutine \
	{
		local i = 0

		while(true)
		{
			wait(0.3 + math.rand(0, 100) / 100.0)

			local item = { type = "Item", value = i }
			i++
			local msg = receive()
			assert(msg.type == "Empty")
			writefln("Producer produced {}.", item.value)
			send(consumer, item)
		}
	}

	consumer = Thread$ coroutine \
	{
		local empty = { type = "Empty" }

		for(i: 0 .. N)
			send(producer, empty)

		while(true)
		{
			local msg = receive()
			wait(0.3 + math.rand(0, 100) / 100.0)
			assert(msg.type == "Item")
			send(producer, empty)
			writefln("Consumer consumed {}.", msg.value)
		}
	}

	scheduler(Set$ producer, consumer)
	writeln("Finished.")
}