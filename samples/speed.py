import sys
import time

oneMillion = 5000000

class Tester:
	def foo(self):
		return 1
		
	def beginTimer(self):
		self.t1 = time.time()
		
	def endTimer(self, s):
		mps = (oneMillion/1000000)/(time.time() - self.t1)
		print "Python %s := %0.2f" % (s, mps)

	def testReflIntMath(self):
		self.beginTimer()
		x = 0;
		y = 5;

		for i in xrange(oneMillion/8):
			x += y; x += y; x += y; x += y;
			x += y; x += y; x += y; x += y;

		self.endTimer("reflIntMath\t")

	def testReflFloatMath(self):
		self.beginTimer()
		x = 0.0;
		y = 5.0;

		for i in xrange(oneMillion/8):
			x += y; x += y; x += y; x += y;
			x += y; x += y; x += y; x += y;

		self.endTimer("reflFloatMath\t")

	def testIntMath(self):
		self.beginTimer()
		x = 0;
		y = 5;
		z = 10;

		for i in xrange(oneMillion/8):
			x = y + z; x = y + z; x = y + z; x = y + z;
			x = y + z; x = y + z; x = y + z; x = y + z;

		self.endTimer("intMath\t\t")

	def testFloatMath(self):
		self.beginTimer()
		x = 0.0;
		y = 5.0;
		z = 10.0;

		for i in xrange(oneMillion/8):
			x = y + z; x = y + z; x = y + z; x = y + z;
			x = y + z; x = y + z; x = y + z; x = y + z;

		self.endTimer("floatMath\t")

	def testSlot(self):
		self.beginTimer()
		self.x = 1
		for i in xrange(oneMillion/8):
			self.x; self.x; self.x; self.x; 
			self.x; self.x; self.x; self.x;
		self.endTimer("slotAccesses\t")

	def testSetSlot(self):
		self.beginTimer()
		self.x = 1
		for i in xrange(oneMillion/8):
			self.x = 1; self.x = 2; self.x = 3; self.x = 4; 
			self.x = 1; self.x = 2; self.x = 3; self.x = 4;
		self.endTimer("slotSets\t\t")

	def testBlock(self):
		self.beginTimer()
		for i in xrange(oneMillion/8):
			self.foo(); self.foo(); self.foo(); self.foo();
			self.foo(); self.foo(); self.foo(); self.foo()
		self.endTimer("blockActivations\t")

	def testInstantiations(self):
		self.beginTimer()
		for i in xrange(oneMillion/8):
			Tester(); Tester(); Tester(); Tester();
			Tester(); Tester(); Tester(); Tester();
		self.endTimer("instantiations\t")

	def testLocals(self):
		self.beginTimer()
		v = 1
		for i in xrange(oneMillion/8):
			v; v;  v; v;
			v; v;  v; v;	
		self.endTimer("localAccesses\t")

	def testSetLocals(self):
		self.beginTimer()
		v = 1
		for i in xrange(oneMillion/8):
			v = 1; v = 2; v = 3; v = 4;
			v = 1; v = 2; v = 3; v = 4;  
		self.endTimer("localSets\t")

	def test(self):
		print ""
		self.testReflIntMath()
		self.testReflFloatMath()
		print ""
		self.testIntMath()
		self.testFloatMath()
		print ""
		self.testLocals()
		self.testSetLocals()
		print ""
		self.testSlot()
		self.testSetSlot()
		print ""
		self.testBlock()
		self.testInstantiations()

		import sys
		print "Python version\t\t := \"%i.%i.%i %s %i\"" % sys.version_info
		print ""
		print "// values in millions per second"
		print ""


Tester().test()

