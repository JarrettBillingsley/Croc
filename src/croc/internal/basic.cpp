
#include <functional>

#include "croc/api.h"
#include "croc/internal/basic.hpp"
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
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wformat"
				case CrocType_Int:       return PUSHFMT("%" CROC_INTEGER_FORMAT, v.mInt);
#pragma GCC diagnostic pop
				case CrocType_Float:     return PUSHFMT("%f", v.mFloat);
				case CrocType_String:    return push(t, v);
				case CrocType_Nativeobj:
				case CrocType_Weakref:   return PUSHFMT("%s 0x%p", typeToString(v.type), cast(void*)v.mGCObj);
				default: assert(false);
			}
		}

		if(!raw)
		{
			assert(false); // TODO:mm
			// if(auto method = getMM(t, &v, MM.ToString))
			// {
			// 	auto funcSlot = push(t, Value(method));
			// 	push(t, v);
			// 	commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 1));

			// 	if(t.stack[t.stackIndex - 1].type != CrocType_String)
			// 	{
			// 		typeString(t, &t.stack[t.stackIndex - 1]);
			// 		throwStdException(t, "TypeError", "toString was supposed to return a string, but returned a '{}'", getString(t, -1));
			// 	}

			// 	return stackSize(t) - 1;
			// }
		}

		// TODO:api the PUSHFMT calls in following should probably be changed to croc_pushFormat calls when that's implemented.
		switch(v.type)
		{
			case CrocType_Function: {
				auto f = v.mFunction;

				if(f->isNative)
				{
					return PUSHFMT("native %s %*s",
						typeToString(CrocType_Function),
						f->name->length, f->name->toCString());
				}
				else
				{
					auto sf = f->scriptFunc;
					return PUSHFMT("script %s %*s(%*s(%d:%d))",
						typeToString(CrocType_Function),
						f->name->length, f->name->toCString(),
						sf->locFile->length, sf->locFile->toCString(),
						sf->locLine, sf->locCol);
				}
			}
			case CrocType_Class: {
				return PUSHFMT("%s %*s (0x%p)",
					typeToString(CrocType_Class),
					v.mClass->name->length, v.mClass->name->toCString(),
					cast(void*)v.mClass);
			}
			case CrocType_Instance: {
				auto pname = v.mInstance->parent->name;
				return PUSHFMT("%s of %*s (0x%p)",
					typeToString(CrocType_Instance),
					pname->length, pname->toCString(),
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
				return PUSHFMT("%s %*s(%*s(%d:%d))",
					typeToString(CrocType_Funcdef),
					d->name->length, d->name->toCString(),
					d->locFile->length, d->locFile->toCString(),
					d->locLine, d->locCol);
			}
			default:
			_default: {
				return PUSHFMT("%s 0x%p", typeToString(v.type), cast(void*)v.mGCObj);
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
		char buffer[BUFFERLENGTH];

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

			// TODO:api the PUSHFMT calls in following should probably be changed to croc_pushFormat calls when that's implemented.
			case CrocType_Class: {
				auto n = v.mClass->name;
				return PUSHFMT("%s %*s", typeToString(CrocType_Class), n->length, n->toCString());
			}
			case CrocType_Instance: {
				auto n = v.mInstance->parent->name;
				return PUSHFMT("%s of %*s", typeToString(CrocType_Instance), n->length, n->toCString());
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
					assert(false); // TODO:ex
					// typeString(t, item);
					// throwStdException(t, "TypeError", "Can only use strings to look in strings, not '{}'", getString(t, -1));
				}

			case CrocType_Table:
				return container.mTable->contains(item);

			case CrocType_Array:
				return container.mArray->contains(item);

			case CrocType_Namespace:
				if(item.type != CrocType_String)
				{
					assert(false); // TODO:ex
					// typeString(t, item);
					// throwStdException(t, "TypeError", "Can only use strings to look in namespaces, not '{}'", getString(t, -1));
				}

				return container.mNamespace->contains(item.mString);

			default:
				(void)t;
				assert(false); // TODO:mm
				// auto method = getMM(t, container, MM.In);

				// if(method is null)
				// {
				// 	typeString(t, container);
				// 	throwStdException(t, "TypeError", "No implementation of {} for type '{}'", MetaNames[MM.In], getString(t, -1));
				// }

				// auto containersave = *container;
				// auto itemsave = *item;

				// auto funcSlot = push(t, Value(method));
				// push(t, containersave);
				// push(t, itemsave);
				// commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 2));

				// auto ret = !t.stack[t.stackIndex - 1].isFalse();
				// pop(t);
				// return ret;
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

		(void)t;
		assert(false); // TODO:mm
		// if(a.type == b.type || b.type != CrocType_Instance)
		// {
		// 	if(auto method = getMM(t, a, MM.Cmp))
		// 		return commonCompare(t, method, a, b);
		// 	else if(auto method = getMM(t, b, MM.Cmp))
		// 		return -commonCompare(t, method, b, a);
		// }
		// else
		// {
		// 	if(auto method = getMM(t, b, MM.Cmp))
		// 		return -commonCompare(t, method, b, a);
		// 	else if(auto method = getMM(t, a, MM.Cmp))
		// 		return commonCompare(t, method, a, b);
		// }

		// auto bsave = *b;
		// typeString(t, a);
		// typeString(t, &bsave);
		// throwStdException(t, "TypeError", "Can't compare types '{}' and '{}'", getString(t, -2), getString(t, -1));
		// assert(false);
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

		(void)t;
		assert(false); // TODO:mm
		// if(a.type == b.type || b.type != CrocType_Instance)
		// {
		// 	if(auto method = getMM(t, a, MM.Equals))
		// 		return commonEquals(t, method, a, b);
		// 	else if(auto method = getMM(t, b, MM.Equals))
		// 		return commonEquals(t, method, b, a);
		// }
		// else
		// {
		// 	if(auto method = getMM(t, b, MM.Equals))
		// 		return commonEquals(t, method, b, a);
		// 	else if(auto method = getMM(t, a, MM.Equals))
		// 		return commonEquals(t, method, a, b);
		// }

		// auto bsave = *b;
		// typeString(t, a);
		// typeString(t, &bsave);
		// throwStdException(t, "TypeError", "Can't compare types '{}' and '{}' for equality", getString(t, -2), getString(t, -1));
		// assert(false);
	}

	void idxImpl(Thread* t, AbsStack dest, Value container, Value key)
	{
		switch(container.type)
		{
			case CrocType_Array: {
				if(key.type != CrocType_Int)
				{
					assert(false); // TODO:ex
					// typeString(t, key);
					// throwStdException(t, "TypeError", "Attempting to index an array with a '{}'", getString(t, -1));
				}

				auto index = key.mInt;
				auto arr = container.mArray;

				if(index < 0)
					index += arr->length;

				if(index < 0 || index >= arr->length)
					assert(false); // TODO:ex
					// throwStdException(t, "BoundsError", "Invalid array index {} (length is {})", key.mInt, arr.length);

				t->stack[dest] = arr->toDArray()[cast(uword)index].value;
				return;
			}
			case CrocType_Memblock: {
				if(key.type != CrocType_Int)
				{
					assert(false); // TODO:ex
					// typeString(t, key);
					// throwStdException(t, "TypeError", "Attempting to index a memblock with a '{}'", getString(t, -1));
				}

				auto index = key.mInt;
				auto mb = container.mMemblock;

				if(index < 0)
					index += mb->data.length;

				if(index < 0 || index >= mb->data.length)
					assert(false); // TODO:ex
					// throwStdException(t, "BoundsError", "Invalid memblock index {} (length is {})", key.mInt, mb.data.length);

				t->stack[dest] = Value::from(cast(crocint)mb->data[cast(uword)index]);
				return;
			}
			case CrocType_String: {
				if(key.type != CrocType_Int)
				{
					assert(false); // TODO:ex
					// typeString(t, key);
					// throwStdException(t, "TypeError", "Attempting to index a string with a '{}'", getString(t, -1));
				}

				auto index = key.mInt;
				auto str = container.mString;

				if(index < 0)
					index += str->cpLength;

				if(index < 0 || index >= str->cpLength)
					assert(false); // TODO:ex
					// throwStdException(t, "BoundsError", "Invalid string index {} (length is {})", key.mInt, str.cpLength);

				auto s = str->toDArray();
				auto offs = utf8CPIdxToByte(s, cast(uword)index);
				auto len = utf8SequenceLength(s[offs]);
				t->stack[dest] = Value::from(String::createUnverified(t->vm, s.slice(offs, offs + len), 1));
				return;
			}
			case CrocType_Table:
				return tableIdxImpl(t, dest, container.mTable, key);

			default: {
				// TODO:mm
				// if(tryMM!(2, true)(t, MM.Index, &t->stack[dest], container, key))
				// 	return;

				// typeString(t, container);
				// throwStdException(t, "TypeError", "Attempting to index a value of type '{}'", getString(t, -1));
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
					assert(false); // TODO:ex
					// typeString(t, key);
					// throwStdException(t, "TypeError", "Attempting to index-assign an array with a '{}'", getString(t, -1));
				}

				auto index = key.mInt;
				auto arr = cont.mArray;

				if(index < 0)
					index += arr->length;

				if(index < 0 || index >= arr->length)
					assert(false); // TODO:ex
					// throwStdException(t, "BoundsError", "Invalid array index {} (length is {})", key.mInt, arr.length);

				arr->idxa(t->vm->mem, cast(uword)index, value);
				return;
			}
			case CrocType_Memblock: {
				if(key.type != CrocType_Int)
				{
					assert(false); // TODO:ex
					// typeString(t, key);
					// throwStdException(t, "TypeError", "Attempting to index-assign a memblock with a '{}'", getString(t, -1));
				}

				auto index = key.mInt;
				auto mb = cont.mMemblock;

				if(index < 0)
					index += mb->data.length;

				if(index < 0 || index >= mb->data.length)
					assert(false); // TODO:ex
					// throwStdException(t, "BoundsError", "Invalid memblock index {} (length is {})", key.mInt, mb.data.length);

				if(value.type != CrocType_Int)
				{
					assert(false); // TODO:ex
					// typeString(t, value);
					// throwStdException(t, "TypeError", "Attempting to index-assign a value of type '{}' into a memblock", getString(t, -1));
				}

				mb->data[cast(uword)index] = cast(uint8_t)value.mInt;
				return;
			}
			case CrocType_Table:
				return tableIdxaImpl(t, cont.mTable, key, value);

			default:
				assert(false); // TODO:mm
				// if(tryMM!(3, false)(t, MM.IndexAssign, &t->stack[container], key, value))
				// 	return;

				// typeString(t, &t->stack[container]);
				// throwStdException(t, "TypeError", "Attempting to index-assign a value of type '{}'", getString(t, -1));
		}
	}

	void tableIdxaImpl(Thread* t, Table* container, Value key, Value value)
	{
		if(key.type == CrocType_Null)
			assert(false); // TODO:ex
			// throwStdException(t, "TypeError", "Attempting to index-assign a table with a key of type 'null'");

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
				assert(false); // TODO:ex
				(void)t;
				(void)type;
				// typeString(t, lo);
				// typeString(t, hi);
				// throwStdException(t, "TypeError", "Attempting to slice '{}' with indices of type '{}' and '{}'", typeToString(type), getString(t, -2), getString(t, -1));
			}

			if(!validIndices(loIndex, hiIndex, len))
				assert(false); // TODO:ex
				// throwStdException(t, "BoundsError", "Invalid slice indices [{} .. {}] ({} length = {})", loIndex, hiIndex, typeToString(type), len);

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
				assert(false); // TODO:mm
				// if(tryMM!(3, true)(t, MM.Slice, &t.stack[dest], src, lo, hi))
				// 	return;

				// typeString(t, src);
				// throwStdException(t, "TypeError", "Attempting to slice a value of type '{}'", getString(t, -1));
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
					assert(false); // TODO:ex
					// typeString(t, lo);
					// typeString(t, hi);
					// throwStdException(t, "TypeError", "Attempting to slice-assign an array with indices of type '{}' and '{}'", getString(t, -2), getString(t, -1));
				}

				if(!validIndices(loIndex, hiIndex, arr->length))
					assert(false); // TODO:ex
					// throwStdException(t, "BoundsError", "Invalid slice-assign indices [{} .. {}] (array length = {})", loIndex, hiIndex, arr.length);

				if(value.type == CrocType_Array)
				{
					if((hiIndex - loIndex) != value.mArray->length)
						assert(false); // TODO:ex
						// throwStdException(t, "RangeError", "Array slice-assign lengths do not match (destination is {}, source is {})", hiIndex - loIndex, value.mArray.length);

					return arr->sliceAssign(t->vm->mem, cast(uword)loIndex, cast(uword)hiIndex, value.mArray);
				}
				else
				{
					assert(false); // TODO:ex
					// typeString(t, value);
					// throwStdException(t, "TypeError", "Attempting to slice-assign a value of type '{}' into an array", getString(t, -1));
				}
			}
			default:
				assert(false); // TODO:mm
				// if(tryMM!(4, false)(t, MM.SliceAssign, container, lo, hi, value))
				// 	return;

				// typeString(t, container);
				// throwStdException(t, "TypeError", "Attempting to slice-assign a value of type '{}'", getString(t, -1));
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
						assert(false); // TODO:ex
						// throwStdException(t, "FieldError", "Attempting to access nonexistent field '{}' from class '{}'", name.toString(), c.name.toString());
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
						assert(false); // TODO:mm
						// if(!raw && tryMM!(2, true)(t, MM.Field, &t.stack[dest], container, &Value(name)))
						// 	return;
						// TODO:ex
						// throwStdException(t, "FieldError", "Attempting to access nonexistent field '{}' from instance of class '{}'", name.toString(), i.parent.name.toString());
					}
				}

				t->stack[dest] = v->value;
				return;
			}
			case CrocType_Namespace: {
				auto v = container.mNamespace->get(name);

				if(v == nullptr)
				{
					assert(false); // TODO:ex
					// toStringImpl(t, *container, false);
					// throwStdException(t, "FieldError", "Attempting to access nonexistent field '{}' from '{}'", name.toString(), getString(t, -1));
				}

				t->stack[dest] = *v;
				return;
			}
			default:
				assert(false); // TODO:mm
				(void)raw;
				// if(!raw && tryMM!(2, true)(t, MM.Field, &t.stack[dest], container, &Value(name)))
				// 	return;

				// typeString(t, container);
				// throwStdException(t, "TypeError", "Attempting to access field '{}' from a value of type '{}'", name.toString(), getString(t, -1));
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
						assert(false); // TODO:ex
						// throwStdException(t, "FieldError", "Attempting to change method '{}' in class '{}' after it has been frozen", name.toString(), c.name.toString());

					c->setMember(t->vm->mem, slot, value);
				}
				else
					assert(false); // TODO:ex
					// throwStdException(t, "FieldError", "Attempting to assign to nonexistent field '{}' in class '{}'", name.toString(), c.name.toString());

				return;
			}
			case CrocType_Instance: {
				auto i = cont.mInstance;

				if(auto slot = i->getField(name))
					i->setField(t->vm->mem, slot, value);
				// TODO:mm
				// else if(!raw && tryMM!(3, false)(t, MM.FieldAssign, &t.stack[container], &Value(name), value))
				// 	return;
				else
					assert(false); // TODO:ex
					// throwStdException(t, "FieldError", "Attempting to assign to nonexistent field '{}' in instance of class '{}'", name.toString(), i.parent.name.toString());
				return;
			}
			case CrocType_Namespace: {
				cont.mNamespace->set(t->vm->mem, name, value);
				return;
			}
			default:
				assert(false); // TODO:mm
				(void)raw;
				// if(!raw && tryMM!(3, false)(t, MM.FieldAssign, &t.stack[container], &Value(name), value))
				// 	return;

				// typeString(t, &t.stack[container]);
				// throwStdException(t, "TypeError", "Attempting to assign field '{}' into a value of type '{}'", name.toString(), getString(t, -1));
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
				assert(false); // TODO:mm
				// if(tryMM!(1, true)(t, MM.Length, &t.stack[dest], src))
				// 	return;

				// typeString(t, src);
				// throwStdException(t, "TypeError", "Can't get the length of a '{}'", getString(t, -1));
		}
	}

	void lenaImpl(Thread* t, Value dest, Value len)
	{
		switch(dest.type)
		{
			case CrocType_Array: {
				if(len.type != CrocType_Int)
				{
					assert(false); // TODO:ex
					// typeString(t, len);
					// throwStdException(t, "TypeError", "Attempting to set the length of an array using a length of type '{}'", getString(t, -1));
				}

				auto l = len.mInt;

				if(l < 0) // || l > uword.max) TODO:range
					assert(false); // TODO:mm
					// throwStdException(t, "RangeError", "Invalid length ({})", l);

				dest.mArray->resize(t->vm->mem, cast(uword)l);
				return;
			}
			case CrocType_Memblock: {
				if(len.type != CrocType_Int)
				{
					assert(false); // TODO:ex
					// typeString(t, len);
					// throwStdException(t, "TypeError", "Attempting to set the length of a memblock using a length of type '{}'", getString(t, -1));
				}

				auto mb = dest.mMemblock;

				if(!mb->ownData)
					assert(false); // TODO:ex
					// throwStdException(t, "ValueError", "Attempting to resize a memblock which does not own its data");

				auto l = len.mInt;

				if(l < 0) // || l > uword.max) TODO:range
					assert(false); // TODO:ex
					// throwStdException(t, "RangeError", "Invalid length ({})", l);

				mb->resize(t->vm->mem, cast(uword)l);
				return;
			}
			default:
				assert(false); // TODO:mm
				// if(tryMM!(2, false)(t, MM.LengthAssign, &dest, len))
				// 	return;

				// typeString(t, &dest);
				// throwStdException(t, "TypeError", "Can't set the length of a '{}'", getString(t, -1));
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
						assert(false); // TODO:ex
						// typeString(t, &stack[slot + 1]);
						// throwStdException(t, "TypeError", "Can't concatenate 'string' and '{}'", getString(t, -1));
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
							// TODO: mm
							// method = getMM(t, &stack[idx], MM.Cat_r);

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
						// TODO:mm
						// method = getMM(t, &stack[slot], MM.Cat);

						if(method == nullptr)
							goto _array;
					}

					if(method == nullptr)
					{
						// TODO:mm
						// method = getMM(t, &stack[slot], MM.Cat);

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
						// TODO:mm
						// method = getMM(t, &stack[slot], MM.Cat);

						if(method == nullptr)
							goto _cat_r;
						else
							goto _common_mm;
					}

				_cat_r:
					if(method == nullptr)
					{
						// TODO:mm
						// method = getMM(t, &stack[slot + 1], MM.Cat_r);

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

					// TODO:api
					(void)funcSlot;
					// commonCall(t, funcSlot + t.stackBase, 1, callPrologue(t, funcSlot + t.stackBase, 1, 2));

					// stack might have changed.
					stack = t->stack;

					slot++;
					stack[slot] = stack[t->stackIndex - 1];
					croc_popTop(*t);
					continue;
				}
				_error:
					assert(false);// TODO:ex
					// typeString(t, &t.stack[slot]);
					// typeString(t, &stack[slot + 1]);
					// throwStdException(t, "TypeError", "Can't concatenate '{}' and '{}'", getString(t, -2), getString(t, -1));
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
						assert(false); // TODO:ex
						// typeString(t, &stack[idx]);
						// throwStdException(t, "TypeError", "Can't append a '{}' to a 'string'", getString(t, -1));
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
				assert(false); // TODO:mm
				// auto method = getMM(t, &target, MM.CatEq);

				// if(method == nullptr)
				// {
				// 	assert(false); // TODO:ex
				// 	// typeString(t, &target);
				// 	// throwStdException(t, "TypeError", "Can't append to a value of type '{}'", getString(t, -1));
				// }

				// checkStack(t, stackIndex);

				// for(auto i = stackIndex; i > firstSlot; i--)
				// 	stack[i] = stack[i - 1];

				// stack[firstSlot] = target;

				// t->nativeCallDepth++;
				// scope(exit) t->nativeCallDepth--;

				// if(callPrologue2(t, method, firstSlot, 0, firstSlot, num + 1))
				// 	execute(t);
				// return;
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
			assert(false); // TODO:ex
			(void)t;
			// typeString(t, v);
			// throwStdException(t, "TypeError", "Can only get super of classes, instances, and namespaces, not values of type '{}'", getString(t, -1));
		}

		// assert(false);
	}
}