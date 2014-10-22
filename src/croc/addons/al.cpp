#ifndef CROC_OPENAL_ADDON

#include "croc/api.h"

namespace croc
{
void initOpenAlLib(CrocThread* t)
{
	croc_eh_throwStd(t, "ApiError", "Attempting to load the OpenAL library, but it was not compiled in");
}
}
#else

#include <type_traits>
#include <tuple>

#include "croc/addons/al.hpp"
#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{

#ifdef CROC_BUILTIN_DOCS
const char* moduleDocs = DModule("openal")
R"()";
#endif

// =====================================================================================================================
// OpenAL shared lib loading

const char* alSharedLibPaths[] =
{
#ifdef _WIN32
	"soft_oal.dll",
	"openal32.dll",
#elif defined(__APPLE__) && defined(__MACH__)
	"../Frameworks/OpenAL.framework/OpenAL",
	"/Library/Frameworks/OpenAL.framework/OpenAL",
	"/System/Library/Frameworks/OpenAL.framework/OpenAL",
#else
	"libopenal.so.1",
	"libopenal.so.0",
	"libopenal.so",
	"libal.so",
	"libAL.so",
#endif
	nullptr
};

void loadSharedLib(CrocThread* t)
{
	if(alEnable != nullptr)
		return;

	auto al = oscompat::openLibraryMulti(t, alSharedLibPaths);

	if(al == nullptr)
		croc_eh_throwStd(t, "OSException", "Cannot find the OpenAL shared library");

	oscompat::getProc(t, al, "alEnable", alEnable);
	oscompat::getProc(t, al, "alDisable", alDisable);
	oscompat::getProc(t, al, "alIsEnabled", alIsEnabled);
	oscompat::getProc(t, al, "alGetString", alGetString);
	oscompat::getProc(t, al, "alGetBooleanv", alGetBooleanv);
	oscompat::getProc(t, al, "alGetIntegerv", alGetIntegerv);
	oscompat::getProc(t, al, "alGetFloatv", alGetFloatv);
	oscompat::getProc(t, al, "alGetDoublev", alGetDoublev);
	oscompat::getProc(t, al, "alGetBoolean", alGetBoolean);
	oscompat::getProc(t, al, "alGetInteger", alGetInteger);
	oscompat::getProc(t, al, "alGetFloat", alGetFloat);
	oscompat::getProc(t, al, "alGetDouble", alGetDouble);
	oscompat::getProc(t, al, "alGetError", alGetError);
	oscompat::getProc(t, al, "alIsExtensionPresent", alIsExtensionPresent);
	oscompat::getProc(t, al, "alGetProcAddress", alGetProcAddress);
	oscompat::getProc(t, al, "alGetEnumValue", alGetEnumValue);
	oscompat::getProc(t, al, "alListenerf", alListenerf);
	oscompat::getProc(t, al, "alListener3f", alListener3f);
	oscompat::getProc(t, al, "alListenerfv", alListenerfv);
	oscompat::getProc(t, al, "alListeneri", alListeneri);
	oscompat::getProc(t, al, "alListener3i", alListener3i);
	oscompat::getProc(t, al, "alListeneriv", alListeneriv);
	oscompat::getProc(t, al, "alGetListenerf", alGetListenerf);
	oscompat::getProc(t, al, "alGetListener3f", alGetListener3f);
	oscompat::getProc(t, al, "alGetListenerfv", alGetListenerfv);
	oscompat::getProc(t, al, "alGetListeneri", alGetListeneri);
	oscompat::getProc(t, al, "alGetListener3i", alGetListener3i);
	oscompat::getProc(t, al, "alGetListeneriv", alGetListeneriv);
	oscompat::getProc(t, al, "alGenSources", alGenSources);
	oscompat::getProc(t, al, "alDeleteSources", alDeleteSources);
	oscompat::getProc(t, al, "alIsSource", alIsSource);
	oscompat::getProc(t, al, "alSourcef", alSourcef);
	oscompat::getProc(t, al, "alSource3f", alSource3f);
	oscompat::getProc(t, al, "alSourcefv", alSourcefv);
	oscompat::getProc(t, al, "alSourcei", alSourcei);
	oscompat::getProc(t, al, "alSource3i", alSource3i);
	oscompat::getProc(t, al, "alSourceiv", alSourceiv);
	oscompat::getProc(t, al, "alGetSourcef", alGetSourcef);
	oscompat::getProc(t, al, "alGetSource3f", alGetSource3f);
	oscompat::getProc(t, al, "alGetSourcefv", alGetSourcefv);
	oscompat::getProc(t, al, "alGetSourcei", alGetSourcei);
	oscompat::getProc(t, al, "alGetSource3i", alGetSource3i);
	oscompat::getProc(t, al, "alGetSourceiv", alGetSourceiv);
	oscompat::getProc(t, al, "alSourcePlayv", alSourcePlayv);
	oscompat::getProc(t, al, "alSourceStopv", alSourceStopv);
	oscompat::getProc(t, al, "alSourceRewindv", alSourceRewindv);
	oscompat::getProc(t, al, "alSourcePausev", alSourcePausev);
	oscompat::getProc(t, al, "alSourcePlay", alSourcePlay);
	oscompat::getProc(t, al, "alSourceStop", alSourceStop);
	oscompat::getProc(t, al, "alSourceRewind", alSourceRewind);
	oscompat::getProc(t, al, "alSourcePause", alSourcePause);
	oscompat::getProc(t, al, "alSourceQueueBuffers", alSourceQueueBuffers);
	oscompat::getProc(t, al, "alSourceUnqueueBuffers", alSourceUnqueueBuffers);
	oscompat::getProc(t, al, "alGenBuffers", alGenBuffers);
	oscompat::getProc(t, al, "alDeleteBuffers", alDeleteBuffers);
	oscompat::getProc(t, al, "alIsBuffer", alIsBuffer);
	oscompat::getProc(t, al, "alBufferData", alBufferData);
	oscompat::getProc(t, al, "alBufferf", alBufferf);
	oscompat::getProc(t, al, "alBuffer3f", alBuffer3f);
	oscompat::getProc(t, al, "alBufferfv", alBufferfv);
	oscompat::getProc(t, al, "alBufferi", alBufferi);
	oscompat::getProc(t, al, "alBuffer3i", alBuffer3i);
	oscompat::getProc(t, al, "alBufferiv", alBufferiv);
	oscompat::getProc(t, al, "alGetBufferf", alGetBufferf);
	oscompat::getProc(t, al, "alGetBuffer3f", alGetBuffer3f);
	oscompat::getProc(t, al, "alGetBufferfv", alGetBufferfv);
	oscompat::getProc(t, al, "alGetBufferi", alGetBufferi);
	oscompat::getProc(t, al, "alGetBuffer3i", alGetBuffer3i);
	oscompat::getProc(t, al, "alGetBufferiv", alGetBufferiv);
	oscompat::getProc(t, al, "alDopplerFactor", alDopplerFactor);
	oscompat::getProc(t, al, "alDopplerVelocity", alDopplerVelocity);
	oscompat::getProc(t, al, "alSpeedOfSound", alSpeedOfSound);
	oscompat::getProc(t, al, "alDistanceModel", alDistanceModel);
	oscompat::getProc(t, al, "alcCreateContext", alcCreateContext);
	oscompat::getProc(t, al, "alcMakeContextCurrent", alcMakeContextCurrent);
	oscompat::getProc(t, al, "alcProcessContext", alcProcessContext);
	oscompat::getProc(t, al, "alcGetCurrentContext", alcGetCurrentContext);
	oscompat::getProc(t, al, "alcGetContextsDevice", alcGetContextsDevice);
	oscompat::getProc(t, al, "alcSuspendContext", alcSuspendContext);
	oscompat::getProc(t, al, "alcDestroyContext", alcDestroyContext);
	oscompat::getProc(t, al, "alcOpenDevice", alcOpenDevice);
	oscompat::getProc(t, al, "alcCloseDevice", alcCloseDevice);
	oscompat::getProc(t, al, "alcGetError", alcGetError);
	oscompat::getProc(t, al, "alcIsExtensionPresent", alcIsExtensionPresent);
	oscompat::getProc(t, al, "alcGetProcAddress", alcGetProcAddress);
	oscompat::getProc(t, al, "alcGetEnumValue", alcGetEnumValue);
	oscompat::getProc(t, al, "alcGetString", alcGetString);
	oscompat::getProc(t, al, "alcGetIntegerv", alcGetIntegerv);
	oscompat::getProc(t, al, "alcCaptureOpenDevice", alcCaptureOpenDevice);
	oscompat::getProc(t, al, "alcCaptureCloseDevice", alcCaptureCloseDevice);
	oscompat::getProc(t, al, "alcCaptureStart", alcCaptureStart);
	oscompat::getProc(t, al, "alcCaptureStop", alcCaptureStop);
	oscompat::getProc(t, al, "alcCaptureSamples", alcCaptureSamples);
}

// =====================================================================================================================
// Helpers

const char* HandleMap = "openal.HandleMap";
const char* ALCdevice_handle = "ALCdevice_handle";
const char* ALCcontext_handle = "ALCcontext_handle";

ALCdevice* ALCdevice_getThis(CrocThread* t, word slot = 0)
{
	if(croc_isNull(t, slot))
		return nullptr;

	croc_hfield(t, slot, ALCdevice_handle);

	if(!croc_isNativeobj(t, -1))
		croc_eh_throwStd(t, "StateError", "Attempting to access a ALCdevice that has not been initialized");

	auto ret = croc_getNativeobj(t, -1);
	croc_popTop(t);
	return cast(ALCdevice*)ret;
}

void pushALCdeviceObj(CrocThread* t, ALCdevice* d)
{
	if(d == nullptr)
	{
		croc_pushNull(t);
		return;
	}

	croc_ex_pushRegistryVar(t, HandleMap);
	croc_pushNativeobj(t, d);
	croc_idx(t, -2);
	croc_insertAndPop(t, -2);

	if(croc_isNull(t, -1))
	{
		croc_popTop(t);
		croc_pushGlobal(t, "ALCdevice");
		croc_pushNull(t);
		croc_pushNativeobj(t, d);
		croc_call(t, -3, 1);
	}
}

