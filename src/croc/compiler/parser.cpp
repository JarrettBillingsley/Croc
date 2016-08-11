
#include <stdio.h>

#include "croc/compiler/parser.hpp"
#include "croc/util/misc.hpp"

// =================================================================================================================
// Public
// =================================================================================================================

crocstr Parser::capture(std::function<void()> dg)
{
	if(c.docComments())
	{
		auto start = l.beginCapture();
		dg();
		return l.endCapture(start);
	}
	else
	{
		dg();
		return crocstr();
	}
}

crocstr Parser::parseName()
{
	return l.expect(Token::Ident).stringValue;
}

Expression* Parser::parseDottedName()
{
	Expression* ret = parseIdentExp();

	while(l.type() == Token::Dot)
	{
		l.next();
		auto tok = l.expect(Token::Ident);
		ret = new(c) DotExp(ret, new(c) StringExp(tok.loc, tok.stringValue));
	}

	return ret;
}

Identifier* Parser::parseIdentifier()
{
	auto tok = l.expect(Token::Ident);
	return new(c) Identifier(tok.loc, tok.stringValue);
}

DArray<Expression*> Parser::parseArguments()
{
	List<Expression*> args(c);
	args.add(parseExpression());

	while(l.type() == Token::Comma)
	{
		l.next();
		args.add(parseExpression());
	}

	return args.toArray();
}

BlockStmt* Parser::parseModule()
{
	auto location = l.loc();

	List<Statement*> statements(c);

	while(l.type() != Token::EOF_)
		statements.add(parseStatement());

	auto stmts = new(c) BlockStmt(location, l.loc(), statements.toArray());
	l.expect(Token::EOF_);
	return stmts;
}

Statement* Parser::parseStatement(bool needScope)
{
	switch(l.type())
	{
		case Token::Colon:
		case Token::Dec:
		case Token::False:
		case Token::FloatLiteral:
		case Token::Ident:
		case Token::Inc:
		case Token::IntLiteral:
		case Token::LBracket:
		case Token::Length:
		case Token::LParen:
		case Token::Null:
		case Token::Or:
		case Token::StringLiteral:
		case Token::This:
		case Token::True:
		case Token::Vararg:
		case Token::Yield:
			return parseExpressionStmt();

		case Token::Function:
		case Token::Global:
		case Token::Local:
		case Token::At:
			return parseDeclStmt();

		case Token::LBrace:
			if(needScope)
			{
				// don't inline this; memory management stuff.
				auto stmt = parseBlockStmt();
				return new(c) ScopeStmt(stmt);
			}
			else
				return parseBlockStmt();

		case Token::Break:    return parseBreakStmt();
		case Token::Continue: return parseContinueStmt();
		case Token::Do:       return parseDoWhileStmt();
		case Token::For:      return parseForStmt();
		case Token::Foreach:  return parseForeachStmt();
		case Token::If:       return parseIfStmt();
		case Token::Import:   return parseImportStmt();
		case Token::Return:   return parseReturnStmt();
		case Token::While:    return parseWhileStmt();

		case Token::Semicolon:
			c.synException(l.loc(), "Empty statements ( ';' ) are not allowed (use {} for an empty statement)");

		default:
			l.expected("statement");
	}

	assert(false);
	return nullptr; // dummy
}

Statement* Parser::parseExpressionStmt()
{
	auto stmt = parseStatementExpr();
	l.statementTerm();
	return stmt;
}

Decorator* Parser::parseDecorator()
{
	l.expect(Token::At);

	auto func = parseDottedName();
	auto argsArr = DArray<Expression*>();
	CompileLoc endLocation;

	if(l.type() == Token::LParen)
	{
		l.next();
		argsArr = parseArguments();
		endLocation = l.expect(Token::RParen).loc;
	}
	else
		endLocation = func->endLocation;

	return new(c) Decorator(func->location, endLocation, func, argsArr, nullptr);
}

Decorator* Parser::parseDecorators()
{
	auto first = parseDecorator();
	auto cur = first;

	while(l.type() == Token::At)
	{
		cur->nextDec = parseDecorator();
		cur = cur->nextDec;
	}

	return first;
}

Statement* Parser::parseDeclStmt()
{
	Decorator* deco = nullptr;

	auto docs = l.tok().preComment;
	auto docsLoc = l.tok().preCommentLoc;

	if(l.type() == Token::At)
		deco = parseDecorators();

	switch(l.type())
	{
		case Token::Local:
		case Token::Global:
			switch(l.peek().type)
			{
				case Token::Ident: {
					if(deco != nullptr)
						c.synException(l.loc(), "Cannot put decorators on variable declarations");

					auto ret = parseVarDecl();
					l.statementTerm();
					attachDocs(*ret, docs, docsLoc);
					return ret;
				}
				case Token::Function:
					{ auto ret = parseFuncDecl(deco);      attachDocs(*ret->def, docs, docsLoc); return ret; }

				default:
					c.synException(l.loc(), "Illegal token '%s' after '%s'",
						l.peek().typeString(), l.tok().typeString());
			}

		case Token::Function:
			{ auto ret = parseFuncDecl(deco);      attachDocs(*ret->def, docs, docsLoc); return ret; }

		default:
			l.expected("Declaration");
	}

	assert(false);
	return nullptr; // dummy
}

