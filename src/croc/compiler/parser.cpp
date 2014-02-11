
#include "croc/compiler/parser.hpp"

namespace croc
{
	// =================================================================================================================
	// Public
	// =================================================================================================================

	const char* Parser::capture(std::function<void()> dg)
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
			return nullptr;
		}
	}

	const char* Parser::parseName()
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

	Module* Parser::parseModule()
	{
		auto location = l.loc();
		auto docs = l.tok().preComment;
		auto docsLoc = l.tok().preCommentLoc;
		Decorator* dec = nullptr;

		if(l.type() == Token::At)
			dec = parseDecorators();

		l.expect(Token::Module);

		List<char, 32> name(c);
		name.add(atoda(parseName()));

		while(l.type() == Token::Dot)
		{
			l.next();
			name.add('.');
			name.add(atoda(parseName()));
		}

		l.statementTerm();

		List<Statement*> statements(c);

		while(l.type() != Token::EOF_)
			statements.add(parseStatement());

		auto stmts = new(c) BlockStmt(location, l.loc(), statements.toArray());

		auto tok = l.expect(Token::EOF_);

		if(tok.preComment != nullptr)
			c.danglingDocException(tok.preCommentLoc, "Doc comment at end of module not attached to any declaration");

		auto ret = new(c) Module(location, l.loc(), c.newString(name.toArrayView().toConst()), stmts, dec);

		// Prevent final docs from being erroneously attached to the module
		l.tok().postComment = nullptr;
		attachDocs(*ret, docs, docsLoc);
		return ret;
	}

	FuncDef* Parser::parseStatements(const char* name)
	{
		auto location = l.loc();

		List<Statement*> statements(c);

		while(l.type() != Token::EOF_)
			statements.add(parseStatement());

		auto tok = l.expect(Token::EOF_);

		if(tok.preComment != nullptr)
			c.danglingDocException(tok.preCommentLoc, "Doc comment at end of code not attached to any declaration");

		auto endLocation = statements.length() > 0 ? statements.last()->endLocation : location;
		auto code = new(c) BlockStmt(location, endLocation, statements.toArray());
		List<FuncParam> params(c);
		params.add(FuncParam(new(c) Identifier(l.loc(), c.newString("this"))));
		return new(c) FuncDef(location, new(c) Identifier(location, c.newString(name)), params.toArray(), true, code);
	}

	FuncDef* Parser::parseExpressionFunc(const char* name)
	{
		auto location = l.loc();

		List<Statement*> statements(c);
		List<Expression*> exprs(c);
		exprs.add(parseExpression());

		if(l.type() != Token::EOF_)
			c.synException(l.loc(), "Extra unexpected code after expression");

		statements.add(new(c) ReturnStmt(exprs[0]->location, exprs[0]->endLocation, exprs.toArray()));
		auto code = new(c) BlockStmt(location, statements[0]->endLocation, statements.toArray());
		List<FuncParam> params(c);
		params.add(FuncParam(new(c) Identifier(l.loc(), c.newString("this"))));
		return new(c) FuncDef(location, new(c) Identifier(location, c.newString(name)), params.toArray(), true, code);
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
			case Token::Super:
			case Token::This:
			case Token::True:
			case Token::Vararg:
			case Token::Yield:
				return parseExpressionStmt();

			case Token::Class:
			case Token::Function:
			case Token::Global:
			case Token::Local:
			case Token::Namespace:
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

			case Token::Assert:   return parseAssertStmt();
			case Token::Break:    return parseBreakStmt();
			case Token::Continue: return parseContinueStmt();
			case Token::Do:       return parseDoWhileStmt();
			case Token::For:      return parseForStmt();
			case Token::Foreach:  return parseForeachStmt();
			case Token::If:       return parseIfStmt();
			case Token::Import:   return parseImportStmt();
			case Token::Return:   return parseReturnStmt();
			case Token::Scope:    return parseScopeActionStmt();
			case Token::Switch:   return parseSwitchStmt();
			case Token::Throw:    return parseThrowStmt();
			case Token::Try:      return parseTryStmt();
			case Token::While:    return parseWhileStmt();

			case Token::Semicolon:
				c.synException(l.loc(), "Empty statements ( ';' ) are not allowed (use {} for an empty statement)");

			default:
				l.expected("statement");
		}

		assert(false);
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
		Expression* context = nullptr;
		CompileLoc endLocation;

		if(l.type() == Token::Dollar)
		{
			l.next();

			List<Expression*> args(c);
			args.add(parseExpression());

			while(l.type() == Token::Comma)
			{
				l.next();
				args.add(parseExpression());
			}

			argsArr = args.toArray();
		}
		else if(l.type() == Token::LParen)
		{
			l.next();

			if(l.type() == Token::With)
			{
				l.next();

				context = parseExpression();

				if(l.type() == Token::Comma)
				{
					l.next();
					argsArr = parseArguments();
				}
			}
			else if(l.type() != Token::RParen)
				argsArr = parseArguments();

			endLocation = l.expect(Token::RParen).loc;
		}
		else
			endLocation = func->endLocation;

		return new(c) Decorator(func->location, endLocation, func, context, argsArr, nullptr);
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
					case Token::Class:
						{ auto ret = parseClassDecl(deco);     attachDocs(*ret,      docs, docsLoc); return ret; }
					case Token::Namespace:
						{ auto ret = parseNamespaceDecl(deco); attachDocs(*ret,      docs, docsLoc); return ret; }

					default:
						c.synException(l.loc(), "Illegal token '%s' after '%s'",
							l.peek().typeString(), l.tok().typeString());
				}

			case Token::Function:
				{ auto ret = parseFuncDecl(deco);      attachDocs(*ret->def, docs, docsLoc); return ret; }
			case Token::Class:
				{ auto ret = parseClassDecl(deco);     attachDocs(*ret,      docs, docsLoc); return ret; }
			case Token::Namespace:
				{ auto ret = parseNamespaceDecl(deco); attachDocs(*ret,      docs, docsLoc); return ret; }

			default:
				l.expected("Declaration");
		}

		assert(false);
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
		{
			code = parseStatement();

			if(code->type != AstTag_BlockStmt)
			{
				List<Statement*> dummy(c);
				dummy.add(code);
				auto arr = dummy.toArray();
				code = new(c) BlockStmt(code->location, code->endLocation, arr);
			}
		}

		return new(c) FuncDef(location, name, params, isVararg, code);
	}

	DArray<FuncParam> Parser::parseFuncParams(bool& isVararg)
	{
		List<FuncParam> ret(c);

		auto parseParam = [&]()
		{
			FuncParam p;
			p.name = parseIdentifier();

			if(l.type() == Token::Colon)
			{
				l.next();
				p.typeMask = parseParamType(p.classTypes, p.typeString, p.customConstraint);
			}

			if(l.type() == Token::Assign)
			{
				l.next();
				p.valueString = capture([&]{p.defValue = parseExpression();});

				// Having a default parameter implies allowing nullptr as a parameter type
				p.typeMask |= cast(uint32_t)TypeMask::Null;
			}

			ret.add(p);
		};

		auto parseRestOfParams = [&]()
		{
			while(l.type() == Token::Comma)
			{
				l.next();

				if(l.type() == Token::Vararg)
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
			p.name = new(c) Identifier(l.loc(), c.newString("this"));

			l.next();
			l.expect(Token::Colon);
			p.typeMask = parseParamType(p.classTypes, p.typeString, p.customConstraint);

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
			else if(l.type() == Token::Vararg)
			{
				isVararg = true;
				l.next();
			}
		}

		return ret.toArray();
	}

	uint32_t Parser::parseParamType(DArray<Expression*>& classTypes, const char*& typeString,
		Expression*& customConstraint)
	{
		uint32_t ret = 0;
		List<Expression*> objTypes(c);

		auto addConstraint = [&](CrocType t)
		{
			if((ret & (1 << cast(uint32_t)t)) && t != CrocType_Instance)
				c.semException(l.loc(), "Duplicate parameter type constraint for type '%s'", typeToString(t));

			ret |= 1 << cast(uint32_t)t;
		};

		auto parseIdentList = [&](Token t) -> Expression*
		{
			l.next();
			auto t2 = l.expect(Token::Ident);
			auto exp = new(c) DotExp(new(c) IdentExp(new(c) Identifier(t.loc, t.stringValue)),
				new(c) StringExp(t2.loc, t2.stringValue));

			while(l.type() == Token::Dot)
			{
				l.next();
				t2 = l.expect(Token::Ident);
				exp = new(c) DotExp(exp, new(c) StringExp(t2.loc, t2.stringValue));
			}

			return exp;
		};

		auto parseSingleType = [&]()
		{
			switch(l.type())
			{
				case Token::Null:      addConstraint(CrocType_Null);      l.next(); break;
				case Token::Function:  addConstraint(CrocType_Function);  l.next(); break;
				case Token::Namespace: addConstraint(CrocType_Namespace); l.next(); break;
				case Token::Class:     addConstraint(CrocType_Class);     l.next(); break;

				default:
					auto t = l.expect(Token::Ident);

					if(l.type() == Token::Dot)
					{
						addConstraint(CrocType_Instance);
						objTypes.add(parseIdentList(t));
					}
					else
					if(strcmp(t.stringValue, "bool") == 0)      addConstraint(CrocType_Bool); else
					if(strcmp(t.stringValue, "int") == 0)       addConstraint(CrocType_Int); else
					if(strcmp(t.stringValue, "float") == 0)     addConstraint(CrocType_Float); else
					if(strcmp(t.stringValue, "string") == 0)    addConstraint(CrocType_String); else
					if(strcmp(t.stringValue, "table") == 0)     addConstraint(CrocType_Table); else
					if(strcmp(t.stringValue, "array") == 0)     addConstraint(CrocType_Array); else
					if(strcmp(t.stringValue, "memblock") == 0)  addConstraint(CrocType_Memblock); else
					if(strcmp(t.stringValue, "thread") == 0)    addConstraint(CrocType_Thread); else
					if(strcmp(t.stringValue, "nativeobj") == 0) addConstraint(CrocType_Nativeobj); else
					if(strcmp(t.stringValue, "weakref") == 0)   addConstraint(CrocType_Weakref); else
					if(strcmp(t.stringValue, "funcdef") == 0)   addConstraint(CrocType_Funcdef); else
					if(strcmp(t.stringValue, "instance") == 0)
					{
						addConstraint(CrocType_Instance);

						if(l.type() == Token::LParen)
						{
							l.next();
							objTypes.add(parseExpression());
							l.expect(Token::RParen);
						}
						else if(l.type() == Token::Ident)
						{
							auto tt = l.expect(Token::Ident);

							if(l.type() == Token::Dot)
								objTypes.add(parseIdentList(tt));
							else
								objTypes.add(new(c) IdentExp(new(c) Identifier(tt.loc, tt.stringValue)));
						}
						else if(l.type() != Token::Or &&
							l.type() != Token::Comma &&
							l.type() != Token::RParen &&
							l.type() != Token::Arrow)

							l.expected("class type");
					}
					else
					{
						addConstraint(CrocType_Instance);
						objTypes.add(new(c) IdentExp(new(c) Identifier(t.loc, t.stringValue)));
						break;
					}
					break;
			}
		};

		typeString = capture([&]
		{
			if(l.type() == Token::At)
			{
				l.next();
				auto n = l.expect(Token::Ident);

				if(l.type() == Token::Dot)
					customConstraint = parseIdentList(n);
				else
					customConstraint = new(c) IdentExp(new(c) Identifier(n.loc, n.stringValue));

				ret = cast(uint32_t)TypeMask::Any;
			}
			else if(l.type() == Token::Not || l.type() == Token::NotKeyword)
			{
				l.next();
				l.expect(Token::Null);
				ret = cast(uint32_t)TypeMask::NotNull;
			}
			else if(l.type() == Token::Ident && strcmp(l.tok().stringValue, "any") == 0)
			{
				l.next();
				ret = cast(uint32_t)TypeMask::Any;
			}
			else
			{
				while(true)
				{
					parseSingleType();

					if(l.type() == Token::Or)
						l.next();
					else
						break;
				}
			}

			assert(ret != 0);
			classTypes = objTypes.toArray();
		});

		return ret;
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

	ClassDecl* Parser::parseClassDecl(Decorator* deco)
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

		l.expect(Token::Class);

		auto className = parseIdentifier();

		List<Expression*> baseClasses(c);

		if(l.type() == Token::Colon)
		{
			l.next();

			Expression* baseClass = nullptr;
			auto sourceStr = capture([&]{baseClass = parseExpression();});
			baseClass->sourceStr = sourceStr;
			baseClasses.add(baseClass);

			while(l.type() == Token::Comma)
			{
				l.next();
				sourceStr = capture([&]{baseClass = parseExpression();});
				baseClass->sourceStr = sourceStr;
				baseClasses.add(baseClass);
			}
		}

		l.expect(Token::LBrace);

		auto oldClassName = mCurrentClassName;
		mCurrentClassName = className->name;

		List<ClassField> fields(c);

		auto addField = [&](Decorator* deco, Identifier* name, Expression* v, FuncLiteralExp* func, bool isOverride,
			const char* preDocs, CompileLoc preDocsLoc)
		{
			if(deco != nullptr)
				v = decoToExp(deco, v);

			fields.add(ClassField(checkPrivateFieldName(name->name), v, func, isOverride));
			attachDocs(fields.last(), preDocs, preDocsLoc);
		};

		auto addMethod = [&](Decorator* deco, FuncDef* m, bool isOverride, const char* preDocs, CompileLoc preDocsLoc)
		{
			auto func = new(c) FuncLiteralExp(m->location, m);
			addField(deco, m->name, func, func, isOverride, preDocs, preDocsLoc);
			m->docs = fields.last().docs;
			m->docsLoc = fields.last().docsLoc;
		};

		while(l.type() != Token::RBrace)
		{
			auto docs = l.tok().preComment;
			auto docsLoc = l.tok().preCommentLoc;
			bool isOverride = false;
			Decorator* memberDeco = nullptr;

			if(l.type() == Token::At)
				memberDeco = parseDecorators();

			if(l.type() == Token::Override)
			{
				l.next();
				isOverride = true;
			}

			switch(l.type())
			{
				case Token::Function:
					addMethod(memberDeco, parseSimpleFuncDef(), isOverride, docs, docsLoc);
					break;

				case Token::This: {
					auto loc = l.expect(Token::This).loc;
					addMethod(memberDeco, parseFuncBody(loc, new(c) Identifier(loc, c.newString("constructor"))),
						isOverride, docs, docsLoc);
					break;
				}
				case Token::Ident: {
					auto id = parseIdentifier();

					Expression* v = nullptr;

					if(l.type() == Token::Assign)
					{
						l.next();
						auto sourceStr = capture([&]{v = parseExpression();});
						v->sourceStr = sourceStr;
					}
					else
						v = new(c) NullExp(id->location);

					l.statementTerm();
					addField(memberDeco, id, v, nullptr, isOverride, docs, docsLoc);
					break;
				}
				case Token::EOF_:
					c.eofException(location, "Class is missing its closing brace");

				default:
					l.expected("Class method or field");
			}
		}

		mCurrentClassName = oldClassName;
		auto endLocation = l.expect(Token::RBrace).loc;
		return new(c) ClassDecl(location, endLocation, protection, deco, className, baseClasses.toArray(),
			fields.toArray());
	}

	NamespaceDecl* Parser::parseNamespaceDecl(Decorator* deco)
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

		l.expect(Token::Namespace);

		auto name = parseIdentifier();
		Expression* parent = nullptr;

		if(l.type() == Token::Colon)
		{
			l.next();
			auto sourceStr = capture([&]{parent = parseExpression();});
			parent->sourceStr = sourceStr;
		}

		l.expect(Token::LBrace);

		auto t = *c.thread();

		auto fieldMap = croc_table_new(t, 8);
		List<NamespaceField> fields(c);

		auto addField = [&](Decorator* deco, Identifier* name, Expression* v, FuncLiteralExp* func, const char* preDocs,
			CompileLoc preDocsLoc)
		{
			croc_pushString(t, name->name);

			if(croc_in(t, -1, fieldMap))
			{
				croc_popTop(t);
				c.semException(v->location, "Redeclaration of member '%s'", name->name);
			}

			croc_pushBool(t, true);
			croc_idxa(t, fieldMap);

			if(deco != nullptr)
				v = decoToExp(deco, v);

			fields.add(NamespaceField(name->name, v, func));
			attachDocs(fields.last(), preDocs, preDocsLoc);
		};

		auto addMethod = [&](Decorator* deco, FuncDef* m, const char* preDocs, CompileLoc preDocsLoc)
		{
			auto func = new(c) FuncLiteralExp(m->location, m);
			addField(deco, m->name, func, func, preDocs, preDocsLoc);
			m->docs = fields.last().docs;
			m->docsLoc = fields.last().docsLoc;
		};

		while(l.type() != Token::RBrace)
		{
			auto docs = l.tok().preComment;
			auto docsLoc = l.tok().preCommentLoc;
			Decorator* memberDeco = nullptr;

			if(l.type() == Token::At)
				memberDeco = parseDecorators();

			switch(l.type())
			{
				case Token::Function:
					addMethod(memberDeco, parseSimpleFuncDef(), docs, docsLoc);
					break;

				case Token::Ident: {
					auto id = parseIdentifier();

					Expression* v = nullptr;

					if(l.type() == Token::Assign)
					{
						l.next();
						auto sourceStr = capture([&]{v = parseExpression();});
						v->sourceStr = sourceStr;
					}
					else
						v = new(c) NullExp(id->location);

					l.statementTerm();
					addField(memberDeco, id, v, nullptr, docs, docsLoc);
					break;
				}
				case Token::EOF_:
					c.eofException(location, "Namespace is missing its closing brace");

				default:
					l.expected("Namespace member");
			}
		}

		croc_popTop(t);
		auto endLocation = l.expect(Token::RBrace).loc;
		return new(c) NamespaceDecl(location, endLocation, protection, deco, name, parent, fields.toArray());
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

	AssertStmt* Parser::parseAssertStmt()
	{
		auto location = l.expect(Token::Assert).loc;
		l.expect(Token::LParen);

		auto cond = parseExpression();
		Expression* msg = nullptr;

		if(l.type() == Token::Comma)
		{
			l.next();
			msg = parseExpression();
		}

		auto endLocation = l.expect(Token::RParen).loc;
		l.statementTerm();

		return new(c) AssertStmt(location, endLocation, cond, msg);
	}

	BreakStmt* Parser::parseBreakStmt()
	{
		auto location = l.expect(Token::Break).loc;
		const char* name = nullptr;

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
		const char* name = nullptr;

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

		const char* name = nullptr;

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
		const char* name = nullptr;

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
		else if(l.type() == Token::Ident && (l.peek().type == Token::Colon || l.peek().type == Token::Semicolon))
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
		const char* name = nullptr;

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

		Expression* expr = nullptr;
		Identifier* importName = nullptr;

		if(l.type() == Token::LParen)
		{
			l.next();
			expr = parseExpression();
			l.expect(Token::RParen);
		}
		else
		{
			List<char, 32> name(c);

			name.add(atoda(parseName()));

			while(l.type() == Token::Dot)
			{
				l.next();
				name.add('.');
				name.add(atoda(parseName()));
			}

			expr = new(c) StringExp(location, c.newString(name.toArrayView().toConst()));
		}

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

	SwitchStmt* Parser::parseSwitchStmt()
	{
		auto location = l.expect(Token::Switch).loc;
		const char* name = nullptr;

		if(l.type() == Token::Ident)
		{
			name = l.tok().stringValue;
			l.next();
		}

		l.expect(Token::LParen);

		auto condition = parseExpression();

		l.expect(Token::RParen);
		l.expect(Token::LBrace);

		List<CaseStmt*> cases(c);

		cases.add(parseCaseStmt());

		while(l.type() == Token::Case)
			cases.add(parseCaseStmt());

		DefaultStmt* caseDefault = nullptr;

		if(l.type() == Token::Default)
			caseDefault = parseDefaultStmt();

		auto endLocation = l.expect(Token::RBrace).loc;
		return new(c) SwitchStmt(location, endLocation, name, condition, cases.toArray(), caseDefault);
	}

	CaseStmt* Parser::parseCaseStmt()
	{
		auto location = l.expect(Token::Case).loc;

		List<CaseCond> conditions(c);
		conditions.add(CaseCond(parseExpression()));
		Expression* highRange = nullptr;

		if(l.type() == Token::DotDot)
		{
			l.next();
			highRange = parseExpression();
		}
		else while(l.type() == Token::Comma)
		{
			l.next();
			conditions.add(CaseCond(parseExpression()));
		}

		l.expect(Token::Colon);

		List<Statement*> statements(c);

		while(l.type() != Token::Case && l.type() != Token::Default && l.type() != Token::RBrace)
			statements.add(parseStatement());

		auto endLocation = l.loc();

		auto code = new(c) ScopeStmt(new(c) BlockStmt(location, endLocation, statements.toArray()));
		return new(c) CaseStmt(location, endLocation, conditions.toArray(), highRange, code);
	}

	DefaultStmt* Parser::parseDefaultStmt()
	{
		auto location = l.loc();

		l.expect(Token::Default);
		l.expect(Token::Colon);

		List<Statement*> statements(c);

		while(l.type() != Token::RBrace)
			statements.add(parseStatement());

		auto endLocation = l.loc();

		auto code = new(c) ScopeStmt(new(c) BlockStmt(location, endLocation, statements.toArray()));
		return new(c) DefaultStmt(location, endLocation, code);
	}

	ThrowStmt* Parser::parseThrowStmt()
	{
		auto location = l.expect(Token::Throw).loc;
		auto exp = parseExpression();
		l.statementTerm();
		return new(c) ThrowStmt(location, exp);
	}

	ScopeActionStmt* Parser::parseScopeActionStmt()
	{
		auto location = l.expect(Token::Scope).loc;
		l.expect(Token::LParen);
		auto id = l.expect(Token::Ident);

		ScopeAction type;

		if(strcmp(id.stringValue, "exit") == 0)
			type = ScopeAction::Exit;
		else if(strcmp(id.stringValue, "success") == 0)
			type = ScopeAction::Success;
		else if(strcmp(id.stringValue, "failure") == 0)
			type = ScopeAction::Failure;
		else
			c.synException(location, "Expected one of 'exit', 'success', or 'failure' for scope statement, not '%s'",
				id.stringValue);

		l.expect(Token::RParen);
		auto stmt = parseStatement();

		return new(c) ScopeActionStmt(location, type, stmt);
	}

	Statement* Parser::parseTryStmt()
	{
		auto location = l.expect(Token::Try).loc;
		auto tryBody = new(c) ScopeStmt(parseStatement());

		List<CatchClause> catches(c);

		bool hadCatchall = false;


		while(l.type() == Token::Catch)
		{
			if(hadCatchall)
				c.synException(l.loc(), "Cannot have a catch clause after a catchall clause");

			l.next();
			l.expect(Token::LParen);

			CatchClause cc;
			cc.catchVar = parseIdentifier();

			List<Expression*> types(c);

			if(l.type() == Token::Colon)
			{
				l.next();

				types.add(parseDottedName());

				while(l.type() == Token::Or)
				{
					l.next();
					types.add(parseDottedName());
				}
			}
			else
				hadCatchall = true;

			l.expect(Token::RParen);

			cc.catchBody = new(c) ScopeStmt(parseStatement());
			cc.exTypes = types.toArray();
			catches.add(cc);
		}

		Statement* finallyBody = nullptr;

		if(l.type() == Token::Finally)
		{
			l.next();
			finallyBody = new(c) ScopeStmt(parseStatement());
		}

		if(catches.length() > 0)
		{
			auto catchArr = catches.toArray();

			if(finallyBody)
			{
				auto tmp = new(c) TryCatchStmt(location, catchArr[catchArr.length - 1].catchBody->endLocation, tryBody,
					catchArr);
				return new(c) TryFinallyStmt(location, finallyBody->endLocation, tmp, finallyBody);
			}
			else
			{
				return new(c) TryCatchStmt(location, catchArr[catchArr.length - 1].catchBody->endLocation, tryBody,
					catchArr);
			}
		}
		else if(finallyBody)
			return new(c) TryFinallyStmt(location, finallyBody->endLocation, tryBody, finallyBody);
		else
			c.eofException(location, "Try statement must be followed by catches, finally, or both");

		assert(false);
	}

	WhileStmt* Parser::parseWhileStmt()
	{
		auto location = l.expect(Token::While).loc;
		const char* name = nullptr;

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
			default: assert(false);
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

			case Token::Not:
				if(l.peek().type == Token::Is)
				{
					l.next();
					l.next();
					exp2 = parseShiftExp();
					exp1 = new(c) NotIsExp(location, exp2->endLocation, exp1, exp2);
				}
				else if(l.peek().type == Token::In)
				{
					l.next();
					l.next();
					exp2 = parseShiftExp();
					exp1 = new(c) NotInExp(location, exp2->endLocation, exp1, exp2);
				}
				// no, there should not be an 'else' here

				break;

			case Token::NotKeyword:
				if(l.peek().type == Token::In)
				{
					l.next();
					l.next();
					exp2 = parseShiftExp();
					exp1 = new(c) NotInExp(location, exp2->endLocation, exp1, exp2);
				}
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

			case Token::In:
				l.next();
				exp2 = parseShiftExp();
				exp1 = new(c) InExp(location, exp2->endLocation, exp1, exp2);
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
				l.expected("Expression*");
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

			bool firstWasBracketed = l.type() == Token::LBracket;
			parseField();

			if(firstWasBracketed && (l.type() == Token::For || l.type() == Token::Foreach))
			{
				auto forComp = parseForComprehension();
				auto endLocation = l.expect(Token::RBrace).loc;

				auto dummy = fields.toArray();
				auto key = dummy[0].key;
				auto value = dummy[0].value;

				return new(c) TableComprehension(location, endLocation, key, value, forComp);
			}

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

			if(l.type() == Token::For || l.type() == Token::Foreach)
			{
				auto forComp = parseForComprehension();
				auto endLocation = l.expect(Token::RBracket).loc;
				return new(c) ArrayComprehension(location, endLocation, exp, forComp);
			}
			else
			{
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
		else if(l.type() == Token::Super)
		{
			endLoc = l.loc();
			l.next();
			return new(c) DotSuperExp(endLoc, new(c) ThisExp(loc));
		}
		else
		{
			endLoc = l.loc();
			auto name = checkPrivateFieldName(parseName());
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
						auto name = checkPrivateFieldName(parseName());
						exp = new(c) DotExp(exp, new(c) StringExp(loc, name));
					}
					else if(l.type() == Token::Super)
					{
						auto endLocation = l.loc();
						l.next();
						exp = new(c) DotSuperExp(endLocation, exp);
					}
					else
					{
						l.expect(Token::LParen);
						auto subExp = parseExpression();
						l.expect(Token::RParen);
						exp = new(c) DotExp(exp, subExp);
					}
					continue;

				case Token::Dollar: {
					l.next();

					List<Expression*> args(c);
					args.add(parseExpression());

					while(l.type() == Token::Comma)
					{
						l.next();
						args.add(parseExpression());
					}

					auto arr = args.toArray();

					if(auto dot = AST_AS(DotExp, exp))
						exp = new(c) MethodCallExp(dot->location, arr[arr.length - 1]->endLocation, dot->op, dot->name,
							arr);
					else
						exp = new(c) CallExp(arr[arr.length - 1]->endLocation, exp, nullptr, arr);
					continue;
				}
				case Token::LParen: {
					if(exp->endLocation.line != l.loc().line)
						return exp;

					l.next();

					Expression* context = nullptr;
					auto args = DArray<Expression*>();

					if(l.type() == Token::With)
					{
						if(exp->type == AstTag_DotExp)
							c.semException(l.loc(), "'with' is disallowed for method calls; if you aren't making an "
								"actual method call, put the function in parentheses");

						l.next();

						context = parseExpression();

						if(l.type() == Token::Comma)
						{
							l.next();
							args = parseArguments();
						}
					}
					else if(l.type() != Token::RParen)
						args = parseArguments();

					auto endLocation = l.expect(Token::RParen).loc;

					if(auto dot = AST_AS(DotExp, exp))
						exp = new(c) MethodCallExp(dot->location, endLocation, dot->op, dot->name, args);
					else
						exp = new(c) CallExp(endLocation, exp, context, args);
					continue;
				}
				case Token::LBracket: {
					l.next();

					Expression* loIndex = nullptr;
					Expression* hiIndex = nullptr;
					CompileLoc endLocation;

					if(l.type() == Token::RBracket)
					{
						// a[]
						loIndex = new(c) NullExp(l.loc());
						hiIndex = new(c) NullExp(l.loc());
						endLocation = l.expect(Token::RBracket).loc;
					}
					else if(l.type() == Token::DotDot)
					{
						loIndex = new(c) NullExp(l.loc());
						l.next();

						if(l.type() == Token::RBracket)
						{
							// a[ .. ]
							hiIndex = new(c) NullExp(l.loc());
							endLocation = l.expect(Token::RBracket).loc;
						}
						else
						{
							// a[ .. 0]
							hiIndex = parseExpression();
							endLocation = l.expect(Token::RBracket).loc;
						}
					}
					else
					{
						loIndex = parseExpression();

						if(l.type() == Token::DotDot)
						{
							l.next();

							if(l.type() == Token::RBracket)
							{
								// a[0 .. ]
								hiIndex = new(c) NullExp(l.loc());
								endLocation = l.expect(Token::RBracket).loc;
							}
							else
							{
								// a[0 .. 0]
								hiIndex = parseExpression();
								endLocation = l.expect(Token::RBracket).loc;
							}
						}
						else
						{
							// a[0]
							endLocation = l.expect(Token::RBracket).loc;

							if(exp->type == AstTag_VarargExp)
								exp = new(c) VargIndexExp(location, endLocation, loIndex);
							else
								exp = new(c) IndexExp(endLocation, exp, loIndex);

							// continue here since this isn't a slice
							continue;
						}
					}

					if(exp->type == AstTag_VarargExp)
						exp = new(c) VargSliceExp(location, endLocation, loIndex, hiIndex);
					else
						exp = new(c) SliceExp(endLocation, exp, loIndex, hiIndex);
					continue;
				}
				default:
					return exp;
			}
		}
	}

	ForComprehension* Parser::parseForComprehension()
	{
		auto loc = l.loc();
		IfComprehension* ifComp = nullptr;
		ForComprehension* forComp = nullptr;

		auto parseNextComp = [&]()
		{
			if(l.type() == Token::If)
				ifComp = parseIfComprehension();

			if(l.type() == Token::For || l.type() == Token::Foreach)
				forComp = parseForComprehension();
		};

		if(l.type() == Token::For)
		{
			l.next();
			auto name = parseIdentifier();

			if(l.type() != Token::Colon && l.type() != Token::Semicolon)
				l.expected(": or ;");

			l.next();

			auto exp = parseExpression();
			l.expect(Token::DotDot);
			auto exp2 = parseExpression();

			Expression* step = nullptr;

			if(l.type() == Token::Comma)
			{
				l.next();
				step = parseExpression();
			}
			else
				step = new(c) IntExp(l.loc(), 1);

			parseNextComp();
			return new(c) ForNumComprehension(loc, name, exp, exp2, step, ifComp, forComp);
		}
		else if(l.type() == Token::Foreach)
		{
			l.next();
			List<Identifier*> names(c);
			names.add(parseIdentifier());

			while(l.type() == Token::Comma)
			{
				l.next();
				names.add(parseIdentifier());
			}

			l.expect(Token::Semicolon);

			List<Expression*> container(c);
			container.add(parseExpression());

			while(l.type() == Token::Comma)
			{
				l.next();
				container.add(parseExpression());
			}

			if(container.length() > 3)
				c.synException(container[0]->location, "Too many expressions in container");

			auto namesArr = DArray<Identifier*>();

			if(names.length() == 1)
			{
				names.add(cast(Identifier*)nullptr);
				namesArr = names.toArray();

				for(uword i = namesArr.length - 1; i > 0; i--)
					namesArr[i] = namesArr[i - 1];

				namesArr[0] = dummyForeachIndex(namesArr[1]->location);
			}
			else
				namesArr = names.toArray();

			parseNextComp();
			return new(c) ForeachComprehension(loc, namesArr, container.toArray(), ifComp, forComp);

		}
		else
			l.expected("for or foreach");

		assert(false);
	}

	IfComprehension* Parser::parseIfComprehension()
	{
		auto loc = l.expect(Token::If).loc;
		auto condition = parseExpression();
		return new(c) IfComprehension(loc, condition);
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
		auto t = *c.thread();
		croc_pushFormat(t, CROC_INTERNAL_NAME("dummy%u"), mDummyNameCounter++);
		auto str = c.newString(croc_getString(t, -1));
		croc_popTop(t);
		return new(c) Identifier(loc, str);
	}

	Identifier* Parser::dummyFuncLiteralName(CompileLoc loc)
	{
		auto t = *c.thread();
		croc_pushFormat(t, "<literal at %*s(%u:%u)>", loc.file.length, loc.file.ptr, loc.line, loc.col);
		auto str = c.newString(croc_getString(t, -1));
		croc_popTop(t);
		return new(c) Identifier(loc, str);
	}

	bool Parser::isPrivateFieldName(const char* name)
	{
		return strlen(name) >= 2 && name[0] == '_' && name[1] == '_';
	}

	const char* Parser::checkPrivateFieldName(const char* fieldName)
	{
		if(mCurrentClassName != nullptr && isPrivateFieldName(fieldName))
		{
			auto t = *c.thread();
			croc_pushString(t, mCurrentClassName);
			croc_pushString(t, fieldName);
			croc_cat(t, 2);
			auto ret = c.newString(croc_getString(t, -1));
			croc_popTop(t);
			return ret;
		}
		else
			return fieldName;
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

		if(auto f = AST_AS(DotExp, dec->func))
		{
			if(dec->context != nullptr)
				c.semException(dec->location, "'with' is disallowed for method calls");

			return new(c) MethodCallExp(dec->location, dec->endLocation, f->op, f->name, argsArray);
		}
		else
			return new(c) CallExp(dec->endLocation, dec->func, dec->context, argsArray);
	}
}