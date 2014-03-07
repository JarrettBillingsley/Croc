
#include <math.h>

#include "croc/compiler/ast.hpp"
#include "croc/compiler/astvisitor.hpp"
#include "croc/compiler/semantic.hpp"
#include "croc/compiler/types.hpp"
#include "croc/types/base.hpp"
#include "croc/util/str.hpp"

#define VISIT(e)               do { e = visit(e);                     } while(false)
#define COND_VISIT(e)          do { if(e) e = visit(e);               } while(false)
#define VISIT_ARR(a)           do { for(auto &x: a) x = visit(x);     } while(false)
#define VISIT_ARR_FIELD(a, y)  do { for(auto &x: a) x.y = visit(x.y); } while(false)
#define PROTECTION(d)\
	do {\
		if(d->protection == Protection::Default)\
			d->protection = isTopLevel() ? Protection::Global : Protection::Local;\
	} while(false)

namespace croc
{
	bool Semantic::isTopLevel()
	{
		return mFinallyDepth->prev == nullptr;
	}

	void Semantic::enterFinally()
	{
		mFinallyDepth->depth++;
	}

	void Semantic::leaveFinally()
	{
		mFinallyDepth->depth--;
	}

	bool Semantic::inFinally()
	{
		return mFinallyDepth->depth > 0;
	}

	Module* Semantic::visit(Module* m)
	{
		FinallyDepth depth(0, mFinallyDepth);
		mFinallyDepth = &depth;
		VISIT(m->statements);
		COND_VISIT(m->decorator);
		mFinallyDepth = depth.prev;
		return m;
	}

	FuncDef* Semantic::visit(FuncDef* d)
	{
		FinallyDepth depth(0, mFinallyDepth);
		mFinallyDepth = &depth;
		auto ret = commonVisitFuncDef(d);
		mFinallyDepth = depth.prev;
		return ret;
	}

	FuncDef* Semantic::commonVisitFuncDef(FuncDef* d)
	{
		uword i = 0;
		for(auto &p: d->params)
		{
			if(p.customConstraint)
			{
				List<Expression*> args(c);
				args.add(new(c) IdentExp(p.name));
				p.customConstraint = new(c) CallExp(p.customConstraint->endLocation, p.customConstraint, nullptr,
					args.toArray());
			}

			if(p.defValue == nullptr)
				continue;

			p.defValue = visit(p.defValue);

			if(!p.defValue->isConstant())
				continue;

			CrocType type;

			if(p.defValue->isNull())        type = CrocType_Null;
			else if(p.defValue->isBool())   type = CrocType_Bool;
			else if(p.defValue->isInt())    type = CrocType_Int;
			else if(p.defValue->isFloat())  type = CrocType_Float;
			else if(p.defValue->isString()) type = CrocType_String;
			else { assert(false); type = CrocType_Null; } // dummy

			if(!(p.typeMask & (1 << type)))
				c.semException(p.defValue->location, "Parameter %u: Default parameter of type '%s' is not allowed",
					i - 1, typeToString(type));

			i++;
		}

		VISIT(d->code);

		List<Statement*> extra(c);

		for(auto &p: d->params)
		{
			if(p.defValue != nullptr)
				extra.add(new(c) CondAssignStmt(p.name->location, p.name->location, new(c) IdentExp(p.name),
					p.defValue));
		}

		if(c.typeConstraints())
			extra.add(new(c) TypecheckStmt(d->code->location, d));

		if(extra.length() > 0)
		{
			extra.add(d->code);
			auto arr = extra.toArray();
			d->code = new(c) BlockStmt(arr[0]->location, arr[arr.length - 1]->endLocation, arr);
		}

		return d;
	}

	Statement* Semantic::visit(AssertStmt* s)
	{
		if(!c.asserts())
			return new(c) BlockStmt(s->location, s->endLocation, DArray<Statement*>());

		VISIT(s->cond);

		if(s->msg)
			VISIT(s->msg);
		else
		{
			croc_pushFormat(*c.thread(), "Assertion failure at %s(%u:%u)",
				s->location.file.ptr, s->location.line, s->location.col);
			auto str = c.newString(croc_getString(*c.thread(), -1));
			croc_popTop(*c.thread());
			s->msg = new(c) StringExp(s->location, str);
		}

		return s;
	}

	Statement* Semantic::visit(ImportStmt* s)
	{
		VISIT(s->expr);

		if(s->expr->isConstant() && !s->expr->isString())
			c.semException(s->expr->location, "Import expression must evaluate to a string");

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
		auto doSelective = [&](List<Statement*>& stmts, Expression* src)
		{
			uword i = 0;
			for(auto sym: s->symbols)
			{
				List<Expression*> lhs(c);
				List<Expression*> rhs(c);
				lhs.add(new(c) IdentExp(s->symbolNames[i]));
				rhs.add(new(c) DotExp(src, new(c) StringExp(sym->location, sym->name)));
				stmts.add(new(c) AssignStmt(sym->location, sym->endLocation, lhs.toArray(), rhs.toArray()));
				i++;
			}
		};

		// First we make the "modules.load(expr)" call.
		auto _modules = new(c) IdentExp(new(c) Identifier(s->location, c.newString("modules")));
		auto _load = new(c) StringExp(s->location, c.newString("load"));
		List<Expression*> args(c);
		args.add(s->expr);
		auto call = new(c) MethodCallExp(s->location, s->endLocation, _modules, _load, args.toArray());

		// Now we make a list of statements.
		List<Statement*> stmts(c);

		// First we declare any selectively-imported symbols as locals
		if(s->symbols.length > 0)
			stmts.add(new(c) VarDecl(s->location, s->endLocation, Protection::Local, s->symbolNames,
				DArray<Expression*>()));

		if(s->importName == nullptr)
		{
			if(s->symbols.length == 0)
				stmts.add(new(c) ExpressionStmt(s->location, s->endLocation, call));
			else
			{
				// Not renamed, but we have to get the namespace so we can fill in the selectively-imported symbols.
				List<Statement*> stmts2(c);

				// First put the import into a temporary local.
				List<Identifier*> names(c);
				List<Expression*> inits(c);
				auto ident = new(c) Identifier(s->location, c.newString(CROC_INTERNAL_NAME("tempimport")));
				names.add(ident);
				inits.add(call);
				stmts2.add(new(c) VarDecl(s->location, s->endLocation, Protection::Local, names.toArray(),
					inits.toArray()));

				// Now get all the fields out.
				doSelective(stmts2, new(c) IdentExp(ident));

				// Finally, we put all this in a scoped sub-block.
				stmts.add(new(c) ScopeStmt(new(c) BlockStmt(s->location, s->endLocation, stmts2.toArray())));
			}
		}
		else
		{
			// Renamed import. Just put it in a new local.
			List<Identifier*> names(c);
			List<Expression*> inits(c);
			names.add(s->importName);
			inits.add(call);
			stmts.add(new(c) VarDecl(s->location, s->endLocation, Protection::Local, names.toArray(), inits.toArray()));

			// Do any selective imports
			if(s->symbols.length > 0)
				doSelective(stmts, new(c) IdentExp(s->importName));
		}

		// Wrap it all up in a (non-scoped) block.
		return new(c) BlockStmt(s->location, s->endLocation, stmts.toArray());
	}