VarDecl* Parser::parseVarDecl()
{
	auto location = l.loc();
	auto protection = Protection::Local;

	if(l.type() == Token::Global)
	{
		protection = Protection::Global;
		l.next();
	}
	else
		l.expect(Token::Local);

	List<Identifier*> names(c);
	names.add(parseIdentifier());

	while(l.type() == Token::Comma)
	{
		l.next();
		names.add(parseIdentifier());
	}

	auto namesArr = names.toArray();
	auto endLocation = namesArr[namesArr.length - 1]->location;

	auto initializer = DArray<Expression*>();

	if(l.type() == Token::Assign)
	{
		l.next();
		List<Expression*> exprs(c);

		auto str = capture([&]{exprs.add(parseExpression());});

		if(c.docComments())
			exprs.last()->sourceStr = str;

		while(l.type() == Token::Comma)
		{
			l.next();

			auto valstr = capture([&]{exprs.add(parseExpression());});

			if(c.docComments())
				exprs.last()->sourceStr = valstr;
		}

		if(namesArr.length < exprs.length())
			c.semException(location, "Declaration has fewer variables than sources");

		initializer = exprs.toArray();
		endLocation = initializer[initializer.length - 1]->endLocation;
	}

	auto ret = new(c) VarDecl(location, endLocation, protection, namesArr, initializer);
	propagateFuncLiteralNames(ret->names.as<AstNode*>(), ret->initializer);
	return ret;
}

FuncDecl* Parser::parseFuncDecl(Decorator* deco)
{
	auto location = l.loc();
	auto protection = Protection::Default;

	if(l.type() == Token::Global)
	{
		protection = Protection::Global;
		l.next();
	}
	else if(l.type() == Token::Local)
	{
		protection = Protection::Local;
		l.next();
	}

	auto def = parseSimpleFuncDef();
	return new(c) FuncDecl(location, protection, def, deco);
}

FuncDef* Parser::parseFuncBody(CompileLoc location, Identifier* name)
{
	l.expect(Token::LParen);
	bool isVararg;
	auto params = parseFuncParams(isVararg);
	l.expect(Token::RParen);

	bool isVarret;
	auto returns = parseFuncReturns(isVarret);

	Statement* code = nullptr;

	if(l.type() == Token::Assign)
	{
		l.next();

		List<Expression*> dummy(c);
		dummy.add(parseExpression());
		auto arr = dummy.toArray();

		code = new(c) ReturnStmt(arr[0]->location, arr[0]->endLocation, arr);
	}
	else
		code = parseBlockStmt();

	return new(c) FuncDef(location, name, params, isVararg, returns, isVarret, code);
}

DArray<FuncParam> Parser::parseFuncParams(bool& isVararg)
{
	List<FuncParam> ret(c);

	auto parseParam = [&]()
	{
		FuncParam p;
		p.name = parseIdentifier();

		if(l.type() == Token::Assign)
		{
			l.next();
			p.valueString = capture([&]{p.defValue = parseExpression();});

			// Having a default parameter implies allowing null as a parameter type
			// p.typeMask |= cast(uint32_t)TypeMask::Null;
		}

		ret.add(p);
	};

	auto parseRestOfParams = [&]()
	{
		while(l.type() == Token::Comma)
		{
			l.next();

			if(l.type() == Token::Vararg || l.type() == Token::Ellipsis)
			{
				isVararg = true;
				l.next();
				break;
			}

			parseParam();
		}
	};

	if(l.type() == Token::This)
	{
		FuncParam p;
		auto thisLoc = l.loc();
		l.next();

		if(l.type() != Token::Colon)
			l.expected(":");

		p.name = new(c) Identifier(thisLoc, c.newString("this"));
		ret.add(p);

		if(l.type() == Token::Comma)
			parseRestOfParams();
	}
	else
	{
		ret.add(FuncParam(new(c) Identifier(l.loc(), c.newString("this"))));

		if(l.type() == Token::Ident)
		{
			parseParam();
			parseRestOfParams();
		}
		else if(l.type() == Token::Vararg || l.type() == Token::Ellipsis)
		{
			isVararg = true;
			l.next();
		}
	}

	return ret.toArray();
}

DArray<FuncReturn> Parser::parseFuncReturns(bool& isVarret)
{
	List<FuncReturn> ret(c);

	isVarret = true;
	return ret.toArray();
}

FuncDef* Parser::parseSimpleFuncDef()
{
	auto location = l.expect(Token::Function).loc;
	auto name = parseIdentifier();
	return parseFuncBody(location, name);
}

FuncDef* Parser::parseFuncLiteral()
{
	auto location = l.expect(Token::Function).loc;

	Identifier* name = nullptr;

	if(l.type() == Token::Ident)
		name = parseIdentifier();
	else
		name = dummyFuncLiteralName(location);

	return parseFuncBody(location, name);
}

FuncDef* Parser::parseHaskellFuncLiteral()
{
	auto location = l.expect(Token::Backslash).loc;
	auto name = dummyFuncLiteralName(location);

	bool isVararg;
	auto params = parseFuncParams(isVararg);

	Statement* code = nullptr;

	if(l.type() == Token::Arrow)
	{
		l.next();

		List<Expression*> dummy(c);
		dummy.add(parseExpression());
		auto arr = dummy.toArray();

		code = new(c) ReturnStmt(arr[0]->location, arr[0]->endLocation, arr);
	}
	else
		code = parseBlockStmt();

	return new(c) FuncDef(location, name, params, isVararg, code);
}

