module croctest;

import tango.core.tools.TraceExceptions;
import tango.io.Stdout;

import croc.api;
import croc.compiler;

import croc.addons.pcre;
import croc.addons.sdl;
import croc.addons.gl;
import croc.addons.net;
import croc.addons.devil;

import croc.ex_doccomments;

uword processComment_wrap(CrocThread* t)
{
	auto str = checkStringParam(t, 1);
	checkParam(t, 2, CrocValue.Type.Table);
	processComment(t, str);
	return 1;
}

version(CrocAllAddons)
{
	version = CrocPcreAddon;
	version = CrocSdlAddon;
	version = CrocGlAddon;
	version = CrocNetAddon;
	version = CrocDevilAddon;
}

/*
<globals>
	Object
	Throwable
	Exception, Error (mirrors of exceptions.*)
	Finalizable
	_doc_ (mirror of docs._doc_)
	dumpVal

	weakref
	deref

	allFieldsOf
	fieldsOf
	findField
	hasField
	hasMethod
	rawGetField
	rawSetField

	isSet
	findGlobal

	typeof
	isArray
	isBool
	isChar
	isClass
	isFloat
	isFuncDef
	isFunction
	isInstance
	isInt
	isMemblock
	isNamespace
	isNativeObj
	isNull
	isString
	isTable
	isThread
	isWeakRef

	nameOf

	format
	rawToString
	toBool
	toChar
	toFloat
	toInt
	toString

	(all mirrors of console.*)
	write
	writef
	writefln
	writeln
	readln

array metamethods
	all
	any
	append
	apply
	bsearch
	count
	countIf
	dup
	each
	expand
	extreme
	fill
	filter
	find
	findIf
	flatten
	insert
	map
	max
	min
	opApply
	opEquals
	pop
	reduce
	reverse
	rreduce
	set
	sort
	toString
char metamethods
	toLower
	toUpper
	isAlpha
	isAlNum
	isLower
	isUpper
	isDigit
	isCtrl
	isPunct
	isSpace
	isHexDigit
	isAscii
	isValid
function metamethods
	isNative
	numParams
	maxParams
	isVararg
	isCacheable
memblock metamethods
	append
	apply
	copyRange
	dup
	fill
	fillRange
	insert
	itemSize
	map
	max
	min
	opAdd
	opAdd_r
	opAddAssign
	opApply
	opCat
	opCat_r
	opCatAssign
	opCmp
	opDiv
	opDiv_r
	opDivAssign
	opEquals
	opMod
	opMod_r
	opModAssign
	opMul
	opMul_r
	opMulAssign
	opSliceAssign
	opSub
	opSub_r
	opSubAssign
	pop
	product
	rawCopy
	readByte
	readDouble
	readFloat
	readInt
	readLong
	readShort
	readUByte
	readUInt
	readULong
	readUShort
	remove
	revDiv
	reverse
	revMod
	revSub
	sort
	sum
	toArray
	toString
	type
	writeByte
	writeDouble
	writeFloat
	writeInt
	writeLong
	writeShort
	writeUByte
	writeUInt
	writeULong
	writeUShort
namespace metamethods
	opApply
string metamethods
	compare
	endsWith
	find
	icompare
	iendsWith
	ifind
	irfind
	isAscii
	istartsWith
	join
	lstrip
	opApply
	repeat
	replace
	reverse
	rfind
	rstrip
	split
	splitLines
	startsWith
	strip
	toFloat
	toInt
	toLower
	toRawAscii
	toRawUnicode
	toUpper
	vjoin
	vsplit
	vsplitLines
table metamethods
	opApply
thread metamethods
	isDead
	isInitial
	isRunning
	isSuspended
	isWaiting
	reset
	state


array
	new
	range
compiler
	compileModule
	eval
	loadString
console : stream
	readln
	stderr
	stdin
	stdout
	write
	writef
	writefln
	writeln
docs
	_doc_
	docsOf
	BaseDocOutput
	TracWikiDocOutput
	HtmlDocOutput
	LatexDocOutput?
env
	getEnv
	putEnv
exceptions
	Location
	ApiError
	AssertError
	BoundsException
	CallException
	CompileException
	Error
	Exception
	FieldException
	FinalizerError
	ImportException
	IOException
	LexicalException
	LookupException
	MethodException
	NameException
	NotImplementedException
	OSException
	ParamException
	RangeException
	RuntimeException
	SemanticException
	SwitchError
	SyntaxException
	TypeException
	UnicodeException
	ValueException
	VMError
	stdException
gc
	allocated
	collect
	collectFull
	limit
	postCallback
	removePostCallback
hash : string
	apply
	clear
	dup
	each
	filter
	keys
	map
	pop
	reduce
	remove
	take
	values
	WeakKeyTable
	WeakValTable
	WeakKeyValTable
json : stream
	fromJSON
	toJSON
	writeJSON
math
	abs
	acos
	asin
	atan
	atan2
	cbrt
	ceil
	cos
	e
	exp
	floatMax
	floatMin
	floatSize
	floor
	frand
	gamma
	hypot
	infinity
	intMax
	intMin
	intSize
	isInf
	isNan
	lgamma
	ln
	log10
	log2
	max
	min
	nan
	pi
	pow
	rand
	round
	sign
	sin
	sqrt
	tan
	trunc
memblock
	new
	range
modules
	customLoaders
	initModule
	load
	loaded
	loaders
	path
	reload
	runMain
path
	dirName
	extension
	fileName
	join
	name
serialization : stream
	serializeGraph
	deserializeGraph
stream
	InoutStream
	InStream
	MemInoutStream
	MemInStream
	MemOutStream
	OutStream
string : memblock
	fromRawUnicode
	fromRawAscii
	StringBuffer
thread
	current
	halt
text
	TextCodec
	registerCodec
	getCodec
	hasCodec
	encode
	decode
	incrementalEncoder
	incrementalDecoder
time
	Timer
	compare
	culture
	dateString
	dateTime
	microTime
	sleep
	timestamp
	timex


debug
	callDepth
	currentLine
	getExtraBytes
	getExtraField
	getFunc
	getFuncEnv
	getHook
	getLocal
	getMetatable
	getRegistry
	getUpval
	lineInfo
	localName
	numExtraFields
	numLocals
	numUpvals
	setExtraBytes
	setExtraField
	setFuncEnv
	setHook
	setLocal
	setMetatable
	setUpval
	sourceLine
	sourceName
	upvalName
file
	accessed
	changeDir
	copy
	created
	currentDir
	exists
	inFile
	inoutFile
	isDir
	isFile
	isReadOnly
	lines
	listDirs
	listFiles
	makeDir
	makeDirChain
	modified
	outFile
	parentDir
	readFile
	readMemblock
	remove
	removeDir
	rename
	size
	writeFile
	writeMemblock
os
	system
	Process
*/

