/******************************************************************************
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

module minid.parser;

import minid.ast;
import minid.compilertypes;
import minid.interpreter;
import minid.lexer;
import minid.types;

struct Parser
{
	private ICompiler c;
	private Lexer* l;
	private uword dummyNameCounter = 0;

// ================================================================================================================================================
// Public
// ================================================================================================================================================

	/**
	*/
	public static Parser opCall(ICompiler compiler, Lexer* lexer)
	{
		Parser ret;
		ret.c = compiler;
		ret.l = lexer;
		return ret;
	}

	/**
	*/
	public dchar[] parseName()
	{
		with(l.expect(Token.Ident))
			return stringValue;
	}

	/**
	*/
	public Identifier parseIdentifier()
	{
		with(l.expect(Token.Ident))
			return new(c) Identifier(c, loc, stringValue);
	}
	
	/**
	Parse a comma-separated list of expressions, such as for argument lists.
	*/
	public Expression[] parseArguments()
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
	public Module parseModule()
	{
		auto location = l.loc;
		auto modDecl = parseModuleDecl();

		scope statements = new List!(Statement)(c.alloc);

		while(l.type != Token.EOF)
			statements ~= parseStatement();

		l.expect(Token.EOF);

		return new(c) Module(c, location, l.loc, modDecl, statements.toArray());
	}
	
	/**
	Parse a module declaration.
	*/
	public ModuleDecl parseModuleDecl()
	{
		auto location = l.loc;

		TableCtorExp attrs;

		if(l.type == Token.LAttr)
			attrs = parseAttrTable();

		l.expect(Token.Module);

		scope names = new List!(dchar[])(c.alloc);
		names ~= parseName();

		while(l.type == Token.Dot)
		{
			l.next();
			names ~= parseName();
		}

		auto endLocation = l.loc;
		l.statementTerm();

		return new(c) ModuleDecl(c, location, endLocation, names.toArray(), attrs);
	}
	
	/**
	Parse a statement.
	
	Params:
		needScope = If true, and the statement is a block statement, the block will be wrapped
			in a ScopeStmt.  Else, the raw block statement will be returned.
	*/
	public Statement parseStatement(bool needScope = true)
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
				Token.Object,
				Token.Function,
				Token.Global,
				Token.LAttr,
				Token.Local,
				Token.Namespace:

				return parseDeclStmt();

			case Token.LBrace:
				if(needScope)
					return new(c) ScopeStmt(c, parseBlockStmt());
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
			case Token.Switch:   return parseSwitchStmt();
			case Token.Throw:    return parseThrowStmt();
			case Token.Try:      return parseTryStmt();
			case Token.While:    return parseWhileStmt();

			case Token.Semicolon:
				c.exception(l.loc, "Empty statements ( ';' ) are not allowed (use {{} for an empty statement)");

			default:
				l.expected("statement");
		}
		
		assert(false);
	}

	/**
	*/
	public Statement parseExpressionStmt()
	{
		auto stmt = parseStatementExpr();
		l.statementTerm();
		return stmt;
	}
	
	/**
	*/
	public DeclStmt parseDeclStmt(TableCtorExp attrs = null)
	{
		switch(l.type)
		{
			case Token.Local, Token.Global:
				switch(l.peek.type)
				{
					case Token.Ident:
						if(attrs !is null)
							c.exception(l.loc, "Cannot attach attributes to variables");

						auto ret = parseVarDecl();
						l.statementTerm();
						return ret;

					case Token.Function:
		            	return parseFuncDecl(attrs);

					case Token.Object:
						return parseObjectDecl(attrs);

					case Token.Namespace:
						return parseNamespaceDecl(attrs);

					default:
						c.exception(l.loc, "Illegal token '{}' after '{}'", l.peek.typeString(), l.tok.typeString());
				}

			case Token.Function:
				return parseFuncDecl(attrs);

			case Token.Object:
				return parseObjectDecl(attrs);

			case Token.Namespace:
				return parseNamespaceDecl(attrs);

			case Token.LAttr:
				if(attrs is null)
					return parseDeclStmt(parseAttrTable());
				else
					l.expected("Declaration");

			default:
				l.expected("Declaration");
		}
		
		assert(false);
	}
	
	/**
	Parse a local or global variable declaration.
	*/
	public VarDecl parseVarDecl()
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

		Expression initializer;

		if(l.type == Token.Assign)
		{
			l.next();
			initializer = parseExpression();
			endLocation = initializer.endLocation;
		}

		return new(c) VarDecl(c, location, endLocation, protection, namesArr, initializer);
	}

	/**
	Parse a function declaration, optional protection included.

	Params:
		attrs = An optional attribute table to attach to the function.
	*/
	public FuncDecl parseFuncDecl(TableCtorExp attrs = null)
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

		return new(c) FuncDecl(c, location, protection, parseSimpleFuncDef(attrs));
	}
	
	/**
	Parse everything starting from the left-paren of the parameter list to the end of the body.
	
	Params:
		location = Where the function actually started.
		name = The name of the function.  Must be non-null.
		attrs = The optional attribute table.

	Returns:
		The completed function definition.
	*/
	public FuncDef parseFuncBody(CompileLoc location, Identifier name, TableCtorExp attrs = null)
	{
		l.expect(Token.LParen);
		bool isVararg;
		auto params = parseFuncParams(isVararg);
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
			code = parseStatement();

		return new(c) FuncDef(c, location, name, params, isVararg, code, attrs);
	}
	
	/**
	Parse a function parameter list, opening and closing parens included.

	Params:
		isVararg = Return value to indicate if the parameter list ended with 'vararg'.

	Returns:
		An array of Param structs.
	*/
	public FuncDef.Param[] parseFuncParams(out bool isVararg)
	{
		alias FuncDef.Param Param;
		alias FuncDef.TypeMask TypeMask;
		scope ret = new List!(Param)(c.alloc);

		void parseParam()
		{
			Param p = void;
			p.name = parseIdentifier();

			if(l.type == Token.Colon)
			{
				l.next();
				p.typeMask = parseParamType(p.objectTypes);
			}
			else
			{
				p.typeMask = TypeMask.Any;
				p.objectTypes = null;
			}

			if(l.type == Token.Assign)
			{
				l.next();
				p.defValue = parseExpression();
				
				// Having a default parameter implies allowing null as a parameter type
				p.typeMask |= TypeMask.Null;
			}
			else
				p.defValue = null;

			ret ~= p;
		}

		Param thisParam;
		thisParam.name = new(c) Identifier(c, l.loc, c.newString("this"));

		if(l.type == Token.This)
		{
			l.next();
			l.expect(Token.Colon);

			thisParam.typeMask = parseParamType(thisParam.objectTypes);
			ret ~= thisParam;

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
		else if(l.type == Token.Vararg)
		{
			ret ~= thisParam;
			isVararg = true;
			l.next();
		}
		else if(l.type == Token.Ident)
		{
			ret ~= thisParam;
			parseParam();

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

		return ret.toArray();
	}
	
	/**
	Parse a parameter type.  This corresponds to the Type element of the grammar.
	Returns the type mask, as well as an optional list of object types that this
	parameter can accept in the objectTypes parameter.
	*/
	public uint parseParamType(out Expression[] objectTypes)
	{
		alias FuncDef.TypeMask TypeMask;

		uint ret = 0;
		scope objTypes = new List!(Expression)(c.alloc);

		void addConstraint(MDValue.Type t)
		{
			if((ret & (1 << cast(uint)t)) && t != MDValue.Type.Object)
				c.exception(l.loc, "Duplicate parameter type constraint for type '{}'", MDValue.typeString(t));

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
				case Token.Null:      addConstraint(MDValue.Type.Null);      l.next(); break;
				case Token.Function:  addConstraint(MDValue.Type.Function);  l.next(); break;
				case Token.Namespace: addConstraint(MDValue.Type.Namespace); l.next(); break;

				case Token.Object:
					l.next();

					addConstraint(MDValue.Type.Object);

					if(l.type == Token.LParen)
					{
						l.next();
						objTypes ~= parseExpression();
						l.expect(Token.RParen);
					}
					else if(l.type == Token.Ident)
					{
						auto t = l.expect(Token.Ident);
						
						if(l.type == Token.Dot)
						{
							addConstraint(MDValue.Type.Object);
							objTypes ~= parseIdentList(t);
						}
						else
						{
							addConstraint(MDValue.Type.Object);
							objTypes ~= new(c) IdentExp(c, new(c) Identifier(c, t.loc, t.stringValue));
						}
					}
					else
						l.expected("object type");

					break;
				
				default:
					auto t = l.expect(Token.Ident);

					if(l.type == Token.Dot)
					{
						addConstraint(MDValue.Type.Object);
						objTypes ~= parseIdentList(t);
					}
					else
					{
						switch(t.stringValue)
						{
							case "bool":      addConstraint(MDValue.Type.Bool); break;
							case "int":       addConstraint(MDValue.Type.Int); break;
							case "float":     addConstraint(MDValue.Type.Float); break;
							case "char":      addConstraint(MDValue.Type.Char); break;
							case "string":    addConstraint(MDValue.Type.String); break;
							case "table":     addConstraint(MDValue.Type.Table); break;
							case "array":     addConstraint(MDValue.Type.Array); break;
							case "thread":    addConstraint(MDValue.Type.Thread); break;
							case "nativeobj": addConstraint(MDValue.Type.NativeObj); break;

							default:
								addConstraint(MDValue.Type.Object);
								objTypes ~= new(c) IdentExp(c, new(c) Identifier(c, t.loc, t.stringValue));
								break;
						}
					}
					break;
			}
		}

		if(l.type == Token.Not)
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
		objectTypes = objTypes.toArray();
		return ret;
	}

	/**
	Parse a simple function declaration.  This is basically a function declaration without
	any preceding 'local' or 'global'.  The function must have a name.
	*/
	public FuncDef parseSimpleFuncDef(TableCtorExp attrs = null)
	{
		auto location = l.expect(Token.Function).loc;
		auto name = parseIdentifier();
		return parseFuncBody(location, name, attrs);
	}
	
	/**
	Parse a function literal.  The name is optional, and one will be autogenerated for the
	function if none exists.
	*/
	public FuncDef parseFuncLiteral()
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
	Parse a Haskell-style function literal, like "\f -> f + 1" or "\(a, b) -> a(b)".
	*/
	public FuncDef parseHaskellFuncLiteral()
	{
		auto location = l.expect(Token.Backslash).loc;
		auto name = dummyFuncLiteralName(location);

		bool isVararg;
		auto params = parseFuncParams(isVararg);

		l.expect(Token.Arrow);

		Statement code;

		{
			scope dummy = new List!(Expression)(c.alloc);
			dummy ~= parseExpression();
			auto arr = dummy.toArray();

			code = new(c) ReturnStmt(c, arr[0].location, arr[0].endLocation, arr);
		}

		return new(c) FuncDef(c, location, name, params, isVararg, code, null);
	}

	/**
	Parse an object declaration, optional protection included.

	Params:
		attrs = An optional attribute table to attach to the declaration.
	*/
	public ObjectDecl parseObjectDecl(TableCtorExp attrs = null)
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

		return new(c) ObjectDecl(c, location, protection, parseObjectDef(false, attrs));
	}
	
	/**
	Parse an object definition.  
	
	Params:
		nameOptional = If true, the name is optional (such as with object literal expressions).
			Otherwise, the name is required (such as with object declarations).
		attrs = An optional attribute table to associate with the object.  This is here
			because an attribute table must first be parsed before the compiler can determine
			what kind of declaration follows it.

	Returns:
		An instance of ObjectDef.
	*/
	public ObjectDef parseObjectDef(bool nameOptional, TableCtorExp attrs = null)
	{
		auto location = l.expect(Token.Object).loc;

		Identifier name;

		if(!nameOptional || l.type == Token.Ident)
			name = parseIdentifier();

		Expression baseObject;

		if(l.type == Token.Colon)
		{
			l.next();
			baseObject = parseExpression();
		}
		else
			baseObject = new(c) IdentExp(c, new(c) Identifier(c, l.loc, c.newString("Object")));

		l.expect(Token.LBrace);

		auto fieldMap = newTable(c.thread);

		scope(exit)
			pop(c.thread);

		alias ObjectDef.Field Field;
		scope fields = new List!(Field)(c.alloc);

		void addField(Identifier name, Expression v)
		{
			pushString(c.thread, name.name);

			if(opin(c.thread, -1, fieldMap))
			{
				pop(c.thread);
				c.exception(name.location, "Redeclaration of field '{}'", name.name);
			}

			pushBool(c.thread, true);
			idxa(c.thread, fieldMap);
			fields ~= Field(name.name, v);
		}

		void addMethod(FuncDef m)
		{
			addField(m.name, new(c) FuncLiteralExp(c, m.location, m));
		}

		while(l.type != Token.RBrace)
		{
			switch(l.type)
			{
				case Token.LAttr:
					auto attr = parseAttrTable();
					addMethod(parseSimpleFuncDef(attr));
					break;

				case Token.Function:
					addMethod(parseSimpleFuncDef());
					break;

				case Token.Ident:
					auto id = parseIdentifier();

					Expression v;

					if(l.type == Token.Assign)
					{
						l.next();
						v = parseExpression();
					}
					else
						v = new(c) NullExp(c, id.location);

					l.statementTerm();
					addField(id, v);
					break;

				case Token.EOF:
					c.eofException(location, "Object is missing its closing brace");

				default:
					l.expected("Object method or field");
			}
		}

		auto endLocation = l.expect(Token.RBrace).loc;
		return new(c) ObjectDef(c, location, endLocation, name, baseObject, fields.toArray(), attrs);
	}

	/**
	Parse a namespace declaration, optional protection included.

	Params:
		attrs = An optional attribute table to attach to the namespace.
	*/
	public NamespaceDecl parseNamespaceDecl(TableCtorExp attrs = null)
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

		return new(c) NamespaceDecl(c, location, protection, parseNamespaceDef(attrs));
	}
	
	/**
	Parse a namespace.  Both literals and declarations require a name.
	
	Params:
		attrs = The optional attribute table to attach to this namespace.

	Returns:
		An instance of this class.
	*/
	public NamespaceDef parseNamespaceDef(TableCtorExp attrs = null)
	{
		auto location = l.loc;
		l.expect(Token.Namespace);

		auto name = parseIdentifier();
		Expression parent;

		if(l.type == Token.Colon)
		{
			l.next();
			parent = parseExpression();
		}

		l.expect(Token.LBrace);

		auto fieldMap = newTable(c.thread);

		scope(exit)
			pop(c.thread);

		alias NamespaceDef.Field Field;
		scope fields = new List!(Field)(c.alloc);

		void addField(dchar[] name, Expression v)
		{
			pushString(c.thread, name);

			if(opin(c.thread, -1, fieldMap))
			{
				pop(c.thread);
				c.exception(v.location, "Redeclaration of member '{}'", name);
			}

			pushBool(c.thread, true);
			idxa(c.thread, fieldMap);
			fields ~= Field(name, v);
		}

		while(l.type != Token.RBrace)
		{
			switch(l.type)
			{
				case Token.Function:
					auto fd = parseSimpleFuncDef();
					addField(fd.name.name, new(c) FuncLiteralExp(c, fd.location, fd));
					break;

				case Token.Ident:
					auto loc = l.loc;
					auto fieldName = parseName();

					Expression v;

					if(l.type == Token.Assign)
					{
						l.next();
						v = parseExpression();
					}
					else
						v = new(c) NullExp(c, loc);

					l.statementTerm();
					addField(fieldName, v);
					break;

				case Token.EOF:
					c.eofException(location, "Namespace is missing its closing brace");

				default:
					l.expected("Namespace member");
			}
		}


		auto endLocation = l.expect(Token.RBrace).loc;
		return new(c) NamespaceDef(c, location, endLocation, name, parent, fields.toArray(), attrs);
	}

	/**
	*/
	public BlockStmt parseBlockStmt()
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
	public AssertStmt parseAssertStmt()
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
	public BreakStmt parseBreakStmt()
	{
		auto location = l.expect(Token.Break).loc;
		l.statementTerm();
		return new(c) BreakStmt(c, location);
	}

	/**
	*/
	public ContinueStmt parseContinueStmt()
	{
		auto location = l.expect(Token.Continue).loc;
		l.statementTerm();
		return new(c) ContinueStmt(c, location);
	}

	/**
	*/
	public DoWhileStmt parseDoWhileStmt()
	{
		auto location = l.expect(Token.Do).loc;
		auto doBody = parseStatement(false);

		l.expect(Token.While);
		l.expect(Token.LParen);

		auto condition = parseExpression();
		auto endLocation = l.expect(Token.RParen).loc;
		return new(c) DoWhileStmt(c, location, endLocation, doBody, condition);
	}

	/**
	This function will actually parse both C-style and numeric for loops.  The return value
	can be either one.
	*/
	public Statement parseForStmt()
	{
		auto location = l.expect(Token.For).loc;
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
			return new(c) ForNumStmt(c, location, index, lo, hi, step, code);
		}

		parseInitializer();

		while(l.type == Token.Comma)
		{
			l.next();
			parseInitializer();
		}

		l.expect(Token.Semicolon);

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
		return new(c) ForStmt(c, location, init.toArray(), condition, increment.toArray(), code);
	}
	
	/**
	*/
	public ForeachStmt parseForeachStmt()
	{
		auto location = l.expect(Token.Foreach).loc;
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

		l.expect(Token.Semicolon);

		scope container = new List!(Expression)(c.alloc);
		container ~= parseExpression();

		while(l.type == Token.Comma)
		{
			l.next();
			container ~= parseExpression();
		}

		if(container.length > 3)
			c.exception(location, "'foreach' may have a maximum of three container expressions");

		l.expect(Token.RParen);

		auto code = parseStatement();
		return new(c) ForeachStmt(c, location, indicesArr, container.toArray(), code);
	}

	/**
	*/
	public IfStmt parseIfStmt()
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
	public ImportStmt parseImportStmt()
	{
		auto location = l.loc;

		l.expect(Token.Import);

		Identifier importName;
		Expression expr;

		if(l.type == Token.Ident && l.peek.type == Token.Assign)
		{
			importName = parseIdentifier();
			l.next();
		}

		if(l.type == Token.LParen)
		{
			l.next();
			expr = parseExpression();
			l.expect(Token.RParen);
		}
		else
		{
			scope name = new List!(dchar)(c.alloc);

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

		scope symbols = new List!(Identifier)(c.alloc);
		scope symbolNames = new List!(Identifier)(c.alloc);

		void parseSelectiveImport()
		{
			auto id = parseIdentifier();

			if(l.type == Token.Assign)
			{
				l.next();
				symbolNames ~= id;
				symbols ~= parseIdentifier();
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
	public ReturnStmt parseReturnStmt()
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
			l.statementTerm();
			return new(c) ReturnStmt(c, location, endLocation, arr);
		}
	}
	
	/**
	*/
	public SwitchStmt parseSwitchStmt()
	{
		auto location = l.expect(Token.Switch).loc;
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
		return new(c) SwitchStmt(c, location, endLocation, condition, cases.toArray(), caseDefault);
	}

	/**
	*/
	public CaseStmt parseCaseStmt()
	{
		auto location = l.expect(Token.Case).loc;

		scope conditions = new List!(Expression)(c.alloc);
		conditions ~= parseExpression();

		while(l.type == Token.Comma)
		{
			l.next();
			conditions ~= parseExpression();
		}

		l.expect(Token.Colon);

		scope statements = new List!(Statement)(c.alloc);

		while(l.type != Token.Case && l.type != Token.Default && l.type != Token.RBrace)
			statements ~= parseStatement();

		auto endLocation = l.loc;

		auto code = new(c) ScopeStmt(c, new(c) BlockStmt(c, location, endLocation, statements.toArray()));
		return new(c) CaseStmt(c, location, endLocation, conditions.toArray(), code);
	}
	
	/**
	*/
	public DefaultStmt parseDefaultStmt()
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
	public ThrowStmt parseThrowStmt()
	{
		auto location = l.expect(Token.Throw).loc;
		auto exp = parseExpression();
		l.statementTerm();
		return new(c) ThrowStmt(c, location, exp);
	}

	/**
	*/
	public TryStmt parseTryStmt()
	{
		auto location = l.expect(Token.Try).loc;
		auto tryBody = new(c) ScopeStmt(c, parseStatement());

		Identifier catchVar;
		Statement catchBody;

		CompileLoc endLocation;

		if(l.type == Token.Catch)
		{
			l.next();
			l.expect(Token.LParen);

			catchVar = parseIdentifier();

			l.expect(Token.RParen);

			catchBody = new(c) ScopeStmt(c, parseStatement());
			endLocation = catchBody.endLocation;
		}

		Statement finallyBody;

		if(l.type == Token.Finally)
		{
			l.next();
			finallyBody = new(c) ScopeStmt(c, parseStatement());
			endLocation = finallyBody.endLocation;
		}

		if(catchBody is null && finallyBody is null)
			c.eofException(location, "Try statement must be followed by a catch, finally, or both");

		return new(c) TryStmt(c, location, endLocation, tryBody, catchVar, catchBody, finallyBody);
	}
	
	/**
	*/
	public WhileStmt parseWhileStmt()
	{
		auto location = l.expect(Token.While).loc;
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
		return new(c) WhileStmt(c, location, condVar, condition, code);
	}

	/**
	Parse any expression which can be executed as a statement, i.e. any expression which
	can have side effects, including assignments, function calls, yields, ?:, &&, and ||
	expressions.  The parsed expression is checked for side effects before being returned.
	*/
	public Statement parseStatementExpr()
	{
		auto location = l.loc;

		if(l.type == Token.Inc)
		{
			l.next();
			return new(c) IncStmt(c, location, location, parsePrimaryExp());
		}
		else if(l.type == Token.Dec)
		{
			l.next();
			return new(c) DecStmt(c, location, location, parsePrimaryExp());
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
		item on the left-hand-side.  Therefore this function parses everything $(I but)
		the first item on the left-hand-side.
	*/
	public AssignStmt parseAssignStmt(Expression firstLHS)
	{
		auto location = l.loc;

		scope lhs = new List!(Expression)(c.alloc);
		lhs ~= firstLHS;

		while(l.type == Token.Comma)
		{
			l.next();
			lhs ~= parsePrimaryExp();
		}

		l.expect(Token.Assign);

		auto rhs = parseExpression();
		return new(c) AssignStmt(c, location, rhs.endLocation, lhs.toArray(), rhs);
	}

	/**
	Parse a reflexive assignment.
	
	Params:
		exp1 = The left-hand-side of the assignment.  As with normal assignments, since
			you can't actually tell that something is an assignment until the LHS is
			at least parsed, this has to be passed as a parameter.
	*/
	public Statement parseOpAssignStmt(Expression exp1)
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
	public Expression parseExpression()
	{
		return parseCondExp();
	}
	
	/**
	Parse a conditional (?:) expression.

	Params:
		exp1 = Conditional expressions can occur as statements, in which case the first
			expression must be parsed in order to see what kind of expression it is.
			In this case, the first expression is passed in as a parameter.  Otherwise,
			it defaults to null and this function parses the first expression itself.
	*/
	public Expression parseCondExp(Expression exp1 = null)
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
			In this case, the first expression is passed in as a parameter.  Otherwise,
			it defaults to null and this function parses the first expression itself.
	*/
	public Expression parseOrOrExp(Expression exp1 = null)
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
			In this case, the first expression is passed in as a parameter.  Otherwise,
			it defaults to null and this function parses the first expression itself.
	*/
	public Expression parseAndAndExp(Expression exp1 = null)
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
	public Expression parseOrExp()
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
	public Expression parseXorExp()
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
	public Expression parseAndExp()
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
	Parse a comparison expression.  This is any of ==, !=, is, !is, <, <=, >, >=,
	<=>, as, in, and !in.
	*/
	public Expression parseCmpExp()
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
	public Expression parseShiftExp()
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
	public Expression parseAddExp()
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
	public Expression parseMulExp()
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
	Parse a unary expression.  This parses negation (-), not (!), complement (~),
	length (#), and coroutine expressions.  '#vararg' is also incidentally parsed.
	*/
	public Expression parseUnExp()
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

			case Token.Coroutine:
				l.next();
				exp = parseUnExp();
				exp = new(c) CoroutineExp(c, exp.endLocation, exp);
				break;

			default:
				exp = parsePrimaryExp();
				break;
		}

		return exp;
	}

	/**
	Parse a primary expression.  Will also parse any postfix expressions attached
	to the primary exps.
	*/
	public Expression parsePrimaryExp()
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
			case Token.Object:                 exp = parseObjectLiteralExp(); break;
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
	public IdentExp parseIdentExp()
	{
		return new(c) IdentExp(c, parseIdentifier());
	}
	
	/**
	*/
	public ThisExp parseThisExp()
	{
		with(l.expect(Token.This))
			return new(c) ThisExp(c, loc);
	}
	
	/**
	*/
	public NullExp parseNullExp()
	{
		with(l.expect(Token.Null))
			return new(c) NullExp(c, loc);
	}
	
	/**
	*/
	public BoolExp parseBoolExp()
	{
		auto loc = l.loc;

		if(l.type == Token.True)
			return new(c) BoolExp(c, loc, true);
		else
		{
			l.expect(Token.False);
			return new(c) BoolExp(c, loc, false);
		}
	}
	
	/**
	*/
	public VarargExp parseVarargExp()
	{
		with(l.expect(Token.Vararg))
			return new(c) VarargExp(c, loc);
	}
	
	/**
	*/
	public CharExp parseCharExp()
	{
		with(l.expect(Token.CharLiteral))
			return new(c) CharExp(c, loc, intValue);
	}
	
	/**
	*/
	public IntExp parseIntExp()
	{
		with(l.expect(Token.IntLiteral))
			return new(c) IntExp(c, loc, intValue);
	}
	
	/**
	*/
	public FloatExp parseFloatExp()
	{
		with(l.expect(Token.FloatLiteral))
			return new(c) FloatExp(c, loc, floatValue);
	}
	
	/**
	*/
	public StringExp parseStringExp()
	{
		with(l.expect(Token.StringLiteral))
			return new(c) StringExp(c, loc, stringValue);
	}
	
	/**
	*/
	public FuncLiteralExp parseFuncLiteralExp()
	{
		auto location = l.loc;
		auto def = parseFuncLiteral();
		return new(c) FuncLiteralExp(c, location, def);
	}
	
	/**
	*/
	public FuncLiteralExp parseHaskellFuncLiteralExp()
	{
		auto location = l.loc;
		auto def = parseHaskellFuncLiteral();
		return new(c) FuncLiteralExp(c, location, def);
	}
	
	/**
	*/
	public ObjectLiteralExp parseObjectLiteralExp()
	{
		auto location = l.loc;
		return new(c) ObjectLiteralExp(c, location, parseObjectDef(true));
	}
	
	/**
	Parse a parenthesized expression.
	*/
	public Expression parseParenExp()
	{
		auto location = l.expect(Token.LParen).loc;
		auto exp = parseExpression();
		auto endLocation = l.expect(Token.RParen).loc;
		return new(c) ParenExp(c, location, endLocation, exp);
	}

	/**
	*/
	public Expression parseTableCtorExp()
	{
		return parseTableImpl(false);
	}

	/**
	Parse an attribute table.  The only difference is the delimiters (</ /> instead
	of { }).
	*/
	public TableCtorExp parseAttrTable()
	{
		return cast(TableCtorExp)cast(void*)parseTableImpl(true);
	}
	
	/**
	*/
	public PrimaryExp parseArrayCtorExp()
	{
		auto location = l.expect(Token.LBracket).loc;

		scope values = new List!(Expression)(c.alloc);

		if(l.type != Token.RBracket)
		{
			auto exp = parseExpression();

			if(l.type == Token.For)
			{
				auto forComp = parseForComprehension();
				auto endLocation = l.expect(Token.RBracket).loc;
				return new(c) ArrayComprehension(c, location, endLocation, exp, forComp);
			}
			else
			{
				values ~= exp;

				while(l.type != Token.RBracket)
				{
					if(l.type == Token.Comma)
						l.next();

					values ~= parseExpression();
				}
			}
		}

		auto endLocation = l.expect(Token.RBracket).loc;
		return new(c) ArrayCtorExp(c, location, endLocation, values.toArray());
	}
	
	/**
	*/
	public NamespaceCtorExp parseNamespaceCtorExp()
	{
		auto location = l.loc;
		auto def = parseNamespaceDef();
		return new(c) NamespaceCtorExp(c, location, def);
	}
	
	/**
	*/
	public YieldExp parseYieldExp()
	{
		auto location = l.expect(Token.Yield).loc;
		l.expect(Token.LParen);

		Expression[] args;

		if(l.type != Token.RParen)
			args = parseArguments();

		auto endLocation = l.expect(Token.RParen).loc;
		return new(c) YieldExp(c, location, endLocation, args);
	}

	/**
	*/
	public SuperCallExp parseSuperCallExp()
	{
		auto location = l.expect(Token.Super).loc;

		Expression method;

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

		Expression[] args;
		CompileLoc endLocation;

		if(l.type == Token.LParen)
		{
			l.next();

			if(l.type != Token.RParen)
				args = parseArguments();

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

		return new(c) SuperCallExp(c, location, endLocation, method, args);
	}
	
	/**
	Parse a member exp (:a).  This is a shorthand expression for "this.a".  This
	also works with super (:super) and paren (:("a")) versions.
	*/
	public Expression parseMemberExp()
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
			return new(c) DotExp(c, new(c) ThisExp(c, loc), new(c) StringExp(c, endLoc, name));
		}
	}
	
	/**
	Parse a postfix expression.  This includes dot expressions (.ident, .super, and .(expr)),
	function calls, indexing, slicing, and vararg slicing.

	Params:
		exp = The expression to which the resulting postfix expression will be attached.
	*/
	public Expression parsePostfixExp(Expression exp)
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

					if(exp.as!(DotExp))
						exp = new(c) MethodCallExp(c, arr[$ - 1].endLocation, exp, null, arr);
					else
						exp = new(c) CallExp(c, arr[$ - 1].endLocation, exp, null, arr);
					continue;

				case Token.LParen:
					if(exp.endLocation.line != l.loc.line)
						c.exception(l.loc, "ambiguous left-paren (function call or beginning of new statement?)");

					l.next();

					Expression context;
					Expression[] args;

					if(l.type == Token.With)
					{
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

					auto endLocation = l.expect(Token.RParen).loc;

					if(exp.as!(DotExp))
						exp = new(c) MethodCallExp(c, endLocation, exp, context, args);
					else
						exp = new(c) CallExp(c, endLocation, exp, context, args);

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
	Parse a for comprehension.  Note that in the grammar, this actually includes an optional
	if comprehension and optional for comprehension after it, meaning that an entire array
	or table comprehension is parsed in one call.
	*/
	public ForComprehension parseForComprehension()
	{
		auto loc = l.expect(Token.For).loc;

		scope names = new List!(Identifier)(c.alloc);
		names ~= parseIdentifier();

		while(l.type == Token.Comma)
		{
			l.next();
			names ~= parseIdentifier();
		}

		l.expect(Token.In);

		auto exp = parseExpression();

		if(l.type == Token.DotDot)
		{
			if(names.length > 1)
				c.exception(loc, "Numeric for comprehension may only have one index");

			l.next();
			auto exp2 = parseExpression();

			Expression step;

			if(l.type == Token.Comma)
			{
				l.next();
				step = parseExpression();
			}
			else
				step = new(c) IntExp(c, l.loc, 1);

			IfComprehension ifComp;

			if(l.type == Token.If)
				ifComp = parseIfComprehension();

			ForComprehension forComp;

			if(l.type == Token.For)
				forComp = parseForComprehension();
				
			auto arr = names.toArray();
			auto name = arr[0];
			c.alloc.freeArray(arr);

			return new(c) ForNumComprehension(c, loc, name, exp, exp2, step, ifComp, forComp);
		}
		else
		{
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
				
			scope container = new List!(Expression)(c.alloc);
			container ~= exp;

			while(l.type == Token.Comma)
			{
				l.next();
				container ~= parseExpression();
			}

			if(container.length > 3)
				c.exception(container[0].location, "Too many expressions in container");

			IfComprehension ifComp;

			if(l.type == Token.If)
				ifComp = parseIfComprehension();

			ForComprehension forComp;

			if(l.type == Token.For)
				forComp = parseForComprehension();

			return new(c) ForeachComprehension(c, loc, namesArr, container.toArray(), ifComp, forComp);
		}
	}
	
	/**
	*/
	public IfComprehension parseIfComprehension()
	{
		auto loc = l.expect(Token.If).loc;
		auto condition = parseExpression();
		return new(c) IfComprehension(c, loc, condition);
	}

// ================================================================================================================================================
// Private
// ================================================================================================================================================

	private Expression parseTableImpl(bool isAttr)
	{
		auto location = l.loc;
		uint terminator;

		if(isAttr)
		{
			l.expect(Token.LAttr);
			terminator = Token.RAttr;
		}
		else
		{
			l.expect(Token.LBrace);
			terminator = Token.RBrace;
		}

		alias TableCtorExp.Field Field;
		scope fields = new List!(Field)(c.alloc);

		if(l.type != terminator)
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

			if(!isAttr && firstWasBracketed)
			{
				if(l.type == Token.For)
				{
					auto forComp = parseForComprehension();
					auto endLocation = l.expect(terminator).loc;
					
					auto dummy = fields.toArray();
					auto key = dummy[0].key;
					auto value = dummy[0].value;
					c.alloc.freeArray(dummy);

					return new(c) TableComprehension(c, location, endLocation, key, value, forComp);
				}
			}

			while(l.type != terminator)
			{
				if(l.type == Token.Comma)
					l.next();

				parseField();
			}
		}

		auto endLocation = l.expect(terminator).loc;
		return new(c) TableCtorExp(c, location, endLocation, fields.toArray());
	}

	private Identifier dummyForeachIndex(CompileLoc loc)
	{
		pushFormat(c.thread, "__dummy{}", dummyNameCounter++);
		auto str = c.newString(getString(c.thread, -1));
		pop(c.thread);
		return new(c) Identifier(c, loc, str);
	}
	
	private Identifier dummyFuncLiteralName(CompileLoc loc)
	{
		pushFormat(c.thread, "<literal at {}({}:{})>", loc.file, loc.line, loc.col);
		auto str = c.newString(getString(c.thread, -1));
		pop(c.thread);
		return new(c) Identifier(c, loc, str);
	}
}