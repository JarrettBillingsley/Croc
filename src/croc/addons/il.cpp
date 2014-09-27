#include <type_traits>
#include <tuple>

#include "croc/ext/il/il.h"
#include "croc/ext/il/ilu.h"

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/oscompat.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
#ifndef CROC_DEVIL_ADDON
void initDevilLib(CrocThread* t)
{
	croc_eh_throwStd(t, "ApiError", "Attempting to load the DevIL library, but it was not compiled in");
}
#else
namespace
{

#ifdef CROC_BUILTIN_DOCS
const char* moduleDocs = DModule("devil")
R"()";
#endif

// =====================================================================================================================
// DevIL shared lib loading

#ifdef _WIN32
const char* ilSharedLibPaths[] = { "devil.dll", nullptr };
const char* iluSharedLibPaths[] = { "ilu.dll", nullptr };
#elif defined(__APPLE__) && defined(__MACH__)
const char* ilSharedLibPaths[] = { "libIL.dylib", nullptr };
const char* iluSharedLibPaths[] = { "libILU.dylib", nullptr };
#else
const char* ilSharedLibPaths[] = { "libIL.so", "/usr/local/lib/libIL.so", nullptr };
const char* iluSharedLibPaths[] = { "libILU.so", "/usr/local/lib/libILU.so", nullptr };
#endif

void loadSharedLib(CrocThread* t)
{
	if(ilInit != nullptr)
		return;

	auto il = oscompat::openLibraryMulti(t, ilSharedLibPaths);

	if(il == nullptr)
		croc_eh_throwStd(t, "OSException", "Cannot find the DevIL shared library");

	auto ilu = oscompat::openLibraryMulti(t, iluSharedLibPaths);

	if(ilu == nullptr)
	{
		oscompat::closeLibrary(t, il);
		croc_eh_throwStd(t, "OSException", "Cannot find the ILU shared library");
	}

	oscompat::getProc(t, il, "ilGetInteger", ilGetInteger);

	auto dllVersion = ilGetInteger(IL_VERSION_NUM);

	if(dllVersion < IL_VERSION)
	{
		oscompat::closeLibrary(t, il);
		oscompat::closeLibrary(t, ilu);
		croc_eh_throwStd(t, "OSException", "DevIL shared library version (%d) is older than needed (%d)",
			dllVersion, IL_VERSION);
	}

	oscompat::getProc(t, ilu, "iluGetInteger", iluGetInteger);

	dllVersion = iluGetInteger(ILU_VERSION_NUM);

	if(dllVersion < ILU_VERSION)
	{
		oscompat::closeLibrary(t, il);
		oscompat::closeLibrary(t, ilu);
		croc_eh_throwStd(t, "OSException", "DevIL ILU shared library version (%d) is older than needed (%d)",
			dllVersion, ILU_VERSION);
	}

#ifdef _WIN32
	// For some mysterious reason, these two functions are exported with stdcall mangling and I have no idea if this is
	// just a bug or what thanks to the completely nonexistent DevIL documentation
	oscompat::getProc(t, il, "_ilFlipSurfaceDxtcData@0", ilFlipSurfaceDxtcData);
	oscompat::getProc(t, il, "_ilInvertSurfaceDxtcDataAlpha@0", ilInvertSurfaceDxtcDataAlpha);
#else
	oscompat::getProc(t, il, "ilFlipSurfaceDxtcData", ilFlipSurfaceDxtcData);
	oscompat::getProc(t, il, "ilInvertSurfaceDxtcDataAlpha", ilInvertSurfaceDxtcDataAlpha);
#endif

	oscompat::getProc(t, il, "ilActiveFace", ilActiveFace);
	oscompat::getProc(t, il, "ilActiveImage", ilActiveImage);
	oscompat::getProc(t, il, "ilActiveLayer", ilActiveLayer);
	oscompat::getProc(t, il, "ilActiveMipmap", ilActiveMipmap);
	oscompat::getProc(t, il, "ilApplyPal", ilApplyPal);
	oscompat::getProc(t, il, "ilApplyProfile", ilApplyProfile);
	oscompat::getProc(t, il, "ilBindImage", ilBindImage);
	oscompat::getProc(t, il, "ilBlit", ilBlit);
	oscompat::getProc(t, il, "ilClampNTSC", ilClampNTSC);
	oscompat::getProc(t, il, "ilClearColour", ilClearColour);
	oscompat::getProc(t, il, "ilClearImage", ilClearImage);
	oscompat::getProc(t, il, "ilCloneCurImage", ilCloneCurImage);
	oscompat::getProc(t, il, "ilCompressDXT", ilCompressDXT);
	oscompat::getProc(t, il, "ilCompressFunc", ilCompressFunc);
	oscompat::getProc(t, il, "ilConvertImage", ilConvertImage);
	oscompat::getProc(t, il, "ilConvertPal", ilConvertPal);
	oscompat::getProc(t, il, "ilCopyImage", ilCopyImage);
	oscompat::getProc(t, il, "ilCopyPixels", ilCopyPixels);
	oscompat::getProc(t, il, "ilCreateSubImage", ilCreateSubImage);
	oscompat::getProc(t, il, "ilDefaultImage", ilDefaultImage);
	oscompat::getProc(t, il, "ilDeleteImage", ilDeleteImage);
	oscompat::getProc(t, il, "ilDeleteImages", ilDeleteImages);
	oscompat::getProc(t, il, "ilDetermineType", ilDetermineType);
	oscompat::getProc(t, il, "ilDetermineTypeF", ilDetermineTypeF);
	oscompat::getProc(t, il, "ilDetermineTypeL", ilDetermineTypeL);
	oscompat::getProc(t, il, "ilDisable", ilDisable);
	oscompat::getProc(t, il, "ilDxtcDataToImage", ilDxtcDataToImage);
	oscompat::getProc(t, il, "ilDxtcDataToSurface", ilDxtcDataToSurface);
	oscompat::getProc(t, il, "ilEnable", ilEnable);
	oscompat::getProc(t, il, "ilFormatFunc", ilFormatFunc);
	oscompat::getProc(t, il, "ilGenImages", ilGenImages);
	oscompat::getProc(t, il, "ilGenImage", ilGenImage);
	oscompat::getProc(t, il, "ilGetAlpha", ilGetAlpha);
	oscompat::getProc(t, il, "ilGetBoolean", ilGetBoolean);
	oscompat::getProc(t, il, "ilGetBooleanv", ilGetBooleanv);
	oscompat::getProc(t, il, "ilGetData", ilGetData);
	oscompat::getProc(t, il, "ilGetDXTCData", ilGetDXTCData);
	oscompat::getProc(t, il, "ilGetError", ilGetError);
	oscompat::getProc(t, il, "ilGetIntegerv", ilGetIntegerv);
	oscompat::getProc(t, il, "ilGetLumpPos", ilGetLumpPos);
	oscompat::getProc(t, il, "ilGetPalette", ilGetPalette);
	oscompat::getProc(t, il, "ilGetString", ilGetString);
	oscompat::getProc(t, il, "ilHint", ilHint);
	oscompat::getProc(t, il, "ilInit", ilInit);
	oscompat::getProc(t, il, "ilImageToDxtcData", ilImageToDxtcData);
	oscompat::getProc(t, il, "ilIsDisabled", ilIsDisabled);
	oscompat::getProc(t, il, "ilIsEnabled", ilIsEnabled);
	oscompat::getProc(t, il, "ilIsImage", ilIsImage);
	oscompat::getProc(t, il, "ilIsValid", ilIsValid);
	oscompat::getProc(t, il, "ilIsValidF", ilIsValidF);
	oscompat::getProc(t, il, "ilIsValidL", ilIsValidL);
	oscompat::getProc(t, il, "ilKeyColour", ilKeyColour);
	oscompat::getProc(t, il, "ilLoad", ilLoad);
	oscompat::getProc(t, il, "ilLoadF", ilLoadF);
	oscompat::getProc(t, il, "ilLoadImage", ilLoadImage);
	oscompat::getProc(t, il, "ilLoadL", ilLoadL);
	oscompat::getProc(t, il, "ilLoadPal", ilLoadPal);
	oscompat::getProc(t, il, "ilModAlpha", ilModAlpha);
	oscompat::getProc(t, il, "ilOriginFunc", ilOriginFunc);
	oscompat::getProc(t, il, "ilOverlayImage", ilOverlayImage);
	oscompat::getProc(t, il, "ilPopAttrib", ilPopAttrib);
	oscompat::getProc(t, il, "ilPushAttrib", ilPushAttrib);
	oscompat::getProc(t, il, "ilRegisterFormat", ilRegisterFormat);
	oscompat::getProc(t, il, "ilRegisterLoad", ilRegisterLoad);
	oscompat::getProc(t, il, "ilRegisterMipNum", ilRegisterMipNum);
	oscompat::getProc(t, il, "ilRegisterNumFaces", ilRegisterNumFaces);
	oscompat::getProc(t, il, "ilRegisterNumImages", ilRegisterNumImages);
	oscompat::getProc(t, il, "ilRegisterOrigin", ilRegisterOrigin);
	oscompat::getProc(t, il, "ilRegisterPal", ilRegisterPal);
	oscompat::getProc(t, il, "ilRegisterSave", ilRegisterSave);
	oscompat::getProc(t, il, "ilRegisterType", ilRegisterType);
	oscompat::getProc(t, il, "ilRemoveLoad", ilRemoveLoad);
	oscompat::getProc(t, il, "ilRemoveSave", ilRemoveSave);
	oscompat::getProc(t, il, "ilResetRead", ilResetRead);
	oscompat::getProc(t, il, "ilResetWrite", ilResetWrite);
	oscompat::getProc(t, il, "ilSave", ilSave);
	oscompat::getProc(t, il, "ilSaveF", ilSaveF);
	oscompat::getProc(t, il, "ilSaveImage", ilSaveImage);
	oscompat::getProc(t, il, "ilSaveL", ilSaveL);
	oscompat::getProc(t, il, "ilSavePal", ilSavePal);
	oscompat::getProc(t, il, "ilSetAlpha", ilSetAlpha);
	oscompat::getProc(t, il, "ilSetData", ilSetData);
	oscompat::getProc(t, il, "ilSetDuration", ilSetDuration);
	oscompat::getProc(t, il, "ilSetInteger", ilSetInteger);
	oscompat::getProc(t, il, "ilSetMemory", ilSetMemory);
	oscompat::getProc(t, il, "ilSetPixels", ilSetPixels);
	oscompat::getProc(t, il, "ilSetRead", ilSetRead);
	oscompat::getProc(t, il, "ilSetString", ilSetString);
	oscompat::getProc(t, il, "ilSetWrite", ilSetWrite);
	oscompat::getProc(t, il, "ilShutDown", ilShutDown);
	oscompat::getProc(t, il, "ilSurfaceToDxtcData", ilSurfaceToDxtcData);
	oscompat::getProc(t, il, "ilTexImage", ilTexImage);
	oscompat::getProc(t, il, "ilTexImageDxtc", ilTexImageDxtc);
	oscompat::getProc(t, il, "ilTypeFromExt", ilTypeFromExt);
	oscompat::getProc(t, il, "ilTypeFunc", ilTypeFunc);
	oscompat::getProc(t, il, "ilLoadData", ilLoadData);
	oscompat::getProc(t, il, "ilLoadDataF", ilLoadDataF);
	oscompat::getProc(t, il, "ilLoadDataL", ilLoadDataL);
	oscompat::getProc(t, il, "ilSaveData", ilSaveData);

	oscompat::getProc(t, ilu, "iluAlienify", iluAlienify);
	oscompat::getProc(t, ilu, "iluBlurAvg", iluBlurAvg);
	oscompat::getProc(t, ilu, "iluBlurGaussian", iluBlurGaussian);
	oscompat::getProc(t, ilu, "iluBuildMipmaps", iluBuildMipmaps);
	oscompat::getProc(t, ilu, "iluColoursUsed", iluColoursUsed);
	oscompat::getProc(t, ilu, "iluCompareImage", iluCompareImage);
	oscompat::getProc(t, ilu, "iluContrast", iluContrast);
	oscompat::getProc(t, ilu, "iluCrop", iluCrop);
	oscompat::getProc(t, ilu, "iluEdgeDetectE", iluEdgeDetectE);
	oscompat::getProc(t, ilu, "iluEdgeDetectP", iluEdgeDetectP);
	oscompat::getProc(t, ilu, "iluEdgeDetectS", iluEdgeDetectS);
	oscompat::getProc(t, ilu, "iluEmboss", iluEmboss);
	oscompat::getProc(t, ilu, "iluEnlargeCanvas", iluEnlargeCanvas);
	oscompat::getProc(t, ilu, "iluEnlargeImage", iluEnlargeImage);
	oscompat::getProc(t, ilu, "iluEqualize", iluEqualize);
	oscompat::getProc(t, ilu, "iluErrorString", iluErrorString);
	oscompat::getProc(t, ilu, "iluConvolution", iluConvolution);
	oscompat::getProc(t, ilu, "iluFlipImage", iluFlipImage);
	oscompat::getProc(t, ilu, "iluGammaCorrect", iluGammaCorrect);
	oscompat::getProc(t, ilu, "iluGetImageInfo", iluGetImageInfo);
	oscompat::getProc(t, ilu, "iluGetIntegerv", iluGetIntegerv);
	oscompat::getProc(t, ilu, "iluGetString", iluGetString);
	oscompat::getProc(t, ilu, "iluImageParameter", iluImageParameter);
	oscompat::getProc(t, ilu, "iluInit", iluInit);
	oscompat::getProc(t, ilu, "iluInvertAlpha", iluInvertAlpha);
	oscompat::getProc(t, ilu, "iluLoadImage", iluLoadImage);
	oscompat::getProc(t, ilu, "iluMirror", iluMirror);
	oscompat::getProc(t, ilu, "iluNegative", iluNegative);
	oscompat::getProc(t, ilu, "iluNoisify", iluNoisify);
	oscompat::getProc(t, ilu, "iluPixelize", iluPixelize);
	oscompat::getProc(t, ilu, "iluRegionfv", iluRegionfv);
	oscompat::getProc(t, ilu, "iluRegioniv", iluRegioniv);
	oscompat::getProc(t, ilu, "iluReplaceColour", iluReplaceColour);
	oscompat::getProc(t, ilu, "iluRotate", iluRotate);
	oscompat::getProc(t, ilu, "iluRotate3D", iluRotate3D);
	oscompat::getProc(t, ilu, "iluSaturate1f", iluSaturate1f);
	oscompat::getProc(t, ilu, "iluSaturate4f", iluSaturate4f);
	oscompat::getProc(t, ilu, "iluScale", iluScale);
	oscompat::getProc(t, ilu, "iluScaleAlpha", iluScaleAlpha);
	oscompat::getProc(t, ilu, "iluScaleColours", iluScaleColours);
	oscompat::getProc(t, ilu, "iluSetLanguage", iluSetLanguage);
	oscompat::getProc(t, ilu, "iluSharpen", iluSharpen);
	oscompat::getProc(t, ilu, "iluSwapColours", iluSwapColours);
	oscompat::getProc(t, ilu, "iluWave", iluWave);

	ilInit();
	iluInit();
}

// =====================================================================================================================
// Helpers

template<typename T, typename Enable = void>
struct ILTypeString
{};

template<typename T>
struct ILTypeString<T, typename std::enable_if<std::is_integral<T>::value && std::is_unsigned<T>::value>::type>
{
	static constexpr const char* value =
		(sizeof(T) == 1) ? "u8" :
		(sizeof(T) == 2) ? "u16" :
		(sizeof(T) == 4) ? "u32" :
		"u64";
};

template<typename T>
struct ILTypeString<T, typename std::enable_if<std::is_integral<T>::value && std::is_signed<T>::value>::type>
{
	static constexpr const char* value =
		(sizeof(T) == 1) ? "i8" :
		(sizeof(T) == 2) ? "i16" :
		(sizeof(T) == 4) ? "i32" :
		"i64";
};

template<typename T>
struct ILTypeString<T, typename std::enable_if<std::is_floating_point<T>::value>::type>
{
	static constexpr const char* value =
		(sizeof(T) == 4) ? "f32" :
		"f64";
};

#define ILCONST(c) croc_pushInt(t, c); croc_newGlobal(t, #c);

void loadConstants(CrocThread* t)
{
	croc_pushString(t, ILTypeString<ILenum>::value);     croc_newGlobal(t, "ILenum");
	croc_pushString(t, ILTypeString<ILboolean>::value);  croc_newGlobal(t, "ILboolean");
	croc_pushString(t, ILTypeString<ILbitfield>::value); croc_newGlobal(t, "ILbitfield");
	croc_pushString(t, ILTypeString<ILbyte>::value);     croc_newGlobal(t, "ILbyte");
	croc_pushString(t, ILTypeString<ILshort>::value);    croc_newGlobal(t, "ILshort");
	croc_pushString(t, ILTypeString<ILint>::value);      croc_newGlobal(t, "ILint");
	croc_pushString(t, ILTypeString<ILsizei>::value);    croc_newGlobal(t, "ILsizei");
	croc_pushString(t, ILTypeString<ILubyte>::value);    croc_newGlobal(t, "ILubyte");
	croc_pushString(t, ILTypeString<ILushort>::value);   croc_newGlobal(t, "ILushort");
	croc_pushString(t, ILTypeString<ILuint>::value);     croc_newGlobal(t, "ILuint");
	croc_pushString(t, ILTypeString<ILfloat>::value);    croc_newGlobal(t, "ILfloat");
	croc_pushString(t, ILTypeString<ILclampf>::value);   croc_newGlobal(t, "ILclampf");
	croc_pushString(t, ILTypeString<ILdouble>::value);   croc_newGlobal(t, "ILdouble");
	croc_pushString(t, ILTypeString<ILclampd>::value);   croc_newGlobal(t, "ILclampd");

	croc_pushInt(t, sizeof(ILenum));     croc_newGlobal(t, "sizeofILenum");
	croc_pushInt(t, sizeof(ILboolean));  croc_newGlobal(t, "sizeofILboolean");
	croc_pushInt(t, sizeof(ILbitfield)); croc_newGlobal(t, "sizeofILbitfield");
	croc_pushInt(t, sizeof(ILbyte));     croc_newGlobal(t, "sizeofILbyte");
	croc_pushInt(t, sizeof(ILshort));    croc_newGlobal(t, "sizeofILshort");
	croc_pushInt(t, sizeof(ILint));      croc_newGlobal(t, "sizeofILint");
	croc_pushInt(t, sizeof(ILsizei));    croc_newGlobal(t, "sizeofILsizei");
	croc_pushInt(t, sizeof(ILubyte));    croc_newGlobal(t, "sizeofILubyte");
	croc_pushInt(t, sizeof(ILushort));   croc_newGlobal(t, "sizeofILushort");
	croc_pushInt(t, sizeof(ILuint));     croc_newGlobal(t, "sizeofILuint");
	croc_pushInt(t, sizeof(ILfloat));    croc_newGlobal(t, "sizeofILfloat");
	croc_pushInt(t, sizeof(ILclampf));   croc_newGlobal(t, "sizeofILclampf");
	croc_pushInt(t, sizeof(ILdouble));   croc_newGlobal(t, "sizeofILdouble");
	croc_pushInt(t, sizeof(ILclampd));   croc_newGlobal(t, "sizeofILclampd");

	croc_pushBool(t, IL_TRUE);  croc_newGlobal(t, "IL_TRUE");
	croc_pushBool(t, IL_FALSE); croc_newGlobal(t, "IL_FALSE");

	ILCONST(IL_COLOUR_INDEX);            ILCONST(IL_COLOR_INDEX);
	ILCONST(IL_ALPHA);                   ILCONST(IL_RGB);
	ILCONST(IL_RGBA);                    ILCONST(IL_BGR);
	ILCONST(IL_BGRA);                    ILCONST(IL_LUMINANCE);
	ILCONST(IL_LUMINANCE_ALPHA);         ILCONST(IL_BYTE);
	ILCONST(IL_UNSIGNED_BYTE);           ILCONST(IL_SHORT);
	ILCONST(IL_UNSIGNED_SHORT);          ILCONST(IL_INT);
	ILCONST(IL_UNSIGNED_INT);            ILCONST(IL_FLOAT);
	ILCONST(IL_DOUBLE);                  ILCONST(IL_HALF);
	ILCONST(IL_MAX_BYTE);                ILCONST(IL_MAX_UNSIGNED_BYTE);
	ILCONST(IL_MAX_SHORT);               ILCONST(IL_MAX_UNSIGNED_SHORT);
	ILCONST(IL_MAX_INT);                 ILCONST(IL_MAX_UNSIGNED_INT);
	ILCONST(IL_VENDOR);                  ILCONST(IL_LOAD_EXT);
	ILCONST(IL_SAVE_EXT);                ILCONST(IL_VERSION_1_7_8);
	ILCONST(IL_VERSION);                 ILCONST(IL_ORIGIN_BIT);
	ILCONST(IL_FILE_BIT);                ILCONST(IL_PAL_BIT);
	ILCONST(IL_FORMAT_BIT);              ILCONST(IL_TYPE_BIT);
	ILCONST(IL_COMPRESS_BIT);            ILCONST(IL_LOADFAIL_BIT);
	ILCONST(IL_FORMAT_SPECIFIC_BIT);     ILCONST(IL_ALL_ATTRIB_BITS);
	ILCONST(IL_PAL_NONE);                ILCONST(IL_PAL_RGB24);
	ILCONST(IL_PAL_RGB32);               ILCONST(IL_PAL_RGBA32);
	ILCONST(IL_PAL_BGR24);               ILCONST(IL_PAL_BGR32);
	ILCONST(IL_PAL_BGRA32);              ILCONST(IL_TYPE_UNKNOWN);
	ILCONST(IL_BMP);                     ILCONST(IL_CUT);
	ILCONST(IL_DOOM);                    ILCONST(IL_DOOM_FLAT);
	ILCONST(IL_ICO);                     ILCONST(IL_JPG);
	ILCONST(IL_JFIF);                    ILCONST(IL_ILBM);
	ILCONST(IL_PCD);                     ILCONST(IL_PCX);
	ILCONST(IL_PIC);                     ILCONST(IL_PNG);
	ILCONST(IL_PNM);                     ILCONST(IL_SGI);
	ILCONST(IL_TGA);                     ILCONST(IL_TIF);
	ILCONST(IL_CHEAD);                   ILCONST(IL_RAW);
	ILCONST(IL_MDL);                     ILCONST(IL_WAL);
	ILCONST(IL_LIF);                     ILCONST(IL_MNG);
	ILCONST(IL_JNG);                     ILCONST(IL_GIF);
	ILCONST(IL_DDS);                     ILCONST(IL_DCX);
	ILCONST(IL_PSD);                     ILCONST(IL_EXIF);
	ILCONST(IL_PSP);                     ILCONST(IL_PIX);
	ILCONST(IL_PXR);                     ILCONST(IL_XPM);
	ILCONST(IL_HDR);                     ILCONST(IL_ICNS);
	ILCONST(IL_JP2);                     ILCONST(IL_EXR);
	ILCONST(IL_WDP);                     ILCONST(IL_VTF);
	ILCONST(IL_WBMP);                    ILCONST(IL_SUN);
	ILCONST(IL_IFF);                     ILCONST(IL_TPL);
	ILCONST(IL_FITS);                    ILCONST(IL_DICOM);
	ILCONST(IL_IWI);                     ILCONST(IL_BLP);
	ILCONST(IL_FTX);                     ILCONST(IL_ROT);
	ILCONST(IL_TEXTURE);                 ILCONST(IL_DPX);
	ILCONST(IL_UTX);                     ILCONST(IL_MP3);
	ILCONST(IL_JASC_PAL);                ILCONST(IL_NO_ERROR);
	ILCONST(IL_INVALID_ENUM);            ILCONST(IL_OUT_OF_MEMORY);
	ILCONST(IL_FORMAT_NOT_SUPPORTED);    ILCONST(IL_INTERNAL_ERROR);
	ILCONST(IL_INVALID_VALUE);           ILCONST(IL_ILLEGAL_OPERATION);
	ILCONST(IL_ILLEGAL_FILE_VALUE);      ILCONST(IL_INVALID_FILE_HEADER);
	ILCONST(IL_INVALID_PARAM);           ILCONST(IL_COULD_NOT_OPEN_FILE);
	ILCONST(IL_INVALID_EXTENSION);       ILCONST(IL_FILE_ALREADY_EXISTS);
	ILCONST(IL_OUT_FORMAT_SAME);         ILCONST(IL_STACK_OVERFLOW);
	ILCONST(IL_STACK_UNDERFLOW);         ILCONST(IL_INVALID_CONVERSION);
	ILCONST(IL_BAD_DIMENSIONS);          ILCONST(IL_FILE_READ_ERROR);
	ILCONST(IL_FILE_WRITE_ERROR);        ILCONST(IL_LIB_GIF_ERROR);
	ILCONST(IL_LIB_JPEG_ERROR);          ILCONST(IL_LIB_PNG_ERROR);
	ILCONST(IL_LIB_TIFF_ERROR);          ILCONST(IL_LIB_MNG_ERROR);
	ILCONST(IL_LIB_JP2_ERROR);           ILCONST(IL_LIB_EXR_ERROR);
	ILCONST(IL_UNKNOWN_ERROR);           ILCONST(IL_ORIGIN_SET);
	ILCONST(IL_ORIGIN_LOWER_LEFT);       ILCONST(IL_ORIGIN_UPPER_LEFT);
	ILCONST(IL_ORIGIN_MODE);             ILCONST(IL_FORMAT_SET);
	ILCONST(IL_FORMAT_MODE);             ILCONST(IL_TYPE_SET);
	ILCONST(IL_TYPE_MODE);               ILCONST(IL_FILE_OVERWRITE);
	ILCONST(IL_FILE_MODE);               ILCONST(IL_CONV_PAL);
	ILCONST(IL_DEFAULT_ON_FAIL);         ILCONST(IL_USE_KEY_COLOUR);
	ILCONST(IL_USE_KEY_COLOR);           ILCONST(IL_BLIT_BLEND);
	ILCONST(IL_SAVE_INTERLACED);         ILCONST(IL_INTERLACE_MODE);
	ILCONST(IL_QUANTIZATION_MODE);       ILCONST(IL_WU_QUANT);
	ILCONST(IL_NEU_QUANT);               ILCONST(IL_NEU_QUANT_SAMPLE);
	ILCONST(IL_MAX_QUANT_INDEXS);        ILCONST(IL_MAX_QUANT_INDICES);
	ILCONST(IL_FASTEST);                 ILCONST(IL_LESS_MEM);
	ILCONST(IL_DONT_CARE);               ILCONST(IL_MEM_SPEED_HINT);
	ILCONST(IL_USE_COMPRESSION);         ILCONST(IL_NO_COMPRESSION);
	ILCONST(IL_COMPRESSION_HINT);        ILCONST(IL_NVIDIA_COMPRESS);
	ILCONST(IL_SQUISH_COMPRESS);         ILCONST(IL_SUB_NEXT);
	ILCONST(IL_SUB_MIPMAP);              ILCONST(IL_SUB_LAYER);
	ILCONST(IL_COMPRESS_MODE);           ILCONST(IL_COMPRESS_NONE);
	ILCONST(IL_COMPRESS_RLE);            ILCONST(IL_COMPRESS_LZO);
	ILCONST(IL_COMPRESS_ZLIB);           ILCONST(IL_TGA_CREATE_STAMP);
	ILCONST(IL_JPG_QUALITY);             ILCONST(IL_PNG_INTERLACE);
	ILCONST(IL_TGA_RLE);                 ILCONST(IL_BMP_RLE);
	ILCONST(IL_SGI_RLE);                 ILCONST(IL_TGA_ID_STRING);
	ILCONST(IL_TGA_AUTHNAME_STRING);     ILCONST(IL_TGA_AUTHCOMMENT_STRING);
	ILCONST(IL_PNG_AUTHNAME_STRING);     ILCONST(IL_PNG_TITLE_STRING);
	ILCONST(IL_PNG_DESCRIPTION_STRING);  ILCONST(IL_TIF_DESCRIPTION_STRING);
	ILCONST(IL_TIF_HOSTCOMPUTER_STRING); ILCONST(IL_TIF_DOCUMENTNAME_STRING);
	ILCONST(IL_TIF_AUTHNAME_STRING);     ILCONST(IL_JPG_SAVE_FORMAT);
	ILCONST(IL_CHEAD_HEADER_STRING);     ILCONST(IL_PCD_PICNUM);
	ILCONST(IL_PNG_ALPHA_INDEX);         ILCONST(IL_JPG_PROGRESSIVE);
	ILCONST(IL_VTF_COMP);                ILCONST(IL_DXTC_FORMAT);
	ILCONST(IL_DXT1);                    ILCONST(IL_DXT2);
	ILCONST(IL_DXT3);                    ILCONST(IL_DXT4);
	ILCONST(IL_DXT5);                    ILCONST(IL_DXT_NO_COMP);
	ILCONST(IL_KEEP_DXTC_DATA);          ILCONST(IL_DXTC_DATA_FORMAT);
	ILCONST(IL_3DC);                     ILCONST(IL_RXGB);
	ILCONST(IL_ATI1N);                   ILCONST(IL_DXT1A);
	ILCONST(IL_CUBEMAP_POSITIVEX);       ILCONST(IL_CUBEMAP_NEGATIVEX);
	ILCONST(IL_CUBEMAP_POSITIVEY);       ILCONST(IL_CUBEMAP_NEGATIVEY);
	ILCONST(IL_CUBEMAP_POSITIVEZ);       ILCONST(IL_CUBEMAP_NEGATIVEZ);
	ILCONST(IL_SPHEREMAP);               ILCONST(IL_VERSION_NUM);
	ILCONST(IL_IMAGE_WIDTH);             ILCONST(IL_IMAGE_HEIGHT);
	ILCONST(IL_IMAGE_DEPTH);             ILCONST(IL_IMAGE_SIZE_OF_DATA);
	ILCONST(IL_IMAGE_BPP);               ILCONST(IL_IMAGE_BYTES_PER_PIXEL);
	ILCONST(IL_IMAGE_BITS_PER_PIXEL);
	ILCONST(IL_IMAGE_FORMAT);            ILCONST(IL_IMAGE_TYPE);
	ILCONST(IL_PALETTE_TYPE);            ILCONST(IL_PALETTE_SIZE);
	ILCONST(IL_PALETTE_BPP);             ILCONST(IL_PALETTE_NUM_COLS);
	ILCONST(IL_PALETTE_BASE_TYPE);       ILCONST(IL_NUM_FACES);
	ILCONST(IL_NUM_IMAGES);              ILCONST(IL_NUM_MIPMAPS);
	ILCONST(IL_NUM_LAYERS);              ILCONST(IL_ACTIVE_IMAGE);
	ILCONST(IL_ACTIVE_MIPMAP);           ILCONST(IL_ACTIVE_LAYER);
	ILCONST(IL_ACTIVE_FACE);             ILCONST(IL_CUR_IMAGE);
	ILCONST(IL_IMAGE_DURATION);          ILCONST(IL_IMAGE_PLANESIZE);
	ILCONST(IL_IMAGE_BPC);               ILCONST(IL_IMAGE_OFFX);
	ILCONST(IL_IMAGE_OFFY);              ILCONST(IL_IMAGE_CUBEFLAGS);
	ILCONST(IL_IMAGE_ORIGIN);            ILCONST(IL_IMAGE_CHANNELS);
	ILCONST(ILU_VERSION_1_7_8);          ILCONST(ILU_VERSION);
	ILCONST(ILU_FILTER);                 ILCONST(ILU_NEAREST);
	ILCONST(ILU_LINEAR);                 ILCONST(ILU_BILINEAR);
	ILCONST(ILU_SCALE_BOX);              ILCONST(ILU_SCALE_TRIANGLE);
	ILCONST(ILU_SCALE_BELL);             ILCONST(ILU_SCALE_BSPLINE);
	ILCONST(ILU_SCALE_LANCZOS3);         ILCONST(ILU_SCALE_MITCHELL);
	ILCONST(ILU_INVALID_ENUM);           ILCONST(ILU_OUT_OF_MEMORY);
	ILCONST(ILU_INTERNAL_ERROR);         ILCONST(ILU_INVALID_VALUE);
	ILCONST(ILU_ILLEGAL_OPERATION);      ILCONST(ILU_INVALID_PARAM);
	ILCONST(ILU_PLACEMENT);              ILCONST(ILU_LOWER_LEFT);
	ILCONST(ILU_LOWER_RIGHT);            ILCONST(ILU_UPPER_LEFT);
	ILCONST(ILU_UPPER_RIGHT);            ILCONST(ILU_CENTER);
	ILCONST(ILU_CONVOLUTION_MATRIX);     ILCONST(ILU_VERSION_NUM);
	ILCONST(ILU_VENDOR);                 ILCONST(ILU_ENGLISH);
	ILCONST(ILU_ARABIC);                 ILCONST(ILU_DUTCH);
	ILCONST(ILU_JAPANESE);               ILCONST(ILU_SPANISH);
	ILCONST(ILU_GERMAN);                 ILCONST(ILU_FRENCH);
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

template<typename R, typename ...Args>
struct function_traits<R (APIENTRY *)(Args...)>
{
	typedef R result_type;
	typedef std::tuple<Args...> arg_types;
};

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
struct is_actual_integral<T, typename std::enable_if<std::is_same<T, ILboolean>::value>::type>
{
	static const bool value = false;
};

template<typename T>
struct is_actual_integral<T, typename std::enable_if<std::is_same<T, ILchar>::value>::type>
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
struct is_nonstring_pointer<T, typename std::enable_if<std::is_same<T, const ILchar*>::value>::type>
{
	static const bool value = false;
};

template<typename T>
struct is_nonstring_pointer<T, typename std::enable_if<std::is_same<T, ILstring>::value>::type>
{
	static const bool value = false;
};

template<typename T>
struct is_nonstring_pointer<T, typename std::enable_if<is_function_pointer<T>::value>::type>
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
getILParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkIntParam(t, slot);
}

template<typename T>
typename std::enable_if<std::is_same<T, ILboolean>::value, T>::type
getILParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkBoolParam(t, slot);
}

