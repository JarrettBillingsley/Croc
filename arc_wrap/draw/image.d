module arc_wrap.draw.image;

import minid.api;
import minid.bind;

import arc.draw.image;

void init(MDThread* t)
{
 	WrapModule!
	(
		"arc.draw.image",
		WrapFunc!(arc.draw.image.drawImage),
		WrapFunc!(arc.draw.image.drawImageTopLeft),
		WrapFunc!(arc.draw.image.drawImageSubsection)
	)(t);
}