/******************************************************************************
This module contains the parser part of the compiler. This uses a lexer to
get a stream of tokens, and parses the tokens into an AST.

License:
Copyright (c) 2008 Jarrett Billingsley

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

module croc.compiler_parser;

import croc.api_interpreter;
import croc.api_stack;
import croc.compiler_ast;
import croc.compiler_lexer;
import croc.compiler_types;
import croc.types;

struct Parser
{
private:
	ICompiler c;
	Lexer* l;
	bool mDanglingDoc = false;
	uword mDummyNameCounter = 0;
	char[] mCurrentClassName = null;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

public:

	/**
	*/
	static Parser opCall(ICompiler compiler, Lexer* lexer)
	{
		Parser ret;
		ret.c = compiler;
		ret.l = lexer;
		return ret;
	}

	/**
	*/
	bool danglingDoc()
	{
		return mDanglingDoc;
	}

	/**
	*/
	char[] capture(void delegate() dg)
	{
		if(c.docComments)
		{
			auto start = l.beginCapture();
			dg();
			return l.endCapture(start);
		}
		else
		{
			dg();
			return null;
		}
	}

	/**
	*/
	char[] parseName()
	{
		with(l.expect(Token.Ident))
			return stringValue;
	}

	/**
	*/
	Expression parseDottedName()
	{
		Expression ret = parseIdentExp();

		while(l.type == Token.Dot)
		{
			l.next();
			auto tok = l.expect(Token.Ident);
			ret = new(c) DotExp(c, ret, new(c) StringExp(c, tok.loc, tok.stringValue));
		}

		return ret;
	}

	/**
	*/
	Identifier parseIdentifier()
	{
		with(l.expect(Token.Ident))
			return new(c) Identifier(c, loc, stringValue);
	}

	/**
	Parse a comma-separated list of expressions, such as for argument lists.
	*/
	Expression[] parseArguments()
	{
		scope args = new List!(Expression)(c.alloc);
		args ~= parseExpression();

		while(l.type == Token.Comma)
		{
			l.next();
			args ~= parseExpression();
		}

		return args.toArray();
	}

	/**
	Parse a module.
	*/
	Module parseModule()
	{
		auto location = l.loc;
		auto docs = l.tok.preComment;
		auto docsLoc = l.tok.preCommentLoc;
		Decorator dec;

		if(l.type == Token.At)
			dec = parseDecorators();

		l.expect(Token.Module);

		scope names = new List!(char[])(c.alloc);
		names ~= parseName();

		while(l.type == Token.Dot)
		{
			l.next();
			names ~= parseName();
		}

		auto endLocation = l.loc;
		l.statementTerm();

		scope statements = new List!(Statement)(c.alloc);

		while(l.type != Token.EOF)
			statements ~= parseStatement();

		auto stmts = new(c) BlockStmt(c, location, l.loc, statements.toArray());

		mDanglingDoc = l.expect(Token.EOF).preComment !is null;
		auto ret = new(c) Module(c, location, l.loc, names.toArray(), stmts, dec);

		// Prevent final docs from being erroneously attached to the module
		l.tok.postComment = null;
		attachDocs(ret, docs, docsLoc);
		return ret;
	}

	/**
	Parse a list of statements into a function definition that takes a variadic number of arguments.

	Params:
		name = The name to use for error messages and debug locations.
	*/
	FuncDef parseStatements(char[] name)
	{
		auto location = l.loc;

		scope statements = new List!(Statement)(c.alloc);

		while(l.type != Token.EOF)
			statements ~= parseStatement();

		mDanglingDoc = l.expect(Token.EOF).preComment !is null;

		auto endLocation = statements.length > 0 ? statements[statements.length - 1].endLocation : location;
		auto code = new(c) BlockStmt(c, location, endLocation, statements.toArray());
		scope params = new List!(FuncDef.Param)(c.alloc);
		params ~= FuncDef.Param(new(c) Identifier(c, l.loc, c.newString("this")));
		return new(c) FuncDef(c, location, new(c) Identifier(c, location, c.newString(name)), params.toArray(), true, code);
	}

	/**
	Parse an expression into a function definition that takes a variadic number of arguments and returns the value
	of the expression when called.

	Params:
		name = The name to use for error messages and debug locations.
	*/
	FuncDef parseExpressionFunc(char[] name)
	{
		auto location = l.loc;

		scope statements = new List!(Statement)(c.alloc);
		scope exprs = new List!(Expression)(c.alloc);
		exprs ~= parseExpression();

		if(l.type != Token.EOF)
			c.synException(l.loc, "Extra unexpected code after expression");

		statements ~= new(c) ReturnStmt(c, exprs[0].location, exprs[0].endLocation, exprs.toArray());
		auto code = new(c) BlockStmt(c, location, statements[0].endLocation, statements.toArray());
		scope params = new List!(FuncDef.Param)(c.alloc);
		params ~= FuncDef.Param(new(c) Identifier(c, l.loc, c.newString("this")));
		return new(c) FuncDef(c, location, new(c) Identifier(c, location, c.newString(name)), params.toArray(), true, code);
	}

	/**
	Parse a statement.

	Params:
		needScope = If true, and the statement is a block statement, the block will be wrapped
			in a ScopeStmt. Else, the raw block statement will be returned.
	*/
	Statement parseStatement(bool needScope = true)
	{
		switch(l.type)
		{
			case
				Token.CharLiteral,
				Token.Colon,
				Token.Dec,
				Token.False,
				Token.FloatLiteral,
				Token.Ident,
				Token.Inc,
				Token.IntLiteral,
				Token.LBracket,
				Token.Length,
				Token.LParen,
				Token.Null,
				Token.Or,
				Token.StringLiteral,
				Token.Super,
				Token.This,
				Token.True,
				Token.Vararg,
				Token.Yield:

				return parseExpressionStmt();

			case
				Token.Class,
				Token.Function,
				Token.Global,
				Token.Local,
				Token.Namespace,
				Token.At:

				return parseDeclStmt();

			case Token.LBrace:
				if(needScope)
				{
					// don't inline this; memory management stuff.
					auto stmt = parseBlockStmt();
					return new(c) ScopeStmt(c, stmt);
				}
				else
					return parseBlockStmt();

			case Token.Assert:   return parseAssertStmt();
			case Token.Break:    return parseBreakStmt();
			case Token.Continue: return parseContinueStmt();
			case Token.Do:       return parseDoWhileStmt();
			case Token.For:      return parseForStmt();
			case Token.Foreach:  return parseForeachStmt();
			case Token.If:       return parseIfStmt();
			case Token.Import:   return parseImportStmt();
			case Token.Return:   return parseReturnStmt();
			case Token.Scope:    return parseScopeActionStmt();
			case Token.Switch:   return parseSwitchStmt();
			case Token.Throw:    return parseThrowStmt();
			case Token.Try:      return parseTryStmt();
			case Token.While:    return parseWhileStmt();

			case Token.Semicolon:
				c.synException(l.loc, "Empty statements ( ';' ) are not allowed (use {{} for an empty statement)");

			default:
				l.expected("statement");
		}

		assert(false);
	}

	/**
	*/
	Statement parseExpressionStmt()
	{
		auto stmt = parseStatementExpr();
		l.statementTerm();
		return stmt;
	}

	/**
	*/
	Decorator parseDecorators()
	{
		Decorator parseDecorator()
		{
			l.expect(Token.At);

			auto func = parseDottedName();
			Expression[] argsArr;
			Expression context;
			CompileLoc endLocation = void;

			if(l.type == Token.Dollar)
			{
				l.next();

				scope args = new List!(Expression)(c.alloc);
				args ~= parseExpression();

				while(l.type == Token.Comma)
				{
					l.next();
					args ~= parseExpression();
				}

				argsArr = args.toArray();
			}
			else if(l.type == Token.LParen)
			{
				l.next();

				if(l.type == Token.With)
				{
					l.next();

					context = parseExpression();

					if(l.type == Token.Comma)
					{
						l.next();
						argsArr = parseArguments();
					}
				}
				else if(l.type != Token.RParen)
					argsArr = parseArguments();

				scope(failure)
					c.alloc.freeArray(argsArr);

				endLocation = l.expect(Token.RParen).loc;
			}
			else
				endLocation = func.endLocation;

			return new(c) Decorator(c, func.location, endLocation, func, context, argsArr, null);
		}

		auto first = parseDecorator();
		auto cur = first;

		while(l.type == Token.At)
		{
			cur.nextDec = parseDecorator();
			cur = cur.nextDec;
		}

		return first;
	}

	/**
	*/
	Statement parseDeclStmt()
	{
		Decorator deco;

		auto docs = l.tok.preComment;
		auto docsLoc = l.tok.preCommentLoc;

		if(l.type == Token.At)
			deco = parseDecorators();

		switch(l.type)
		{
			case Token.Local, Token.Global:
				switch(l.peek.type)
				{
					case Token.Ident:
						if(deco !is null)
							c.synException(l.loc, "Cannot put decorators on variable declarations");

						auto ret = parseVarDecl();
						l.statementTerm();
						attachDocs(ret, docs, docsLoc);
						return ret;

					case Token.Function:  auto ret = parseFuncDecl(deco); attachDocs(ret.def, docs, docsLoc); return ret;
					case Token.Class:     auto ret = parseClassDecl(deco); attachDocs(ret.def, docs, docsLoc); return ret;
					case Token.Namespace: auto ret = parseNamespaceDecl(deco); attachDocs(ret.def, docs, docsLoc); return ret;

					default:
						c.synException(l.loc, "Illegal token '{}' after '{}'", l.peek.typeString(), l.tok.typeString());
				}

			case Token.Function:  auto ret = parseFuncDecl(deco); attachDocs(ret.def, docs, docsLoc); return ret;
			case Token.Class:     auto ret = parseClassDecl(deco); attachDocs(ret.def, docs, docsLoc); return ret;
			case Token.Namespace: auto ret = parseNamespaceDecl(deco); attachDocs(ret.def, docs, docsLoc); return ret;

			default:
				l.expected("Declaration");
		}

		assert(false);
	}

	/**
	Parse a local or global variable declaration.
	*/
	VarDecl parseVarDecl()
	{
		auto location = l.loc;
		auto protection = Protection.Local;

		if(l.type == Token.Global)
		{
			protection = Protection.Global;
			l.next();
		}
		else
			l.expect(Token.Local);

		scope names = new List!(Identifier)(c.alloc);
		names ~= parseIdentifier();

		while(l.type == Token.Comma)
		{
			l.next();
			names ~= parseIdentifier();
		}

		auto namesArr = names.toArray();
		auto endLocation = namesArr[$ - 1].location;

		scope(failure)
			c.alloc.freeArray(namesArr);

		Expression[] initializer;

		if(l.type == Token.Assign)
		{
			l.next();
			scope exprs = new List!(Expression)(c.alloc);

			auto str = capture({exprs ~= parseExpression();});

			if(c.docComments)
				exprs[exprs.length - 1].sourceStr = str;

			while(l.type == Token.Comma)
			{
				l.next();

				auto valstr = capture({exprs ~= parseExpression();});

				if(c.docComments)
					exprs[exprs.length - 1].sourceStr = valstr;
			}

			if(namesArr.length < exprs.length)
				c.semException(location, "Declaration has fewer variables than sources");

			initializer = exprs.toArray();
			endLocation = initializer[$ - 1].endLocation;
		}

		return new(c) VarDecl(c, location, endLocation, protection, namesArr, initializer);
	}

	/**
	Parse a function declaration, optional protection included.
	*/
	FuncDecl parseFuncDecl(Decorator deco)
	{
		auto location = l.loc;
		auto protection = Protection.Default;

		if(l.type == Token.Global)
		{
			protection = Protection.Global;
			l.next();
		}
		else if(l.type == Token.Local)
		{
			protection = Protection.Local;
			l.next();
		}

		auto def = parseSimpleFuncDef();
		return new(c) FuncDecl(c, location, protection, def, deco);
	}

	/**
	Parse everything starting from the left-paren of the parameter list to the end of the body.

	Params:
		location = Where the function actually started.
		name = The name of the function. Must be non-null.

	Returns:
		The completed function definition.
	*/
	FuncDef parseFuncBody(CompileLoc location, Identifier name)
	{
		l.expect(Token.LParen);
		bool isVararg;
		auto params = parseFuncParams(isVararg);

		scope(failure)
			c.alloc.freeArray(params);

		l.expect(Token.RParen);

		Statement code;

		if(l.type == Token.Assign)
		{
			l.next;

			scope dummy = new List!(Expression)(c.alloc);
			dummy ~= parseExpression();
			auto arr = dummy.toArray();

			code = new(c) ReturnStmt(c, arr[0].location, arr[0].endLocation, arr);
		}
		else
		{
			code = parseStatement();

			if(!code.as!(BlockStmt))
			{
				scope dummy = new List!(Statement)(c.alloc);
				dummy ~= code;
				auto arr = dummy.toArray();
				code = new(c) BlockStmt(c, code.location, code.endLocation, arr);
			}
		}

		return new(c) FuncDef(c, location, name, params, isVararg, code);
	}

	/**
	Parse a function parameter list, opening and closing parens included.

	Params:
		isVararg = Return value to indicate if the parameter list ended with 'vararg'.

	Returns:
		An array of Param structs.
	*/
	FuncDef.Param[] parseFuncParams(out bool isVararg)
	{
		alias FuncDef.Param Param;
		alias FuncDef.TypeMask TypeMask;
		scope ret = new List!(Param)(c.alloc);

		scope(failure)
			foreach(ref p; ret)
				c.alloc.freeArray(p.classTypes);

		void parseParam()
		{
			Param p;
			p.name = parseIdentifier();

			if(l.type == Token.Colon)
			{
				l.next();
				p.typeMask = parseParamType(p.classTypes, p.typeString, p.customConstraint);
			}

			if(l.type == Token.Assign)
			{
				l.next();
				p.valueString = capture({p.defValue = parseExpression();});

				// Having a default parameter implies allowing null as a parameter type
				p.typeMask |= TypeMask.Null;
			}

			ret ~= p;
		}

		void parseRestOfParams()
		{
			while(l.type == Token.Comma)
			{
				l.next();

				if(l.type == Token.Vararg)
				{
					isVararg = true;
					l.next();
					break;
				}

				parseParam();
			}
		}

		if(l.type == Token.This)
		{
			Param p;
			p.name = new(c) Identifier(c, l.loc, c.newString("this"));

			l.next();
			l.expect(Token.Colon);
			p.typeMask = parseParamType(p.classTypes, p.typeString, p.customConstraint);

			ret ~= p;

			if(l.type == Token.Comma)
				parseRestOfParams();
		}
		else
		{
			ret ~= Param(new(c) Identifier(c, l.loc, c.newString("this")));

			if(l.type == Token.Ident)
			{
				parseParam();
				parseRestOfParams();
			}
			else if(l.type == Token.Vararg)
			{
				isVararg = true;
				l.next();
			}
		}

		return ret.toArray();
	}

	/**
	Parse a parameter type. This corresponds to the Type element of the grammar.
	Returns the type mask, an optional list of class types that this parameter can accept in the classTypes parameter,
	a string representation of the type in typeString if documentation generation is enabled, and an optional custom
	constraint if this function parameter uses a custom constraint.
	*/
	uint parseParamType(out Expression[] classTypes, out char[] typeString, out Expression customConstraint)
	{
		alias FuncDef.TypeMask TypeMask;

		uint ret = 0;
		scope objTypes = new List!(Expression)(c.alloc);

		void addConstraint(CrocValue.Type t)
		{
			if((ret & (1 << cast(uint)t)) && t != CrocValue.Type.Instance)
				c.semException(l.loc, "Duplicate parameter type constraint for type '{}'", CrocValue.typeStrings[t]);

			ret |= 1 << cast(uint)t;
		}

		Expression parseIdentList(Token t)
		{
			l.next();
			auto t2 = l.expect(Token.Ident);
			auto exp = new(c) DotExp(c, new(c) IdentExp(c, new(c) Identifier(c, t.loc, t.stringValue)), new(c) StringExp(c, t2.loc, t2.stringValue));

			while(l.type == Token.Dot)
			{
				l.next();
				t2 = l.expect(Token.Ident);
				exp = new(c) DotExp(c, exp, new(c) StringExp(c, t2.loc, t2.stringValue));
			}

			return exp;
		}

		void parseSingleType()
		{
			switch(l.type)
			{
				case Token.Null:      addConstraint(CrocValue.Type.Null);      l.next(); break;
				case Token.Function:  addConstraint(CrocValue.Type.Function);  l.next(); break;
				case Token.Namespace: addConstraint(CrocValue.Type.Namespace); l.next(); break;
				case Token.Class:     addConstraint(CrocValue.Type.Class);     l.next(); break;

				default:
					auto t = l.expect(Token.Ident);

					if(l.type == Token.Dot)
					{
						addConstraint(CrocValue.Type.Instance);
						objTypes ~= parseIdentList(t);
					}
					else
					{
						switch(t.stringValue)
						{
							case "bool":      addConstraint(CrocValue.Type.Bool); break;
							case "int":       addConstraint(CrocValue.Type.Int); break;
							case "float":     addConstraint(CrocValue.Type.Float); break;
							case "char":      addConstraint(CrocValue.Type.Char); break;
							case "string":    addConstraint(CrocValue.Type.String); break;
							case "table":     addConstraint(CrocValue.Type.Table); break;
							case "array":     addConstraint(CrocValue.Type.Array); break;
							case "memblock":  addConstraint(CrocValue.Type.Memblock); break;
							case "thread":    addConstraint(CrocValue.Type.Thread); break;
							case "nativeobj": addConstraint(CrocValue.Type.NativeObj); break;
							case "weakref":   addConstraint(CrocValue.Type.WeakRef); break;
							case "funcdef":   addConstraint(CrocValue.Type.FuncDef); break;

							case "instance":
								addConstraint(CrocValue.Type.Instance);

								if(l.type == Token.LParen)
								{
									l.next();
									objTypes ~= parseExpression();
									l.expect(Token.RParen);
								}
								else if(l.type == Token.Ident)
								{
									auto tt = l.expect(Token.Ident);

									if(l.type == Token.Dot)
										objTypes ~= parseIdentList(tt);
									else
										objTypes ~= new(c) IdentExp(c, new(c) Identifier(c, tt.loc, tt.stringValue));
								}
								else if(l.type != Token.Or && l.type != Token.Comma && l.type != Token.RParen && l.type != Token.Arrow)
									l.expected("class type");

								break;

							default:
								addConstraint(CrocValue.Type.Instance);
								objTypes ~= new(c) IdentExp(c, new(c) Identifier(c, t.loc, t.stringValue));
								break;
						}
					}
					break;
			}
		}

		typeString = capture(
		{
			if(l.type == Token.At)
			{
				l.next();
				auto n = l.expect(Token.Ident);

				if(l.type == Token.Dot)
					customConstraint = parseIdentList(n);
				else
					customConstraint = new(c) IdentExp(c, new(c) Identifier(c, n.loc, n.stringValue));

				ret = TypeMask.Any;
			}
			else if(l.type == Token.Not)
			{
				l.next();
				l.expect(Token.Null);
				ret = TypeMask.NotNull;
			}
			else if(l.type == Token.Ident && l.tok.stringValue == "any")
			{
				l.next();
				ret = TypeMask.Any;
			}
			else
			{
				while(true)
				{
					parseSingleType();

					if(l.type == Token.Or)
						l.next;
					else
						break;
				}
			}

			assert(ret !is 0);
			classTypes = objTypes.toArray();
		});

		return ret;
	}

	/**
	Parse a simple function declaration. This is basically a function declaration without
	any preceding 'local' or 'global'. The function must have a name.
	*/
	FuncDef parseSimpleFuncDef()
	{
		auto location = l.expect(Token.Function).loc;
		auto name = parseIdentifier();
		return parseFuncBody(location, name);
	}

	/**
	Parse a function literal. The name is optional, and one will be autogenerated for the
	function if none exists.
	*/
	FuncDef parseFuncLiteral()
	{
		auto location = l.expect(Token.Function).loc;

		Identifier name;

		if(l.type == Token.Ident)
			name = parseIdentifier();
		else
			name = dummyFuncLiteralName(location);

		return parseFuncBody(location, name);
	}

	/**
	Parse a Haskell-style function literal, like "\f -> f + 1" or "\a, b { ... }".
	*/
	FuncDef parseHaskellFuncLiteral()
	{
		auto location = l.expect(Token.Backslash).loc;
		auto name = dummyFuncLiteralName(location);

		bool isVararg;
		auto params = parseFuncParams(isVararg);

		scope(failure)
			c.alloc.freeArray(params);

		Statement code;

		if(l.type == Token.Arrow)
		{
			l.next();

			scope dummy = new List!(Expression)(c.alloc);
			dummy ~= parseExpression();
			auto arr = dummy.toArray();

			code = new(c) ReturnStmt(c, arr[0].location, arr[0].endLocation, arr);
		}
		else
			code = parseBlockStmt();

		return new(c) FuncDef(c, location, name, params, isVararg, code);
	}

	/**
	Parse a class declaration, optional protection included.
	*/
	ClassDecl parseClassDecl(Decorator deco)
	{
		auto location = l.loc;
		auto protection = Protection.Default;

		if(l.type == Token.Global)
		{
			protection = Protection.Global;
			l.next();
		}
		else if(l.type == Token.Local)
		{
			protection = Protection.Local;
			l.next();
		}

		auto def = parseClassDef(false);
		return new(c) ClassDecl(c, location, protection, def, deco);
	}

	/**
	Parse a class definition.

	Params:
		nameOptional = If true, the name is optional (such as with class literal expressions).
			Otherwise, the name is required (such as with class declarations).

	Returns:
		An instance of ClassDef.
	*/
	ClassDef parseClassDef(bool nameOptional)
	{
		auto location = l.expect(Token.Class).loc;

		Identifier className;

		if(nameOptional)
		{
			if(l.type == Token.Ident)
				className = parseIdentifier();
			else
				className = dummyClassLiteralName(location);
		}
		else
			className = parseIdentifier();

		Expression baseClass = null;

		if(l.type == Token.Colon)
		{
			l.next();
			baseClass.sourceStr = capture({baseClass = parseExpression();});
		}

		l.expect(Token.LBrace);

		auto oldClassName = mCurrentClassName;
		mCurrentClassName = className.name;

		scope(exit)
			mCurrentClassName = oldClassName;

		alias ClassDef.Field Field;
		scope fields = new List!(Field)(c.alloc);

		void addField(Identifier name, Expression v, bool isMethod, char[] preDocs, CompileLoc preDocsLoc)
		{
			if(isPrivateFieldName(name.name))
				fields ~= Field(makePrivateFieldName(className.name, name.name), v, false, isMethod);
			else
				fields ~= Field(name.name, v, true, isMethod);

			// Stupid no ref returns and stupid compiler not diagnosing this.. stupid stupid
			auto tmp = fields[fields.length - 1];
			attachDocs(&tmp, preDocs, preDocsLoc);
			fields[fields.length - 1] = tmp;
		}

		void addMethod(FuncDef m, char[] preDocs, CompileLoc preDocsLoc)
		{
			addField(m.name, new(c) FuncLiteralExp(c, m.location, m), true, preDocs, preDocsLoc);
			m.docs = fields[fields.length - 1].docs;
			m.docsLoc = fields[fields.length - 1].docsLoc;
		}

		while(l.type != Token.RBrace)
		{
			auto docs = l.tok.preComment;
			auto docsLoc = l.tok.preCommentLoc;

			switch(l.type)
			{
				case Token.Function:
					addMethod(parseSimpleFuncDef(), docs, docsLoc);
					break;

				case Token.This:
					auto loc = l.expect(Token.This).loc;
					addMethod(parseFuncBody(loc, new(c) Identifier(c, loc, c.newString("constructor"))), docs, docsLoc);
					break;

				case Token.At:
					auto dec = parseDecorators();
					Identifier fieldName = void;
					Expression init = void;
					bool isMethod = false;

					if(l.type == Token.Function || l.type == Token.This)
					{
						isMethod = true;
						FuncDef fd = void;

						if(l.type == Token.Function)
							fd = parseSimpleFuncDef();
						else
						{
							auto loc = l.expect(Token.This).loc;
							fd = parseFuncBody(loc, new(c) Identifier(c, loc, c.newString("constructor")));
						}

						fieldName = fd.name;
						init = new(c) FuncLiteralExp(c, fd.location, fd);
					}
					else
					{
						fieldName = parseIdentifier();

						if(l.type == Token.Assign)
						{
							l.next();
							init.sourceStr = capture({init = parseExpression();});
						}
						else
							init = new(c) NullExp(c, fieldName.location);

						l.statementTerm();
					}

					addField(fieldName, decoToExp(dec, init), isMethod, docs, docsLoc);
					break;

				case Token.Ident:
					auto id = parseIdentifier();

					Expression v;

					if(l.type == Token.Assign)
					{
						l.next();
						v.sourceStr = capture({v = parseExpression();});
					}
					else
						v = new(c) NullExp(c, id.location);

					l.statementTerm();
					addField(id, v, false, docs, docsLoc);
					break;

				case Token.EOF:
					c.eofException(location, "Class is missing its closing brace");

				default:
					l.expected("Class method or field");
			}
		}

		auto endLocation = l.expect(Token.RBrace).loc;
		return new(c) ClassDef(c, location, endLocation, className, baseClass, fields.toArray());
	}

	/**
	Parse a namespace declaration, optional protection included.
	*/
	NamespaceDecl parseNamespaceDecl(Decorator deco)
	{
		auto location = l.loc;
		auto protection = Protection.Default;

		if(l.type == Token.Global)
		{
			protection = Protection.Global;
			l.next();
		}
		else if(l.type == Token.Local)
		{
			protection = Protection.Local;
			l.next();
		}

		auto def = parseNamespaceDef();
		return new(c) NamespaceDecl(c, location, protection, def, deco);
	}

	/**
	Parse a namespace. Both literals and declarations require a name.

	Returns:
		An instance of this class.
	*/
	NamespaceDef parseNamespaceDef()
	{
		auto location = l.loc;
		l.expect(Token.Namespace);

		auto name = parseIdentifier();
		Expression parent;

		if(l.type == Token.Colon)
		{
			l.next();
			parent.sourceStr = capture({parent = parseExpression();});
		}


		l.expect(Token.LBrace);

		auto fieldMap = newTable(c.thread);

		scope(exit)
			pop(c.thread);

		alias NamespaceDef.Field Field;
		scope fields = new List!(Field)(c.alloc);

		void addField(char[] name, Expression v, char[] preDocs, CompileLoc preDocsLoc)
		{
			pushString(c.thread, name);

			if(opin(c.thread, -1, fieldMap))
			{
				pop(c.thread);
				c.semException(v.location, "Redeclaration of member '{}'", name);
			}

			pushBool(c.thread, true);
			idxa(c.thread, fieldMap);
			fields ~= Field(name, v);

			// Stupid no ref returns and stupid compiler not diagnosing this.. stupid stupid
			auto tmp = fields[fields.length - 1];
			attachDocs(&tmp, preDocs, preDocsLoc);
			fields[fields.length - 1] = tmp;
		}

		while(l.type != Token.RBrace)
		{
			auto docs = l.tok.preComment;
			auto docsLoc = l.tok.preCommentLoc;

			switch(l.type)
			{
				case Token.Function:
					auto fd = parseSimpleFuncDef();
					addField(fd.name.name, new(c) FuncLiteralExp(c, fd.location, fd), docs, docsLoc);
					break;

				case Token.At:
					auto dec = parseDecorators();

					Identifier fieldName = void;
					Expression init = void;

					if(l.type == Token.Function)
					{
						auto fd = parseSimpleFuncDef();
						fieldName = fd.name;
						init = new(c) FuncLiteralExp(c, fd.location, fd);
					}
					else
					{
						fieldName = parseIdentifier();

						if(l.type == Token.Assign)
						{
							l.next();
							init.sourceStr = capture({init = parseExpression();});
						}
						else
							init = new(c) NullExp(c, fieldName.location);

						l.statementTerm();
					}

					addField(fieldName.name, decoToExp(dec, init), docs, docsLoc);
					break;


				case Token.Ident:
					auto loc = l.loc;
					auto fieldName = parseName();

					Expression v;

					if(l.type == Token.Assign)
					{
						l.next();
						v.sourceStr = capture({v = parseExpression();});
					}
					else
						v = new(c) NullExp(c, loc);

					l.statementTerm();
					addField(fieldName, v, docs, docsLoc);
					break;

				case Token.EOF:
					c.eofException(location, "Namespace is missing its closing brace");

				default:
					l.expected("Namespace member");
			}
		}


		auto endLocation = l.expect(Token.RBrace).loc;
		return new(c) NamespaceDef(c, location, endLocation, name, parent, fields.toArray());
	}

	/**
	*/
	BlockStmt parseBlockStmt()
	{
		auto location = l.expect(Token.LBrace).loc;

		scope statements = new List!(Statement)(c.alloc);

		while(l.type != Token.RBrace)
			statements ~= parseStatement();

		auto endLocation = l.expect(Token.RBrace).loc;
		return new(c) BlockStmt(c, location, endLocation, statements.toArray());
	}

	/**
	*/
	AssertStmt parseAssertStmt()
	{
		auto location = l.expect(Token.Assert).loc;
		l.expect(Token.LParen);

		auto cond = parseExpression();
		Expression msg;

		if(l.type == Token.Comma)
		{
			l.next();
			msg = parseExpression();
		}

		auto endLocation = l.expect(Token.RParen).loc;
		l.statementTerm();

		return new(c) AssertStmt(c, location, endLocation, cond, msg);
	}

	/**
	*/
	BreakStmt parseBreakStmt()
	{
		auto location = l.expect(Token.Break).loc;
		char[] name = null;

		if(!l.isStatementTerm() && l.type == Token.Ident)
		{
			name = l.tok.stringValue;
			l.next();
		}

		l.statementTerm();
		return new(c) BreakStmt(c, location, name);
	}

	/**
	*/
	ContinueStmt parseContinueStmt()
	{
		auto location = l.expect(Token.Continue).loc;
		char[] name = null;

		if(!l.isStatementTerm() && l.type == Token.Ident)
		{
			name = l.tok.stringValue;
			l.next();
		}

		l.statementTerm();
		return new(c) ContinueStmt(c, location, name);
	}

	/**
	*/
	DoWhileStmt parseDoWhileStmt()
	{
		auto location = l.expect(Token.Do).loc;
		auto doBody = parseStatement(false);

		l.expect(Token.While);

		char[] name = null;

		if(l.type == Token.Ident)
		{
			name = l.tok.stringValue;
			l.next();
		}

		l.expect(Token.LParen);

		auto condition = parseExpression();
		auto endLocation = l.expect(Token.RParen).loc;
		return new(c) DoWhileStmt(c, location, endLocation, name, doBody, condition);
	}

	/**
	This function will actually parse both C-style and numeric for loops. The return value
	can be either one.
	*/
	Statement parseForStmt()
	{
		auto location = l.expect(Token.For).loc;
		char[] name = null;

		if(l.type == Token.Ident)
		{
			name = l.tok.stringValue;
			l.next();
		}

		l.expect(Token.LParen);

		alias ForStmt.Init Init;
		scope init = new List!(Init)(c.alloc);

		void parseInitializer()
		{
			Init tmp = void;

			if(l.type == Token.Local)
			{
				tmp.isDecl = true;
				tmp.decl = parseVarDecl();
			}
			else
			{
				tmp.isDecl = false;
				tmp.stmt = parseStatementExpr();
			}

			init ~= tmp;
		}

		if(l.type == Token.Semicolon)
			l.next();
		else if(l.type == Token.Ident && (l.peek.type == Token.Colon || l.peek.type == Token.Semicolon))
		{
			auto index = parseIdentifier();

			l.next();

			auto lo = parseExpression();
			l.expect(Token.DotDot);
			auto hi = parseExpression();

			Expression step;

			if(l.type == Token.Comma)
			{
				l.next();
				step = parseExpression();
			}
			else
				step = new(c) IntExp(c, l.loc, 1);

			l.expect(Token.RParen);

			auto code = parseStatement();
			return new(c) ForNumStmt(c, location, name, index, lo, hi, step, code);
		}
		else
		{
			parseInitializer();

			while(l.type == Token.Comma)
			{
				l.next();
				parseInitializer();
			}

			l.expect(Token.Semicolon);
		}

		Expression condition;

		if(l.type == Token.Semicolon)
			l.next();
		else
		{
			condition = parseExpression();
			l.expect(Token.Semicolon);
		}

		scope increment = new List!(Statement)(c.alloc);

		if(l.type == Token.RParen)
			l.next();
		else
		{
			increment ~= parseStatementExpr();

			while(l.type == Token.Comma)
			{
				l.next();
				increment ~= parseStatementExpr();
			}

			l.expect(Token.RParen);
		}

		auto code = parseStatement(false);
		return new(c) ForStmt(c, location, name, init.toArray(), condition, increment.toArray(), code);
	}

	/**
	*/
	ForeachStmt parseForeachStmt()
	{
		auto location = l.expect(Token.Foreach).loc;
		char[] name = null;

		if(l.type == Token.Ident)
		{
			name = l.tok.stringValue;
			l.next();
		}

		l.expect(Token.LParen);

		scope indices = new List!(Identifier)(c.alloc);
		indices ~= parseIdentifier();

		while(l.type == Token.Comma)
		{
			l.next();
			indices ~= parseIdentifier();
		}

		Identifier[] indicesArr;

		if(indices.length == 1)
		{
			indices ~= cast(Identifier)null;
			indicesArr = indices.toArray();

			for(uword i = indicesArr.length - 1; i > 0; i--)
				indicesArr[i] = indicesArr[i - 1];

			indicesArr[0] = dummyForeachIndex(indicesArr[1].location);
		}
		else
			indicesArr = indices.toArray();

		scope(failure)
			c.alloc.freeArray(indicesArr);

		l.expect(Token.Semicolon);

		scope container = new List!(Expression)(c.alloc);
		container ~= parseExpression();

		while(l.type == Token.Comma)
		{
			l.next();
			container ~= parseExpression();
		}

		if(container.length > 3)
			c.synException(location, "'foreach' may have a maximum of three container expressions");

		l.expect(Token.RParen);

		auto code = parseStatement();
		return new(c) ForeachStmt(c, location, name, indicesArr, container.toArray(), code);
	}

	/**
	*/
	IfStmt parseIfStmt()
	{
		auto location = l.expect(Token.If).loc;
		l.expect(Token.LParen);

		IdentExp condVar;

		if(l.type == Token.Local)
		{
			l.next();
			condVar = parseIdentExp();
			l.expect(Token.Assign);
		}

		auto condition = parseExpression();
		l.expect(Token.RParen);
		auto ifBody = parseStatement();

		Statement elseBody;

		auto endLocation = ifBody.endLocation;

		if(l.type == Token.Else)
		{
			l.next();
			elseBody = parseStatement();
			endLocation = elseBody.endLocation;
		}

		return new(c) IfStmt(c, location, endLocation, condVar, condition, ifBody, elseBody);
	}

	/**
	Parse an import statement.
	*/
	ImportStmt parseImportStmt()
	{
		auto location = l.loc;

		l.expect(Token.Import);

		Expression expr;
		Identifier importName;

		if(l.type == Token.LParen)
		{
			l.next();
			expr = parseExpression();
			l.expect(Token.RParen);
		}
		else
		{
			scope name = new List!(char)(c.alloc);

			name ~= parseName();

			while(l.type == Token.Dot)
			{
				l.next();
				name ~= ".";
				name ~= parseName();
			}

			auto arr = name.toArray();
			expr = new(c) StringExp(c, location, c.newString(arr));
			c.alloc.freeArray(arr);
		}

		if(l.type == Token.As)
		{
			l.next();
			importName = parseIdentifier();
		}

		scope symbols = new List!(Identifier)(c.alloc);
		scope symbolNames = new List!(Identifier)(c.alloc);

		void parseSelectiveImport()
		{
			auto id = parseIdentifier();

			if(l.type == Token.As)
			{
				l.next();
				symbolNames ~= parseIdentifier();
				symbols ~= id;
			}
			else
			{
				symbolNames ~= id;
				symbols ~= id;
			}
		}

		if(l.type == Token.Colon)
		{
			l.next();

			parseSelectiveImport();

			while(l.type == Token.Comma)
			{
				l.next();
				parseSelectiveImport();
			}
		}

		auto endLocation = l.loc;
		l.statementTerm();
		return new(c) ImportStmt(c, location, endLocation, importName, expr, symbols.toArray(), symbolNames.toArray());
	}

	/**
	*/
	ReturnStmt parseReturnStmt()
	{
		auto location = l.expect(Token.Return).loc;

		if(l.isStatementTerm())
		{
			auto endLocation = l.loc;
			l.statementTerm();
			return new(c) ReturnStmt(c, location, endLocation, null);
		}
		else
		{
			assert(l.loc.line == location.line);

			scope exprs = new List!(Expression)(c.alloc);
			exprs ~= parseExpression();

			while(l.type == Token.Comma)
			{
				l.next();
				exprs ~= parseExpression();
			}

			auto arr = exprs.toArray();
			auto endLocation = arr[$ - 1].endLocation;

			scope(failure)
				c.alloc.freeArray(arr);

			l.statementTerm();
			return new(c) ReturnStmt(c, location, endLocation, arr);
		}
	}

	/**
	*/
	SwitchStmt parseSwitchStmt()
	{
		auto location = l.expect(Token.Switch).loc;
		char[] name = null;

		if(l.type == Token.Ident)
		{
			name = l.tok.stringValue;
			l.next();
		}

		l.expect(Token.LParen);

		auto condition = parseExpression();

		l.expect(Token.RParen);
		l.expect(Token.LBrace);

		scope cases = new List!(CaseStmt)(c.alloc);

		cases ~= parseCaseStmt();

		while(l.type == Token.Case)
			cases ~= parseCaseStmt();

		DefaultStmt caseDefault;

		if(l.type == Token.Default)
			caseDefault = parseDefaultStmt();

		auto endLocation = l.expect(Token.RBrace).loc;
		return new(c) SwitchStmt(c, location, endLocation, name, condition, cases.toArray(), caseDefault);
	}

	/**
	*/
	CaseStmt parseCaseStmt()
	{
		auto location = l.expect(Token.Case).loc;

		alias CaseStmt.CaseCond CaseCond;
		scope conditions = new List!(CaseCond)(c.alloc);
		conditions ~= CaseCond(parseExpression());
		Expression highRange;

		if(l.type == Token.DotDot)
		{
			l.next();
			highRange = parseExpression();
		}
		else while(l.type == Token.Comma)
		{
			l.next();
			conditions ~= CaseCond(parseExpression());
		}

		l.expect(Token.Colon);

		scope statements = new List!(Statement)(c.alloc);

		while(l.type != Token.Case && l.type != Token.Default && l.type != Token.RBrace)
			statements ~= parseStatement();

		auto endLocation = l.loc;

		auto code = new(c) ScopeStmt(c, new(c) BlockStmt(c, location, endLocation, statements.toArray()));
		return new(c) CaseStmt(c, location, endLocation, conditions.toArray(), highRange, code);
	}

	/**
	*/
	DefaultStmt parseDefaultStmt()
	{
		auto location = l.loc;

		l.expect(Token.Default);
		l.expect(Token.Colon);

		scope statements = new List!(Statement)(c.alloc);

		while(l.type != Token.RBrace)
			statements ~= parseStatement();

		auto endLocation = l.loc;

		auto code = new(c) ScopeStmt(c, new(c) BlockStmt(c, location, endLocation, statements.toArray()));
		return new(c) DefaultStmt(c, location, endLocation, code);
	}

	/**
	*/
	ThrowStmt parseThrowStmt()
	{
		auto location = l.expect(Token.Throw).loc;
		auto exp = parseExpression();
		l.statementTerm();
		return new(c) ThrowStmt(c, location, exp);
	}

	/**
	*/
	ScopeActionStmt parseScopeActionStmt()
	{
		auto location = l.expect(Token.Scope).loc;
		l.expect(Token.LParen);
		auto id = l.expect(Token.Ident);

		ubyte type = void;

		if(id.stringValue == "exit")
			type = ScopeActionStmt.Exit;
		else if(id.stringValue == "success")
			type = ScopeActionStmt.Success;
		else if(id.stringValue == "failure")
			type = ScopeActionStmt.Failure;
		else
			c.synException(location, "Expected one of 'exit', 'success', or 'failure' for scope statement, not '{}'", id.stringValue);

		l.expect(Token.RParen);
		auto stmt = parseStatement();

		return new(c) ScopeActionStmt(c, location, type, stmt);
	}

	/**
	*/
	Statement parseTryStmt()
	{
		alias TryCatchStmt.CatchClause CC;

		auto location = l.expect(Token.Try).loc;
		auto tryBody = new(c) ScopeStmt(c, parseStatement());

		scope catches = new List!(CC)(c.alloc);

		scope(failure)
		{
			foreach(ref ca; catches)
				c.alloc.freeArray(ca.exTypes);
		}

		while(l.type == Token.Catch)
		{
			l.next();
			l.expect(Token.LParen);

			CC cc;
			cc.catchVar = parseIdentifier();
			l.expect(Token.Colon);

			scope types = new List!(Expression)(c.alloc);
			types ~= parseDottedName();

			while(l.type == Token.Or)
			{
				l.next();
				types ~= parseDottedName();
			}

			l.expect(Token.RParen);

			cc.catchBody = new(c) ScopeStmt(c, parseStatement());
			cc.exTypes = types.toArray();
			catches ~= cc;
		}

		Statement finallyBody;

		if(l.type == Token.Finally)
		{
			l.next();
			finallyBody = new(c) ScopeStmt(c, parseStatement());
		}

		if(catches.length > 0)
		{
			auto catchArr = catches.toArray();

			if(finallyBody)
			{
				auto tmp = new(c) TryCatchStmt(c, location, catchArr[$ - 1].catchBody.endLocation, tryBody, catchArr);
				return new(c) TryFinallyStmt(c, location, finallyBody.endLocation, tmp, finallyBody);
			}
			else
			{
				return new(c) TryCatchStmt(c, location, catchArr[$ - 1].catchBody.endLocation, tryBody, catchArr);
			}
		}
		else if(finallyBody)
			return new(c) TryFinallyStmt(c, location, finallyBody.endLocation, tryBody, finallyBody);
		else
			c.eofException(location, "Try statement must be followed by catches, finally, or both");

		assert(false);
	}

	/**
	*/
	WhileStmt parseWhileStmt()
	{
		auto location = l.expect(Token.While).loc;
		char[] name = null;

		if(l.type == Token.Ident)
		{
			name = l.tok.stringValue;
			l.next();
		}

		l.expect(Token.LParen);

		IdentExp condVar;

		if(l.type == Token.Local)
		{
			l.next();
			condVar = parseIdentExp();
			l.expect(Token.Assign);
		}

		auto condition = parseExpression();
		l.expect(Token.RParen);
		auto code = parseStatement(false);
		return new(c) WhileStmt(c, location, name, condVar, condition, code);
	}

	/**
	Parse any expression which can be executed as a statement, i.e. any expression which
	can have side effects, as well as assignments, function calls, yields, ?:, &&, and ||
	expressions. The parsed expression is checked for side effects before being returned.
	*/
	Statement parseStatementExpr()
	{
		auto location = l.loc;

		if(l.type == Token.Inc)
		{
			l.next();
			auto exp = parsePrimaryExp();
			return new(c) IncStmt(c, location, location, exp);
		}
		else if(l.type == Token.Dec)
		{
			l.next();
			auto exp = parsePrimaryExp();
			return new(c) DecStmt(c, location, location, exp);
		}

		Expression exp;

		if(l.type == Token.Length)
			exp = parseUnExp();
		else
			exp = parsePrimaryExp();

		if(l.tok.isOpAssign())
			return parseOpAssignStmt(exp);
		else if(l.type == Token.Assign || l.type == Token.Comma)
			return parseAssignStmt(exp);
		else if(l.type == Token.Inc)
		{
			l.next();
			return new(c) IncStmt(c, location, location, exp);
		}
		else if(l.type == Token.Dec)
		{
			l.next();
			return new(c) DecStmt(c, location, location, exp);
		}
		else if(l.type == Token.OrOr)
			exp = parseOrOrExp(exp);
		else if(l.type == Token.AndAnd)
			exp = parseAndAndExp(exp);
		else if(l.type == Token.Question)
			exp = parseCondExp(exp);

		exp.checkToNothing(c);
		return new(c) ExpressionStmt(c, exp);
	}

	/**
	Parse an assignment.

	Params:
		firstLHS = Since you can't tell if you're on an assignment until you parse
		at least one item in the left-hand-side, this parameter should be the first
		item on the left-hand-side. Therefore this function parses everything $(I but)
		the first item on the left-hand-side.
	*/
	AssignStmt parseAssignStmt(Expression firstLHS)
	{
		auto location = l.loc;

		scope lhs = new List!(Expression)(c.alloc);
		lhs ~= firstLHS;

		while(l.type == Token.Comma)
		{
			l.next();

			if(l.type == Token.Length)
				lhs ~= parseUnExp();
			else
				lhs ~= parsePrimaryExp();
		}

		l.expect(Token.Assign);

		scope rhs = new List!(Expression)(c.alloc);
		rhs ~= parseExpression();

		while(l.type == Token.Comma)
		{
			l.next();
			rhs ~= parseExpression();
		}

		if(lhs.length < rhs.length)
			c.semException(location, "Assignment has fewer destinations than sources");

		auto rhsArr = rhs.toArray();
		return new(c) AssignStmt(c, location, rhsArr[$ - 1].endLocation, lhs.toArray(), rhsArr);
	}

	/**
	Parse a reflexive assignment.

	Params:
		exp1 = The left-hand-side of the assignment. As with normal assignments, since
			you can't actually tell that something is an assignment until the LHS is
			at least parsed, this has to be passed as a parameter.
	*/
	Statement parseOpAssignStmt(Expression exp1)
	{
		auto location = l.loc;

		static char[] makeCase(char[] tok, char[] type)
		{
			return
			"case Token." ~ tok ~ ":"
				"l.next();"
				"auto exp2 = parseExpression();"
				"return new(c) " ~ type ~ "(c, location, exp2.endLocation, exp1, exp2);";
		}

		mixin(
		"switch(l.type)"
		"{"
			~ makeCase("AddEq",     "AddAssignStmt")
			~ makeCase("SubEq",     "SubAssignStmt")
			~ makeCase("CatEq",     "CatAssignStmt")
			~ makeCase("MulEq",     "MulAssignStmt")
			~ makeCase("DivEq",     "DivAssignStmt")
			~ makeCase("ModEq",     "ModAssignStmt")
			~ makeCase("ShlEq",     "ShlAssignStmt")
			~ makeCase("ShrEq",     "ShrAssignStmt")
			~ makeCase("UShrEq",    "UShrAssignStmt")
			~ makeCase("XorEq",     "XorAssignStmt")
			~ makeCase("OrEq",      "OrAssignStmt")
			~ makeCase("AndEq",     "AndAssignStmt")
			~ makeCase("DefaultEq", "CondAssignStmt") ~
			"default: assert(false, \"OpEqExp parse switch\");"
		"}");
	}

	/**
	Parse an expression.
	*/
	Expression parseExpression()
	{
		return parseCondExp();
	}

	/**
	Parse a conditional (?:) expression.

	Params:
		exp1 = Conditional expressions can occur as statements, in which case the first
			expression must be parsed in order to see what kind of expression it is.
			In this case, the first expression is passed in as a parameter. Otherwise,
			it defaults to null and this function parses the first expression itself.
	*/
	Expression parseCondExp(Expression exp1 = null)
	{
		auto location = l.loc;

		Expression exp2;
		Expression exp3;

		if(exp1 is null)
			exp1 = parseOrOrExp();

		while(l.type == Token.Question)
		{
			l.next();

			exp2 = parseExpression();
			l.expect(Token.Colon);
			exp3 = parseCondExp();
			exp1 = new(c) CondExp(c, location, exp3.endLocation, exp1, exp2, exp3);

			location = l.loc;
		}

		return exp1;
	}

	/**
	Parse a logical or (||) expression.

	Params:
		exp1 = Or-or expressions can occur as statements, in which case the first
			expression must be parsed in order to see what kind of expression it is.
			In this case, the first expression is passed in as a parameter. Otherwise,
			it defaults to null and this function parses the first expression itself.
	*/
	Expression parseOrOrExp(Expression exp1 = null)
	{
		auto location = l.loc;

		Expression exp2;

		if(exp1 is null)
			exp1 = parseAndAndExp();

		while(l.type == Token.OrOr)
		{
			l.next();

			exp2 = parseAndAndExp();
			exp1 = new(c) OrOrExp(c, location, exp2.endLocation, exp1, exp2);

			location = l.loc;
		}

		return exp1;
	}

	/**
	Parse a logical and (&&) expression.

	Params:
		exp1 = And-and expressions can occur as statements, in which case the first
			expression must be parsed in order to see what kind of expression it is.
			In this case, the first expression is passed in as a parameter. Otherwise,
			it defaults to null and this function parses the first expression itself.
	*/
	Expression parseAndAndExp(Expression exp1 = null)
	{
		auto location = l.loc;

		Expression exp2;

		if(exp1 is null)
			exp1 = parseOrExp();

		while(l.type == Token.AndAnd)
		{
			l.next();

			exp2 = parseOrExp();
			exp1 = new(c) AndAndExp(c, location, exp2.endLocation, exp1, exp2);

			location = l.loc;
		}

		return exp1;
	}

	/**
	*/
	Expression parseOrExp()
	{
		auto location = l.loc;

		Expression exp1;
		Expression exp2;

		exp1 = parseXorExp();

		while(l.type == Token.Or)
		{
			l.next();

			exp2 = parseXorExp();
			exp1 = new(c) OrExp(c, location, exp2.endLocation, exp1, exp2);

			location = l.loc;
		}

		return exp1;
	}

	/**
	*/
	Expression parseXorExp()
	{
		auto location = l.loc;

		Expression exp1;
		Expression exp2;

		exp1 = parseAndExp();

		while(l.type == Token.Xor)
		{
			l.next();

			exp2 = parseAndExp();
			exp1 = new(c) XorExp(c, location, exp2.endLocation, exp1, exp2);

			location = l.loc;
		}

		return exp1;
	}

	/**
	*/
	Expression parseAndExp()
	{
		CompileLoc location = l.loc;

		Expression exp1;
		Expression exp2;

		exp1 = parseCmpExp();

		while(l.type == Token.And)
		{
			l.next();

			exp2 = parseCmpExp();
			exp1 = new(c) AndExp(c, location, exp2.endLocation, exp1, exp2);

			location = l.loc;
		}

		return exp1;
	}

	/**
	Parse a comparison expression. This is any of ==, !=, is, !is, <, <=, >, >=,
	<=>, as, in, and !in.
	*/
	Expression parseCmpExp()
	{
		auto location = l.loc;

		auto exp1 = parseShiftExp();
		Expression exp2;

		switch(l.type)
		{
			case Token.EQ:
				l.next();
				exp2 = parseShiftExp();
				exp1 = new(c) EqualExp(c, location, exp2.endLocation, exp1, exp2);
				break;

			case Token.NE:
				l.next();
				exp2 = parseShiftExp();
				exp1 = new(c) NotEqualExp(c, location, exp2.endLocation, exp1, exp2);
				break;

			case Token.Not:
				if(l.peek.type == Token.Is)
				{
					l.next();
					l.next();
					exp2 = parseShiftExp();
					exp1 = new(c) NotIsExp(c, location, exp2.endLocation, exp1, exp2);
				}
				else if(l.peek.type == Token.In)
				{
					l.next();
					l.next();
					exp2 = parseShiftExp();
					exp1 = new(c) NotInExp(c, location, exp2.endLocation, exp1, exp2);
				}
				// no, there should not be an 'else' here

				break;

			case Token.Is:
				l.next();
				exp2 = parseShiftExp();
				exp1 = new(c) IsExp(c, location, exp2.endLocation, exp1, exp2);
				break;

			case Token.LT:
				l.next();
				exp2 = parseShiftExp();
				exp1 = new(c) LTExp(c, location, exp2.endLocation, exp1, exp2);
				break;

			case Token.LE:
				l.next();
				exp2 = parseShiftExp();
				exp1 = new(c) LEExp(c, location, exp2.endLocation, exp1, exp2);
				break;

			case Token.GT:
				l.next();
				exp2 = parseShiftExp();
				exp1 = new(c) GTExp(c, location, exp2.endLocation, exp1, exp2);
				break;

			case Token.GE:
				l.next();
				exp2 = parseShiftExp();
				exp1 = new(c) GEExp(c, location, exp2.endLocation, exp1, exp2);
				break;

			case Token.As:
				l.next();
				exp2 = parseShiftExp();
				exp1 = new(c) AsExp(c, location, exp2.endLocation, exp1, exp2);
				break;

			case Token.In:
				l.next();
				exp2 = parseShiftExp();
				exp1 = new(c) InExp(c, location, exp2.endLocation, exp1, exp2);
				break;

			case Token.Cmp3:
				l.next();
				exp2 = parseShiftExp();
				exp1 = new(c) Cmp3Exp(c, location, exp2.endLocation, exp1, exp2);
				break;

			default:
				break;
		}

		return exp1;
	}

	/**
	*/
	Expression parseShiftExp()
	{
		auto location = l.loc;

		auto exp1 = parseAddExp();
		Expression exp2;

		while(true)
		{
			switch(l.type)
			{
				case Token.Shl:
					l.next();
					exp2 = parseAddExp();
					exp1 = new(c) ShlExp(c, location, exp2.endLocation, exp1, exp2);
					continue;

				case Token.Shr:
					l.next();
					exp2 = parseAddExp();
					exp1 = new(c) ShrExp(c, location, exp2.endLocation, exp1, exp2);
					continue;

				case Token.UShr:
					l.next();
					exp2 = parseAddExp();
					exp1 = new(c) UShrExp(c, location, exp2.endLocation, exp1, exp2);
					continue;

				default:
					break;
			}

			break;
		}

		return exp1;
	}

	/**
	This function parses not only addition and subtraction expressions, but also
	concatenation expressions.
	*/
	Expression parseAddExp()
	{
		auto location = l.loc;

		auto exp1 = parseMulExp();
		Expression exp2;

		while(true)
		{
			switch(l.type)
			{
				case Token.Add:
					l.next();
					exp2 = parseMulExp();
					exp1 = new(c) AddExp(c, location, exp2.endLocation, exp1, exp2);
					continue;

				case Token.Sub:
					l.next();
					exp2 = parseMulExp();
					exp1 = new(c) SubExp(c, location, exp2.endLocation, exp1, exp2);
					continue;

				case Token.Cat:
					l.next();
					exp2 = parseMulExp();
					exp1 = new(c) CatExp(c, location, exp2.endLocation, exp1, exp2);
					continue;

				default:
					break;
			}

			break;
		}

		return exp1;
	}

	/**
	*/
	Expression parseMulExp()
	{
		auto location = l.loc;

		auto exp1 = parseUnExp();
		Expression exp2;

		while(true)
		{
			switch(l.type)
			{
				case Token.Mul:
					l.next();
					exp2 = parseUnExp();
					exp1 = new(c) MulExp(c, location, exp2.endLocation, exp1, exp2);
					continue;

				case Token.Div:
					l.next();
					exp2 = parseUnExp();
					exp1 = new(c) DivExp(c, location, exp2.endLocation, exp1, exp2);
					continue;

				case Token.Mod:
					l.next();
					exp2 = parseUnExp();
					exp1 = new(c) ModExp(c, location, exp2.endLocation, exp1, exp2);
					continue;

				default:
					break;
			}

			break;
		}

		return exp1;
	}

	/**
	Parse a unary expression. This parses negation (-), not (!), complement (~),
	and length (#) expressions. '#vararg' is also incidentally parsed.
	*/
	Expression parseUnExp()
	{
		auto location = l.loc;

		Expression exp;

		switch(l.type)
		{
			case Token.Sub:
				l.next();
				exp = parseUnExp();
				exp = new(c) NegExp(c, location, exp);
				break;

			case Token.Not:
				l.next();
				exp = parseUnExp();
				exp = new(c) NotExp(c, location, exp);
				break;

			case Token.Cat:
				l.next();
				exp = parseUnExp();
				exp = new(c) ComExp(c, location, exp);
				break;

			case Token.Length:
				l.next();
				exp = parseUnExp();

				if(exp.as!(VarargExp))
					exp = new(c) VargLenExp(c, location, exp.endLocation);
				else
					exp = new(c) LenExp(c, location, exp);
				break;

			default:
				exp = parsePrimaryExp();
				break;
		}

		return exp;
	}

	/**
	Parse a primary expression. Will also parse any postfix expressions attached
	to the primary exps.
	*/
	Expression parsePrimaryExp()
	{
		Expression exp;
		auto location = l.loc;

		switch(l.type)
		{
			case Token.Ident:                  exp = parseIdentExp(); break;
			case Token.This:                   exp = parseThisExp(); break;
			case Token.Null:                   exp = parseNullExp(); break;
			case Token.True, Token.False:      exp = parseBoolExp(); break;
			case Token.Vararg:                 exp = parseVarargExp(); break;
			case Token.CharLiteral:            exp = parseCharExp(); break;
			case Token.IntLiteral:             exp = parseIntExp(); break;
			case Token.FloatLiteral:           exp = parseFloatExp(); break;
			case Token.StringLiteral:          exp = parseStringExp(); break;
			case Token.Function:               exp = parseFuncLiteralExp(); break;
			case Token.Backslash:              exp = parseHaskellFuncLiteralExp(); break;
			case Token.Class:                  exp = parseClassLiteralExp(); break;
			case Token.LParen:                 exp = parseParenExp(); break;
			case Token.LBrace:                 exp = parseTableCtorExp(); break;
			case Token.LBracket:               exp = parseArrayCtorExp(); break;
			case Token.Namespace:              exp = parseNamespaceCtorExp(); break;
			case Token.Yield:                  exp = parseYieldExp(); break;
			case Token.Super:                  exp = parseSuperCallExp(); break;
			case Token.Colon:                  exp = parseMemberExp(); break;

			default:
				l.expected("Expression");
		}

		return parsePostfixExp(exp);
	}

	/**
	*/
	IdentExp parseIdentExp()
	{
		auto id = parseIdentifier();
		return new(c) IdentExp(c, id);
	}

	/**
	*/
	ThisExp parseThisExp()
	{
		with(l.expect(Token.This))
			return new(c) ThisExp(c, loc);
	}

	/**
	*/
	NullExp parseNullExp()
	{
		with(l.expect(Token.Null))
			return new(c) NullExp(c, loc);
	}

	/**
	*/
	BoolExp parseBoolExp()
	{
		auto loc = l.loc;

		if(l.type == Token.True)
		{
			l.expect(Token.True);
			return new(c) BoolExp(c, loc, true);
		}
		else
		{
			l.expect(Token.False);
			return new(c) BoolExp(c, loc, false);
		}
	}

	/**
	*/
	VarargExp parseVarargExp()
	{
		with(l.expect(Token.Vararg))
			return new(c) VarargExp(c, loc);
	}

	/**
	*/
	CharExp parseCharExp()
	{
		with(l.expect(Token.CharLiteral))
			return new(c) CharExp(c, loc, cast(dchar)intValue);
	}

	/**
	*/
	IntExp parseIntExp()
	{
		with(l.expect(Token.IntLiteral))
			return new(c) IntExp(c, loc, intValue);
	}

	/**
	*/
	FloatExp parseFloatExp()
	{
		with(l.expect(Token.FloatLiteral))
			return new(c) FloatExp(c, loc, floatValue);
	}

	/**
	*/
	StringExp parseStringExp()
	{
		with(l.expect(Token.StringLiteral))
			return new(c) StringExp(c, loc, stringValue);
	}

	/**
	*/
	FuncLiteralExp parseFuncLiteralExp()
	{
		auto location = l.loc;
		auto def = parseFuncLiteral();
		return new(c) FuncLiteralExp(c, location, def);
	}

	/**
	*/
	FuncLiteralExp parseHaskellFuncLiteralExp()
	{
		auto location = l.loc;
		auto def = parseHaskellFuncLiteral();
		return new(c) FuncLiteralExp(c, location, def);
	}

	/**
	*/
	ClassLiteralExp parseClassLiteralExp()
	{
		auto location = l.loc;
		auto def = parseClassDef(true);
		return new(c) ClassLiteralExp(c, location, def);
	}

	/**
	Parse a parenthesized expression.
	*/
	Expression parseParenExp()
	{
		auto location = l.expect(Token.LParen).loc;
		auto exp = parseExpression();
		auto endLocation = l.expect(Token.RParen).loc;
		return new(c) ParenExp(c, location, endLocation, exp);
	}

	/**
	*/
	Expression parseTableCtorExp()
	{
		auto location = l.expect(Token.LBrace).loc;

		alias TableCtorExp.Field Field;
		scope fields = new List!(Field)(c.alloc);

		if(l.type != Token.RBrace)
		{
			void parseField()
			{
				Expression k;
				Expression v;

				switch(l.type)
				{
					case Token.LBracket:
						l.next();
						k = parseExpression();

						l.expect(Token.RBracket);
						l.expect(Token.Assign);

						v = parseExpression();
						break;

					case Token.Function:
						auto fd = parseSimpleFuncDef();
						k = new(c) StringExp(c, fd.location, fd.name.name);
						v = new(c) FuncLiteralExp(c, fd.location, fd);
						break;

					default:
						Identifier id = parseIdentifier();
						l.expect(Token.Assign);
						k = new(c) StringExp(c, id.location, id.name);
						v = parseExpression();
						break;
				}

				fields ~= Field(k, v);
			}

			bool firstWasBracketed = l.type == Token.LBracket;
			parseField();

			if(firstWasBracketed && (l.type == Token.For || l.type == Token.Foreach))
			{
				auto forComp = parseForComprehension();
				auto endLocation = l.expect(Token.RBrace).loc;

				auto dummy = fields.toArray();
				auto key = dummy[0].key;
				auto value = dummy[0].value;
				c.alloc.freeArray(dummy);

				return new(c) TableComprehension(c, location, endLocation, key, value, forComp);
			}

			if(l.type == Token.Comma)
				l.next();

			while(l.type != Token.RBrace)
			{
				parseField();

				if(l.type == Token.Comma)
					l.next();
			}
		}

		auto endLocation = l.expect(Token.RBrace).loc;
		return new(c) TableCtorExp(c, location, endLocation, fields.toArray());
	}

	/**
	*/
	PrimaryExp parseArrayCtorExp()
	{
		auto location = l.expect(Token.LBracket).loc;

		scope values = new List!(Expression)(c.alloc);

		if(l.type != Token.RBracket)
		{
			auto exp = parseExpression();

			if(l.type == Token.For || l.type == Token.Foreach)
			{
				auto forComp = parseForComprehension();
				auto endLocation = l.expect(Token.RBracket).loc;
				return new(c) ArrayComprehension(c, location, endLocation, exp, forComp);
			}
			else
			{
				values ~= exp;

				if(l.type == Token.Comma)
					l.next();

				while(l.type != Token.RBracket)
				{
					values ~= parseExpression();

					if(l.type == Token.Comma)
						l.next();
				}
			}
		}

		auto endLocation = l.expect(Token.RBracket).loc;
		return new(c) ArrayCtorExp(c, location, endLocation, values.toArray());
	}

	/**
	*/
	NamespaceCtorExp parseNamespaceCtorExp()
	{
		auto location = l.loc;
		auto def = parseNamespaceDef();
		return new(c) NamespaceCtorExp(c, location, def);
	}

	/**
	*/
	YieldExp parseYieldExp()
	{
		auto location = l.expect(Token.Yield).loc;
		l.expect(Token.LParen);

		Expression[] args;

		if(l.type != Token.RParen)
			args = parseArguments();

		scope(failure)
			c.alloc.freeArray(args);

		auto endLocation = l.expect(Token.RParen).loc;
		return new(c) YieldExp(c, location, endLocation, args);
	}

	/**
	*/
	MethodCallExp parseSuperCallExp()
	{
		auto location = l.expect(Token.Super).loc;

		Expression method;

		if(l.type == Token.Dot)
		{
			l.next();

			if(l.type == Token.Ident)
			{
				with(l.expect(Token.Ident))
					method = new(c) StringExp(c, location, stringValue);
			}
			else
			{
				l.expect(Token.LParen);
				method = parseExpression();
				l.expect(Token.RParen);
			}
		}
		else
			method = new(c) StringExp(c, location, c.newString("constructor"));

		Expression[] args;
		CompileLoc endLocation;

		if(l.type == Token.LParen)
		{
			l.next();

			if(l.type != Token.RParen)
				args = parseArguments();

			scope(failure)
				c.alloc.freeArray(args);

			endLocation = l.expect(Token.RParen).loc;
		}
		else
		{
			l.expect(Token.Dollar);

			scope a = new List!(Expression)(c.alloc);
			a ~= parseExpression();

			while(l.type == Token.Comma)
			{
				l.next();
				a ~= parseExpression();
			}

			args = a.toArray();
			endLocation = args[$ - 1].endLocation;
		}

		return new(c) MethodCallExp(c, location, endLocation, null, method, args, true);
	}

	/**
	Parse a member exp (:a). This is a shorthand expression for "this.a". This
	also works with super (:super) and paren (:("a")) versions.
	*/
	Expression parseMemberExp()
	{
		auto loc = l.expect(Token.Colon).loc;
		CompileLoc endLoc;

		if(l.type == Token.LParen)
		{
			l.next();
			auto exp = parseExpression();
			endLoc = l.expect(Token.RParen).loc;
			return new(c) DotExp(c, new(c) ThisExp(c, loc), exp);
		}
		else if(l.type == Token.Super)
		{
			endLoc = l.loc;
			l.next();
			return new(c) DotSuperExp(c, endLoc, new(c) ThisExp(c, loc));
		}
		else
		{
			endLoc = l.loc;
			auto name = parseName();

			if(mCurrentClassName !is null && isPrivateFieldName(name))
				name = makePrivateFieldName(mCurrentClassName, name);

			return new(c) DotExp(c, new(c) ThisExp(c, loc), new(c) StringExp(c, endLoc, name));
		}
	}

	/**
	Parse a postfix expression. This includes dot expressions (.ident, .super, and .(expr)),
	function calls, indexing, slicing, and vararg slicing.

	Params:
		exp = The expression to which the resulting postfix expression will be attached.
	*/
	Expression parsePostfixExp(Expression exp)
	{
		while(true)
		{
			auto location = l.loc;

			switch(l.type)
			{
				case Token.Dot:
					l.next();

					if(l.type == Token.Ident)
					{
						auto loc = l.loc;
						auto name = parseName();

						if(mCurrentClassName !is null && isPrivateFieldName(name))
							name = makePrivateFieldName(mCurrentClassName, name);

						exp = new(c) DotExp(c, exp, new(c) StringExp(c, loc, name));
					}
					else if(l.type == Token.Super)
					{
						auto endLocation = l.loc;
						l.next();
						exp = new(c) DotSuperExp(c, endLocation, exp);
					}
					else
					{
						l.expect(Token.LParen);
						auto subExp = parseExpression();
						l.expect(Token.RParen);
						exp = new(c) DotExp(c, exp, subExp);
					}
					continue;

				case Token.Dollar:
					l.next();

					scope args = new List!(Expression)(c.alloc);
					args ~= parseExpression();

					while(l.type == Token.Comma)
					{
						l.next();
						args ~= parseExpression();
					}

					auto arr = args.toArray();

					if(auto dot = exp.as!(DotExp))
						exp = new(c) MethodCallExp(c, dot.location, arr[$ - 1].endLocation, dot.op, dot.name, arr, false);
					else
						exp = new(c) CallExp(c, arr[$ - 1].endLocation, exp, null, arr);
					continue;

				case Token.LParen:
					if(exp.endLocation.line != l.loc.line)
						c.synException(l.loc, "ambiguous left-paren (function call or beginning of new statement?)");

					l.next();

					Expression context;
					Expression[] args;

					if(l.type == Token.With)
					{
						if(exp.as!(DotExp))
							c.semException(l.loc, "'with' is disallowed for method calls; if you aren't making an actual method call, put the function in parentheses");

						l.next();

						context = parseExpression();

						if(l.type == Token.Comma)
						{
							l.next();
							args = parseArguments();
						}
					}
					else if(l.type != Token.RParen)
						args = parseArguments();

					{
					scope(failure)
						c.alloc.freeArray(args);

					auto endLocation = l.expect(Token.RParen).loc;

					if(auto dot = exp.as!(DotExp))
						exp = new(c) MethodCallExp(c, dot.location, endLocation, dot.op, dot.name, args, false);
					else
						exp = new(c) CallExp(c, endLocation, exp, context, args);
					}

					continue;

				case Token.LBracket:
					l.next();

					Expression loIndex;
					Expression hiIndex;
					CompileLoc endLocation;

					if(l.type == Token.RBracket)
					{
						// a[]
						loIndex = new(c) NullExp(c, l.loc);
						hiIndex = new(c) NullExp(c, l.loc);
						endLocation = l.expect(Token.RBracket).loc;
					}
					else if(l.type == Token.DotDot)
					{
						loIndex = new(c) NullExp(c, l.loc);
						l.next();

						if(l.type == Token.RBracket)
						{
							// a[ .. ]
							hiIndex = new(c) NullExp(c, l.loc);
							endLocation = l.expect(Token.RBracket).loc;
						}
						else
						{
							// a[ .. 0]
							hiIndex = parseExpression();
							endLocation = l.expect(Token.RBracket).loc;
						}
					}
					else
					{
						loIndex = parseExpression();

						if(l.type == Token.DotDot)
						{
							l.next();

							if(l.type == Token.RBracket)
							{
								// a[0 .. ]
								hiIndex = new(c) NullExp(c, l.loc);
								endLocation = l.expect(Token.RBracket).loc;
							}
							else
							{
								// a[0 .. 0]
								hiIndex = parseExpression();
								endLocation = l.expect(Token.RBracket).loc;
							}
						}
						else
						{
							// a[0]
							endLocation = l.expect(Token.RBracket).loc;

							if(exp.as!(VarargExp))
								exp = new(c) VargIndexExp(c, location, endLocation, loIndex);
							else
								exp = new(c) IndexExp(c, endLocation, exp, loIndex);

							// continue here since this isn't a slice
							continue;
						}
					}

					if(exp.as!(VarargExp))
						exp = new(c) VargSliceExp(c, location, endLocation, loIndex, hiIndex);
					else
						exp = new(c) SliceExp(c, endLocation, exp, loIndex, hiIndex);
					continue;

				default:
					return exp;
			}
		}
	}

	/**
	Parse a for comprehension. Note that in the grammar, this actually includes an optional
	if comprehension and optional for comprehension after it, meaning that an entire array
	or table comprehension is parsed in one call.
	*/
	ForComprehension parseForComprehension()
	{
		auto loc = l.loc;
		IfComprehension ifComp;
		ForComprehension forComp;

		void parseNextComp()
		{
			if(l.type == Token.If)
				ifComp = parseIfComprehension();

			if(l.type == Token.For || l.type == Token.Foreach)
				forComp = parseForComprehension();
		}

		if(l.type == Token.For)
		{
			l.next();
			auto name = parseIdentifier();

			if(l.type != Token.Colon && l.type != Token.Semicolon)
				l.expected(": or ;");

			l.next();

			auto exp = parseExpression();
			l.expect(Token.DotDot);
			auto exp2 = parseExpression();

			Expression step;

			if(l.type == Token.Comma)
			{
				l.next();
				step = parseExpression();
			}
			else
				step = new(c) IntExp(c, l.loc, 1);

			parseNextComp();
			return new(c) ForNumComprehension(c, loc, name, exp, exp2, step, ifComp, forComp);
		}
		else if(l.type == Token.Foreach)
		{
			l.next();
			scope names = new List!(Identifier)(c.alloc);
			names ~= parseIdentifier();

			while(l.type == Token.Comma)
			{
				l.next();
				names ~= parseIdentifier();
			}

			l.expect(Token.Semicolon);

			scope container = new List!(Expression)(c.alloc);
			container ~= parseExpression();

			while(l.type == Token.Comma)
			{
				l.next();
				container ~= parseExpression();
			}

			if(container.length > 3)
				c.synException(container[0].location, "Too many expressions in container");

			Identifier[] namesArr;

			if(names.length == 1)
			{
				names ~= cast(Identifier)null;
				namesArr = names.toArray();

				for(uword i = namesArr.length - 1; i > 0; i--)
					namesArr[i] = namesArr[i - 1];

				namesArr[0] = dummyForeachIndex(namesArr[1].location);
			}
			else
				namesArr = names.toArray();

			scope(failure)
				c.alloc.freeArray(namesArr);

			parseNextComp();
			return new(c) ForeachComprehension(c, loc, namesArr, container.toArray(), ifComp, forComp);

		}
		else
			l.expected("for or foreach");

		assert(false);
	}

	/**
	*/
	IfComprehension parseIfComprehension()
	{
		auto loc = l.expect(Token.If).loc;
		auto condition = parseExpression();
		return new(c) IfComprehension(c, loc, condition);
	}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

