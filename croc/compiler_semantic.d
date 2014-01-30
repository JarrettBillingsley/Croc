/******************************************************************************
This module contains an AST visitor which performs semantic analysis on a
parsed AST. Semantic analysis rewrites some language constructs in terms of
others, performs constant folding, and checks what little it can for
correctness.

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

module croc.compiler_semantic;

import tango.text.Util;

import croc.api_interpreter;
import croc.api_stack;
import croc.compiler_ast;
import croc.compiler_astvisitor;
import croc.compiler_types;
import croc.types;
import croc.utf;
import croc.utils;

scope class Semantic : IdentityVisitor
{
private:
	word[] mFinallyDepths;
	uword mDummyNameCounter = 0;

public:
	this(ICompiler c)
	{
		super(c);
		mFinallyDepths = c.alloc.allocArray!(word)(1);
	}

	~this()
	{
		c.alloc.freeArray(mFinallyDepths);
	}

	bool isTopLevel()
	{
		return mFinallyDepths.length == 1;
	}

	alias Visitor.visit visit;

	override Module visit(Module m)
	{
		m.statements = visit(m.statements);

		if(m.decorator)
			m.decorator = visit(m.decorator);

		return m;
	}

	FuncDef visitStatements(FuncDef d)
	{
		return visitFuncDef(d);
	}

	override FuncDef visit(FuncDef d)
	{
		c.alloc.resizeArray(mFinallyDepths, mFinallyDepths.length + 1);

		scope(exit)
			c.alloc.resizeArray(mFinallyDepths, mFinallyDepths.length - 1);

		return visitFuncDef(d);
	}

	void enterFinally()
	{
		mFinallyDepths[$ - 1]++;
	}

	void leaveFinally()
	{
		mFinallyDepths[$ - 1]--;
	}

	bool inFinally()
	{
		return mFinallyDepths[$ - 1] > 0;
	}

	FuncDef visitFuncDef(FuncDef d)
	{
		foreach(i, ref p; d.params)
		{
			if(p.customConstraint)
			{
				scope args = new List!(Expression)(c);
				args ~= new(c) IdentExp(p.name);
				p.customConstraint = new(c) CallExp(p.customConstraint.endLocation, p.customConstraint, null, args.toArray());
			}

			if(p.defValue is null)
				continue;

			p.defValue = visit(p.defValue);

			if(!p.defValue.isConstant)
				continue;

			CrocValue.Type type;

			if(p.defValue.isNull)
				type = CrocValue.Type.Null;
			else if(p.defValue.isBool)
				type = CrocValue.Type.Bool;
			else if(p.defValue.isInt)
				type = CrocValue.Type.Int;
			else if(p.defValue.isFloat)
				type = CrocValue.Type.Float;
			else if(p.defValue.isString)
				type = CrocValue.Type.String;
			else
				assert(false);

			if(!(p.typeMask & (1 << type)))
				c.semException(p.defValue.location, "Parameter {}: Default parameter of type '{}' is not allowed", i - 1, CrocValue.typeStrings[type]);
		}

		d.code = visit(d.code);

		scope extra = new List!(Statement)(c);

		foreach(ref p; d.params)
			if(p.defValue !is null)
				extra ~= new(c) CondAssignStmt(p.name.location, p.name.location, new(c) IdentExp(p.name), p.defValue);

		if(c.typeConstraints())
			extra ~= new(c) TypecheckStmt(d.code.location, d);

		if(extra.length > 0)
		{
			extra ~= d.code;
			auto arr = extra.toArray();
			d.code = new(c) BlockStmt(arr[0].location, arr[$ - 1].endLocation, arr);
		}

		return d;
	}

	override Statement visit(AssertStmt s)
	{
		if(!c.asserts())
			return new(c) BlockStmt(s.location, s.endLocation, null);

		s.cond = visit(s.cond);

		if(s.msg)
			s.msg = visit(s.msg);
		else
		{
			pushFormat(c.thread, "Assertion failure at {}({}:{})", s.location.file, s.location.line, s.location.col);
			auto str = c.newString(getString(c.thread, -1));
			pop(c.thread);
			s.msg = new(c) StringExp(s.location, str);
		}

		return s;
	}

	override Statement visit(ImportStmt s)
	{
		s.expr = visit(s.expr);

		if(s.expr.isConstant() && !s.expr.isString())
			c.semException(s.expr.location, "Import expression must evaluate to a string");

		// We rewrite import statements as function calls/local variable declarations. The rewrites work as follows:
		// import blah
		// 		modules.load("blah")
		// import blah as x
		// 		local x = modules.load("blah")
		// import blah: y, z
		// 		local y, z; { local __temp = modules.load("blah"); y = __temp.y; z = __temp.z }
		// import blah as x: y, z
		// 		local y, z; local x = modules.load("blah"); y = x.y; z = x.z

		// This does the actual loading of selective imports out of the source namespace.
		void doSelective(List!(Statement) stmts, Expression src)
		{
			foreach(i, sym; s.symbols)
			{
				scope lhs = new List!(Expression)(c);
				scope rhs = new List!(Expression)(c);
				lhs ~= new(c) IdentExp(s.symbolNames[i]);
				rhs ~= new(c) DotExp(src, new(c) StringExp(sym.location, sym.name));
				stmts ~= new(c) AssignStmt(sym.location, sym.endLocation, lhs.toArray(), rhs.toArray());
			}
		}

		// First we make the "modules.load(expr)" call.
		auto _modules = new(c) IdentExp(new(c) Identifier(s.location, c.newString("modules")));
		auto _load = new(c) StringExp(s.location, c.newString("load"));
		scope args = new List!(Expression)(c);
		args ~= s.expr;
		auto call = new(c) MethodCallExp(s.location, s.endLocation, _modules, _load, args.toArray(), false);

		// Now we make a list of statements.
		scope stmts = new List!(Statement)(c);

		// First we declare any selectively-imported symbols as locals
		if(s.symbols.length > 0)
			stmts ~= new(c) VarDecl(s.location, s.endLocation, Protection.Local, s.symbolNames, null);

		if(s.importName is null)
		{
			if(s.symbols.length == 0)
				stmts ~= new(c) ExpressionStmt(s.location, s.endLocation, call);
			else
			{
				// It's not renamed, but we have to get the namespace so we can fill in the selectively-imported symbols.
				scope stmts2 = new List!(Statement)(c);

				// First put the import into a temporary local.
				scope names = new List!(Identifier)(c);
				scope inits = new List!(Expression)(c);
				auto ident = new(c) Identifier(s.location, c.newString(InternalName!("tempimport")));
				names ~= ident;
				inits ~= call;
				stmts2 ~= new(c) VarDecl(s.location, s.endLocation, Protection.Local, names.toArray(), inits.toArray());

				// Now get all the fields out.
				doSelective(stmts2, new(c) IdentExp(ident));

				// Finally, we put all this in a scoped sub-block.
				stmts ~= new(c) ScopeStmt(new(c) BlockStmt(s.location, s.endLocation, stmts2.toArray()));
			}
		}
		else
		{
			// Renamed import. Just put it in a new local.
			scope names = new List!(Identifier)(c);
			scope inits = new List!(Expression)(c);
			names ~= s.importName;
			inits ~= call;
			stmts ~= new(c) VarDecl(s.location, s.endLocation, Protection.Local, names.toArray(), inits.toArray());

			// Do any selective imports
			if(s.symbols.length > 0)
				doSelective(stmts, new(c) IdentExp(s.importName));
		}

		// Wrap it all up in a (non-scoped) block.
		return new(c) BlockStmt(s.location, s.endLocation, stmts.toArray());
	}

	override ScopeStmt visit(ScopeStmt s)
	{
		s.statement = visit(s.statement);
		return s;
	}

	override ExpressionStmt visit(ExpressionStmt s)
	{
		s.expr = visit(s.expr);
		return s;
	}

	override VarDecl visit(VarDecl d)
	{
		foreach(ref init; d.initializer)
			init = visit(init);

		if(d.protection == Protection.Default)
			d.protection = isTopLevel() ? Protection.Global : Protection.Local;

		return d;
	}

	override Decorator visit(Decorator d)
	{
		d.func = visit(d.func);

		if(d.context)
			d.context = visit(d.context);

		foreach(ref a; d.args)
			a = visit(a);

		if(d.nextDec)
			d.nextDec = visit(d.nextDec);

		return d;
	}

	override FuncDecl visit(FuncDecl d)
	{
		if(d.protection == Protection.Default)
			d.protection = isTopLevel() ? Protection.Global : Protection.Local;

		d.def = visit(d.def);

		if(d.decorator !is null)
			d.decorator = visit(d.decorator);

		return d;
	}

	override ClassDecl visit(ClassDecl d)
	{
		if(d.protection == Protection.Default)
			d.protection = isTopLevel() ? Protection.Global : Protection.Local;

		if(d.decorator !is null)
			d.decorator = visit(d.decorator);

		if(d.baseClass)
			d.baseClass = visit(d.baseClass);

		foreach(ref field; d.fields)
			field.initializer = visit(field.initializer);

		return d;
	}

	override NamespaceDecl visit(NamespaceDecl d)
	{
		if(d.protection == Protection.Default)
			d.protection = isTopLevel() ? Protection.Global : Protection.Local;

		if(d.decorator !is null)
			d.decorator = visit(d.decorator);

		if(d.parent)
			visit(d.parent);

		foreach(ref field; d.fields)
			field.initializer = visit(field.initializer);

		return d;
	}

	override Statement visit(BlockStmt s)
	{
		alias TryCatchStmt.CatchClause CC;

		bool found = 0;
		uword i = 0;

		foreach(idx, ref stmt; s.statements)
		{
			stmt = visit(stmt);

			// Do we need to process a scope statement?
			auto ss = stmt.as!(ScopeActionStmt);

			if(ss is null)
				continue;

			found = true;
			i = idx;
			break;
		}

		if(!found)
			return s;

		auto ss = s.statements[i].as!(ScopeActionStmt);

		// Get all the statements that follow this scope statement.
		auto rest = s.statements[i + 1 .. $];

		if(rest.length == 0)
		{
			// If there are no more statements, the body of the scope statement will either always or never be run
			if(ss.type == ScopeActionStmt.Exit || ss.type == ScopeActionStmt.Success)
				s.statements[$ - 1] = ss.stmt;
			else
				s.statements = s.statements[0 .. $ - 1];

			return s;
		}

		// Have to rewrite the statements. Scope statements are just fancy ways of writing try-catch-finally blocks.
		auto tryBody = new(c) ScopeStmt(new(c) BlockStmt(rest[0].location, rest[$ - 1].endLocation, rest));
		Statement replacement;

		switch(ss.type)
		{
			case ScopeActionStmt.Exit:
				/*
				scope(exit) { ss.stmt }
				rest
				=>
				try { rest }
				finally { ss.stmt }
				*/
				replacement = visit(new(c) TryFinallyStmt(ss.location, ss.endLocation, tryBody, ss.stmt));
				break;

			case ScopeActionStmt.Success:
				/*
				scope(success) { ss.stmt }
				rest
				=>
				local __dummy = true
				try { rest }
				catch(__dummy2: Throwable) { __dummy = false; throw __dummy2 }
				finally { if(__dummy) ss.stmt }
				*/

				// local __dummy = true
				auto finishedVar = genDummyVar(ss.endLocation, InternalName!("scope{}"));
				auto finishedVarExp = new(c) IdentExp(finishedVar);
				Statement declStmt;
				{
					scope nameList = new List!(Identifier)(c);
					nameList ~= finishedVar;
					scope initializer = new List!(Expression)(c);
					initializer ~= new(c) BoolExp(ss.location, true);
					declStmt = new(c) VarDecl(ss.location, ss.location, Protection.Local, nameList.toArray(), initializer.toArray());
				}

				// catch(__dummy2: Throwable) { __dummy = false; throw __dummy2 }
				auto catchVar = genDummyVar(ss.location, InternalName!("scope{}"));
				TryCatchStmt catchStmt;
				{
					scope types = new List!(Expression)(c);
					types ~= new(c) IdentExp(new(c) Identifier(ss.location, c.newString("Throwable")));

					scope dummy = new List!(Statement)(c);
					// __dummy = false;
					scope lhs = new List!(Expression)(c);
					lhs ~= finishedVarExp;
					scope rhs = new List!(Expression)(c);
					rhs ~= new(c) BoolExp(ss.location, false);
					dummy ~= new(c) AssignStmt(ss.location, ss.location, lhs.toArray(), rhs.toArray());
					// throw __dummy2
					dummy ~= new(c) ThrowStmt(ss.stmt.location, new(c) IdentExp(catchVar), true);
					auto code = dummy.toArray();
					auto catchBody = new(c) ScopeStmt(new(c) BlockStmt(code[0].location, code[$ - 1].endLocation, code));

					scope catches = new List!(CC)(c);
					catches ~= CC(catchVar, types.toArray(), catchBody);

					catchStmt = new(c) TryCatchStmt(ss.location, ss.endLocation, tryBody, catches.toArray());
				}

				// finally { if(__dummy) ss.stmt }
				ScopeStmt finallyBody;
				{
					scope dummy = new List!(Statement)(c);
					// if(__dummy) ss.stmt
					dummy ~= new(c) IfStmt(ss.location, ss.endLocation, null, finishedVarExp, ss.stmt, null);
					auto code = dummy.toArray();
					finallyBody = new(c) ScopeStmt(new(c) BlockStmt(code[0].location, code[$ - 1].endLocation, code));
				}

				// Put it all together
				scope code = new List!(Statement)(c);
				code ~= declStmt;
				code ~= new(c) TryFinallyStmt(ss.location, ss.endLocation, catchStmt, finallyBody);
				auto codeArr = code.toArray();
				replacement = visit(new(c) ScopeStmt(new(c) BlockStmt(codeArr[0].location, codeArr[$ - 1].endLocation, codeArr)));
				break;

			case ScopeActionStmt.Failure:
				/*
				scope(failure) { ss.stmt }
				rest
				=>
				try { rest }
				catch(__dummy: Throwable) { ss.stmt; throw __dummy }
				*/
				auto catchVar = genDummyVar(ss.location, InternalName!("scope{}"));
				scope types = new List!(Expression)(c);
				types ~= new(c) IdentExp(new(c) Identifier(ss.location, c.newString("Throwable")));

				scope dummy = new List!(Statement)(c);
				dummy ~= ss.stmt;
				dummy ~= new(c) ThrowStmt(ss.stmt.endLocation, new(c) IdentExp(catchVar), true);
				auto catchCode = dummy.toArray();
				auto catchBody = new(c) ScopeStmt(new(c) BlockStmt(catchCode[0].location, catchCode[$ - 1].endLocation, catchCode));

				scope catches = new List!(CC)(c);
				catches ~= CC(catchVar, types.toArray(), catchBody);
				replacement = visit(new(c) TryCatchStmt(ss.location, ss.endLocation, tryBody, catches.toArray()));
				break;

			default: assert(false);
		}

		s.statements = s.statements[0 .. i + 1];
		s.statements[i] = replacement;
		return s;
	}

	override Statement visit(IfStmt s)
	{
		s.condition = visit(s.condition);
		s.ifBody = visit(s.ifBody);

		if(s.elseBody)
			s.elseBody = visit(s.elseBody);

		if(s.condition.isConstant)
		{
			if(s.condition.isTrue)
			{
				if(s.condVar is null)
					return new(c) ScopeStmt(s.ifBody);

				scope names = new List!(Identifier)(c);
				names ~= s.condVar.name;

				scope initializer = new List!(Expression)(c);
				initializer ~= s.condition;

				scope temp = new List!(Statement)(c);
				temp ~= new(c) VarDecl(s.condVar.location, s.condVar.endLocation, Protection.Local, names.toArray(), initializer.toArray());
				temp ~= s.ifBody;

				return new(c) ScopeStmt(new(c) BlockStmt(s.location, s.endLocation, temp.toArray()));
			}
			else
			{
				if(s.elseBody)
					return new(c) ScopeStmt(s.elseBody);
				else
					return new(c) BlockStmt(s.location, s.endLocation, null);
			}
		}

		return s;
	}

	override Statement visit(WhileStmt s)
	{
		s.condition = visit(s.condition);
		s.code = visit(s.code);

		if(s.condition.isConstant && !s.condition.isTrue)
			return new(c) BlockStmt(s.location, s.endLocation, null);

		return s;
	}

	override Statement visit(DoWhileStmt s)
	{
		s.code = visit(s.code);
		s.condition = visit(s.condition);
		// Jarrett, stop rewriting do-while statements with constant conditions. you did this before. it fucks up breaks/continues inside them. STOP IT.
		return s;
	}

	override Statement visit(ForStmt s)
	{
		foreach(ref i; s.init)
		{
			if(i.isDecl)
				i.decl = visit(i.decl);
			else
				i.stmt = visit(i.stmt);
		}

		if(s.condition)
			s.condition = visit(s.condition);

		foreach(ref inc; s.increment)
			inc = visit(inc);

		s.code = visit(s.code);

		if(s.condition && s.condition.isConstant)
		{
			if(s.condition.isTrue)
				s.condition = null;
			else
			{
				if(s.init.length > 0)
				{
					scope inits = new List!(Statement)(c);

					foreach(i; s.init)
					{
						if(i.isDecl)
							inits ~= i.decl;
						else
							inits ~= i.stmt;
					}

					return new(c) ScopeStmt(new(c) BlockStmt(s.location, s.endLocation, inits.toArray()));
				}
				else
					return new(c) BlockStmt(s.location, s.endLocation, null);
			}
		}

		return s;
	}

	override Statement visit(ForNumStmt s)
	{
		s.lo = visit(s.lo);
		s.hi = visit(s.hi);
		s.step = visit(s.step);

		if(s.lo.isConstant && !s.lo.isInt)
			c.semException(s.lo.location, "Low value of a numeric for loop must be an integer");

		if(s.hi.isConstant && !s.hi.isInt)
			c.semException(s.hi.location, "High value of a numeric for loop must be an integer");

		if(s.step.isConstant)
		{
			if(!s.step.isInt)
				c.semException(s.step.location, "Step value of a numeric for loop must be an integer");

			if(s.step.asInt() == 0)
				c.semException(s.step.location, "Step value of a numeric for loop may not be 0");
		}

		s.code = visit(s.code);
		return s;
	}

	override ForeachStmt visit(ForeachStmt s)
	{
		foreach(ref c; s.container)
			c = visit(c);

		s.code = visit(s.code);
		return s;
	}

	override SwitchStmt visit(SwitchStmt s)
	{
		s.condition = visit(s.condition);

		scope rangeCases = new List!(CaseStmt)(c);

		foreach(ref c; s.cases)
		{
			c = visit(c);

			if(c.highRange !is null && c.conditions[0].exp.isConstant && c.highRange.isConstant)
				rangeCases ~= c;
		}

		foreach(rc; rangeCases)
		{
			auto lo = rc.conditions[0].exp;
			auto hi = rc.highRange;

			// this might not work for ranges using absurdly large numbers. fuh.
			if((lo.isInt || lo.isFloat) && (hi.isInt || hi.isFloat))
			{
				auto loVal = lo.asFloat;
				auto hiVal = hi.asFloat;

				foreach(c2; s.cases)
				{
					if(rc is c2)
						continue;

					if(c2.highRange !is null)
					{
						auto lo2 = c2.conditions[0].exp;
						auto hi2 = c2.highRange;

						if((lo2.isConstant && hi2.isConstant) && (lo2.isInt || lo2.isFloat) && (hi2.isInt || hi2.isFloat))
						{
							auto lo2Val = lo2.asFloat;
							auto hi2Val = hi2.asFloat;

							if(loVal == lo2Val ||
								(loVal < lo2Val && (lo2Val - loVal) <= (hiVal - loVal)) ||
								(loVal > lo2Val && (loVal - lo2Val) <= (hi2Val - lo2Val)))
								c.semException(lo2.location, "case range overlaps range at {}({}:{})", lo.location.file, lo.location.line, lo.location.col);
						}
					}
					else
					{
						foreach(cond; c2.conditions)
						{
							if(cond.exp.isConstant &&
								(cond.exp.isInt && cond.exp.asInt >= loVal && cond.exp.asInt <= hiVal) ||
								(cond.exp.isFloat && cond.exp.asFloat >= loVal && cond.exp.asFloat <= hiVal))
								c.semException(cond.exp.location, "case value overlaps range at {}({}:{})", lo.location.file, lo.location.line, lo.location.col);
						}
					}
				}
			}
			else if(lo.isString && hi.isString)
			{
				auto loVal = lo.asString;
				auto hiVal = hi.asString;

				foreach(c2; s.cases)
				{
					if(rc is c2)
						continue;

					if(c2.highRange !is null)
					{
						auto lo2 = c2.conditions[0].exp;
						auto hi2 = c2.highRange;

						if((lo2.isConstant && hi2.isConstant) && (lo2.isString && hi2.isString))
						{
							auto lo2Val = lo2.asString;
							auto hi2Val = hi2.asString;

							if( (loVal >= lo2Val && loVal <= hi2Val) ||
								(hiVal >= lo2Val && hiVal <= hi2Val) ||
								(lo2Val >= loVal && lo2Val <= hiVal) ||
								(hi2Val >= loVal && hi2Val <= hiVal))
								c.semException(lo2.location, "case range overlaps range at {}({}:{})", lo.location.file, lo.location.line, lo.location.col);
						}
					}
					else
					{
						foreach(cond; c2.conditions)
						{
							if(cond.exp.isConstant && cond.exp.isString && cond.exp.asString >= loVal && cond.exp.asString <= hiVal)
								c.semException(cond.exp.location, "case value overlaps range at {}({}:{})", lo.location.file, lo.location.line, lo.location.col);
						}
					}
				}
			}
		}

		if(s.caseDefault)
			s.caseDefault = visit(s.caseDefault);

		return s;
	}

	override CaseStmt visit(CaseStmt s)
	{
		foreach(ref cond; s.conditions)
			cond.exp = visit(cond.exp);

		if(s.highRange)
		{
			s.highRange = visit(s.highRange);

			auto lo = s.conditions[0].exp;
			auto hi = s.highRange;

			if(lo.isConstant && hi.isConstant)
			{
				if(lo.isInt && hi.isInt)
				{
					if(lo.asInt > hi.asInt)
						c.semException(lo.location, "Invalid case range (low is greater than high)");
					else if(lo.asInt == hi.asInt)
						s.highRange = null;
				}
				else if((lo.isInt && hi.isFloat) || (lo.isFloat && hi.isInt) || (lo.isFloat && hi.isFloat))
				{
					if(lo.asFloat > hi.asFloat)
						c.semException(lo.location, "Invalid case range (low is greater than high)");
					else if(lo.asFloat == hi.asFloat)
						s.highRange = null;
				}
				else if(lo.isString && hi.isString)
				{
					if(lo.asString > hi.asString)
						c.semException(lo.location, "Invalid case range (low is greater than high)");
					else if(lo.asString == hi.asString)
						s.highRange = null;
				}
			}
		}

		s.code = visit(s.code);
		return s;
	}

	override DefaultStmt visit(DefaultStmt s)
	{
		s.code = visit(s.code);
		return s;
	}

	override ContinueStmt visit(ContinueStmt s)
	{
		if(inFinally())
			c.semException(s.location, "Continue statements are illegal inside finally blocks");

		return s;
	}

	override BreakStmt visit(BreakStmt s)
	{
		if(inFinally())
			c.semException(s.location, "Break statements are illegal inside finally blocks");

		return s;
	}

	override ReturnStmt visit(ReturnStmt s)
	{
		if(inFinally())
			c.semException(s.location, "Return statements are illegal inside finally blocks");

		foreach(ref exp; s.exprs)
			exp = visit(exp);

		return s;
	}

	override TryCatchStmt visit(TryCatchStmt s)
	{
		s.tryBody = visit(s.tryBody);

		foreach(ref c; s.catches)
		{
			foreach(ref e; c.exTypes)
				e = visit(e);

			c.catchBody = visit(c.catchBody);
		}

		/*
		Now we have to do some fancy transformation of the catch statements into a single statement that switches
		on the type of the caught exception.

		try
			...
		catch(e: E1)
			catch1()
		catch(f: E2|E3)
			catch2()

		=>

		try
			...
		catch(__catch0)
		{
			if(__catch0 as E1) { local e = __catch0; catch1() }
			else if(__catch0 as E2 || __catch0 as E3) { local f = __catch0; catch2() }
			else throw __catch0
		}
		*/

		// catch(__catch0)
		auto cvar = genDummyVar(s.catches[0].catchVar.location, InternalName!("catch{}"));
		auto cvarExp = new(c) IdentExp(cvar);
		s.hiddenCatchVar = cvar;

		// else throw __catch0
		Statement stmt = new(c) ThrowStmt(s.endLocation, cvarExp, true);

		// Doing it in reverse to make building it up easier.
		foreach_reverse(ref ca; s.catches)
		{
			// if(__catch0 as E2 || __catch0 as E3)
			Expression cond = new(c) AsExp(ca.catchVar.location, ca.catchVar.location, cvarExp, ca.exTypes[0]);

			foreach(type; ca.exTypes[1 .. $])
			{
				auto tmp = new(c) AsExp(ca.catchVar.location, ca.catchVar.location, cvarExp, type);
				cond = new(c) OrOrExp(ca.catchVar.location, ca.catchVar.location, cond, tmp);
			}

			scope code = new List!(Statement)(c);

			// local f = __catch0;
			scope nameList = new List!(Identifier)(c);
			nameList ~= ca.catchVar;
			scope initializer = new List!(Expression)(c);
			initializer ~= cvarExp;
			code ~= new(c) VarDecl(ca.catchVar.location, ca.catchVar.location, Protection.Local, nameList.toArray(), initializer.toArray());

			// catch2()
			code ~= ca.catchBody;

			// wrap it up
			auto ifCode = new(c) ScopeStmt(new(c) BlockStmt(ca.catchBody.location, ca.catchBody.endLocation, code.toArray()));
			stmt = new(c) IfStmt(ca.catchVar.location, stmt.endLocation, null, cond, ifCode, stmt);
		}

		s.transformedCatch = stmt;
		return s;
	}

	override TryFinallyStmt visit(TryFinallyStmt s)
	{
		s.tryBody = visit(s.tryBody);
		enterFinally();
		s.finallyBody = visit(s.finallyBody);
		leaveFinally();
		return s;
	}

	override ThrowStmt visit(ThrowStmt s)
	{
		s.exp = visit(s.exp);
		return s;
	}

	override ScopeActionStmt visit(ScopeActionStmt s)
	{
		if(s.type == ScopeActionStmt.Exit || s.type == ScopeActionStmt.Success)
		{
			enterFinally();
			s.stmt = visit(s.stmt);
			leaveFinally();
		}
		else
			s.stmt = visit(s.stmt);

		return s;
	}

	override AssignStmt visit(AssignStmt s)
	{
		foreach(ref exp; s.lhs)
			exp = visit(exp);

		foreach(ref exp; s.rhs)
			exp = visit(exp);

		return s;
	}

	OpAssignStmt visitOpAssign(OpAssignStmt s)
	{
		s.lhs = visit(s.lhs);
		s.rhs = visit(s.rhs);
		return s;
	}

	override AddAssignStmt visit(AddAssignStmt s)   { return cast(AddAssignStmt)visitOpAssign(s);  }
	override SubAssignStmt visit(SubAssignStmt s)   { return cast(SubAssignStmt)visitOpAssign(s);  }
	override MulAssignStmt visit(MulAssignStmt s)   { return cast(MulAssignStmt)visitOpAssign(s);  }
	override DivAssignStmt visit(DivAssignStmt s)   { return cast(DivAssignStmt)visitOpAssign(s);  }
	override ModAssignStmt visit(ModAssignStmt s)   { return cast(ModAssignStmt)visitOpAssign(s);  }
	override ShlAssignStmt visit(ShlAssignStmt s)   { return cast(ShlAssignStmt)visitOpAssign(s);  }
	override ShrAssignStmt visit(ShrAssignStmt s)   { return cast(ShrAssignStmt)visitOpAssign(s);  }
	override UShrAssignStmt visit(UShrAssignStmt s) { return cast(UShrAssignStmt)visitOpAssign(s); }
	override XorAssignStmt visit(XorAssignStmt s)   { return cast(XorAssignStmt)visitOpAssign(s);  }
	override OrAssignStmt visit(OrAssignStmt s)     { return cast(OrAssignStmt)visitOpAssign(s);   }
	override AndAssignStmt visit(AndAssignStmt s)   { return cast(AndAssignStmt)visitOpAssign(s);  }

	override Statement visit(CondAssignStmt s)
	{
		s.lhs = visit(s.lhs);
		s.rhs = visit(s.rhs);

		if(s.rhs.isConstant() && s.rhs.isNull())
			return new(c) BlockStmt(s.location, s.endLocation, null);

		return s;
	}

	override CatAssignStmt visit(CatAssignStmt s)
	{
		s.lhs = visit(s.lhs);
		s.rhs = visit(s.rhs);

		if(auto catExp = s.rhs.as!(CatExp))
		{
			s.operands = catExp.operands;
			catExp.operands = null;
		}
		else
		{
			scope dummy = new List!(Expression)(c);
			dummy ~= s.rhs;
			s.operands = dummy.toArray();
		}

		s.collapsed = true;
		return s;
	}

	override IncStmt visit(IncStmt s)
	{
		s.exp = visit(s.exp);
		return s;
	}

	override DecStmt visit(DecStmt s)
	{
		s.exp = visit(s.exp);
		return s;
	}

	override Expression visit(CondExp e)
	{
		e.cond = visit(e.cond);
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.cond.isConstant)
		{
			if(e.cond.isTrue())
				return e.op1;
			else
				return e.op2;
		}

		return e;
	}

	override Expression visit(OrOrExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant)
		{
			if(e.op1.isTrue())
				return e.op1;
			else
				return e.op2;
		}

		return e;
	}

	override Expression visit(AndAndExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant)
		{
			if(e.op1.isTrue())
				return e.op2;
			else
				return e.op1;
		}

		return e;
	}

	override Expression visit(OrExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(!e.op1.isInt || !e.op2.isInt)
				c.semException(e.location, "Bitwise Or must be performed on integers");

			return new(c) IntExp(e.location, e.op1.asInt() | e.op2.asInt());
		}

		return e;
	}

	override Expression visit(XorExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(!e.op1.isInt || !e.op2.isInt)
				c.semException(e.location, "Bitwise Xor must be performed on integers");

			return new(c) IntExp(e.location, e.op1.asInt() ^ e.op2.asInt());
		}

		return e;
	}

	override Expression visit(AndExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(!e.op1.isInt || !e.op2.isInt)
				c.semException(e.location, "Bitwise And must be performed on integers");

			return new(c) IntExp(e.location, e.op1.asInt() & e.op2.asInt());
		}

		return e;
	}

	Expression visitEquality(BaseEqualExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		bool isTrue = e.type == AstTag.EqualExp || e.type == AstTag.IsExp;

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(e.op1.isNull && e.op2.isNull)
				return new(c) BoolExp(e.location, isTrue);

			if(e.op1.isBool && e.op2.isBool)
				return new(c) BoolExp(e.location, isTrue ? e.op1.asBool() == e.op2.asBool() : e.op1.asBool() != e.op2.asBool());

			if(e.op1.isInt && e.op2.isInt)
				return new(c) BoolExp(e.location, isTrue ? e.op1.asInt() == e.op2.asInt() : e.op1.asInt() != e.op2.asInt());

			if(e.type == AstTag.IsExp || e.type == AstTag.NotIsExp)
			{
				if(e.op1.isFloat && e.op2.isFloat)
					return new(c) BoolExp(e.location, isTrue ? e.op1.asFloat() == e.op2.asFloat() : e.op1.asFloat() != e.op2.asFloat());
			}
			else
			{
				if((e.op1.isInt || e.op1.isFloat) && (e.op2.isInt || e.op2.isFloat))
					return new(c) BoolExp(e.location, isTrue ? e.op1.asFloat() == e.op2.asFloat() : e.op1.asFloat() != e.op2.asFloat());
			}

			if(e.op1.isString && e.op2.isString)
				return new(c) BoolExp(e.location, isTrue ? e.op1.asString() == e.op2.asString() : e.op1.asString() != e.op2.asString());

			if(e.type == AstTag.IsExp || e.type == AstTag.NotIsExp)
				return new(c) BoolExp(e.location, !isTrue);
			else
				c.semException(e.location, "Cannot compare different types");
		}

		return e;
	}

	override Expression visit(EqualExp e)    { return visitEquality(e); }
	override Expression visit(NotEqualExp e) { return visitEquality(e); }
	override Expression visit(IsExp e)       { return visitEquality(e); }
	override Expression visit(NotIsExp e)    { return visitEquality(e); }

	word commonCompare(Expression op1, Expression op2)
	{
		word cmpVal = void;

		if(op1.isNull && op2.isNull)
			cmpVal = 0;
		else if(op1.isInt && op2.isInt)
			cmpVal = Compare3(op1.asInt(), op2.asInt());
		else if((op1.isInt || op1.isFloat) && (op2.isInt || op2.isFloat))
			cmpVal = Compare3(op1.asFloat(), op2.asFloat());
		else if(op1.isString && op2.isString)
			cmpVal = scmp(op1.asString(), op2.asString());
		else
			c.semException(op1.location, "Invalid compile-time comparison");

		return cmpVal;
	}

	Expression visitComparison(BaseCmpExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			auto cmpVal = commonCompare(e.op1, e.op2);

			switch(e.type)
			{
				case AstTag.LTExp: return new(c) BoolExp(e.location, cmpVal < 0);
				case AstTag.LEExp: return new(c) BoolExp(e.location, cmpVal <= 0);
				case AstTag.GTExp: return new(c) BoolExp(e.location, cmpVal > 0);
				case AstTag.GEExp: return new(c) BoolExp(e.location, cmpVal >= 0);
				default: assert(false, "BaseCmpExp fold");
			}
		}

		return e;
	}

	override Expression visit(LTExp e) { return visitComparison(e); }
	override Expression visit(LEExp e) { return visitComparison(e); }
	override Expression visit(GTExp e) { return visitComparison(e); }
	override Expression visit(GEExp e) { return visitComparison(e); }

	override Expression visit(Cmp3Exp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
			return new(c) IntExp(e.location, commonCompare(e.op1, e.op2));

		return e;
	}

	override AsExp visit(AsExp e)
	{
		if(e.op1.isConstant() || e.op2.isConstant())
			c.semException(e.location, "Neither argument of an 'as' expression may be a constant");

		return e;
	}

	override Expression visit(InExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant && e.op2.isString)
		{
			auto s = e.op2.asString;

			if(e.op1.isString)
				return new(c) BoolExp(e.location, s.locatePattern(e.op1.asString()) != s.length);
			else
				c.semException(e.location, "'in' must be performed on a string with a string");
		}

		return e;
	}

	override Expression visit(NotInExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant && e.op2.isString)
		{
			auto s = e.op2.asString;

			if(e.op1.isString)
				return new(c) BoolExp(e.location, s.locatePattern(e.op1.asString()) == s.length);
			else
				c.semException(e.location, "'!in' must be performed on a string with a string");
		}

		return e;
	}

	override Expression visit(ShlExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(!e.op1.isInt || !e.op2.isInt)
				c.semException(e.location, "Bitwise left-shift must be performed on integers");

			return new(c) IntExp(e.location, e.op1.asInt() << e.op2.asInt());
		}

		return e;
	}

	override Expression visit(ShrExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(!e.op1.isInt || !e.op2.isInt)
				c.semException(e.location, "Bitwise right-shift must be performed on integers");

			return new(c) IntExp(e.location, e.op1.asInt() >> e.op2.asInt());
		}

		return e;
	}

	override Expression visit(UShrExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(!e.op1.isInt || !e.op2.isInt)
				c.semException(e.location, "Bitwise unsigned right-shift must be performed on integers");

			return new(c) IntExp(e.location, e.op1.asInt() >>> e.op2.asInt());
		}

		return e;
	}

	override Expression visit(AddExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(e.op1.isInt && e.op2.isInt)
				return new(c) IntExp(e.location, e.op1.asInt() + e.op2.asInt());
			else if((e.op1.isInt || e.op1.isFloat) && (e.op2.isInt || e.op2.isFloat))
				return new(c) FloatExp(e.location, e.op1.asFloat() + e.op2.asFloat());
			else
				c.semException(e.location, "Addition must be performed on numbers");
		}

		return e;
	}

	override Expression visit(SubExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(e.op1.isInt && e.op2.isInt)
				return new(c) IntExp(e.location, e.op1.asInt() - e.op2.asInt());
			else if((e.op1.isInt || e.op1.isFloat) && (e.op2.isInt || e.op2.isFloat))
				return new(c) FloatExp(e.location, e.op1.asFloat() - e.op2.asFloat());
			else
				c.semException(e.location, "Subtraction must be performed on numbers");
		}

		return e;
	}

	override Expression visit(CatExp e)
	{
		if(e.collapsed)
			return e;

		e.collapsed = true;

		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		// Collapse
		{
			scope tmp = new List!(Expression)(c);

			if(auto l = e.op1.as!(CatExp))
				tmp ~= l.operands;
			else
				tmp ~= e.op1;

			// Not needed?  e.operands should be empty
			//tmp ~= e.operands;
			tmp ~= e.op2;

			e.operands = tmp.toArray();
			e.endLocation = e.operands[$ - 1].endLocation;
		}

		// Const fold
		scope newOperands = new List!(Expression)(c);
		scope tempStr = new List!(char, 64)(c);

		auto ops = e.operands;

		for(word i = 0; i < ops.length; i++)
		{
			// this first case can only happen when the last item in the array can't be folded. otherwise i will be set to ops.length - 1,
			// incremented, and the loop will break.
			if(i == ops.length - 1)
				newOperands ~= ops[i];
			else if(ops[i].isConstant && ops[i + 1].isConstant)
			{
				if(ops[i].isString && ops[i + 1].isString)
				{
					word j = i + 2;

					for(; j < ops.length && ops[j].isString; j++)
					{}

					// j points to first non-const non-string non-char operand
					foreach(op; ops[i .. j])
						tempStr ~= op.asString();

					auto dat = tempStr.toArray();
					auto str = c.newString(dat);
					newOperands ~= new(c) StringExp(e.location, str);

					i = j - 1;
				}
				else
					newOperands ~= ops[i];
			}
			else
				newOperands ~= ops[i];
		}

		if(newOperands.length == 1)
			return newOperands[0]; // depends on List storing its data on the stack..
		else
		{
			e.operands = newOperands.toArray();
			return e;
		}
	}

	override Expression visit(MulExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(e.op1.isInt && e.op2.isInt)
				return new(c) IntExp(e.location, e.op1.asInt() * e.op2.asInt());
			else if((e.op1.isInt || e.op1.isFloat) && (e.op2.isInt || e.op2.isFloat))
				return new(c) FloatExp(e.location, e.op1.asFloat() * e.op2.asFloat());
			else
				c.semException(e.location, "Multiplication must be performed on numbers");
		}

		return e;
	}

	override Expression visit(DivExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(e.op1.isInt && e.op2.isInt)
			{
				if(e.op2.asInt() == 0)
					c.semException(e.location, "Division by 0");

				return new(c) IntExp(e.location, e.op1.asInt() / e.op2.asInt());
			}
			else if((e.op1.isInt || e.op1.isFloat) && (e.op2.isInt || e.op2.isFloat))
				return new(c) FloatExp(e.location, e.op1.asFloat() / e.op2.asFloat());
			else
				c.semException(e.location, "Division must be performed on numbers");
		}

		return e;
	}

	override Expression visit(ModExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(e.op1.isInt && e.op2.isInt)
			{
				if(e.op2.asInt() == 0)
					c.semException(e.location, "Modulo by 0");

				return new(c) IntExp(e.location, e.op1.asInt() % e.op2.asInt());
			}
			else if((e.op1.isInt || e.op1.isFloat) && (e.op2.isInt || e.op2.isFloat))
				return new(c) FloatExp(e.location, e.op1.asFloat() % e.op2.asFloat());
			else
				c.semException(e.location, "Modulo must be performed on numbers");
		}

		return e;
	}

	override Expression visit(NegExp e)
	{
		e.op = visit(e.op);

		if(e.op.isConstant)
		{
			if(auto ie = e.op.as!(IntExp))
			{
				ie.value = -ie.value;
				return ie;
			}
			else if(auto fe = e.op.as!(FloatExp))
			{
				fe.value = -fe.value;
				return fe;
			}
			else
				c.semException(e.location, "Negation must be performed on numbers");
		}

		return e;
	}

	override Expression visit(NotExp e)
	{
		e.op = visit(e.op);

		if(e.op.isConstant)
			return new(c) BoolExp(e.location, !e.op.isTrue);

		switch(e.op.type)
		{
			case AstTag.LTExp:       auto old = e.op.as!(LTExp);       return new(c) GEExp(e.location, e.endLocation, old.op1, old.op2);
			case AstTag.LEExp:       auto old = e.op.as!(LEExp);       return new(c) GTExp(e.location, e.endLocation, old.op1, old.op2);
			case AstTag.GTExp:       auto old = e.op.as!(GTExp);       return new(c) LEExp(e.location, e.endLocation, old.op1, old.op2);
			case AstTag.GEExp:       auto old = e.op.as!(GEExp);       return new(c) LTExp(e.location, e.endLocation, old.op1, old.op2);
			case AstTag.EqualExp:    auto old = e.op.as!(EqualExp);    return new(c) NotEqualExp(e.location, e.endLocation, old.op1, old.op2);
			case AstTag.NotEqualExp: auto old = e.op.as!(NotEqualExp); return new(c) EqualExp(e.location, e.endLocation, old.op1, old.op2);
			case AstTag.IsExp:       auto old = e.op.as!(IsExp);       return new(c) NotIsExp(e.location, e.endLocation, old.op1, old.op2);
			case AstTag.NotIsExp:    auto old = e.op.as!(NotIsExp);    return new(c) IsExp(e.location, e.endLocation, old.op1, old.op2);
			case AstTag.InExp:       auto old = e.op.as!(InExp);       return new(c) NotInExp(e.location, e.endLocation, old.op1, old.op2);
			case AstTag.NotInExp:    auto old = e.op.as!(NotInExp);    return new(c) InExp(e.location, e.endLocation, old.op1, old.op2);

			case AstTag.AndAndExp:
				auto old = e.op.as!(AndAndExp);
				auto op1 = visit(new(c) NotExp(old.op1.location, old.op1));
				auto op2 = visit(new(c) NotExp(old.op2.location, old.op2));
				return new(c) OrOrExp(e.location, e.endLocation, op1, op2);

			case AstTag.OrOrExp:
				auto old = e.op.as!(OrOrExp);
				auto op1 = visit(new(c) NotExp(old.op1.location, old.op1));
				auto op2 = visit(new(c) NotExp(old.op2.location, old.op2));
				return new(c) AndAndExp(e.location, e.endLocation, op1, op2);

			// TODO: what about multiple 'not's?  "!!x"

			default:
				break;
		}

		return e;
	}

	override Expression visit(ComExp e)
	{
		e.op = visit(e.op);

		if(e.op.isConstant)
		{
			if(auto ie = e.op.as!(IntExp))
			{
				ie.value = ~ie.value;
				return ie;
			}
			else
				c.semException(e.location, "Bitwise complement must be performed on integers");
		}

		return e;
	}

	override Expression visit(LenExp e)
	{
		e.op = visit(e.op);

		if(e.op.isConstant)
		{
			if(e.op.isString)
				return new(c) IntExp(e.location, e.op.asString().length);
			else
				c.semException(e.location, "Length must be performed on a string at compile time");
		}

		return e;
	}

	override Expression visit(DotExp e)
	{
		e.op = visit(e.op);
		e.name = visit(e.name);

		if(e.name.isConstant && !e.name.isString)
			c.semException(e.name.location, "Field name must be a string");

		return e;
	}

	override Expression visit(DotSuperExp e)
	{
		e.op = visit(e.op);
		return e;
	}

	override Expression visit(MethodCallExp e)
	{
		if(e.op)
			e.op = visit(e.op);

		e.method = visit(e.method);

		if(e.method.isConstant && !e.method.isString)
			c.semException(e.method.location, "Method name must be a string");

		foreach(ref arg; e.args)
			arg = visit(arg);

		return e;
	}

	override Expression visit(CallExp e)
	{
		e.op = visit(e.op);

		if(e.context)
			e.context = visit(e.context);

		foreach(ref arg; e.args)
			arg = visit(arg);

		return e;
	}

	override Expression visit(IndexExp e)
	{
		e.op = visit(e.op);
		e.index = visit(e.index);

		if(e.op.isConstant && e.index.isConstant)
		{
			if(!e.op.isString || !e.index.isInt)
				c.semException(e.location, "Can only index strings with integers at compile time");

			auto str = e.op.asString();
			auto strLen = fastUtf8CPLength(str);
			auto idx = e.index.asInt();

			if(idx < 0)
				idx += strLen;

			if(idx < 0 || idx >= strLen)
				c.semException(e.location, "Invalid string index");

			auto offs = utf8CPIdxToByte(str, cast(uword)idx);
			auto len = utf8SequenceLength(str[offs]);
			return new(c) StringExp(e.location, c.newString(str[offs .. offs + len]));
		}

		return e;
	}

	override Expression visit(VargIndexExp e)
	{
		e.index = visit(e.index);

		if(e.index.isConstant && !e.index.isInt)
			c.semException(e.index.location, "index of a vararg indexing must be an integer");

		return e;
	}

	override Expression visit(SliceExp e)
	{
		e.op = visit(e.op);
		e.loIndex = visit(e.loIndex);
		e.hiIndex = visit(e.hiIndex);

		if(e.op.isConstant && e.loIndex.isConstant && e.hiIndex.isConstant)
		{
			if(!e.op.isString || (!e.loIndex.isInt && !e.loIndex.isNull) || (!e.hiIndex.isInt && !e.hiIndex.isNull))
				c.semException(e.location, "Can only slice strings with integers at compile time");

			auto str = e.op.asString();
			crocint l, h;

			if(e.loIndex.isInt)
				l = e.loIndex.asInt();
			else
				l = 0;

			if(e.hiIndex.isInt)
				h = e.hiIndex.asInt();
			else
				h = str.length;

			if(l < 0)
				l += str.length;

			if(h < 0)
				h += str.length;

			if(l > h || l < 0 || l > str.length || h < 0 || h > str.length)
				c.semException(e.location, "Invalid slice indices");

			return new(c) StringExp(e.location, c.newString(str[cast(uword)l .. cast(uword)h]));
		}

		return e;
	}

	override Expression visit(VargSliceExp e)
	{
		e.loIndex = visit(e.loIndex);
		e.hiIndex = visit(e.hiIndex);

		if(e.loIndex.isConstant && !(e.loIndex.isNull || e.loIndex.isInt))
			c.semException(e.loIndex.location, "low index of vararg slice must be null or int");

		if(e.hiIndex.isConstant && !(e.hiIndex.isNull || e.hiIndex.isInt))
			c.semException(e.hiIndex.location, "high index of vararg slice must be null or int");

		return e;
	}

	override FuncLiteralExp visit(FuncLiteralExp e)
	{
		e.def = visit(e.def);
		return e;
	}

	override Expression visit(ParenExp e)
	{
		e.exp = visit(e.exp);

		if(e.exp.isMultRet())
			return e;
		else
			return e.exp;
	}

	override TableCtorExp visit(TableCtorExp e)
	{
		foreach(ref field; e.fields)
		{
			field.key = visit(field.key);
			field.value = visit(field.value);
		}

		return e;
	}

	override ArrayCtorExp visit(ArrayCtorExp e)
	{
		foreach(ref value; e.values)
			value = visit(value);

		return e;
	}

	override YieldExp visit(YieldExp e)
	{
		foreach(ref arg; e.args)
			arg = visit(arg);

		return e;
	}

	override TableComprehension visit(TableComprehension e)
	{
		e.key = visit(e.key);
		e.value = visit(e.value);
		e.forComp = visitForComp(e.forComp);
		return e;
	}

	override Expression visit(ArrayComprehension e)
	{
		e.exp = visit(e.exp);
		e.forComp = visitForComp(e.forComp);
		return e;
	}

	ForComprehension visitForComp(ForComprehension e)
	{
		if(auto x = e.as!(ForeachComprehension))
			return visit(x);
		else
		{
			auto x = e.as!(ForNumComprehension);
			assert(x !is null);
			return visit(x);
		}
	}

	override ForeachComprehension visit(ForeachComprehension e)
	{
		foreach(ref exp; e.container)
			exp = visit(exp);

		if(e.ifComp)
			e.ifComp = visit(e.ifComp);

		if(e.forComp)
			e.forComp = visitForComp(e.forComp);

		return e;
	}

	override ForNumComprehension visit(ForNumComprehension e)
	{
		e.lo = visit(e.lo);
		e.hi = visit(e.hi);

		if(e.step)
			e.step = visit(e.step);

		if(e.ifComp)
			e.ifComp = visit(e.ifComp);

		if(e.forComp)
			e.forComp = visitForComp(e.forComp);

		return e;
	}

	override IfComprehension visit(IfComprehension e)
	{
		e.condition = visit(e.condition);
		return e;
	}

private:
	Identifier genDummyVar(CompileLoc loc, char[] fmt)
	{
		pushFormat(c.thread, fmt, mDummyNameCounter++);
		auto str = c.newString(getString(c.thread, -1));
		pop(c.thread);
		return new(c) Identifier(loc, str);
	}
}