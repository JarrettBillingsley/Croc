#ifndef CROC_COMPILER_LEXER_HPP
#define CROC_COMPILER_LEXER_HPP

#include "croc/compiler/types.hpp"
#include "croc/util/utf.hpp"

#define KEYWORD_LIST(X)\
	X(AndKeyword,    "and")\
	X(As,            "as")\
	X(Break,         "break")\
	X(Continue,      "continue")\
	X(Do,            "do")\
	X(Else,          "else")\
	X(False,         "false")\
	X(For,           "for")\
	X(Foreach,       "foreach")\
	X(Function,      "function")\
	X(Global,        "global")\
	X(If,            "if")\
	X(Import,        "import")\
	X(Is,            "is")\
	X(Local,         "local")\
	X(NotKeyword,    "not")\
	X(Null,          "null")\
	X(OrKeyword,     "or")\
	X(Return,        "return")\
	X(Switch,        "switch")\
	X(This,          "this")\
	X(True,          "true")\
	X(Vararg,        "vararg")\
	X(While,         "while")\
	X(Yield,         "yield")

#define NONKEYWORD_LIST(X)\
	X(Add,           "+")\
	X(AddEq,         "+=")\
	X(Inc,           "++")\
	X(Sub,           "-")\
	X(SubEq,         "-=")\
	X(Dec,           "--")\
	X(Cat,           "~")\
	X(Mul,           "*")\
	X(MulEq,         "*=")\
	X(DefaultEq,     "?=")\
	X(Div,           "/")\
	X(DivEq,         "/=")\
	X(Mod,           "%")\
	X(ModEq,         "%=")\
	X(LT,            "<")\
	X(LE,            "<=")\
	X(Shl,           "<<")\
	X(ShlEq,         "<<=")\
	X(GT,            ">")\
	X(GE,            ">=")\
	X(Shr,           ">>")\
	X(ShrEq,         ">>=")\
	X(UShr,          ">>>")\
	X(UShrEq,        ">>>=")\
	X(And,           "&")\
	X(AndEq,         "&=")\
	X(AndAnd,        "&&")\
	X(Or,            "|")\
	X(OrEq,          "|=")\
	X(OrOr,          "||")\
	X(Xor,           "^")\
	X(XorEq,         "^=")\
	X(Assign,        "=")\
	X(EQ,            "==")\
	X(Dot,           ".")\
	X(DotDot,        "..")\
	X(Ellipsis,      "...")\
	X(Not,           "!")\
	X(NE,            "!=")\
	X(LParen,        "(")\
	X(RParen,        ")")\
	X(LBracket,      "[")\
	X(RBracket,      "]")\
	X(LBrace,        "{")\
	X(RBrace,        "}")\
	X(Colon,         ":")\
	X(Comma,         ",")\
	X(Semicolon,     ";")\
	X(Length,        "#")\
	X(Question,      "?")\
	X(Backslash,     "\\")\
	X(Arrow,         "->")\
	X(At,            "@")

#define MISC_TOKEN_LIST(X)\
	X(Ident,         "Identifier")\
	X(StringLiteral, "String Literal")\
	X(IntLiteral,    "Int Literal")\
	X(FloatLiteral,  "Float Literal")\
	X(EOF_,          "<EOF>")

#define TOKEN_LIST(X)\
	KEYWORD_LIST(X)\
	NONKEYWORD_LIST(X)\
	MISC_TOKEN_LIST(X)

struct Token
{
	enum
	{
#define POOP(Name, _) Name,
		TOKEN_LIST(POOP)
#undef POOP

		NUM_KEYWORDS = Yield + 1 // CAREFUL, this depends on the keywords being first in the list.
	};

	uint32_t type;

	union
	{
		bool boolValue;
		crocstr stringValue;
		crocint intValue;
		crocfloat floatValue;
	};

	NumFormat format;
	CompileLoc loc;
	crocstr preComment;
	crocstr postComment;
	CompileLoc preCommentLoc;
	CompileLoc postCommentLoc;
	const uchar* startChar;

	static crocstr KeywordStrings[];
	static const char* Strings[];

	inline bool isOpAssign()
	{
		switch(type)
		{
			case Token::AddEq:
			case Token::SubEq:
			case Token::MulEq:
			case Token::DivEq:
			case Token::ModEq:
			case Token::ShlEq:
			case Token::ShrEq:
			case Token::UShrEq:
			case Token::OrEq:
			case Token::XorEq:
			case Token::AndEq:
			case Token::DefaultEq:
				return true;

			default:
				return false;
		}
	}

	inline const char* typeString()
	{
		return Strings[type];
	}
};

struct Lexer
{
private:
	Compiler& mCompiler;
	CompileLoc mLoc;
	crocstr mSource;
	const uchar* mSourcePtr;
	const uchar* mSourceEnd;
	const uchar* mCharPos;
	const uchar* mLookaheadCharPos;

	crocchar mCharacter;
	crocchar mLookaheadCharacter;
	bool mHaveLookahead;
	bool mNewlineSinceLastTok;
	bool mTokSinceLastNewline;
	bool mHadLinePragma;
	crocstr mLinePragmaFile;
	uword mLinePragmaLine;

	const uchar* mCaptureEnd;

	Token mTok;
	Token mPeekTok;
	bool mHavePeekTok;

public:
	Lexer(Compiler& compiler) :
		mCompiler(compiler),
		mLoc(),
		mSource(),
		mSourcePtr(nullptr),
		mSourceEnd(nullptr),
		mCharPos(nullptr),
		mLookaheadCharPos(nullptr),
		mCharacter(0),
		mLookaheadCharacter(0),
		mHaveLookahead(false),
		mNewlineSinceLastTok(false),
		mTokSinceLastNewline(false),
		mHadLinePragma(false),
		mLinePragmaFile(),
		mLinePragmaLine(0),
		mCaptureEnd(nullptr),
		mTok(),
		mPeekTok(),
		mHavePeekTok(false)
	{}

	inline Token& tok() { return mTok; }
	inline CompileLoc& loc() { return mTok.loc; }
	inline uword type() { return mTok.type; }

	void begin(crocstr name, crocstr source);
	Token expect(uword t);
	void expected(const char* message);
	bool isStatementTerm();
	void statementTerm();
	Token& peek();
	void next();
	const uchar* beginCapture();
	crocstr endCapture(const uchar* captureStart);

private:
	static int lookupKeyword(crocstr str);
	crocchar readChar(const uchar*& pos);
	crocchar lookaheadChar();
	void nextChar();
	void nextLine(bool readMultiple = true);
	bool convertInt(crocstr str, crocint& ret, uword radix);
	bool convertUInt(crocstr str, crocint& ret, uword radix);
	bool readNumLiteral(bool prependPoint, crocfloat& fret, crocint& iret, NumFormat& format);
	uint32_t readHexDigits(uword num);
	crocchar readEscapeSequence(CompileLoc beginning);
	crocstr readStringLiteral(bool escape);
	uword readVerbatimOpening(CompileLoc beginning);
	crocstr readVerbatimString(CompileLoc beginning, uword equalLen);
	void addComment(crocstr str, CompileLoc location);
	void readLineComment();
	void readBlockComment();
	void nextToken();
};

#endif