template<typename T>
typename std::enable_if<std::is_floating_point<T>::value, T>::type
getILParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkNumParam(t, slot);
}

template<typename T>
typename std::enable_if<std::is_same<T, ILchar>::value, T>::type
getILParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkCharParam(t, slot);
}

template<typename T>
typename std::enable_if<std::is_same<T, const ILchar*>::value, T>::type
getILParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkStringParam(t, slot);
}

template<typename T>
typename std::enable_if<std::is_same<T, ILstring>::value, T>::type
getILParam(CrocThread* t, word_t slot)
{
	return (T)croc_ex_checkStringParam(t, slot);
}

template<typename T>
typename std::enable_if<is_nonstring_pointer<T>::value, T>::type
getILParam(CrocThread* t, word_t slot)
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
getILParams(CrocThread* t, std::tuple<T...>& params)
{
	(void)t;
	(void)params;
}

template<int Idx = 0, typename... T>
typename std::enable_if<Idx < sizeof...(T), void>::type
getILParams(CrocThread* t, std::tuple<T...>& params)
{
	std::get<Idx>(params) = getILParam<typename tuple_element<Idx, T...>::type>(t, Idx + 1);
	getILParams<Idx + 1, T...>(t, params);
}

template<typename T>
typename std::enable_if<std::is_void<T>::value, void>::type
pushIL(CrocThread* t, std::function<T()> func)
{
	(void)t;
	func();
}

