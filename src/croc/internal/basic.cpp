
#include <functional>

#include "croc/api.h"
#include "croc/internal/basic.hpp"
#include "croc/internal/calls.hpp"
#include "croc/internal/interpreter.hpp"
#include "croc/internal/stack.hpp"
#include "croc/types.hpp"

#define BUFFERLENGTH 120
#define PUSHFMT(...)\
	push(t, Value::from(String::create(t->vm, DArray<const char>::n(buffer,\
		snprintf(buffer, BUFFERLENGTH, __VA_ARGS__)))));

namespace croc
{
	bool validIndices(crocint lo, crocint hi, uword len)
	{
		return lo >= 0 && hi <= len && lo <= hi;
	}

	bool correctIndices(crocint& loIndex, crocint& hiIndex, Value lo, Value hi, uword len)
	{
		if(lo.type == CrocType_Null)
			loIndex = 0;
		else if(lo.type == CrocType_Int)
		{
			loIndex = lo.mInt;

			if(loIndex < 0)
				loIndex += len;
		}
		else
			return false;

		if(hi.type == CrocType_Null)
			hiIndex = len;
		else if(hi.type == CrocType_Int)
		{
			hiIndex = hi.mInt;

			if(hiIndex < 0)
				hiIndex += len;
		}
		else
			return false;

		return true;
	}

	word toStringImpl(Thread* t, Value v, bool raw)
	{
		char buffer[BUFFERLENGTH];

		// ORDER CROCTYPE
		if(v.type < CrocType_FirstRefType)
		{
			switch(v.type)
			{
				case CrocType_Null:      return croc_pushString(*t, "null");
				case CrocType_Bool:      return croc_pushString(*t, v.mBool ? "true" : "false");
				case CrocType_Int:       return PUSHFMT("%" CROC_INTEGER_FORMAT, v.mInt);
				case CrocType_Float:     return PUSHFMT("%f", v.mFloat);
				case CrocType_String:    return push(t, v);
				case CrocType_Nativeobj:
				case CrocType_Weakref:   return PUSHFMT("%s 0x%p", typeToString(v.type), cast(void*)v.mGCObj);
				default: assert(false);
			}
		}

		if(!raw)
		{
			if(auto method = getMM(t, v, MM_ToString))
			{
				auto funcSlot = push(t, Value::from(method));
				push(t, v);
				commonCall(t, funcSlot + t->stackBase, 1, callPrologue(t, funcSlot + t->stackBase, 1, 1));

				if(t->stack[t->stackIndex - 1].type != CrocType_String)
				{
					pushTypeStringImpl(t, t->stack[t->stackIndex - 1]);
					croc_eh_throwStd(*t, "TypeError",
						"toString was supposed to return a string, but returned a '%s'", croc_getString(*t, -1));
				}

				return croc_getStackSize(*t) - 1;
			}
		}

		switch(v.type)
		{
			case CrocType_Function: {
				auto f = v.mFunction;

				if(f->isNative)
				{
					return croc_pushFormat(*t, "native %s %s", typeToString(CrocType_Function), f->name->toCString());
				}
				else
				{
					auto sf = f->scriptFunc;
					return croc_pushFormat(*t, "script %s %s(%s(%u:%u))",
						typeToString(CrocType_Function),
						f->name->toCString(),
						sf->locFile->toCString(),
						sf->locLine, sf->locCol);
				}
			}
			case CrocType_Class: {
				return croc_pushFormat(*t, "%s %s (0x%p)",
					typeToString(CrocType_Class),
					v.mClass->name->toCString(),
					cast(void*)v.mClass);
			}
			case CrocType_Instance: {
				auto pname = v.mInstance->parent->name;
				return croc_pushFormat(*t, "%s of %s (0x%p)",
					typeToString(CrocType_Instance),
					pname->toCString(),
					cast(void*)v.mInstance);
			}
			case CrocType_Namespace: {
				if(raw)
					goto _default;

				croc_pushString(*t, typeToString(CrocType_Namespace));
				croc_pushString(*t, " ");
				pushFullNamespaceName(t, v.mNamespace);

				auto slot = t->stackIndex - 3;
				catImpl(t, slot, slot, 3);
				croc_pop(*t, 2);
				return slot - t->stackBase;
			}
			case CrocType_Funcdef: {
				auto d = v.mFuncdef;
				return croc_pushFormat(*t, "%s %s(%s(%u:%u))",
					typeToString(CrocType_Funcdef),
					d->name->toCString(),
					d->locFile->toCString(),
					d->locLine, d->locCol);
			}
			default:
			_default: {
				return croc_pushFormat(*t, "%s 0x%p", typeToString(v.type), cast(void*)v.mGCObj);
			}
		}
	}