	ScopeStmt* Semantic::visit(ScopeStmt* s)
	{
		VISIT(s->statement);
		return s;
	}

	ExpressionStmt* Semantic::visit(ExpressionStmt* s)
	{
		VISIT(s->expr);
		return s;
	}

	VarDecl* Semantic::visit(VarDecl* d)
	{
		VISIT_ARR(d->initializer);
		PROTECTION(d);
		return d;
	}

	Decorator* Semantic::visit(Decorator* d)
	{
		VISIT(d->func);
		COND_VISIT(d->context);
		VISIT_ARR(d->args);
		COND_VISIT(d->nextDec);
		return d;
	}

	FuncDecl* Semantic::visit(FuncDecl* d)
	{
		PROTECTION(d);
		VISIT(d->def);
		COND_VISIT(d->decorator);
		return d;
	}

	ClassDecl* Semantic::visit(ClassDecl* d)
	{
		PROTECTION(d);
		COND_VISIT(d->decorator);
		VISIT_ARR(d->baseClasses);
		VISIT_ARR_FIELD(d->fields, initializer);
		return d;
	}

	NamespaceDecl* Semantic::visit(NamespaceDecl* d)
	{
		PROTECTION(d);
		COND_VISIT(d->decorator);
		COND_VISIT(d->parent);
		VISIT_ARR_FIELD(d->fields, initializer);
		return d;
	}

	Statement* Semantic::visit(BlockStmt* s)
	{
		uword i = 0;

		for(auto &stmt: s->statements)
		{
			stmt = visit(stmt);

			// Do we need to process a scope statement?
			if(stmt->type == AstTag_ScopeActionStmt)
				goto _found;

			i++;
		}

		return s;
	_found:

		auto ss = AST_AS(ScopeActionStmt, s->statements[i]);

		// Get all the statements that follow this scope statement.
		auto rest = s->statements.slice(i + 1, s->statements.length);

		if(rest.length == 0)
		{
			// If there are no more statements, the body of the scope statement will either always or never be run
			if(ss->action == ScopeAction::Exit || ss->action == ScopeAction::Success)
				s->statements[s->statements.length - 1] = ss->stmt;
			else
				s->statements = s->statements.slice(0, s->statements.length - 1);

			return s;
		}

		// Have to rewrite the statements. Scope statements are just fancy ways of writing try-catch-finally blocks.
		auto tryBody = new(c) ScopeStmt(new(c) BlockStmt(rest[0]->location, rest[rest.length - 1]->endLocation, rest));
		Statement* replacement = nullptr;

		switch(ss->action)
		{
			case ScopeAction::Exit:
				/*
				scope(exit) { ss.stmt }
				rest
				=>
				try { rest }
				finally { ss.stmt }
				*/
				replacement = visit(new(c) TryFinallyStmt(ss->location, ss->endLocation, tryBody, ss->stmt));
				break;

			case ScopeAction::Success: {
				/*
				scope(success) { ss.stmt }
				rest
				=>
				local __dummy = true
				try { rest }
				catch(__dummy2) { __dummy = false; throw __dummy2 }
				finally { if(__dummy) ss.stmt }
				*/

				// local __dummy = true
				auto finishedVar = genDummyVar(ss->endLocation, CROC_INTERNAL_NAME("scope%u"));
				auto finishedVarExp = new(c) IdentExp(finishedVar);
				Statement* declStmt = nullptr;

				{
					List<Identifier*> nameList(c);
					nameList.add(finishedVar);
					List<Expression*> initializer(c);
					initializer.add(new(c) BoolExp(ss->location, true));
					declStmt = new(c) VarDecl(ss->location, ss->location, Protection::Local, nameList.toArray(), initializer.toArray());
				}

				// catch(__dummy2) { __dummy = false; throw __dummy2 }
				auto catchVar = genDummyVar(ss->location, CROC_INTERNAL_NAME("scope%u"));
				TryCatchStmt* catchStmt = nullptr;

				{
					List<Statement*> dummy(c);
					// __dummy = false;
					List<Expression*> lhs(c);
					lhs.add(finishedVarExp);
					List<Expression*> rhs(c);
					rhs.add(new(c) BoolExp(ss->location, false));
					dummy.add(new(c) AssignStmt(ss->location, ss->location, lhs.toArray(), rhs.toArray()));
					// throw __dummy2
					dummy.add(new(c) ThrowStmt(ss->stmt->location, new(c) IdentExp(catchVar), true));
					auto code = dummy.toArray();
					auto catchBody = new(c) ScopeStmt(new(c) BlockStmt(code[0]->location, code[code.length - 1]->endLocation, code));

					List<CatchClause> catches(c);
					catches.add(CatchClause(catchVar, DArray<Expression*>(), catchBody));

					catchStmt = new(c) TryCatchStmt(ss->location, ss->endLocation, tryBody, catches.toArray());
				}

				// finally { if(__dummy) ss.stmt }
				ScopeStmt* finallyBody = nullptr;

				{
					List<Statement*> dummy(c);
					// if(__dummy) ss.stmt
					dummy.add(new(c) IfStmt(ss->location, ss->endLocation, nullptr, finishedVarExp, ss->stmt, nullptr));
					auto code = dummy.toArray();
					finallyBody = new(c) ScopeStmt(new(c) BlockStmt(code[0]->location, code[code.length - 1]->endLocation, code));
				}

				// Put it all together
				List<Statement*> code(c);
				code.add(declStmt);
				code.add(new(c) TryFinallyStmt(ss->location, ss->endLocation, catchStmt, finallyBody));
				auto codeArr = code.toArray();
				replacement = visit(new(c) ScopeStmt(new(c) BlockStmt(codeArr[0]->location, codeArr[codeArr.length - 1]->endLocation, codeArr)));
				break;
			}
			case ScopeAction::Failure: {
				/*
				scope(failure) { ss.stmt }
				rest
				=>
				try { rest }
				catch(__dummy) { ss.stmt; throw __dummy }
				*/
				auto catchVar = genDummyVar(ss->location, CROC_INTERNAL_NAME("scope%u"));

				List<Statement*> dummy(c);
				dummy.add(ss->stmt);
				dummy.add(new(c) ThrowStmt(ss->stmt->endLocation, new(c) IdentExp(catchVar), true));
				auto catchCode = dummy.toArray();
				auto catchBody = new(c) ScopeStmt(new(c) BlockStmt(catchCode[0]->location, catchCode[catchCode.length - 1]->endLocation, catchCode));

				List<CatchClause> catches(c);
				catches.add(CatchClause(catchVar, DArray<Expression*>(), catchBody));
				replacement = visit(new(c) TryCatchStmt(ss->location, ss->endLocation, tryBody, catches.toArray()));
				break;
			}
			default: assert(false);
		}

		s->statements = s->statements.slice(0, i + 1);
		s->statements[i] = replacement;
		return s;
	}