private:

	Identifier dummyForeachIndex(CompileLoc loc)
	{
		pushFormat(c.thread, "__dummy{}", mDummyNameCounter++);
		auto str = c.newString(getString(c.thread, -1));
		pop(c.thread);
		return new(c) Identifier(c, loc, str);
	}

	Identifier dummyFuncLiteralName(CompileLoc loc)
	{
		pushFormat(c.thread, "<literal at {}({}:{})>", loc.file, loc.line, loc.col);
		auto str = c.newString(getString(c.thread, -1));
		pop(c.thread);
		return new(c) Identifier(c, loc, str);
	}

	Identifier dummyClassLiteralName(CompileLoc loc)
	{
		pushFormat(c.thread, "<class at {}({}:{})>", loc.file, loc.line, loc.col);
		auto str = c.newString(getString(c.thread, -1));
		pop(c.thread);
		return new(c) Identifier(c, loc, str);
	}

	bool isPrivateFieldName(char[] name)
	{
		return name.length >= 2 && name[0] == '_' && name[1] != '_';
	}

	char[] makePrivateFieldName(char[] className, char[] fieldName)
	{
		pushString(c.thread, className);
		pushString(c.thread, fieldName);
		cat(c.thread, 2);
		auto ret = c.newString(getString(c.thread, -1));
		pop(c.thread);
		return ret;
	}

	void attachDocs(T)(T t, char[] preDocs, CompileLoc preDocsLoc)
	{
		if(!c.docComments)
			return;

		if(preDocs.length > 0)
		{
			if(l.tok.postComment.length > 0)
				c.synException(preDocsLoc, "Cannot have two doc comments on one declaration");
			else
			{
				t.docs = preDocs;
				t.docsLoc = preDocsLoc;
			}
		}
		else if(l.tok.postComment.length > 0)
		{
			t.docs = l.tok.postComment;
			t.docsLoc = l.tok.postCommentLoc;
		}
	}

	Expression decoToExp(Decorator dec, Expression exp)
	{
		scope args = new List!(Expression)(c.alloc);

		if(dec.nextDec)
			args ~= decoToExp(dec.nextDec, exp);
		else
			args ~= exp;

		args ~= dec.args;
		auto argsArray = args.toArray();

		scope(failure)
			c.alloc.freeArray(argsArray);

		if(auto f = dec.func.as!(DotExp))
		{
			if(dec.context !is null)
				c.semException(dec.location, "'with' is disallowed for method calls");

			return new(c) MethodCallExp(c, dec.location, dec.endLocation, f.op, f.name, argsArray, false);
		}
		else
			return new(c) CallExp(c, dec.endLocation, dec.func, dec.context, argsArray);
	}
}