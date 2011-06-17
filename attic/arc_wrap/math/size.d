module arc_wrap.math.size;

import minid.api;
import minid.bind;

import arc.math.size;

void init(MDThread* t)
{
	WrapModule!
	(
		"arc.math.size",
		WrapType!
		(
			Size,
			"Size",
			WrapCtors!(void function(float, float)),

			WrapMethod!(Size.set),
			WrapMethod!(Size.toString, "toString"),
			WrapMethod!(Size.maxComponent),
			WrapMethod!(Size.minComponent),
			WrapMethod!(Size.opNeg),
			WrapMethod!(Size.scale),
			WrapMethod!(Size.abs),
			WrapMethod!(Size.absCopy),
			WrapMethod!(Size.clamp),
			WrapMethod!(Size.randomise, "randomize"),
			WrapMethod!(Size.getWidth),
			WrapMethod!(Size.getHeight),
			WrapMethod!(Size.setWidth),
			WrapMethod!(Size.setHeight),
			WrapMethod!(Size.addW),
			WrapMethod!(Size.addH)
		)
	)(t);
}