	Statement* Semantic::visit(IfStmt* s)
	{
		VISIT(s->condition);
		VISIT(s->ifBody);

		COND_VISIT(s->elseBody);

		if(s->condition->isConstant())
		{
			if(s->condition->isTrue())
			{
				if(s->condVar == nullptr)
					return new(c) ScopeStmt(s->ifBody);

				List<Identifier*> names(c);
				names.add(s->condVar->name);

				List<Expression*> initializer(c);
				initializer.add(s->condition);

				List<Statement*> temp(c);
				temp.add(new(c) VarDecl(s->condVar->location, s->condVar->endLocation, Protection::Local, names.toArray(), initializer.toArray()));
				temp.add(s->ifBody);

				return new(c) ScopeStmt(new(c) BlockStmt(s->location, s->endLocation, temp.toArray()));
			}
			else
			{
				if(s->elseBody)
					return new(c) ScopeStmt(s->elseBody);
				else
					return new(c) BlockStmt(s->location, s->endLocation, DArray<Statement*>());
			}
		}

		return s;
	}

	Statement* Semantic::visit(WhileStmt* s)
	{
		VISIT(s->condition);
		VISIT(s->code);

		if(s->condition->isConstant() && !s->condition->isTrue())
			return new(c) BlockStmt(s->location, s->endLocation, DArray<Statement*>());

		return s;
	}

	Statement* Semantic::visit(DoWhileStmt* s)
	{
		// Jarrett, stop rewriting do-while statements with constant conditions. you did this before. it fucks up breaks/continues inside them. STOP IT.
		VISIT(s->code);
		VISIT(s->condition);
		return s;
	}

	Statement* Semantic::visit(ForStmt* s)
	{
		for(auto &i: s->init)
		{
			if(i.isDecl)
				i.decl = visit(i.decl);
			else
				i.stmt = visit(i.stmt);
		}

		COND_VISIT(s->condition);
		VISIT_ARR(s->increment);
		VISIT(s->code);

		if(s->condition && s->condition->isConstant())
		{
			if(s->condition->isTrue())
				s->condition = nullptr;
			else
			{
				if(s->init.length > 0)
				{
					List<Statement*> inits(c);

					for(auto &i: s->init)
					{
						if(i.isDecl)
							inits.add(i.decl);
						else
							inits.add(i.stmt);
					}

					return new(c) ScopeStmt(new(c) BlockStmt(s->location, s->endLocation, inits.toArray()));
				}
				else
					return new(c) BlockStmt(s->location, s->endLocation, DArray<Statement*>());
			}
		}

		return s;
	}

	Statement* Semantic::visit(ForNumStmt* s)
	{
		VISIT(s->lo);
		VISIT(s->hi);
		VISIT(s->step);

		if(s->lo->isConstant() && !s->lo->isInt())
			c.semException(s->lo->location, "Low value of a numeric for loop must be an integer");

		if(s->hi->isConstant() && !s->hi->isInt())
			c.semException(s->hi->location, "High value of a numeric for loop must be an integer");

		if(s->step->isConstant())
		{
			if(!s->step->isInt())
				c.semException(s->step->location, "Step value of a numeric for loop must be an integer");

			if(s->step->asInt() == 0)
				c.semException(s->step->location, "Step value of a numeric for loop may not be 0");
		}

		VISIT(s->code);
		return s;
	}

	ForeachStmt* Semantic::visit(ForeachStmt* s)
	{
		VISIT_ARR(s->container);
		VISIT(s->code);
		return s;
	}