ALCcontext* ALCcontext_getThis(CrocThread* t, word slot = 0)
{
	if(croc_isNull(t, slot))
		return nullptr;

	croc_hfield(t, slot, ALCcontext_handle);

	if(!croc_isNativeobj(t, -1))
		croc_eh_throwStd(t, "StateError", "Attempting to access a ALCcontext that has not been initialized");

	auto ret = croc_getNativeobj(t, -1);
	croc_popTop(t);
	return cast(ALCcontext*)ret;
}

void pushALCcontextObj(CrocThread* t, ALCcontext* c)
{
	if(c == nullptr)
	{
		croc_pushNull(t);
		return;
	}

	croc_ex_pushRegistryVar(t, HandleMap);
	croc_pushNativeobj(t, c);
	croc_idx(t, -2);
	croc_insertAndPop(t, -2);

	if(croc_isNull(t, -1))
	{
		croc_popTop(t);
		croc_pushGlobal(t, "ALCcontext");
		croc_pushNull(t);
		croc_pushNativeobj(t, c);
		croc_call(t, -3, 1);
	}
}

const StdlibRegisterInfo ALCdevice_constructor_info =
{
	Docstr(DFunc("constructor")
	R"()"),

	"constructor", 1
};

word_t ALCdevice_constructor(CrocThread* t)
{
	// Check for double-init
	croc_hfield(t, 0, ALCdevice_handle);
	if(!croc_isNull(t, -1))
		croc_eh_throwStd(t, "StateError", "Attempting to call constructor on already-initialized ALCdevice");
	croc_popTop(t);

	// Set handle
	croc_ex_checkParam(t, 1, CrocType_Nativeobj);
	croc_dup(t, 1);
	croc_hfielda(t, 0, ALCdevice_handle);

	// Insert this instance into the handle map
	croc_ex_pushRegistryVar(t, HandleMap);
	croc_dup(t, 1);
	croc_dup(t, 0);
	croc_idxa(t, -3);

	return 0;
}

const StdlibRegisterInfo ALCcontext_constructor_info =
{
	Docstr(DFunc("constructor")
	R"()"),

	"constructor", 1
};

word_t ALCcontext_constructor(CrocThread* t)
{
	// Check for double-init
	croc_hfield(t, 0, ALCcontext_handle);
	if(!croc_isNull(t, -1))
		croc_eh_throwStd(t, "StateError", "Attempting to call constructor on already-initialized ALCcontext");
	croc_popTop(t);

	// Set handle
	croc_ex_checkParam(t, 1, CrocType_Nativeobj);
	croc_dup(t, 1);
	croc_hfielda(t, 0, ALCcontext_handle);

	// Insert this instance into the handle map
	croc_ex_pushRegistryVar(t, HandleMap);
	croc_dup(t, 1);
	croc_dup(t, 0);
	croc_idxa(t, -3);

	return 0;
}

// =====================================================================================================================
// Wrapping

template<typename T, typename Enable = void>
struct ALTypeString
{};

template<typename T>
struct ALTypeString<T, typename std::enable_if<std::is_integral<T>::value && std::is_unsigned<T>::value>::type>
{
	static constexpr const char* value =
		(sizeof(T) == 1) ? "u8" :
		(sizeof(T) == 2) ? "u16" :
		(sizeof(T) == 4) ? "u32" :
		"u64";
};

template<typename T>
struct ALTypeString<T, typename std::enable_if<std::is_integral<T>::value && std::is_signed<T>::value>::type>
{
	static constexpr const char* value =
		(sizeof(T) == 1) ? "i8" :
		(sizeof(T) == 2) ? "i16" :
		(sizeof(T) == 4) ? "i32" :
		"i64";
};

template<typename T>
struct ALTypeString<T, typename std::enable_if<std::is_floating_point<T>::value>::type>
{
	static constexpr const char* value =
		(sizeof(T) == 4) ? "f32" :
		"f64";
};

#define ALICONST(c) croc_pushInt(t, c); croc_newGlobal(t, #c);
#define ALFCONST(c) croc_pushFloat(t, c); croc_newGlobal(t, #c);
#define ALBCONST(c) croc_pushBool(t, c); croc_newGlobal(t, #c);
#define ALSCONST(c) croc_pushString(t, c); croc_newGlobal(t, #c);