	word pushFullNamespaceName(Thread* t, Namespace* ns)
	{
		std::function<uword(Namespace*)> namespaceName = [&t, &namespaceName](Namespace* ns) -> uword
		{
			if(ns->name->cpLength == 0)
				return 0;

			uword n = 0;

			if(ns->parent)
			{
				auto ret = namespaceName(ns->parent);

				if(ret > 0)
				{
					croc_pushString(*t, ".");
					n = ret + 1;
				}
			}

			push(t, Value::from(ns->name));
			return n + 1;
		};

		auto x = namespaceName(ns);

		if(x == 0)
			return croc_pushString(*t, "");
		else
		{
			auto slot = t->stackIndex - x;
			catImpl(t, slot, slot, x);

			if(x > 1)
				croc_pop(*t, x - 1);

			return slot - t->stackBase;
		}
	}

	word pushTypeStringImpl(Thread* t, Value v)
	{
		switch(v.type)
		{
			case CrocType_Null:
			case CrocType_Bool:
			case CrocType_Int:
			case CrocType_Float:
			case CrocType_Nativeobj:
			case CrocType_String:
			case CrocType_Weakref:
			case CrocType_Table:
			case CrocType_Namespace:
			case CrocType_Array:
			case CrocType_Memblock:
			case CrocType_Function:
			case CrocType_Funcdef:
			case CrocType_Thread:
				return croc_pushString(*t, typeToString(v.type));

			case CrocType_Class: {
				auto n = v.mClass->name;
				return croc_pushFormat(*t, "%s %s", typeToString(CrocType_Class), n->toCString());
			}
			case CrocType_Instance: {
				auto n = v.mInstance->parent->name;
				return croc_pushFormat(*t, "%s of %s", typeToString(CrocType_Instance), n->toCString());
			}
			default: assert(false);
		}
	}

	bool inImpl(Thread* t, Value item, Value container)
	{
		switch(container.type)
		{
			case CrocType_String:
				if(item.type == CrocType_String)
					return container.mString->contains(item.mString->toDArray());
				else
				{
					pushTypeStringImpl(t, item);
					croc_eh_throwStd(*t, "TypeError", "Can only use strings to look in strings, not '%s'",
						croc_getString(*t, -1));
				}

			case CrocType_Table:
				return container.mTable->contains(item);

			case CrocType_Array:
				return container.mArray->contains(item);

			case CrocType_Namespace:
				if(item.type != CrocType_String)
				{
					pushTypeStringImpl(t, item);
					croc_eh_throwStd(*t, "TypeError", "Can only use strings to look in namespaces, not '%s'",
						croc_getString(*t, -1));
				}

				return container.mNamespace->contains(item.mString);

			default:
				auto method = getMM(t, container, MM_In);

				if(method == nullptr)
				{
					pushTypeStringImpl(t, container);
					croc_eh_throwStd(*t, "TypeError", "No implementation of %s for type '%s'",
						MetaNames[MM_In], croc_getString(*t, -1));
				}

				auto funcSlot = push(t, Value::from(method));
				push(t, container);
				push(t, item);
				commonCall(t, funcSlot + t->stackBase, 1, callPrologue(t, funcSlot + t->stackBase, 1, 2));

				auto ret = !t->stack[t->stackIndex - 1].isFalse();
				croc_popTop(*t);
				return ret;
		}
	}

	namespace
	{
		crocint commonCompare(Thread* t, Function* method, Value a, Value b)
		{
			auto funcReg = push(t, Value::from(method));
			push(t, a);
			push(t, b);
			commonCall(t, funcReg + t->stackBase, 1, callPrologue(t, funcReg + t->stackBase, 1, 2));

			auto ret = *getValue(t, -1);
			croc_popTop(*t);

			if(ret.type != CrocType_Int)
			{
				pushTypeStringImpl(t, ret);
				croc_eh_throwStd(*t, "TypeError", "%s is expected to return an int, but '%s' was returned instead",
					MetaNames[MM_Cmp], croc_getString(*t, -1));
			}

			return ret.mInt;
		}
	}