	SwitchStmt* Semantic::visit(SwitchStmt* s)
	{
		VISIT(s->condition);
		VISIT_ARR(s->cases);

		for(auto rc: s->cases)
		{
			if(rc->highRange == nullptr || !rc->conditions[0].exp->isConstant() || !rc->highRange->isConstant())
				continue;

			auto lo = rc->conditions[0].exp;
			auto hi = rc->highRange;

			// this might not work for ranges using absurdly large numbers. fuh.
			if(lo->isNum() && hi->isNum())
			{
				auto loVal = lo->asFloat();
				auto hiVal = hi->asFloat();

				for(auto c2: s->cases)
				{
					if(rc == c2)
						continue;

					if(c2->highRange != nullptr)
					{
						auto lo2 = c2->conditions[0].exp;
						auto hi2 = c2->highRange;

						if((lo2->isConstant() && hi2->isConstant()) && lo2->isNum() && hi2->isNum())
						{
							auto lo2Val = lo2->asFloat();
							auto hi2Val = hi2->asFloat();

							if(loVal == lo2Val ||
								(loVal < lo2Val && (lo2Val - loVal) <= (hiVal - loVal)) ||
								(loVal > lo2Val && (loVal - lo2Val) <= (hi2Val - lo2Val)))
								c.semException(lo2->location, "case range overlaps range at %s(%u:%u)",
									lo->location.file.ptr, lo->location.line, lo->location.col);
						}
					}
					else
					{
						for(auto cond: c2->conditions)
						{
							if(cond.exp->isConstant() &&
								((cond.exp->isInt() && cond.exp->asInt() >= loVal && cond.exp->asInt() <= hiVal) ||
								(cond.exp->isFloat() && cond.exp->asFloat() >= loVal && cond.exp->asFloat() <= hiVal)))
								c.semException(cond.exp->location, "case value overlaps range at %s(%u:%u)",
									lo->location.file.ptr, lo->location.line, lo->location.col);
						}
					}
				}
			}
			else if(lo->isString() && hi->isString())
			{
				auto loVal = lo->asString();
				auto hiVal = hi->asString();

				for(auto c2: s->cases)
				{
					if(rc == c2)
						continue;

					if(c2->highRange != nullptr)
					{
						auto lo2 = c2->conditions[0].exp;
						auto hi2 = c2->highRange;

						if((lo2->isConstant() && hi2->isConstant()) && (lo2->isString() && hi2->isString()))
						{
							auto lo2Val = lo2->asString();
							auto hi2Val = hi2->asString();

							if( (loVal >= lo2Val && loVal <= hi2Val) ||
								(hiVal >= lo2Val && hiVal <= hi2Val) ||
								(lo2Val >= loVal && lo2Val <= hiVal) ||
								(hi2Val >= loVal && hi2Val <= hiVal))
								c.semException(lo2->location, "case range overlaps range at %s(%u:%u)",
									lo->location.file.ptr, lo->location.line, lo->location.col);
						}
					}
					else
					{
						for(auto cond: c2->conditions)
						{
							if(cond.exp->isConstant() && cond.exp->isString() &&
								cond.exp->asString() >= loVal && cond.exp->asString() <= hiVal)
								c.semException(cond.exp->location, "case value overlaps range at %s(%u:%u)",
									lo->location.file.ptr, lo->location.line, lo->location.col);
						}
					}
				}
			}
		}

		COND_VISIT(s->caseDefault);
		return s;
	}

	CaseStmt* Semantic::visit(CaseStmt* s)
	{
		VISIT_ARR_FIELD(s->conditions, exp);

		if(s->highRange)
		{
			VISIT(s->highRange);

			auto lo = s->conditions[0].exp;
			auto hi = s->highRange;

			if(lo->isConstant() && hi->isConstant())
			{
				if(lo->isInt() && hi->isInt())
				{
					if(lo->asInt() > hi->asInt())
						c.semException(lo->location, "Invalid case range (low is greater than high)");
					else if(lo->asInt() == hi->asInt())
						s->highRange = nullptr;
				}
				else if(lo->isNum() && hi->isNum())
				{
					if(lo->asFloat() > hi->asFloat())
						c.semException(lo->location, "Invalid case range (low is greater than high)");
					else if(lo->asFloat() == hi->asFloat())
						s->highRange = nullptr;
				}
				else if(lo->isString() && hi->isString())
				{
					if(lo->asString() > hi->asString())
						c.semException(lo->location, "Invalid case range (low is greater than high)");
					else if(lo->asString() == hi->asString())
						s->highRange = nullptr;
				}
			}
		}

		VISIT(s->code);
		return s;
	}

	DefaultStmt* Semantic::visit(DefaultStmt* s)
	{
		VISIT(s->code);
		return s;
	}

	ContinueStmt* Semantic::visit(ContinueStmt* s)
	{
		if(inFinally())
			c.semException(s->location, "Continue statements are illegal inside finally blocks");

		return s;
	}

	BreakStmt* Semantic::visit(BreakStmt* s)
	{
		if(inFinally())
			c.semException(s->location, "Break statements are illegal inside finally blocks");

		return s;
	}

	ReturnStmt* Semantic::visit(ReturnStmt* s)
	{
		if(inFinally())
			c.semException(s->location, "Return statements are illegal inside finally blocks");

		VISIT_ARR(s->exprs);
		return s;
	}

	TryCatchStmt* Semantic::visit(TryCatchStmt* s)
	{
		VISIT(s->tryBody);

		for(auto &c: s->catches)
		{
			VISIT_ARR(c.exTypes);
			VISIT(c.catchBody);
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
			if(__catch0.super is E1) { local e = __catch0; catch1() }
			else if(__catch0.super is E2 || __catch0.super is E3) { local f = __catch0; catch2() }
			else throw __catch0
		}

		For catchall clauses,

		try
			...
		catch(e: E1)
			catch1()
		catch(f)
			catch2()

		=>

		try
			...
		catch(__catch0)
		{
			if(__catch0.super is E1) { local e = __catch0; catch1() }
			else { local f = __catch0; catch2() }
		}
		*/

		// catch(__catch0)
		auto cvar = genDummyVar(s->catches[0].catchVar->location, CROC_INTERNAL_NAME("catch%u"));
		auto cvarExp = new(c) IdentExp(cvar);
		auto cvarSuperExp = new(c) DotSuperExp(cvarExp->endLocation, cvarExp);
		s->hiddenCatchVar = cvar;

		Statement* stmt = nullptr;

		if(s->catches[s->catches.length - 1].exTypes.length != 0)
			stmt = new(c) ThrowStmt(s->endLocation, cvarExp, true); // else throw __catch0

		// Doing it in reverse to make building it up easier.
		for(auto &ca: s->catches.reverse())
		{
			List<Statement*> code(c);

			// local f = __catch0;
			List<Identifier*> nameList(c);
			nameList.add(ca.catchVar);
			List<Expression*> initializer(c);
			initializer.add(cvarExp);
			code.add(new(c) VarDecl(ca.catchVar->location, ca.catchVar->location, Protection::Local, nameList.toArray(),
				initializer.toArray()));

			// catch2()
			code.add(ca.catchBody);

			// wrap it up
			auto ifCode = new(c) ScopeStmt(new(c) BlockStmt(ca.catchBody->location, ca.catchBody->endLocation,
				code.toArray()));

			if(stmt == nullptr) // only nullptr if last catch clause is a catchall
				stmt = ifCode;
			else
			{
				// if(__catch0.super is E2 || __catch0.super is E3)
				Expression* cond = new(c) IsExp(ca.catchVar->location, ca.catchVar->location, cvarSuperExp,
					ca.exTypes[0]);

				for(auto type: ca.exTypes.slice(1, ca.exTypes.length))
				{
					auto tmp = new(c) IsExp(ca.catchVar->location, ca.catchVar->location, cvarSuperExp, type);
					cond = new(c) OrOrExp(ca.catchVar->location, ca.catchVar->location, cond, tmp);
				}

				stmt = new(c) IfStmt(ca.catchVar->location, stmt->endLocation, nullptr, cond, ifCode, stmt);
			}
		}

		s->transformedCatch = stmt;
		return s;
	}