void registerConstants(CrocThread* t)
{
	croc_pushString(t, ALTypeString<ALenum>::value);     croc_newGlobal(t, "ALenum");
	croc_pushString(t, ALTypeString<ALboolean>::value);  croc_newGlobal(t, "ALboolean");
	croc_pushString(t, ALTypeString<ALbyte>::value);     croc_newGlobal(t, "ALbyte");
	croc_pushString(t, ALTypeString<ALshort>::value);    croc_newGlobal(t, "ALshort");
	croc_pushString(t, ALTypeString<ALint>::value);      croc_newGlobal(t, "ALint");
	croc_pushString(t, ALTypeString<ALsizei>::value);    croc_newGlobal(t, "ALsizei");
	croc_pushString(t, ALTypeString<ALubyte>::value);    croc_newGlobal(t, "ALubyte");
	croc_pushString(t, ALTypeString<ALushort>::value);   croc_newGlobal(t, "ALushort");
	croc_pushString(t, ALTypeString<ALuint>::value);     croc_newGlobal(t, "ALuint");
	croc_pushString(t, ALTypeString<ALfloat>::value);    croc_newGlobal(t, "ALfloat");
	croc_pushString(t, ALTypeString<ALdouble>::value);   croc_newGlobal(t, "ALdouble");

	croc_pushInt(t, sizeof(ALenum));     croc_newGlobal(t, "sizeofALenum");
	croc_pushInt(t, sizeof(ALboolean));  croc_newGlobal(t, "sizeofALboolean");
	croc_pushInt(t, sizeof(ALbyte));     croc_newGlobal(t, "sizeofALbyte");
	croc_pushInt(t, sizeof(ALshort));    croc_newGlobal(t, "sizeofALshort");
	croc_pushInt(t, sizeof(ALint));      croc_newGlobal(t, "sizeofALint");
	croc_pushInt(t, sizeof(ALsizei));    croc_newGlobal(t, "sizeofALsizei");
	croc_pushInt(t, sizeof(ALubyte));    croc_newGlobal(t, "sizeofALubyte");
	croc_pushInt(t, sizeof(ALushort));   croc_newGlobal(t, "sizeofALushort");
	croc_pushInt(t, sizeof(ALuint));     croc_newGlobal(t, "sizeofALuint");
	croc_pushInt(t, sizeof(ALfloat));    croc_newGlobal(t, "sizeofALfloat");
	croc_pushInt(t, sizeof(ALdouble));   croc_newGlobal(t, "sizeofALdouble");

	croc_pushString(t, ALTypeString<ALCenum>::value);     croc_newGlobal(t, "ALCenum");
	croc_pushString(t, ALTypeString<ALCboolean>::value);  croc_newGlobal(t, "ALCboolean");
	croc_pushString(t, ALTypeString<ALCbyte>::value);     croc_newGlobal(t, "ALCbyte");
	croc_pushString(t, ALTypeString<ALCshort>::value);    croc_newGlobal(t, "ALCshort");
	croc_pushString(t, ALTypeString<ALCint>::value);      croc_newGlobal(t, "ALCint");
	croc_pushString(t, ALTypeString<ALCsizei>::value);    croc_newGlobal(t, "ALCsizei");
	croc_pushString(t, ALTypeString<ALCubyte>::value);    croc_newGlobal(t, "ALCubyte");
	croc_pushString(t, ALTypeString<ALCushort>::value);   croc_newGlobal(t, "ALCushort");
	croc_pushString(t, ALTypeString<ALCuint>::value);     croc_newGlobal(t, "ALCuint");
	croc_pushString(t, ALTypeString<ALCfloat>::value);    croc_newGlobal(t, "ALCfloat");
	croc_pushString(t, ALTypeString<ALCdouble>::value);   croc_newGlobal(t, "ALCdouble");

	croc_pushInt(t, sizeof(ALCenum));     croc_newGlobal(t, "sizeofALCenum");
	croc_pushInt(t, sizeof(ALCboolean));  croc_newGlobal(t, "sizeofALCboolean");
	croc_pushInt(t, sizeof(ALCbyte));     croc_newGlobal(t, "sizeofALCbyte");
	croc_pushInt(t, sizeof(ALCshort));    croc_newGlobal(t, "sizeofALCshort");
	croc_pushInt(t, sizeof(ALCint));      croc_newGlobal(t, "sizeofALCint");
	croc_pushInt(t, sizeof(ALCsizei));    croc_newGlobal(t, "sizeofALCsizei");
	croc_pushInt(t, sizeof(ALCubyte));    croc_newGlobal(t, "sizeofALCubyte");
	croc_pushInt(t, sizeof(ALCushort));   croc_newGlobal(t, "sizeofALCushort");
	croc_pushInt(t, sizeof(ALCuint));     croc_newGlobal(t, "sizeofALCuint");
	croc_pushInt(t, sizeof(ALCfloat));    croc_newGlobal(t, "sizeofALCfloat");
	croc_pushInt(t, sizeof(ALCdouble));   croc_newGlobal(t, "sizeofALCdouble");

	croc_pushBool(t, AL_TRUE);  croc_newGlobal(t, "AL_TRUE");
	croc_pushBool(t, AL_FALSE); croc_newGlobal(t, "AL_FALSE");

	ALICONST(AL_NONE);                                         ALICONST(AL_SOURCE_RELATIVE);
	ALICONST(AL_CONE_INNER_ANGLE);                             ALICONST(AL_CONE_OUTER_ANGLE);
	ALICONST(AL_PITCH);                                        ALICONST(AL_POSITION);
	ALICONST(AL_DIRECTION);                                    ALICONST(AL_VELOCITY);
	ALICONST(AL_LOOPING);                                      ALICONST(AL_BUFFER);
	ALICONST(AL_GAIN);                                         ALICONST(AL_MIN_GAIN);
	ALICONST(AL_MAX_GAIN);                                     ALICONST(AL_ORIENTATION);
	ALICONST(AL_SOURCE_STATE);                                 ALICONST(AL_INITIAL);
	ALICONST(AL_PLAYING);                                      ALICONST(AL_PAUSED);
	ALICONST(AL_STOPPED);                                      ALICONST(AL_BUFFERS_QUEUED);
	ALICONST(AL_BUFFERS_PROCESSED);                            ALICONST(AL_REFERENCE_DISTANCE);
	ALICONST(AL_ROLLOFF_FACTOR);                               ALICONST(AL_CONE_OUTER_GAIN);
	ALICONST(AL_MAX_DISTANCE);                                 ALICONST(AL_SEC_OFFSET);
	ALICONST(AL_SAMPLE_OFFSET);                                ALICONST(AL_BYTE_OFFSET);
	ALICONST(AL_SOURCE_TYPE);                                  ALICONST(AL_STATIC);
	ALICONST(AL_STREAMING);                                    ALICONST(AL_UNDETERMINED);
	ALICONST(AL_FORMAT_MONO8);                                 ALICONST(AL_FORMAT_MONO16);
	ALICONST(AL_FORMAT_STEREO8);                               ALICONST(AL_FORMAT_STEREO16);
	ALICONST(AL_FREQUENCY);                                    ALICONST(AL_BITS);
	ALICONST(AL_CHANNELS);                                     ALICONST(AL_SIZE);
	ALICONST(AL_UNUSED);                                       ALICONST(AL_PENDING);
	ALICONST(AL_PROCESSED);                                    ALICONST(AL_NO_ERROR);
	ALICONST(AL_INVALID_NAME);                                 ALICONST(AL_INVALID_ENUM);
	ALICONST(AL_INVALID_VALUE);                                ALICONST(AL_INVALID_OPERATION);
	ALICONST(AL_OUT_OF_MEMORY);                                ALICONST(AL_VENDOR);
	ALICONST(AL_VERSION);                                      ALICONST(AL_RENDERER);
	ALICONST(AL_EXTENSIONS);                                   ALICONST(AL_DOPPLER_FACTOR);
	ALICONST(AL_DOPPLER_VELOCITY);                             ALICONST(AL_SPEED_OF_SOUND);
	ALICONST(AL_DISTANCE_MODEL);                               ALICONST(AL_INVERSE_DISTANCE);
	ALICONST(AL_INVERSE_DISTANCE_CLAMPED);                     ALICONST(AL_LINEAR_DISTANCE);
	ALICONST(AL_LINEAR_DISTANCE_CLAMPED);                      ALICONST(AL_EXPONENT_DISTANCE);
	ALICONST(AL_EXPONENT_DISTANCE_CLAMPED);                    ALICONST(AL_METERS_PER_UNIT);
	ALICONST(AL_DIRECT_FILTER);                                ALICONST(AL_AUXILIARY_SEND_FILTER);
	ALICONST(AL_AIR_ABSORPTION_FACTOR);                        ALICONST(AL_ROOM_ROLLOFF_FACTOR);
	ALICONST(AL_CONE_OUTER_GAINHF);                            ALICONST(AL_DIRECT_FILTER_GAINHF_AUTO);
	ALICONST(AL_AUXILIARY_SEND_FILTER_GAIN_AUTO);              ALICONST(AL_AUXILIARY_SEND_FILTER_GAINHF_AUTO);
	ALICONST(AL_REVERB_DENSITY);                               ALICONST(AL_REVERB_DIFFUSION);
	ALICONST(AL_REVERB_GAIN);                                  ALICONST(AL_REVERB_GAINHF);
	ALICONST(AL_REVERB_DECAY_TIME);                            ALICONST(AL_REVERB_DECAY_HFRATIO);
	ALICONST(AL_REVERB_REFLECTIONS_GAIN);                      ALICONST(AL_REVERB_REFLECTIONS_DELAY);
	ALICONST(AL_REVERB_LATE_REVERB_GAIN);                      ALICONST(AL_REVERB_LATE_REVERB_DELAY);
	ALICONST(AL_REVERB_AIR_ABSORPTION_GAINHF);                 ALICONST(AL_REVERB_ROOM_ROLLOFF_FACTOR);
	ALICONST(AL_REVERB_DECAY_HFLIMIT);                         ALICONST(AL_EAXREVERB_DENSITY);
	ALICONST(AL_EAXREVERB_DIFFUSION);                          ALICONST(AL_EAXREVERB_GAIN);
	ALICONST(AL_EAXREVERB_GAINHF);                             ALICONST(AL_EAXREVERB_GAINLF);
	ALICONST(AL_EAXREVERB_DECAY_TIME);                         ALICONST(AL_EAXREVERB_DECAY_HFRATIO);
	ALICONST(AL_EAXREVERB_DECAY_LFRATIO);                      ALICONST(AL_EAXREVERB_REFLECTIONS_GAIN);
	ALICONST(AL_EAXREVERB_REFLECTIONS_DELAY);                  ALICONST(AL_EAXREVERB_REFLECTIONS_PAN);
	ALICONST(AL_EAXREVERB_LATE_REVERB_GAIN);                   ALICONST(AL_EAXREVERB_LATE_REVERB_DELAY);
	ALICONST(AL_EAXREVERB_LATE_REVERB_PAN);                    ALICONST(AL_EAXREVERB_ECHO_TIME);
	ALICONST(AL_EAXREVERB_ECHO_DEPTH);                         ALICONST(AL_EAXREVERB_MODULATION_TIME);
	ALICONST(AL_EAXREVERB_MODULATION_DEPTH);                   ALICONST(AL_EAXREVERB_AIR_ABSORPTION_GAINHF);
	ALICONST(AL_EAXREVERB_HFREFERENCE);                        ALICONST(AL_EAXREVERB_LFREFERENCE);
	ALICONST(AL_EAXREVERB_ROOM_ROLLOFF_FACTOR);                ALICONST(AL_EAXREVERB_DECAY_HFLIMIT);
	ALICONST(AL_CHORUS_WAVEFORM);                              ALICONST(AL_CHORUS_PHASE);
	ALICONST(AL_CHORUS_RATE);                                  ALICONST(AL_CHORUS_DEPTH);
	ALICONST(AL_CHORUS_FEEDBACK);                              ALICONST(AL_CHORUS_DELAY);
	ALICONST(AL_DISTORTION_EDGE);                              ALICONST(AL_DISTORTION_GAIN);
	ALICONST(AL_DISTORTION_LOWPASS_CUTOFF);                    ALICONST(AL_DISTORTION_EQCENTER);
	ALICONST(AL_DISTORTION_EQBANDWIDTH);                       ALICONST(AL_ECHO_DELAY);
	ALICONST(AL_ECHO_LRDELAY);                                 ALICONST(AL_ECHO_DAMPING);
	ALICONST(AL_ECHO_FEEDBACK);                                ALICONST(AL_ECHO_SPREAD);
	ALICONST(AL_FLANGER_WAVEFORM);                             ALICONST(AL_FLANGER_PHASE);
	ALICONST(AL_FLANGER_RATE);                                 ALICONST(AL_FLANGER_DEPTH);
	ALICONST(AL_FLANGER_FEEDBACK);                             ALICONST(AL_FLANGER_DELAY);
	ALICONST(AL_FREQUENCY_SHIFTER_FREQUENCY);                  ALICONST(AL_FREQUENCY_SHIFTER_LEFT_DIRECTION);
	ALICONST(AL_FREQUENCY_SHIFTER_RIGHT_DIRECTION);            ALICONST(AL_VOCAL_MORPHER_PHONEMEA);
	ALICONST(AL_VOCAL_MORPHER_PHONEMEA_COARSE_TUNING);         ALICONST(AL_VOCAL_MORPHER_PHONEMEB);
	ALICONST(AL_VOCAL_MORPHER_PHONEMEB_COARSE_TUNING);         ALICONST(AL_VOCAL_MORPHER_WAVEFORM);
	ALICONST(AL_VOCAL_MORPHER_RATE);                           ALICONST(AL_PITCH_SHIFTER_COARSE_TUNE);
	ALICONST(AL_PITCH_SHIFTER_FINE_TUNE);                      ALICONST(AL_RING_MODULATOR_FREQUENCY);
	ALICONST(AL_RING_MODULATOR_HIGHPASS_CUTOFF);               ALICONST(AL_RING_MODULATOR_WAVEFORM);
	ALICONST(AL_AUTOWAH_ATTACK_TIME);                          ALICONST(AL_AUTOWAH_RELEASE_TIME);
	ALICONST(AL_AUTOWAH_RESONANCE);                            ALICONST(AL_AUTOWAH_PEAK_GAIN);
	ALICONST(AL_COMPRESSOR_ONOFF);                             ALICONST(AL_EQUALIZER_LOW_GAIN);
	ALICONST(AL_EQUALIZER_LOW_CUTOFF);                         ALICONST(AL_EQUALIZER_MID1_GAIN);
	ALICONST(AL_EQUALIZER_MID1_CENTER);                        ALICONST(AL_EQUALIZER_MID1_WIDTH);
	ALICONST(AL_EQUALIZER_MID2_GAIN);                          ALICONST(AL_EQUALIZER_MID2_CENTER);
	ALICONST(AL_EQUALIZER_MID2_WIDTH);                         ALICONST(AL_EQUALIZER_HIGH_GAIN);
	ALICONST(AL_EQUALIZER_HIGH_CUTOFF);                        ALICONST(AL_EFFECT_FIRST_PARAMETER);
	ALICONST(AL_EFFECT_LAST_PARAMETER);                        ALICONST(AL_EFFECT_TYPE);
	ALICONST(AL_EFFECT_NULL);                                  ALICONST(AL_EFFECT_REVERB);
	ALICONST(AL_EFFECT_CHORUS);                                ALICONST(AL_EFFECT_DISTORTION);
	ALICONST(AL_EFFECT_ECHO);                                  ALICONST(AL_EFFECT_FLANGER);
	ALICONST(AL_EFFECT_FREQUENCY_SHIFTER);                     ALICONST(AL_EFFECT_VOCAL_MORPHER);
	ALICONST(AL_EFFECT_PITCH_SHIFTER);                         ALICONST(AL_EFFECT_RING_MODULATOR);
	ALICONST(AL_EFFECT_AUTOWAH);                               ALICONST(AL_EFFECT_COMPRESSOR);
	ALICONST(AL_EFFECT_EQUALIZER);                             ALICONST(AL_EFFECT_EAXREVERB);
	ALICONST(AL_EFFECTSLOT_EFFECT);                            ALICONST(AL_EFFECTSLOT_GAIN);
	ALICONST(AL_EFFECTSLOT_AUXILIARY_SEND_AUTO);               ALICONST(AL_EFFECTSLOT_NULL);
	ALICONST(AL_LOWPASS_GAIN);                                 ALICONST(AL_LOWPASS_GAINHF);
	ALICONST(AL_HIGHPASS_GAIN);                                ALICONST(AL_HIGHPASS_GAINLF);
	ALICONST(AL_BANDPASS_GAIN);                                ALICONST(AL_BANDPASS_GAINLF);
	ALICONST(AL_BANDPASS_GAINHF);                              ALICONST(AL_FILTER_FIRST_PARAMETER);
	ALICONST(AL_FILTER_LAST_PARAMETER);                        ALICONST(AL_FILTER_TYPE);
	ALICONST(AL_FILTER_NULL);                                  ALICONST(AL_FILTER_LOWPASS);
	ALICONST(AL_FILTER_HIGHPASS);                              ALICONST(AL_FILTER_BANDPASS);
	ALICONST(AL_CHORUS_WAVEFORM_SINUSOID);                     ALICONST(AL_CHORUS_WAVEFORM_TRIANGLE);
	ALICONST(AL_CHORUS_MIN_WAVEFORM);                          ALICONST(AL_CHORUS_MAX_WAVEFORM);
	ALICONST(AL_CHORUS_DEFAULT_WAVEFORM);                      ALICONST(AL_CHORUS_MIN_PHASE);
	ALICONST(AL_CHORUS_MAX_PHASE);                             ALICONST(AL_CHORUS_DEFAULT_PHASE);
	ALICONST(AL_FLANGER_WAVEFORM_SINUSOID);                    ALICONST(AL_FLANGER_WAVEFORM_TRIANGLE);
	ALICONST(AL_FLANGER_MIN_WAVEFORM);                         ALICONST(AL_FLANGER_MAX_WAVEFORM);
	ALICONST(AL_FLANGER_DEFAULT_WAVEFORM);                     ALICONST(AL_FLANGER_MIN_PHASE);
	ALICONST(AL_FLANGER_MAX_PHASE);                            ALICONST(AL_FLANGER_DEFAULT_PHASE);
	ALICONST(AL_FREQUENCY_SHIFTER_MIN_LEFT_DIRECTION);         ALICONST(AL_FREQUENCY_SHIFTER_MAX_LEFT_DIRECTION);
	ALICONST(AL_FREQUENCY_SHIFTER_DEFAULT_LEFT_DIRECTION);     ALICONST(AL_FREQUENCY_SHIFTER_DIRECTION_DOWN);
	ALICONST(AL_FREQUENCY_SHIFTER_DIRECTION_UP);               ALICONST(AL_FREQUENCY_SHIFTER_DIRECTION_OFF);
	ALICONST(AL_FREQUENCY_SHIFTER_MIN_RIGHT_DIRECTION);        ALICONST(AL_FREQUENCY_SHIFTER_MAX_RIGHT_DIRECTION);
	ALICONST(AL_FREQUENCY_SHIFTER_DEFAULT_RIGHT_DIRECTION);    ALICONST(AL_VOCAL_MORPHER_MIN_PHONEMEA);
	ALICONST(AL_VOCAL_MORPHER_MAX_PHONEMEA);                   ALICONST(AL_VOCAL_MORPHER_DEFAULT_PHONEMEA);
	ALICONST(AL_VOCAL_MORPHER_MIN_PHONEMEA_COARSE_TUNING);     ALICONST(AL_VOCAL_MORPHER_MAX_PHONEMEA_COARSE_TUNING);
	ALICONST(AL_VOCAL_MORPHER_DEFAULT_PHONEMEA_COARSE_TUNING); ALICONST(AL_VOCAL_MORPHER_MIN_PHONEMEB);
	ALICONST(AL_VOCAL_MORPHER_MAX_PHONEMEB);                   ALICONST(AL_VOCAL_MORPHER_DEFAULT_PHONEMEB);
	ALICONST(AL_VOCAL_MORPHER_MIN_PHONEMEB_COARSE_TUNING);     ALICONST(AL_VOCAL_MORPHER_MAX_PHONEMEB_COARSE_TUNING);
	ALICONST(AL_VOCAL_MORPHER_DEFAULT_PHONEMEB_COARSE_TUNING); ALICONST(AL_VOCAL_MORPHER_PHONEME_A);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_E);                      ALICONST(AL_VOCAL_MORPHER_PHONEME_I);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_O);                      ALICONST(AL_VOCAL_MORPHER_PHONEME_U);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_AA);                     ALICONST(AL_VOCAL_MORPHER_PHONEME_AE);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_AH);                     ALICONST(AL_VOCAL_MORPHER_PHONEME_AO);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_EH);                     ALICONST(AL_VOCAL_MORPHER_PHONEME_ER);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_IH);                     ALICONST(AL_VOCAL_MORPHER_PHONEME_IY);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_UH);                     ALICONST(AL_VOCAL_MORPHER_PHONEME_UW);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_B);                      ALICONST(AL_VOCAL_MORPHER_PHONEME_D);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_F);                      ALICONST(AL_VOCAL_MORPHER_PHONEME_G);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_J);                      ALICONST(AL_VOCAL_MORPHER_PHONEME_K);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_L);                      ALICONST(AL_VOCAL_MORPHER_PHONEME_M);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_N);                      ALICONST(AL_VOCAL_MORPHER_PHONEME_P);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_R);                      ALICONST(AL_VOCAL_MORPHER_PHONEME_S);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_T);                      ALICONST(AL_VOCAL_MORPHER_PHONEME_V);
	ALICONST(AL_VOCAL_MORPHER_PHONEME_Z);                      ALICONST(AL_VOCAL_MORPHER_WAVEFORM_SINUSOID);
	ALICONST(AL_VOCAL_MORPHER_WAVEFORM_TRIANGLE);              ALICONST(AL_VOCAL_MORPHER_WAVEFORM_SAWTOOTH);
	ALICONST(AL_VOCAL_MORPHER_MIN_WAVEFORM);                   ALICONST(AL_VOCAL_MORPHER_MAX_WAVEFORM);
	ALICONST(AL_VOCAL_MORPHER_DEFAULT_WAVEFORM);               ALICONST(AL_PITCH_SHIFTER_MIN_COARSE_TUNE);
	ALICONST(AL_PITCH_SHIFTER_MAX_COARSE_TUNE);                ALICONST(AL_PITCH_SHIFTER_DEFAULT_COARSE_TUNE);
	ALICONST(AL_PITCH_SHIFTER_MIN_FINE_TUNE);                  ALICONST(AL_PITCH_SHIFTER_MAX_FINE_TUNE);
	ALICONST(AL_PITCH_SHIFTER_DEFAULT_FINE_TUNE);              ALICONST(AL_RING_MODULATOR_SINUSOID);
	ALICONST(AL_RING_MODULATOR_SAWTOOTH);                      ALICONST(AL_RING_MODULATOR_SQUARE);
	ALICONST(AL_RING_MODULATOR_MIN_WAVEFORM);                  ALICONST(AL_RING_MODULATOR_MAX_WAVEFORM);
	ALICONST(AL_RING_MODULATOR_DEFAULT_WAVEFORM);              ALICONST(AL_COMPRESSOR_MIN_ONOFF);
	ALICONST(AL_COMPRESSOR_MAX_ONOFF);                         ALICONST(AL_COMPRESSOR_DEFAULT_ONOFF);
	ALICONST(AL_FORMAT_IMA_ADPCM_MONO16_EXT);                  ALICONST(AL_FORMAT_IMA_ADPCM_STEREO16_EXT);
	ALICONST(AL_FORMAT_WAVE_EXT);                              ALICONST(AL_FORMAT_VORBIS_EXT);
	ALICONST(AL_FORMAT_QUAD8_LOKI);                            ALICONST(AL_FORMAT_QUAD16_LOKI);
	ALICONST(AL_FORMAT_MONO_FLOAT32);                          ALICONST(AL_FORMAT_STEREO_FLOAT32);
	ALICONST(AL_FORMAT_MONO_DOUBLE_EXT);                       ALICONST(AL_FORMAT_STEREO_DOUBLE_EXT);
	ALICONST(AL_FORMAT_MONO_MULAW_EXT);                        ALICONST(AL_FORMAT_STEREO_MULAW_EXT);
	ALICONST(AL_FORMAT_MONO_ALAW_EXT);                         ALICONST(AL_FORMAT_STEREO_ALAW_EXT);
	ALICONST(ALC_CHAN_MAIN_LOKI);                              ALICONST(ALC_CHAN_PCM_LOKI);
	ALICONST(ALC_CHAN_CD_LOKI);                                ALICONST(AL_FORMAT_QUAD8);
	ALICONST(AL_FORMAT_QUAD16);                                ALICONST(AL_FORMAT_QUAD32);
	ALICONST(AL_FORMAT_REAR8);                                 ALICONST(AL_FORMAT_REAR16);
	ALICONST(AL_FORMAT_REAR32);                                ALICONST(AL_FORMAT_51CHN8);
	ALICONST(AL_FORMAT_51CHN16);                               ALICONST(AL_FORMAT_51CHN32);
	ALICONST(AL_FORMAT_61CHN8);                                ALICONST(AL_FORMAT_61CHN16);
	ALICONST(AL_FORMAT_61CHN32);                               ALICONST(AL_FORMAT_71CHN8);
	ALICONST(AL_FORMAT_71CHN16);                               ALICONST(AL_FORMAT_71CHN32);
	ALICONST(AL_FORMAT_MONO_MULAW);                            ALICONST(AL_FORMAT_STEREO_MULAW);
	ALICONST(AL_FORMAT_QUAD_MULAW);                            ALICONST(AL_FORMAT_REAR_MULAW);
	ALICONST(AL_FORMAT_51CHN_MULAW);                           ALICONST(AL_FORMAT_61CHN_MULAW);
	ALICONST(AL_FORMAT_71CHN_MULAW);                           ALICONST(AL_FORMAT_MONO_IMA4);
	ALICONST(AL_FORMAT_STEREO_IMA4);                           ALICONST(ALC_CONNECTED);
	ALICONST(AL_SOURCE_DISTANCE_MODEL);                        ALICONST(AL_BYTE_RW_OFFSETS_SOFT);
	ALICONST(AL_SAMPLE_RW_OFFSETS_SOFT);                       ALICONST(AL_LOOP_POINTS_SOFT);
	ALICONST(AL_FOLDBACK_EVENT_BLOCK);                         ALICONST(AL_FOLDBACK_EVENT_START);
	ALICONST(AL_FOLDBACK_EVENT_STOP);                          ALICONST(AL_FOLDBACK_MODE_MONO);
	ALICONST(AL_FOLDBACK_MODE_STEREO);                         ALICONST(AL_DEDICATED_GAIN);
	ALICONST(AL_EFFECT_DEDICATED_DIALOGUE);                    ALICONST(AL_EFFECT_DEDICATED_LOW_FREQUENCY_EFFECT);
	ALICONST(AL_MONO_SOFT);                                    ALICONST(AL_STEREO_SOFT);
	ALICONST(AL_REAR_SOFT);                                    ALICONST(AL_QUAD_SOFT);
	ALICONST(AL_5POINT1_SOFT);                                 ALICONST(AL_6POINT1_SOFT);
	ALICONST(AL_7POINT1_SOFT);                                 ALICONST(AL_BYTE_SOFT);
	ALICONST(AL_UNSIGNED_BYTE_SOFT);                           ALICONST(AL_SHORT_SOFT);
	ALICONST(AL_UNSIGNED_SHORT_SOFT);                          ALICONST(AL_INT_SOFT);
	ALICONST(AL_UNSIGNED_INT_SOFT);                            ALICONST(AL_FLOAT_SOFT);
	ALICONST(AL_DOUBLE_SOFT);                                  ALICONST(AL_BYTE3_SOFT);
	ALICONST(AL_UNSIGNED_BYTE3_SOFT);                          ALICONST(AL_MONO8_SOFT);
	ALICONST(AL_MONO16_SOFT);                                  ALICONST(AL_MONO32F_SOFT);
	ALICONST(AL_STEREO8_SOFT);                                 ALICONST(AL_STEREO16_SOFT);
	ALICONST(AL_STEREO32F_SOFT);                               ALICONST(AL_QUAD8_SOFT);
	ALICONST(AL_QUAD16_SOFT);                                  ALICONST(AL_QUAD32F_SOFT);
	ALICONST(AL_REAR8_SOFT);                                   ALICONST(AL_REAR16_SOFT);
	ALICONST(AL_REAR32F_SOFT);                                 ALICONST(AL_5POINT1_8_SOFT);
	ALICONST(AL_5POINT1_16_SOFT);                              ALICONST(AL_5POINT1_32F_SOFT);
	ALICONST(AL_6POINT1_8_SOFT);                               ALICONST(AL_6POINT1_16_SOFT);
	ALICONST(AL_6POINT1_32F_SOFT);                             ALICONST(AL_7POINT1_8_SOFT);
	ALICONST(AL_7POINT1_16_SOFT);                              ALICONST(AL_7POINT1_32F_SOFT);
	ALICONST(AL_INTERNAL_FORMAT_SOFT);                         ALICONST(AL_BYTE_LENGTH_SOFT);
	ALICONST(AL_SAMPLE_LENGTH_SOFT);                           ALICONST(AL_SEC_LENGTH_SOFT);
	ALICONST(AL_DIRECT_CHANNELS_SOFT);                         ALICONST(ALC_FORMAT_CHANNELS_SOFT);
	ALICONST(ALC_FORMAT_TYPE_SOFT);                            ALICONST(ALC_BYTE_SOFT);
	ALICONST(ALC_UNSIGNED_BYTE_SOFT);                          ALICONST(ALC_SHORT_SOFT);
	ALICONST(ALC_UNSIGNED_SHORT_SOFT);                         ALICONST(ALC_INT_SOFT);
	ALICONST(ALC_UNSIGNED_INT_SOFT);                           ALICONST(ALC_FLOAT_SOFT);
	ALICONST(ALC_MONO_SOFT);                                   ALICONST(ALC_STEREO_SOFT);
	ALICONST(ALC_QUAD_SOFT);                                   ALICONST(ALC_5POINT1_SOFT);
	ALICONST(ALC_6POINT1_SOFT);                                ALICONST(ALC_7POINT1_SOFT);
	ALICONST(AL_STEREO_ANGLES);                                ALICONST(AL_SOURCE_RADIUS);
	ALICONST(AL_SAMPLE_OFFSET_LATENCY_SOFT);                   ALICONST(AL_SEC_OFFSET_LATENCY_SOFT);
	ALICONST(ALC_DEFAULT_FILTER_ORDER);                        ALICONST(AL_DEFERRED_UPDATES_SOFT);
	ALICONST(AL_UNPACK_BLOCK_ALIGNMENT_SOFT);                  ALICONST(AL_PACK_BLOCK_ALIGNMENT_SOFT);
	ALICONST(AL_FORMAT_MONO_MSADPCM_SOFT);                     ALICONST(AL_FORMAT_STEREO_MSADPCM_SOFT);
	ALICONST(ALC_FALSE);                                       ALICONST(ALC_TRUE);
	ALICONST(ALC_FREQUENCY);                                   ALICONST(ALC_REFRESH);
	ALICONST(ALC_SYNC);                                        ALICONST(ALC_MONO_SOURCES);
	ALICONST(ALC_STEREO_SOURCES);                              ALICONST(ALC_NO_ERROR);
	ALICONST(ALC_INVALID_DEVICE);                              ALICONST(ALC_INVALID_CONTEXT);
	ALICONST(ALC_INVALID_ENUM);                                ALICONST(ALC_INVALID_VALUE);
	ALICONST(ALC_OUT_OF_MEMORY);                               ALICONST(ALC_MAJOR_VERSION);
	ALICONST(ALC_MINOR_VERSION);                               ALICONST(ALC_ATTRIBUTES_SIZE);
	ALICONST(ALC_ALL_ATTRIBUTES);                              ALICONST(ALC_DEFAULT_DEVICE_SPECIFIER);
	ALICONST(ALC_DEVICE_SPECIFIER);                            ALICONST(ALC_EXTENSIONS);
	ALICONST(ALC_CAPTURE_DEVICE_SPECIFIER);                    ALICONST(ALC_CAPTURE_DEFAULT_DEVICE_SPECIFIER);
	ALICONST(ALC_CAPTURE_SAMPLES);                             ALICONST(ALC_DEFAULT_ALL_DEVICES_SPECIFIER);
	ALICONST(ALC_ALL_DEVICES_SPECIFIER);                       ALICONST(ALC_EFX_MAJOR_VERSION);
	ALICONST(ALC_EFX_MINOR_VERSION);                           ALICONST(ALC_MAX_AUXILIARY_SENDS);

	ALFCONST(AL_LOWPASS_MIN_GAIN);                             ALFCONST(AL_LOWPASS_MAX_GAIN);
	ALFCONST(AL_LOWPASS_DEFAULT_GAIN);                         ALFCONST(AL_LOWPASS_MIN_GAINHF);
	ALFCONST(AL_LOWPASS_MAX_GAINHF);                           ALFCONST(AL_LOWPASS_DEFAULT_GAINHF);
	ALFCONST(AL_HIGHPASS_MIN_GAIN);                            ALFCONST(AL_HIGHPASS_MAX_GAIN);
	ALFCONST(AL_HIGHPASS_DEFAULT_GAIN);                        ALFCONST(AL_HIGHPASS_MIN_GAINLF);
	ALFCONST(AL_HIGHPASS_MAX_GAINLF);                          ALFCONST(AL_HIGHPASS_DEFAULT_GAINLF);
	ALFCONST(AL_BANDPASS_MIN_GAIN);                            ALFCONST(AL_BANDPASS_MAX_GAIN);
	ALFCONST(AL_BANDPASS_DEFAULT_GAIN);                        ALFCONST(AL_BANDPASS_MIN_GAINHF);
	ALFCONST(AL_BANDPASS_MAX_GAINHF);                          ALFCONST(AL_BANDPASS_DEFAULT_GAINHF);
	ALFCONST(AL_BANDPASS_MIN_GAINLF);                          ALFCONST(AL_BANDPASS_MAX_GAINLF);
	ALFCONST(AL_BANDPASS_DEFAULT_GAINLF);                      ALFCONST(AL_REVERB_MIN_DENSITY);
	ALFCONST(AL_REVERB_MAX_DENSITY);                           ALFCONST(AL_REVERB_DEFAULT_DENSITY);
	ALFCONST(AL_REVERB_MIN_DIFFUSION);                         ALFCONST(AL_REVERB_MAX_DIFFUSION);
	ALFCONST(AL_REVERB_DEFAULT_DIFFUSION);                     ALFCONST(AL_REVERB_MIN_GAIN);
	ALFCONST(AL_REVERB_MAX_GAIN);                              ALFCONST(AL_REVERB_DEFAULT_GAIN);
	ALFCONST(AL_REVERB_MIN_GAINHF);                            ALFCONST(AL_REVERB_MAX_GAINHF);
	ALFCONST(AL_REVERB_DEFAULT_GAINHF);                        ALFCONST(AL_REVERB_MIN_DECAY_TIME);
	ALFCONST(AL_REVERB_MAX_DECAY_TIME);                        ALFCONST(AL_REVERB_DEFAULT_DECAY_TIME);
	ALFCONST(AL_REVERB_MIN_DECAY_HFRATIO);                     ALFCONST(AL_REVERB_MAX_DECAY_HFRATIO);
	ALFCONST(AL_REVERB_DEFAULT_DECAY_HFRATIO);                 ALFCONST(AL_REVERB_MIN_REFLECTIONS_GAIN);
	ALFCONST(AL_REVERB_MAX_REFLECTIONS_GAIN);                  ALFCONST(AL_REVERB_DEFAULT_REFLECTIONS_GAIN);
	ALFCONST(AL_REVERB_MIN_REFLECTIONS_DELAY);                 ALFCONST(AL_REVERB_MAX_REFLECTIONS_DELAY);
	ALFCONST(AL_REVERB_DEFAULT_REFLECTIONS_DELAY);             ALFCONST(AL_REVERB_MIN_LATE_REVERB_GAIN);
	ALFCONST(AL_REVERB_MAX_LATE_REVERB_GAIN);                  ALFCONST(AL_REVERB_DEFAULT_LATE_REVERB_GAIN);
	ALFCONST(AL_REVERB_MIN_LATE_REVERB_DELAY);                 ALFCONST(AL_REVERB_MAX_LATE_REVERB_DELAY);
	ALFCONST(AL_REVERB_DEFAULT_LATE_REVERB_DELAY);             ALFCONST(AL_REVERB_MIN_AIR_ABSORPTION_GAINHF);
	ALFCONST(AL_REVERB_MAX_AIR_ABSORPTION_GAINHF);             ALFCONST(AL_REVERB_DEFAULT_AIR_ABSORPTION_GAINHF);
	ALFCONST(AL_REVERB_MIN_ROOM_ROLLOFF_FACTOR);               ALFCONST(AL_REVERB_MAX_ROOM_ROLLOFF_FACTOR);
	ALFCONST(AL_REVERB_DEFAULT_ROOM_ROLLOFF_FACTOR);           ALFCONST(AL_EAXREVERB_MIN_DENSITY);
	ALFCONST(AL_EAXREVERB_MAX_DENSITY);                        ALFCONST(AL_EAXREVERB_DEFAULT_DENSITY);
	ALFCONST(AL_EAXREVERB_MIN_DIFFUSION);                      ALFCONST(AL_EAXREVERB_MAX_DIFFUSION);
	ALFCONST(AL_EAXREVERB_DEFAULT_DIFFUSION);                  ALFCONST(AL_EAXREVERB_MIN_GAIN);
	ALFCONST(AL_EAXREVERB_MAX_GAIN);                           ALFCONST(AL_EAXREVERB_DEFAULT_GAIN);
	ALFCONST(AL_EAXREVERB_MIN_GAINHF);                         ALFCONST(AL_EAXREVERB_MAX_GAINHF);
	ALFCONST(AL_EAXREVERB_DEFAULT_GAINHF);                     ALFCONST(AL_EAXREVERB_MIN_GAINLF);
	ALFCONST(AL_EAXREVERB_MAX_GAINLF);                         ALFCONST(AL_EAXREVERB_DEFAULT_GAINLF);
	ALFCONST(AL_EAXREVERB_MIN_DECAY_TIME);                     ALFCONST(AL_EAXREVERB_MAX_DECAY_TIME);
	ALFCONST(AL_EAXREVERB_DEFAULT_DECAY_TIME);                 ALFCONST(AL_EAXREVERB_MIN_DECAY_HFRATIO);
	ALFCONST(AL_EAXREVERB_MAX_DECAY_HFRATIO);                  ALFCONST(AL_EAXREVERB_DEFAULT_DECAY_HFRATIO);
	ALFCONST(AL_EAXREVERB_MIN_DECAY_LFRATIO);                  ALFCONST(AL_EAXREVERB_MAX_DECAY_LFRATIO);
	ALFCONST(AL_EAXREVERB_DEFAULT_DECAY_LFRATIO);              ALFCONST(AL_EAXREVERB_MIN_REFLECTIONS_GAIN);
	ALFCONST(AL_EAXREVERB_MAX_REFLECTIONS_GAIN);               ALFCONST(AL_EAXREVERB_DEFAULT_REFLECTIONS_GAIN);
	ALFCONST(AL_EAXREVERB_MIN_REFLECTIONS_DELAY);              ALFCONST(AL_EAXREVERB_MAX_REFLECTIONS_DELAY);
	ALFCONST(AL_EAXREVERB_DEFAULT_REFLECTIONS_DELAY);          ALFCONST(AL_EAXREVERB_DEFAULT_REFLECTIONS_PAN_XYZ);
	ALFCONST(AL_EAXREVERB_MIN_LATE_REVERB_GAIN);               ALFCONST(AL_EAXREVERB_MAX_LATE_REVERB_GAIN);
	ALFCONST(AL_EAXREVERB_DEFAULT_LATE_REVERB_GAIN);           ALFCONST(AL_EAXREVERB_MIN_LATE_REVERB_DELAY);
	ALFCONST(AL_EAXREVERB_MAX_LATE_REVERB_DELAY);              ALFCONST(AL_EAXREVERB_DEFAULT_LATE_REVERB_DELAY);
	ALFCONST(AL_EAXREVERB_DEFAULT_LATE_REVERB_PAN_XYZ);        ALFCONST(AL_EAXREVERB_MIN_ECHO_TIME);
	ALFCONST(AL_EAXREVERB_MAX_ECHO_TIME);                      ALFCONST(AL_EAXREVERB_DEFAULT_ECHO_TIME);
	ALFCONST(AL_EAXREVERB_MIN_ECHO_DEPTH);                     ALFCONST(AL_EAXREVERB_MAX_ECHO_DEPTH);
	ALFCONST(AL_EAXREVERB_DEFAULT_ECHO_DEPTH);                 ALFCONST(AL_EAXREVERB_MIN_MODULATION_TIME);
	ALFCONST(AL_EAXREVERB_MAX_MODULATION_TIME);                ALFCONST(AL_EAXREVERB_DEFAULT_MODULATION_TIME);
	ALFCONST(AL_EAXREVERB_MIN_MODULATION_DEPTH);               ALFCONST(AL_EAXREVERB_MAX_MODULATION_DEPTH);
	ALFCONST(AL_EAXREVERB_DEFAULT_MODULATION_DEPTH);           ALFCONST(AL_EAXREVERB_MIN_AIR_ABSORPTION_GAINHF);
	ALFCONST(AL_EAXREVERB_MAX_AIR_ABSORPTION_GAINHF);          ALFCONST(AL_EAXREVERB_DEFAULT_AIR_ABSORPTION_GAINHF);
	ALFCONST(AL_EAXREVERB_MIN_HFREFERENCE);                    ALFCONST(AL_EAXREVERB_MAX_HFREFERENCE);
	ALFCONST(AL_EAXREVERB_DEFAULT_HFREFERENCE);                ALFCONST(AL_EAXREVERB_MIN_LFREFERENCE);
	ALFCONST(AL_EAXREVERB_MAX_LFREFERENCE);                    ALFCONST(AL_EAXREVERB_DEFAULT_LFREFERENCE);
	ALFCONST(AL_EAXREVERB_MIN_ROOM_ROLLOFF_FACTOR);            ALFCONST(AL_EAXREVERB_MAX_ROOM_ROLLOFF_FACTOR);
	ALFCONST(AL_EAXREVERB_DEFAULT_ROOM_ROLLOFF_FACTOR);        ALFCONST(AL_CHORUS_MIN_RATE);
	ALFCONST(AL_CHORUS_MAX_RATE);                              ALFCONST(AL_CHORUS_DEFAULT_RATE);
	ALFCONST(AL_CHORUS_MIN_DEPTH);                             ALFCONST(AL_CHORUS_MAX_DEPTH);
	ALFCONST(AL_CHORUS_DEFAULT_DEPTH);                         ALFCONST(AL_CHORUS_MIN_FEEDBACK);
	ALFCONST(AL_CHORUS_MAX_FEEDBACK);                          ALFCONST(AL_CHORUS_DEFAULT_FEEDBACK);
	ALFCONST(AL_CHORUS_MIN_DELAY);                             ALFCONST(AL_CHORUS_MAX_DELAY);
	ALFCONST(AL_CHORUS_DEFAULT_DELAY);                         ALFCONST(AL_DISTORTION_MIN_EDGE);
	ALFCONST(AL_DISTORTION_MAX_EDGE);                          ALFCONST(AL_DISTORTION_DEFAULT_EDGE);
	ALFCONST(AL_DISTORTION_MIN_GAIN);                          ALFCONST(AL_DISTORTION_MAX_GAIN);
	ALFCONST(AL_DISTORTION_DEFAULT_GAIN);                      ALFCONST(AL_DISTORTION_MIN_LOWPASS_CUTOFF);
	ALFCONST(AL_DISTORTION_MAX_LOWPASS_CUTOFF);                ALFCONST(AL_DISTORTION_DEFAULT_LOWPASS_CUTOFF);
	ALFCONST(AL_DISTORTION_MIN_EQCENTER);                      ALFCONST(AL_DISTORTION_MAX_EQCENTER);
	ALFCONST(AL_DISTORTION_DEFAULT_EQCENTER);                  ALFCONST(AL_DISTORTION_MIN_EQBANDWIDTH);
	ALFCONST(AL_DISTORTION_MAX_EQBANDWIDTH);                   ALFCONST(AL_DISTORTION_DEFAULT_EQBANDWIDTH);
	ALFCONST(AL_ECHO_MIN_DELAY);                               ALFCONST(AL_ECHO_MAX_DELAY);
	ALFCONST(AL_ECHO_DEFAULT_DELAY);                           ALFCONST(AL_ECHO_MIN_LRDELAY);
	ALFCONST(AL_ECHO_MAX_LRDELAY);                             ALFCONST(AL_ECHO_DEFAULT_LRDELAY);
	ALFCONST(AL_ECHO_MIN_DAMPING);                             ALFCONST(AL_ECHO_MAX_DAMPING);
	ALFCONST(AL_ECHO_DEFAULT_DAMPING);                         ALFCONST(AL_ECHO_MIN_FEEDBACK);
	ALFCONST(AL_ECHO_MAX_FEEDBACK);                            ALFCONST(AL_ECHO_DEFAULT_FEEDBACK);
	ALFCONST(AL_ECHO_MIN_SPREAD);                              ALFCONST(AL_ECHO_MAX_SPREAD);
	ALFCONST(AL_ECHO_DEFAULT_SPREAD);                          ALFCONST(AL_FLANGER_MIN_RATE);
	ALFCONST(AL_FLANGER_MAX_RATE);                             ALFCONST(AL_FLANGER_DEFAULT_RATE);
	ALFCONST(AL_FLANGER_MIN_DEPTH);                            ALFCONST(AL_FLANGER_MAX_DEPTH);
	ALFCONST(AL_FLANGER_DEFAULT_DEPTH);                        ALFCONST(AL_FLANGER_MIN_FEEDBACK);
	ALFCONST(AL_FLANGER_MAX_FEEDBACK);                         ALFCONST(AL_FLANGER_DEFAULT_FEEDBACK);
	ALFCONST(AL_FLANGER_MIN_DELAY);                            ALFCONST(AL_FLANGER_MAX_DELAY);
	ALFCONST(AL_FLANGER_DEFAULT_DELAY);                        ALFCONST(AL_FREQUENCY_SHIFTER_MIN_FREQUENCY);
	ALFCONST(AL_FREQUENCY_SHIFTER_MAX_FREQUENCY);              ALFCONST(AL_FREQUENCY_SHIFTER_DEFAULT_FREQUENCY);
	ALFCONST(AL_VOCAL_MORPHER_MIN_RATE);                       ALFCONST(AL_VOCAL_MORPHER_MAX_RATE);
	ALFCONST(AL_VOCAL_MORPHER_DEFAULT_RATE);                   ALFCONST(AL_RING_MODULATOR_MIN_FREQUENCY);
	ALFCONST(AL_RING_MODULATOR_MAX_FREQUENCY);                 ALFCONST(AL_RING_MODULATOR_DEFAULT_FREQUENCY);
	ALFCONST(AL_RING_MODULATOR_MIN_HIGHPASS_CUTOFF);           ALFCONST(AL_RING_MODULATOR_MAX_HIGHPASS_CUTOFF);
	ALFCONST(AL_RING_MODULATOR_DEFAULT_HIGHPASS_CUTOFF);       ALFCONST(AL_AUTOWAH_MIN_ATTACK_TIME);
	ALFCONST(AL_AUTOWAH_MAX_ATTACK_TIME);                      ALFCONST(AL_AUTOWAH_DEFAULT_ATTACK_TIME);
	ALFCONST(AL_AUTOWAH_MIN_RELEASE_TIME);                     ALFCONST(AL_AUTOWAH_MAX_RELEASE_TIME);
	ALFCONST(AL_AUTOWAH_DEFAULT_RELEASE_TIME);                 ALFCONST(AL_AUTOWAH_MIN_RESONANCE);
	ALFCONST(AL_AUTOWAH_MAX_RESONANCE);                        ALFCONST(AL_AUTOWAH_DEFAULT_RESONANCE);
	ALFCONST(AL_AUTOWAH_MIN_PEAK_GAIN);                        ALFCONST(AL_AUTOWAH_MAX_PEAK_GAIN);
	ALFCONST(AL_AUTOWAH_DEFAULT_PEAK_GAIN);                    ALFCONST(AL_EQUALIZER_MIN_LOW_GAIN);
	ALFCONST(AL_EQUALIZER_MAX_LOW_GAIN);                       ALFCONST(AL_EQUALIZER_DEFAULT_LOW_GAIN);
	ALFCONST(AL_EQUALIZER_MIN_LOW_CUTOFF);                     ALFCONST(AL_EQUALIZER_MAX_LOW_CUTOFF);
	ALFCONST(AL_EQUALIZER_DEFAULT_LOW_CUTOFF);                 ALFCONST(AL_EQUALIZER_MIN_MID1_GAIN);
	ALFCONST(AL_EQUALIZER_MAX_MID1_GAIN);                      ALFCONST(AL_EQUALIZER_DEFAULT_MID1_GAIN);
	ALFCONST(AL_EQUALIZER_MIN_MID1_CENTER);                    ALFCONST(AL_EQUALIZER_MAX_MID1_CENTER);
	ALFCONST(AL_EQUALIZER_DEFAULT_MID1_CENTER);                ALFCONST(AL_EQUALIZER_MIN_MID1_WIDTH);
	ALFCONST(AL_EQUALIZER_MAX_MID1_WIDTH);                     ALFCONST(AL_EQUALIZER_DEFAULT_MID1_WIDTH);
	ALFCONST(AL_EQUALIZER_MIN_MID2_GAIN);                      ALFCONST(AL_EQUALIZER_MAX_MID2_GAIN);
	ALFCONST(AL_EQUALIZER_DEFAULT_MID2_GAIN);                  ALFCONST(AL_EQUALIZER_MIN_MID2_CENTER);
	ALFCONST(AL_EQUALIZER_MAX_MID2_CENTER);                    ALFCONST(AL_EQUALIZER_DEFAULT_MID2_CENTER);
	ALFCONST(AL_EQUALIZER_MIN_MID2_WIDTH);                     ALFCONST(AL_EQUALIZER_MAX_MID2_WIDTH);
	ALFCONST(AL_EQUALIZER_DEFAULT_MID2_WIDTH);                 ALFCONST(AL_EQUALIZER_MIN_HIGH_GAIN);
	ALFCONST(AL_EQUALIZER_MAX_HIGH_GAIN);                      ALFCONST(AL_EQUALIZER_DEFAULT_HIGH_GAIN);
	ALFCONST(AL_EQUALIZER_MIN_HIGH_CUTOFF);                    ALFCONST(AL_EQUALIZER_MAX_HIGH_CUTOFF);
	ALFCONST(AL_EQUALIZER_DEFAULT_HIGH_CUTOFF);                ALFCONST(AL_MIN_AIR_ABSORPTION_FACTOR);
	ALFCONST(AL_MAX_AIR_ABSORPTION_FACTOR);                    ALFCONST(AL_DEFAULT_AIR_ABSORPTION_FACTOR);
	ALFCONST(AL_MIN_ROOM_ROLLOFF_FACTOR);                      ALFCONST(AL_MAX_ROOM_ROLLOFF_FACTOR);
	ALFCONST(AL_DEFAULT_ROOM_ROLLOFF_FACTOR);                  ALFCONST(AL_MIN_CONE_OUTER_GAINHF);
	ALFCONST(AL_MAX_CONE_OUTER_GAINHF);                        ALFCONST(AL_DEFAULT_CONE_OUTER_GAINHF);
	ALFCONST(AL_DEFAULT_METERS_PER_UNIT);                      ALFCONST(AL_MIN_METERS_PER_UNIT);
	ALFCONST(AL_MAX_METERS_PER_UNIT);

	ALBCONST(AL_REVERB_MIN_DECAY_HFLIMIT);                     ALBCONST(AL_REVERB_MAX_DECAY_HFLIMIT);
	ALBCONST(AL_REVERB_DEFAULT_DECAY_HFLIMIT);                 ALBCONST(AL_EAXREVERB_MIN_DECAY_HFLIMIT);
	ALBCONST(AL_EAXREVERB_MAX_DECAY_HFLIMIT);                  ALBCONST(AL_EAXREVERB_DEFAULT_DECAY_HFLIMIT);
	ALBCONST(AL_MIN_DIRECT_FILTER_GAINHF_AUTO);                ALBCONST(AL_MAX_DIRECT_FILTER_GAINHF_AUTO);
	ALBCONST(AL_DEFAULT_DIRECT_FILTER_GAINHF_AUTO);            ALBCONST(AL_MIN_AUXILIARY_SEND_FILTER_GAIN_AUTO);
	ALBCONST(AL_MAX_AUXILIARY_SEND_FILTER_GAIN_AUTO);          ALBCONST(AL_DEFAULT_AUXILIARY_SEND_FILTER_GAIN_AUTO);
	ALBCONST(AL_MIN_AUXILIARY_SEND_FILTER_GAINHF_AUTO);        ALBCONST(AL_MAX_AUXILIARY_SEND_FILTER_GAINHF_AUTO);
	ALBCONST(AL_DEFAULT_AUXILIARY_SEND_FILTER_GAINHF_AUTO);

	ALSCONST(AL_EXT_FOLDBACK_NAME);                            ALSCONST(ALC_EXT_EFX_NAME);
}