	crocint cmpImpl(Thread* t, Value a, Value b)
	{
		if(a.type == CrocType_Int)
		{
			if(b.type == CrocType_Int)
				return Compare3(a.mInt, b.mInt);
			else if(b.type == CrocType_Float)
				return Compare3(cast(crocfloat)a.mInt, b.mFloat);
		}
		else if(a.type == CrocType_Float)
		{
			if(b.type == CrocType_Int)
				return Compare3(a.mFloat, cast(crocfloat)b.mInt);
			else if(b.type == CrocType_Float)
				return Compare3(a.mFloat, b.mFloat);
		}

		if(a.type == b.type)
		{
			switch(a.type)
			{
				case CrocType_Null:   return 0;
				case CrocType_Bool:   return (cast(crocint)a.mBool - cast(crocint)b.mBool);
				case CrocType_String: return (a.mString == b.mString) ? 0 : a.mString->compare(b.mString);
				default: break;
			}
		}

		if(a.type == b.type || b.type != CrocType_Instance)
		{
			if(auto method = getMM(t, a, MM_Cmp))
				return commonCompare(t, method, a, b);
			else if(auto method = getMM(t, b, MM_Cmp))
				return -commonCompare(t, method, b, a);
		}
		else
		{
			if(auto method = getMM(t, b, MM_Cmp))
				return -commonCompare(t, method, b, a);
			else if(auto method = getMM(t, a, MM_Cmp))
				return commonCompare(t, method, a, b);
		}

		pushTypeStringImpl(t, a);
		pushTypeStringImpl(t, b);
		croc_eh_throwStd(*t, "TypeError", "Can't compare types '%s' and '%s'",
			croc_getString(*t, -2), croc_getString(*t, -1));
		assert(false);
	}

	bool switchCmpImpl(Thread* t, Value a, Value b)
	{
		if(a.type != b.type)
			return false;

		if(a == b)
			return true;

		if(a.type == CrocType_Instance)
		{
			if(auto method = getMM(t, a, MM_Cmp))
				return commonCompare(t, method, a, b) == 0;
			else if(auto method = getMM(t, b, MM_Cmp))
				return commonCompare(t, method, b, a) == 0;
		}

		return false;
	}

	namespace
	{
		bool commonEquals(Thread* t, Function* method, Value a, Value b)
		{
			auto funcReg = push(t, Value::from(method));
			push(t, a);
			push(t, b);
			commonCall(t, funcReg + t->stackBase, 1, callPrologue(t, funcReg + t->stackBase, 1, 2));

			auto ret = *getValue(t, -1);
			croc_popTop(*t);

			if(ret.type != CrocType_Bool)
			{
				pushTypeStringImpl(t, ret);
				croc_eh_throwStd(*t, "TypeError", "%s is expected to return a bool, but '%s' was returned instead",
					MetaNames[MM_Equals], croc_getString(*t, -1));
			}

			return ret.mInt;
		}
	}

	bool equalsImpl(Thread* t, Value a, Value b)
	{
		if(a.type == CrocType_Int)
		{
			if(b.type == CrocType_Int)
				return a.mInt == b.mInt;
			else if(b.type == CrocType_Float)
				return (cast(crocfloat)a.mInt) == b.mFloat;
		}
		else if(a.type == CrocType_Float)
		{
			if(b.type == CrocType_Int)
				return a.mFloat == (cast(crocfloat)b.mInt);
			else if(b.type == CrocType_Float)
				return a.mFloat == b.mFloat;
		}

		if(a.type == b.type)
		{
			switch(a.type)
			{
				case CrocType_Null:   return true;
				case CrocType_Bool:   return a.mBool == b.mBool;
				case CrocType_String: return a.mString == b.mString;
				default: break;
			}
		}

		if(a.type == b.type || b.type != CrocType_Instance)
		{
			if(auto method = getMM(t, a, MM_Equals))
				return commonEquals(t, method, a, b);
			else if(auto method = getMM(t, b, MM_Equals))
				return commonEquals(t, method, b, a);
		}
		else
		{
			if(auto method = getMM(t, b, MM_Equals))
				return commonEquals(t, method, b, a);
			else if(auto method = getMM(t, a, MM_Equals))
				return commonEquals(t, method, a, b);
		}

		pushTypeStringImpl(t, a);
		pushTypeStringImpl(t, b);
		croc_eh_throwStd(*t, "TypeError", "Can't compare types '%s' and '%s' for equality",
			croc_getString(*t, -2), croc_getString(*t, -1));
		assert(false);
	}