	TryFinallyStmt* Semantic::visit(TryFinallyStmt* s)
	{
		VISIT(s->tryBody);
		enterFinally();
		VISIT(s->finallyBody);
		leaveFinally();
		return s;
	}

	ThrowStmt* Semantic::visit(ThrowStmt* s)
	{
		VISIT(s->exp);
		return s;
	}

	ScopeActionStmt* Semantic::visit(ScopeActionStmt* s)
	{
		if(s->action == ScopeAction::Exit || s->action == ScopeAction::Success)
		{
			enterFinally();
			VISIT(s->stmt);
			leaveFinally();
		}
		else
			VISIT(s->stmt);

		return s;
	}

	AssignStmt* Semantic::visit(AssignStmt* s)
	{
		VISIT_ARR(s->lhs);
		VISIT_ARR(s->rhs);
		return s;
	}

	OpAssignStmt* Semantic::visitOpAssign(OpAssignStmt* s)
	{
		VISIT(s->lhs);
		VISIT(s->rhs);
		return s;
	}

	AddAssignStmt*  Semantic::visit(AddAssignStmt* s)  { return cast(AddAssignStmt*) visitOpAssign(s); }
	SubAssignStmt*  Semantic::visit(SubAssignStmt* s)  { return cast(SubAssignStmt*) visitOpAssign(s); }
	MulAssignStmt*  Semantic::visit(MulAssignStmt* s)  { return cast(MulAssignStmt*) visitOpAssign(s); }
	DivAssignStmt*  Semantic::visit(DivAssignStmt* s)  { return cast(DivAssignStmt*) visitOpAssign(s); }
	ModAssignStmt*  Semantic::visit(ModAssignStmt* s)  { return cast(ModAssignStmt*) visitOpAssign(s); }
	ShlAssignStmt*  Semantic::visit(ShlAssignStmt* s)  { return cast(ShlAssignStmt*) visitOpAssign(s); }
	ShrAssignStmt*  Semantic::visit(ShrAssignStmt* s)  { return cast(ShrAssignStmt*) visitOpAssign(s); }
	UShrAssignStmt* Semantic::visit(UShrAssignStmt* s) { return cast(UShrAssignStmt*)visitOpAssign(s); }
	XorAssignStmt*  Semantic::visit(XorAssignStmt* s)  { return cast(XorAssignStmt*) visitOpAssign(s); }
	OrAssignStmt*   Semantic::visit(OrAssignStmt* s)   { return cast(OrAssignStmt*)  visitOpAssign(s); }
	AndAssignStmt*  Semantic::visit(AndAssignStmt* s)  { return cast(AndAssignStmt*) visitOpAssign(s); }

	Statement* Semantic::visit(CondAssignStmt* s)
	{
		VISIT(s->lhs);
		VISIT(s->rhs);

		if(s->rhs->isConstant() && s->rhs->isNull())
			return new(c) BlockStmt(s->location, s->endLocation, DArray<Statement*>());

		return s;
	}

	CatAssignStmt* Semantic::visit(CatAssignStmt* s)
	{
		VISIT(s->lhs);
		VISIT(s->rhs);

		if(auto catExp = AST_AS(CatExp, s->rhs))
		{
			s->operands = catExp->operands;
			catExp->operands = DArray<Expression*>();
		}
		else
		{
			List<Expression*> dummy(c);
			dummy.add(s->rhs);
			s->operands = dummy.toArray();
		}

		s->collapsed = true;
		return s;
	}

	IncStmt* Semantic::visit(IncStmt* s)
	{
		VISIT(s->exp);
		return s;
	}

	DecStmt* Semantic::visit(DecStmt* s)
	{
		VISIT(s->exp);
		return s;
	}

	Expression* Semantic::visit(CondExp* e)
	{
		VISIT(e->cond);
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->cond->isConstant())
		{
			if(e->cond->isTrue())
				return e->op1;
			else
				return e->op2;
		}