BlockStmt* Parser::parseBlockStmt()
{
	auto location = l.expect(Token::LBrace).loc;

	List<Statement*> statements(c);

	while(l.type() != Token::RBrace)
		statements.add(parseStatement());

	auto endLocation = l.expect(Token::RBrace).loc;
	return new(c) BlockStmt(location, endLocation, statements.toArray());
}

BreakStmt* Parser::parseBreakStmt()
{
	auto location = l.expect(Token::Break).loc;
	crocstr name = crocstr();

	if(!l.isStatementTerm() && l.type() == Token::Ident)
	{
		name = l.tok().stringValue;
		l.next();
	}

	l.statementTerm();
	return new(c) BreakStmt(location, name);
}

ContinueStmt* Parser::parseContinueStmt()
{
	auto location = l.expect(Token::Continue).loc;
	crocstr name = crocstr();

	if(!l.isStatementTerm() && l.type() == Token::Ident)
	{
		name = l.tok().stringValue;
		l.next();
	}

	l.statementTerm();
	return new(c) ContinueStmt(location, name);
}

DoWhileStmt* Parser::parseDoWhileStmt()
{
	auto location = l.expect(Token::Do).loc;
	auto doBody = parseStatement(false);

	l.expect(Token::While);

	crocstr name = crocstr();

	if(l.type() == Token::Ident)
	{
		name = l.tok().stringValue;
		l.next();
	}

	l.expect(Token::LParen);

	auto condition = parseExpression();
	auto endLocation = l.expect(Token::RParen).loc;
	return new(c) DoWhileStmt(location, endLocation, name, doBody, condition);
}

Statement* Parser::parseForStmt()
{
	auto location = l.expect(Token::For).loc;
	crocstr name = crocstr();

	if(l.type() == Token::Ident)
	{
		name = l.tok().stringValue;
		l.next();
	}

	l.expect(Token::LParen);

	List<ForStmtInit> init(c);

	auto parseInitializer = [&]()
	{
		ForStmtInit tmp;

		if(l.type() == Token::Local)
		{
			tmp.isDecl = true;
			tmp.decl = parseVarDecl();
		}
		else
		{
			tmp.isDecl = false;
			tmp.stmt = parseStatementExpr();
		}

		init.add(tmp);
	};

	if(l.type() == Token::Semicolon)
		l.next();
	else if(l.type() == Token::Ident && l.peek().type == Token::Semicolon)
	{
		auto index = parseIdentifier();

		l.next();

		auto lo = parseExpression();
		l.expect(Token::DotDot);
		auto hi = parseExpression();

		Expression* step = nullptr;

		if(l.type() == Token::Comma)
		{
			l.next();
			step = parseExpression();
		}
		else
			step = new(c) IntExp(l.loc(), 1);

		l.expect(Token::RParen);

		auto code = parseStatement();
		return new(c) ForNumStmt(location, name, index, lo, hi, step, code);
	}
	else
	{
		parseInitializer();

		while(l.type() == Token::Comma)
		{
			l.next();
			parseInitializer();
		}

		l.expect(Token::Semicolon);
	}

	Expression* condition = nullptr;

	if(l.type() == Token::Semicolon)
		l.next();
	else
	{
		condition = parseExpression();
		l.expect(Token::Semicolon);
	}

	List<Statement*> increment(c);

	if(l.type() == Token::RParen)
		l.next();
	else
	{
		increment.add(parseStatementExpr());

		while(l.type() == Token::Comma)
		{
			l.next();
			increment.add(parseStatementExpr());
		}

		l.expect(Token::RParen);
	}

	auto code = parseStatement(false);
	return new(c) ForStmt(location, name, init.toArray(), condition, increment.toArray(), code);
}

ForeachStmt* Parser::parseForeachStmt()
{
	auto location = l.expect(Token::Foreach).loc;
	crocstr name = crocstr();

	if(l.type() == Token::Ident)
	{
		name = l.tok().stringValue;
		l.next();
	}

	l.expect(Token::LParen);

	List<Identifier*> indices(c);
	indices.add(parseIdentifier());

	while(l.type() == Token::Comma)
	{
		l.next();
		indices.add(parseIdentifier());
	}

	auto indicesArr = DArray<Identifier*>();

	if(indices.length() == 1)
	{
		indices.add(cast(Identifier*)nullptr);
		indicesArr = indices.toArray();

		for(uword i = indicesArr.length - 1; i > 0; i--)
			indicesArr[i] = indicesArr[i - 1];

		indicesArr[0] = dummyForeachIndex(indicesArr[1]->location);
	}
	else
		indicesArr = indices.toArray();

	l.expect(Token::Semicolon);

	List<Expression*> container(c);
	container.add(parseExpression());

	while(l.type() == Token::Comma)
	{
		l.next();
		container.add(parseExpression());
	}

	if(container.length() > 3)
		c.synException(location, "'foreach' may have a maximum of three container expressions");

	l.expect(Token::RParen);

	auto code = parseStatement();
	return new(c) ForeachStmt(location, name, indicesArr, container.toArray(), code);
}