template<typename T>
typename std::enable_if<is_actual_integral<T>::value, void>::type
pushIL(CrocThread* t, T val)
{
	croc_pushInt(t, val);
}

template<typename T>
typename std::enable_if<std::is_same<T, ILboolean>::value, void>::type
pushIL(CrocThread* t, T val)
{
	croc_pushBool(t, val);
}

template<typename T>
typename std::enable_if<std::is_floating_point<T>::value, void>::type
pushIL(CrocThread* t, T val)
{
	croc_pushFloat(t, val);
}

template<typename T>
typename std::enable_if<std::is_same<T, ILchar>::value, void>::type
pushIL(CrocThread* t, T val)
{
	croc_pushChar(t, val);
}

template<typename T>
typename std::enable_if<std::is_same<T, ILstring>::value, void>::type
pushIL(CrocThread* t, T val)
{
	croc_pushString(t, val);
}

template<typename T>
typename std::enable_if<std::is_same<T, ILconst_string>::value, void>::type
pushIL(CrocThread* t, T val)
{
	croc_pushString(t, val);
}

template<typename R, typename... Args>
struct wrapil;

template<typename... Args>
struct wrapil<void, std::tuple<Args...>>
{
	static const uword_t numParams = sizeof...(Args);

	template<void (* ILAPIENTRY* Fun)(Args...)>
	struct func_holder
	{
		static word_t func(CrocThread* t)
		{
			std::tuple<Args...> _params;
			getILParams(t, _params);
			call(*Fun, _params);
			return 0;
		}
	};
};