template<typename T>
struct function_traits;

template<typename R, typename ...Args>
struct function_traits<R(Args...)>
{
	typedef R result_type;
	typedef std::tuple<Args...> arg_types;
};

template<typename R, typename ...Args>
struct function_traits<R (*)(Args...)>
{
	typedef R result_type;
	typedef std::tuple<Args...> arg_types;
};

// HACK: x64 only has one calling convention, so declaring this in 64-bit mode counts as a duplicate decl
#if CROC_BUILD_BITS == 32
template<typename R, typename ...Args>
struct function_traits<R (APIENTRY *)(Args...)>
{
	typedef R result_type;
	typedef std::tuple<Args...> arg_types;
};
#endif

namespace detail
{
	template<typename F, typename Tuple, bool Done, int Total, int... N>
	struct call_impl
	{
		static typename function_traits<F>::result_type call(F f, Tuple&& t)
		{
			return call_impl<F, Tuple, Total == 1 + sizeof...(N), Total, N..., sizeof...(N)>::call(f, std::forward<Tuple>(t));
		}
	};

	template<typename F, typename Tuple, int Total, int... N>
	struct call_impl<F, Tuple, true, Total, N...>
	{
		static typename function_traits<F>::result_type call(F f, Tuple&& t)
		{
			return f(std::get<N>(std::forward<Tuple>(t))...);
		}
	};
}

