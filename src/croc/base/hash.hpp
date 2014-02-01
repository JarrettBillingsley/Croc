#ifndef CROC_BASE_HASH_HPP
#define CROC_BASE_HASH_HPP

#include "croc/base/darray.hpp"
#include "croc/base/memory.hpp"
#include "croc/base/sanity.hpp"
#include "croc/utils.hpp"

enum NodeFlags
{
	NodeFlags_Used =        (1 << 0),
	NodeFlags_KeyModified = (1 << 1),
	NodeFlags_ValModified = (1 << 2)
};

#define IS_USED(n) TEST_FLAG((n)->flags, NodeFlags_Used)
#define SET_USED(n) SET_FLAG((n)->flags, NodeFlags_Used)
#define CLEAR_USED(n) CLEAR_FLAG((n)->flags, NodeFlags_Used)

#define IS_KEY_MODIFIED(n) TEST_FLAG((n)->flags, NodeFlags_KeyModified)
#define SET_KEY_MODIFIED(n) SET_FLAG((n)->flags, NodeFlags_KeyModified)
#define CLEAR_KEY_MODIFIED(n) CLEAR_FLAG((n)->flags, NodeFlags_KeyModified)

#define IS_VAL_MODIFIED(n) TEST_FLAG((n)->flags, NodeFlags_ValModified)
#define SET_VAL_MODIFIED(n) SET_FLAG((n)->flags, NodeFlags_ValModified)
#define CLEAR_VAL_MODIFIED(n) CLEAR_FLAG((n)->flags, NodeFlags_ValModified)

#define IS_EITHER_MODIFIED(n) TEST_FLAG((n)->flags, (NodeFlags_KeyModified | NodeFlags_ValModified))

#define CLEAR_BOTH_MODIFIED(n) CLEAR_FLAG((n)->flags, (NodeFlags_KeyModified | NodeFlags_ValModified))

namespace croc
{
	typedef uint32_t hash_t;

	struct DefaultHasher
	{
		template<typename T> static inline hash_t toHash(const T* t)
		{
			return cast(hash_t)*t;
		}
	};

	struct MethodHasher
	{
		template<typename T> static inline hash_t toHash(const T* t)
		{
			return t->toHash();
		}
	};

	template<typename K, typename V>
	struct HashNode
	{
		K key;
		V value;
		size_t next; // index into mNodes, or mNodes.length for "null"
		uint32_t flags;

		inline void init(hash_t hash)                 { (void)hash; }
		inline bool equals(const K& key, hash_t hash) { (void)hash; return this->key == key; }
		inline void copyFrom(HashNode<K, V>* other)   { value = other->value; }
	};

	template<typename K, typename V>
	struct HashNodeWithHash : HashNode<K, V>
	{
		hash_t hash;

		inline void init(hash_t hash)                 { this->hash = hash; }
		inline bool equals(const K& key, hash_t hash) { return this->hash == hash && this->key == key; }
		inline void copyFrom(HashNode<K, V>* other)   { this->value = other->value; hash = other->hash; }
	};

	template<typename K, typename V, typename Hasher = DefaultHasher, typename Node = HashNode<K, V> >
	struct Hash
	{
		typedef Node NodeType;

	private:
		DArray<Node> mNodes;
		uint32_t mHashMask;
		Node* mColBucket;
		size_t mSize;

	public:
		void dupInto(Hash<K, V, Hasher, Node>& other)
		{
			other.mNodes.slicea(mNodes);
			other.mHashMask = mHashMask;
			other.mColBucket = other.mNodes.ptr + (mColBucket - mNodes.ptr);
			other.mSize = mSize;
		}

		void dupInto(Hash<K, V, Hasher, Node>& other, DArray<Node> otherNodes)
		{
			otherNodes.slicea(mNodes);
			other.mNodes = otherNodes;
			other.mHashMask = mHashMask;
			other.mColBucket = otherNodes.ptr + (mColBucket - mNodes.ptr);
			other.mSize = mSize;
		}

		void prealloc(Memory& mem, size_t size)
		{
			if(size <= mNodes.length)
				return;
			else
			{
				auto newSize = largerPow2(size);
				resizeArray(mem, newSize < 4 ? 4 : newSize);
			}
		}

		V* insert(Memory& mem, K key)
		{
			return &insertNode(mem, key).value;
		}

