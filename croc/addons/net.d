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

import tango.net.InternetAddress;
import tango.net.device.Socket;

import croc.api;
import croc.stdlib_stream;

struct NetLib
{
static:
	void init(CrocThread* t)
	{
		makeModule(t, "net", function uword(CrocThread* t)
		{
			importModuleNoNS(t, "stream");

			SocketObj.init(t);

			newFunction(t, &connect, "connect"); newGlobal(t, "connect");
			newFunction(t, &listen,  "listen");  newGlobal(t, "listen");

			return 0;
		});
	}

	InternetAddress getAddr(CrocThread* t, word slot)
	{
		checkAnyParam(t, slot);
		auto port = checkIntParam(t, slot + 1);

		if(port < 0 || port > ushort.max)
			throwStdException(t, "RangeException", "Invalid port number: {}", port);

		if(isString(t, slot))
			return new InternetAddress(getString(t, slot), cast(ushort)port);
		else if(isInt(t, slot))
		{
			auto ip = getInt(t, slot);

			if(ip < 0 || ip > uint.max)
				throwStdException(t, "RangeException", "Invalid IP address: {}", ip);

			return new InternetAddress(cast(uint)ip, cast(ushort)port);
		}
		else
			paramTypeError(t, slot, "int|string");

		assert(false);
	}

	uword connect(CrocThread* t)
	{
		auto addr = getAddr(t, 1);
		auto socket = safeCode(t, new Socket());
		safeCode(t, socket.connect(addr));

		pushGlobal(t, "Socket");
		pushNull(t);
		pushNativeObj(t, socket);
		rawCall(t, -3, 1);

		return 1;
	}

	uword listen(CrocThread* t)
	{
		auto addr = getAddr(t, 1);
		auto backlog = optIntParam(t, 3, 32);

		if(backlog < 1)
			throwStdException(t, "RangeException", "Invalid backlog: {}", backlog);

		auto reuse = optBoolParam(t, 4, false);
		auto socket = safeCode(t, new ServerSocket(addr, cast(int)backlog, reuse));

		pushGlobal(t, "Socket");
		pushNull(t);
		pushNativeObj(t, socket);
		rawCall(t, -3, 1);

		return 1;
	}
}

struct SocketObj
{
static:
	alias InoutStreamObj.Fields Fields;

	struct Members
	{
		InoutStreamObj.Members base;
		Socket socket;
		int linger = -1;
		float timeout;
	}

	void init(CrocThread* t)
	{
		CreateClass(t, "Socket", "stream.InoutStream", (CreateClass* c)
		{
			c.method("constructor",  &constructor);
			c.method("close",        &close);
			c.method("localAddress", &localAddress);
			c.method("setLinger",    &setLinger);
			c.method("setTimeout",   &setTimeout);
			c.method("accept",       &accept);

			// Tango BUG 1690
			c.method("write",        &write_shim);
			c.method("writeln",      &writeln_shim);
			c.method("writef",       &writef_shim);
			c.method("writefln",     &writefln_shim);
		});

		newFunction(t, &allocator, "Socket.allocator");
		setAllocator(t, -2);

		newFunction(t, &finalizer, "Socket.finalizer");
		setFinalizer(t, -2);

		newGlobal(t, "Socket");
	}

	Members* getThis(CrocThread* t)
	{
		return checkInstParam!(Members)(t, 0, "Socket");
	}

	private Members* getOpenThis(CrocThread* t)
	{
		auto ret = checkInstParam!(Members)(t, 0, "Socket");

		if(ret.base.closed)
			throwStdException(t, "ValueException", "Attempting to perform operation on a closed socket");

		return ret;
	}

	uword allocator(CrocThread* t)
	{
		newInstance(t, 0, Fields.max + 1, Members.sizeof);
		*(cast(Members*)getExtraBytes(t, -1).ptr) = Members.init;

		dup(t);
		pushNull(t);
		rotateAll(t, 3);
		methodCall(t, 2, "constructor", 0);
		return 1;
	}