template<typename R, typename... Args>
struct wrapil<R, std::tuple<Args...>>
{
	static const uword_t numParams = sizeof...(Args);

	template<R (* ILAPIENTRY* Fun)(Args...)>
	struct func_holder
	{
		static word_t func(CrocThread* t)
		{
			std::tuple<Args...> _params;
			getILParams(t, _params);
			pushIL(t, call(*Fun, _params));
			return 1;
		}
	};
};

#define NUMPARAMS(FUNC) wrapil<function_traits<decltype(FUNC)>::result_type, function_traits<decltype(FUNC)>::arg_types>::numParams
#define WRAPIL(FUNC) wrapil<function_traits<decltype(FUNC)>::result_type, function_traits<decltype(FUNC)>::arg_types>::func_holder<&FUNC>::func
#define WRAP(FUNC) {#FUNC, NUMPARAMS(FUNC), &WRAPIL(FUNC)}

word_t crocilGetPalette(CrocThread* t)
{
	auto haveMemblock = croc_ex_optParam(t, 1, CrocType_Memblock);

	if(auto ptr = ilGetPalette())
	{
		auto size = ilGetInteger(IL_PALETTE_SIZE);

		if(haveMemblock)
		{
			croc_memblock_reviewNativeArray(t, 1, cast(void*)ptr, size);
			croc_dup(t, 1);
		}
		else
			croc_memblock_viewNativeArray(t, cast(void*)ptr, size);
	}
	else
		croc_pushNull(t);

	return 1;
}