		Node* insertNode(Memory& mem, K key)
		{
			auto hash = Hasher::toHash(&key);

			{
				auto node = lookupNode(key, hash);

				if(node != nullptr)
					return node;
			}

			auto nodes = mNodes;
			auto colBucket = getColBucket();

			if(colBucket == nullptr)
			{
				rehash(mem);
				nodes = mNodes;
				colBucket = getColBucket();
				assert(colBucket != nullptr);
			}

			auto mainPosNodeIdx = hash & mHashMask;
			auto mainPosNode = &nodes[mainPosNodeIdx];

			if(IS_USED(mainPosNode))
			{
				auto otherNode = &mNodes[Hasher::toHash(&mainPosNode->key) & mHashMask];

				if(otherNode == mainPosNode)
				{
					// other node is the head of its list, defer to it.
					colBucket->next = mainPosNode->next;
					mainPosNode->next = colBucket - nodes.ptr;
					mainPosNode = colBucket;
				}
				else
				{
					// other node is in the middle of a list, push it out.
					while(otherNode->next != mainPosNodeIdx)
						otherNode = &nodes[otherNode->next];

					otherNode->next = colBucket - nodes.ptr;
					*colBucket = *mainPosNode;
					mainPosNode->next = nodes.length;
				}
			}
			else
				mainPosNode->next = nodes.length;

			mainPosNode->init(hash);
			mainPosNode->key = key;
			mainPosNode->flags = NodeFlags_Used; // do this to clear out any modified bits
			mSize++;
			return mainPosNode;
		}

		bool remove(K key)
		{
			auto hash = Hasher::toHash(&key);
			auto nodes = mNodes;
			auto n = &mNodes[hash & mHashMask];

			if(!IS_USED(n))
				return false;

			if(n->equals(key, hash))
			{
				// Removing head of list.
				if(n->next == nodes.length)
					// Only item in the list.
					markUnused(n);
				else
				{
					// Other items.  Have to move the next item into where the head used to be.
					auto next = &nodes[n->next];
					*n = *next;
					markUnused(next);
				}

				return true;
			}
			else
			{
				while(n->next != nodes.length && IS_USED(n->next))
				{
					auto next = &nodes[n->next];

					if(next->equals(key, hash))
					{
						// Removing from the middle or end of the list.
						markUnused(next);
						n->next = next->next;
						return true;
					}

					n = next;
				}

				// Nonexistent key.
				return false;
			}
		}

		V* lookup(K key)
		{
			auto ret = lookupNode(key, Hasher::toHash(&key));

			if(ret)
				return &ret->value;
			else
				return nullptr;
		}

		V* lookup(K key, hash_t hash)
		{
			auto ret = lookupNode(key, hash);

			if(ret)
				return &ret->value;
			else
				return nullptr;
		}

		inline Node* lookupNode(K key)
		{
			return lookupNode(key, Hasher::hash(key));
		}

		Node* lookupNode(K key, hash_t hash)
		{
			if(mNodes.length == 0)
				return nullptr;

			auto nodes = mNodes;

			for(auto n = &nodes[hash & mHashMask]; IS_USED(n); n = &nodes[n->next])
			{
				if(n->equals(key, hash))
					return n;

				if(n->next == nodes.length)
					break;
			}

			return nullptr;
		}

		struct RegularHashIterator
		{
		private:
			DArray<Node> mNodes;
			size_t mIdx;

			void next()
			{
				for(this->mIdx++; this->mIdx < mNodes.length; this->mIdx++)
				{
					if(IS_USED(&mNodes[this->mIdx]))
						return;
				}
			}

		public:
			RegularHashIterator(DArray<Node> nodes) : mNodes(nodes), mIdx(cast(size_t)-1) {}
			RegularHashIterator(const RegularHashIterator& other) : mNodes(other.mNodes), mIdx(other.mIdx) {}
			RegularHashIterator& operator++() { next(); return *this; }
			RegularHashIterator operator++(int) { RegularHashIterator tmp(*this); operator++(); return tmp; }
			bool operator==(const RegularHashIterator& rhs) { return mNodes.ptr == rhs.mNodes.ptr && mIdx == rhs.mIdx; }
			bool operator!=(const RegularHashIterator& rhs) { return !(*this == rhs); }
			Node* operator*() { return &mNodes[mIdx]; }
			void moveToEnd() { mIdx = mNodes.length; }
		};

		struct ModifiedHashIterator
		{
		private:
			DArray<Node> mNodes;
			size_t mIdx;

			void next()
			{
				for(this->mIdx++; this->mIdx < mNodes.length; this->mIdx++)
				{
					if(IS_EITHER_MODIFIED(&mNodes[this->mIdx]))
						return;
				}
			}

