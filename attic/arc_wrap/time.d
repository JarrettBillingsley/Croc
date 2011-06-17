module arc_wrap.time;

import minid.api;
import minid.bind;

import arc.time;

void init(MDThread* t)
{
	WrapModule!
	(
		"arc.time",
		WrapFunc!(arc.time.open),
		WrapFunc!(arc.time.close),
		WrapFunc!(arc.time.process),
		WrapFunc!(arc.time.sleep),
		WrapFunc!(arc.time.elapsedMilliseconds),
		WrapFunc!(arc.time.elapsedSeconds),
		WrapFunc!(arc.time.fps),
		WrapFunc!(arc.time.limitFPS),
		WrapFunc!(arc.time.getTime)
	)(t);
}