IfStmt* Parser::parseIfStmt()
{
	auto location = l.expect(Token::If).loc;
	l.expect(Token::LParen);

	IdentExp* condVar = nullptr;

	if(l.type() == Token::Local)
	{
		l.next();
		condVar = parseIdentExp();
		l.expect(Token::Assign);
	}

	auto condition = parseExpression();
	l.expect(Token::RParen);
	auto ifBody = parseStatement();

	Statement* elseBody = nullptr;

	auto endLocation = ifBody->endLocation;

	if(l.type() == Token::Else)
	{
		l.next();
		elseBody = parseStatement();
		endLocation = elseBody->endLocation;
	}

	return new(c) IfStmt(location, endLocation, condVar, condition, ifBody, elseBody);
}

ImportStmt* Parser::parseImportStmt()
{
	auto location = l.loc();

	l.expect(Token::Import);

	List<uchar, 32> name(c);
	name.add(parseName());

	while(l.type() == Token::Dot)
	{
		l.next();
		name.add('.');
		name.add(parseName());
	}

	auto expr = new(c) StringExp(location, c.newString(name.toArrayView()));

	Identifier* importName = nullptr;

	if(l.type() == Token::As)
	{
		l.next();
		importName = parseIdentifier();
	}

	List<Identifier*> symbols(c);
	List<Identifier*> symbolNames(c);

	auto parseSelectiveImport = [&]()
	{
		auto id = parseIdentifier();

		if(l.type() == Token::As)
		{
			l.next();
			symbolNames.add(parseIdentifier());
			symbols.add(id);
		}
		else
		{
			symbolNames.add(id);
			symbols.add(id);
		}
	};

	if(l.type() == Token::Colon)
	{
		l.next();

		parseSelectiveImport();

		while(l.type() == Token::Comma)
		{
			l.next();
			parseSelectiveImport();
		}
	}

	auto endLocation = l.loc();
	l.statementTerm();
	return new(c) ImportStmt(location, endLocation, importName, expr, symbols.toArray(), symbolNames.toArray());
}

ReturnStmt* Parser::parseReturnStmt()
{
	auto location = l.expect(Token::Return).loc;

	if(l.isStatementTerm())
	{
		auto endLocation = l.loc();
		l.statementTerm();
		return new(c) ReturnStmt(location, endLocation, DArray<Expression*>());
	}
	else
	{
		assert(l.loc().line == location.line);

		List<Expression*> exprs(c);
		exprs.add(parseExpression());

		while(l.type() == Token::Comma)
		{
			l.next();
			exprs.add(parseExpression());
		}

		auto arr = exprs.toArray();
		auto endLocation = arr[arr.length - 1]->endLocation;

		l.statementTerm();
		return new(c) ReturnStmt(location, endLocation, arr);
	}
}

WhileStmt* Parser::parseWhileStmt()
{
	auto location = l.expect(Token::While).loc;
	crocstr name = crocstr();

	if(l.type() == Token::Ident)
	{
		name = l.tok().stringValue;
		l.next();
	}

	l.expect(Token::LParen);

	IdentExp* condVar = nullptr;

	if(l.type() == Token::Local)
	{
		l.next();
		condVar = parseIdentExp();
		l.expect(Token::Assign);
	}

	auto condition = parseExpression();
	l.expect(Token::RParen);
	auto code = parseStatement(false);
	return new(c) WhileStmt(location, name, condVar, condition, code);
}

Statement* Parser::parseStatementExpr()
{
	auto location = l.loc();

	if(l.type() == Token::Inc)
	{
		l.next();
		auto exp = parsePrimaryExp();
		return new(c) IncStmt(location, location, exp);
	}
	else if(l.type() == Token::Dec)
	{
		l.next();
		auto exp = parsePrimaryExp();
		return new(c) DecStmt(location, location, exp);
	}

	Expression* exp = nullptr;

	if(l.type() == Token::Length)
		exp = parseUnExp();
	else
		exp = parsePrimaryExp();

	if(l.tok().isOpAssign())
		return parseOpAssignStmt(exp);
	else if(l.type() == Token::Assign || l.type() == Token::Comma)
		return parseAssignStmt(exp);
	else if(l.type() == Token::Inc)
	{
		l.next();
		return new(c) IncStmt(location, location, exp);
	}
	else if(l.type() == Token::Dec)
	{
		l.next();
		return new(c) DecStmt(location, location, exp);
	}
	else if(l.type() == Token::OrOr || l.type() == Token::OrKeyword)
		exp = parseOrOrExp(exp);
	else if(l.type() == Token::AndAnd || l.type() == Token::AndKeyword)
		exp = parseAndAndExp(exp);
	else if(l.type() == Token::Question)
		exp = parseCondExp(exp);

	exp->checkToNothing(c);
	return new(c) ExpressionStmt(exp);
}