void main()
{
	scope(exit) Stdout.flush;

	CrocVM vm;
	CrocThread* t;

	try
	{
		t = openVM(&vm);
		loadUnsafeLibs(t, CrocUnsafeLib.ReallyAll);

		version(CrocPcreAddon) PcreLib.init(t);
		version(CrocSdlAddon) SdlLib.init(t);
		version(CrocGlAddon) GlLib.init(t);
		version(CrocNetAddon) NetLib.init(t);
		version(CrocDevilAddon) DevilLib.init(t);

		newFunction(t, &processComment_wrap, "processComment");
		newGlobal(t, "processComment");

		Compiler.setDefaultFlags(t, Compiler.All | Compiler.DocDecorators);
		runModule(t, "samples.simple");
	}
	catch(CrocException e)
	{
		t = t ? t : mainThread(&vm); // in case, while fucking around, we manage to throw an exception from openVM
		catchException(t);
		Stdout.formatln("{}", e);

		dup(t);
		pushNull(t);
		methodCall(t, -2, "tracebackString", 1);
		Stdout.formatln("{}", getString(t, -1));

		pop(t, 2);

		if(e.info)
		{
			Stdout("\nD Traceback: ").newline;
			e.info.writeOut((char[]s) { Stdout(s); });
		}
	}
	catch(CrocHaltException e)
		Stdout.formatln("Thread halted");
	catch(Exception e)
	{
		Stdout("Bad error:").newline;
		e.writeOut((char[]s) { Stdout(s); });
		return;
	}

	closeVM(&vm);
}
