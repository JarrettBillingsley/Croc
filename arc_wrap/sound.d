module arc_wrap.sound;

import minid.api;
import minid.bind;

import arc.sound;

void init(MDThread* t)
{
	WrapModule!
	(
		"arc.sound",
		WrapFunc!(arc.sound.open),
		WrapFunc!(arc.sound.close),
		WrapFunc!(arc.sound.process),
		WrapFunc!(arc.sound.on),
		WrapFunc!(arc.sound.off),
		WrapFunc!(arc.sound.isSoundOn),

		WrapType!
		(
			Sound,
			"Sound",
			WrapCtors!(void function(SoundFile)),

			WrapMethod!(Sound.getSound),
			WrapMethod!(Sound.setSound),
			WrapMethod!(Sound.setGain),
			WrapMethod!(Sound.getPitch),
			WrapMethod!(Sound.setPitch),
			WrapMethod!(Sound.getVolume),
			WrapMethod!(Sound.setVolume),
			WrapMethod!(Sound.getLooping),
			WrapMethod!(Sound.setLoop),
			WrapMethod!(Sound.getPaused),
			WrapMethod!(Sound.setPaused),
			WrapMethod!(Sound.play),
			WrapMethod!(Sound.pause),
			WrapMethod!(Sound.seek),
			WrapMethod!(Sound.tell),
			WrapMethod!(Sound.stop),
			WrapMethod!(Sound.updateBuffers),
			WrapMethod!(Sound.process)
		),

		WrapType!
		(
			SoundFile,
			"SoundFile",
			WrapCtors!(void function(char[])),

			WrapMethod!(SoundFile.getFrequency),
			WrapMethod!(SoundFile.getBuffers, "getBuffersList", uint[] function()),
			WrapMethod!(SoundFile.getBuffers, uint[] function(int, int)),
			WrapMethod!(SoundFile.getBuffersLength),
			WrapMethod!(SoundFile.getBuffersPerSecond),
			WrapMethod!(SoundFile.getLength),
			WrapMethod!(SoundFile.getSize),
			WrapMethod!(SoundFile.getSource),
			WrapMethod!(SoundFile.allocBuffers),
			WrapMethod!(SoundFile.freeBuffers),
			WrapMethod!(SoundFile.print)
		)
	)(t);
}