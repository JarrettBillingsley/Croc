module tests.common

function xpass(s: string|function)
{
	try
	{
		if(isString(s))
			loadString(s)
		else
			s()
	}
	catch(e)
		throw "Expected to pass but failed"
}

function xfail(s: string|function)
{
	try
	{
		if(isString(s))
			loadString(s)
		else
			s()
	}
	catch(e)
		return

	throw "Expected to fail but passed"
}

function xfailex(s: string)
{
	try
		loadString(s)()
	catch(e)
		return

	throw "Expected to fail but passed"
}