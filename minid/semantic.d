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

module minid.semantic;

import minid.ast;
import minid.astvisitor;
import minid.compilertypes;
import minid.interpreter;
import minid.types;
import minid.utils;

class Semantic : IdentityVisitor
{
	private word mFuncDepth = 0;

	public this(ICompiler c)
	{
		super(c);
	}
	
	public bool isTopLevel()
	{
		return mFuncDepth == 0;
	}

	alias Visitor.visit visit;
	
	public override Module visit(Module m)
	{
		foreach(ref stmt; m.statements)
			stmt = visit(stmt);

		return m;
	}
	
	public FuncDef visitStatements(FuncDef d)
	{
		return visitFuncDef(d);	
	}

	public override ObjectDef visit(ObjectDef d)
	{
		d.baseObject = visit(d.baseObject);

		foreach(ref field; d.fields)
			field.initializer = visit(field.initializer);

		return d;
	}

	public override FuncDef visit(FuncDef d)
	{
		mFuncDepth++;

		scope(exit)
			mFuncDepth--;
			
		return visitFuncDef(d);
	}

	public FuncDef visitFuncDef(FuncDef d)
	{
		foreach(i, ref p; d.params)
		{
			if(p.defValue is null)
				continue;

			p.defValue = visit(p.defValue);

			if(!p.defValue.isConstant)
				continue;

			MDValue.Type type;

			if(p.defValue.isNull)
				type = MDValue.Type.Null;
			else if(p.defValue.isBool)
				type = MDValue.Type.Bool;
			else if(p.defValue.isInt)
				type = MDValue.Type.Int;
			else if(p.defValue.isFloat)
				type = MDValue.Type.Float;
			else if(p.defValue.isChar)
				type = MDValue.Type.Char;
			else if(p.defValue.isString)
				type = MDValue.Type.String;
			else
				assert(false);

			if(!(p.typeMask & (1 << type)))
			{
				if(i == 0)
					c.exception(p.defValue.location, "'this' parameter: Default parameter of type '{}' is not allowed", MDValue.typeString(type));
				else
					c.exception(p.defValue.location, "Parameter {}: Default parameter of type '{}' is not allowed", i - 1, MDValue.typeString(type));
			}
		}

		d.code = visit(d.code);

		scope extra = new List!(Statement)(c.alloc);

		foreach(ref p; d.params)
			if(p.defValue !is null)
				extra ~= new(c) CondAssignStmt(c, p.name.location, p.name.location, new(c) IdentExp(c, p.name), p.defValue);

		if(c.typeConstraints())
			extra ~= new(c) TypecheckStmt(c, d.code.location, d);

		if(extra.length > 0)
		{
			extra ~= d.code;
			auto arr = extra.toArray();
			d.code = new(c) BlockStmt(c, arr[0].location, arr[$ - 1].endLocation, arr);
		}

		return d;
	}
	
	public override Expression visit(NamespaceDef d)
	{
		if(d.parent)
			visit(d.parent);

		foreach(ref field; d.fields)
			field.initializer = visit(field.initializer);

		/*
		Rewrite:

		namespace N
		{
			function f() {}
		}

		as:

		(function <namespace N>()
		{
			local raw_namespace N {} // raw so it doesn't get rewritten

			local function __temp()
			{
				N.f = function f() {}
			}

			funcenv __temp, N
			__temp()

			return N
		})()
		*/
		
		scope funcBody = new List!(Statement)(c.alloc);

		{
			// local raw_namespace N {}
			{
				scope dummy = new List!(Identifier)(c.alloc);
				dummy ~= d.name;
				auto init = new(c) RawNamespaceExp(c, d.location, d.name, d.parent);
				funcBody ~= new(c) VarDecl(c, d.location, d.endLocation, Protection.Local, dummy.toArray(), init);
			}
	
			// local function __temp()
			Identifier innerFuncName;
	
			{
				// {
				//     N.f = function f() {}
				// }
	
				scope stmts = new List!(Statement)(c.alloc);
	
				foreach(field; d.fields)
				{
					scope lhs = new List!(Expression)(c.alloc);
					lhs ~= new(c) DotExp(c, new(c) IdentExp(c, d.name), new(c) StringExp(c, field.initializer.location, field.name));
					stmts ~= new(c) AssignStmt(c, field.initializer.location, field.initializer.endLocation, lhs.toArray(), field.initializer);
				}
	
				auto innerFuncBody = new(c) BlockStmt(c, d.location, d.endLocation, stmts.toArray());
				innerFuncName = new(c) Identifier(c, d.location, c.newString("__temp"));

				scope params = new List!(FuncDef.Param)(c.alloc);
				params ~= FuncDef.Param(new(c) Identifier(c, d.location, c.newString("this")));
				auto innerFuncDef = new(c) FuncDef(c, d.location, innerFuncName, params.toArray(), false, innerFuncBody);
				auto lit = new(c) FuncLiteralExp(c, d.location, innerFuncDef);
				funcBody ~= new(c) OtherDecl(c, Protection.Local, innerFuncName, lit);
			}
	
			// funcenv __temp, N
			funcBody ~= new(c) FuncEnvStmt(c, d.location, innerFuncName, d.name);
			
			// __temp()
			funcBody ~= new(c) ExpressionStmt(c, d.location, d.endLocation, new(c) CallExp(c, d.endLocation, new(c) IdentExp(c, innerFuncName), null, null));
	
			// return N
			{
				scope dummy = new List!(Expression)(c.alloc);
				dummy ~= new(c) IdentExp(c, d.name);
				funcBody ~= new(c) ReturnStmt(c, d.location, d.location, dummy.toArray());
			}
		}

		scope params = new List!(FuncDef.Param)(c.alloc);
		params ~= FuncDef.Param(new(c) Identifier(c, d.location, c.newString("this")));
		auto funcDef = new(c) FuncDef(c, d.location, d.name, params.toArray(), false, new(c) BlockStmt(c, d.location, d.endLocation, funcBody.toArray()));
		auto funcExp = new(c) FuncLiteralExp(c, d.location, funcDef);
		return new(c) CallExp(c, d.endLocation, funcExp, null, null);
	}