word_t crocilGetData(CrocThread* t)
{
	auto haveMemblock = croc_ex_optParam(t, 1, CrocType_Memblock);

	if(auto ptr = ilGetData())
	{
		auto size = ilGetInteger(IL_IMAGE_SIZE_OF_DATA);

		if(haveMemblock)
		{
			croc_memblock_reviewNativeArray(t, 1, cast(void*)ptr, size);
			croc_dup(t, 1);
		}
		else
			croc_memblock_viewNativeArray(t, cast(void*)ptr, size);
	}
	else
		croc_pushNull(t);

	return 1;
}

word_t crocilGetAlpha(CrocThread* t)
{
	auto type = croc_ex_checkIntParam(t, 1);
	auto haveMemblock = croc_ex_optParam(t, 2, CrocType_Memblock);

	if(auto ptr = ilGetAlpha(type))
	{
		auto size = ilGetInteger(IL_IMAGE_WIDTH) * ilGetInteger(IL_IMAGE_HEIGHT) * ilGetInteger(IL_IMAGE_DEPTH);

		switch(type)
		{
			case IL_SHORT: case IL_UNSIGNED_SHORT: case IL_HALF: size *= 2; break;
			case IL_INT: case IL_UNSIGNED_INT: case IL_FLOAT:    size *= 4; break;
			case IL_DOUBLE:                                      size *= 8; break;
			default: break;
		}

		if(haveMemblock)
		{
			croc_lenai(t, 2, size);
			auto mbData = croc_memblock_getData(t, 2);
			memcpy(mbData, ptr, size);
			croc_dup(t, 2);
		}
		else
			croc_memblock_fromNativeArray(t, cast(void*)ptr, size);

		free(ptr);
	}
	else
		croc_pushNull(t);

	return 1;
}