template<typename F, typename Tuple>
typename function_traits<F>::result_type call(F f, Tuple&& t)
{
	typedef typename std::decay<Tuple>::type ttype;
	return detail::call_impl<F, Tuple, 0 == std::tuple_size<ttype>::value, std::tuple_size<ttype>::value>::call(f, std::forward<Tuple>(t));
}

template<typename T, typename Enable = void>
struct is_actual_integral
{
	static const bool value = std::is_integral<T>::value;
};

template<typename T>
struct is_actual_integral<T, typename std::enable_if<std::is_same<T, ALboolean>::value || std::is_same<T, ALCboolean>::value>::type>
{
	static const bool value = false;
};

template<typename T>
struct is_function_pointer
{
	static const bool value =
		std::is_pointer<T>::value ?
		std::is_function<typename std::remove_pointer<T>::type>::value :
		false;
};

template<typename T, typename Enable = void>
struct is_nonstring_pointer
{
	static const bool value = std::is_pointer<T>::value;
};

template<typename T>
struct is_nonstring_pointer<T, typename std::enable_if<std::is_same<T, const ALchar*>::value || std::is_same<T, const ALCchar*>::value>::type>
{
	static const bool value = false;
};

template<typename T>
struct is_nonstring_pointer<T, typename std::enable_if<is_function_pointer<T>::value>::type>
{
	static const bool value = false;
};

