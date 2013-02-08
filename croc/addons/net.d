/******************************************************************************
A binding to some of Tango's network functionality.

License:
Copyright (c) 2009 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

	1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

	2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

	3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module croc.addons.net;

version(CrocAllAddons)
	version = CrocNetAddon;

version(CrocNetAddon)
{

import tango.io.model.IConduit;
import tango.net.InternetAddress;
import tango.net.device.Socket;

import croc.api;
import croc.ex_library;

// =====================================================================================================================
// Public
// =====================================================================================================================

public:

void initNetLib(CrocThread* t)
{
	makeModule(t, "net", function uword(CrocThread* t)
	{
		importModuleNoNS(t, "stream");

		CreateClass(t, "NetException", "exceptions.IOException", (CreateClass*){});
		newGlobal(t, "NetException");

		registerGlobals(t, _funcs);

		SocketObj.init(t);
		ServerSocketObj.init(t);

		return 0;
	});
}

// =====================================================================================================================
// Private
// =====================================================================================================================

private:

const RegisterFunc[] _funcs =
[
	{ "connect", &_connect, maxParams: 2 },
	{ "listen",  &_listen,  maxParams: 4 }
];

InternetAddress _getAddr(CrocThread* t, word slot)
{
	checkAnyParam(t, slot);
	auto port = checkIntParam(t, slot + 1);

	if(port < 0 || port > ushort.max)
		throwStdException(t, "RangeException", "Invalid port number: {}", port);

	if(isString(t, slot))
		return safeCode(t, "ValueException", new InternetAddress(getString(t, slot), cast(ushort)port));
	else if(isInt(t, slot))
	{
		auto ip = getInt(t, slot);

		if(ip < 0 || ip > uint.max)
			throwStdException(t, "RangeException", "Invalid IP address: {}", ip);

		return safeCode(t, "ValueException", new InternetAddress(cast(uint)ip, cast(ushort)port));
	}
	else
		paramTypeError(t, slot, "int|string");

	assert(false);
}

uword _connect(CrocThread* t)
{
	auto addr = _getAddr(t, 1);
	auto socket = safeCode(t, "NetException", new Socket());
	safeCode(t, "NetException", socket.connect(addr));

	pushGlobal(t, "Socket");
	pushNull(t);
	pushNativeObj(t, socket);
	return rawCall(t, -3, 1);
}

uword _listen(CrocThread* t)
{
	auto addr = _getAddr(t, 1);
	auto backlog = optIntParam(t, 3, 32);
	auto reuse = optBoolParam(t, 4, false);

	if(backlog < 1)
		throwStdException(t, "RangeException", "Invalid backlog: {}", backlog);

	auto socket = safeCode(t, "NetException", new ServerSocket(addr, cast(int)backlog, reuse));

	pushGlobal(t, "ServerSocket");
	pushNull(t);
	pushNativeObj(t, socket);
	return rawCall(t, -3, 1);

}

// =====================================================================================================================
// class Socket

struct SocketObj
{
static:
	const Socket =  "Socket__socket";
	const Closed =  "Socket__closed";

	void init(CrocThread* t)
	{
		CreateClass(t, "Socket", "stream.Stream", (CreateClass* c)
		{
			pushNull(t);        c.field("__socket");
			pushBool(t, false); c.field("__closed");

			c.method("constructor",  1, &_constructor);
			c.method("finalizer",    0, &_finalizer);
			c.method("read",         3, &_read);
			c.method("write",        3, &_write);
			c.method("readable",     0, &_readable);
			c.method("writable",     0, &_writable);
			c.method("close",        0, &_close);
			c.method("isOpen",       0, &_isOpen);
			c.method("localAddress", 0, &_localAddress);
		});

		newGlobal(t, "Socket");
	}

	void checkOpen(CrocThread* t)
	{
		field(t, 0, Closed);

		if(getBool(t, -1))
			throwStdException(t, "StateException", "Attempting to perform operation on a closed socket");

		pop(t);
	}

	.Socket getThis(CrocThread* t)
	{
		field(t, 0, Socket);
		auto ret = cast(.Socket)getNativeObj(t, -1); assert(ret !is null);
		pop(t);
		return ret;
	}

	.Socket getOpenThis(CrocThread* t)
	{
		checkOpen(t);
		return getThis(t);
	}

	uword _constructor(CrocThread* t)
	{
		field(t, 0, Socket);

		if(!isNull(t, -1))
			throwStdException(t, "StateException", "Attempting to call constructor on an already-initialized Socket");

		pop(t);

		checkParam(t, 1, CrocValue.Type.NativeObj);
		auto socket = cast(.Socket)getNativeObj(t, 1);

		if(socket is null)
			throwStdException(t, "ValueException", "instances of Socket may only be created using instances of the Tango Socket class");

		dup(t, 1);
		fielda(t, 0, Socket);

		pushNull(t);
		pushNull(t);
		return superCall(t, -2, "constructor", 0);
	}

	uword _finalizer(CrocThread* t)
	{
		dup(t, 0);
		pushNull(t);
		return methodCall(t, -2, "close", 0);
	}

	uword _read(CrocThread* t)
	{
		auto socket = getOpenThis(t);
		checkParam(t, 1, CrocValue.Type.Memblock);
		auto _len = len(t, 1);
		auto _offset = optIntParam(t, 2, 0);
		auto _size = optIntParam(t, 3, _len - _offset);

		if(_offset < 0 || _offset > _len)
			throwStdException(t, "BoundsException", "Invalid offset {} in memblock of size {}", _offset, _len);

		if(_size < 0 || _size > _len - _offset)
			throwStdException(t, "BoundsException", "Invalid size {} in memblock of size {} starting from offset {}", _size, _len, _offset);

		auto offset = cast(uword)_offset;
		auto size = cast(uword)_size;
		auto dest = cast(void*)(getMemblockData(t, 1).ptr + offset);
		auto initial = size;

		while(size > 0)
		{
			auto numRead = safeCode(t, "NetException", socket.read(dest[0 .. size]));

			if(numRead == IOStream.Eof)
				break;
			else if(numRead < size)
			{
				size -= numRead;
				break;
			}

			size -= numRead;
			dest += numRead;
		}

		pushInt(t, initial - size);
		return 1;
	}

	uword _write(CrocThread* t)
	{
		auto socket = getOpenThis(t);
		checkParam(t, 1, CrocValue.Type.Memblock);
		auto _len = len(t, 1);
		auto _offset = optIntParam(t, 2, 0);
		auto _size = optIntParam(t, 3, _len - _offset);

		if(_offset < 0 || _offset > _len)
			throwStdException(t, "BoundsException", "Invalid offset {} in memblock of size {}", _offset, _len);

		if(_size < 0 || _size > _len - _offset)
			throwStdException(t, "BoundsException", "Invalid size {} in memblock of size {} starting from offset {}", _size, _len, _offset);

		auto offset = cast(uword)_offset;
		auto size = cast(uword)_size;
		auto src = cast(void*)(getMemblockData(t, 1).ptr + offset);
		auto initial = size;

		while(size > 0)
		{
			auto numWritten = safeCode(t, "exceptions.IOException", socket.write(src[0 .. size]));

			if(numWritten == IOStream.Eof)
			{
				lookup(t, "stream.EOFException");
				pushNull(t);
				pushString(t, "End-of-flow encountered while writing");
				rawCall(t, -3, 1);
				throwException(t);
			}

			size -= numWritten;
			src += numWritten;
		}

		pushInt(t, initial);
		return 1;
	}

	uword _readable(CrocThread* t)
	{
		pushBool(t, true);
		return 1;
	}

	uword _writable(CrocThread* t)
	{
		pushBool(t, true);
		return 1;
	}

	uword _close(CrocThread* t)
	{
		auto socket = getThis(t);

		field(t, 0, Closed);

		if(!getBool(t, -1))
		{
			// Set closed to true first, in case either shutdown or close fails, so that the finalizer won't try to
			// close it again.
			pushBool(t, true);
			fielda(t, 0, Closed);
			safeCode(t, "NetException", socket.shutdown());
			safeCode(t, "NetException", socket.close());
		}

		return 0;
	}

	uword _isOpen(CrocThread* t)
	{
		field(t, 0, Closed);
		pushBool(t, !getBool(t, -1));
		return 1;
	}

	uword _localAddress(CrocThread* t)
	{
		auto socket = getOpenThis(t);
		auto addr = cast(IPv4Address)safeCode(t, "NetException", socket.socket.localAddress());
		assert(addr !is null);
		pushString(t, safeCode(t, "NetException", addr.toAddrString()));
		pushInt(t, safeCode(t, "NetException", addr.port()));
		return 2;
	}
}

// =====================================================================================================================
// class ServerSocket

struct ServerSocketObj
{
static:
	const Socket = "ServerSocket__socket";
	const Closed = "ServerSocket__closed";
	const Linger = "ServerSocket__linger";

	void init(CrocThread* t)
	{
		CreateClass(t, "ServerSocket", (CreateClass* c)
		{
			pushNull(t);        c.field("__socket");
			pushBool(t, false); c.field("__closed");
			pushInt(t, -1);     c.field("__linger");

			c.method("constructor",  1, &_constructor);
			c.method("finalizer",    0, &_finalizer);
			c.method("close",        0, &_close);
			c.method("isOpen",       0, &_isOpen);
			c.method("setLinger",    1, &_setLinger);
			c.method("accept",       0, &_accept);
		});

		newGlobal(t, "ServerSocket");
	}

	void checkOpen(CrocThread* t)
	{
		field(t, 0, Closed);

		if(getBool(t, -1))
			throwStdException(t, "StateException", "Attempting to perform operation on a closed socket");

		pop(t);
	}

	ServerSocket getThis(CrocThread* t)
	{
		field(t, 0, Socket);
		auto ret = cast(ServerSocket)getNativeObj(t, -1); assert(ret !is null);
		pop(t);
		return ret;
	}

	ServerSocket getOpenThis(CrocThread* t)
	{
		checkOpen(t);
		return getThis(t);
	}

	uword _constructor(CrocThread* t)
	{
		field(t, 0, Socket);

		if(!isNull(t, -1))
			throwStdException(t, "StateException", "Attempting to call constructor on an already-initialized Socket");

		pop(t);

		checkParam(t, 1, CrocValue.Type.NativeObj);
		auto socket = cast(.Socket)getNativeObj(t, 1);

		if(socket is null)
			throwStdException(t, "ValueException", "instances of Socket may only be created using instances of the Tango Socket class");

		dup(t, 1);
		fielda(t, 0, Socket);

		return 0;
	}

	uword _finalizer(CrocThread* t)
	{
		dup(t, 0);
		pushNull(t);
		return methodCall(t, -2, "close", 0);
	}

	uword _close(CrocThread* t)
	{
		auto socket = getThis(t);

		field(t, 0, Closed);

		if(!getBool(t, -1))
		{
			// Set closed to true first, in case either shutdown or close fails, so that the finalizer won't try to
			// close it again.
			pushBool(t, true);
			fielda(t, 0, Closed);
			safeCode(t, "NetException", socket.shutdown());
			safeCode(t, "NetException", socket.close());
		}

		return 0;
	}

	uword _isOpen(CrocThread* t)
	{
		field(t, 0, Closed);
		pushBool(t, !getBool(t, -1));
		return 1;
	}

	uword _setLinger(CrocThread* t)
	{
		checkOpen(t);
		checkIntParam(t, 1);
		dup(t, 1);
		fielda(t, 0, Linger);
		return 0;
	}

	uword _accept(CrocThread* t)
	{
		auto socket = getOpenThis(t);
		auto newSock = safeCode(t, "NetException", socket.accept());

		field(t, 0, Linger);
		auto linger = getInt(t, -1);

		if(linger)
			newSock.socket.linger(cast(int)linger);

		pushGlobal(t, "Socket");
		pushNull(t);
		pushNativeObj(t, newSock);
		return rawCall(t, -3, 1);
	}
}

}