	void idxImpl(Thread* t, AbsStack dest, Value container, Value key)
	{
		switch(container.type)
		{
			case CrocType_Array: {
				if(key.type != CrocType_Int)
				{
					pushTypeStringImpl(t, key);
					croc_eh_throwStd(*t, "TypeError", "Attempting to index an array with a '%s'",
						croc_getString(*t, -1));
				}

				auto index = key.mInt;
				auto arr = container.mArray;

				if(index < 0)
					index += arr->length;

				if(index < 0 || index >= arr->length)
					croc_eh_throwStd(*t, "BoundsError", "Invalid array index %" CROC_INTEGER_FORMAT " (length is %u)", key.mInt, arr->length);

				t->stack[dest] = arr->toDArray()[cast(uword)index].value;
				return;
			}
			case CrocType_Memblock: {
				if(key.type != CrocType_Int)
				{
					pushTypeStringImpl(t, key);
					croc_eh_throwStd(*t, "TypeError", "Attempting to index a memblock with a '%s'",
						croc_getString(*t, -1));
				}

				auto index = key.mInt;
				auto mb = container.mMemblock;

				if(index < 0)
					index += mb->data.length;

				if(index < 0 || index >= mb->data.length)
					croc_eh_throwStd(*t, "BoundsError",
						"Invalid memblock index %" CROC_INTEGER_FORMAT " (length is %u)",
						key.mInt, mb->data.length);

				t->stack[dest] = Value::from(cast(crocint)mb->data[cast(uword)index]);
				return;
			}
			case CrocType_String: {
				if(key.type != CrocType_Int)
				{
					pushTypeStringImpl(t, key);
					croc_eh_throwStd(*t, "TypeError", "Attempting to index a string with a '%s'",
						croc_getString(*t, -1));
				}

				auto index = key.mInt;
				auto str = container.mString;

				if(index < 0)
					index += str->cpLength;

				if(index < 0 || index >= str->cpLength)
					croc_eh_throwStd(*t, "BoundsError", "Invalid string index %" CROC_INTEGER_FORMAT " (length is %u)",
						key.mInt, str->cpLength);

				auto s = str->toDArray();
				auto offs = utf8CPIdxToByte(s, cast(uword)index);
				auto len = utf8SequenceLength(s[offs]);
				t->stack[dest] = Value::from(String::createUnverified(t->vm, s.slice(offs, offs + len), 1));
				return;
			}
			case CrocType_Table:
				return tableIdxImpl(t, dest, container.mTable, key);

			default: {
				if(tryMMDest(t, MM_Index, dest, container, key))
					return;

				pushTypeStringImpl(t, container);
				croc_eh_throwStd(*t, "TypeError", "Attempting to index a value of type '%s'", croc_getString(*t, -1));
			}
		}
	}

	void tableIdxImpl(Thread* t, AbsStack dest, Table* container, Value key)
	{
		if(auto v = container->get(key))
			t->stack[dest] = *v;
		else
			t->stack[dest] = Value::nullValue;
	}

	void idxaImpl(Thread* t, AbsStack container, Value key, Value value)
	{
		auto cont = t->stack[container];

		switch(cont.type)
		{
			case CrocType_Array: {
				if(key.type != CrocType_Int)
				{
					pushTypeStringImpl(t, key);
					croc_eh_throwStd(*t, "TypeError", "Attempting to index-assign an array with a '%s'",
						croc_getString(*t, -1));
				}

				auto index = key.mInt;
				auto arr = cont.mArray;

				if(index < 0)
					index += arr->length;

				if(index < 0 || index >= arr->length)
					croc_eh_throwStd(*t, "BoundsError", "Invalid array index %" CROC_INTEGER_FORMAT " (length is %u)", key.mInt, arr->length);

				arr->idxa(t->vm->mem, cast(uword)index, value);
				return;
			}
			case CrocType_Memblock: {
				if(key.type != CrocType_Int)
				{
					pushTypeStringImpl(t, key);
					croc_eh_throwStd(*t, "TypeError", "Attempting to index-assign a memblock with a '%s'",
						croc_getString(*t, -1));
				}

				auto index = key.mInt;
				auto mb = cont.mMemblock;

				if(index < 0)
					index += mb->data.length;

				if(index < 0 || index >= mb->data.length)
					croc_eh_throwStd(*t, "BoundsError", "Invalid memblock index %" CROC_INTEGER_FORMAT " (length is %u)",
						key.mInt, mb->data.length);

				if(value.type != CrocType_Int)
				{
					pushTypeStringImpl(t, value);
					croc_eh_throwStd(*t, "TypeError", "Attempting to index-assign a value of type '%s' into a memblock",
						croc_getString(*t, -1));
				}

				mb->data[cast(uword)index] = cast(uint8_t)value.mInt;
				return;
			}
			case CrocType_Table:
				return tableIdxaImpl(t, cont.mTable, key, value);

			default:
				if(tryMM(t, MM_IndexAssign, t->stack[container], key, value))
					return;

				pushTypeStringImpl(t, t->stack[container]);
				croc_eh_throwStd(*t, "TypeError", "Attempting to index-assign a value of type '%s'",
					croc_getString(*t, -1));
		}
	}

	void tableIdxaImpl(Thread* t, Table* container, Value key, Value value)
	{
		if(key.type == CrocType_Null)
			croc_eh_throwStd(*t, "TypeError", "Attempting to index-assign a table with a key of type 'null'");

		container->idxa(t->vm->mem, key, value);
	}