template<typename T>
struct is_nonstring_pointer<T, typename std::enable_if<std::is_same<T, ALCcontext*>::value || std::is_same<T, ALCdevice*>::value>::type>
{
	static const bool value = false;
};

template <int N, typename... T>
struct tuple_element;

template <typename T0, typename... T>
struct tuple_element<0, T0, T...>
{
	typedef T0 type;
};

template <int N, typename T0, typename... T>
struct tuple_element<N, T0, T...>
{
	typedef typename tuple_element<N-1, T...>::type type;
};

template<typename T>
typename std::enable_if<is_actual_integral<T>::value, T>::type
getALParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkIntParam(t, slot);
}

template<typename T>
typename std::enable_if<std::is_same<T, ALboolean>::value || std::is_same<T, ALCboolean>::value, T>::type
getALParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkBoolParam(t, slot);
}

template<typename T>
typename std::enable_if<std::is_floating_point<T>::value, T>::type
getALParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkNumParam(t, slot);
}

template<typename T>
typename std::enable_if<std::is_same<T, const ALchar*>::value || std::is_same<T, const ALCchar*>::value, T>::type
getALParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkStringParam(t, slot);
}

template<typename T>
typename std::enable_if<std::is_same<T, ALCcontext*>::value, T>::type
getALParam(CrocThread* t, word_t slot)
{
	return (T)ALCcontext_getThis(t, slot);
}