AssignStmt* Parser::parseAssignStmt(Expression* firstLHS)
{
	auto location = l.loc();

	List<Expression*> lhs(c);
	lhs.add(firstLHS);

	while(l.type() == Token::Comma)
	{
		l.next();

		if(l.type() == Token::Length)
			lhs.add(parseUnExp());
		else
			lhs.add(parsePrimaryExp());
	}

	l.expect(Token::Assign);

	List<Expression*> rhs(c);
	rhs.add(parseExpression());

	while(l.type() == Token::Comma)
	{
		l.next();
		rhs.add(parseExpression());
	}

	if(lhs.length() < rhs.length())
		c.semException(location, "Assignment has fewer destinations than sources");

	auto rhsArr = rhs.toArray();
	auto ret = new(c) AssignStmt(location, rhsArr[rhsArr.length - 1]->endLocation, lhs.toArray(), rhsArr);
	propagateFuncLiteralNames(ret->lhs.as<AstNode*>(), ret->rhs);
	return ret;
}

Statement* Parser::parseOpAssignStmt(Expression* exp1)
{
	auto location = l.loc();

#define MAKE_CASE(tok, type)\
case Token::tok: {\
	l.next();\
	auto exp2 = parseExpression(); \
	return new(c) type(location, exp2->endLocation, exp1, exp2);\
}

	switch(l.type())
	{
		MAKE_CASE(AddEq,     AddAssignStmt)
		MAKE_CASE(SubEq,     SubAssignStmt)
		MAKE_CASE(CatEq,     CatAssignStmt)
		MAKE_CASE(MulEq,     MulAssignStmt)
		MAKE_CASE(DivEq,     DivAssignStmt)
		MAKE_CASE(ModEq,     ModAssignStmt)
		MAKE_CASE(ShlEq,     ShlAssignStmt)
		MAKE_CASE(ShrEq,     ShrAssignStmt)
		MAKE_CASE(UShrEq,    UShrAssignStmt)
		MAKE_CASE(XorEq,     XorAssignStmt)
		MAKE_CASE(OrEq,      OrAssignStmt)
		MAKE_CASE(AndEq,     AndAssignStmt)
		MAKE_CASE(DefaultEq, CondAssignStmt)
		default: assert(false); return nullptr; // dummy
	}
#undef MAKE_CASE
}

Expression* Parser::parseExpression()
{
	return parseCondExp();
}

Expression* Parser::parseCondExp(Expression* exp1)
{
	auto location = l.loc();

	Expression* exp2 = nullptr;
	Expression* exp3 = nullptr;

	if(exp1 == nullptr)
		exp1 = parseLogicalCondExp();

	while(l.type() == Token::Question)
	{
		l.next();

		exp2 = parseExpression();
		l.expect(Token::Colon);
		exp3 = parseCondExp();
		exp1 = new(c) CondExp(location, exp3->endLocation, exp1, exp2, exp3);

		location = l.loc();
	}

	return exp1;
}

Expression* Parser::parseLogicalCondExp()
{
	Expression* exp1 = parseOrExp();

	switch(l.type())
	{
		case Token::OrOr:
		case Token::OrKeyword:
			return parseOrOrExp(exp1);

		case Token::AndAnd:
		case Token::AndKeyword:
			return parseAndAndExp(exp1);

		default:
			return exp1;
	}
}

Expression* Parser::parseOrOrExp(Expression* exp1)
{
	auto location = l.loc();

	Expression* exp2 = nullptr;

	if(exp1 == nullptr)
		exp1 = parseOrExp();

	while(l.type() == Token::OrOr || l.type() == Token::OrKeyword)
	{
		l.next();

		exp2 = parseOrExp();
		exp1 = new(c) OrOrExp(location, exp2->endLocation, exp1, exp2);

		location = l.loc();
	}

	return exp1;
}

Expression* Parser::parseAndAndExp(Expression* exp1)
{
	auto location = l.loc();

	Expression* exp2 = nullptr;

	if(exp1 == nullptr)
		exp1 = parseOrExp();

	while(l.type() == Token::AndAnd || l.type() == Token::AndKeyword)
	{
		l.next();

		exp2 = parseOrExp();
		exp1 = new(c) AndAndExp(location, exp2->endLocation, exp1, exp2);

		location = l.loc();
	}

	return exp1;
}

Expression* Parser::parseOrExp()
{
	auto location = l.loc();

	Expression* exp1 = nullptr;
	Expression* exp2 = nullptr;

	exp1 = parseXorExp();

	while(l.type() == Token::Or)
	{
		l.next();

		exp2 = parseXorExp();
		exp1 = new(c) OrExp(location, exp2->endLocation, exp1, exp2);

		location = l.loc();
	}

	return exp1;
}

Expression* Parser::parseXorExp()
{
	auto location = l.loc();

	Expression* exp1 = nullptr;
	Expression* exp2 = nullptr;

	exp1 = parseAndExp();

	while(l.type() == Token::Xor)
	{
		l.next();

		exp2 = parseAndExp();
		exp1 = new(c) XorExp(location, exp2->endLocation, exp1, exp2);

		location = l.loc();
	}

	return exp1;
}

Expression* Parser::parseAndExp()
{
	CompileLoc location = l.loc();

	Expression* exp1 = nullptr;
	Expression* exp2 = nullptr;

	exp1 = parseCmpExp();

	while(l.type() == Token::And)
	{
		l.next();

		exp2 = parseCmpExp();
		exp1 = new(c) AndExp(location, exp2->endLocation, exp1, exp2);

		location = l.loc();
	}

	return exp1;
}

