module arc_wrap.all;

import minid.api;

import arc_wrap.draw.color;
import arc_wrap.draw.image;
import arc_wrap.draw.shape;
import arc_wrap.font;
import arc_wrap.input;
import arc_wrap.math.collision;
import arc_wrap.math.point;
import arc_wrap.math.rect;
import arc_wrap.math.size;
import arc_wrap.sound;
import arc_wrap.texture;
import arc_wrap.time;
import arc_wrap.window;

struct ArcLib
{
static:
	public void init(MDThread* t)
	{
		arc_wrap.draw.color.init(t);
		arc_wrap.draw.image.init(t);
		arc_wrap.draw.shape.init(t);
		arc_wrap.font.init(t);
		arc_wrap.input.init(t);
		arc_wrap.math.collision.init(t);
		arc_wrap.math.point.init(t);
		arc_wrap.math.rect.init(t);
		arc_wrap.math.size.init(t);
		arc_wrap.sound.init(t);
		arc_wrap.texture.init(t);
		arc_wrap.time.init(t);
		arc_wrap.window.init(t);
	}
}