template<typename T>
typename std::enable_if<std::is_same<T, ALCdevice*>::value, T>::type
getALParam(CrocThread* t, word_t slot)
{
	return (T)ALCdevice_getThis(t, slot);
}

template<typename T>
typename std::enable_if<is_nonstring_pointer<T>::value, T>::type
getALParam(CrocThread* t, word_t slot)
{
	croc_ex_checkAnyParam(t, slot);

	if(croc_isMemblock(t, slot))
		return (T)croc_memblock_getData(t, slot);
	else if(croc_isInt(t, slot))
		return (T)croc_getInt(t, slot);
	else if(croc_isNull(t, slot))
		return nullptr;
	else
		croc_ex_paramTypeError(t, slot, "memblock|int|nullptr");

	return nullptr; // dummy
}

template<int Idx = 0, typename... T>
typename std::enable_if<Idx == sizeof...(T), void>::type
getALParams(CrocThread* t, std::tuple<T...>& params)
{
	(void)t;
	(void)params;
}

template<int Idx = 0, typename... T>
typename std::enable_if<Idx < sizeof...(T), void>::type
getALParams(CrocThread* t, std::tuple<T...>& params)
{
	std::get<Idx>(params) = getALParam<typename tuple_element<Idx, T...>::type>(t, Idx + 1);
	getALParams<Idx + 1, T...>(t, params);
}