Expression* Parser::parseCmpExp()
{
	auto location = l.loc();

	auto exp1 = parseShiftExp();
	Expression* exp2 = nullptr;

	switch(l.type())
	{
		case Token::EQ:
			l.next();
			exp2 = parseShiftExp();
			exp1 = new(c) EqualExp(location, exp2->endLocation, exp1, exp2);
			break;

		case Token::NE:
			l.next();
			exp2 = parseShiftExp();
			exp1 = new(c) NotEqualExp(location, exp2->endLocation, exp1, exp2);
			break;

		case Token::Is:
			if(l.peek().type == Token::NotKeyword)
			{
				l.next();
				l.next();
				exp2 = parseShiftExp();
				exp1 = new(c) NotIsExp(location, exp2->endLocation, exp1, exp2);
			}
			else
			{
				l.next();
				exp2 = parseShiftExp();
				exp1 = new(c) IsExp(location, exp2->endLocation, exp1, exp2);
			}
			break;

		case Token::LT:
			l.next();
			exp2 = parseShiftExp();
			exp1 = new(c) LTExp(location, exp2->endLocation, exp1, exp2);
			break;

		case Token::LE:
			l.next();
			exp2 = parseShiftExp();
			exp1 = new(c) LEExp(location, exp2->endLocation, exp1, exp2);
			break;

		case Token::GT:
			l.next();
			exp2 = parseShiftExp();
			exp1 = new(c) GTExp(location, exp2->endLocation, exp1, exp2);
			break;

		case Token::GE:
			l.next();
			exp2 = parseShiftExp();
			exp1 = new(c) GEExp(location, exp2->endLocation, exp1, exp2);
			break;

		case Token::Cmp3:
			l.next();
			exp2 = parseShiftExp();
			exp1 = new(c) Cmp3Exp(location, exp2->endLocation, exp1, exp2);
			break;

		default:
			break;
	}

	return exp1;
}

Expression* Parser::parseShiftExp()
{
	auto location = l.loc();

	auto exp1 = parseAddExp();
	Expression* exp2 = nullptr;

	while(true)
	{
		switch(l.type())
		{
			case Token::Shl:
				l.next();
				exp2 = parseAddExp();
				exp1 = new(c) ShlExp(location, exp2->endLocation, exp1, exp2);
				continue;

			case Token::Shr:
				l.next();
				exp2 = parseAddExp();
				exp1 = new(c) ShrExp(location, exp2->endLocation, exp1, exp2);
				continue;

			case Token::UShr:
				l.next();
				exp2 = parseAddExp();
				exp1 = new(c) UShrExp(location, exp2->endLocation, exp1, exp2);
				continue;

			default:
				break;
		}

		break;
	}

	return exp1;
}

Expression* Parser::parseAddExp()
{
	auto location = l.loc();

	auto exp1 = parseMulExp();
	Expression* exp2 = nullptr;

	while(true)
	{
		switch(l.type())
		{
			case Token::Add:
				l.next();
				exp2 = parseMulExp();
				exp1 = new(c) AddExp(location, exp2->endLocation, exp1, exp2);
				continue;

			case Token::Sub:
				l.next();
				exp2 = parseMulExp();
				exp1 = new(c) SubExp(location, exp2->endLocation, exp1, exp2);
				continue;

			case Token::Cat:
				l.next();
				exp2 = parseMulExp();
				exp1 = new(c) CatExp(location, exp2->endLocation, exp1, exp2);
				continue;

			default:
				break;
		}

		break;
	}

	return exp1;
}

Expression* Parser::parseMulExp()
{
	auto location = l.loc();

	auto exp1 = parseUnExp();
	Expression* exp2 = nullptr;

	while(true)
	{
		switch(l.type())
		{
			case Token::Mul:
				l.next();
				exp2 = parseUnExp();
				exp1 = new(c) MulExp(location, exp2->endLocation, exp1, exp2);
				continue;

			case Token::Div:
				l.next();
				exp2 = parseUnExp();
				exp1 = new(c) DivExp(location, exp2->endLocation, exp1, exp2);
				continue;

			case Token::Mod:
				l.next();
				exp2 = parseUnExp();
				exp1 = new(c) ModExp(location, exp2->endLocation, exp1, exp2);
				continue;

			default:
				break;
		}

		break;
	}

	return exp1;
}

Expression* Parser::parseUnExp()
{
	auto location = l.loc();

	Expression* exp = nullptr;

	switch(l.type())
	{
		case Token::Sub:
			l.next();
			exp = parseUnExp();
			exp = new(c) NegExp(location, exp);
			break;

		case Token::Not:
		case Token::NotKeyword:
			l.next();
			exp = parseUnExp();
			exp = new(c) NotExp(location, exp);
			break;

		case Token::Cat:
			l.next();
			exp = parseUnExp();
			exp = new(c) ComExp(location, exp);
			break;

		case Token::Length:
			l.next();
			exp = parseUnExp();

			if(exp->type == AstTag_VarargExp)
				exp = new(c) VargLenExp(location, exp->endLocation);
			else
				exp = new(c) LenExp(location, exp);
			break;

		default:
			exp = parsePrimaryExp();
			break;
	}

	return exp;
}

