" Vim syntax file
" Language:	Croc
" Maintainer: Jarrett Billingsley
" Last Change:	2011-06-18

if !exists("main_syntax")
  if version < 600
    syntax clear
  elseif exists("b:current_syntax")
    finish
  endif
  let main_syntax = 'croc'
endif

syn case match

" Keywords
syn keyword crocExternal     import module
syn keyword crocConditional  if else switch case default
syn keyword crocBranch       break continue
syn keyword crocRepeat       while for do foreach
syn keyword crocBoolean      true false
syn keyword crocConstant     null
syn keyword crocStructure    class coroutine namespace function
syn keyword crocExceptions   throw try catch finally scope
syn keyword crocStatement    return yield assert
syn keyword crocReserved     in vararg this super with is as
syn keyword crocStorageClass local global
if exists("croc_hl_operator_overload")
	syn keyword crocOpOverload opApply opCall opCat opCat_r opCatAssign opCmp
	syn keyword crocOpOverload opEquals opField opFieldAssign opIn opIndex opIndexAssign
	syn keyword crocOpOverload opLength opLengthAssign opMethod opSlice opSliceAssign
endif

" Comments
syn keyword crocTodo          contained TODO FIXME TEMP XXX
syn match   crocCommentStar   contained "^\s*\*[^/]"me=e-1
syn match   crocCommentStar   contained "^\s*\*$"
syn match   crocCommentPlus   contained "^\s*+[^/]"me=e-1
syn match   crocCommentPlus   contained "^\s*+$"
syn region  crocBlockComment  start="/\*"  end="\*/" contains=crocBlockCommentString,crocTodo,@Spell
syn region  crocNestedComment start="/+"  end="+/" contains=crocNestedComment,crocNestedCommentString,crocTodo,@Spell
syn match   crocLineComment   "//.*" contains=crocLineCommentString,crocTodo,@Spell

hi link crocLineCommentString crocBlockCommentString
hi link crocBlockCommentString crocString
hi link crocNestedCommentString crocString
hi link crocCommentStar  crocBlockComment
hi link crocCommentPlus  crocNestedComment

syn sync minlines=25

" Characters
syn match crocSpecialCharError contained "[^']"

" Escape sequences
syn match crocEscSequence "\\\([\"\\'abfnrtv]\|x\x\x\|u\x\{4}\|U\x\{8}\|\d\{1,3}\)"
syn match crocCharacter   "'[^']*'" contains=crocEscSequence,crocSpecialCharError
syn match crocCharacter   "'\\''" contains=crocEscSequence
syn match crocCharacter   "'[^\\]'"

" Strings
syn region crocString start=+"+ end=+"+ contains=crocEscSequence,@Spell
syn region crocRawString start=+`+ end=+`+ contains=@Spell
syn region crocRawString start=+@"+ skip=+""+ end=+"+ contains=@Spell

" Numbers
syn case ignore
syn match crocInt        display "\<\d[0-9_]*\>"
" Hex number
syn match crocHex        display "\<0x[0-9a-f_]\+\>"
" Octal number
syn match crocOctal      display "\<0c[0-7_]\+\>"
"floating point number, with dot, optional exponent
syn match crocFloat      display "\<\d[0-9_]*\.[0-9_]*\(e[-+]\=[0-9_]\+\)\="
"floating point number, starting with a dot, optional exponent
syn match crocFloat      display "\(\.[0-9_]\+\)\(e[-+]\=[0-9_]\+\)\=\>"
"floating point number, without dot, with exponent
syn match crocFloat      display "\<\d[0-9_]*e[-+]\=[0-9_]\+\>"
" binary number
syn match crocBinary     display "\<0b[01_]\+\>"
syn case match

" The default highlighting.
hi def link crocBinary				Number
hi def link crocInt				Number
hi def link crocHex				Number
hi def link crocOctal				Number
hi def link crocFloat				Float
hi def link crocBranch				Conditional
hi def link crocConditional		Conditional
hi def link crocRepeat				Repeat
hi def link crocExceptions			Exception
hi def link crocStatement			Statement
hi def link crocStorageClass		StorageClass
hi def link crocBoolean			Boolean
hi def link crocRawString			String
hi def link crocString				String
hi def link crocCharacter			Character
hi def link crocEscSequence		SpecialChar
hi def link crocSpecialCharError	Error
hi def link crocOpOverload			Operator
hi def link crocConstant			Constant
hi def link crocStructure			Structure
hi def link crocTodo				Todo
hi def link crocLineComment		Comment
hi def link crocBlockComment		Comment
hi def link crocNestedComment		Comment
hi def link crocExternal			Include

let b:current_syntax = "croc"

" vim: ts=4