	namespace
	{
		bool commonSliceIndices(Thread* t, crocint& loIndex, crocint& hiIndex, Value lo, Value hi, CrocType type, uword len)
		{
			if(lo.type == CrocType_Null && hi.type == CrocType_Null)
				return false;

			if(!correctIndices(loIndex, hiIndex, lo, hi, len))
			{
				pushTypeStringImpl(t, lo);
				pushTypeStringImpl(t, hi);
				croc_eh_throwStd(*t, "TypeError", "Attempting to slice '%s' with indices of type '%s' and '%s'",
					typeToString(type), croc_getString(*t, -2), croc_getString(*t, -1));
			}

			if(!validIndices(loIndex, hiIndex, len))
				croc_eh_throwStd(*t, "BoundsError",
					"Invalid slice indices [%" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT "] (%s length = %u)",
					loIndex, hiIndex, typeToString(type), len);

			return true;
		}
	}

	void sliceImpl(Thread* t, AbsStack dest, Value src, Value lo, Value hi)
	{
		crocint loIndex, hiIndex;

		switch(src.type)
		{
			case CrocType_Array: {
				auto arr = src.mArray;

				if(commonSliceIndices(t, loIndex, hiIndex, lo, hi, CrocType_Array, arr->length))
					t->stack[dest] = Value::from(arr->slice(t->vm->mem, cast(uword)loIndex, cast(uword)hiIndex));
				else
					t->stack[dest] = src;
				return;
			}
			case CrocType_Memblock: {
				auto mb = src.mMemblock;

				if(commonSliceIndices(t, loIndex, hiIndex, lo, hi, CrocType_Memblock, mb->data.length))
					t->stack[dest] = Value::from(mb->slice(t->vm->mem, cast(uword)loIndex, cast(uword)hiIndex));
				else
					t->stack[dest] = src;
				return;
			}
			case CrocType_String: {
				auto str = src.mString;

				if(commonSliceIndices(t, loIndex, hiIndex, lo, hi, CrocType_String, str->cpLength))
					t->stack[dest] = Value::from(str->slice(t->vm, cast(uword)loIndex, cast(uword)hiIndex));
				else
					t->stack[dest] = src;
				return;
			}
			default:
				if(tryMMDest(t, MM_Slice, dest, src, lo, hi))
					return;

				pushTypeStringImpl(t, src);
				croc_eh_throwStd(*t, "TypeError", "Attempting to slice a value of type '%s'", croc_getString(*t, -1));
		}
	}

	void sliceaImpl(Thread* t, Value container, Value lo, Value hi, Value value)
	{
		switch(container.type)
		{
			case CrocType_Array: {
				auto arr = container.mArray;
				crocint loIndex, hiIndex;

				if(!correctIndices(loIndex, hiIndex, lo, hi, arr->length))
				{
					pushTypeStringImpl(t, lo);
					pushTypeStringImpl(t, hi);
					croc_eh_throwStd(*t, "TypeError",
						"Attempting to slice-assign an array with indices of type '%s' and '%s'",
						croc_getString(*t, -2), croc_getString(*t, -1));
				}

				if(!validIndices(loIndex, hiIndex, arr->length))
					croc_eh_throwStd(*t, "BoundsError",
						"Invalid slice-assign indices [%" CROC_INTEGER_FORMAT " .. %" CROC_INTEGER_FORMAT "] (array length = %u)",
						loIndex, hiIndex, arr->length);

				if(value.type == CrocType_Array)
				{
					if((hiIndex - loIndex) != value.mArray->length)
						croc_eh_throwStd(*t, "RangeError",
							"Array slice-assign lengths do not match (destination is % " CROC_INTEGER_FORMAT ", source is %u)",
							hiIndex - loIndex, value.mArray->length);

					return arr->sliceAssign(t->vm->mem, cast(uword)loIndex, cast(uword)hiIndex, value.mArray);
				}
				else
				{
					pushTypeStringImpl(t, value);
					croc_eh_throwStd(*t, "TypeError", "Attempting to slice-assign a value of type '%s' into an array",
						croc_getString(*t, -1));
				}
			}
			default:
				if(tryMM(t, MM_SliceAssign, container, lo, hi, value))
					return;

				pushTypeStringImpl(t, container);
				croc_eh_throwStd(*t, "TypeError", "Attempting to slice-assign a value of type '%s'",
					croc_getString(*t, -1));
		}
	}