Expression* Parser::parsePrimaryExp()
{
	Expression* exp = nullptr;

	switch(l.type())
	{
		case Token::Ident:                  exp = parseIdentExp(); break;
		case Token::This:                   exp = parseThisExp(); break;
		case Token::Null:                   exp = parseNullExp(); break;
		case Token::True:
		case Token::False:                  exp = parseBoolExp(); break;
		case Token::Vararg:                 exp = parseVarargExp(); break;
		case Token::IntLiteral:             exp = parseIntExp(); break;
		case Token::FloatLiteral:           exp = parseFloatExp(); break;
		case Token::StringLiteral:          exp = parseStringExp(); break;
		case Token::Function:               exp = parseFuncLiteralExp(); break;
		case Token::Backslash:              exp = parseHaskellFuncLiteralExp(); break;
		case Token::LParen:                 exp = parseParenExp(); break;
		case Token::LBrace:                 exp = parseTableCtorExp(); break;
		case Token::LBracket:               exp = parseArrayCtorExp(); break;
		case Token::Yield:                  exp = parseYieldExp(); break;
		case Token::Colon:                  exp = parseMemberExp(); break;

		default:
			l.expected("expression");
	}

	return parsePostfixExp(exp);
}

IdentExp* Parser::parseIdentExp()
{
	auto id = parseIdentifier();
	return new(c) IdentExp(id);
}

ThisExp* Parser::parseThisExp()
{
	auto tok = l.expect(Token::This);
	return new(c) ThisExp(tok.loc);
}

NullExp* Parser::parseNullExp()
{
	auto tok = l.expect(Token::Null);
	return new(c) NullExp(tok.loc);
}

BoolExp* Parser::parseBoolExp()
{
	auto loc = l.loc();

	if(l.type() == Token::True)
	{
		l.expect(Token::True);
		return new(c) BoolExp(loc, true);
	}
	else
	{
		l.expect(Token::False);
		return new(c) BoolExp(loc, false);
	}
}

VarargExp* Parser::parseVarargExp()
{
	auto tok = l.expect(Token::Vararg);
	return new(c) VarargExp(tok.loc);
}

IntExp* Parser::parseIntExp()
{
	auto tok = l.expect(Token::IntLiteral);
	return new(c) IntExp(tok.loc, tok.intValue);
}

FloatExp* Parser::parseFloatExp()
{
	auto tok = l.expect(Token::FloatLiteral);
	return new(c) FloatExp(tok.loc, tok.floatValue);
}

StringExp* Parser::parseStringExp()
{
	auto tok = l.expect(Token::StringLiteral);
	return new(c) StringExp(tok.loc, tok.stringValue);
}

FuncLiteralExp* Parser::parseFuncLiteralExp()
{
	auto location = l.loc();
	auto def = parseFuncLiteral();
	return new(c) FuncLiteralExp(location, def);
}

FuncLiteralExp* Parser::parseHaskellFuncLiteralExp()
{
	auto location = l.loc();
	auto def = parseHaskellFuncLiteral();
	return new(c) FuncLiteralExp(location, def);
}

Expression* Parser::parseParenExp()
{
	auto location = l.expect(Token::LParen).loc;
	auto exp = parseExpression();
	auto endLocation = l.expect(Token::RParen).loc;
	return new(c) ParenExp(location, endLocation, exp);
}

Expression* Parser::parseTableCtorExp()
{
	auto location = l.expect(Token::LBrace).loc;

	List<TableCtorField> fields(c);

	if(l.type() != Token::RBrace)
	{
		auto parseField = [&]()
		{
			Expression* k = nullptr;
			Expression* v = nullptr;

			switch(l.type())
			{
				case Token::LBracket: {
					l.next();
					k = parseExpression();

					l.expect(Token::RBracket);
					l.expect(Token::Assign);

					v = parseExpression();
					break;
				}
				case Token::Function: {
					auto fd = parseSimpleFuncDef();
					k = new(c) StringExp(fd->location, fd->name->name);
					v = new(c) FuncLiteralExp(fd->location, fd);
					break;
				}
				default:
					Identifier* id = parseIdentifier();
					l.expect(Token::Assign);
					k = new(c) StringExp(id->location, id->name);
					v = parseExpression();

					if(auto fl = AST_AS(FuncLiteralExp, v))
						propagateFuncLiteralName(k, fl);
					break;
			}

			fields.add(TableCtorField(k, v));
		};

		parseField();

		if(l.type() == Token::Comma)
			l.next();

		while(l.type() != Token::RBrace)
		{
			parseField();

			if(l.type() == Token::Comma)
				l.next();
		}
	}

	auto endLocation = l.expect(Token::RBrace).loc;
	return new(c) TableCtorExp(location, endLocation, fields.toArray());
}

PrimaryExp* Parser::parseArrayCtorExp()
{
	auto location = l.expect(Token::LBracket).loc;

	List<Expression*> values(c);

	if(l.type() != Token::RBracket)
	{
		auto exp = parseExpression();

		values.add(exp);

		if(l.type() == Token::Comma)
			l.next();

		while(l.type() != Token::RBracket)
		{
			values.add(parseExpression());

			if(l.type() == Token::Comma)
				l.next();
		}
	}

	auto endLocation = l.expect(Token::RBracket).loc;
	return new(c) ArrayCtorExp(location, endLocation, values.toArray());
}

