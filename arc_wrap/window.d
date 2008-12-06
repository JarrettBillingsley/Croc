module arc_wrap.window;

import minid.api;
import minid.bind;

import arc.window;

void init(MDThread* t)
{
	WrapModule!
	(
		"arc.window",
		WrapFunc!(arc.window.open),
		WrapFunc!(arc.window.close),
		WrapFunc!(arc.window.getWidth),
		WrapFunc!(arc.window.getHeight),
		WrapFunc!(arc.window.getSize),
		WrapFunc!(arc.window.isFullScreen),
		WrapFunc!(arc.window.resize),
		WrapFunc!(arc.window.toggleFullScreen),
		WrapFunc!(arc.window.clear),
		WrapFunc!(arc.window.swap),
		WrapFunc!(arc.window.swapClear),
		WrapFunc!(arc.window.screenshot),

		WrapNamespace!
		(
			"coordinates",
			WrapFunc!(arc.window.coordinates.setSize),
			WrapFunc!(arc.window.coordinates.setOrigin),
			WrapFunc!(arc.window.coordinates.getSize),
			WrapFunc!(arc.window.coordinates.getOrigin),
			WrapFunc!(arc.window.coordinates.getWidth),
			WrapFunc!(arc.window.coordinates.getHeight)
		)
	)(t);
}