	public override Statement visit(AssertStmt s)
	{
		if(!c.asserts())
			return new(c) BlockStmt(c, s.location, s.endLocation, null);

		s.cond = visit(s.cond);

		if(s.msg)
			s.msg = visit(s.msg);
		else
		{
			pushFormat(c.thread, "Assertion failure at {}({}:{})", s.location.file, s.location.line, s.location.col);
			auto str = c.newString(getString(c.thread, -1));
			pop(c.thread);
			s.msg = new(c) StringExp(c, s.location, str);
		}

		auto cond = new(c) NotExp(c, s.cond.location, s.cond);
		auto t = new(c) ThrowStmt(c, s.msg.location, s.msg);
		return new(c) IfStmt(c, s.location, s.endLocation, null, cond, t, null);
	}

	public override ImportStmt visit(ImportStmt s)
	{
		s.expr = visit(s.expr);

		if(s.expr.isConstant() && !s.expr.isString())
			c.exception(s.expr.location, "Import expression must evaluate to a string");

		return s;
	}
	
	public override ScopeStmt visit(ScopeStmt s)
	{
		s.statement = visit(s.statement);
		return s;
	}
	
	public override ExpressionStmt visit(ExpressionStmt s)
	{
		s.expr = visit(s.expr);
		return s;
	}
	
	public override VarDecl visit(VarDecl d)
	{
		if(d.initializer)
			d.initializer = visit(d.initializer);

		if(d.protection == Protection.Default)
			d.protection = isTopLevel() ? Protection.Global : Protection.Local;

		return d;
	}

	public override OtherDecl visit(OtherDecl d)
	{
		d.expr = visit(d.expr);

		if(d.protection == Protection.Default)
			d.protection = isTopLevel() ? Protection.Global : Protection.Local;

		return d;
	}

	public override BlockStmt visit(BlockStmt s)
	{
		foreach(ref stmt; s.statements)
			stmt = visit(stmt);

		return s;
	}

	public override Statement visit(IfStmt s)
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
					return new(c) ScopeStmt(c, s.ifBody);

				scope names = new List!(Identifier)(c.alloc);
				names ~= s.condVar.name;

				scope temp = new List!(Statement)(c.alloc);
				temp ~= new(c) VarDecl(c, s.condVar.location, s.condVar.endLocation, Protection.Local, names.toArray(), s.condition);
				temp ~= s.ifBody;

