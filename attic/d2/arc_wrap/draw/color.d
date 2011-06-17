module arc_wrap.draw.color;

import minid.api;
import minid.bind;

import arc.draw.color;

void init(MDThread* t)
{
	WrapModule!
	(
		"arc.draw.color",

		WrapType!
		(
			Color,
			"Color",
			WrapCtors!
			(
				void function(int, int, int),
				void function(int, int, int, int),
				void function(float, float, float),
				void function(float, float, float, float)
			),

			WrapMethod!(Color.setR),
			WrapMethod!(Color.setG),
			WrapMethod!(Color.setB),
			WrapMethod!(Color.setA),
			WrapMethod!(Color.getR),
			WrapMethod!(Color.getG),
			WrapMethod!(Color.getB),
			WrapMethod!(Color.getA),
			WrapMethod!(Color.setGLColor)
		)
	)(t);
}