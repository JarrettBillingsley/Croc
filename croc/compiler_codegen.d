/******************************************************************************
This module defines an AST visitor which performs code generation on an AST
that has already been semantic'ed.

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

module croc.compiler_codegen;

// debug = PRINTEXPSTACK;

import croc.api_interpreter;
import croc.api_stack;
import croc.base_alloc;
import croc.compiler_ast;
import croc.compiler_astvisitor;
import croc.compiler_funcstate;
import croc.compiler_types;
import croc.types;

// TODO: abstract codegen enough that we don't need to use the Op1/Op2 values directly
import croc.base_opcodes;

scope class Codegen : Visitor
{
private:
	FuncState fs;

public:
	this(ICompiler c)
	{
		super(c);
	}

	alias Visitor.visit visit;

	void codegenStatements(FuncDef d)
	{
		scope fs_ = new FuncState(c, d.location, d.name.name, null);

		{
			fs = fs_;
			scope(exit)
				fs = null;

			fs.setVararg(d.isVararg);
			fs.setNumParams(d.params.length);

			Scope scop = void;
			fs.pushScope(scop);
				foreach(ref p; d.params)
					fs.addParam(p.name, p.typeMask);

				fs.activateLocals(d.params.length);

				visit(d.code);
			fs.popScope(d.code.endLocation);
			fs.defaultReturn(d.code.endLocation);
		}

		auto def = fs_.toFuncDef();
		push(c.thread, CrocValue(def));
		insertAndPop(c.thread, -2);
	}

	override Module visit(Module m)
	{
		scope fs_ = new FuncState(c, m.location, c.newString("<top-level>"), null);

		try
		{
			fs = fs_;
			scope(exit)
				fs = null;

			fs.setNumParams(1);

			Scope scop = void;
			fs.pushScope(scop);
				fs.insertLocal(new(c) Identifier(c, m.location, c.newString("this")));
				fs.activateLocals(1);

				visit(m.statements);

				if(m.decorator)
				{
					visitDecorator(m.decorator, { fs.pushThis(); });
					fs.popToNothing();
				}
			fs.popScope(m.endLocation);
			fs.defaultReturn(m.endLocation);

			debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		}
		finally
		{
			debug(PRINTEXPSTACK)
				fs.printExpStack();
		}

		auto def = fs_.toFuncDef();
		push(c.thread, CrocValue(def));
		insertAndPop(c.thread, -2);

		return m;
	}

	override ClassDef visit(ClassDef d)
	{
		classDefBegin(d); // leaves local containing class on the stack
		classDefEnd(d); // still leaves it

		return d;
	}

	void classDefBegin(ClassDef d)
	{
		fs.pushString(d.name.name);

		if(d.baseClass)
		{
			visit(d.baseClass);
			fs.toSource(d.baseClass.location);
		}
		else
		{
			fs.pushNull();
			fs.toSource(d.location);
		}

		fs.newClass(d.location);
	}

	void classDefEnd(ClassDef d)
	{
		if(d.fields.length == 0)
			return;

		fs.toSource(d.location);

		foreach(ref field; d.fields)
		{
			fs.dup();
			fs.pushString(field.name);
			fs.toSource(field.initializer.location);
			fs.field();
			visit(field.initializer);
			fs.assign(field.initializer.location, 1, 1);
		}
	}

	override NamespaceDef visit(NamespaceDef d)
	{
		auto desc = namespaceDefBegin(d);
		namespaceDefEnd(d, desc);
		return d;
	}

	NamespaceDesc namespaceDefBegin(NamespaceDef d)
	{
		fs.pushString(d.name.name);

		if(d.parent)
		{
			visit(d.parent);
			fs.toSource(d.parent.location);
			fs.newNamespace(d.location);
		}
		else
			fs.newNamespaceNP(d.location);

		return fs.beginNamespace(d.location);
	}

	void namespaceDefEnd(NamespaceDef d, ref NamespaceDesc desc)
	{
		if(d.fields.length)
		{
			fs.toSource(d.location);

			foreach(ref field; d.fields)
			{
				fs.dup();
				fs.pushString(field.name);
				fs.toSource(field.initializer.location);
				fs.field();
				visit(field.initializer);
				fs.assign(field.initializer.location, 1, 1);
			}
		}

		fs.endNamespace(desc);
	}

	override FuncDef visit(FuncDef d)
	{
		scope inner = new FuncState(c, d.location, d.name.name, fs);

		{
			fs = inner;
			scope(exit)
				fs = fs.parent();

			fs.setVararg(d.isVararg);
			fs.setNumParams(d.params.length);

			Scope scop = void;
			fs.pushScope(scop);
				foreach(ref p; d.params)
					fs.addParam(p.name, p.typeMask);

				fs.activateLocals(d.params.length);

				visit(d.code);
			fs.popScope(d.code.endLocation);
			fs.defaultReturn(d.code.endLocation);
		}

		fs.pushClosure(inner);

		return d;
	}

	override TypecheckStmt visit(TypecheckStmt s)
	{
		alias FuncDef.TypeMask TypeMask;
		bool needParamCheck = false;

		foreach(ref p; s.def.params)
		{
			if(p.typeMask != TypeMask.Any)
			{
				needParamCheck = true;
				break;
			}
		}

		/*
		if(s.def.params.any((ref Param p) { return p.typeMask != TypeMask.Any; }))
		if(s.def.params.findIf((ref Param p) { return p.typeMask != TypeMask.Any; }) != s.def.params.length)
			fs.paramCheck(s.def.code.location);
		*/

		if(needParamCheck)
			fs.paramCheck(s.def.code.location);


		foreach(idx, ref p; s.def.params)
		{
			if(p.classTypes.length > 0)
			{
				InstRef success;

				foreach(t; p.classTypes)
				{
					visit(t);
					fs.toSource(t.endLocation);
					fs.catToTrue(success, fs.checkObjParam(t.endLocation, idx));
				}

				fs.objParamFail(p.classTypes[$ - 1].endLocation, idx);
				fs.patchTrueToHere(success);
			}
			else if(p.customConstraint)
			{
				InstRef success;

				auto con = p.customConstraint;
				visit(con);
				fs.toSource(con.endLocation);
				fs.catToTrue(success, fs.codeIsTrue(con.endLocation));

				dottedNameToString(con.as!(CallExp).op);
				fs.pushString(getString(c.thread, -1));
				fs.toSource(con.endLocation);
				fs.customParamFail(con.endLocation, idx);
				pop(c.thread);
				fs.patchTrueToHere(success);
			}
		}

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	word dottedNameToString(Expression exp)
	{
		int work(Expression exp)
		{
			if(auto n = exp.as!(IdentExp))
			{
				pushString(c.thread, n.name.name);
				return 1;
			}
			else if(auto n = exp.as!(DotExp))
			{
				auto ret = work(n.op);
				pushString(c.thread, ".");
				pushString(c.thread, n.name.as!(StringExp).value);
				return ret + 2;
			}
			else
				assert(false);
		}

		return cat(c.thread, work(exp));
	}

	override ImportStmt visit(ImportStmt s)
	{
		assert(false);
	}

	override ScopeStmt visit(ScopeStmt s)
	{
		Scope scop = void;
		fs.pushScope(scop);
		visit(s.statement);
		fs.popScope(s.endLocation);
		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override ExpressionStmt visit(ExpressionStmt s)
	{
		visit(s.expr);
		fs.popToNothing();
		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	void visitDecorator(Decorator d, void delegate() obj)
	{
		uword genArgs()
		{
			if(d.nextDec)
			{
				visitDecorator(d.nextDec, obj);
				fs.toSource(d.nextDec.endLocation);
				fs.toTemporary(d.nextDec.endLocation);
			}
			else
			{
				obj();
				fs.toSource(d.location);
				fs.toTemporary(d.location);
			}

			codeGenList(d.args);
			return d.args.length + 1; // 1 for nextDec/obj
		}

		if(auto dot = d.func.as!(DotExp))
		{
			if(d.context !is null)
				c.semException(d.location, "'with' is disallowed on method calls");
			visitMethodCall(d.location, d.endLocation, false, dot.op, dot.name, &genArgs);
		}
		else
			visitCall(d.endLocation, d.func, d.context, &genArgs);
	}

	override FuncDecl visit(FuncDecl d)
	{
		if(d.protection == Protection.Local)
		{
			fs.insertLocal(d.def.name);
			fs.activateLocals(1);
			fs.pushVar(d.def.name);
		}
		else
		{
			assert(d.protection == Protection.Global);
			fs.pushNewGlobal(d.def.name);
		}

		visit(d.def);
		fs.assign(d.endLocation, 1, 1);

		if(d.decorator)
		{
			fs.pushVar(d.def.name);
			visitDecorator(d.decorator, { fs.pushVar(d.def.name); });
			fs.assign(d.endLocation, 1, 1);
		}

		return d;
	}

	override ClassDecl visit(ClassDecl d)
	{
		if(d.protection == Protection.Local)
		{
			fs.insertLocal(d.def.name);
			fs.activateLocals(1);
			fs.pushVar(d.def.name);
		}
		else
		{
			assert(d.protection == Protection.Global);
			fs.pushNewGlobal(d.def.name);
		}

		// put empty class in d.name
		classDefBegin(d.def);
		fs.assign(d.location, 1, 1);

		// evaluate rest of decl
		fs.pushVar(d.def.name);
		classDefEnd(d.def);
		fs.pop();

		if(d.decorator)
		{
			// reassign decorated class into name
			fs.pushVar(d.def.name);
			visitDecorator(d.decorator, { fs.pushVar(d.def.name); });
			fs.assign(d.endLocation, 1, 1);
		}

		return d;
	}

	override NamespaceDecl visit(NamespaceDecl d)
	{
		if(d.protection == Protection.Local)
		{
			fs.insertLocal(d.def.name);
			fs.activateLocals(1);
			fs.pushVar(d.def.name);
		}
		else
		{
			assert(d.protection == Protection.Global);
			fs.pushNewGlobal(d.def.name);
		}

		// put empty namespace in d.name
		auto desc = namespaceDefBegin(d.def);
		fs.assign(d.location, 1, 1);

		// evaluate rest of decl
		fs.pushVar(d.def.name);
		namespaceDefEnd(d.def, desc);
		fs.pop();

		if(d.decorator)
		{
			// reassign decorated namespace into name
			fs.pushVar(d.def.name);
			visitDecorator(d.decorator, { fs.pushVar(d.def.name); });
			fs.assign(d.endLocation, 1, 1);
		}

		return d;
	}

	override VarDecl visit(VarDecl d)
	{
		// Check for name conflicts within the definition
		foreach(i, n; d.names)
		{
			foreach(n2; d.names[0 .. i])
			{
				if(n.name == n2.name)
				{
					auto loc = n2.location;
					c.semException(n.location, "Variable '{}' conflicts with previous definition at {}({}:{})", n.name, loc.file, loc.line, loc.col);
				}
			}
		}

		if(d.protection == Protection.Global)
		{
			foreach(n; d.names)
				fs.pushNewGlobal(n);

			codeGenAssignRHS(d.initializer);
			fs.assign(d.location, d.names.length, d.initializer.length);
		}
		else
		{
			fs.pushNewLocals(d.names.length);
			codeGenList(d.initializer);
			fs.assign(d.location, d.names.length, d.initializer.length);

			foreach(n; d.names)
				fs.insertLocal(n);

			fs.activateLocals(d.names.length);
		}

		return d;
	}

	override BlockStmt visit(BlockStmt s)
	{
		foreach(st; s.statements)
			visit(st);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override AssertStmt visit(AssertStmt s)
	{
		assert(c.asserts()); // can't have made it here unless asserts are enabled
		
		InstRef i = codeCondition(s.cond);
		fs.patchFalseToHere(i);
		visit(s.msg);
		fs.assertFail(s.location);
		fs.patchTrueToHere(i);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override IfStmt visit(IfStmt s)
	{
		if(s.elseBody)
			visitIf(s.location, s.endLocation, s.elseBody.location, s.condVar, s.condition, { visit(s.ifBody); }, { visit(s.elseBody); });
		else
			visitIf(s.location, s.endLocation, s.endLocation, s.condVar, s.condition, { visit(s.ifBody); }, null);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	void visitIf(CompileLoc location, CompileLoc endLocation, CompileLoc elseLocation, IdentExp condVar, Expression condition, void delegate() genBody, void delegate() genElse)
	{
		Scope scop = void;
		fs.pushScope(scop);

		InstRef i = void;

		if(condVar !is null)
		{
			fs.pushNewLocals(1);
			visit(condition);
			fs.assign(condition.location, 1, 1);
			fs.insertLocal(condVar.name);
			fs.activateLocals(1);

			i = codeCondition(condVar);
		}
		else
			i = codeCondition(condition);

		fs.invertJump(i);
		fs.patchTrueToHere(i);
		genBody();

		if(genElse !is null)
		{
			fs.popScope(elseLocation);

			auto j = fs.makeJump(elseLocation);
			fs.patchFalseToHere(i);

			fs.pushScope(scop);
				genElse();
			fs.popScope(endLocation);

			fs.patchJumpToHere(j);
		}
		else
		{
			fs.popScope(endLocation);
			fs.patchFalseToHere(i);
		}
	}

	override WhileStmt visit(WhileStmt s)
	{
		auto beginLoop = fs.here();

		Scope scop = void;
		fs.pushScope(scop);

		// s.condition.isConstant && !s.condition.isTrue is handled in semantic
		if(s.condition.isConstant && s.condition.isTrue)
		{
			fs.setBreakable();
			fs.setContinuable();
			fs.setScopeName(s.name);

			if(s.condVar !is null)
			{
				fs.pushNewLocals(1);
				visit(s.condition);
				fs.assign(s.condition.location, 1, 1);
				fs.insertLocal(s.condVar.name);
				fs.activateLocals(1);
			}

			visit(s.code);
			fs.patchContinuesTo(beginLoop);
			fs.jumpTo(s.endLocation, beginLoop);
			fs.patchBreaksToHere();
			fs.popScope(s.endLocation);
		}
		else
		{
			InstRef cond = void;

			if(s.condVar !is null)
			{
				fs.pushNewLocals(1);
				visit(s.condition);
				fs.assign(s.condition.location, 1, 1);
				fs.insertLocal(s.condVar.name);
				fs.activateLocals(1);

				cond = codeCondition(s.condVar);
			}
			else
				cond = codeCondition(s.condition);

			fs.invertJump(cond);
			fs.patchTrueToHere(cond);

			fs.setBreakable();
			fs.setContinuable();
			fs.setScopeName(s.name);
			visit(s.code);
			fs.patchContinuesTo(beginLoop);
			fs.closeScopeUpvals(s.endLocation);
			fs.jumpTo(s.endLocation, beginLoop);
			fs.patchBreaksToHere();

			fs.popScope(s.endLocation);
			fs.patchFalseToHere(cond);
		}

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override DoWhileStmt visit(DoWhileStmt s)
	{
		auto beginLoop = fs.here();
		Scope scop = void;
		fs.pushScope(scop);

		fs.setBreakable();
		fs.setContinuable();
		fs.setScopeName(s.name);
		visit(s.code);

		if(s.condition.isConstant)
		{
			fs.patchContinuesToHere();

			if(s.condition.isTrue)
				fs.jumpTo(s.endLocation, beginLoop);

			fs.patchBreaksToHere();
			fs.popScope(s.endLocation);
		}
		else
		{
			fs.closeScopeUpvals(s.condition.location);
			fs.patchContinuesToHere();

			auto cond = codeCondition(s.condition);
			fs.invertJump(cond);
			fs.patchTrueToHere(cond);
			fs.jumpTo(s.endLocation, beginLoop);
			fs.patchBreaksToHere();

			fs.popScope(s.endLocation);
			fs.patchFalseToHere(cond);
		}

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override ForStmt visit(ForStmt s)
	{
		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();
			fs.setContinuable();
			fs.setScopeName(s.name);

			foreach(init; s.init)
			{
				if(init.isDecl)
					visit(init.decl);
				else
				{
					visit(init.stmt);
					fs.popToNothing();
				}
			}

			auto beginLoop = fs.here();
			InstRef cond = void;

			if(s.condition)
			{
				cond = codeCondition(s.condition);
				fs.invertJump(cond);
				fs.patchTrueToHere(cond);
			}

			visit(s.code);

			fs.closeScopeUpvals(s.location);
			fs.patchContinuesToHere();

			foreach(inc; s.increment)
			{
				visit(inc);
				fs.popToNothing();
			}

			fs.jumpTo(s.endLocation, beginLoop);
			fs.patchBreaksToHere();
		fs.popScope(s.endLocation);

		if(s.condition)
			fs.patchFalseToHere(cond);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override ForNumStmt visit(ForNumStmt s)
	{
		visitForNum(s.location, s.endLocation, s.name, s.lo, s.hi, s.step, s.index, { visit(s.code); });

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	void visitForNum(CompileLoc location, CompileLoc endLocation, char[] name, Expression lo, Expression hi, Expression step, Identifier index, void delegate() genBody)
	{
		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();
			fs.setContinuable();
			fs.setScopeName(name);

			auto forDesc = fs.beginFor(location, { visit(lo); visit(hi); visit(step); });

			fs.insertLocal(index);
			fs.activateLocals(1);
			genBody();

			fs.endFor(endLocation, forDesc);
		fs.popScope(endLocation);
	}

	override ForeachStmt visit(ForeachStmt s)
	{
		visitForeach(s.location, s.endLocation, s.name, s.indices, s.container, { visit(s.code); });
		
		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	void visitForeach(CompileLoc location, CompileLoc endLocation, char[] name, Identifier[] indices, Expression[] container, void delegate() genBody)
	{
		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();
			fs.setContinuable();
			fs.setScopeName(name);

			auto desc = fs.beginForeach(location, { codeGenList(container); }, container.length);

			foreach(i; indices)
				fs.insertLocal(i);

			fs.activateLocals(indices.length);
			genBody();

			fs.endForeach(endLocation, desc, indices.length);
		fs.popScope(endLocation);
	}

	override SwitchStmt visit(SwitchStmt s)
	{
		Scope scop = void;
		fs.pushScope(scop);
			fs.setBreakable();
			fs.setScopeName(s.name);

			visit(s.condition);
			fs.toSource(s.condition.endLocation);

			foreach(caseStmt; s.cases)
			{
				if(caseStmt.highRange)
				{
					auto c = &caseStmt.conditions[0];
					auto lo = c.exp;
					auto hi = caseStmt.highRange;

					fs.dup();
					visit(lo);
					fs.toSource(lo.endLocation);

					auto jmp1 = fs.codeCmp(lo.location, Comparison.LT);

					fs.dup();
					visit(hi);
					fs.toSource(hi.endLocation);

					auto jmp2 = fs.codeCmp(hi.endLocation, Comparison.GT);

					c.dynJump = fs.makeJump(hi.endLocation);

					fs.patchJumpToHere(jmp1);
					fs.patchJumpToHere(jmp2);
				}
				else
				{
					foreach(ref c; caseStmt.conditions)
					{
						if(!c.exp.isConstant)
						{
							fs.dup();
							visit(c.exp);
							fs.toSource(c.exp.endLocation);
							c.dynJump = fs.codeSwitchCmp(c.exp.endLocation);
						}
					}
				}
			}

			SwitchDesc sdesc;
			fs.beginSwitch(sdesc, s.location); // pops the condition exp off the stack

			foreach(c; s.cases)
				visit(c);

			if(s.caseDefault)
				visit(s.caseDefault);

			fs.endSwitch();
			fs.patchBreaksToHere();
		fs.popScope(s.endLocation);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override CaseStmt visit(CaseStmt s)
	{
		if(s.highRange)
			fs.patchJumpToHere(s.conditions[0].dynJump);
		else
		{
			foreach(c; s.conditions)
			{
				if(c.exp.isConstant)
					fs.addCase(c.exp.location, c.exp);
				else
					fs.patchJumpToHere(c.dynJump);
			}
		}

		visit(s.code);
		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override DefaultStmt visit(DefaultStmt s)
	{
		fs.addDefault(s.location);
		visit(s.code);
		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override ContinueStmt visit(ContinueStmt s)
	{
		fs.codeContinue(s.location, s.name);
		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override BreakStmt visit(BreakStmt s)
	{
		fs.codeBreak(s.location, s.name);
		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override ReturnStmt visit(ReturnStmt s)
	{
		if(!fs.inTryCatch() && s.exprs.length == 1 && (s.exprs[0].type == AstTag.CallExp || s.exprs[0].type == AstTag.MethodCallExp))
		{
			visit(s.exprs[0]);
			fs.makeTailcall();
			fs.saveRets(s.exprs[0].endLocation, 1);
			fs.codeRet(s.endLocation);
		}
		else
		{
			codeGenList(s.exprs);
			fs.saveRets(s.endLocation, s.exprs.length);

			if(fs.inTryCatch())
				fs.codeUnwind(s.endLocation);

			fs.codeRet(s.endLocation);
		}

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override TryCatchStmt visit(TryCatchStmt s)
	{
		Scope scop = void;
		auto pushCatch = fs.codeCatch(s.location, scop);

		visit(s.tryBody);

		auto jumpOverCatch = fs.popCatch(s.tryBody.endLocation, s.transformedCatch.location, pushCatch);

		fs.pushScope(scop);
			fs.insertLocal(s.hiddenCatchVar);
			fs.activateLocals(1);
			visit(s.transformedCatch);
		fs.popScope(s.transformedCatch.endLocation);

		fs.patchJumpToHere(jumpOverCatch);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override TryFinallyStmt visit(TryFinallyStmt s)
	{
		Scope scop = void;
		auto pushFinally = fs.codeFinally(s.location, scop);

		visit(s.tryBody);

		fs.popFinally(s.tryBody.endLocation, s.finallyBody.location, pushFinally);

		fs.pushScope(scop);
			visit(s.finallyBody);
			fs.codeEndFinal(s.finallyBody.endLocation);
		fs.popScope(s.finallyBody.endLocation);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override ThrowStmt visit(ThrowStmt s)
	{
		visit(s.exp);
		fs.toSource(s.exp.endLocation);
		fs.codeThrow(s.endLocation, s.rethrowing);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override AssignStmt visit(AssignStmt s)
	{
		foreach(exp; s.lhs)
			exp.checkLHS(c);

		foreach(dest; s.lhs)
			visit(dest);

		fs.resolveAssignmentConflicts(s.lhs[$ - 1].location, s.lhs.length);

		codeGenAssignRHS(s.rhs);
		fs.assign(s.endLocation, s.lhs.length, s.rhs.length);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	OpAssignStmt visitOpAssign(OpAssignStmt s)
	{
		if(s.lhs.type != AstTag.ThisExp)
			s.lhs.checkLHS(c);

		visit(s.lhs);
		fs.dup();
		fs.toSource(s.lhs.endLocation);

		visit(s.rhs);
		fs.toSource(s.rhs.endLocation);

		fs.reflexOp(s.endLocation, s.type);
		fs.assign(s.endLocation, 1, 1);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override AddAssignStmt  visit(AddAssignStmt s)  { return visitOpAssign(s); }
	override SubAssignStmt  visit(SubAssignStmt s)  { return visitOpAssign(s); }
	override MulAssignStmt  visit(MulAssignStmt s)  { return visitOpAssign(s); }
	override DivAssignStmt  visit(DivAssignStmt s)  { return visitOpAssign(s); }
	override ModAssignStmt  visit(ModAssignStmt s)  { return visitOpAssign(s); }
	override AndAssignStmt  visit(AndAssignStmt s)  { return visitOpAssign(s); }
	override OrAssignStmt   visit(OrAssignStmt s)   { return visitOpAssign(s); }
	override XorAssignStmt  visit(XorAssignStmt s)  { return visitOpAssign(s); }
	override ShlAssignStmt  visit(ShlAssignStmt s)  { return visitOpAssign(s); }
	override ShrAssignStmt  visit(ShrAssignStmt s)  { return visitOpAssign(s); }
	override UShrAssignStmt visit(UShrAssignStmt s) { return visitOpAssign(s); }

	override CondAssignStmt visit(CondAssignStmt s)
	{
		visit(s.lhs);
		fs.dup();
		fs.toSource(s.lhs.endLocation);
		fs.pushNull();

		auto i = fs.codeIs(s.lhs.endLocation, false);

		visit(s.rhs);
		fs.assign(s.endLocation, 1, 1);

		fs.patchJumpToHere(i);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override CatAssignStmt visit(CatAssignStmt s)
	{
		assert(s.collapsed, "CatAssignStmt codeGen not collapsed");
		assert(s.operands.length >= 1, "CatAssignStmt codeGen not enough ops");

		if(s.lhs.type != AstTag.ThisExp)
			s.lhs.checkLHS(c);

		visit(s.lhs);
		fs.dup();
		fs.toSource(s.lhs.endLocation);

		codeGenList(s.operands, false);
		
		fs.concatEq(s.endLocation, s.operands.length);
		fs.assign(s.endLocation, 1, 1);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override IncStmt visit(IncStmt s)
	{
		if(s.exp.type != AstTag.ThisExp)
			s.exp.checkLHS(c);

		visit(s.exp);
		fs.dup();
		fs.toSource(s.exp.endLocation);

		fs.incDec(s.endLocation, s.type);
		fs.assign(s.endLocation, 1, 1);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override DecStmt visit(DecStmt s)
	{
		if(s.exp.type != AstTag.ThisExp)
			s.exp.checkLHS(c);

		visit(s.exp);
		fs.dup();
		fs.toSource(s.exp.endLocation);

		fs.incDec(s.endLocation, s.type);
		fs.assign(s.endLocation, 1, 1);

		debug(EXPSTACKCHECK) fs.checkExpStackEmpty();
		return s;
	}

	override CondExp visit(CondExp e)
	{
		fs.pushNewLocals(1);

		auto c = codeCondition(e.cond);
		fs.invertJump(c);
		fs.patchTrueToHere(c);

		fs.dup();
		visit(e.op1);
		fs.assign(e.op1.endLocation, 1, 1);

		auto i = fs.makeJump(e.op1.endLocation);

		fs.patchFalseToHere(c);

		fs.dup();
		visit(e.op2);
		fs.assign(e.op2.endLocation, 1, 1);

		fs.patchJumpToHere(i);
		fs.toTemporary(e.endLocation);

		return e;
	}

	override OrOrExp visit(OrOrExp e)
	{
		fs.pushNewLocals(1);
		fs.dup();
		visit(e.op1);
		fs.assign(e.op1.endLocation, 1, 1);
		fs.dup();
		fs.toSource(e.op1.endLocation);
		auto i = fs.codeIsTrue(e.op1.endLocation);
		fs.dup();
		visit(e.op2);
		fs.assign(e.op2.endLocation, 1, 1);
		fs.patchJumpToHere(i);
		fs.toTemporary(e.endLocation);
		return e;
	}

	override AndAndExp visit(AndAndExp e)
	{
		fs.pushNewLocals(1);
		fs.dup();
		visit(e.op1);
		fs.assign(e.op1.endLocation, 1, 1);
		fs.dup();
		fs.toSource(e.op1.endLocation);
		auto i = fs.codeIsTrue(e.op1.endLocation, false);
		fs.dup();
		visit(e.op2);
		fs.assign(e.op2.endLocation, 1, 1);
		fs.patchJumpToHere(i);
		fs.toTemporary(e.endLocation);
		return e;
	}

	BinaryExp visitBinExp(BinaryExp e)
	{
		visit(e.op1);
		fs.toSource(e.op1.endLocation);
		visit(e.op2);
		fs.toSource(e.op2.endLocation);
		fs.binOp(e.endLocation, e.type);
		return e;
	}

	override BinaryExp visit(AddExp e)   { return visitBinExp(e); }
	override BinaryExp visit(SubExp e)   { return visitBinExp(e); }
	override BinaryExp visit(MulExp e)   { return visitBinExp(e); }
	override BinaryExp visit(DivExp e)   { return visitBinExp(e); }
	override BinaryExp visit(ModExp e)   { return visitBinExp(e); }
	override BinaryExp visit(AndExp e)   { return visitBinExp(e); }
	override BinaryExp visit(OrExp e)    { return visitBinExp(e); }
	override BinaryExp visit(XorExp e)   { return visitBinExp(e); }
	override BinaryExp visit(ShlExp e)   { return visitBinExp(e); }
	override BinaryExp visit(ShrExp e)   { return visitBinExp(e); }
	override BinaryExp visit(UShrExp e)  { return visitBinExp(e); }
	override BinaryExp visit(AsExp e)    { return visitBinExp(e); }
	override BinaryExp visit(Cmp3Exp e)  { return visitBinExp(e); }

	override CatExp visit(CatExp e)
	{
		assert(e.collapsed is true, "CatExp codeGen not collapsed");
		assert(e.operands.length >= 2, "CatExp codeGen not enough ops");

		codeGenList(e.operands, false);
		fs.concat(e.endLocation, e.operands.length);
		return e;
	}

	BinaryExp visitComparisonExp(BinaryExp e)
	{
		fs.pushNewLocals(1);
		auto i = codeCondition(e);
		fs.dup();
		fs.pushBool(false);
		fs.assign(e.endLocation, 1, 1);
		auto j = fs.makeJump(e.endLocation);
		fs.patchTrueToHere(i);
		fs.dup();
		fs.pushBool(true);
		fs.assign(e.endLocation, 1, 1);
		fs.patchJumpToHere(j);
		fs.toTemporary(e.endLocation);
		return e;
	}

	override BinaryExp visit(EqualExp e)    { return visitComparisonExp(e); }
	override BinaryExp visit(NotEqualExp e) { return visitComparisonExp(e); }
	override BinaryExp visit(IsExp e)       { return visitComparisonExp(e); }
	override BinaryExp visit(NotIsExp e)    { return visitComparisonExp(e); }
	override BinaryExp visit(LTExp e)       { return visitComparisonExp(e); }
	override BinaryExp visit(LEExp e)       { return visitComparisonExp(e); }
	override BinaryExp visit(GTExp e)       { return visitComparisonExp(e); }
	override BinaryExp visit(GEExp e)       { return visitComparisonExp(e); }
	override BinaryExp visit(InExp e)       { return visitComparisonExp(e); }
	override BinaryExp visit(NotInExp e)    { return visitComparisonExp(e); }

	UnExp visitUnExp(UnExp e)
	{
		visit(e.op);
		fs.toSource(e.op.endLocation);
		fs.unOp(e.endLocation, e.type);
		return e;
	}

	override UnExp visit(NegExp e)       { return visitUnExp(e); }
	override UnExp visit(NotExp e)       { return visitUnExp(e); }
	override UnExp visit(ComExp e)       { return visitUnExp(e); }
	override UnExp visit(CoroutineExp e) { return visitUnExp(e); }

	override LenExp visit(LenExp e)
	{
		visit(e.op);
		fs.toSource(e.op.endLocation);
		fs.length();
		return e;
	}

	override VargLenExp visit(VargLenExp e)
	{
		if(!fs.isVararg())
			c.semException(e.location, "'vararg' cannot be used in a non-variadic function");

		fs.pushVargLen(e.endLocation);
		return e;
	}

	override DotExp visit(DotExp e)
	{
		visit(e.op);
		fs.toSource(e.op.endLocation);
		visit(e.name);
		fs.toSource(e.endLocation);
		fs.field();
		return e;
	}

	override DotSuperExp visit(DotSuperExp e)
	{
		visit(e.op);
		fs.toSource(e.op.endLocation);
		fs.unOp(e.endLocation, e.type);
		return e;
	}

	override MethodCallExp visit(MethodCallExp e)
	{
		visitMethodCall(e.location, e.endLocation, e.isSuperCall, e.op, e.method, delegate uword()
		{
			codeGenList(e.args);
			return e.args.length;
		});

		return e;
	}

	void visitMethodCall(CompileLoc location, CompileLoc endLocation, bool isSuperCall, Expression op, Expression method, uword delegate() genArgs)
	{
		auto desc = fs.beginMethodCall();

		if(isSuperCall)
			fs.pushThis();
		else
			visit(op);

		fs.toSource(location);
		fs.updateMethodCall(desc, 1);

		visit(method);
		fs.toSource(method.endLocation);
		fs.updateMethodCall(desc, 2);

		genArgs();
		fs.pushMethodCall(endLocation, isSuperCall, desc);
	}

	override CallExp visit(CallExp e)
	{
		visitCall(e.endLocation, e.op, e.context, delegate uword()
		{
			codeGenList(e.args);
			return e.args.length;
		});

		return e;
	}

	void visitCall(CompileLoc endLocation, Expression op, Expression context, uword delegate() genArgs)
	{
		visit(op);
		fs.toTemporary(op.endLocation);

		if(context)
		{
			visit(context);
			fs.toTemporary(context.endLocation);
		}
		else
		{
			fs.pushNull();
			fs.toTemporary(op.endLocation);
		}

		auto numArgs = genArgs();
		fs.pushCall(endLocation, numArgs);
	}

	override IndexExp visit(IndexExp e)
	{
		visit(e.op);
		fs.toSource(e.op.endLocation);
		visit(e.index);
		fs.toSource(e.endLocation);
		fs.index();
		return e;
	}

	override VargIndexExp visit(VargIndexExp e)
	{
		if(!fs.isVararg())
			c.semException(e.location, "'vararg' cannot be used in a non-variadic function");

		visit(e.index);
		fs.toSource(e.index.endLocation);
		fs.varargIndex();

		return e;
	}

	override SliceExp visit(SliceExp e)
	{
		Expression[3] list;
		list[0] = e.op;
		list[1] = e.loIndex;
		list[2] = e.hiIndex;
		codeGenList(list[], false);
		fs.slice();
		return e;
	}

	override VargSliceExp visit(VargSliceExp e)
	{
		if(!fs.isVararg())
			c.semException(e.location, "'vararg' cannot be used in a non-variadic function");

		Expression[2] list;
		list[0] = e.loIndex;
		list[1] = e.hiIndex;
		codeGenList(list[], false);
		fs.varargSlice(e.endLocation);
		return e;
	}

	override IdentExp visit(IdentExp e)
	{
		fs.pushVar(e.name);
		return e;
	}

	override ThisExp visit(ThisExp e)
	{
		fs.pushThis();
		return e;
	}

	override NullExp visit(NullExp e)
	{
		fs.pushNull();
		return e;
	}

	override BoolExp visit(BoolExp e)
	{
		fs.pushBool(e.value);
		return e;
	}

	override IntExp visit(IntExp e)
	{
		fs.pushInt(e.value);
		return e;
	}

	override FloatExp visit(FloatExp e)
	{
		fs.pushFloat(e.value);
		return e;
	}

	override CharExp visit(CharExp e)
	{
		fs.pushChar(e.value);
		return e;
	}

	override StringExp visit(StringExp e)
	{
		fs.pushString(e.value);
		return e;
	}

	override VarargExp visit(VarargExp e)
	{
		if(!fs.isVararg())
			c.semException(e.location, "'vararg' cannot be used in a non-variadic function");

		fs.pushVararg(e.location);
		return e;
	}

	override FuncLiteralExp visit(FuncLiteralExp e)
	{
		visit(e.def);
		return e;
	}

	override ClassLiteralExp visit(ClassLiteralExp e)
	{
		visit(e.def);
		return e;
	}

	override NamespaceCtorExp visit(NamespaceCtorExp e)
	{
		visit(e.def);
		return e;
	}

	override ParenExp visit(ParenExp e)
	{
		assert(e.exp.isMultRet(), "ParenExp codeGen not multret");

		visit(e.exp);
		fs.toTemporary(e.endLocation);
		return e;
	}

	override TableCtorExp visit(TableCtorExp e)
	{
		fs.pushTable(e.location);

		foreach(ref field; e.fields)
		{
			fs.dup();
			visit(field.key);
			fs.toSource(field.key.endLocation);
			fs.index();
			visit(field.value);
			fs.assign(field.value.endLocation, 1, 1);
		}

		return e;
	}

	override ArrayCtorExp visit(ArrayCtorExp e)
	{
		if(e.values.length > ArrayCtorExp.maxFields)
			c.semException(e.location, "Array constructor has too many fields (more than {})", ArrayCtorExp.maxFields);

		static uword min(uword a, uword b)
		{
			return (a > b) ? b : a;
		}

		if(e.values.length > 0 && e.values[$ - 1].isMultRet())
			fs.pushArray(e.location, e.values.length - 1);
		else
			fs.pushArray(e.location, e.values.length);

		if(e.values.length > 0)
		{
			uword index = 0;
			uword fieldsLeft = e.values.length;
			uword block = 0;

			while(fieldsLeft > 0)
			{
				auto numToDo = min(fieldsLeft, Instruction.ArraySetFields);
				fieldsLeft -= numToDo;
				fs.dup();
				codeGenList(e.values[index .. index + numToDo], fieldsLeft == 0);
				fs.arraySet(e.values[index + numToDo - 1].endLocation, numToDo, block);
				index += numToDo;
				block++;
			}
		}

		return e;
	}

	override YieldExp visit(YieldExp e)
	{
		codeGenList(e.args);
		fs.pushYield(e.endLocation, e.args.length);
		return e;
	}

	override TableComprehension visit(TableComprehension e)
	{
		fs.pushTable(e.location);

		visitForComp(e.forComp,
		{
			fs.dup();
			visit(e.key);
			fs.toSource(e.key.endLocation);
			fs.index();
			visit(e.value);
			fs.assign(e.value.endLocation, 1, 1);
		});
		return e;
	}

	override ArrayComprehension visit(ArrayComprehension e)
	{
		fs.pushArray(e.location, 0);

		visitForComp(e.forComp,
		{
			fs.dup();
			visit(e.exp);
			fs.toSource(e.exp.endLocation);
			fs.arrayAppend(e.exp.endLocation);
		});
		return e;
	}

	ForComprehension visitForComp(ForComprehension e, void delegate() inner)
	{
		if(auto x = e.as!(ForeachComprehension))
			return visit(x, inner);
		else
		{
			auto x = e.as!(ForNumComprehension);
			assert(x !is null);
			return visit(x, inner);
		}
	}

	ForeachComprehension visit(ForeachComprehension e, void delegate() inner)
	{
		auto newInner = inner;

		if(e.ifComp)
		{
			if(e.forComp)
				newInner = { visit(e.ifComp, { visitForComp(e.forComp, inner); }); };
			else
				newInner = { visit(e.ifComp, inner); };
		}
		else if(e.forComp)
			newInner = { visitForComp(e.forComp, inner); };

		visitForeach(e.location, e.endLocation, "", e.indices, e.container, newInner);
		return e;
	}

	ForNumComprehension visit(ForNumComprehension e, void delegate() inner)
	{
		auto newInner = inner;

		if(e.ifComp)
		{
			if(e.forComp)
				newInner = { visit(e.ifComp, { visitForComp(e.forComp, inner); }); };
			else
				newInner = { visit(e.ifComp, inner); };
		}
		else if(e.forComp)
			newInner = { visitForComp(e.forComp, inner); };

		visitForNum(e.location, e.endLocation, "", e.lo, e.hi, e.step, e.index, newInner);
		return e;
	}

	IfComprehension visit(IfComprehension e, void delegate() inner)
	{
		visitIf(e.location, e.endLocation, e.endLocation, null, e.condition, inner, null);
		return e;
	}

	void codeGenList(Expression[] exprs, bool allowMultRet = true)
	{
		if(exprs.length == 0)
			return;

		foreach(e; exprs[0 .. $ - 1])
		{
			visit(e);
			fs.toTemporary(e.endLocation);
		}

		visit(exprs[$ - 1]);

		if(!allowMultRet || !exprs[$ - 1].isMultRet())
			fs.toTemporary(exprs[$ - 1].endLocation);
	}

	void codeGenAssignRHS(Expression[] exprs)
	{
		if(exprs.length == 0)
			return;

		foreach(i, e; exprs[0 .. $ - 1])
		{
			visit(e);
			fs.flushSideEffects(e.endLocation);
		}

		visit(exprs[$ - 1]);
	}

	// ---------------------------------------------------------------------------
	// Condition codegen

package:

	InstRef codeCondition(Expression e)
	{
		switch(e.type)
		{
			case AstTag.CondExp:     return codeCondition(e.as!(CondExp));
			case AstTag.OrOrExp:     return codeCondition(e.as!(OrOrExp));
			case AstTag.AndAndExp:   return codeCondition(e.as!(AndAndExp));
			case AstTag.EqualExp:    return codeCondition(e.as!(EqualExp));
			case AstTag.NotEqualExp: return codeCondition(e.as!(NotEqualExp));
			case AstTag.IsExp:       return codeCondition(e.as!(IsExp));
			case AstTag.NotIsExp:    return codeCondition(e.as!(NotIsExp));
			case AstTag.InExp:       return codeCondition(e.as!(InExp));
			case AstTag.NotInExp:    return codeCondition(e.as!(NotInExp));
			case AstTag.LTExp:       return codeCondition(e.as!(LTExp));
			case AstTag.LEExp:       return codeCondition(e.as!(LEExp));
			case AstTag.GTExp:       return codeCondition(e.as!(GTExp));
			case AstTag.GEExp:       return codeCondition(e.as!(GEExp));
			case AstTag.ParenExp:    return codeCondition(e.as!(ParenExp));

			default:
				visit(e);
				fs.toSource(e.endLocation);
				InstRef ret;
				ret.trueList = fs.codeIsTrue(e.endLocation);
				return ret;
		}
	}

	InstRef codeCondition(CondExp e)
	{
		auto c = codeCondition(e.cond);
		fs.invertJump(c);
		fs.patchTrueToHere(c);

		auto left = codeCondition(e.op1);
		fs.invertJump(left);
		fs.patchTrueToHere(left);

		auto trueJump = fs.makeJump(e.op1.endLocation);

		fs.patchFalseToHere(c);
		// Done with c

		auto right = codeCondition(e.op2);
		fs.catToFalse(right, left.falseList);
		fs.catToTrue(right, trueJump);
		return right;
	}

	InstRef codeCondition(OrOrExp e)
	{
		auto left = codeCondition(e.op1);
		fs.patchFalseToHere(left);

		auto right = codeCondition(e.op2);
		fs.catToTrue(right, left.trueList);

		return right;
	}

	InstRef codeCondition(AndAndExp e)
	{
		auto left = codeCondition(e.op1);
		fs.invertJump(left);
		fs.patchTrueToHere(left);

		auto right = codeCondition(e.op2);
		fs.catToFalse(right, left.falseList);

		return right;
	}

	InstRef codeEqualExpCondition(BaseEqualExp e)
	{
		visit(e.op1);
		fs.toSource(e.op1.endLocation);
		visit(e.op2);
		fs.toSource(e.op2.endLocation);

		InstRef ret;

		switch(e.type)
		{
			case AstTag.EqualExp:    ret.trueList = fs.codeEquals(e.op2.endLocation, true); break;
			case AstTag.NotEqualExp: ret.trueList = fs.codeEquals(e.op2.endLocation, false); break;
			case AstTag.IsExp:       ret.trueList = fs.codeIs(e.op2.endLocation, true); break;
			case AstTag.NotIsExp:    ret.trueList = fs.codeIs(e.op2.endLocation, false); break;
			case AstTag.InExp:       ret.trueList = fs.codeIn(e.op2.endLocation, true); break;
			case AstTag.NotInExp:    ret.trueList = fs.codeIn(e.op2.endLocation, false); break;
			default: assert(false);
		}

		return ret;
	}

	InstRef codeCondition(EqualExp e)    { return codeEqualExpCondition(e); }
	InstRef codeCondition(NotEqualExp e) { return codeEqualExpCondition(e); }
	InstRef codeCondition(IsExp e)       { return codeEqualExpCondition(e); }
	InstRef codeCondition(NotIsExp e)    { return codeEqualExpCondition(e); }
	InstRef codeCondition(InExp e)       { return codeEqualExpCondition(e); }
	InstRef codeCondition(NotInExp e)    { return codeEqualExpCondition(e); }

	InstRef codeCmpExpCondition(BaseCmpExp e)
	{
		visit(e.op1);
		fs.toSource(e.op1.endLocation);
		visit(e.op2);
		fs.toSource(e.op2.endLocation);

		InstRef ret;

		switch(e.type)
		{
			case AstTag.LTExp: ret.trueList = fs.codeCmp(e.endLocation, Comparison.LT); break;
			case AstTag.LEExp: ret.trueList = fs.codeCmp(e.endLocation, Comparison.LE); break;
			case AstTag.GTExp: ret.trueList = fs.codeCmp(e.endLocation, Comparison.GT); break;
			case AstTag.GEExp: ret.trueList = fs.codeCmp(e.endLocation, Comparison.GE); break;
			default: assert(false);
		}

		return ret;
	}

	InstRef codeCondition(LTExp e) { return codeCmpExpCondition(e); }
	InstRef codeCondition(LEExp e) { return codeCmpExpCondition(e); }
	InstRef codeCondition(GTExp e) { return codeCmpExpCondition(e); }
	InstRef codeCondition(GEExp e) { return codeCmpExpCondition(e); }

	// Have to keep this cause it "unwraps" the ParenExp, which the default case in codeCondition does not
	InstRef codeCondition(ParenExp e)
	{
		visit(e.exp);
		fs.toSource(e.exp.endLocation);
		InstRef ret;
		ret.trueList = fs.codeIsTrue(e.exp.endLocation);
		return ret;
	}
}