	void fieldImpl(Thread* t, AbsStack dest, Value container, String* name, bool raw)
	{
		switch(container.type)
		{
			case CrocType_Table: {
				// This is right, tables do not distinguish between field access and indexing.
				tableIdxImpl(t, dest, container.mTable, Value::from(name));
				return;
			}
			case CrocType_Class: {
				auto c = container.mClass;
				auto v = c->getField(name);

				if(v == nullptr)
				{
					v = c->getMethod(name);

					if(v == nullptr)
						croc_eh_throwStd(*t, "FieldError",
							"Attempting to access nonexistent field '%s' from class '%s'",
							name->toCString(), c->name->toCString());
				}

				t->stack[dest] = v->value;
				return;
			}
			case CrocType_Instance: {
				auto i = container.mInstance;
				auto v = i->getField(name);

				if(v == nullptr)
				{
					v = i->getMethod(name);

					if(v == nullptr)
					{
						if(!raw && tryMMDest(t, MM_Field, dest, container, Value::from(name)))
							return;

						croc_eh_throwStd(*t, "FieldError",
							"Attempting to access nonexistent field '%s' from instance of class '%s'",
							name->toCString(), i->parent->name->toCString());
					}
				}

				t->stack[dest] = v->value;
				return;
			}
			case CrocType_Namespace: {
				auto v = container.mNamespace->get(name);

				if(v == nullptr)
				{
					toStringImpl(t, container, false);
					croc_eh_throwStd(*t, "FieldError", "Attempting to access nonexistent field '%s' from '%s'",
						name->toCString(), croc_getString(*t, -1));
				}

				t->stack[dest] = *v;
				return;
			}
			default:
				if(!raw && tryMMDest(t, MM_Field, dest, container, Value::from(name)))
					return;

				pushTypeStringImpl(t, container);
				croc_eh_throwStd(*t, "TypeError", "Attempting to access field '%s' from a value of type '%s'",
					name->toCString(), croc_getString(*t, -1));
		}
	}

	void fieldaImpl(Thread* t, AbsStack container, String* name, Value value, bool raw)
	{
		auto cont = t->stack[container];

		switch(cont.type)
		{
			case CrocType_Table:
				// This is right, tables do not distinguish between field access and indexing.
				tableIdxaImpl(t, cont.mTable, Value::from(name), value);
				return;

			case CrocType_Class: {
				auto c = cont.mClass;

				if(auto slot = c->getField(name))
					c->setMember(t->vm->mem, slot, value);
				else if(auto slot = c->getMethod(name))
				{
					if(c->isFrozen)
						croc_eh_throwStd(*t, "FieldError",
							"Attempting to change method '%s' in class '%s' after it has been frozen",
							name->toCString(), c->name->toCString());

					c->setMember(t->vm->mem, slot, value);
				}
				else
					croc_eh_throwStd(*t, "FieldError", "Attempting to assign to nonexistent field '%s' in class '%s'",
						name->toCString(), c->name->toCString());

				return;
			}
			case CrocType_Instance: {
				auto i = cont.mInstance;

				if(auto slot = i->getField(name))
					i->setField(t->vm->mem, slot, value);
				else if(!raw && tryMM(t, MM_FieldAssign, t->stack[container], Value::from(name), value))
					return;
				else
					croc_eh_throwStd(*t, "FieldError",
						"Attempting to assign to nonexistent field '%s' in instance of class '%s'",
						name->toCString(), i->parent->name->toCString());
				return;
			}
			case CrocType_Namespace: {
				cont.mNamespace->set(t->vm->mem, name, value);
				return;
			}
			default:
				if(!raw && tryMM(t, MM_FieldAssign, t->stack[container], Value::from(name), value))
					return;

				pushTypeStringImpl(t, t->stack[container]);
				croc_eh_throwStd(*t, "TypeError", "Attempting to assign field '%s' into a value of type '%s'",
					name->toCString(), croc_getString(*t, -1));
		}
	}

	void lenImpl(Thread* t, AbsStack dest, Value src)
	{
		switch(src.type)
		{
			case CrocType_String:    t->stack[dest] = Value::from(cast(crocint)src.mString->cpLength);      return;
			case CrocType_Table:     t->stack[dest] = Value::from(cast(crocint)src.mTable->length());       return;
			case CrocType_Array:     t->stack[dest] = Value::from(cast(crocint)src.mArray->length);         return;
			case CrocType_Memblock:  t->stack[dest] = Value::from(cast(crocint)src.mMemblock->data.length); return;
			case CrocType_Namespace: t->stack[dest] = Value::from(cast(crocint)src.mNamespace->length());   return;

			default:
				if(tryMMDest(t, MM_Length, dest, src))
					return;

				pushTypeStringImpl(t, src);
				croc_eh_throwStd(*t, "TypeError", "Can't get the length of a '%s'", croc_getString(*t, -1));
		}
	}