		return e;
	}

	Expression* Semantic::visit(OrOrExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant())
		{
			if(e->op1->isTrue())
				return e->op1;
			else
				return e->op2;
		}

		return e;
	}

	Expression* Semantic::visit(AndAndExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant())
		{
			if(e->op1->isTrue())
				return e->op2;
			else
				return e->op1;
		}

		return e;
	}

	Expression* Semantic::visit(OrExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant())
		{
			if(!e->op1->isInt() || !e->op2->isInt())
				c.semException(e->location, "Bitwise Or must be performed on integers");

			return new(c) IntExp(e->location, e->op1->asInt() | e->op2->asInt());
		}

		return e;
	}

	Expression* Semantic::visit(XorExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant())
		{
			if(!e->op1->isInt() || !e->op2->isInt())
				c.semException(e->location, "Bitwise Xor must be performed on integers");

			return new(c) IntExp(e->location, e->op1->asInt() ^ e->op2->asInt());
		}

		return e;
	}

	Expression* Semantic::visit(AndExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant())
		{
			if(!e->op1->isInt() || !e->op2->isInt())
				c.semException(e->location, "Bitwise And must be performed on integers");

			return new(c) IntExp(e->location, e->op1->asInt() & e->op2->asInt());
		}

		return e;
	}

	Expression* Semantic::visitEquality(BinaryExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		bool isTrue = e->type == AstTag_EqualExp || e->type == AstTag_IsExp;

		if(e->op1->isConstant() && e->op2->isConstant())
		{
			if(e->op1->isNull() && e->op2->isNull())
				return new(c) BoolExp(e->location, isTrue);

			if(e->op1->isBool() && e->op2->isBool())
			{
				return new(c) BoolExp(e->location,
					isTrue ?
					e->op1->asBool() == e->op2->asBool() :
					e->op1->asBool() != e->op2->asBool());
			}

			if(e->op1->isInt() && e->op2->isInt())
			{
				return new(c) BoolExp(e->location,
					isTrue ?
					e->op1->asInt() == e->op2->asInt() :
					e->op1->asInt() != e->op2->asInt());
			}

			if(e->type == AstTag_IsExp || e->type == AstTag_NotIsExp)
			{
				if(e->op1->isFloat() && e->op2->isFloat())
					return new(c) BoolExp(e->location,
						isTrue ?
						e->op1->asFloat() == e->op2->asFloat() :
						e->op1->asFloat() != e->op2->asFloat());
			}
			else
			{
				if(e->op1->isNum() && e->op2->isNum())
					return new(c) BoolExp(e->location,
						isTrue ?
						e->op1->asFloat() == e->op2->asFloat() :
						e->op1->asFloat() != e->op2->asFloat());
			}

			if(e->op1->isString() && e->op2->isString())
				return new(c) BoolExp(e->location,
					isTrue ?
					e->op1->asString() == e->op2->asString() :
					e->op1->asString() != e->op2->asString());

			if(e->type == AstTag_IsExp || e->type == AstTag_NotIsExp)
				return new(c) BoolExp(e->location, !isTrue);
			else
				c.semException(e->location, "Cannot compare different types");
		}

		return e;
	}

	Expression* Semantic::visit(EqualExp* e)    { return visitEquality(e); }
	Expression* Semantic::visit(NotEqualExp* e) { return visitEquality(e); }
	Expression* Semantic::visit(IsExp* e)       { return visitEquality(e); }
	Expression* Semantic::visit(NotIsExp* e)    { return visitEquality(e); }

	word Semantic::commonCompare(Expression* op1, Expression* op2)
	{
		if(op1->isNull() && op2->isNull())
			return 0;
		else if(op1->isInt() && op2->isInt())
			return Compare3(op1->asInt(), op2->asInt());
		else if(op1->isNum() && op2->isNum())
			return Compare3(op1->asFloat(), op2->asFloat());
		else if(op1->isString() && op2->isString())
			return op1->asString().cmp(op2->asString());
		else
			c.semException(op1->location, "Invalid compile-time comparison");

		assert(false);
		return 0; // dummy
	}

	Expression* Semantic::visitComparison(BinaryExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant())
		{
			auto cmpVal = commonCompare(e->op1, e->op2);

			switch(e->type)
			{
				case AstTag_LTExp: return new(c) BoolExp(e->location, cmpVal < 0);
				case AstTag_LEExp: return new(c) BoolExp(e->location, cmpVal <= 0);
				case AstTag_GTExp: return new(c) BoolExp(e->location, cmpVal > 0);
				case AstTag_GEExp: return new(c) BoolExp(e->location, cmpVal >= 0);
				default: assert(false);
			}
		}

		return e;
	}

	Expression* Semantic::visit(LTExp* e) { return visitComparison(e); }
	Expression* Semantic::visit(LEExp* e) { return visitComparison(e); }
	Expression* Semantic::visit(GTExp* e) { return visitComparison(e); }
	Expression* Semantic::visit(GEExp* e) { return visitComparison(e); }

	Expression* Semantic::visit(Cmp3Exp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant())
			return new(c) IntExp(e->location, commonCompare(e->op1, e->op2));

		return e;
	}

	Expression* Semantic::visit(InExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant() && e->op2->isString())
		{
			auto s = e->op2->asString();

			if(e->op1->isString())
				return new(c) BoolExp(e->location, strLocate(s, e->op1->asString()) != s.length);
			else
				c.semException(e->location, "'in' must be performed on a string with a string");
		}

		return e;
	}

	Expression* Semantic::visit(NotInExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant() && e->op2->isString())
		{
			auto s = e->op2->asString();

			if(e->op1->isString())
				return new(c) BoolExp(e->location, strLocate(s, e->op1->asString()) == s.length);
			else
				c.semException(e->location, "'!in' must be performed on a string with a string");
		}

		return e;
	}

	Expression* Semantic::visit(ShlExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant())
		{
			if(!e->op1->isInt() || !e->op2->isInt())
				c.semException(e->location, "Bitwise left-shift must be performed on integers");

			return new(c) IntExp(e->location, e->op1->asInt() << e->op2->asInt());
		}

		return e;
	}

	Expression* Semantic::visit(ShrExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant())
		{
			if(!e->op1->isInt() || !e->op2->isInt())
				c.semException(e->location, "Bitwise right-shift must be performed on integers");

			return new(c) IntExp(e->location, e->op1->asInt() >> e->op2->asInt());
		}

		return e;
	}

	Expression* Semantic::visit(UShrExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant())
		{
			if(!e->op1->isInt() || !e->op2->isInt())
				c.semException(e->location, "Bitwise unsigned right-shift must be performed on integers");

			return new(c) IntExp(e->location, cast(uint64_t)e->op1->asInt() >> cast(uint64_t)e->op2->asInt());
		}

		return e;
	}

	Expression* Semantic::visit(AddExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant())
		{
			if(e->op1->isInt() && e->op2->isInt())
				return new(c) IntExp(e->location, e->op1->asInt() + e->op2->asInt());
			else if(e->op1->isNum() && e->op2->isNum())
				return new(c) FloatExp(e->location, e->op1->asFloat() + e->op2->asFloat());
			else
				c.semException(e->location, "Addition must be performed on numbers");
		}

		return e;
	}

	Expression* Semantic::visit(SubExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant())
		{
			if(e->op1->isInt() && e->op2->isInt())
				return new(c) IntExp(e->location, e->op1->asInt() - e->op2->asInt());
			else if(e->op1->isNum() && e->op2->isNum())
				return new(c) FloatExp(e->location, e->op1->asFloat() - e->op2->asFloat());
			else
				c.semException(e->location, "Subtraction must be performed on numbers");
		}

		return e;
	}

	Expression* Semantic::visit(CatExp* e)
	{
		if(e->collapsed)
			return e;

		e->collapsed = true;

		VISIT(e->op1);
		VISIT(e->op2);

		// Collapse
		{
			List<Expression*> tmp(c);

			if(auto l = AST_AS(CatExp, e->op1))
				tmp.add(l->operands);
			else
				tmp.add(e->op1);

			// Not needed?  e->operands should be empty
			//tmp.add(e->operands);
			tmp.add(e->op2);

			e->operands = tmp.toArray();
			e->endLocation = e->operands[e->operands.length - 1]->endLocation;
		}

		// Const fold
		List<Expression*> newOperands(c);
		List<uchar, 64> tempStr(c);

		auto ops = e->operands;

		for(uword i = 0; i < ops.length; i++)
		{
			// this first case can only happen when the last item in the array can't be folded. otherwise i will be set to ops.length - 1,
			// incremented, and the loop will break.
			if(i == ops.length - 1 ||
				!ops[i]->isConstant() || !ops[i + 1]->isConstant() ||
				!ops[i]->isString() || !ops[i + 1]->isString())

				newOperands.add(ops[i]);
			else
			{
				uword j = i + 2;

				while(j < ops.length && ops[j]->isString())
					j++;

				// j points to first non-const non-string non-char operand
				for(auto op: ops.slice(i, j))
					tempStr.add(op->asString());

				newOperands.add(new(c) StringExp(e->location, c.newString(tempStr.toArray())));
				i = j - 1;
			}
		}

		if(newOperands.length() == 1)
			return newOperands[0];
		else
		{
			e->operands = newOperands.toArray();
			return e;
		}
	}

	Expression* Semantic::visit(MulExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant())
		{
			if(e->op1->isInt() && e->op2->isInt())
				return new(c) IntExp(e->location, e->op1->asInt() * e->op2->asInt());
			else if(e->op1->isNum() && e->op2->isNum())
				return new(c) FloatExp(e->location, e->op1->asFloat() * e->op2->asFloat());
			else
				c.semException(e->location, "Multiplication must be performed on numbers");
		}

		return e;
	}

	Expression* Semantic::visit(DivExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant())
		{
			if(e->op1->isInt() && e->op2->isInt())
			{
				if(e->op2->asInt() == 0)
					c.semException(e->location, "Division by 0");

				return new(c) IntExp(e->location, e->op1->asInt() / e->op2->asInt());
			}
			else if(e->op1->isNum() && e->op2->isNum())
				return new(c) FloatExp(e->location, e->op1->asFloat() / e->op2->asFloat());
			else
				c.semException(e->location, "Division must be performed on numbers");
		}

		return e;
	}

	Expression* Semantic::visit(ModExp* e)
	{
		VISIT(e->op1);
		VISIT(e->op2);

		if(e->op1->isConstant() && e->op2->isConstant())
		{
			if(e->op1->isInt() && e->op2->isInt())
			{
				if(e->op2->asInt() == 0)
					c.semException(e->location, "Modulo by 0");

				return new(c) IntExp(e->location, e->op1->asInt() % e->op2->asInt());
			}
			else if(e->op1->isNum() && e->op2->isNum())
				return new(c) FloatExp(e->location, fmod(e->op1->asFloat(), e->op2->asFloat()));
			else
				c.semException(e->location, "Modulo must be performed on numbers");
		}

		return e;
	}

	Expression* Semantic::visit(NegExp* e)
	{
		VISIT(e->op);

		if(e->op->isConstant())
		{
			if(auto ie = AST_AS(IntExp, e->op))
			{
				ie->value = -ie->value;
				return ie;
			}
			else if(auto fe = AST_AS(FloatExp, e->op))
			{
				fe->value = -fe->value;
				return fe;
			}
			else
				c.semException(e->location, "Negation must be performed on numbers");
		}

		return e;
	}

	Expression* Semantic::visit(NotExp* e)
	{
		VISIT(e->op);

		if(e->op->isConstant())
			return new(c) BoolExp(e->location, !e->op->isTrue());

		switch(e->op->type)
		{
			case AstTag_LTExp:       { auto old = AST_AS(LTExp,       e->op); return new(c) GEExp      (e->location, e->endLocation, old->op1, old->op2); }
			case AstTag_LEExp:       { auto old = AST_AS(LEExp,       e->op); return new(c) GTExp      (e->location, e->endLocation, old->op1, old->op2); }
			case AstTag_GTExp:       { auto old = AST_AS(GTExp,       e->op); return new(c) LEExp      (e->location, e->endLocation, old->op1, old->op2); }
			case AstTag_GEExp:       { auto old = AST_AS(GEExp,       e->op); return new(c) LTExp      (e->location, e->endLocation, old->op1, old->op2); }
			case AstTag_EqualExp:    { auto old = AST_AS(EqualExp,    e->op); return new(c) NotEqualExp(e->location, e->endLocation, old->op1, old->op2); }
			case AstTag_NotEqualExp: { auto old = AST_AS(NotEqualExp, e->op); return new(c) EqualExp   (e->location, e->endLocation, old->op1, old->op2); }
			case AstTag_IsExp:       { auto old = AST_AS(IsExp,       e->op); return new(c) NotIsExp   (e->location, e->endLocation, old->op1, old->op2); }
			case AstTag_NotIsExp:    { auto old = AST_AS(NotIsExp,    e->op); return new(c) IsExp      (e->location, e->endLocation, old->op1, old->op2); }
			case AstTag_InExp:       { auto old = AST_AS(InExp,       e->op); return new(c) NotInExp   (e->location, e->endLocation, old->op1, old->op2); }
			case AstTag_NotInExp:    { auto old = AST_AS(NotInExp,    e->op); return new(c) InExp      (e->location, e->endLocation, old->op1, old->op2); }

			case AstTag_AndAndExp: {
				auto old = AST_AS(AndAndExp, e->op);
				auto op1 = visit(new(c) NotExp(old->op1->location, old->op1));
				auto op2 = visit(new(c) NotExp(old->op2->location, old->op2));
				return new(c) OrOrExp(e->location, e->endLocation, op1, op2);
			}
			case AstTag_OrOrExp: {
				auto old = AST_AS(OrOrExp, e->op);
				auto op1 = visit(new(c) NotExp(old->op1->location, old->op1));
				auto op2 = visit(new(c) NotExp(old->op2->location, old->op2));
				return new(c) AndAndExp(e->location, e->endLocation, op1, op2);
			}
			// TODO: what about multiple 'not's?  "!!x"

			default:
				break;
		}

		return e;
	}

	Expression* Semantic::visit(ComExp* e)
	{
		VISIT(e->op);

		if(e->op->isConstant())
		{
			if(auto ie = AST_AS(IntExp, e->op))
			{
				ie->value = ~ie->value;
				return ie;
			}
			else
				c.semException(e->location, "Bitwise complement must be performed on integers");
		}

		return e;
	}

	Expression* Semantic::visit(LenExp* e)
	{
		VISIT(e->op);

		if(e->op->isConstant())
		{
			if(e->op->isString())
			{
				auto s = e->op->asString();
				croc_pushStringn(*c.thread(), cast(const char*)s.ptr, s.length);
				auto len = croc_len(*c.thread(), -1);
				croc_popTop(*c.thread());
				return new(c) IntExp(e->location, len);
			}
			else
				c.semException(e->location, "Length must be performed on a string at compile time");
		}

		return e;
	}

	Expression* Semantic::visit(DotExp* e)
	{
		VISIT(e->op);
		VISIT(e->name);

		if(e->name->isConstant() && !e->name->isString())
			c.semException(e->name->location, "Field name must be a string");

		return e;
	}

	Expression* Semantic::visit(DotSuperExp* e)
	{
		VISIT(e->op);
		return e;
	}

	Expression* Semantic::visit(MethodCallExp* e)
	{
		COND_VISIT(e->op);
		VISIT(e->method);

		if(e->method->isConstant() && !e->method->isString())
			c.semException(e->method->location, "Method name must be a string");

		VISIT_ARR(e->args);
		return e;
	}

	Expression* Semantic::visit(CallExp* e)
	{
		VISIT(e->op);
		COND_VISIT(e->context);
		VISIT_ARR(e->args);
		return e;
	}

	Expression* Semantic::visit(IndexExp* e)
	{
		VISIT(e->op);
		VISIT(e->index);

		if(e->op->isConstant() && e->index->isConstant())
		{
			if(!e->op->isString() || !e->index->isInt())
				c.semException(e->location, "Can only index strings with integers at compile time");

			auto str = e->op->asString();
			auto strLen = fastUtf8CPLength(str);
			auto idx = e->index->asInt();

			if(idx < 0)
				idx += strLen;

			if(idx < 0 || idx >= strLen)
				c.semException(e->location, "Invalid string index");

			auto offs = utf8CPIdxToByte(str, cast(uword)idx);
			auto len = utf8SequenceLength(str[offs]);
			return new(c) StringExp(e->location, c.newString(str.slice(offs, offs + len)));
		}

		return e;
	}

	Expression* Semantic::visit(VargIndexExp* e)
	{
		VISIT(e->index);

		if(e->index->isConstant() && !e->index->isInt())
			c.semException(e->index->location, "index of a vararg indexing must be an integer");

		return e;
	}

	Expression* Semantic::visit(SliceExp* e)
	{
		VISIT(e->op);
		VISIT(e->loIndex);
		VISIT(e->hiIndex);

		if(e->op->isConstant() && e->loIndex->isConstant() && e->hiIndex->isConstant())
		{
			if(!e->op->isString() ||
				(!e->loIndex->isInt() && !e->loIndex->isNull()) ||
				(!e->hiIndex->isInt() && !e->hiIndex->isNull()))
				c.semException(e->location, "Can only slice strings with integers at compile time");

			auto str = e->op->asString();
			auto strLen = fastUtf8CPLength(str);
			crocint l, h;

			if(e->loIndex->isInt())
				l = e->loIndex->asInt();
			else
				l = 0;

			if(e->hiIndex->isInt())
				h = e->hiIndex->asInt();
			else
				h = strLen;

			if(l < 0)
				l += strLen;

			if(h < 0)
				h += strLen;

			if(l > h || l < 0 || l > strLen || h < 0 || h > strLen)
				c.semException(e->location, "Invalid slice indices");

			return new(c) StringExp(e->location, c.newString(utf8Slice(str, cast(uword)l, cast(uword)h)));
		}

		return e;
	}

	Expression* Semantic::visit(VargSliceExp* e)
	{
		VISIT(e->loIndex);
		VISIT(e->hiIndex);

		if(e->loIndex->isConstant() && !(e->loIndex->isNull() || e->loIndex->isInt()))
			c.semException(e->loIndex->location, "low index of vararg slice must be nullptr or int");

		if(e->hiIndex->isConstant() && !(e->hiIndex->isNull() || e->hiIndex->isInt()))
			c.semException(e->hiIndex->location, "high index of vararg slice must be nullptr or int");

		return e;
	}

	FuncLiteralExp* Semantic::visit(FuncLiteralExp* e)
	{
		VISIT(e->def);
		return e;
	}

	Expression* Semantic::visit(ParenExp* e)
	{
		VISIT(e->exp);

		if(e->exp->isMultRet())
			return e;
		else
			return e->exp;
	}

	TableCtorExp* Semantic::visit(TableCtorExp* e)
	{
		for(auto &field: e->fields)
		{
			VISIT(field.key);
			VISIT(field.value);
		}

		return e;
	}

	ArrayCtorExp* Semantic::visit(ArrayCtorExp* e)
	{
		VISIT_ARR(e->values);
		return e;
	}

	YieldExp* Semantic::visit(YieldExp* e)
	{
		VISIT_ARR(e->args);
		return e;
	}

	TableComprehension* Semantic::visit(TableComprehension* e)
	{
		VISIT(e->key);
		VISIT(e->value);
		e->forComp = visitForComp(e->forComp);
		return e;
	}

	Expression* Semantic::visit(ArrayComprehension* e)
	{
		VISIT(e->exp);
		e->forComp = visitForComp(e->forComp);
		return e;
	}

	ForComprehension* Semantic::visitForComp(ForComprehension* e)
	{
		if(auto x = AST_AS(ForeachComprehension, e))
			return visit(x);
		else
		{
			auto y = AST_AS(ForNumComprehension, e);
			assert(y != nullptr);
			return visit(y);
		}
	}

	ForeachComprehension* Semantic::visit(ForeachComprehension* e)
	{
		VISIT_ARR(e->container);
		COND_VISIT(e->ifComp);
		if(e->forComp) e->forComp = visitForComp(e->forComp);
		return e;
	}

	ForNumComprehension* Semantic::visit(ForNumComprehension* e)
	{
		VISIT(e->lo);
		VISIT(e->hi);
		COND_VISIT(e->step);
		COND_VISIT(e->ifComp);
		if(e->forComp) e->forComp = visitForComp(e->forComp);
		return e;
	}

	IfComprehension* Semantic::visit(IfComprehension* e)
	{
		VISIT(e->condition);
		return e;
	}

	Identifier* Semantic::genDummyVar(CompileLoc loc, const char* fmt)
	{
		croc_pushFormat(*c.thread(), fmt, mDummyNameCounter++);
		auto str = c.newString(croc_getString(*c.thread(), -1));
		croc_popTop(*c.thread());
		return new(c) Identifier(loc, str);
	}
}