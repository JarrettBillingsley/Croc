
#include "croc/compiler/builder.hpp"
#include "croc/compiler/codegen.hpp"
#include "croc/internal/eh.hpp"
#include "croc/internal/stack.hpp"

// #define PRINTEXPSTACK

namespace croc
{
	void Codegen::codegenStatements(FuncDef* d)
	{
		bool failed;

		// This scope is to allow the FuncBuilder's dtor to run and clean up gunk whether or not it failed.
		{
			FuncBuilder fb_(c, d->location, d->name->name, nullptr);
			fb = &fb_;

			auto slot = croc_pushNull(*c.thread());

			failed = tryCode(c.thread(), slot, [&]
			{
				fb->setVararg(d->isVararg);
				fb->setNumParams(d->params.length);

				Scope scop;
				fb->pushScope(scop);
					for(auto &p: d->params)
						fb->addParam(p.name, p.typeMask);

					fb->activateLocals(d->params.length);

					visit(d->code);
				fb->popScope(d->code->endLocation);
				fb->defaultReturn(d->code->endLocation);
			});

			fb = nullptr;

			if(!failed)
			{
				croc_popTop(*c.thread()); // dummy null
				push(c.thread(), Value::from(fb_.toFuncDef()));
				croc_insertAndPop(*c.thread(), -2);
			}
		}

		if(failed)
			croc_eh_rethrow(*c.thread());
	}

	Module* Codegen::visit(Module* m)
	{
		bool failed;

		// This scope is to allow the FuncBuilder's dtor to run and clean up gunk whether or not it failed.
		{
			FuncBuilder fb_(c, m->location, c.newString("<top-level>"), nullptr);
			fb = &fb_;

			auto slot = croc_pushNull(*c.thread());

			failed = tryCode(c.thread(), slot, [&]
			{
				fb->setNumParams(1);

				Scope scop;
				fb->pushScope(scop);
					fb->insertLocal(new(c) Identifier(m->location, c.newString("this")));
					fb->activateLocals(1);

					visit(m->statements);

					if(m->decorator)
					{
						visitDecorator(m->decorator, [this]{ fb->pushThis(); });
						fb->popToNothing();
					}
				fb->popScope(m->endLocation);
				fb->defaultReturn(m->endLocation);

				DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
			});

			DEBUG_PRINTEXPSTACK(if(failed) fb->printExpStack();)

			fb = nullptr;

			if(!failed)
			{
				croc_popTop(*c.thread()); // dummy null
				push(c.thread(), Value::from(fb_.toFuncDef()));
				croc_insertAndPop(*c.thread(), -2);
			}
		}

		if(failed)
			croc_eh_rethrow(*c.thread());

		return m;
	}

	FuncDef* Codegen::visit(FuncDef* d)
	{
		bool failed;

		// This scope is to allow the FuncBuilder's dtor to run and clean up gunk whether or not it failed.
		{
			FuncBuilder inner(c, d->location, d->name->name, fb);
			fb = &inner;

			auto slot = croc_pushNull(*c.thread());

			failed = tryCode(c.thread(), slot, [&]
			{
				fb->setVararg(d->isVararg);
				fb->setNumParams(d->params.length);

				Scope scop;
				fb->pushScope(scop);
					for(auto &p: d->params)
						fb->addParam(p.name, p.typeMask);

					fb->activateLocals(d->params.length);

					visit(d->code);
				fb->popScope(d->code->endLocation);
				fb->defaultReturn(d->code->endLocation);
				fb->parent()->pushClosure(fb);
			});

			fb = fb->parent();

			if(!failed)
				croc_popTop(*c.thread()); // dummy null
		}

		if(failed)
			croc_eh_rethrow(*c.thread());

		return d;
	}

