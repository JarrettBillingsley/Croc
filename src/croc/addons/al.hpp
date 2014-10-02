#ifndef CROC_ADDONS_AL_HPP
#define CROC_ADDONS_AL_HPP

#include <cfloat>

// =====================================================================================================================
// OpenAL Soft Header stuff (taken from the 1.1 headers)

extern "C"
{

#define AL_API
#define ALC_API

#if defined(_WIN32)
 #define AL_APIENTRY __cdecl
 #define ALC_APIENTRY __cdecl
#else
 #define AL_APIENTRY
 #define ALC_APIENTRY
#endif

typedef char ALboolean;
typedef char ALchar;
typedef signed char ALbyte;
typedef unsigned char ALubyte;
typedef short ALshort;
typedef unsigned short ALushort;
typedef int ALint;
typedef unsigned int ALuint;
typedef int ALsizei;
typedef int ALenum;
typedef float ALfloat;
typedef double ALdouble;
typedef void ALvoid;
typedef struct ALCdevice_struct ALCdevice;
typedef struct ALCcontext_struct ALCcontext;
typedef char ALCboolean;
typedef char ALCchar;
typedef signed char ALCbyte;
typedef unsigned char ALCubyte;
typedef short ALCshort;
typedef unsigned short ALCushort;
typedef int ALCint;
typedef unsigned int ALCuint;
typedef int ALCsizei;
typedef int ALCenum;
typedef float ALCfloat;
typedef double ALCdouble;
typedef void ALCvoid;
typedef void (AL_APIENTRY*LPALFOLDBACKCALLBACK)(ALenum,ALsizei);
typedef int64_t ALint64SOFT;
typedef uint64_t ALuint64SOFT;

#define AL_FALSE                                 0
#define AL_TRUE                                  1
#define AL_NONE                                  0
#define AL_SOURCE_RELATIVE                       0x202
#define AL_CONE_INNER_ANGLE                      0x1001
#define AL_CONE_OUTER_ANGLE                      0x1002
#define AL_PITCH                                 0x1003
#define AL_POSITION                              0x1004
#define AL_DIRECTION                             0x1005
#define AL_VELOCITY                              0x1006
#define AL_LOOPING                               0x1007
#define AL_BUFFER                                0x1009
#define AL_GAIN                                  0x100A
#define AL_MIN_GAIN                              0x100D
#define AL_MAX_GAIN                              0x100E
#define AL_ORIENTATION                           0x100F
#define AL_SOURCE_STATE                          0x1010
#define AL_INITIAL                               0x1011
#define AL_PLAYING                               0x1012
#define AL_PAUSED                                0x1013
#define AL_STOPPED                               0x1014
#define AL_BUFFERS_QUEUED                        0x1015
#define AL_BUFFERS_PROCESSED                     0x1016
#define AL_REFERENCE_DISTANCE                    0x1020
#define AL_ROLLOFF_FACTOR                        0x1021
#define AL_CONE_OUTER_GAIN                       0x1022
#define AL_MAX_DISTANCE                          0x1023
#define AL_SEC_OFFSET                            0x1024
#define AL_SAMPLE_OFFSET                         0x1025
#define AL_BYTE_OFFSET                           0x1026
#define AL_SOURCE_TYPE                           0x1027
#define AL_STATIC                                0x1028
#define AL_STREAMING                             0x1029
#define AL_UNDETERMINED                          0x1030
#define AL_FORMAT_MONO8                          0x1100
#define AL_FORMAT_MONO16                         0x1101
#define AL_FORMAT_STEREO8                        0x1102
#define AL_FORMAT_STEREO16                       0x1103
#define AL_FREQUENCY                             0x2001
#define AL_BITS                                  0x2002
#define AL_CHANNELS                              0x2003
#define AL_SIZE                                  0x2004
#define AL_UNUSED                                0x2010
#define AL_PENDING                               0x2011
#define AL_PROCESSED                             0x2012
#define AL_NO_ERROR                              0
#define AL_INVALID_NAME                          0xA001
#define AL_INVALID_ENUM                          0xA002
#define AL_INVALID_VALUE                         0xA003
#define AL_INVALID_OPERATION                     0xA004
#define AL_OUT_OF_MEMORY                         0xA005
#define AL_VENDOR                                0xB001
#define AL_VERSION                               0xB002
#define AL_RENDERER                              0xB003
#define AL_EXTENSIONS                            0xB004
#define AL_DOPPLER_FACTOR                        0xC000
#define AL_DOPPLER_VELOCITY                      0xC001
#define AL_SPEED_OF_SOUND                        0xC003
#define AL_DISTANCE_MODEL                        0xD000
#define AL_INVERSE_DISTANCE                      0xD001
#define AL_INVERSE_DISTANCE_CLAMPED              0xD002
#define AL_LINEAR_DISTANCE                       0xD003
#define AL_LINEAR_DISTANCE_CLAMPED               0xD004
#define AL_EXPONENT_DISTANCE                     0xD005
#define AL_EXPONENT_DISTANCE_CLAMPED             0xD006
#define AL_METERS_PER_UNIT                       0x20004
#define AL_DIRECT_FILTER                         0x20005
#define AL_AUXILIARY_SEND_FILTER                 0x20006
#define AL_AIR_ABSORPTION_FACTOR                 0x20007
#define AL_ROOM_ROLLOFF_FACTOR                   0x20008
#define AL_CONE_OUTER_GAINHF                     0x20009
#define AL_DIRECT_FILTER_GAINHF_AUTO             0x2000A
#define AL_AUXILIARY_SEND_FILTER_GAIN_AUTO       0x2000B
#define AL_AUXILIARY_SEND_FILTER_GAINHF_AUTO     0x2000C
#define AL_REVERB_DENSITY                        0x0001
#define AL_REVERB_DIFFUSION                      0x0002
#define AL_REVERB_GAIN                           0x0003
#define AL_REVERB_GAINHF                         0x0004
#define AL_REVERB_DECAY_TIME                     0x0005
#define AL_REVERB_DECAY_HFRATIO                  0x0006
#define AL_REVERB_REFLECTIONS_GAIN               0x0007
#define AL_REVERB_REFLECTIONS_DELAY              0x0008
#define AL_REVERB_LATE_REVERB_GAIN               0x0009
#define AL_REVERB_LATE_REVERB_DELAY              0x000A
#define AL_REVERB_AIR_ABSORPTION_GAINHF          0x000B
#define AL_REVERB_ROOM_ROLLOFF_FACTOR            0x000C
#define AL_REVERB_DECAY_HFLIMIT                  0x000D
#define AL_EAXREVERB_DENSITY                     0x0001
#define AL_EAXREVERB_DIFFUSION                   0x0002
#define AL_EAXREVERB_GAIN                        0x0003
#define AL_EAXREVERB_GAINHF                      0x0004
#define AL_EAXREVERB_GAINLF                      0x0005
#define AL_EAXREVERB_DECAY_TIME                  0x0006
#define AL_EAXREVERB_DECAY_HFRATIO               0x0007
#define AL_EAXREVERB_DECAY_LFRATIO               0x0008
#define AL_EAXREVERB_REFLECTIONS_GAIN            0x0009
#define AL_EAXREVERB_REFLECTIONS_DELAY           0x000A
#define AL_EAXREVERB_REFLECTIONS_PAN             0x000B
#define AL_EAXREVERB_LATE_REVERB_GAIN            0x000C
#define AL_EAXREVERB_LATE_REVERB_DELAY           0x000D
#define AL_EAXREVERB_LATE_REVERB_PAN             0x000E
#define AL_EAXREVERB_ECHO_TIME                   0x000F
#define AL_EAXREVERB_ECHO_DEPTH                  0x0010
#define AL_EAXREVERB_MODULATION_TIME             0x0011
#define AL_EAXREVERB_MODULATION_DEPTH            0x0012
#define AL_EAXREVERB_AIR_ABSORPTION_GAINHF       0x0013
#define AL_EAXREVERB_HFREFERENCE                 0x0014
#define AL_EAXREVERB_LFREFERENCE                 0x0015
#define AL_EAXREVERB_ROOM_ROLLOFF_FACTOR         0x0016
#define AL_EAXREVERB_DECAY_HFLIMIT               0x0017
#define AL_CHORUS_WAVEFORM                       0x0001
#define AL_CHORUS_PHASE                          0x0002
#define AL_CHORUS_RATE                           0x0003
#define AL_CHORUS_DEPTH                          0x0004
#define AL_CHORUS_FEEDBACK                       0x0005
#define AL_CHORUS_DELAY                          0x0006
#define AL_DISTORTION_EDGE                       0x0001
#define AL_DISTORTION_GAIN                       0x0002
#define AL_DISTORTION_LOWPASS_CUTOFF             0x0003
#define AL_DISTORTION_EQCENTER                   0x0004
#define AL_DISTORTION_EQBANDWIDTH                0x0005
#define AL_ECHO_DELAY                            0x0001
#define AL_ECHO_LRDELAY                          0x0002
#define AL_ECHO_DAMPING                          0x0003
#define AL_ECHO_FEEDBACK                         0x0004
#define AL_ECHO_SPREAD                           0x0005
#define AL_FLANGER_WAVEFORM                      0x0001
#define AL_FLANGER_PHASE                         0x0002
#define AL_FLANGER_RATE                          0x0003
#define AL_FLANGER_DEPTH                         0x0004
#define AL_FLANGER_FEEDBACK                      0x0005
#define AL_FLANGER_DELAY                         0x0006
#define AL_FREQUENCY_SHIFTER_FREQUENCY           0x0001
#define AL_FREQUENCY_SHIFTER_LEFT_DIRECTION      0x0002
#define AL_FREQUENCY_SHIFTER_RIGHT_DIRECTION     0x0003
#define AL_VOCAL_MORPHER_PHONEMEA                0x0001
#define AL_VOCAL_MORPHER_PHONEMEA_COARSE_TUNING  0x0002
#define AL_VOCAL_MORPHER_PHONEMEB                0x0003
#define AL_VOCAL_MORPHER_PHONEMEB_COARSE_TUNING  0x0004
#define AL_VOCAL_MORPHER_WAVEFORM                0x0005
#define AL_VOCAL_MORPHER_RATE                    0x0006
#define AL_PITCH_SHIFTER_COARSE_TUNE             0x0001
#define AL_PITCH_SHIFTER_FINE_TUNE               0x0002
#define AL_RING_MODULATOR_FREQUENCY              0x0001
#define AL_RING_MODULATOR_HIGHPASS_CUTOFF        0x0002
#define AL_RING_MODULATOR_WAVEFORM               0x0003
#define AL_AUTOWAH_ATTACK_TIME                   0x0001
#define AL_AUTOWAH_RELEASE_TIME                  0x0002
#define AL_AUTOWAH_RESONANCE                     0x0003
#define AL_AUTOWAH_PEAK_GAIN                     0x0004
#define AL_COMPRESSOR_ONOFF                      0x0001
#define AL_EQUALIZER_LOW_GAIN                    0x0001
#define AL_EQUALIZER_LOW_CUTOFF                  0x0002
#define AL_EQUALIZER_MID1_GAIN                   0x0003
#define AL_EQUALIZER_MID1_CENTER                 0x0004
#define AL_EQUALIZER_MID1_WIDTH                  0x0005
#define AL_EQUALIZER_MID2_GAIN                   0x0006
#define AL_EQUALIZER_MID2_CENTER                 0x0007
#define AL_EQUALIZER_MID2_WIDTH                  0x0008
#define AL_EQUALIZER_HIGH_GAIN                   0x0009
#define AL_EQUALIZER_HIGH_CUTOFF                 0x000A
#define AL_EFFECT_FIRST_PARAMETER                0x0000
#define AL_EFFECT_LAST_PARAMETER                 0x8000
#define AL_EFFECT_TYPE                           0x8001
#define AL_EFFECT_NULL                           0x0000
#define AL_EFFECT_REVERB                         0x0001
#define AL_EFFECT_CHORUS                         0x0002
#define AL_EFFECT_DISTORTION                     0x0003
#define AL_EFFECT_ECHO                           0x0004
#define AL_EFFECT_FLANGER                        0x0005
#define AL_EFFECT_FREQUENCY_SHIFTER              0x0006
#define AL_EFFECT_VOCAL_MORPHER                  0x0007
#define AL_EFFECT_PITCH_SHIFTER                  0x0008
#define AL_EFFECT_RING_MODULATOR                 0x0009
#define AL_EFFECT_AUTOWAH                        0x000A
#define AL_EFFECT_COMPRESSOR                     0x000B
#define AL_EFFECT_EQUALIZER                      0x000C
#define AL_EFFECT_EAXREVERB                      0x8000
#define AL_EFFECTSLOT_EFFECT                     0x0001
#define AL_EFFECTSLOT_GAIN                       0x0002
#define AL_EFFECTSLOT_AUXILIARY_SEND_AUTO        0x0003
#define AL_EFFECTSLOT_NULL                       0x0000
#define AL_LOWPASS_GAIN                          0x0001
#define AL_LOWPASS_GAINHF                        0x0002
#define AL_HIGHPASS_GAIN                         0x0001
#define AL_HIGHPASS_GAINLF                       0x0002
#define AL_BANDPASS_GAIN                         0x0001
#define AL_BANDPASS_GAINLF                       0x0002
#define AL_BANDPASS_GAINHF                       0x0003
#define AL_FILTER_FIRST_PARAMETER                0x0000
#define AL_FILTER_LAST_PARAMETER                 0x8000
#define AL_FILTER_TYPE                           0x8001
#define AL_FILTER_NULL                           0x0000
#define AL_FILTER_LOWPASS                        0x0001
#define AL_FILTER_HIGHPASS                       0x0002
#define AL_FILTER_BANDPASS                       0x0003
#define AL_LOWPASS_MIN_GAIN                      (0.0f)
#define AL_LOWPASS_MAX_GAIN                      (1.0f)
#define AL_LOWPASS_DEFAULT_GAIN                  (1.0f)
#define AL_LOWPASS_MIN_GAINHF                    (0.0f)
#define AL_LOWPASS_MAX_GAINHF                    (1.0f)
#define AL_LOWPASS_DEFAULT_GAINHF                (1.0f)
#define AL_HIGHPASS_MIN_GAIN                     (0.0f)
#define AL_HIGHPASS_MAX_GAIN                     (1.0f)
#define AL_HIGHPASS_DEFAULT_GAIN                 (1.0f)
#define AL_HIGHPASS_MIN_GAINLF                   (0.0f)
#define AL_HIGHPASS_MAX_GAINLF                   (1.0f)
#define AL_HIGHPASS_DEFAULT_GAINLF               (1.0f)
#define AL_BANDPASS_MIN_GAIN                     (0.0f)
#define AL_BANDPASS_MAX_GAIN                     (1.0f)
#define AL_BANDPASS_DEFAULT_GAIN                 (1.0f)
#define AL_BANDPASS_MIN_GAINHF                   (0.0f)
#define AL_BANDPASS_MAX_GAINHF                   (1.0f)
#define AL_BANDPASS_DEFAULT_GAINHF               (1.0f)
#define AL_BANDPASS_MIN_GAINLF                   (0.0f)
#define AL_BANDPASS_MAX_GAINLF                   (1.0f)
#define AL_BANDPASS_DEFAULT_GAINLF               (1.0f)
#define AL_REVERB_MIN_DENSITY                    (0.0f)
#define AL_REVERB_MAX_DENSITY                    (1.0f)
#define AL_REVERB_DEFAULT_DENSITY                (1.0f)
#define AL_REVERB_MIN_DIFFUSION                  (0.0f)
#define AL_REVERB_MAX_DIFFUSION                  (1.0f)
#define AL_REVERB_DEFAULT_DIFFUSION              (1.0f)
#define AL_REVERB_MIN_GAIN                       (0.0f)
#define AL_REVERB_MAX_GAIN                       (1.0f)
#define AL_REVERB_DEFAULT_GAIN                   (0.32f)
#define AL_REVERB_MIN_GAINHF                     (0.0f)
#define AL_REVERB_MAX_GAINHF                     (1.0f)
#define AL_REVERB_DEFAULT_GAINHF                 (0.89f)
#define AL_REVERB_MIN_DECAY_TIME                 (0.1f)
#define AL_REVERB_MAX_DECAY_TIME                 (20.0f)
#define AL_REVERB_DEFAULT_DECAY_TIME             (1.49f)
#define AL_REVERB_MIN_DECAY_HFRATIO              (0.1f)
#define AL_REVERB_MAX_DECAY_HFRATIO              (2.0f)
#define AL_REVERB_DEFAULT_DECAY_HFRATIO          (0.83f)
#define AL_REVERB_MIN_REFLECTIONS_GAIN           (0.0f)
#define AL_REVERB_MAX_REFLECTIONS_GAIN           (3.16f)
#define AL_REVERB_DEFAULT_REFLECTIONS_GAIN       (0.05f)
#define AL_REVERB_MIN_REFLECTIONS_DELAY          (0.0f)
#define AL_REVERB_MAX_REFLECTIONS_DELAY          (0.3f)
#define AL_REVERB_DEFAULT_REFLECTIONS_DELAY      (0.007f)
#define AL_REVERB_MIN_LATE_REVERB_GAIN           (0.0f)
#define AL_REVERB_MAX_LATE_REVERB_GAIN           (10.0f)
#define AL_REVERB_DEFAULT_LATE_REVERB_GAIN       (1.26f)
#define AL_REVERB_MIN_LATE_REVERB_DELAY          (0.0f)
#define AL_REVERB_MAX_LATE_REVERB_DELAY          (0.1f)
#define AL_REVERB_DEFAULT_LATE_REVERB_DELAY      (0.011f)
#define AL_REVERB_MIN_AIR_ABSORPTION_GAINHF      (0.892f)
#define AL_REVERB_MAX_AIR_ABSORPTION_GAINHF      (1.0f)
#define AL_REVERB_DEFAULT_AIR_ABSORPTION_GAINHF  (0.994f)
#define AL_REVERB_MIN_ROOM_ROLLOFF_FACTOR        (0.0f)
#define AL_REVERB_MAX_ROOM_ROLLOFF_FACTOR        (10.0f)
#define AL_REVERB_DEFAULT_ROOM_ROLLOFF_FACTOR    (0.0f)
#define AL_REVERB_MIN_DECAY_HFLIMIT              AL_FALSE
#define AL_REVERB_MAX_DECAY_HFLIMIT              AL_TRUE
#define AL_REVERB_DEFAULT_DECAY_HFLIMIT          AL_TRUE
#define AL_EAXREVERB_MIN_DENSITY                 (0.0f)
#define AL_EAXREVERB_MAX_DENSITY                 (1.0f)
#define AL_EAXREVERB_DEFAULT_DENSITY             (1.0f)
#define AL_EAXREVERB_MIN_DIFFUSION               (0.0f)
#define AL_EAXREVERB_MAX_DIFFUSION               (1.0f)
#define AL_EAXREVERB_DEFAULT_DIFFUSION           (1.0f)
#define AL_EAXREVERB_MIN_GAIN                    (0.0f)
#define AL_EAXREVERB_MAX_GAIN                    (1.0f)
#define AL_EAXREVERB_DEFAULT_GAIN                (0.32f)
#define AL_EAXREVERB_MIN_GAINHF                  (0.0f)
#define AL_EAXREVERB_MAX_GAINHF                  (1.0f)
#define AL_EAXREVERB_DEFAULT_GAINHF              (0.89f)
#define AL_EAXREVERB_MIN_GAINLF                  (0.0f)
#define AL_EAXREVERB_MAX_GAINLF                  (1.0f)
#define AL_EAXREVERB_DEFAULT_GAINLF              (1.0f)
#define AL_EAXREVERB_MIN_DECAY_TIME              (0.1f)
#define AL_EAXREVERB_MAX_DECAY_TIME              (20.0f)
#define AL_EAXREVERB_DEFAULT_DECAY_TIME          (1.49f)
#define AL_EAXREVERB_MIN_DECAY_HFRATIO           (0.1f)
#define AL_EAXREVERB_MAX_DECAY_HFRATIO           (2.0f)
#define AL_EAXREVERB_DEFAULT_DECAY_HFRATIO       (0.83f)
#define AL_EAXREVERB_MIN_DECAY_LFRATIO           (0.1f)
#define AL_EAXREVERB_MAX_DECAY_LFRATIO           (2.0f)
#define AL_EAXREVERB_DEFAULT_DECAY_LFRATIO       (1.0f)
#define AL_EAXREVERB_MIN_REFLECTIONS_GAIN        (0.0f)
#define AL_EAXREVERB_MAX_REFLECTIONS_GAIN        (3.16f)
#define AL_EAXREVERB_DEFAULT_REFLECTIONS_GAIN    (0.05f)
#define AL_EAXREVERB_MIN_REFLECTIONS_DELAY       (0.0f)
#define AL_EAXREVERB_MAX_REFLECTIONS_DELAY       (0.3f)
#define AL_EAXREVERB_DEFAULT_REFLECTIONS_DELAY   (0.007f)
#define AL_EAXREVERB_DEFAULT_REFLECTIONS_PAN_XYZ (0.0f)
#define AL_EAXREVERB_MIN_LATE_REVERB_GAIN        (0.0f)
#define AL_EAXREVERB_MAX_LATE_REVERB_GAIN        (10.0f)
#define AL_EAXREVERB_DEFAULT_LATE_REVERB_GAIN    (1.26f)
#define AL_EAXREVERB_MIN_LATE_REVERB_DELAY       (0.0f)
#define AL_EAXREVERB_MAX_LATE_REVERB_DELAY       (0.1f)
#define AL_EAXREVERB_DEFAULT_LATE_REVERB_DELAY   (0.011f)
#define AL_EAXREVERB_DEFAULT_LATE_REVERB_PAN_XYZ (0.0f)
#define AL_EAXREVERB_MIN_ECHO_TIME               (0.075f)
#define AL_EAXREVERB_MAX_ECHO_TIME               (0.25f)
#define AL_EAXREVERB_DEFAULT_ECHO_TIME           (0.25f)
#define AL_EAXREVERB_MIN_ECHO_DEPTH              (0.0f)
#define AL_EAXREVERB_MAX_ECHO_DEPTH              (1.0f)
#define AL_EAXREVERB_DEFAULT_ECHO_DEPTH          (0.0f)
#define AL_EAXREVERB_MIN_MODULATION_TIME         (0.04f)
#define AL_EAXREVERB_MAX_MODULATION_TIME         (4.0f)
#define AL_EAXREVERB_DEFAULT_MODULATION_TIME     (0.25f)
#define AL_EAXREVERB_MIN_MODULATION_DEPTH        (0.0f)
#define AL_EAXREVERB_MAX_MODULATION_DEPTH        (1.0f)
#define AL_EAXREVERB_DEFAULT_MODULATION_DEPTH    (0.0f)
#define AL_EAXREVERB_MIN_AIR_ABSORPTION_GAINHF   (0.892f)
#define AL_EAXREVERB_MAX_AIR_ABSORPTION_GAINHF   (1.0f)
#define AL_EAXREVERB_DEFAULT_AIR_ABSORPTION_GAINHF (0.994f)
#define AL_EAXREVERB_MIN_HFREFERENCE             (1000.0f)
#define AL_EAXREVERB_MAX_HFREFERENCE             (20000.0f)
#define AL_EAXREVERB_DEFAULT_HFREFERENCE         (5000.0f)
#define AL_EAXREVERB_MIN_LFREFERENCE             (20.0f)
#define AL_EAXREVERB_MAX_LFREFERENCE             (1000.0f)
#define AL_EAXREVERB_DEFAULT_LFREFERENCE         (250.0f)
#define AL_EAXREVERB_MIN_ROOM_ROLLOFF_FACTOR     (0.0f)
#define AL_EAXREVERB_MAX_ROOM_ROLLOFF_FACTOR     (10.0f)
#define AL_EAXREVERB_DEFAULT_ROOM_ROLLOFF_FACTOR (0.0f)
#define AL_EAXREVERB_MIN_DECAY_HFLIMIT           AL_FALSE
#define AL_EAXREVERB_MAX_DECAY_HFLIMIT           AL_TRUE
#define AL_EAXREVERB_DEFAULT_DECAY_HFLIMIT       AL_TRUE
#define AL_CHORUS_WAVEFORM_SINUSOID              (0)
#define AL_CHORUS_WAVEFORM_TRIANGLE              (1)
#define AL_CHORUS_MIN_WAVEFORM                   (0)
#define AL_CHORUS_MAX_WAVEFORM                   (1)
#define AL_CHORUS_DEFAULT_WAVEFORM               (1)
#define AL_CHORUS_MIN_PHASE                      (-180)
#define AL_CHORUS_MAX_PHASE                      (180)
#define AL_CHORUS_DEFAULT_PHASE                  (90)
#define AL_CHORUS_MIN_RATE                       (0.0f)
#define AL_CHORUS_MAX_RATE                       (10.0f)
#define AL_CHORUS_DEFAULT_RATE                   (1.1f)
#define AL_CHORUS_MIN_DEPTH                      (0.0f)
#define AL_CHORUS_MAX_DEPTH                      (1.0f)
#define AL_CHORUS_DEFAULT_DEPTH                  (0.1f)
#define AL_CHORUS_MIN_FEEDBACK                   (-1.0f)
#define AL_CHORUS_MAX_FEEDBACK                   (1.0f)
#define AL_CHORUS_DEFAULT_FEEDBACK               (0.25f)
#define AL_CHORUS_MIN_DELAY                      (0.0f)
#define AL_CHORUS_MAX_DELAY                      (0.016f)
#define AL_CHORUS_DEFAULT_DELAY                  (0.016f)
#define AL_DISTORTION_MIN_EDGE                   (0.0f)
#define AL_DISTORTION_MAX_EDGE                   (1.0f)
#define AL_DISTORTION_DEFAULT_EDGE               (0.2f)
#define AL_DISTORTION_MIN_GAIN                   (0.01f)
#define AL_DISTORTION_MAX_GAIN                   (1.0f)
#define AL_DISTORTION_DEFAULT_GAIN               (0.05f)
#define AL_DISTORTION_MIN_LOWPASS_CUTOFF         (80.0f)
#define AL_DISTORTION_MAX_LOWPASS_CUTOFF         (24000.0f)
#define AL_DISTORTION_DEFAULT_LOWPASS_CUTOFF     (8000.0f)
#define AL_DISTORTION_MIN_EQCENTER               (80.0f)
#define AL_DISTORTION_MAX_EQCENTER               (24000.0f)
#define AL_DISTORTION_DEFAULT_EQCENTER           (3600.0f)
#define AL_DISTORTION_MIN_EQBANDWIDTH            (80.0f)
#define AL_DISTORTION_MAX_EQBANDWIDTH            (24000.0f)
#define AL_DISTORTION_DEFAULT_EQBANDWIDTH        (3600.0f)
#define AL_ECHO_MIN_DELAY                        (0.0f)
#define AL_ECHO_MAX_DELAY                        (0.207f)
#define AL_ECHO_DEFAULT_DELAY                    (0.1f)
#define AL_ECHO_MIN_LRDELAY                      (0.0f)
#define AL_ECHO_MAX_LRDELAY                      (0.404f)
#define AL_ECHO_DEFAULT_LRDELAY                  (0.1f)
#define AL_ECHO_MIN_DAMPING                      (0.0f)
#define AL_ECHO_MAX_DAMPING                      (0.99f)
#define AL_ECHO_DEFAULT_DAMPING                  (0.5f)
#define AL_ECHO_MIN_FEEDBACK                     (0.0f)
#define AL_ECHO_MAX_FEEDBACK                     (1.0f)
#define AL_ECHO_DEFAULT_FEEDBACK                 (0.5f)
#define AL_ECHO_MIN_SPREAD                       (-1.0f)
#define AL_ECHO_MAX_SPREAD                       (1.0f)
#define AL_ECHO_DEFAULT_SPREAD                   (-1.0f)
#define AL_FLANGER_WAVEFORM_SINUSOID             (0)
#define AL_FLANGER_WAVEFORM_TRIANGLE             (1)
#define AL_FLANGER_MIN_WAVEFORM                  (0)
#define AL_FLANGER_MAX_WAVEFORM                  (1)
#define AL_FLANGER_DEFAULT_WAVEFORM              (1)
#define AL_FLANGER_MIN_PHASE                     (-180)
#define AL_FLANGER_MAX_PHASE                     (180)
#define AL_FLANGER_DEFAULT_PHASE                 (0)
#define AL_FLANGER_MIN_RATE                      (0.0f)
#define AL_FLANGER_MAX_RATE                      (10.0f)
#define AL_FLANGER_DEFAULT_RATE                  (0.27f)
#define AL_FLANGER_MIN_DEPTH                     (0.0f)
#define AL_FLANGER_MAX_DEPTH                     (1.0f)
#define AL_FLANGER_DEFAULT_DEPTH                 (1.0f)
#define AL_FLANGER_MIN_FEEDBACK                  (-1.0f)
#define AL_FLANGER_MAX_FEEDBACK                  (1.0f)
#define AL_FLANGER_DEFAULT_FEEDBACK              (-0.5f)
#define AL_FLANGER_MIN_DELAY                     (0.0f)
#define AL_FLANGER_MAX_DELAY                     (0.004f)
#define AL_FLANGER_DEFAULT_DELAY                 (0.002f)
#define AL_FREQUENCY_SHIFTER_MIN_FREQUENCY       (0.0f)
#define AL_FREQUENCY_SHIFTER_MAX_FREQUENCY       (24000.0f)
#define AL_FREQUENCY_SHIFTER_DEFAULT_FREQUENCY   (0.0f)
#define AL_FREQUENCY_SHIFTER_MIN_LEFT_DIRECTION  (0)
#define AL_FREQUENCY_SHIFTER_MAX_LEFT_DIRECTION  (2)
#define AL_FREQUENCY_SHIFTER_DEFAULT_LEFT_DIRECTION (0)
#define AL_FREQUENCY_SHIFTER_DIRECTION_DOWN      (0)
#define AL_FREQUENCY_SHIFTER_DIRECTION_UP        (1)
#define AL_FREQUENCY_SHIFTER_DIRECTION_OFF       (2)
#define AL_FREQUENCY_SHIFTER_MIN_RIGHT_DIRECTION (0)
#define AL_FREQUENCY_SHIFTER_MAX_RIGHT_DIRECTION (2)
#define AL_FREQUENCY_SHIFTER_DEFAULT_RIGHT_DIRECTION (0)
#define AL_VOCAL_MORPHER_MIN_PHONEMEA            (0)
#define AL_VOCAL_MORPHER_MAX_PHONEMEA            (29)
#define AL_VOCAL_MORPHER_DEFAULT_PHONEMEA        (0)
#define AL_VOCAL_MORPHER_MIN_PHONEMEA_COARSE_TUNING (-24)
#define AL_VOCAL_MORPHER_MAX_PHONEMEA_COARSE_TUNING (24)
#define AL_VOCAL_MORPHER_DEFAULT_PHONEMEA_COARSE_TUNING (0)
#define AL_VOCAL_MORPHER_MIN_PHONEMEB            (0)
#define AL_VOCAL_MORPHER_MAX_PHONEMEB            (29)
#define AL_VOCAL_MORPHER_DEFAULT_PHONEMEB        (10)
#define AL_VOCAL_MORPHER_MIN_PHONEMEB_COARSE_TUNING (-24)
#define AL_VOCAL_MORPHER_MAX_PHONEMEB_COARSE_TUNING (24)
#define AL_VOCAL_MORPHER_DEFAULT_PHONEMEB_COARSE_TUNING (0)
#define AL_VOCAL_MORPHER_PHONEME_A               (0)
#define AL_VOCAL_MORPHER_PHONEME_E               (1)
#define AL_VOCAL_MORPHER_PHONEME_I               (2)
#define AL_VOCAL_MORPHER_PHONEME_O               (3)
#define AL_VOCAL_MORPHER_PHONEME_U               (4)
#define AL_VOCAL_MORPHER_PHONEME_AA              (5)
#define AL_VOCAL_MORPHER_PHONEME_AE              (6)
#define AL_VOCAL_MORPHER_PHONEME_AH              (7)
#define AL_VOCAL_MORPHER_PHONEME_AO              (8)
#define AL_VOCAL_MORPHER_PHONEME_EH              (9)
#define AL_VOCAL_MORPHER_PHONEME_ER              (10)
#define AL_VOCAL_MORPHER_PHONEME_IH              (11)
#define AL_VOCAL_MORPHER_PHONEME_IY              (12)
#define AL_VOCAL_MORPHER_PHONEME_UH              (13)
#define AL_VOCAL_MORPHER_PHONEME_UW              (14)
#define AL_VOCAL_MORPHER_PHONEME_B               (15)
#define AL_VOCAL_MORPHER_PHONEME_D               (16)
#define AL_VOCAL_MORPHER_PHONEME_F               (17)
#define AL_VOCAL_MORPHER_PHONEME_G               (18)
#define AL_VOCAL_MORPHER_PHONEME_J               (19)
#define AL_VOCAL_MORPHER_PHONEME_K               (20)
#define AL_VOCAL_MORPHER_PHONEME_L               (21)
#define AL_VOCAL_MORPHER_PHONEME_M               (22)
#define AL_VOCAL_MORPHER_PHONEME_N               (23)
#define AL_VOCAL_MORPHER_PHONEME_P               (24)
#define AL_VOCAL_MORPHER_PHONEME_R               (25)
#define AL_VOCAL_MORPHER_PHONEME_S               (26)
#define AL_VOCAL_MORPHER_PHONEME_T               (27)
#define AL_VOCAL_MORPHER_PHONEME_V               (28)
#define AL_VOCAL_MORPHER_PHONEME_Z               (29)
#define AL_VOCAL_MORPHER_WAVEFORM_SINUSOID       (0)
#define AL_VOCAL_MORPHER_WAVEFORM_TRIANGLE       (1)
#define AL_VOCAL_MORPHER_WAVEFORM_SAWTOOTH       (2)
#define AL_VOCAL_MORPHER_MIN_WAVEFORM            (0)
#define AL_VOCAL_MORPHER_MAX_WAVEFORM            (2)
#define AL_VOCAL_MORPHER_DEFAULT_WAVEFORM        (0)
#define AL_VOCAL_MORPHER_MIN_RATE                (0.0f)
#define AL_VOCAL_MORPHER_MAX_RATE                (10.0f)
#define AL_VOCAL_MORPHER_DEFAULT_RATE            (1.41f)
#define AL_PITCH_SHIFTER_MIN_COARSE_TUNE         (-12)
#define AL_PITCH_SHIFTER_MAX_COARSE_TUNE         (12)
#define AL_PITCH_SHIFTER_DEFAULT_COARSE_TUNE     (12)
#define AL_PITCH_SHIFTER_MIN_FINE_TUNE           (-50)
#define AL_PITCH_SHIFTER_MAX_FINE_TUNE           (50)
#define AL_PITCH_SHIFTER_DEFAULT_FINE_TUNE       (0)
#define AL_RING_MODULATOR_MIN_FREQUENCY          (0.0f)
#define AL_RING_MODULATOR_MAX_FREQUENCY          (8000.0f)
#define AL_RING_MODULATOR_DEFAULT_FREQUENCY      (440.0f)
#define AL_RING_MODULATOR_MIN_HIGHPASS_CUTOFF    (0.0f)
#define AL_RING_MODULATOR_MAX_HIGHPASS_CUTOFF    (24000.0f)
#define AL_RING_MODULATOR_DEFAULT_HIGHPASS_CUTOFF (800.0f)
#define AL_RING_MODULATOR_SINUSOID               (0)
#define AL_RING_MODULATOR_SAWTOOTH               (1)
#define AL_RING_MODULATOR_SQUARE                 (2)
#define AL_RING_MODULATOR_MIN_WAVEFORM           (0)
#define AL_RING_MODULATOR_MAX_WAVEFORM           (2)
#define AL_RING_MODULATOR_DEFAULT_WAVEFORM       (0)
#define AL_AUTOWAH_MIN_ATTACK_TIME               (0.0001f)
#define AL_AUTOWAH_MAX_ATTACK_TIME               (1.0f)
#define AL_AUTOWAH_DEFAULT_ATTACK_TIME           (0.06f)
#define AL_AUTOWAH_MIN_RELEASE_TIME              (0.0001f)
#define AL_AUTOWAH_MAX_RELEASE_TIME              (1.0f)
#define AL_AUTOWAH_DEFAULT_RELEASE_TIME          (0.06f)
#define AL_AUTOWAH_MIN_RESONANCE                 (2.0f)
#define AL_AUTOWAH_MAX_RESONANCE                 (1000.0f)
#define AL_AUTOWAH_DEFAULT_RESONANCE             (1000.0f)
#define AL_AUTOWAH_MIN_PEAK_GAIN                 (0.00003f)
#define AL_AUTOWAH_MAX_PEAK_GAIN                 (31621.0f)
#define AL_AUTOWAH_DEFAULT_PEAK_GAIN             (11.22f)
#define AL_COMPRESSOR_MIN_ONOFF                  (0)
#define AL_COMPRESSOR_MAX_ONOFF                  (1)
#define AL_COMPRESSOR_DEFAULT_ONOFF              (1)
#define AL_EQUALIZER_MIN_LOW_GAIN                (0.126f)
#define AL_EQUALIZER_MAX_LOW_GAIN                (7.943f)
#define AL_EQUALIZER_DEFAULT_LOW_GAIN            (1.0f)
#define AL_EQUALIZER_MIN_LOW_CUTOFF              (50.0f)
#define AL_EQUALIZER_MAX_LOW_CUTOFF              (800.0f)
#define AL_EQUALIZER_DEFAULT_LOW_CUTOFF          (200.0f)
#define AL_EQUALIZER_MIN_MID1_GAIN               (0.126f)
#define AL_EQUALIZER_MAX_MID1_GAIN               (7.943f)
#define AL_EQUALIZER_DEFAULT_MID1_GAIN           (1.0f)
#define AL_EQUALIZER_MIN_MID1_CENTER             (200.0f)
#define AL_EQUALIZER_MAX_MID1_CENTER             (3000.0f)
#define AL_EQUALIZER_DEFAULT_MID1_CENTER         (500.0f)
#define AL_EQUALIZER_MIN_MID1_WIDTH              (0.01f)
#define AL_EQUALIZER_MAX_MID1_WIDTH              (1.0f)
#define AL_EQUALIZER_DEFAULT_MID1_WIDTH          (1.0f)
#define AL_EQUALIZER_MIN_MID2_GAIN               (0.126f)
#define AL_EQUALIZER_MAX_MID2_GAIN               (7.943f)
#define AL_EQUALIZER_DEFAULT_MID2_GAIN           (1.0f)
#define AL_EQUALIZER_MIN_MID2_CENTER             (1000.0f)
#define AL_EQUALIZER_MAX_MID2_CENTER             (8000.0f)
#define AL_EQUALIZER_DEFAULT_MID2_CENTER         (3000.0f)
#define AL_EQUALIZER_MIN_MID2_WIDTH              (0.01f)
#define AL_EQUALIZER_MAX_MID2_WIDTH              (1.0f)
#define AL_EQUALIZER_DEFAULT_MID2_WIDTH          (1.0f)
#define AL_EQUALIZER_MIN_HIGH_GAIN               (0.126f)
#define AL_EQUALIZER_MAX_HIGH_GAIN               (7.943f)
#define AL_EQUALIZER_DEFAULT_HIGH_GAIN           (1.0f)
#define AL_EQUALIZER_MIN_HIGH_CUTOFF             (4000.0f)
#define AL_EQUALIZER_MAX_HIGH_CUTOFF             (16000.0f)
#define AL_EQUALIZER_DEFAULT_HIGH_CUTOFF         (6000.0f)
#define AL_MIN_AIR_ABSORPTION_FACTOR             (0.0f)
#define AL_MAX_AIR_ABSORPTION_FACTOR             (10.0f)
#define AL_DEFAULT_AIR_ABSORPTION_FACTOR         (0.0f)
#define AL_MIN_ROOM_ROLLOFF_FACTOR               (0.0f)
#define AL_MAX_ROOM_ROLLOFF_FACTOR               (10.0f)
#define AL_DEFAULT_ROOM_ROLLOFF_FACTOR           (0.0f)
#define AL_MIN_CONE_OUTER_GAINHF                 (0.0f)
#define AL_MAX_CONE_OUTER_GAINHF                 (1.0f)
#define AL_DEFAULT_CONE_OUTER_GAINHF             (1.0f)
#define AL_MIN_DIRECT_FILTER_GAINHF_AUTO         AL_FALSE
#define AL_MAX_DIRECT_FILTER_GAINHF_AUTO         AL_TRUE
#define AL_DEFAULT_DIRECT_FILTER_GAINHF_AUTO     AL_TRUE
#define AL_MIN_AUXILIARY_SEND_FILTER_GAIN_AUTO   AL_FALSE
#define AL_MAX_AUXILIARY_SEND_FILTER_GAIN_AUTO   AL_TRUE
#define AL_DEFAULT_AUXILIARY_SEND_FILTER_GAIN_AUTO AL_TRUE
#define AL_MIN_AUXILIARY_SEND_FILTER_GAINHF_AUTO AL_FALSE
#define AL_MAX_AUXILIARY_SEND_FILTER_GAINHF_AUTO AL_TRUE
#define AL_DEFAULT_AUXILIARY_SEND_FILTER_GAINHF_AUTO AL_TRUE
#define AL_MIN_METERS_PER_UNIT                   FLT_MIN
#define AL_MAX_METERS_PER_UNIT                   FLT_MAX
#define AL_DEFAULT_METERS_PER_UNIT               (1.0f)
#define AL_FORMAT_IMA_ADPCM_MONO16_EXT           0x10000
#define AL_FORMAT_IMA_ADPCM_STEREO16_EXT         0x10001
#define AL_FORMAT_WAVE_EXT                       0x10002
#define AL_FORMAT_VORBIS_EXT                     0x10003
#define AL_FORMAT_QUAD8_LOKI                     0x10004
#define AL_FORMAT_QUAD16_LOKI                    0x10005
#define AL_FORMAT_MONO_FLOAT32                   0x10010
#define AL_FORMAT_STEREO_FLOAT32                 0x10011
#define AL_FORMAT_MONO_DOUBLE_EXT                0x10012
#define AL_FORMAT_STEREO_DOUBLE_EXT              0x10013
#define AL_FORMAT_MONO_MULAW_EXT                 0x10014
#define AL_FORMAT_STEREO_MULAW_EXT               0x10015
#define AL_FORMAT_MONO_ALAW_EXT                  0x10016
#define AL_FORMAT_STEREO_ALAW_EXT                0x10017
#define ALC_CHAN_MAIN_LOKI                       0x500001
#define ALC_CHAN_PCM_LOKI                        0x500002
#define ALC_CHAN_CD_LOKI                         0x500003
#define AL_FORMAT_QUAD8                          0x1204
#define AL_FORMAT_QUAD16                         0x1205
#define AL_FORMAT_QUAD32                         0x1206
#define AL_FORMAT_REAR8                          0x1207
#define AL_FORMAT_REAR16                         0x1208
#define AL_FORMAT_REAR32                         0x1209
#define AL_FORMAT_51CHN8                         0x120A
#define AL_FORMAT_51CHN16                        0x120B
#define AL_FORMAT_51CHN32                        0x120C
#define AL_FORMAT_61CHN8                         0x120D
#define AL_FORMAT_61CHN16                        0x120E
#define AL_FORMAT_61CHN32                        0x120F
#define AL_FORMAT_71CHN8                         0x1210
#define AL_FORMAT_71CHN16                        0x1211
#define AL_FORMAT_71CHN32                        0x1212
#define AL_FORMAT_MONO_MULAW                     0x10014
#define AL_FORMAT_STEREO_MULAW                   0x10015
#define AL_FORMAT_QUAD_MULAW                     0x10021
#define AL_FORMAT_REAR_MULAW                     0x10022
#define AL_FORMAT_51CHN_MULAW                    0x10023
#define AL_FORMAT_61CHN_MULAW                    0x10024
#define AL_FORMAT_71CHN_MULAW                    0x10025
#define AL_FORMAT_MONO_IMA4                      0x1300
#define AL_FORMAT_STEREO_IMA4                    0x1301
#define ALC_CONNECTED                            0x313
#define AL_SOURCE_DISTANCE_MODEL                 0x200
#define AL_BYTE_RW_OFFSETS_SOFT                  0x1031
#define AL_SAMPLE_RW_OFFSETS_SOFT                0x1032
#define AL_LOOP_POINTS_SOFT                      0x2015
#define AL_EXT_FOLDBACK_NAME                     "AL_EXT_FOLDBACK"
#define AL_FOLDBACK_EVENT_BLOCK                  0x4112
#define AL_FOLDBACK_EVENT_START                  0x4111
#define AL_FOLDBACK_EVENT_STOP                   0x4113
#define AL_FOLDBACK_MODE_MONO                    0x4101
#define AL_FOLDBACK_MODE_STEREO                  0x4102
#define AL_DEDICATED_GAIN                        0x0001
#define AL_EFFECT_DEDICATED_DIALOGUE             0x9001
#define AL_EFFECT_DEDICATED_LOW_FREQUENCY_EFFECT 0x9000
#define AL_MONO_SOFT                             0x1500
#define AL_STEREO_SOFT                           0x1501
#define AL_REAR_SOFT                             0x1502
#define AL_QUAD_SOFT                             0x1503
#define AL_5POINT1_SOFT                          0x1504
#define AL_6POINT1_SOFT                          0x1505
#define AL_7POINT1_SOFT                          0x1506
#define AL_BYTE_SOFT                             0x1400
#define AL_UNSIGNED_BYTE_SOFT                    0x1401
#define AL_SHORT_SOFT                            0x1402
#define AL_UNSIGNED_SHORT_SOFT                   0x1403
#define AL_INT_SOFT                              0x1404
#define AL_UNSIGNED_INT_SOFT                     0x1405
#define AL_FLOAT_SOFT                            0x1406
#define AL_DOUBLE_SOFT                           0x1407
#define AL_BYTE3_SOFT                            0x1408
#define AL_UNSIGNED_BYTE3_SOFT                   0x1409
#define AL_MONO8_SOFT                            0x1100
#define AL_MONO16_SOFT                           0x1101
#define AL_MONO32F_SOFT                          0x10010
#define AL_STEREO8_SOFT                          0x1102
#define AL_STEREO16_SOFT                         0x1103
#define AL_STEREO32F_SOFT                        0x10011
#define AL_QUAD8_SOFT                            0x1204
#define AL_QUAD16_SOFT                           0x1205
#define AL_QUAD32F_SOFT                          0x1206
#define AL_REAR8_SOFT                            0x1207
#define AL_REAR16_SOFT                           0x1208
#define AL_REAR32F_SOFT                          0x1209
#define AL_5POINT1_8_SOFT                        0x120A
#define AL_5POINT1_16_SOFT                       0x120B
#define AL_5POINT1_32F_SOFT                      0x120C
#define AL_6POINT1_8_SOFT                        0x120D
#define AL_6POINT1_16_SOFT                       0x120E
#define AL_6POINT1_32F_SOFT                      0x120F
#define AL_7POINT1_8_SOFT                        0x1210
#define AL_7POINT1_16_SOFT                       0x1211
#define AL_7POINT1_32F_SOFT                      0x1212
#define AL_INTERNAL_FORMAT_SOFT                  0x2008
#define AL_BYTE_LENGTH_SOFT                      0x2009
#define AL_SAMPLE_LENGTH_SOFT                    0x200A
#define AL_SEC_LENGTH_SOFT                       0x200B
#define AL_DIRECT_CHANNELS_SOFT                  0x1033
#define ALC_FORMAT_CHANNELS_SOFT                 0x1990
#define ALC_FORMAT_TYPE_SOFT                     0x1991
#define ALC_BYTE_SOFT                            0x1400
#define ALC_UNSIGNED_BYTE_SOFT                   0x1401
#define ALC_SHORT_SOFT                           0x1402
#define ALC_UNSIGNED_SHORT_SOFT                  0x1403
#define ALC_INT_SOFT                             0x1404
#define ALC_UNSIGNED_INT_SOFT                    0x1405
#define ALC_FLOAT_SOFT                           0x1406
#define ALC_MONO_SOFT                            0x1500
#define ALC_STEREO_SOFT                          0x1501
#define ALC_QUAD_SOFT                            0x1503
#define ALC_5POINT1_SOFT                         0x1504
#define ALC_6POINT1_SOFT                         0x1505
#define ALC_7POINT1_SOFT                         0x1506
#define AL_STEREO_ANGLES                         0x1030
#define AL_SOURCE_RADIUS                         0x1031
#define AL_SAMPLE_OFFSET_LATENCY_SOFT            0x1200
#define AL_SEC_OFFSET_LATENCY_SOFT               0x1201
#define ALC_DEFAULT_FILTER_ORDER                 0x1100
#define AL_DEFERRED_UPDATES_SOFT                 0xC002
#define AL_UNPACK_BLOCK_ALIGNMENT_SOFT           0x200C
#define AL_PACK_BLOCK_ALIGNMENT_SOFT             0x200D
#define AL_FORMAT_MONO_MSADPCM_SOFT              0x1302
#define AL_FORMAT_STEREO_MSADPCM_SOFT            0x1303
#define ALC_FALSE                                0
#define ALC_TRUE                                 1
#define ALC_FREQUENCY                            0x1007
#define ALC_REFRESH                              0x1008
#define ALC_SYNC                                 0x1009
#define ALC_MONO_SOURCES                         0x1010
#define ALC_STEREO_SOURCES                       0x1011
#define ALC_NO_ERROR                             0
#define ALC_INVALID_DEVICE                       0xA001
#define ALC_INVALID_CONTEXT                      0xA002
#define ALC_INVALID_ENUM                         0xA003
#define ALC_INVALID_VALUE                        0xA004
#define ALC_OUT_OF_MEMORY                        0xA005
#define ALC_MAJOR_VERSION                        0x1000
#define ALC_MINOR_VERSION                        0x1001
#define ALC_ATTRIBUTES_SIZE                      0x1002
#define ALC_ALL_ATTRIBUTES                       0x1003
#define ALC_DEFAULT_DEVICE_SPECIFIER             0x1004
#define ALC_DEVICE_SPECIFIER                     0x1005
#define ALC_EXTENSIONS                           0x1006
#define ALC_EXT_CAPTURE 1
#define ALC_CAPTURE_DEVICE_SPECIFIER             0x310
#define ALC_CAPTURE_DEFAULT_DEVICE_SPECIFIER     0x311
#define ALC_CAPTURE_SAMPLES                      0x312
#define ALC_ENUMERATE_ALL_EXT 1
#define ALC_DEFAULT_ALL_DEVICES_SPECIFIER        0x1012
#define ALC_ALL_DEVICES_SPECIFIER                0x1013
#define ALC_EXT_EFX_NAME                         "ALC_EXT_EFX"
#define ALC_EFX_MAJOR_VERSION                    0x20001
#define ALC_EFX_MINOR_VERSION                    0x20002
#define ALC_MAX_AUXILIARY_SENDS                  0x20003

AL_API void (AL_APIENTRY *alEnable)(ALenum capability);
AL_API void (AL_APIENTRY *alDisable)(ALenum capability);
AL_API ALboolean (AL_APIENTRY *alIsEnabled)(ALenum capability);
AL_API const ALchar* (AL_APIENTRY *alGetString)(ALenum param);
AL_API void (AL_APIENTRY *alGetBooleanv)(ALenum param, ALboolean *values);
AL_API void (AL_APIENTRY *alGetIntegerv)(ALenum param, ALint *values);
AL_API void (AL_APIENTRY *alGetFloatv)(ALenum param, ALfloat *values);
AL_API void (AL_APIENTRY *alGetDoublev)(ALenum param, ALdouble *values);
AL_API ALboolean (AL_APIENTRY *alGetBoolean)(ALenum param);
AL_API ALint (AL_APIENTRY *alGetInteger)(ALenum param);
AL_API ALfloat (AL_APIENTRY *alGetFloat)(ALenum param);
AL_API ALdouble (AL_APIENTRY *alGetDouble)(ALenum param);
AL_API ALenum (AL_APIENTRY *alGetError)(void);
AL_API ALboolean (AL_APIENTRY *alIsExtensionPresent)(const ALchar *extname);
AL_API void* (AL_APIENTRY *alGetProcAddress)(const ALchar *fname);
AL_API ALenum (AL_APIENTRY *alGetEnumValue)(const ALchar *ename);
AL_API void (AL_APIENTRY *alListenerf)(ALenum param, ALfloat value);
AL_API void (AL_APIENTRY *alListener3f)(ALenum param, ALfloat value1, ALfloat value2, ALfloat value3);
AL_API void (AL_APIENTRY *alListenerfv)(ALenum param, const ALfloat *values);
AL_API void (AL_APIENTRY *alListeneri)(ALenum param, ALint value);
AL_API void (AL_APIENTRY *alListener3i)(ALenum param, ALint value1, ALint value2, ALint value3);
AL_API void (AL_APIENTRY *alListeneriv)(ALenum param, const ALint *values);
AL_API void (AL_APIENTRY *alGetListenerf)(ALenum param, ALfloat *value);
AL_API void (AL_APIENTRY *alGetListener3f)(ALenum param, ALfloat *value1, ALfloat *value2, ALfloat *value3);
AL_API void (AL_APIENTRY *alGetListenerfv)(ALenum param, ALfloat *values);
AL_API void (AL_APIENTRY *alGetListeneri)(ALenum param, ALint *value);
AL_API void (AL_APIENTRY *alGetListener3i)(ALenum param, ALint *value1, ALint *value2, ALint *value3);
AL_API void (AL_APIENTRY *alGetListeneriv)(ALenum param, ALint *values);
AL_API void (AL_APIENTRY *alGenSources)(ALsizei n, ALuint *sources);
AL_API void (AL_APIENTRY *alDeleteSources)(ALsizei n, const ALuint *sources);
AL_API ALboolean (AL_APIENTRY *alIsSource)(ALuint source);
AL_API void (AL_APIENTRY *alSourcef)(ALuint source, ALenum param, ALfloat value);
AL_API void (AL_APIENTRY *alSource3f)(ALuint source, ALenum param, ALfloat value1, ALfloat value2, ALfloat value3);
AL_API void (AL_APIENTRY *alSourcefv)(ALuint source, ALenum param, const ALfloat *values);
AL_API void (AL_APIENTRY *alSourcei)(ALuint source, ALenum param, ALint value);
AL_API void (AL_APIENTRY *alSource3i)(ALuint source, ALenum param, ALint value1, ALint value2, ALint value3);
AL_API void (AL_APIENTRY *alSourceiv)(ALuint source, ALenum param, const ALint *values);
AL_API void (AL_APIENTRY *alGetSourcef)(ALuint source, ALenum param, ALfloat *value);
AL_API void (AL_APIENTRY *alGetSource3f)(ALuint source, ALenum param, ALfloat *value1, ALfloat *value2, ALfloat *value3);
AL_API void (AL_APIENTRY *alGetSourcefv)(ALuint source, ALenum param, ALfloat *values);
AL_API void (AL_APIENTRY *alGetSourcei)(ALuint source,  ALenum param, ALint *value);
AL_API void (AL_APIENTRY *alGetSource3i)(ALuint source, ALenum param, ALint *value1, ALint *value2, ALint *value3);
AL_API void (AL_APIENTRY *alGetSourceiv)(ALuint source,  ALenum param, ALint *values);
AL_API void (AL_APIENTRY *alSourcePlayv)(ALsizei n, const ALuint *sources);
AL_API void (AL_APIENTRY *alSourceStopv)(ALsizei n, const ALuint *sources);
AL_API void (AL_APIENTRY *alSourceRewindv)(ALsizei n, const ALuint *sources);
AL_API void (AL_APIENTRY *alSourcePausev)(ALsizei n, const ALuint *sources);
AL_API void (AL_APIENTRY *alSourcePlay)(ALuint source);
AL_API void (AL_APIENTRY *alSourceStop)(ALuint source);
AL_API void (AL_APIENTRY *alSourceRewind)(ALuint source);
AL_API void (AL_APIENTRY *alSourcePause)(ALuint source);
AL_API void (AL_APIENTRY *alSourceQueueBuffers)(ALuint source, ALsizei nb, const ALuint *buffers);
AL_API void (AL_APIENTRY *alSourceUnqueueBuffers)(ALuint source, ALsizei nb, ALuint *buffers);
AL_API void (AL_APIENTRY *alGenBuffers)(ALsizei n, ALuint *buffers);
AL_API void (AL_APIENTRY *alDeleteBuffers)(ALsizei n, const ALuint *buffers);
AL_API ALboolean (AL_APIENTRY *alIsBuffer)(ALuint buffer);
AL_API void (AL_APIENTRY *alBufferData)(ALuint buffer, ALenum format, const ALvoid *data, ALsizei size, ALsizei freq);
AL_API void (AL_APIENTRY *alBufferf)(ALuint buffer, ALenum param, ALfloat value);
AL_API void (AL_APIENTRY *alBuffer3f)(ALuint buffer, ALenum param, ALfloat value1, ALfloat value2, ALfloat value3);
AL_API void (AL_APIENTRY *alBufferfv)(ALuint buffer, ALenum param, const ALfloat *values);
AL_API void (AL_APIENTRY *alBufferi)(ALuint buffer, ALenum param, ALint value);
AL_API void (AL_APIENTRY *alBuffer3i)(ALuint buffer, ALenum param, ALint value1, ALint value2, ALint value3);
AL_API void (AL_APIENTRY *alBufferiv)(ALuint buffer, ALenum param, const ALint *values);
AL_API void (AL_APIENTRY *alGetBufferf)(ALuint buffer, ALenum param, ALfloat *value);
AL_API void (AL_APIENTRY *alGetBuffer3f)(ALuint buffer, ALenum param, ALfloat *value1, ALfloat *value2, ALfloat *value3);
AL_API void (AL_APIENTRY *alGetBufferfv)(ALuint buffer, ALenum param, ALfloat *values);
AL_API void (AL_APIENTRY *alGetBufferi)(ALuint buffer, ALenum param, ALint *value);
AL_API void (AL_APIENTRY *alGetBuffer3i)(ALuint buffer, ALenum param, ALint *value1, ALint *value2, ALint *value3);
AL_API void (AL_APIENTRY *alGetBufferiv)(ALuint buffer, ALenum param, ALint *values);
AL_API void (AL_APIENTRY *alDopplerFactor)(ALfloat value);
AL_API void (AL_APIENTRY *alDopplerVelocity)(ALfloat value);
AL_API void (AL_APIENTRY *alSpeedOfSound)(ALfloat value);
AL_API void (AL_APIENTRY *alDistanceModel)(ALenum distanceModel);

ALC_API ALCdevice* (ALC_APIENTRY *alcOpenDevice)(const ALCchar *devicename);
ALC_API ALCboolean (ALC_APIENTRY *alcCloseDevice)(ALCdevice *device);
ALC_API ALCenum (ALC_APIENTRY *alcGetError)(ALCdevice *device);
ALC_API ALCboolean (ALC_APIENTRY *alcIsExtensionPresent)(ALCdevice *device, const ALCchar *extname);
ALC_API void*      (ALC_APIENTRY *alcGetProcAddress)(ALCdevice *device, const ALCchar *funcname);
ALC_API ALCenum    (ALC_APIENTRY *alcGetEnumValue)(ALCdevice *device, const ALCchar *enumname);
ALC_API const ALCchar* (ALC_APIENTRY *alcGetString)(ALCdevice *device, ALCenum param);
ALC_API void           (ALC_APIENTRY *alcGetIntegerv)(ALCdevice *device, ALCenum param, ALCsizei size, ALCint *values);
ALC_API ALCcontext* (ALC_APIENTRY *alcCreateContext)(ALCdevice *device, const ALCint* attrlist);

ALC_API ALCboolean  (ALC_APIENTRY *alcMakeContextCurrent)(ALCcontext *context);
ALC_API void        (ALC_APIENTRY *alcProcessContext)(ALCcontext *context);
ALC_API ALCcontext* (ALC_APIENTRY *alcGetCurrentContext)(void);
ALC_API ALCdevice*  (ALC_APIENTRY *alcGetContextsDevice)(ALCcontext *context);
ALC_API void        (ALC_APIENTRY *alcSuspendContext)(ALCcontext *context);
ALC_API void        (ALC_APIENTRY *alcDestroyContext)(ALCcontext *context);

ALC_API ALCdevice* (ALC_APIENTRY *alcCaptureOpenDevice)(const ALCchar *devicename, ALCuint frequency, ALCenum format, ALCsizei buffersize);
ALC_API ALCboolean (ALC_APIENTRY *alcCaptureCloseDevice)(ALCdevice *device);
ALC_API void       (ALC_APIENTRY *alcCaptureStart)(ALCdevice *device);
ALC_API void       (ALC_APIENTRY *alcCaptureStop)(ALCdevice *device);
ALC_API void       (ALC_APIENTRY *alcCaptureSamples)(ALCdevice *device, ALCvoid *buffer, ALCsizei samples);

// AL_EXT_STATIC_BUFFER
AL_API ALvoid (AL_APIENTRY *alBufferDataStatic)(const ALint buffer, ALenum format, ALvoid *data, ALsizei len, ALsizei freq);

// ALC_EXT_thread_local_context
ALC_API ALCboolean  (ALC_APIENTRY *alcSetThreadContext)(ALCcontext *context);
ALC_API ALCcontext* (ALC_APIENTRY *alcGetThreadContext)(void);

// AL_SOFT_buffer_sub_data
AL_API ALvoid (AL_APIENTRY *alBufferSubDataSOFT)(ALuint buffer,ALenum format,const ALvoid *data,ALsizei offset,ALsizei length);

// AL_EXT_FOLDBACK
AL_API void (AL_APIENTRY *alRequestFoldbackStart)(ALenum mode,ALsizei count,ALsizei length,ALfloat *mem,LPALFOLDBACKCALLBACK callback);
AL_API void (AL_APIENTRY *alRequestFoldbackStop)(void);

// AL_SOFT_buffer_samples
AL_API void (AL_APIENTRY *alBufferSamplesSOFT)(ALuint buffer, ALuint samplerate, ALenum internalformat, ALsizei samples, ALenum channels, ALenum type, const ALvoid *data);
AL_API void (AL_APIENTRY *alBufferSubSamplesSOFT)(ALuint buffer, ALsizei offset, ALsizei samples, ALenum channels, ALenum type, const ALvoid *data);
AL_API void (AL_APIENTRY *alGetBufferSamplesSOFT)(ALuint buffer, ALsizei offset, ALsizei samples, ALenum channels, ALenum type, ALvoid *data);
AL_API ALboolean (AL_APIENTRY *alIsBufferFormatSupportedSOFT)(ALenum format);

// ALC_SOFT_loopback
ALC_API ALCdevice* (ALC_APIENTRY *alcLoopbackOpenDeviceSOFT)(const ALCchar *deviceName);
ALC_API ALCboolean (ALC_APIENTRY *alcIsRenderFormatSupportedSOFT)(ALCdevice *device, ALCsizei freq, ALCenum channels, ALCenum type);
ALC_API void (ALC_APIENTRY *alcRenderSamplesSOFT)(ALCdevice *device, ALCvoid *buffer, ALCsizei samples);

// AL_SOFT_source_latency
AL_API void (AL_APIENTRY *alSourcedSOFT)(ALuint source, ALenum param, ALdouble value);
AL_API void (AL_APIENTRY *alSource3dSOFT)(ALuint source, ALenum param, ALdouble value1, ALdouble value2, ALdouble value3);
AL_API void (AL_APIENTRY *alSourcedvSOFT)(ALuint source, ALenum param, const ALdouble *values);
AL_API void (AL_APIENTRY *alGetSourcedSOFT)(ALuint source, ALenum param, ALdouble *value);
AL_API void (AL_APIENTRY *alGetSource3dSOFT)(ALuint source, ALenum param, ALdouble *value1, ALdouble *value2, ALdouble *value3);
AL_API void (AL_APIENTRY *alGetSourcedvSOFT)(ALuint source, ALenum param, ALdouble *values);
AL_API void (AL_APIENTRY *alSourcei64SOFT)(ALuint source, ALenum param, ALint64SOFT value);
AL_API void (AL_APIENTRY *alSource3i64SOFT)(ALuint source, ALenum param, ALint64SOFT value1, ALint64SOFT value2, ALint64SOFT value3);
AL_API void (AL_APIENTRY *alSourcei64vSOFT)(ALuint source, ALenum param, const ALint64SOFT *values);
AL_API void (AL_APIENTRY *alGetSourcei64SOFT)(ALuint source, ALenum param, ALint64SOFT *value);
AL_API void (AL_APIENTRY *alGetSource3i64SOFT)(ALuint source, ALenum param, ALint64SOFT *value1, ALint64SOFT *value2, ALint64SOFT *value3);
AL_API void (AL_APIENTRY *alGetSourcei64vSOFT)(ALuint source, ALenum param, ALint64SOFT *values);

// AL_SOFT_deferred_updates
AL_API ALvoid (AL_APIENTRY *alDeferUpdatesSOFT)(void);
AL_API ALvoid (AL_APIENTRY *alProcessUpdatesSOFT)(void);

// ALC_SOFT_pause_device
ALC_API void (ALC_APIENTRY *alcDevicePauseSOFT)(ALCdevice *device);
ALC_API void (ALC_APIENTRY *alcDeviceResumeSOFT)(ALCdevice *device);

// ALC_EXT_EFX
AL_API ALvoid (AL_APIENTRY *alGenEffects)(ALsizei n, ALuint *effects);
AL_API ALvoid (AL_APIENTRY *alDeleteEffects)(ALsizei n, const ALuint *effects);
AL_API ALboolean (AL_APIENTRY *alIsEffect)(ALuint effect);
AL_API ALvoid (AL_APIENTRY *alEffecti)(ALuint effect, ALenum param, ALint iValue);
AL_API ALvoid (AL_APIENTRY *alEffectiv)(ALuint effect, ALenum param, const ALint *piValues);
AL_API ALvoid (AL_APIENTRY *alEffectf)(ALuint effect, ALenum param, ALfloat flValue);
AL_API ALvoid (AL_APIENTRY *alEffectfv)(ALuint effect, ALenum param, const ALfloat *pflValues);
AL_API ALvoid (AL_APIENTRY *alGetEffecti)(ALuint effect, ALenum param, ALint *piValue);
AL_API ALvoid (AL_APIENTRY *alGetEffectiv)(ALuint effect, ALenum param, ALint *piValues);
AL_API ALvoid (AL_APIENTRY *alGetEffectf)(ALuint effect, ALenum param, ALfloat *pflValue);
AL_API ALvoid (AL_APIENTRY *alGetEffectfv)(ALuint effect, ALenum param, ALfloat *pflValues);
AL_API ALvoid (AL_APIENTRY *alGenFilters)(ALsizei n, ALuint *filters);
AL_API ALvoid (AL_APIENTRY *alDeleteFilters)(ALsizei n, const ALuint *filters);
AL_API ALboolean (AL_APIENTRY *alIsFilter)(ALuint filter);
AL_API ALvoid (AL_APIENTRY *alFilteri)(ALuint filter, ALenum param, ALint iValue);
AL_API ALvoid (AL_APIENTRY *alFilteriv)(ALuint filter, ALenum param, const ALint *piValues);
AL_API ALvoid (AL_APIENTRY *alFilterf)(ALuint filter, ALenum param, ALfloat flValue);
AL_API ALvoid (AL_APIENTRY *alFilterfv)(ALuint filter, ALenum param, const ALfloat *pflValues);
AL_API ALvoid (AL_APIENTRY *alGetFilteri)(ALuint filter, ALenum param, ALint *piValue);
AL_API ALvoid (AL_APIENTRY *alGetFilteriv)(ALuint filter, ALenum param, ALint *piValues);
AL_API ALvoid (AL_APIENTRY *alGetFilterf)(ALuint filter, ALenum param, ALfloat *pflValue);
AL_API ALvoid (AL_APIENTRY *alGetFilterfv)(ALuint filter, ALenum param, ALfloat *pflValues);
AL_API ALvoid (AL_APIENTRY *alGenAuxiliaryEffectSlots)(ALsizei n, ALuint *effectslots);
AL_API ALvoid (AL_APIENTRY *alDeleteAuxiliaryEffectSlots)(ALsizei n, const ALuint *effectslots);
AL_API ALboolean (AL_APIENTRY *alIsAuxiliaryEffectSlot)(ALuint effectslot);
AL_API ALvoid (AL_APIENTRY *alAuxiliaryEffectSloti)(ALuint effectslot, ALenum param, ALint iValue);
AL_API ALvoid (AL_APIENTRY *alAuxiliaryEffectSlotiv)(ALuint effectslot, ALenum param, const ALint *piValues);
AL_API ALvoid (AL_APIENTRY *alAuxiliaryEffectSlotf)(ALuint effectslot, ALenum param, ALfloat flValue);
AL_API ALvoid (AL_APIENTRY *alAuxiliaryEffectSlotfv)(ALuint effectslot, ALenum param, const ALfloat *pflValues);
AL_API ALvoid (AL_APIENTRY *alGetAuxiliaryEffectSloti)(ALuint effectslot, ALenum param, ALint *piValue);
AL_API ALvoid (AL_APIENTRY *alGetAuxiliaryEffectSlotiv)(ALuint effectslot, ALenum param, ALint *piValues);
AL_API ALvoid (AL_APIENTRY *alGetAuxiliaryEffectSlotf)(ALuint effectslot, ALenum param, ALfloat *pflValue);
AL_API ALvoid (AL_APIENTRY *alGetAuxiliaryEffectSlotfv)(ALuint effectslot, ALenum param, ALfloat *pflValues);
}

#endif