word_t crocilCompressDXT(CrocThread* t)
{
	auto data = getILParam<ILubyte*>(t, 1);
	auto width = getILParam<ILuint>(t, 2);
	auto height = getILParam<ILuint>(t, 3);
	auto depth = getILParam<ILuint>(t, 4);
	auto dxtcFormat = getILParam<ILuint>(t, 5);
	auto haveMemblock = croc_ex_optParam(t, 6, CrocType_Memblock);

	ILuint dxtcSize;

	if(auto ptr = ilCompressDXT(data, width, height, depth, dxtcFormat, &dxtcSize))
	{
		if(haveMemblock)
		{
			croc_memblock_reviewNativeArray(t, 6, cast(void*)ptr, dxtcSize);
			croc_dup(t, 6);
		}
		else
			croc_memblock_viewNativeArray(t, cast(void*)ptr, dxtcSize);
	}
	else
		croc_pushNull(t);

	return 1;
}

word_t crociluGetImageInfo(CrocThread* t)
{
	ILinfo info;
	info.SizeOfData = IL_MAX_UNSIGNED_INT;
	iluGetImageInfo(&info);

	if(info.SizeOfData == IL_MAX_UNSIGNED_INT)
		croc_pushNull(t);
	else
	{
		croc_table_new(t, 15);
		croc_pushInt(t, info.Id);         croc_fielda(t, -2, "Id");
		croc_pushInt(t, info.Width);      croc_fielda(t, -2, "Width");
		croc_pushInt(t, info.Height);     croc_fielda(t, -2, "Height");
		croc_pushInt(t, info.Depth);      croc_fielda(t, -2, "Depth");
		croc_pushInt(t, info.Bpp);        croc_fielda(t, -2, "Bpp");
		croc_pushInt(t, info.SizeOfData); croc_fielda(t, -2, "SizeOfData");
		croc_pushInt(t, info.Format);     croc_fielda(t, -2, "Format");
		croc_pushInt(t, info.Type);       croc_fielda(t, -2, "Type");
		croc_pushInt(t, info.Origin);     croc_fielda(t, -2, "Origin");
		croc_pushInt(t, info.PalType);    croc_fielda(t, -2, "PalType");
		croc_pushInt(t, info.PalSize);    croc_fielda(t, -2, "PalSize");
		croc_pushInt(t, info.CubeFlags);  croc_fielda(t, -2, "CubeFlags");
		croc_pushInt(t, info.NumNext);    croc_fielda(t, -2, "NumNext");
		croc_pushInt(t, info.NumMips);    croc_fielda(t, -2, "NumMips");
		croc_pushInt(t, info.NumLayers);  croc_fielda(t, -2, "NumLayers");
	}

	return 1;
}

