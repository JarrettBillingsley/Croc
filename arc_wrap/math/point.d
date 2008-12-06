module arc_wrap.math.point;

import minid.api;
import minid.bind;

import arc.math.point;

void init(MDThread* t)
{
	WrapModule!
	(
		"arc.math.point",

		WrapType!
		(
			Point,
			"Point",
			WrapCtors!
			(
				// only the (float, float) ctor actually exists.
				// we're abusing the binding lib to perform autoconversion of ints to floats for this ctor ;)
				void function(float, float),
				void function(float, int),
				void function(int, float),
				void function(int, int)
			),

			WrapMethod!(Point.set),
			WrapMethod!(Point.angle),
			WrapMethod!(Point.length),
			WrapMethod!(Point.toString, "toString"),
			WrapMethod!(Point.maxComponent),
			WrapMethod!(Point.minComponent),
			WrapMethod!(Point.opNeg),
			WrapMethod!(Point.cross),
			WrapMethod!(Point.dot),
			WrapMethod!(Point.scale),
			// apply
			WrapMethod!(Point.lengthSquared),
			WrapMethod!(Point.normalise, "normalize"),
			WrapMethod!(Point.normaliseCopy, "normalizeCopy"),
			WrapMethod!(Point.rotate),
			WrapMethod!(Point.rotateCopy),
			WrapMethod!(Point.abs),
			WrapMethod!(Point.absCopy),
			WrapMethod!(Point.clamp),
			WrapMethod!(Point.randomise, "randomize"),
			WrapMethod!(Point.distance),
			WrapMethod!(Point.distanceSquared),
			WrapMethod!(Point.getX),
			WrapMethod!(Point.getY),
			WrapMethod!(Point.setX),
			WrapMethod!(Point.setY),
			WrapMethod!(Point.addX),
			WrapMethod!(Point.addY),
			WrapMethod!(Point.above),
			WrapMethod!(Point.below),
			WrapMethod!(Point.left),
			WrapMethod!(Point.right)
		)
	)(t);
}