		public:
			ModifiedHashIterator(DArray<Node> nodes) : mNodes(nodes), mIdx(cast(size_t)-1) {}
			ModifiedHashIterator(const ModifiedHashIterator& other) : mNodes(other.mNodes), mIdx(other.mIdx) {}
			ModifiedHashIterator& operator++() { next(); return *this; }
			ModifiedHashIterator operator++(int) { ModifiedHashIterator tmp(*this); operator++(); return tmp; }
			bool operator==(const ModifiedHashIterator& rhs) { return mNodes.ptr == rhs.mNodes.ptr && mIdx == rhs.mIdx; }
			bool operator!=(const ModifiedHashIterator& rhs) { return !(*this == rhs); }
			Node* operator*() { return &mNodes[mIdx]; }
			void moveToEnd() { mIdx = mNodes.length; }
		};

		RegularHashIterator begin()
		{
			RegularHashIterator ret(mNodes);
			ret++;
			return ret;
		}

		RegularHashIterator end()
		{
			RegularHashIterator ret(mNodes);
			ret.moveToEnd();
			return ret;
		}

		struct ModifiedIteration
		{
		private:
			DArray<Node> mNodes;

		public:
			ModifiedIteration(DArray<Node> nodes) : mNodes(nodes) {}

			ModifiedHashIterator begin()
			{
				ModifiedHashIterator ret(mNodes);
				ret++;
				return ret;
			}

			ModifiedHashIterator end()
			{
				ModifiedHashIterator ret(mNodes);
				ret.moveToEnd();
				return ret;
			}
		};

		ModifiedIteration modifiedNodes()
		{
			return ModifiedIteration(mNodes);
		}

		bool next(size_t& idx, K*& key, V*& val)
		{
			auto nodes = mNodes;

			for(; idx < nodes.length; idx++)
			{
				if(IS_USED(&nodes[idx]))
				{
					key = &nodes[idx].key;
					val = &nodes[idx].value;
					idx++;
					return true;
				}
			}

			return false;
		}

		bool nextNode(size_t& idx, Node*& n)
		{
			auto nodes = mNodes;

			for(; idx < nodes.length; idx++)
			{
				if(IS_USED(&nodes[idx]))
				{
					n = &nodes[idx++];
					return true;
				}
			}

			return false;
		}

		bool nextModified(size_t& idx, Node*& n)
		{
			auto nodes = mNodes;

			for(; idx < nodes.length; idx++)
			{
				if((nodes[idx].flags & (NodeFlags_KeyModified | NodeFlags_ValModified)) != 0)
				{
					n = &nodes[idx++];
					return true;
				}
			}

			return false;
		}

		size_t length()
		{
			return mSize;
		}

		size_t capacity()
		{
			return mNodes.length;
		}

		size_t dataSize()
		{
			return mNodes.length * sizeof(Node);
		}

		void minimize(Memory& mem)
		{
			if(mSize == 0)
				clear(mem);
			else
			{
				auto newSize = largerPow2(mSize);
				resizeArray(mem, newSize < 4 ? 4 : newSize);
			}
		}

		void clear(Memory& mem)
		{
			mNodes.free(mem);
			mHashMask = 0;
			mColBucket = nullptr;
			mSize = 0;
		}

	private:
		void markUnused(Node* n)
		{
			assert(n >= mNodes.ptr && n < mNodes.ptr + mNodes.length);

			CLEAR_USED(n);

			if(n < mColBucket)
				mColBucket = n;

			mSize--;
		}

		void rehash(Memory& mem)
		{
			if(mNodes.length != 0)
				resizeArray(mem, mNodes.length * 2);
			else
				resizeArray(mem, 4);
		}

		void resizeArray(Memory& mem, size_t newSize)
		{
			auto oldNodes = mNodes;

			mNodes = DArray<Node>::alloc(mem, newSize);
			mHashMask = mNodes.length - 1;
			mColBucket = mNodes.ptr;
			mSize = 0;

			for(size_t i = 0; i < oldNodes.length; i++)
			{
				auto node = &oldNodes[i];

				if(IS_USED(node))
				{
					auto newNode = insertNode(mem, node->key);
					newNode->copyFrom(node);
					newNode->flags = node->flags; // the used bit won't matter
				}
			}

			oldNodes.free(mem);
		}

		Node* getColBucket()
		{
			for(auto end = mNodes.ptr + mNodes.length; mColBucket < end; mColBucket++)
				if(!IS_USED(mColBucket))
					return mColBucket;

			return nullptr;
		}
	};
}

#endif