	uword finalizer(CrocThread* t)
	{
		auto memb = cast(Members*)getExtraBytes(t, 0).ptr;

		if(memb.base.closable && !memb.base.closed)
		{
			memb.base.closed = true;
			memb.base.dirty = false;

			safeCode(t, memb.socket.shutdown());
			safeCode(t, memb.socket.close());
		}

		return 0;
	}

	public uword constructor(CrocThread* t)
	{
		auto memb = getThis(t);

		if(memb.socket !is null)
			throwStdException(t, "ValueException", "Attempting to call constructor on an already-initialized Socket");

		checkParam(t, 1, CrocValue.Type.NativeObj);
		auto socket = cast(Socket)getNativeObj(t, 1);

		if(socket is null)
			throwStdException(t, "ValueException", "instances of Socket may only be created using instances of the Tango Socket class");

		memb.timeout = cast(float)socket.timeout / 1000;
		memb.socket = socket;

		pushNull(t);
		pushNull(t);
		pushNativeObj(t, socket);
		pushBool(t, true);
		superCall(t, -4, "constructor", 0);

		return 0;
	}

	public uword close(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		memb.base.closed = true;

		safeCode(t, memb.socket.shutdown());
		safeCode(t, memb.socket.close());

		return 0;
	}

	uword localAddress(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto addr = cast(IPv4Address)safeCode(t, memb.socket.socket.localAddress());

		assert(addr !is null);

		pushString(t, safeCode(t, addr.toAddrString()));
		pushInt(t, safeCode(t, addr.port()));
		return 2;
	}

	uword setLinger(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		memb.linger = cast(int)checkIntParam(t, 1);
		return 0;
	}

	uword setTimeout(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto period = checkNumParam(t, 1);

		if(period <  0)
			throwStdException(t, "RangeException", "Invalid timeout period: {}", period);

		memb.timeout = period;
		memb.socket.timeout = cast(uint)(memb.timeout * 1000);
		return 0;
	}

	uword accept(CrocThread* t)
	{
		auto memb = getOpenThis(t);
		auto ss = cast(ServerSocket)memb.socket;

		if(ss is null)
			throwStdException(t, "ValueException", "Socket is not a server socket");

		auto sock = safeCode(t, ss.accept());

		if(memb.linger)
			sock.socket.linger(memb.linger);

		pushGlobal(t, "Socket");
		pushNull(t);
		pushNativeObj(t, sock);
		rawCall(t, -3, 1);
		return 1;
	}
	
	uword write_shim(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto memb = getOpenThis(t);

		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);

			if(len(t, -1) > 0)
				memb.base.print.write(getString(t, -1));

			pop(t);
		}

		return 0;
	}

	uword writeln_shim(CrocThread* t)
	{
		auto numParams = stackSize(t) - 1;
		auto memb = getOpenThis(t);

		for(uword i = 1; i <= numParams; i++)
		{
			pushToString(t, i);

			if(len(t, -1) > 0)
				memb.base.print.write(getString(t, -1));

			pop(t);
		}

		memb.base.print.newline;
		return 0;
	}

	uword writef_shim(CrocThread* t)
	{
		auto memb = getOpenThis(t);

		pushGlobal(t, "format");
		pushNull(t);
		rotateAll(t, 2);
		rawCall(t, 1, 1);

		if(len(t, 1) > 0)
			memb.base.print.write(getString(t, 1));

		return 0;
	}

	uword writefln_shim(CrocThread* t)
	{
		auto memb = getOpenThis(t);

		pushGlobal(t, "format");
		pushNull(t);
		rotateAll(t, 2);
		rawCall(t, 1, 1);

		if(len(t, 1) > 0)
			memb.base.print.write(getString(t, 1));

		memb.base.print.newline;
		return 0;
	}
}

}