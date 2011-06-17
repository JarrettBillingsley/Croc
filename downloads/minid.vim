" Vim syntax file
" Language:	MiniD
" Maintainer: Jarrett Billingsley
" Last Change:	2008-06-10

if !exists("main_syntax")
  if version < 600
    syntax clear
  elseif exists("b:current_syntax")
    finish
  endif
  let main_syntax = 'minid'
endif

syn case match

" Keywords
syn keyword minidExternal     import module
syn keyword minidConditional  if else switch case default
syn keyword minidBranch       break continue
syn keyword minidRepeat       while for do foreach
syn keyword minidBoolean      true false
syn keyword minidConstant     null
syn keyword minidStructure    class coroutine namespace function
syn keyword minidExceptions   throw try catch finally scope
syn keyword minidStatement    return yield assert
syn keyword minidReserved     in vararg this super with is as
syn keyword minidStorageClass local global
if exists("minid_hl_operator_overload")
	syn keyword minidOpOverload opAdd opAdd_r opAddAssign opAnd opAnd_r opAndAssign
	syn keyword minidOpOverload opApply opCall opCat opCat_r opCatAssign opCmp opCom
	syn keyword minidOpOverload opDec opDiv opDiv_r opDivAssign opEquals opField
	syn keyword minidOpOverload opFieldAssign opIn opInc opIndex opIndexAssign
	syn keyword minidOpOverload opLength opLengthAssign opMethod opMod opMod_r opModAssign
	syn keyword minidOpOverload opMul opMul_r opMulAssign opNeg opOr opOr_r opOrAssign
	syn keyword minidOpOverload opShl opShl_r opShlAssign opShr opShr_r opShrAssign
	syn keyword minidOpOverload opSlice opSliceAssign opSub opSub_r opSubAssign
	syn keyword minidOpOverload opUShr opUShr_r opUShrAssign opXor opXor_r opXorAssign
endif

" Comments
syn keyword minidTodo          contained TODO FIXME TEMP XXX
syn match   minidCommentStar   contained "^\s*\*[^/]"me=e-1
syn match   minidCommentStar   contained "^\s*\*$"
syn match   minidCommentPlus   contained "^\s*+[^/]"me=e-1
syn match   minidCommentPlus   contained "^\s*+$"
syn region  minidBlockComment  start="/\*"  end="\*/" contains=minidBlockCommentString,minidTodo,@Spell
syn region  minidNestedComment start="/+"  end="+/" contains=minidNestedComment,minidNestedCommentString,minidTodo,@Spell
syn match   minidLineComment   "//.*" contains=minidLineCommentString,minidTodo,@Spell

hi link minidLineCommentString minidBlockCommentString
hi link minidBlockCommentString minidString
hi link minidNestedCommentString minidString
hi link minidCommentStar  minidBlockComment
hi link minidCommentPlus  minidNestedComment

syn sync minlines=25

" Characters
syn match minidSpecialCharError contained "[^']"

" Escape sequences
syn match minidEscSequence "\\\([\"\\'abfnrtv]\|x\x\x\|u\x\{4}\|U\x\{8}\|\d\{1,3}\)"
syn match minidCharacter   "'[^']*'" contains=minidEscSequence,minidSpecialCharError
syn match minidCharacter   "'\\''" contains=minidEscSequence
syn match minidCharacter   "'[^\\]'"

" Strings
syn region minidString start=+"+ end=+"+ contains=minidEscSequence,@Spell
syn region minidRawString start=+`+ end=+`+ contains=@Spell
syn region minidRawString start=+@"+ skip=+""+ end=+"+ contains=@Spell

" Numbers
syn case ignore
syn match minidInt        display "\<\d[0-9_]*\>"
" Hex number
syn match minidHex        display "\<0x[0-9a-f_]\+\>"
" Octal number
syn match minidOctal      display "\<0c[0-7_]\+\>"
"floating point number, with dot, optional exponent
syn match minidFloat      display "\<\d[0-9_]*\.[0-9_]*\(e[-+]\=[0-9_]\+\)\="
"floating point number, starting with a dot, optional exponent
syn match minidFloat      display "\(\.[0-9_]\+\)\(e[-+]\=[0-9_]\+\)\=\>"
"floating point number, without dot, with exponent
syn match minidFloat      display "\<\d[0-9_]*e[-+]\=[0-9_]\+\>"
" binary number
syn match minidBinary     display "\<0b[01_]\+\>"
syn case match

" The default highlighting.
hi def link minidBinary				Number
hi def link minidInt				Number
hi def link minidHex				Number
hi def link minidOctal				Number
hi def link minidFloat				Float
hi def link minidBranch				Conditional
hi def link minidConditional		Conditional
hi def link minidRepeat				Repeat
hi def link minidExceptions			Exception
hi def link minidStatement			Statement
hi def link minidStorageClass		StorageClass
hi def link minidBoolean			Boolean
hi def link minidRawString			String
hi def link minidString				String
hi def link minidCharacter			Character
hi def link minidEscSequence		SpecialChar
hi def link minidSpecialCharError	Error
hi def link minidOpOverload			Operator
hi def link minidConstant			Constant
hi def link minidStructure			Structure
hi def link minidTodo				Todo
hi def link minidLineComment		Comment
hi def link minidBlockComment		Comment
hi def link minidNestedComment		Comment
hi def link minidExternal			Include

let b:current_syntax = "minid"

" vim: ts=4