				return new(c) ScopeStmt(c, new(c) BlockStmt(c, s.location, s.endLocation, temp.toArray()));
			}
			else
			{
				if(s.elseBody)
					return new(c) ScopeStmt(c, s.elseBody);
				else
					return new(c) BlockStmt(c, s.location, s.endLocation, null);
			}
		}

		return s;
	}

	public override Statement visit(WhileStmt s)
	{
		s.condition = visit(s.condition);
		s.code = visit(s.code);

		if(s.condition.isConstant && !s.condition.isTrue)
			return new(c) BlockStmt(c, s.location, s.endLocation, null);

		return s;
	}
	
	public override Statement visit(DoWhileStmt s)
	{
		s.code = visit(s.code);
		s.condition = visit(s.condition);

		if(s.condition.isConstant && !s.condition.isTrue)
			return s.code;

		return s;
	}
	
	public override Statement visit(ForStmt s)
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
					scope inits = new List!(Statement)(c.alloc);

					foreach(i; s.init)
					{
						if(i.isDecl)
							inits ~= i.decl;
						else
							inits ~= i.stmt;
					}

					return new(c) ScopeStmt(c, new(c) BlockStmt(c, s.location, s.endLocation, inits.toArray()));
				}
				else
					return new(c) BlockStmt(c, s.location, s.endLocation, null);
			}
		}

		return s;
	}
	
	public override Statement visit(ForNumStmt s)
	{
		s.lo = visit(s.lo);
		s.hi = visit(s.hi);
		s.step = visit(s.step);

		if(s.lo.isConstant && !s.lo.isInt)
			c.exception(s.lo.location, "Low value of a numeric for loop must be an integer");

		if(s.hi.isConstant && !s.hi.isInt)
			c.exception(s.hi.location, "High value of a numeric for loop must be an integer");

		if(s.step.isConstant)
		{
			if(!s.step.isInt)
				c.exception(s.step.location, "Step value of a numeric for loop must be an integer");

			if(s.step.asInt() == 0)
				c.exception(s.step.location, "Step value of a numeric for loop may not be 0");
		}

		s.code = visit(s.code);
		return s;
	}
	
	public override ForeachStmt visit(ForeachStmt s)
	{
		foreach(ref c; s.container)
			c = visit(c);

		s.code = visit(s.code);
		return s;
	}
	
	public override SwitchStmt visit(SwitchStmt s)
	{
		s.condition = visit(s.condition);

		foreach(ref c; s.cases)
			c = visit(c);

		if(s.caseDefault)
			s.caseDefault = visit(s.caseDefault);

		return s;
	}
	
	public override CaseStmt visit(CaseStmt s)
	{
		foreach(ref cond; s.conditions)
			cond.exp = visit(cond.exp);

		s.code = visit(s.code);
		return s;
	}

	public override DefaultStmt visit(DefaultStmt s)
	{
		s.code = visit(s.code);
		return s;
	}

	public override ReturnStmt visit(ReturnStmt s)
	{
		foreach(ref exp; s.exprs)
			exp = visit(exp);

		return s;
	}
	
	public override TryStmt visit(TryStmt s)
	{
		s.tryBody = visit(s.tryBody);

		if(s.catchBody)
			s.catchBody = visit(s.catchBody);

		if(s.finallyBody)
			s.finallyBody = visit(s.finallyBody);

		return s;
	}
	
	public override ThrowStmt visit(ThrowStmt s)
	{
		s.exp = visit(s.exp);
		return s;
	}
	
	public override AssignStmt visit(AssignStmt s)
	{
		foreach(ref exp; s.lhs)
			exp = visit(exp);

		s.rhs = visit(s.rhs);
		return s;
	}

	public OpAssignStmt visitOpAssign(OpAssignStmt s)
	{
		s.lhs = visit(s.lhs);
		s.rhs = visit(s.rhs);
		return s;
	}
	
	public override AddAssignStmt visit(AddAssignStmt s)   { return visitOpAssign(s); }
	public override SubAssignStmt visit(SubAssignStmt s)   { return visitOpAssign(s); }
	public override MulAssignStmt visit(MulAssignStmt s)   { return visitOpAssign(s); }
	public override DivAssignStmt visit(DivAssignStmt s)   { return visitOpAssign(s); }
	public override ModAssignStmt visit(ModAssignStmt s)   { return visitOpAssign(s); }
	public override ShlAssignStmt visit(ShlAssignStmt s)   { return visitOpAssign(s); }
	public override ShrAssignStmt visit(ShrAssignStmt s)   { return visitOpAssign(s); }
	public override UShrAssignStmt visit(UShrAssignStmt s) { return visitOpAssign(s); }
	public override XorAssignStmt visit(XorAssignStmt s)   { return visitOpAssign(s); }
	public override OrAssignStmt visit(OrAssignStmt s)     { return visitOpAssign(s); }
	public override AndAssignStmt visit(AndAssignStmt s)   { return visitOpAssign(s); }

	public override CondAssignStmt visit(CondAssignStmt s)
	{
		s.lhs = visit(s.lhs);
		s.rhs = visit(s.rhs);

		if(s.rhs.isConstant() && s.rhs.isNull())
			return new(c) BlockStmt(c, s.location, s.endLocation, null);

		return s;
	}

	public override CatAssignStmt visit(CatAssignStmt s)
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
			scope dummy = new List!(Expression)(c.alloc);
			dummy ~= s.rhs;
			s.operands = dummy.toArray();
		}

		s.collapsed = true;
		return s;
	}
	
	public override IncStmt visit(IncStmt s)
	{
		s.exp = visit(s.exp);
		return s;
	}
	
	public override DecStmt visit(DecStmt s)
	{
		s.exp = visit(s.exp);
		return s;
	}
	
	public override Expression visit(CondExp e)
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
	
	public override Expression visit(OrOrExp e)
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
	
	public override Expression visit(AndAndExp e)
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
	
	public override Expression visit(OrExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(!e.op1.isInt || !e.op2.isInt)
				c.exception(e.location, "Bitwise Or must be performed on integers");

			return new(c) IntExp(c, e.location, e.op1.asInt() | e.op2.asInt());
		}

		return e;
	}
	
	public override Expression visit(XorExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(!e.op1.isInt || !e.op2.isInt)
				c.exception(e.location, "Bitwise Xor must be performed on integers");

			return new(c) IntExp(c, e.location, e.op1.asInt() ^ e.op2.asInt());
		}

		return e;
	}
	
	public override Expression visit(AndExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(!e.op1.isInt || !e.op2.isInt)
				c.exception(e.location, "Bitwise And must be performed on integers");

			return new(c) IntExp(c, e.location, e.op1.asInt() & e.op2.asInt());
		}

		return e;
	}

	public Expression visitEquality(BaseEqualExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		bool isTrue = e.type == AstTag.EqualExp || e.type == AstTag.IsExp;

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(e.op1.isNull && e.op2.isNull)
				return new(c) BoolExp(c, e.location, isTrue);

			if(e.op1.isBool && e.op2.isBool)
				return new(c) BoolExp(c, e.location, isTrue ? e.op1.asBool() == e.op2.asBool() : e.op1.asBool() != e.op2.asBool());

			if(e.op1.isInt && e.op2.isInt)
				return new(c) BoolExp(c, e.location, isTrue ? e.op1.asInt() == e.op2.asInt() : e.op1.asInt() != e.op2.asInt());

			if(e.type == AstTag.IsExp || e.type == AstTag.NotIsExp)
			{
				if(e.op1.isFloat && e.op2.isFloat)
					return new(c) BoolExp(c, e.location, isTrue ? e.op1.asFloat() == e.op2.asFloat() : e.op1.asFloat() != e.op2.asFloat());
			}
			else
			{
				if((e.op1.isInt || e.op1.isFloat) && (e.op2.isInt || e.op2.isFloat))
					return new(c) BoolExp(c, e.location, isTrue ? e.op1.asFloat() == e.op2.asFloat() : e.op1.asFloat() != e.op2.asFloat());
			}

			if(e.op1.isChar && e.op2.isChar)
				return new(c) BoolExp(c, e.location, isTrue ? e.op1.asChar() == e.op2.asChar() : e.op1.asChar() != e.op2.asChar());

			if(e.op1.isString && e.op2.isString)
				return new(c) BoolExp(c, e.location, isTrue ? e.op1.asString() == e.op2.asString() : e.op1.asString() != e.op2.asString());

			if(e.type == AstTag.IsExp || e.type == AstTag.NotIsExp)
				return new(c) BoolExp(c, e.location, !isTrue);
			else
				c.exception(e.location, "Cannot compare different types");
		}

		return e;
	}
	
	public override Expression visit(EqualExp e)    { return visitEquality(e); }
	public override Expression visit(NotEqualExp e) { return visitEquality(e); }
	public override Expression visit(IsExp e)       { return visitEquality(e); }
	public override Expression visit(NotIsExp e)    { return visitEquality(e); }

	public word commonCompare(Expression op1, Expression op2)
	{
		word cmpVal = void;

		if(op1.isNull && op2.isNull)
			cmpVal = 0;
		else if(op1.isInt && op2.isInt)
			cmpVal = Compare3(op1.asInt(), op2.asInt());
		else if((op1.isInt || op1.isFloat) && (op2.isInt || op2.isFloat))
			cmpVal = Compare3(op1.asFloat(), op2.asFloat());
		else if(op1.isChar && op2.isChar)
			cmpVal = Compare3(op1.asChar, op2.asChar);
		else if(op1.isString && op2.isString)
			cmpVal = scmp(op1.asString(), op2.asString());
		else
			c.exception(op1.location, "Invalid compile-time comparison");
			
		return cmpVal;
	}

	public Expression visitComparison(BaseCmpExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			auto cmpVal = commonCompare(e.op1, e.op2);

			switch(e.type)
			{
				case AstTag.LTExp: return new(c) BoolExp(c, e.location, cmpVal < 0);
				case AstTag.LEExp: return new(c) BoolExp(c, e.location, cmpVal <= 0);
				case AstTag.GTExp: return new(c) BoolExp(c, e.location, cmpVal > 0);
				case AstTag.GEExp: return new(c) BoolExp(c, e.location, cmpVal >= 0);
				default: assert(false, "BaseCmpExp fold");
			}
		}

		return e;
	}
	
	public override Expression visit(LTExp e) { return visitComparison(e); }
	public override Expression visit(LEExp e) { return visitComparison(e); }
	public override Expression visit(GTExp e) { return visitComparison(e); }
	public override Expression visit(GEExp e) { return visitComparison(e); }

	public override Cmp3Exp visit(Cmp3Exp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
			return new(c) IntExp(c, e.location, commonCompare(e.op1, e.op2));

		return e;
	}

	public override AsExp visit(AsExp e)
	{
		if(e.op1.isConstant() || e.op2.isConstant())
			c.exception(e.location, "Neither argument of an 'as' expression may be a constant");

		return e;
	}
	
	// TODO: maybe do folding of 'in'?

	public override Expression visit(ShlExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(!e.op1.isInt || !e.op2.isInt)
				c.exception(e.location, "Bitwise left-shift must be performed on integers");

			return new(c) IntExp(c, e.location, e.op1.asInt() << e.op2.asInt());
		}

		return e;
	}
	
	public override Expression visit(ShrExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(!e.op1.isInt || !e.op2.isInt)
				c.exception(e.location, "Bitwise right-shift must be performed on integers");

			return new(c) IntExp(c, e.location, e.op1.asInt() >> e.op2.asInt());
		}

		return e;
	}
	
	public override Expression visit(UShrExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(!e.op1.isInt || !e.op2.isInt)
				c.exception(e.location, "Bitwise unsigned right-shift must be performed on integers");

			return new(c) IntExp(c, e.location, e.op1.asInt() >>> e.op2.asInt());
		}

		return e;
	}
	
	public override Expression visit(AddExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(e.op1.isInt && e.op2.isInt)
				return new(c) IntExp(c, e.location, e.op1.asInt() + e.op2.asInt());
			else if((e.op1.isInt || e.op1.isFloat) && (e.op2.isInt || e.op2.isFloat))
				return new(c) FloatExp(c, e.location, e.op1.asFloat() + e.op2.asFloat());
			else
				c.exception(e.location, "Addition must be performed on numbers");
		}

		return e;
	}

	public override Expression visit(SubExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(e.op1.isInt && e.op2.isInt)
				return new(c) IntExp(c, e.location, e.op1.asInt() - e.op2.asInt());
			else if((e.op1.isInt || e.op1.isFloat) && (e.op2.isInt || e.op2.isFloat))
				return new(c) FloatExp(c, e.location, e.op1.asFloat() - e.op2.asFloat());
			else
				c.exception(e.location, "Subtraction must be performed on numbers");
		}

		return e;
	}
	
	public override Expression visit(CatExp e)
	{
		if(e.collapsed)
			return e;

		e.collapsed = true;

		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		// Collapse
		{
			scope tmp = new List!(Expression)(c.alloc);

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
		scope newOperands = new List!(Expression)(c.alloc);
		scope tempStr = new List!(char)(c.alloc);

		auto ops = e.operands;

		for(word i = 0; i < ops.length; i++)
		{
			// this first case can only happen when the last item in the array can't be folded.  otherwise i will be set to ops.length - 1,
			// incremented, and the loop will break.
			if(i == ops.length - 1)
				newOperands ~= ops[i];
			else if(ops[i].isConstant && ops[i + 1].isConstant)
			{
				if((ops[i].isString || ops[i].isChar) && (ops[i + 1].isString || ops[i + 1].isChar))
				{
					word j = i + 2;
					
					for(; j < ops.length && (ops[j].isString || ops[j].isChar); j++)
					{}
					
					// j points to first non-const non-string non-char operand
					foreach(op; ops[i .. j])
					{
						if(op.isString)
							tempStr ~= op.asString();
						else
							tempStr ~= op.asChar();
					}

					newOperands ~= new(c) StringExp(c, e.location, c.newString(tempStr.toArray()));
					
					i = j - 1;
				}
				else
					newOperands ~= ops[i];
			}
			else
				newOperands ~= ops[i];
		}

		c.alloc.freeArray(e.operands);

		if(newOperands.length == 1)
		{
			auto arr = newOperands.toArray();
			auto ret = arr[0];
			c.alloc.freeArray(arr);
			return ret;
		}
		else
		{
			e.operands = newOperands.toArray();
			return e;
		}
	}

	public override Expression visit(MulExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(e.op1.isInt && e.op2.isInt)
				return new(c) IntExp(c, e.location, e.op1.asInt() * e.op2.asInt());
			else if((e.op1.isInt || e.op1.isFloat) && (e.op2.isInt || e.op2.isFloat))
				return new(c) FloatExp(c, e.location, e.op1.asFloat() * e.op2.asFloat());
			else
				c.exception(e.location, "Multiplication must be performed on numbers");
		}

		return e;
	}
	
	public override Expression visit(DivExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(e.op1.isInt && e.op2.isInt)
			{
				if(e.op2.asInt() == 0)
					c.exception(e.location, "Division by 0");

				return new(c) IntExp(c, e.location, e.op1.asInt() / e.op2.asInt());
			}
			else if((e.op1.isInt || e.op1.isFloat) && (e.op2.isInt || e.op2.isFloat))
				return new(c) FloatExp(c, e.location, e.op1.asFloat() / e.op2.asFloat());
			else
				c.exception(e.location, "Division must be performed on numbers");
		}

		return e;
	}

	public override Expression visit(ModExp e)
	{
		e.op1 = visit(e.op1);
		e.op2 = visit(e.op2);

		if(e.op1.isConstant && e.op2.isConstant)
		{
			if(e.op1.isInt && e.op2.isInt)
			{
				if(e.op2.asInt() == 0)
					c.exception(e.location, "Modulo by 0");

				return new(c) IntExp(c, e.location, e.op1.asInt() % e.op2.asInt());
			}
			else if((e.op1.isInt || e.op1.isFloat) && (e.op2.isInt || e.op2.isFloat))
				return new(c) FloatExp(c, e.location, e.op1.asFloat() % e.op2.asFloat());
			else
				c.exception(e.location, "Modulo must be performed on numbers");
		}

		return e;
	}
	
	public override Expression visit(NegExp e)
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
				c.exception(e.location, "Negation must be performed on numbers");
		}

		return e;
	}
	
	public override Expression visit(NotExp e)
	{
		e.op = visit(e.op);

		if(e.op.isConstant)
			return new(c) BoolExp(c, e.location, !e.op.isTrue);

		switch(e.op.type)
		{
			case AstTag.LTExp:       auto old = e.as!(LTExp);       return new(c) GEExp(c, e.location, e.endLocation, old.op1, old.op2);
			case AstTag.LEExp:       auto old = e.as!(LEExp);       return new(c) GTExp(c, e.location, e.endLocation, old.op1, old.op2);
			case AstTag.GTExp:       auto old = e.as!(GTExp);       return new(c) LEExp(c, e.location, e.endLocation, old.op1, old.op2);
			case AstTag.GEExp:       auto old = e.as!(GEExp);       return new(c) LTExp(c, e.location, e.endLocation, old.op1, old.op2);
			case AstTag.EqualExp:    auto old = e.as!(EqualExp);    return new(c) NotEqualExp(c, e.location, e.endLocation, old.op1, old.op2);
			case AstTag.NotEqualExp: auto old = e.as!(NotEqualExp); return new(c) EqualExp(c, e.location, e.endLocation, old.op1, old.op2);
			case AstTag.IsExp:       auto old = e.as!(IsExp);       return new(c) NotIsExp(c, e.location, e.endLocation, old.op1, old.op2);
			case AstTag.NotIsExp:    auto old = e.as!(NotIsExp);    return new(c) IsExp(c, e.location, e.endLocation, old.op1, old.op2);
			case AstTag.InExp:       auto old = e.as!(InExp);       return new(c) NotInExp(c, e.location, e.endLocation, old.op1, old.op2);
			case AstTag.NotInExp:    auto old = e.as!(NotInExp);    return new(c) InExp(c, e.location, e.endLocation, old.op1, old.op2);

			// TODO: what about multiple 'not's?  "!!x"

			default:
				break;
		}

		return e;
	}

	public override Expression visit(ComExp e)
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
				c.exception(e.location, "Bitwise complement must be performed on integers");
		}

		return e;
	}
	
	public override Expression visit(LenExp e)
	{
		e.op = visit(e.op);

		if(e.op.isConstant)
		{
			if(e.op.isString)
				return new(c) IntExp(c, e.location, e.op.asString().length);
			else
				c.exception(e.location, "Length must be performed on a string at compile time");
		}

		return e;
	}
	
	public override Expression visit(CoroutineExp e)
	{
		e.op = visit(e.op);
		return e;
	}
	
	public override Expression visit(DotExp e)
	{
		e.op = visit(e.op);
		e.name = visit(e.name);

		if(e.name.isConstant && !e.name.isString)
			c.exception(e.name.location, "Field name must be a string");

		return e;
	}
	
	public override Expression visit(DotSuperExp e)
	{
		e.op = visit(e.op);
		return e;
	}

	public override Expression visit(MethodCallExp e)
	{
		if(e.op)
			e.op = visit(e.op);
			
		e.method = visit(e.method);

		if(e.method.isConstant && !e.method.isString)
			c.exception(e.method.location, "Method name must be a string");

		if(e.context)
			e.context = visit(e.context);

		foreach(ref arg; e.args)
			arg = visit(arg);

		return e;
	}
	
	public override Expression visit(CallExp e)
	{
		e.op = visit(e.op);

		if(e.context)
			e.context = visit(e.context);

		foreach(ref arg; e.args)
			arg = visit(arg);

		return e;
	}
	
	public override Expression visit(IndexExp e)
	{
		e.op = visit(e.op);
		e.index = visit(e.index);

		if(e.op.isConstant && e.index.isConstant)
		{
			if(!e.op.isString || !e.index.isInt)
				c.exception(e.location, "Can only index strings with integers at compile time");

			auto idx = e.index.asInt();

			if(idx < 0)
				idx += e.op.asString.length;

			if(idx < 0 || idx >= e.op.asString.length)
				c.exception(e.location, "Invalid string index");

			return new(c) CharExp(c, e.location, e.op.asString[idx]);
		}

		return e;
	}
	
	public override Expression visit(VargIndexExp e)
	{
		e.index = visit(e.index);

		if(e.index.isConstant && !e.index.isInt)
			c.exception(e.index.location, "index of a vararg indexing must be an integer");

		return e;
	}
	
	public override Expression visit(SliceExp e)
	{
		e.op = visit(e.op);
		e.loIndex = visit(e.loIndex);
		e.hiIndex = visit(e.hiIndex);

		if(e.op.isConstant && e.loIndex.isConstant && e.hiIndex.isConstant)
		{
			if(!e.op.isString || (!e.loIndex.isInt && !e.loIndex.isNull) || (!e.hiIndex.isInt && !e.hiIndex.isNull))
				c.exception(e.location, "Can only slice strings with integers at compile time");

			auto str = e.op.asString();
			word l, h;

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

			if(l < 0 || l >= str.length || h < 0 || h >= str.length || l > h)
				c.exception(e.location, "Invalid slice indices");

			return new(c) StringExp(c, e.location, c.newString(str[l .. h]));
		}

		return e;
	}
	
	public override Expression visit(VargSliceExp e)
	{
		e.loIndex = visit(e.loIndex);
		e.hiIndex = visit(e.hiIndex);

		if(e.loIndex.isConstant && !(e.loIndex.isNull || e.loIndex.isInt))
			c.exception(e.loIndex.location, "low index of vararg slice must be null or int");

		if(e.hiIndex.isConstant && !(e.hiIndex.isNull || e.hiIndex.isInt))
			c.exception(e.hiIndex.location, "high index of vararg slice must be null or int");

		return e;
	}
	
	public override FuncLiteralExp visit(FuncLiteralExp e)
	{
		e.def = visit(e.def);
		return e;
	}
	
	public override ObjectLiteralExp visit(ObjectLiteralExp e)
	{
		e.def = visit(e.def);
		return e;
	}
	
	public override Expression visit(NamespaceCtorExp e)
	{
		return visit(e.def);
	}
	
	public override Expression visit(ParenExp e)
	{
		e.exp = visit(e.exp);

		if(e.exp.isMultRet())
			return e;
		else
			return e.exp;
	}

	public override TableCtorExp visit(TableCtorExp e)
	{
		foreach(ref field; e.fields)
		{
			field.key = visit(field.key);
			field.value = visit(field.value);
		}

		return e;
	}
	
	public override ArrayCtorExp visit(ArrayCtorExp e)
	{
		foreach(ref value; e.values)
			value = visit(value);

		return e;
	}
	
	public override YieldExp visit(YieldExp e)
	{
		foreach(ref arg; e.args)
			arg = visit(arg);

		return e;
	}
	
	public override TableComprehension visit(TableComprehension e)
	{
		e.key = visit(e.key);
		e.value = visit(e.value);
		e.forComp = visitForComp(e.forComp);

		/*
		Rewrite:
		
		x = {[v] = k for k, v in y if v < 10}

		as:

		x = (function()
		{
			local __temp = {}

			foreach(k, v; y)
				if(v < 10)
					__temp[v] = k

			return __temp
		})()
		*/

		// (function()
		scope funcBody = new List!(Statement)(c.alloc);

		{
			auto __temp = new(c) Identifier(c, e.location, c.newString("__temp"));

			// local __temp = {}
			{
				scope dummy = new List!(Identifier)(c.alloc);
				dummy ~= __temp;
				auto init = new(c) TableCtorExp(c, e.location, e.endLocation, null);
				funcBody ~= new(c) VarDecl(c, e.location, e.endLocation, Protection.Local, dummy.toArray(), init);
			}

			// foreach(i; y)
			//     if(i < 10)
			//         __temp[v] = k
			{
				scope dummy = new List!(Expression)(c.alloc);
				dummy ~= new(c) IndexExp(c, e.endLocation, new(c) IdentExp(c, __temp), e.key);
				auto idxa = new(c) AssignStmt(c, e.location, e.endLocation, dummy.toArray(), e.value);
				funcBody ~= rewriteForComp(e.forComp, idxa);
			}


			// return __temp
			{
				scope dummy = new List!(Expression)(c.alloc);
				dummy ~= new(c) IdentExp(c, __temp);
				funcBody ~= new(c) ReturnStmt(c, e.location, e.location, dummy.toArray());
			}
		}

		auto _body = new(c) BlockStmt(c, e.location, e.endLocation, funcBody.toArray());
		scope params = new List!(FuncDef.Param)(c.alloc);
		params ~= FuncDef.Param(new(c) Identifier(c, e.location, c.newString("this")));
		auto funcDef = new(c) FuncDef(c, e.location, dummyComprehensionName!("table")(e.location), params.toArray(), false, _body);
		auto funcExp = new(c) FuncLiteralExp(c, e.location, funcDef);
		return new(c) CallExp(c, e.endLocation, funcExp, null, null);
	}

	public override Expression visit(ArrayComprehension e)
	{
		e.exp = visit(e.exp);
		e.forComp = visitForComp(e.forComp);

		/*
		Rewrite:
		
		x = [i for i in y if i < 10]
		
		as:

		x = (function()
		{
			local __temp = []

			foreach(i; y)
				if(i < 10)
					append __temp, i

			return __temp
		})()
		*/

		// (function()
		scope funcBody = new List!(Statement)(c.alloc);

		{
			auto __temp = new(c) Identifier(c, e.location, c.newString("__temp"));
			auto __tempExp = new(c) IdentExp(c, __temp);

			// local __temp = []
			{
				scope dummy = new List!(Identifier)(c.alloc);
				dummy ~= __temp;
				auto init = new(c) ArrayCtorExp(c, e.location, e.endLocation, null);
				funcBody ~= new(c) VarDecl(c, e.location, e.endLocation, Protection.Local, dummy.toArray(), init);
			}

			// append __temp, i
			auto append = new(c) AppendStmt(c, e.location, __tempExp, e.exp);

			// foreach(i; y)
			//     if(i < 10)
			funcBody ~= rewriteForComp(e.forComp, append);

			// return __temp
			{
				scope dummy = new List!(Expression)(c.alloc);
				dummy ~= __tempExp;
				funcBody ~= new(c) ReturnStmt(c, e.location, e.location, dummy.toArray());
			}
		}

		auto _body = new(c) BlockStmt(c, e.location, e.endLocation, funcBody.toArray());
		scope params = new List!(FuncDef.Param)(c.alloc);
		params ~= FuncDef.Param(new(c) Identifier(c, e.location, c.newString("this")));
		auto funcDef = new(c) FuncDef(c, e.location, dummyComprehensionName!("array")(e.location), params.toArray(), false, _body);
		auto funcExp = new(c) FuncLiteralExp(c, e.location, funcDef);
		return new(c) CallExp(c, e.endLocation, funcExp, null, null);
	}

	private Statement rewriteForComp(ForComprehension e, Statement inner)
	{
		if(auto x = e.as!(ForeachComprehension))
			return rewrite(x, inner);
		else
		{
			auto x = e.as!(ForNumComprehension);
			assert(x !is null);
			return rewrite(x, inner);
		}
	}

	private Statement rewrite(ForeachComprehension e, Statement inner)
	{
		if(e.ifComp)
		{
			if(e.forComp)
				inner = rewrite(e.ifComp, rewriteForComp(e.forComp, inner));
			else
				inner = rewrite(e.ifComp, inner);
		}
		else if(e.forComp)
			inner = rewriteForComp(e.forComp, inner);

		auto indices = e.indices;
		auto cont = e.container;
		e.indices = null;
		e.container = null;
		return new(c) ForeachStmt(c, e.location, indices, cont, inner);
	}

	private Statement rewrite(ForNumComprehension e, Statement inner)
	{
		if(e.ifComp)
		{
			if(e.forComp)
				inner = rewrite(e.ifComp, rewriteForComp(e.forComp, inner));
			else
				inner = rewrite(e.ifComp, inner);
		}
		else if(e.forComp)
			inner = rewriteForComp(e.forComp, inner);

		return new(c) ForNumStmt(c, e.location, e.index, e.lo, e.hi, e.step, inner);
	}
	
	private Statement rewrite(IfComprehension e, Statement inner)
	{
		return new(c) IfStmt(c, e.location, e.endLocation, null, e.condition, inner, null);
	}

	public ForComprehension visitForComp(ForComprehension e)
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

	public override ForeachComprehension visit(ForeachComprehension e)
	{
		foreach(ref exp; e.container)
			exp = visit(exp);

		if(e.ifComp)
			e.ifComp = visit(e.ifComp);

		if(e.forComp)
			e.forComp = visitForComp(e.forComp);

		return e;
	}
	
	public override ForNumComprehension visit(ForNumComprehension e)
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
	
	public override IfComprehension visit(IfComprehension e)
	{
		e.condition = visit(e.condition);
		return e;
	}

	package Identifier dummyComprehensionName(char[] type)(CompileLoc loc)
	{
		pushFormat(c.thread, "<" ~ type ~ " comprehension at {}({}:{})>", loc.file, loc.line, loc.col);
		auto str = c.newString(getString(c.thread, -1));
		pop(c.thread);
		return new(c) Identifier(c, loc, str);
	}
}