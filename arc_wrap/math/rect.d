module arc_wrap.math.rect;

import minid.api;
import minid.bind;

import arc.math.point;
import arc.math.rect;
import arc.math.size;

void init(MDThread* t)
{
	WrapModule!
	(
		"arc.math.rect",
		WrapType!
		(
			Rect,
			"Rect",
			WrapCtors!
			(
				void function(float, float, float, float),
				void function(Point, Size),
				void function(Size),
				void function(float, float)
			),

			WrapMethod!(Rect.getBottomRight),
			WrapMethod!(Rect.getTop),
			WrapMethod!(Rect.getLeft),
			WrapMethod!(Rect.getBottom),
			WrapMethod!(Rect.getRight),
			WrapMethod!(Rect.getPosition),
			WrapMethod!(Rect.getSize),
			WrapMethod!(Rect.move),
			WrapMethod!(Rect.contains),
			WrapMethod!(Rect.intersects)
		)
	)(t);
}