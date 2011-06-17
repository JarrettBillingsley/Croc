module arc_wrap.draw.shape;

import minid.api;
import minid.bind;

import arc.draw.shape;

void init(MDThread* t)
{
	WrapModule!
	(
		"arc.draw.shape",
		WrapFunc!(arc.draw.shape.drawPixel),
		WrapFunc!(arc.draw.shape.drawLine),
		WrapFunc!(arc.draw.shape.drawCircle),
		WrapFunc!(arc.draw.shape.drawRectangle),
		WrapFunc!(arc.draw.shape.drawPolygon)
	)(t);
}