YieldExp* Parser::parseYieldExp()
{
	auto location = l.expect(Token::Yield).loc;
	l.expect(Token::LParen);

	auto args = DArray<Expression*>();

	if(l.type() != Token::RParen)
		args = parseArguments();

	auto endLocation = l.expect(Token::RParen).loc;
	return new(c) YieldExp(location, endLocation, args);
}

Expression* Parser::parseMemberExp()
{
	auto loc = l.expect(Token::Colon).loc;
	CompileLoc endLoc;

	if(l.type() == Token::LParen)
	{
		l.next();
		auto exp = parseExpression();
		endLoc = l.expect(Token::RParen).loc;
		return new(c) DotExp(new(c) ThisExp(loc), exp);
	}
	else
	{
		endLoc = l.loc();
		auto name = parseName();
		return new(c) DotExp(new(c) ThisExp(loc), new(c) StringExp(endLoc, name));
	}
}

Expression* Parser::parsePostfixExp(Expression* exp)
{
	while(true)
	{
		auto location = l.loc();

		switch(l.type())
		{
			case Token::Dot:
				l.next();

				if(l.type() == Token::Ident)
				{
					auto loc = l.loc();
					auto name = parseName();
					exp = new(c) DotExp(exp, new(c) StringExp(loc, name));
				}
				else
				{
					l.expect(Token::LParen);
					auto subExp = parseExpression();
					l.expect(Token::RParen);
					exp = new(c) DotExp(exp, subExp);
				}
				continue;

			case Token::LParen: {
				if(exp->endLocation.line != l.loc().line)
					return exp;

				l.next();

				auto args = DArray<Expression*>();

				if(l.type() != Token::RParen)
					args = parseArguments();

				auto endLocation = l.expect(Token::RParen).loc;

				// if(auto dot = AST_AS(DotExp, exp))
				// 	exp = new(c) MethodCallExp(dot->location, endLocation, dot->op, dot->name, args);
				// else
					exp = new(c) CallExp(endLocation, exp, args);
				continue;
			}
			case Token::LBracket: {
				l.next();

				Expression* loIndex = nullptr;
				CompileLoc endLocation;

				loIndex = parseExpression();
				endLocation = l.expect(Token::RBracket).loc;

				if(exp->type == AstTag_VarargExp)
					exp = new(c) VargIndexExp(location, endLocation, loIndex);
				else
					exp = new(c) IndexExp(endLocation, exp, loIndex);

				continue;
			}
			default:
				return exp;
		}
	}
}

// =================================================================================================================
// Private
// =================================================================================================================

void Parser::propagateFuncLiteralNames(DArray<AstNode*> lhs, DArray<Expression*> rhs)
{
	// Rename function literals on the RHS that have dummy names with appropriate names derived from the LHS.
	uword i = 0;
	for(auto r: rhs)
	{
		if(auto fl = AST_AS(FuncLiteralExp, r))
			propagateFuncLiteralName(lhs[i], fl);
		i++;
	}
}

void Parser::propagateFuncLiteralName(AstNode* lhs, FuncLiteralExp* fl)
{
	if(fl->def->name->name[0] != '<')
		return;

	if(auto id = AST_AS(Identifier, lhs))
	{
		// This case happens in variable declarations
		fl->def->name = new(c) Identifier(fl->def->name->location, id->name);
	}
	else if(auto id = AST_AS(IdentExp, lhs))
	{
		// This happens in assignments
		fl->def->name = new(c) Identifier(fl->def->name->location, id->name->name);
	}
	else if(auto str = AST_AS(StringExp, lhs))
	{
		// This happens in table ctors
		fl->def->name = new(c) Identifier(fl->def->name->location, str->value);
	}
	else if(auto fe = AST_AS(DotExp, lhs))
	{
		if(auto id = AST_AS(StringExp, fe->name))
		{
			// This happens in assignments
			fl->def->name = new(c) Identifier(fl->def->name->location, id->value);
		}
	}
}

Identifier* Parser::dummyForeachIndex(CompileLoc loc)
{
	char buf[256];
	snprintf(buf, 256, "dummy%" CROC_SIZE_T_FORMAT, mDummyNameCounter++);
	auto str = c.newString(buf);
	return new(c) Identifier(loc, str);
}

Identifier* Parser::dummyFuncLiteralName(CompileLoc loc)
{

	char buf[256];
	snprintf(buf, 256,
		"<literal at %s(%" CROC_SIZE_T_FORMAT ":%" CROC_SIZE_T_FORMAT ")>", loc.file.ptr, loc.line, loc.col);
	auto str = c.newString(buf);
	return new(c) Identifier(loc, str);
}

Expression* Parser::decoToExp(Decorator* dec, Expression* exp)
{
	List<Expression*> args(c);

	if(dec->nextDec)
		args.add(decoToExp(dec->nextDec, exp));
	else
		args.add(exp);

	args.add(dec->args);
	auto argsArray = args.toArray();

	// if(auto f = AST_AS(DotExp, dec->func))
	// 	return new(c) MethodCallExp(dec->location, dec->endLocation, f->op, f->name, argsArray);
	// else
		return new(c) CallExp(dec->endLocation, dec->func, argsArray);
}