	void lenaImpl(Thread* t, Value dest, Value len)
	{
		switch(dest.type)
		{
			case CrocType_Array: {
				if(len.type != CrocType_Int)
				{
					pushTypeStringImpl(t, len);
					croc_eh_throwStd(*t, "TypeError",
						"Attempting to set the length of an array using a length of type '%s'", croc_getString(*t, -1));
				}

				auto l = len.mInt;

				if(l < 0) // || l > uword.max) TODO:range
					croc_eh_throwStd(*t, "RangeError", "Invalid length (%" CROC_INTEGER_FORMAT ")", l);

				dest.mArray->resize(t->vm->mem, cast(uword)l);
				return;
			}
			case CrocType_Memblock: {
				if(len.type != CrocType_Int)
				{
					pushTypeStringImpl(t, len);
					croc_eh_throwStd(*t, "TypeError",
						"Attempting to set the length of a memblock using a length of type '%s'",
						croc_getString(*t, -1));
				}

				auto mb = dest.mMemblock;

				if(!mb->ownData)
					croc_eh_throwStd(*t, "ValueError", "Attempting to resize a memblock which does not own its data");

				auto l = len.mInt;

				if(l < 0) // || l > uword.max) TODO:range
					croc_eh_throwStd(*t, "RangeError", "Invalid length (%" CROC_INTEGER_FORMAT ")", l);

				mb->resize(t->vm->mem, cast(uword)l);
				return;
			}
			default:
				if(tryMM(t, MM_LengthAssign, dest, len))
					return;

				pushTypeStringImpl(t, dest);
				croc_eh_throwStd(*t, "TypeError", "Can't set the length of a '%s'", croc_getString(*t, -1));
		}
	}

	void catImpl(Thread* t, AbsStack dest, AbsStack firstSlot, uword num)
	{
		auto slot = firstSlot;
		auto endSlot = slot + num;
		auto endSlotm1 = endSlot - 1;
		auto stack = t->stack;

		while(slot < endSlotm1)
		{
			Function* method = nullptr;
			bool swap = false;

			switch(stack[slot].type)
			{
				case CrocType_String: {
					uword len = 0;
					uword cpLen = 0;
					uword idx = slot;

					for(; idx < endSlot; idx++)
					{
						auto val = stack[idx];

						if(val.type != CrocType_String)
							break;

						len += val.mString->length;
						cpLen += val.mString->cpLength;
					}

					if(idx > (slot + 1))
					{
						stringConcat(t, stack[slot], stack.slice(slot + 1, idx), len, cpLen);
						slot = idx - 1;
					}

					if(slot == endSlotm1)
						break; // to exit function

					if(stack[slot + 1].type == CrocType_Array)
						goto _array;
					else if(stack[slot + 1].type == CrocType_Instance)
						goto _cat_r;
					else
					{
						pushTypeStringImpl(t, stack[slot + 1]);
						croc_eh_throwStd(*t, "TypeError", "Can't concatenate 'string' and '%s'",
							croc_getString(*t, -1));
					}
				}
				case CrocType_Array: {
				_array:
					uword idx = slot + 1;
					uword len = stack[slot].type == CrocType_Array ? stack[slot].mArray->length : 1;

					for(; idx < endSlot; idx++)
					{
						if(stack[idx].type == CrocType_Array)
							len += stack[idx].mArray->length;
						else if(stack[idx].type == CrocType_Instance)
						{
							method = getMM(t, stack[idx], MM_Cat_r);

							if(method == nullptr)
								len++;
							else
								break;
						}
						else
							len++;
					}

					if(idx > (slot + 1))
					{
						arrayConcat(t, stack.slice(slot, idx), len);
						slot = idx - 1;
					}

					if(slot == endSlotm1)
						break; // to exit function

					assert(method != nullptr);
					goto _cat_r;
				}
				case CrocType_Instance: {
					if(stack[slot + 1].type == CrocType_Array)
					{
						method = getMM(t, stack[slot], MM_Cat);

						if(method == nullptr)
							goto _array;
					}

					if(method == nullptr)
					{
						method = getMM(t, stack[slot], MM_Cat);

						if(method == nullptr)
							goto _cat_r;
					}

					goto _common_mm;
				}
				default:
					// Basic
					if(stack[slot + 1].type == CrocType_Array)
						goto _array;
					else
					{
						method = getMM(t, stack[slot], MM_Cat);

						if(method == nullptr)
							goto _cat_r;
						else
							goto _common_mm;
					}

				_cat_r:
					if(method == nullptr)
					{
						method = getMM(t, stack[slot + 1], MM_Cat_r);

						if(method == nullptr)
							goto _error;
					}

					swap = true;
					// fall through

				_common_mm: {
					assert(method != nullptr);

					auto src1save = stack[slot];
					auto src2save = stack[slot + 1];

					auto funcSlot = push(t, Value::from(method));

					if(swap)
					{
						push(t, src2save);
						push(t, src1save);
					}
					else
					{
						push(t, src1save);
						push(t, src2save);
					}

					commonCall(t, funcSlot + t->stackBase, 1, callPrologue(t, funcSlot + t->stackBase, 1, 2));

					// stack might have changed.
					stack = t->stack;

					slot++;
					stack[slot] = stack[t->stackIndex - 1];
					croc_popTop(*t);
					continue;
				}
				_error:
					pushTypeStringImpl(t, stack[slot]);
					pushTypeStringImpl(t, stack[slot + 1]);
					croc_eh_throwStd(*t, "TypeError", "Can't concatenate '%s' and '%s'",
						croc_getString(*t, -2), croc_getString(*t, -1));
			}

			break;
		}

		t->stack[dest] = stack[slot];
	}