	TypecheckStmt* Codegen::visit(TypecheckStmt* s)
	{
		bool needParamCheck = false;

		for(auto &p: s->def->params)
		{
			if(p.typeMask != cast(uint32_t)TypeMask::Any)
			{
				needParamCheck = true;
				break;
			}
		}

		if(needParamCheck)
			fb->paramCheck(s->def->code->location);

		uword idx = 0;
		for(auto &p: s->def->params)
		{
			if(p.classTypes.length > 0)
			{
				auto success = InstRef();

				for(auto t: p.classTypes)
				{
					visit(t);
					fb->toSource(t->endLocation);
					fb->catToTrue(success, fb->checkObjParam(t->endLocation, idx));
				}

				fb->objParamFail(p.classTypes[p.classTypes.length - 1]->endLocation, idx);
				fb->patchTrueToHere(success);
			}
			else if(p.customConstraint)
			{
				auto success = InstRef();
				auto con = p.customConstraint;
				visit(con);
				fb->toSource(con->endLocation);
				fb->catToTrue(success, fb->codeIsTrue(con->endLocation));

				dottedNameToString(AST_AS(CallExp, con)->op);
				fb->pushString(getCrocstr(c.thread(), -1));
				fb->toSource(con->endLocation);
				fb->customParamFail(con->endLocation, idx);
				croc_popTop(*c.thread());
				fb->patchTrueToHere(success);
			}

			idx++;
		}

		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	word Codegen::dottedNameToString(Expression* exp)
	{
		std::function<word(Expression*)> work = [&](Expression* exp)
		{
			if(auto n = AST_AS(IdentExp, exp))
			{
				croc_pushString(*c.thread(), cast(const char*)n->name->name.ptr);
				return 1;
			}
			else if(auto n = AST_AS(DotExp, exp))
			{
				auto ret = work(n->op);
				croc_pushString(*c.thread(), ".");
				croc_pushString(*c.thread(), cast(const char*)AST_AS(StringExp, n->name)->value.ptr);
				return ret + 2;
			}
			else
			{
				assert(false);
				return 0; // dummy
			}
		};

		return croc_cat(*c.thread(), work(exp));
	}

	ImportStmt* Codegen::visit(ImportStmt* s)
	{
		(void)s;
		assert(false);
		return nullptr; // dummy
	}

	ScopeStmt* Codegen::visit(ScopeStmt* s)
	{
		Scope scop;
		fb->pushScope(scop);
		visit(s->statement);
		fb->popScope(s->endLocation);
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	ExpressionStmt* Codegen::visit(ExpressionStmt* s)
	{
		visit(s->expr);
		fb->popToNothing();
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	void Codegen::visitDecorator(Decorator* d, std::function<void()> obj)
	{
		auto genArgs = [&]
		{
			if(d->nextDec)
			{
				visitDecorator(d->nextDec, obj);
				fb->toSource(d->nextDec->endLocation);
				fb->toTemporary(d->nextDec->endLocation);
			}
			else
			{
				obj();
				fb->toSource(d->location);
				fb->toTemporary(d->location);
			}

			codeGenList(d->args);
			return d->args.length + 1; // 1 for nextDec/obj
		};

		if(auto dot = AST_AS(DotExp, d->func))
		{
			if(d->context != nullptr)
				c.semException(d->location, "'with' is disallowed on method calls");
			visitMethodCall(d->location, d->endLocation, dot->op, dot->name, genArgs);
		}
		else
			visitCall(d->endLocation, d->func, d->context, genArgs);
	}

	FuncDecl* Codegen::visit(FuncDecl* d)
	{
		if(d->protection == Protection::Local)
		{
			fb->insertLocal(d->def->name);
			fb->activateLocals(1);
			fb->pushVar(d->def->name);
		}
		else
		{
			assert(d->protection == Protection::Global);
			fb->pushNewGlobal(d->def->name);
		}

		visit(d->def);
		fb->assign(d->endLocation, 1, 1);

		if(d->decorator)
		{
			fb->pushVar(d->def->name);
			visitDecorator(d->decorator, [this, &d]{ fb->pushVar(d->def->name); });
			fb->assign(d->endLocation, 1, 1);
		}

		return d;
	}

	ClassDecl* Codegen::visit(ClassDecl* d)
	{
		if(d->protection == Protection::Local)
		{
			fb->insertLocal(d->name);
			fb->activateLocals(1);
			fb->pushVar(d->name);
		}
		else
		{
			assert(d->protection == Protection::Global);
			fb->pushNewGlobal(d->name);
		}

		// put empty class in d->name
		fb->pushString(d->name->name);

		if(d->baseClasses.length > 0)
		{
			for(auto base: d->baseClasses)
			{
				visit(base);
				fb->toTemporary(base->location);
			}
		}

		fb->newClass(d->location, d->baseClasses.length);
		fb->assign(d->location, 1, 1);

		// evaluate rest of decl
		fb->pushVar(d->name);

		if(d->fields.length != 0)
		{
			fb->toSource(d->location);

			for(auto &field: d->fields)
			{
				fb->dup();
				fb->pushString(field.name);
				visit(field.initializer);
				fb->toSource(field.initializer->location);

				if(field.func)
					fb->addClassMethod(field.initializer->location, field.isOverride);
				else
					fb->addClassField(field.initializer->location, field.isOverride);
			}
		}

		fb->pop();

		if(d->decorator)
		{
			// reassign decorated class into name
			fb->pushVar(d->name);
			visitDecorator(d->decorator, [this, &d]{ fb->pushVar(d->name); });
			fb->assign(d->endLocation, 1, 1);
		}

		return d;
	}

	NamespaceDecl* Codegen::visit(NamespaceDecl* d)
	{
		if(d->protection == Protection::Local)
		{
			fb->insertLocal(d->name);
			fb->activateLocals(1);
			fb->pushVar(d->name);
		}
		else
		{
			assert(d->protection == Protection::Global);
			fb->pushNewGlobal(d->name);
		}

		// put empty namespace in d->name
		fb->pushString(d->name->name);

		if(d->parent)
		{
			visit(d->parent);
			fb->toSource(d->parent->location);
			fb->newNamespace(d->location);
		}
		else
			fb->newNamespaceNP(d->location);

		auto desc = fb->beginNamespace(d->location);

		fb->assign(d->location, 1, 1);

		// evaluate rest of decl
		fb->pushVar(d->name);

		if(d->fields.length)
		{
			fb->toSource(d->location);

			for(auto &field: d->fields)
			{
				fb->dup();
				fb->pushString(field.name);
				fb->toSource(field.initializer->location);
				fb->field();
				visit(field.initializer);
				fb->assign(field.initializer->location, 1, 1);
			}
		}

		fb->endNamespace(desc);
		fb->pop();

		if(d->decorator)
		{
			// reassign decorated namespace into name
			fb->pushVar(d->name);
			visitDecorator(d->decorator, [this, &d]{ fb->pushVar(d->name); });
			fb->assign(d->endLocation, 1, 1);
		}

		return d;
	}

	VarDecl* Codegen::visit(VarDecl* d)
	{
		// Check for name conflicts within the definition
		for(uword i = 0; i < d->names.length; i++)
		{
			auto n1 = d->names[i];

			for(uword j = 0; j < i; j++)
			{
				if(n1->name == d->names[j]->name)
				{
					auto loc = d->names[j]->location;
					c.semException(n1->location, "Variable '%s' conflicts with previous definition at %s(%u:%u)",
						n1->name.ptr, loc.file.ptr, loc.line, loc.col);
				}
			}
		}

		if(d->protection == Protection::Global)
		{
			for(auto n: d->names)
				fb->pushNewGlobal(n);

			codeGenAssignRHS(d->initializer);
			fb->assign(d->location, d->names.length, d->initializer.length);
		}
		else
		{
			fb->pushNewLocals(d->names.length);
			codeGenList(d->initializer);
			fb->assign(d->location, d->names.length, d->initializer.length);

			for(auto n: d->names)
				fb->insertLocal(n);

			fb->activateLocals(d->names.length);
		}

		return d;
	}

	BlockStmt* Codegen::visit(BlockStmt* s)
	{
		for(auto st: s->statements)
			visit(st);

		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	AssertStmt* Codegen::visit(AssertStmt* s)
	{
		assert(c.asserts()); // can't have made it here unless asserts are enabled

		InstRef i = codeCondition(s->cond);
		fb->patchFalseToHere(i);
		visit(s->msg);
		fb->toSource(s->msg->endLocation);
		fb->assertFail(s->location);
		fb->patchTrueToHere(i);

		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	IfStmt* Codegen::visit(IfStmt* s)
	{
		if(s->elseBody)
			visitIf(s->endLocation, s->elseBody->location, s->condVar, s->condition,
				[this, &s]{ visit(s->ifBody); }, [this, &s]{ visit(s->elseBody); });
		else
			visitIf(s->endLocation, s->endLocation, s->condVar, s->condition,
				[this, &s]{ visit(s->ifBody); }, nullptr);

		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	void Codegen::visitIf(CompileLoc endLocation, CompileLoc elseLocation, IdentExp* condVar,
		Expression* condition, std::function<void()> genBody, std::function<void()> genElse)
	{
		Scope scop;
		fb->pushScope(scop);

		auto i = InstRef();

		if(condVar)
		{
			fb->pushNewLocals(1);
			visit(condition);
			fb->assign(condition->location, 1, 1);
			fb->insertLocal(condVar->name);
			fb->activateLocals(1);
			i = codeCondition(condVar);
		}
		else
			i = codeCondition(condition);

		fb->invertJump(i);
		fb->patchTrueToHere(i);
		genBody();

		if(genElse)
		{
			fb->popScope(elseLocation);
			auto j = fb->makeJump(elseLocation);
			fb->patchFalseToHere(i);
			fb->pushScope(scop);
				genElse();
			fb->popScope(endLocation);
			fb->patchJumpToHere(j);
		}
		else
		{
			fb->popScope(endLocation);
			fb->patchFalseToHere(i);
		}
	}

	WhileStmt* Codegen::visit(WhileStmt* s)
	{
		auto beginLoop = fb->here();

		Scope scop;
		fb->pushScope(scop);

		// s.condition->isConstant && !s.condition->isTrue is handled in semantic
		if(s->condition->isConstant() && s->condition->isTrue())
		{
			fb->setBreakable();
			fb->setContinuable();
			fb->setScopeName(s->name);

			if(s->condVar)
			{
				fb->pushNewLocals(1);
				visit(s->condition);
				fb->assign(s->condition->location, 1, 1);
				fb->insertLocal(s->condVar->name);
				fb->activateLocals(1);
			}

			visit(s->code);
			fb->patchContinuesTo(beginLoop);
			fb->jumpTo(s->endLocation, beginLoop);
			fb->patchBreaksToHere();
			fb->popScope(s->endLocation);
		}
		else
		{
			auto cond = InstRef();

			if(s->condVar)
			{
				fb->pushNewLocals(1);
				visit(s->condition);
				fb->assign(s->condition->location, 1, 1);
				fb->insertLocal(s->condVar->name);
				fb->activateLocals(1);
				cond = codeCondition(s->condVar);
			}
			else
				cond = codeCondition(s->condition);

			fb->invertJump(cond);
			fb->patchTrueToHere(cond);
			fb->setBreakable();
			fb->setContinuable();
			fb->setScopeName(s->name);
			visit(s->code);
			fb->patchContinuesTo(beginLoop);
			fb->closeScopeUpvals(s->endLocation);
			fb->jumpTo(s->endLocation, beginLoop);
			fb->patchBreaksToHere();
			fb->popScope(s->endLocation);
			fb->patchFalseToHere(cond);
		}

		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	DoWhileStmt* Codegen::visit(DoWhileStmt* s)
	{
		auto beginLoop = fb->here();
		Scope scop;
		fb->pushScope(scop);
		fb->setBreakable();
		fb->setContinuable();
		fb->setScopeName(s->name);
		visit(s->code);

		if(s->condition->isConstant())
		{
			fb->patchContinuesToHere();

			if(s->condition->isTrue())
				fb->jumpTo(s->endLocation, beginLoop);

			fb->patchBreaksToHere();
			fb->popScope(s->endLocation);
		}
		else
		{
			fb->closeScopeUpvals(s->condition->location);
			fb->patchContinuesToHere();
			auto cond = codeCondition(s->condition);
			fb->invertJump(cond);
			fb->patchTrueToHere(cond);
			fb->jumpTo(s->endLocation, beginLoop);
			fb->patchBreaksToHere();
			fb->popScope(s->endLocation);
			fb->patchFalseToHere(cond);
		}

		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	ForStmt* Codegen::visit(ForStmt* s)
	{
		Scope scop;
		fb->pushScope(scop);
			fb->setBreakable();
			fb->setContinuable();
			fb->setScopeName(s->name);

			for(auto &init: s->init)
			{
				if(init.isDecl)
					visit(init.decl);
				else
				{
					visit(init.stmt);
					fb->popToNothing();
				}
			}

			auto beginLoop = fb->here();
			auto cond = InstRef();

			if(s->condition)
			{
				cond = codeCondition(s->condition);
				fb->invertJump(cond);
				fb->patchTrueToHere(cond);
			}

			visit(s->code);

			fb->closeScopeUpvals(s->location);
			fb->patchContinuesToHere();

			for(auto inc: s->increment)
			{
				visit(inc);
				fb->popToNothing();
			}

			fb->jumpTo(s->endLocation, beginLoop);
			fb->patchBreaksToHere();
		fb->popScope(s->endLocation);

		if(s->condition)
			fb->patchFalseToHere(cond);

		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	ForNumStmt* Codegen::visit(ForNumStmt* s)
	{
		visitForNum(s->location, s->endLocation, s->name, s->lo, s->hi, s->step, s->index,
			[this, &s]{ visit(s->code); });
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	void Codegen::visitForNum(CompileLoc location, CompileLoc endLocation, crocstr name, Expression* lo,
		Expression* hi, Expression* step, Identifier* index, std::function<void()> genBody)
	{
		Scope scop;
		fb->pushScope(scop);
			fb->setBreakable();
			fb->setContinuable();
			fb->setScopeName(name);
			auto forDesc = fb->beginFor(location, [this, &lo, &hi, &step]{ visit(lo); visit(hi); visit(step); });
			fb->insertLocal(index);
			fb->activateLocals(1);
			genBody();
			fb->endFor(endLocation, forDesc);
		fb->popScope(endLocation);
	}

	ForeachStmt* Codegen::visit(ForeachStmt* s)
	{
		visitForeach(s->location, s->endLocation, s->name, s->indices, s->container, [this, &s]{ visit(s->code); });
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	void Codegen::visitForeach(CompileLoc location, CompileLoc endLocation, crocstr name,
		DArray<Identifier*> indices, DArray<Expression*> container, std::function<void()> genBody)
	{
		Scope scop;
		fb->pushScope(scop);
			fb->setBreakable();
			fb->setContinuable();
			fb->setScopeName(name);
			auto desc = fb->beginForeach(location, [this, &container]{ codeGenList(container); }, container.length);

			for(auto i: indices)
				fb->insertLocal(i);

			fb->activateLocals(indices.length);
			genBody();
			fb->endForeach(endLocation, desc, indices.length);
		fb->popScope(endLocation);
	}

	SwitchStmt* Codegen::visit(SwitchStmt* s)
	{
		Scope scop;
		fb->pushScope(scop);
			fb->setBreakable();
			fb->setScopeName(s->name);
			visit(s->condition);
			fb->toSource(s->condition->endLocation);

			for(auto caseStmt: s->cases)
			{
				if(caseStmt->highRange)
				{
					auto &c = caseStmt->conditions[0];
					auto lo = c.exp;
					auto hi = caseStmt->highRange;

					fb->dup();
					visit(lo);
					fb->toSource(lo->endLocation);

					auto jmp1 = fb->codeCmp(lo->location, Comparison_LT);

					fb->dup();
					visit(hi);
					fb->toSource(hi->endLocation);

					auto jmp2 = fb->codeCmp(hi->endLocation, Comparison_GT);

					c.dynJump = fb->makeJump(hi->endLocation);
					fb->patchJumpToHere(jmp1);
					fb->patchJumpToHere(jmp2);
				}
				else
				{
					for(auto &c: caseStmt->conditions)
					{
						if(!c.exp->isConstant())
						{
							fb->dup();
							visit(c.exp);
							fb->toSource(c.exp->endLocation);
							c.dynJump = fb->codeSwitchCmp(c.exp->endLocation);
						}
					}
				}
			}

			fb->beginSwitch(s->location); // pops the condition exp off the stack

			for(auto c: s->cases)
				visit(c);

			if(s->caseDefault)
				visit(s->caseDefault);

			fb->endSwitch();
			fb->patchBreaksToHere();
		fb->popScope(s->endLocation);
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	CaseStmt* Codegen::visit(CaseStmt* s)
	{
		if(s->highRange)
			fb->patchJumpToHere(s->conditions[0].dynJump);
		else
		{
			for(auto &c: s->conditions)
			{
				if(c.exp->isConstant())
					fb->addCase(c.exp->location, c.exp);
				else
					fb->patchJumpToHere(c.dynJump);
			}
		}

		visit(s->code);
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	DefaultStmt* Codegen::visit(DefaultStmt* s)
	{
		fb->addDefault();
		visit(s->code);
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	ContinueStmt* Codegen::visit(ContinueStmt* s)
	{
		fb->codeContinue(s->location, s->name);
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	BreakStmt* Codegen::visit(BreakStmt* s)
	{
		fb->codeBreak(s->location, s->name);
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	ReturnStmt* Codegen::visit(ReturnStmt* s)
	{
		if(!fb->inTryCatch() &&
			s->exprs.length == 1 &&
			(s->exprs[0]->type == AstTag_CallExp || s->exprs[0]->type == AstTag_MethodCallExp))
		{
			visit(s->exprs[0]);
			fb->makeTailcall();
			fb->saveRets(s->exprs[0]->endLocation, 1);
			fb->codeRet(s->endLocation);
		}
		else
		{
			codeGenList(s->exprs);
			fb->saveRets(s->endLocation, s->exprs.length);

			if(fb->inTryCatch())
				fb->codeUnwind(s->endLocation);

			fb->codeRet(s->endLocation);
		}

		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	TryCatchStmt* Codegen::visit(TryCatchStmt* s)
	{
		Scope scop;
		auto pushCatch = fb->codeCatch(s->location, scop);
		visit(s->tryBody);
		auto jumpOverCatch = fb->popCatch(s->tryBody->endLocation, s->transformedCatch->location, pushCatch);

		fb->pushScope(scop);
			fb->insertLocal(s->hiddenCatchVar);
			fb->activateLocals(1);
			visit(s->transformedCatch);
		fb->popScope(s->transformedCatch->endLocation);

		fb->patchJumpToHere(jumpOverCatch);
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	TryFinallyStmt* Codegen::visit(TryFinallyStmt* s)
	{
		Scope scop;
		auto pushFinally = fb->codeFinally(s->location, scop);
		visit(s->tryBody);
		fb->popFinally(s->tryBody->endLocation, s->finallyBody->location, pushFinally);

		fb->pushScope(scop);
			visit(s->finallyBody);
			fb->codeEndFinal(s->finallyBody->endLocation);
		fb->popScope(s->finallyBody->endLocation);

		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	ThrowStmt* Codegen::visit(ThrowStmt* s)
	{
		visit(s->exp);
		fb->toSource(s->exp->endLocation);
		fb->codeThrow(s->endLocation, s->rethrowing);
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	AssignStmt* Codegen::visit(AssignStmt* s)
	{
		for(auto exp: s->lhs)
			exp->checkLHS(c);

		for(auto dest: s->lhs)
			visit(dest);

		fb->resolveAssignmentConflicts(s->lhs[s->lhs.length - 1]->location, s->lhs.length);

		codeGenAssignRHS(s->rhs);
		fb->assign(s->endLocation, s->lhs.length, s->rhs.length);
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	OpAssignStmt* Codegen::visitOpAssign(OpAssignStmt* s)
	{
		if(s->lhs->type != AstTag_ThisExp)
			s->lhs->checkLHS(c);

		visit(s->lhs);
		fb->dup();
		fb->toSource(s->lhs->endLocation);
		visit(s->rhs);
		fb->toSource(s->rhs->endLocation);
		fb->reflexOp(s->endLocation, s->type);
		fb->assign(s->endLocation, 1, 1);
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	Statement* Codegen::visit(AddAssignStmt* s)  { return visitOpAssign(s); }
	Statement* Codegen::visit(SubAssignStmt* s)  { return visitOpAssign(s); }
	Statement* Codegen::visit(MulAssignStmt* s)  { return visitOpAssign(s); }
	Statement* Codegen::visit(DivAssignStmt* s)  { return visitOpAssign(s); }
	Statement* Codegen::visit(ModAssignStmt* s)  { return visitOpAssign(s); }
	Statement* Codegen::visit(AndAssignStmt* s)  { return visitOpAssign(s); }
	Statement* Codegen::visit(OrAssignStmt* s)   { return visitOpAssign(s); }
	Statement* Codegen::visit(XorAssignStmt* s)  { return visitOpAssign(s); }
	Statement* Codegen::visit(ShlAssignStmt* s)  { return visitOpAssign(s); }
	Statement* Codegen::visit(ShrAssignStmt* s)  { return visitOpAssign(s); }
	Statement* Codegen::visit(UShrAssignStmt* s) { return visitOpAssign(s); }

	CondAssignStmt* Codegen::visit(CondAssignStmt* s)
	{
		visit(s->lhs);
		fb->dup();
		fb->toSource(s->lhs->endLocation);
		fb->pushNull();
		auto i = fb->codeIs(s->lhs->endLocation, false);
		visit(s->rhs);
		fb->assign(s->endLocation, 1, 1);
		fb->patchJumpToHere(i);
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	CatAssignStmt* Codegen::visit(CatAssignStmt* s)
	{
		assert(s->collapsed);
		assert(s->operands.length >= 1);

		if(s->lhs->type != AstTag_ThisExp)
			s->lhs->checkLHS(c);

		visit(s->lhs);
		fb->dup();
		fb->toSource(s->lhs->endLocation);
		codeGenList(s->operands, false);
		fb->concatEq(s->endLocation, s->operands.length);
		fb->assign(s->endLocation, 1, 1);
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	IncStmt* Codegen::visit(IncStmt* s)
	{
		if(s->exp->type != AstTag_ThisExp)
			s->exp->checkLHS(c);

		visit(s->exp);
		fb->dup();
		fb->toSource(s->exp->endLocation);
		fb->incDec(s->endLocation, s->type);
		fb->assign(s->endLocation, 1, 1);
		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	DecStmt* Codegen::visit(DecStmt* s)
	{
		if(s->exp->type != AstTag_ThisExp)
			s->exp->checkLHS(c);

		visit(s->exp);
		fb->dup();
		fb->toSource(s->exp->endLocation);

		fb->incDec(s->endLocation, s->type);
		fb->assign(s->endLocation, 1, 1);

		DEBUG_EXPSTACKCHECK(fb->checkExpStackEmpty();)
		return s;
	}

	CondExp* Codegen::visit(CondExp* e)
	{
		fb->pushNewLocals(1);
		auto c = codeCondition(e->cond);
		fb->invertJump(c);
		fb->patchTrueToHere(c);
		fb->dup();
		visit(e->op1);
		fb->assign(e->op1->endLocation, 1, 1);
		auto i = fb->makeJump(e->op1->endLocation);
		fb->patchFalseToHere(c);
		fb->dup();
		visit(e->op2);
		fb->assign(e->op2->endLocation, 1, 1);
		fb->patchJumpToHere(i);
		fb->toTemporary(e->endLocation);
		return e;
	}

	OrOrExp* Codegen::visit(OrOrExp* e)
	{
		fb->pushNewLocals(1);
		fb->dup();
		visit(e->op1);
		fb->assign(e->op1->endLocation, 1, 1);
		fb->dup();
		fb->toSource(e->op1->endLocation);
		auto i = fb->codeIsTrue(e->op1->endLocation);
		fb->dup();
		visit(e->op2);
		fb->assign(e->op2->endLocation, 1, 1);
		fb->patchJumpToHere(i);
		fb->toTemporary(e->endLocation);
		return e;
	}

	AndAndExp* Codegen::visit(AndAndExp* e)
	{
		fb->pushNewLocals(1);
		fb->dup();
		visit(e->op1);
		fb->assign(e->op1->endLocation, 1, 1);
		fb->dup();
		fb->toSource(e->op1->endLocation);
		auto i = fb->codeIsTrue(e->op1->endLocation, false);
		fb->dup();
		visit(e->op2);
		fb->assign(e->op2->endLocation, 1, 1);
		fb->patchJumpToHere(i);
		fb->toTemporary(e->endLocation);
		return e;
	}

	BinaryExp* Codegen::visitBinExp(BinaryExp* e)
	{
		visit(e->op1);
		fb->toSource(e->op1->endLocation);
		visit(e->op2);
		fb->toSource(e->op2->endLocation);
		fb->binOp(e->endLocation, e->type);
		return e;
	}

	BinaryExp* Codegen::visit(AddExp* e)  { return visitBinExp(e); }
	BinaryExp* Codegen::visit(SubExp* e)  { return visitBinExp(e); }
	BinaryExp* Codegen::visit(MulExp* e)  { return visitBinExp(e); }
	BinaryExp* Codegen::visit(DivExp* e)  { return visitBinExp(e); }
	BinaryExp* Codegen::visit(ModExp* e)  { return visitBinExp(e); }
	BinaryExp* Codegen::visit(AndExp* e)  { return visitBinExp(e); }
	BinaryExp* Codegen::visit(OrExp* e)   { return visitBinExp(e); }
	BinaryExp* Codegen::visit(XorExp* e)  { return visitBinExp(e); }
	BinaryExp* Codegen::visit(ShlExp* e)  { return visitBinExp(e); }
	BinaryExp* Codegen::visit(ShrExp* e)  { return visitBinExp(e); }
	BinaryExp* Codegen::visit(UShrExp* e) { return visitBinExp(e); }
	BinaryExp* Codegen::visit(Cmp3Exp* e) { return visitBinExp(e); }

	CatExp* Codegen::visit(CatExp* e)
	{
		assert(e->collapsed == true);
		assert(e->operands.length >= 2);
		codeGenList(e->operands, false);
		fb->concat(e->endLocation, e->operands.length);
		return e;
	}

	BinaryExp* Codegen::visitComparisonExp(BinaryExp* e)
	{
		fb->pushNewLocals(1);
		auto i = codeCondition(e);
		fb->dup();
		fb->pushBool(false);
		fb->assign(e->endLocation, 1, 1);
		auto j = fb->makeJump(e->endLocation);
		fb->patchTrueToHere(i);
		fb->dup();
		fb->pushBool(true);
		fb->assign(e->endLocation, 1, 1);
		fb->patchJumpToHere(j);
		fb->toTemporary(e->endLocation);
		return e;
	}

	BinaryExp* Codegen::visit(EqualExp* e)    { return visitComparisonExp(e); }
	BinaryExp* Codegen::visit(NotEqualExp* e) { return visitComparisonExp(e); }
	BinaryExp* Codegen::visit(IsExp* e)       { return visitComparisonExp(e); }
	BinaryExp* Codegen::visit(NotIsExp* e)    { return visitComparisonExp(e); }
	BinaryExp* Codegen::visit(LTExp* e)       { return visitComparisonExp(e); }
	BinaryExp* Codegen::visit(LEExp* e)       { return visitComparisonExp(e); }
	BinaryExp* Codegen::visit(GTExp* e)       { return visitComparisonExp(e); }
	BinaryExp* Codegen::visit(GEExp* e)       { return visitComparisonExp(e); }
	BinaryExp* Codegen::visit(InExp* e)       { return visitComparisonExp(e); }
	BinaryExp* Codegen::visit(NotInExp* e)    { return visitComparisonExp(e); }

	UnExp* Codegen::visitUnExp(UnExp* e)
	{
		visit(e->op);
		fb->toSource(e->op->endLocation);
		fb->unOp(e->endLocation, e->type);
		return e;
	}

	UnExp* Codegen::visit(NegExp* e)      { return visitUnExp(e); }
	UnExp* Codegen::visit(NotExp* e)      { return visitUnExp(e); }
	UnExp* Codegen::visit(ComExp* e)      { return visitUnExp(e); }
	UnExp* Codegen::visit(DotSuperExp* e) { return visitUnExp(e); }

	LenExp* Codegen::visit(LenExp* e)
	{
		visit(e->op);
		fb->toSource(e->op->endLocation);
		fb->length();
		return e;
	}

	VargLenExp* Codegen::visit(VargLenExp* e)
	{
		if(!fb->isVararg())
			c.semException(e->location, "'vararg' cannot be used in a non-variadic function");

		fb->pushVargLen(e->endLocation);
		return e;
	}

	DotExp* Codegen::visit(DotExp* e)
	{
		visit(e->op);
		fb->toSource(e->op->endLocation);
		visit(e->name);
		fb->toSource(e->endLocation);
		fb->field();
		return e;
	}

	MethodCallExp* Codegen::visit(MethodCallExp* e)
	{
		visitMethodCall(e->location, e->endLocation, e->op, e->method, [&]
		{
			codeGenList(e->args);
			return e->args.length;
		});

		return e;
	}

	void Codegen::visitMethodCall(CompileLoc location, CompileLoc endLocation, Expression* op, Expression* method,
		std::function<uword()> genArgs)
	{
		auto desc = fb->beginMethodCall();
		visit(op);
		fb->toSource(location);
		fb->updateMethodCall(desc, 1);
		visit(method);
		fb->toSource(method->endLocation);
		fb->updateMethodCall(desc, 2);
		genArgs();
		fb->pushMethodCall(endLocation, desc);
	}

	CallExp* Codegen::visit(CallExp* e)
	{
		visitCall(e->endLocation, e->op, e->context, [&]
		{
			codeGenList(e->args);
			return e->args.length;
		});

		return e;
	}

	void Codegen::visitCall(CompileLoc endLocation, Expression* op, Expression* context,
		std::function<uword()> genArgs)
	{
		visit(op);
		fb->toTemporary(op->endLocation);

		if(context)
		{
			visit(context);
			fb->toTemporary(context->endLocation);
		}
		else
		{
			fb->pushNull();
			fb->toTemporary(op->endLocation);
		}

		auto numArgs = genArgs();
		fb->pushCall(endLocation, numArgs);
	}

	IndexExp* Codegen::visit(IndexExp* e)
	{
		visit(e->op);
		fb->toSource(e->op->endLocation);
		visit(e->index);
		fb->toSource(e->endLocation);
		fb->index();
		return e;
	}

	VargIndexExp* Codegen::visit(VargIndexExp* e)
	{
		if(!fb->isVararg())
			c.semException(e->location, "'vararg' cannot be used in a non-variadic function");

		visit(e->index);
		fb->toSource(e->index->endLocation);
		fb->varargIndex();
		return e;
	}

	SliceExp* Codegen::visit(SliceExp* e)
	{
		Expression* list[3];
		list[0] = e->op;
		list[1] = e->loIndex;
		list[2] = e->hiIndex;
		codeGenList(DArray<Expression*>::n(list, 3), false);
		fb->slice();
		return e;
	}

	VargSliceExp* Codegen::visit(VargSliceExp* e)
	{
		if(!fb->isVararg())
			c.semException(e->location, "'vararg' cannot be used in a non-variadic function");

		Expression* list[2];
		list[0] = e->loIndex;
		list[1] = e->hiIndex;
		codeGenList(DArray<Expression*>::n(list, 2), false);
		fb->varargSlice(e->endLocation);
		return e;
	}

	IdentExp* Codegen::visit(IdentExp* e)
	{
		fb->pushVar(e->name);
		return e;
	}

	ThisExp* Codegen::visit(ThisExp* e)
	{
		fb->pushThis();
		return e;
	}

	NullExp* Codegen::visit(NullExp* e)
	{
		fb->pushNull();
		return e;
	}

	BoolExp* Codegen::visit(BoolExp* e)
	{
		fb->pushBool(e->value);
		return e;
	}

	IntExp* Codegen::visit(IntExp* e)
	{
		fb->pushInt(e->value);
		return e;
	}

	FloatExp* Codegen::visit(FloatExp* e)
	{
		fb->pushFloat(e->value);
		return e;
	}

	StringExp* Codegen::visit(StringExp* e)
	{
		fb->pushString(e->value);
		return e;
	}

	VarargExp* Codegen::visit(VarargExp* e)
	{
		if(!fb->isVararg())
			c.semException(e->location, "'vararg' cannot be used in a non-variadic function");

		fb->pushVararg(e->location);
		return e;
	}

	FuncLiteralExp* Codegen::visit(FuncLiteralExp* e)
	{
		visit(e->def);
		return e;
	}

	ParenExp* Codegen::visit(ParenExp* e)
	{
		assert(e->exp->isMultRet());
		visit(e->exp);
		fb->toTemporary(e->endLocation);
		return e;
	}

	TableCtorExp* Codegen::visit(TableCtorExp* e)
	{
		fb->pushTable(e->location);

		for(auto &field: e->fields)
		{
			fb->dup();
			visit(field.key);
			fb->toSource(field.key->endLocation);
			fb->index();
			visit(field.value);
			fb->assign(field.value->endLocation, 1, 1);
		}

		return e;
	}

	ArrayCtorExp* Codegen::visit(ArrayCtorExp* e)
	{
		if(e->values.length > INST_MAX_ARRAY_FIELDS)
			c.semException(e->location, "Array constructor has too many fields (more than %u)", INST_MAX_ARRAY_FIELDS);

		if(e->values.length > 0 && e->values[e->values.length - 1]->isMultRet())
			fb->pushArray(e->location, e->values.length - 1);
		else
			fb->pushArray(e->location, e->values.length);

		if(e->values.length > 0)
		{
			uword index = 0;
			uword fieldsLeft = e->values.length;
			uword block = 0;

			while(fieldsLeft > 0)
			{
				auto numToDo = fieldsLeft < INST_ARRAY_SET_FIELDS ? fieldsLeft : INST_ARRAY_SET_FIELDS;
				fieldsLeft -= numToDo;
				fb->dup();
				codeGenList(e->values.slice(index, index + numToDo), fieldsLeft == 0);
				fb->arraySet(e->values[index + numToDo - 1]->endLocation, numToDo, block);
				index += numToDo;
				block++;
			}
		}

		return e;
	}

	YieldExp* Codegen::visit(YieldExp* e)
	{
		codeGenList(e->args);
		fb->pushYield(e->endLocation, e->args.length);
		return e;
	}

	TableComprehension* Codegen::visit(TableComprehension* e)
	{
		fb->pushTable(e->location);
		visitForComp(e->forComp, [&]
		{
			fb->dup();
			visit(e->key);
			fb->toSource(e->key->endLocation);
			fb->index();
			visit(e->value);
			fb->assign(e->value->endLocation, 1, 1);
		});
		return e;
	}

	ArrayComprehension* Codegen::visit(ArrayComprehension* e)
	{
		fb->pushArray(e->location, 0);
		visitForComp(e->forComp, [&]
		{
			fb->dup();
			visit(e->exp);
			fb->toSource(e->exp->endLocation);
			fb->arrayAppend(e->exp->endLocation);
		});
		return e;
	}

	ForComprehension* Codegen::visitForComp(ForComprehension* e, std::function<void()> inner)
	{
		if(auto x = AST_AS(ForeachComprehension, e))
			return visitForeachComp(x, inner);
		else
		{
			auto y = AST_AS(ForNumComprehension, e);
			assert(y);
			return visitForNumComp(y, inner);
		}
	}

	ForeachComprehension* Codegen::visitForeachComp(ForeachComprehension* e, std::function<void()> inner)
	{
		auto newInner = inner;

		if(e->ifComp)
		{
			if(e->forComp)
				newInner = [this, &e, &inner]{ visit(e->ifComp,
					[this, &e, &inner]{ visitForComp(e->forComp, inner); }); };
			else
				newInner = [this, &e, &inner]{ visit(e->ifComp, inner); };
		}
		else if(e->forComp)
			newInner = [&]{ visitForComp(e->forComp, inner); };

		visitForeach(e->location, e->endLocation, crocstr(), e->indices, e->container, newInner);
		return e;
	}

	ForNumComprehension* Codegen::visitForNumComp(ForNumComprehension* e, std::function<void()> inner)
	{
		auto newInner = inner;

		if(e->ifComp)
		{
			if(e->forComp)
				newInner = [this, &e, &inner]{ visit(e->ifComp,
					[this, &e, &inner]{ visitForComp(e->forComp, inner); }); };
			else
				newInner = [this, &e, &inner]{ visit(e->ifComp, inner); };
		}
		else if(e->forComp)
			newInner = [&]{ visitForComp(e->forComp, inner); };

		visitForNum(e->location, e->endLocation, crocstr(), e->lo, e->hi, e->step, e->index, newInner);
		return e;
	}

	IfComprehension* Codegen::visit(IfComprehension* e, std::function<void()> inner)
	{
		visitIf(e->endLocation, e->endLocation, nullptr, e->condition, inner, nullptr);
		return e;
	}

	void Codegen::codeGenList(DArray<Expression*> exprs, bool allowMultRet)
	{
		if(exprs.length == 0)
			return;

		for(auto e: exprs.slice(0, exprs.length - 1))
		{
			visit(e);
			fb->toTemporary(e->endLocation);
		}

		visit(exprs[exprs.length - 1]);

		if(!allowMultRet || !exprs[exprs.length - 1]->isMultRet())
			fb->toTemporary(exprs[exprs.length - 1]->endLocation);
	}

	void Codegen::codeGenAssignRHS(DArray<Expression*> exprs)
	{
		if(exprs.length == 0)
			return;

		for(auto e: exprs.slice(0, exprs.length - 1))
		{
			visit(e);
			fb->toTemporary(e->endLocation);
		}

		visit(exprs[exprs.length - 1]);
	}

	// ---------------------------------------------------------------------------
	// Condition codegen

	InstRef Codegen::codeCondition(Expression* e)
	{
		switch(e->type)
		{
			case AstTag_CondExp:     return codeCondition(cast(CondExp*)e);
			case AstTag_OrOrExp:     return codeCondition(cast(OrOrExp*)e);
			case AstTag_AndAndExp:   return codeCondition(cast(AndAndExp*)e);
			case AstTag_EqualExp:    return codeCondition(cast(EqualExp*)e);
			case AstTag_NotEqualExp: return codeCondition(cast(NotEqualExp*)e);
			case AstTag_IsExp:       return codeCondition(cast(IsExp*)e);
			case AstTag_NotIsExp:    return codeCondition(cast(NotIsExp*)e);
			case AstTag_InExp:       return codeCondition(cast(InExp*)e);
			case AstTag_NotInExp:    return codeCondition(cast(NotInExp*)e);
			case AstTag_LTExp:       return codeCondition(cast(LTExp*)e);
			case AstTag_LEExp:       return codeCondition(cast(LEExp*)e);
			case AstTag_GTExp:       return codeCondition(cast(GTExp*)e);
			case AstTag_GEExp:       return codeCondition(cast(GEExp*)e);
			case AstTag_ParenExp:    return codeCondition(cast(ParenExp*)e);

			default:
				visit(e);
				fb->toSource(e->endLocation);
				auto ret = InstRef();
				ret.trueList = fb->codeIsTrue(e->endLocation);
				return ret;
		}
	}

	InstRef Codegen::codeCondition(CondExp* e)
	{
		auto c = codeCondition(e->cond);
		fb->invertJump(c);
		fb->patchTrueToHere(c);
		auto left = codeCondition(e->op1);
		fb->invertJump(left);
		fb->patchTrueToHere(left);
		auto trueJump = fb->makeJump(e->op1->endLocation);
		fb->patchFalseToHere(c);
		// Done with c
		auto right = codeCondition(e->op2);
		fb->catToFalse(right, left.falseList);
		fb->catToTrue(right, trueJump);
		return right;
	}

	InstRef Codegen::codeCondition(OrOrExp* e)
	{
		auto left = codeCondition(e->op1);
		fb->patchFalseToHere(left);
		auto right = codeCondition(e->op2);
		fb->catToTrue(right, left.trueList);
		return right;
	}

	InstRef Codegen::codeCondition(AndAndExp* e)
	{
		auto left = codeCondition(e->op1);
		fb->invertJump(left);
		fb->patchTrueToHere(left);
		auto right = codeCondition(e->op2);
		fb->catToFalse(right, left.falseList);
		return right;
	}

	InstRef Codegen::codeEqualExpCondition(BinaryExp* e)
	{
		visit(e->op1);
		fb->toSource(e->op1->endLocation);
		visit(e->op2);
		fb->toSource(e->op2->endLocation);

		auto ret = InstRef();

		switch(e->type)
		{
			case AstTag_EqualExp:    ret.trueList = fb->codeEquals(e->op2->endLocation, true);  break;
			case AstTag_NotEqualExp: ret.trueList = fb->codeEquals(e->op2->endLocation, false); break;
			case AstTag_IsExp:       ret.trueList = fb->codeIs(e->op2->endLocation, true);      break;
			case AstTag_NotIsExp:    ret.trueList = fb->codeIs(e->op2->endLocation, false);     break;
			case AstTag_InExp:       ret.trueList = fb->codeIn(e->op2->endLocation, true);      break;
			case AstTag_NotInExp:    ret.trueList = fb->codeIn(e->op2->endLocation, false);     break;
			default: assert(false);
		}

		return ret;
	}

	InstRef Codegen::codeCondition(EqualExp* e)    { return codeEqualExpCondition(e); }
	InstRef Codegen::codeCondition(NotEqualExp* e) { return codeEqualExpCondition(e); }
	InstRef Codegen::codeCondition(IsExp* e)       { return codeEqualExpCondition(e); }
	InstRef Codegen::codeCondition(NotIsExp* e)    { return codeEqualExpCondition(e); }
	InstRef Codegen::codeCondition(InExp* e)       { return codeEqualExpCondition(e); }
	InstRef Codegen::codeCondition(NotInExp* e)    { return codeEqualExpCondition(e); }

	InstRef Codegen::codeCmpExpCondition(BinaryExp* e)
	{
		visit(e->op1);
		fb->toSource(e->op1->endLocation);
		visit(e->op2);
		fb->toSource(e->op2->endLocation);

		auto ret = InstRef();

		switch(e->type)
		{
			case AstTag_LTExp: ret.trueList = fb->codeCmp(e->endLocation, Comparison_LT); break;
			case AstTag_LEExp: ret.trueList = fb->codeCmp(e->endLocation, Comparison_LE); break;
			case AstTag_GTExp: ret.trueList = fb->codeCmp(e->endLocation, Comparison_GT); break;
			case AstTag_GEExp: ret.trueList = fb->codeCmp(e->endLocation, Comparison_GE); break;
			default: assert(false);
		}

		return ret;
	}

	InstRef Codegen::codeCondition(LTExp* e) { return codeCmpExpCondition(e); }
	InstRef Codegen::codeCondition(LEExp* e) { return codeCmpExpCondition(e); }
	InstRef Codegen::codeCondition(GTExp* e) { return codeCmpExpCondition(e); }
	InstRef Codegen::codeCondition(GEExp* e) { return codeCmpExpCondition(e); }

	// Have to keep this cause it "unwraps" the ParenExp, which the default case in codeCondition does not
	InstRef Codegen::codeCondition(ParenExp* e)
	{
		visit(e->exp);
		fb->toSource(e->exp->endLocation);
		auto ret = InstRef();
		ret.trueList = fb->codeIsTrue(e->exp->endLocation);
		return ret;
	}
}