const CrocRegisterFunc _ilFuncs[] =
{
	WRAP(ilActiveFace),
	WRAP(ilActiveImage),
	WRAP(ilActiveLayer),
	WRAP(ilActiveMipmap),
	WRAP(ilApplyPal),
	WRAP(ilApplyProfile),
	WRAP(ilBindImage),
	WRAP(ilBlit),
	WRAP(ilClampNTSC),
	WRAP(ilClearColour),
	WRAP(ilClearImage),
	WRAP(ilCloneCurImage),
	{"ilCompressDXT", 6, &crocilCompressDXT},
	WRAP(ilCompressFunc),
	WRAP(ilConvertImage),
	WRAP(ilConvertPal),
	WRAP(ilCopyImage),
	WRAP(ilCopyPixels),
	WRAP(ilCreateSubImage),
	WRAP(ilDefaultImage),
	WRAP(ilDeleteImage),
	WRAP(ilDeleteImages),
	WRAP(ilDetermineType),
	WRAP(ilDetermineTypeL),
	WRAP(ilDisable),
	WRAP(ilDxtcDataToImage),
	WRAP(ilDxtcDataToSurface),
	WRAP(ilEnable),
	WRAP(ilFlipSurfaceDxtcData),
	WRAP(ilFormatFunc),
	WRAP(ilGenImages),
	WRAP(ilGenImage),
	{"ilGetAlpha", 2, &crocilGetAlpha},
	WRAP(ilGetBoolean),
	WRAP(ilGetBooleanv),
	{"ilGetData", 1, &crocilGetData},
	WRAP(ilGetDXTCData),
	WRAP(ilGetError),
	WRAP(ilGetInteger),
	WRAP(ilGetIntegerv),
	WRAP(ilGetLumpPos),
	{"ilGetPalette", 1, &crocilGetPalette},
	WRAP(ilGetString),
	WRAP(ilHint),
	WRAP(ilInvertSurfaceDxtcDataAlpha),
	WRAP(ilImageToDxtcData),
	WRAP(ilIsDisabled),
	WRAP(ilIsEnabled),
	WRAP(ilIsImage),
	WRAP(ilIsValid),
	WRAP(ilIsValidL),
	WRAP(ilKeyColour),
	WRAP(ilLoad),
	WRAP(ilLoadImage),
	WRAP(ilLoadL),
	WRAP(ilLoadPal),
	WRAP(ilModAlpha),
	WRAP(ilOriginFunc),
	WRAP(ilOverlayImage),
	WRAP(ilPopAttrib),
	WRAP(ilPushAttrib),
	WRAP(ilSave),
	WRAP(ilSaveImage),
	WRAP(ilSaveL),
	WRAP(ilSavePal),
	WRAP(ilSetAlpha),
	WRAP(ilSetDuration),
	WRAP(ilSetInteger),
	WRAP(ilSetPixels),
	WRAP(ilSetString),
	WRAP(ilSurfaceToDxtcData),
	WRAP(ilTexImage),
	WRAP(ilTexImageDxtc),
	WRAP(ilTypeFromExt),
	WRAP(ilTypeFunc),
	WRAP(ilLoadData),
	WRAP(ilLoadDataL),
	WRAP(ilSaveData),

	// Lifecycle stuff that's handled for you
	// WRAP(ilInit),
	// WRAP(iluInit),
	// WRAP(ilShutDown),

	// These all use C function pointers (or are rendered useless because they can only be called from C callbacks).
	// WRAP(ilSetMemory),
	// WRAP(ilSetRead),
	// WRAP(ilSetWrite),
	// WRAP(ilRegisterFormat),
	// WRAP(ilRegisterLoad),
	// WRAP(ilRegisterMipNum),
	// WRAP(ilRegisterNumFaces),
	// WRAP(ilRegisterNumImages),
	// WRAP(ilRegisterOrigin),
	// WRAP(ilRegisterPal),
	// WRAP(ilRegisterSave),
	// WRAP(ilRegisterType),
	// WRAP(ilRemoveLoad),
	// WRAP(ilRemoveSave),
	// WRAP(ilResetRead),
	// WRAP(ilResetWrite),

	// These use C FILE*s. I guess technically they could be wrapped...?
	// WRAP(ilDetermineTypeF),
	// WRAP(ilIsValidF),
	// WRAP(ilLoadF),
	// WRAP(ilSaveF),
	// WRAP(ilLoadDataF),

	// This passes off a pointer to the library, which is unsafe. The fix is to dup the memory, buuuut then that makes
	// it no different than ilSetPixels. So.
	// WRAP(ilSetData),

	WRAP(iluAlienify),
	WRAP(iluBlurAvg),
	WRAP(iluBlurGaussian),
	WRAP(iluBuildMipmaps),
	WRAP(iluColoursUsed),
	WRAP(iluCompareImage),
	WRAP(iluContrast),
	WRAP(iluCrop),
	WRAP(iluEdgeDetectE),
	WRAP(iluEdgeDetectP),
	WRAP(iluEdgeDetectS),
	WRAP(iluEmboss),
	WRAP(iluEnlargeCanvas),
	WRAP(iluEnlargeImage),
	WRAP(iluEqualize),
	WRAP(iluErrorString),
	WRAP(iluConvolution),
	WRAP(iluFlipImage),
	WRAP(iluGammaCorrect),
	{"iluGetImageInfo", 0, &crociluGetImageInfo},
	WRAP(iluGetInteger),
	WRAP(iluGetIntegerv),
	WRAP(iluGetString),
	WRAP(iluImageParameter),
	WRAP(iluInvertAlpha),
	WRAP(iluLoadImage),
	WRAP(iluMirror),
	WRAP(iluNegative),
	WRAP(iluNoisify),
	WRAP(iluPixelize),
	WRAP(iluRegionfv),
	WRAP(iluRegioniv),
	WRAP(iluReplaceColour),
	WRAP(iluRotate),
	WRAP(iluRotate3D),
	WRAP(iluSaturate1f),
	WRAP(iluSaturate4f),
	WRAP(iluScale),
	WRAP(iluScaleAlpha),
	WRAP(iluScaleColours),
	WRAP(iluSetLanguage),
	WRAP(iluSharpen),
	WRAP(iluSwapColours),
	WRAP(iluWave),

	{nullptr, 0, nullptr}
};

// =====================================================================================================================
// Loader

word loader(CrocThread* t)
{
	loadSharedLib(t);
	loadConstants(t);
	croc_ex_registerGlobals(t, _ilFuncs);

	croc_pushGlobal(t, "ilClearColour");    croc_newGlobal(t, "ilClearColor");
	croc_pushGlobal(t, "ilKeyColour");      croc_newGlobal(t, "ilKeyColor");
	croc_pushGlobal(t, "iluColoursUsed");   croc_newGlobal(t, "iluColorsUsed");
	croc_pushGlobal(t, "iluSwapColours");   croc_newGlobal(t, "iluSwapColors");
	croc_pushGlobal(t, "iluReplaceColour"); croc_newGlobal(t, "iluReplaceColor");
	croc_pushGlobal(t, "iluScaleColours");  croc_newGlobal(t, "iluScaleColors");

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

void initDevilLib(CrocThread* t)
{
	croc_ex_makeModule(t, "devil", &loader);
}
#endif
}