	void arrayConcat(Thread* t, DArray<Value> vals, uword len)
	{
		if(vals.length == 2 && vals[0].type == CrocType_Array)
		{
			if(vals[1].type == CrocType_Array)
				vals[1] = Value::from(vals[0].mArray->cat(t->vm->mem, vals[1].mArray));
			else
				vals[1] = Value::from(vals[0].mArray->cat(t->vm->mem, vals[1]));

			return;
		}

		auto ret = Array::create(t->vm->mem, len);

		uword i = 0;

		for(auto &v: vals)
		{
			if(v.type == CrocType_Array)
			{
				auto a = v.mArray;
				ret->sliceAssign(t->vm->mem, i, i + a->length, a);
				i += a->length;
			}
			else
			{
				ret->idxa(t->vm->mem, i, v);
				i++;
			}
		}

		vals[vals.length - 1] = Value::from(ret);
	}

	void stringConcat(Thread* t, Value first, DArray<Value> vals, uword len, uword cpLen)
	{
		auto tmpBuffer = DArray<char>::alloc(t->vm->mem, len);
		uword i = 0;

		auto add = [&tmpBuffer, &i](Value& v)
		{
			auto s = v.mString->toDArray();
			tmpBuffer.slicea(i, i + s.length, DArray<char>::n(cast(char*)s.ptr, s.length));
			i += s.length;
		};

		add(first);

		for(auto &v: vals)
			add(v);

		vals[vals.length - 1] = Value::from(String::createUnverified(t->vm, tmpBuffer.toConst(), cpLen));
		tmpBuffer.free(t->vm->mem);
	}

	void catEqImpl(Thread* t, AbsStack dest, AbsStack firstSlot, uword num)
	{
		assert(num >= 1);

		auto endSlot = firstSlot + num;
		auto stack = t->stack;
		auto target = stack[dest];

		switch(target.type)
		{
			case CrocType_String: {
				uword len = target.mString->length;
				uword cpLen = target.mString->cpLength;

				for(uword idx = firstSlot; idx < endSlot; idx++)
				{
					if(stack[idx].type == CrocType_String)
					{
						auto s = stack[idx].mString;
						len += s->length;
						cpLen += s->cpLength;
					}
					else
					{
						pushTypeStringImpl(t, stack[idx]);
						croc_eh_throwStd(*t, "TypeError", "Can't append a '%s' to a 'string'", croc_getString(*t, -1));
					}
				}

				stringConcat(t, target, stack.slice(firstSlot, endSlot), len, cpLen);
				stack[dest] = stack[endSlot - 1];
				return;
			}
			case CrocType_Array: {
				arrayAppend(t, target.mArray, stack.slice(firstSlot, endSlot));
				return;
			}
			default:
				auto method = getMM(t, target, MM_CatEq);

				if(method == nullptr)
				{
					pushTypeStringImpl(t, target);
					croc_eh_throwStd(*t, "TypeError", "Can't append to a value of type '%s'", croc_getString(*t, -1));
				}

				checkStack(t, t->stackIndex);

				for(auto i = t->stackIndex; i > firstSlot; i--)
					stack[i] = stack[i - 1];

				stack[firstSlot] = target;

				t->nativeCallDepth++;

				if(funcCallPrologue(t, method, firstSlot, 0, firstSlot, num + 1))
				{
					t->currentAR->incdNativeDepth = true;
					execute(t);
				}

				t->nativeCallDepth--;
				return;
		}
	}

	void arrayAppend(Thread* t, Array* a, DArray<Value> vals)
	{
		uword len = a->length;

		for(auto &val: vals)
		{
			if(val.type == CrocType_Array)
				len += val.mArray->length;
			else
				len++;
		}

		uword i = a->length;
		a->resize(t->vm->mem, len);

		for(auto &v: vals)
		{
			if(v.type == CrocType_Array)
			{
				auto arr = v.mArray;
				a->sliceAssign(t->vm->mem, i, i + arr->length, arr);
				i += arr->length;
			}
			else
			{
				a->idxa(t->vm->mem, i, v);
				i++;
			}
		}
	}

	Value superOfImpl(Thread* t, Value v)
	{
		if(v.type == CrocType_Instance)
			return Value::from(v.mInstance->parent);
		else if(v.type == CrocType_Namespace)
		{
			if(auto p = v.mNamespace->parent)
				return Value::from(p);
			else
				return Value::nullValue;
		}
		else
		{
			pushTypeStringImpl(t, v);
			croc_eh_throwStd(*t, "TypeError",
				"Can only get super of classes, instances, and namespaces, not values of type '%s'",
				croc_getString(*t, -1));
		}

		assert(false);
	}
}