template<typename T>
typename std::enable_if<std::is_void<T>::value, void>::type
pushAL(CrocThread* t, std::function<T()> func)
{
	(void)t;
	func();
}

template<typename T>
typename std::enable_if<is_actual_integral<T>::value, void>::type
pushAL(CrocThread* t, T val)
{
	croc_pushInt(t, val);
}

template<typename T>
typename std::enable_if<std::is_same<T, ALboolean>::value || std::is_same<T, ALCboolean>::value, void>::type
pushAL(CrocThread* t, T val)
{
	croc_pushBool(t, val);
}

template<typename T>
typename std::enable_if<std::is_floating_point<T>::value, void>::type
pushAL(CrocThread* t, T val)
{
	croc_pushFloat(t, val);
}

template<typename T>
typename std::enable_if<std::is_same<T, const ALchar*>::value || std::is_same<T, const ALCchar*>::value, void>::type
pushAL(CrocThread* t, T val)
{
	croc_pushString(t, val);
}

template<typename T>
typename std::enable_if<std::is_same<T, ALCcontext*>::value, void>::type
pushAL(CrocThread* t, T val)
{
	pushALCcontextObj(t, val);
}

template<typename T>
typename std::enable_if<std::is_same<T, ALCdevice*>::value, void>::type
pushAL(CrocThread* t, T val)
{
	pushALCdeviceObj(t, val);
}

template<typename R, typename... Args>
struct wrapal;

template<typename... Args>
struct wrapal<void, std::tuple<Args...>>
{
	static const uword_t numParams = sizeof...(Args);

	template<void (* AL_APIENTRY* Fun)(Args...)>
	struct func_holder
	{
		static word_t func(CrocThread* t)
		{
			std::tuple<Args...> _params;
			getALParams(t, _params);
			call(*Fun, _params);
			return 0;
		}
	};
};

template<typename R, typename... Args>
struct wrapal<R, std::tuple<Args...>>
{
	static const uword_t numParams = sizeof...(Args);

	template<R (* AL_APIENTRY* Fun)(Args...)>
	struct func_holder
	{
		static word_t func(CrocThread* t)
		{
			std::tuple<Args...> _params;
			getALParams(t, _params);
			pushAL(t, call(*Fun, _params));
			return 1;
		}
	};
};

#define NUMPARAMS(FUNC) wrapal<function_traits<decltype(FUNC)>::result_type, function_traits<decltype(FUNC)>::arg_types>::numParams
#define WRAPAL(FUNC) wrapal<function_traits<decltype(FUNC)>::result_type, function_traits<decltype(FUNC)>::arg_types>::func_holder<&FUNC>::func
#define WRAP(FUNC) {#FUNC, NUMPARAMS(FUNC), &WRAPAL(FUNC)}

const CrocRegisterFunc _alFuncs[] =
{
	WRAP(alEnable),
	WRAP(alDisable),
	WRAP(alIsEnabled),
	WRAP(alGetString),
	WRAP(alGetBooleanv),
	WRAP(alGetIntegerv),
	WRAP(alGetFloatv),
	WRAP(alGetDoublev),
	WRAP(alGetBoolean),
	WRAP(alGetInteger),
	WRAP(alGetFloat),
	WRAP(alGetDouble),
	WRAP(alGetError),
	WRAP(alIsExtensionPresent),
	WRAP(alGetEnumValue),
	WRAP(alListenerf),
	WRAP(alListener3f),
	WRAP(alListenerfv),
	WRAP(alListeneri),
	WRAP(alListener3i),
	WRAP(alListeneriv),
	WRAP(alGetListenerf),
	WRAP(alGetListener3f),
	WRAP(alGetListenerfv),
	WRAP(alGetListeneri),
	WRAP(alGetListener3i),
	WRAP(alGetListeneriv),
	WRAP(alGenSources),
	WRAP(alDeleteSources),
	WRAP(alIsSource),
	WRAP(alSourcef),
	WRAP(alSource3f),
	WRAP(alSourcefv),
	WRAP(alSourcei),
	WRAP(alSource3i),
	WRAP(alSourceiv),
	WRAP(alGetSourcef),
	WRAP(alGetSource3f),
	WRAP(alGetSourcefv),
	WRAP(alGetSourcei),
	WRAP(alGetSource3i),
	WRAP(alGetSourceiv),
	WRAP(alSourcePlayv),
	WRAP(alSourceStopv),
	WRAP(alSourceRewindv),
	WRAP(alSourcePausev),
	WRAP(alSourcePlay),
	WRAP(alSourceStop),
	WRAP(alSourceRewind),
	WRAP(alSourcePause),
	WRAP(alSourceQueueBuffers),
	WRAP(alSourceUnqueueBuffers),
	WRAP(alGenBuffers),
	WRAP(alDeleteBuffers),
	WRAP(alIsBuffer),
	WRAP(alBufferData),
	WRAP(alBufferf),
	WRAP(alBuffer3f),
	WRAP(alBufferfv),
	WRAP(alBufferi),
	WRAP(alBuffer3i),
	WRAP(alBufferiv),
	WRAP(alGetBufferf),
	WRAP(alGetBuffer3f),
	WRAP(alGetBufferfv),
	WRAP(alGetBufferi),
	WRAP(alGetBuffer3i),
	WRAP(alGetBufferiv),
	WRAP(alDopplerFactor),
	WRAP(alDopplerVelocity),
	WRAP(alSpeedOfSound),
	WRAP(alDistanceModel),
	WRAP(alcCreateContext),
	WRAP(alcMakeContextCurrent),
	WRAP(alcProcessContext),
	WRAP(alcGetCurrentContext),
	WRAP(alcGetContextsDevice),
	WRAP(alcSuspendContext),
	WRAP(alcDestroyContext),
	WRAP(alcOpenDevice),
	WRAP(alcCloseDevice),
	WRAP(alcGetError),
	WRAP(alcIsExtensionPresent),
	WRAP(alcGetEnumValue),
	WRAP(alcGetString),
	WRAP(alcGetIntegerv),
	WRAP(alcCaptureOpenDevice),
	WRAP(alcCaptureCloseDevice),
	WRAP(alcCaptureStart),
	WRAP(alcCaptureStop),
	WRAP(alcCaptureSamples),
	{nullptr, 0, nullptr}
};

// =====================================================================================================================
// Loader

word loader(CrocThread* t)
{
	loadSharedLib(t);
	registerConstants(t);
	croc_ex_registerGlobals(t, _alFuncs);

	croc_ex_lookup(t, "hash.WeakValTable");
	croc_pushNull(t);
	croc_call(t, -2, 1);
	croc_ex_setRegistryVar(t, HandleMap);

	croc_class_new(t, "ALCdevice", 0);
		croc_pushNull(t); croc_class_addHField(t, -2, ALCdevice_handle);
		registerMethod(t, _DListItem(ALCdevice_constructor), 0);
	croc_newGlobal(t, "ALCdevice");

	croc_class_new(t, "ALCcontext", 0);
		croc_pushNull(t); croc_class_addHField(t, -2, ALCcontext_handle);
		registerMethod(t, _DListItem(ALCcontext_constructor), 0);
	croc_newGlobal(t, "ALCcontext");

#ifdef CROC_BUILTIN_DOCS
	CrocDoc doc;
	croc_ex_doc_init(t, &doc, __FILE__);
	croc_dup(t, 0);
	croc_ex_doc_push(&doc, moduleDocs);
		// croc_field(t, -1, "Regex");
		// 	croc_ex_doc_push(&doc, RegexDocs);
		// 	docFields(&doc, Regex_methodFuncs);
		// 	docFieldUV(&doc, Regex_opApplyFunc);

		// 	docField(&doc, {Regex_opIndex_info, nullptr});
		// 	croc_ex_doc_pop(&doc, -1);
		// croc_popTop(t);
	croc_ex_doc_pop(&doc, -1);
	croc_ex_doc_finish(&doc);
	croc_popTop(t);
#endif

	return 0;
}
}

void initOpenAlLib(CrocThread* t)
{
	croc_ex_makeModule(t, "openal", &loader);
}
}
#endif