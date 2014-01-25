/******************************************************************************
A binding to the DevIL image library.

License:
Copyright (c) 2011 Jarrett Billingsley
Portions of this module were borrowed from Sean Kerr's codebox.text.Regex module.

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

	1. The origin of this software must not be misrepresented; you must not
	claim that you wrote the original software. If you use this software in a
	product, an acknowledgment in the product documentation would be
	appreciated but is not required.

	2. Altered source versions must be plainly marked as such, and must not
	be misrepresented as being the original software.

	3. This notice may not be removed or altered from any source distribution.
******************************************************************************/

module croc.addons.devil;

version(CrocAllAddons)
	version = CrocDevilAddon;

version(CrocDevilAddon){}else
{
	import croc.api;

	struct DevilLib
	{
		static void init(CrocThread* t)
		{
			throwStdException(t, "ApiError", "Attempting to load the DevIL library, but it was not compiled in");
		}
	}
}

version(CrocDevilAddon)
{

import tango.stdc.stdlib;
import tango.stdc.stringz;

import derelict.devil.il;
import derelict.devil.ilu;

import croc.api;
import croc.ex_library;

import croc.addons.devil_wrap;

template typeStringOf(_T)
{
	static if(is(realType!(_T) == byte))
		const typeStringOf = CrocMemblock.typeStructs[CrocMemblock.TypeCode.i8].name;
	else static if(is(realType!(_T) == ubyte))
		const typeStringOf = CrocMemblock.typeStructs[CrocMemblock.TypeCode.u8].name;
	else static if(is(realType!(_T) == short))
		const typeStringOf = CrocMemblock.typeStructs[CrocMemblock.TypeCode.i16].name;
	else static if(is(realType!(_T) == ushort))
		const typeStringOf = CrocMemblock.typeStructs[CrocMemblock.TypeCode.u16].name;
	else static if(is(realType!(_T) == int))
		const typeStringOf = CrocMemblock.typeStructs[CrocMemblock.TypeCode.i32].name;
	else static if(is(realType!(_T) == uint))
		const typeStringOf = CrocMemblock.typeStructs[CrocMemblock.TypeCode.u32].name;
	else static if(is(realType!(_T) == long))
		const typeStringOf = CrocMemblock.typeStructs[CrocMemblock.TypeCode.i64].name;
	else static if(is(realType!(_T) == ulong))
		const typeStringOf = CrocMemblock.typeStructs[CrocMemblock.TypeCode.u64].name;
	else static if(is(realType!(_T) == float))
		const typeStringOf = CrocMemblock.typeStructs[CrocMemblock.TypeCode.f32].name;
	else static if(is(realType!(_T) == double))
		const typeStringOf = CrocMemblock.typeStructs[CrocMemblock.TypeCode.f64].name;
	else
		static assert(false, "Don't know what type string corresponds to " ~ _T.stringof);
}

struct DevilLib
{
static:
	void init(CrocThread* t)
	{
		makeModule(t, "devil", function uword(CrocThread* t)
		{
			CreateClass(t, "DevILException", "exceptions.Exception", (CreateClass* c) {});
			newGlobal(t, "DevILException");

			safeCode(t, "DevILException",
			{
				DerelictIL.load();
				DerelictILU.load();
			}());

			pushString(t, typeStringOf!(ILenum)); newGlobal(t, "ILenum");
			pushString(t, typeStringOf!(ILboolean)); newGlobal(t, "ILboolean");
			pushString(t, typeStringOf!(ILbitfield)); newGlobal(t, "ILbitfield");
			pushString(t, typeStringOf!(ILbyte)); newGlobal(t, "ILbyte");
			pushString(t, typeStringOf!(ILshort)); newGlobal(t, "ILshort");
			pushString(t, typeStringOf!(ILint)); newGlobal(t, "ILint");
			pushString(t, typeStringOf!(ILubyte)); newGlobal(t, "ILubyte");
			pushString(t, typeStringOf!(ILushort)); newGlobal(t, "ILushort");
			pushString(t, typeStringOf!(ILuint)); newGlobal(t, "ILuint");
			pushString(t, typeStringOf!(ILsizei)); newGlobal(t, "ILsizei");
			pushString(t, typeStringOf!(ILfloat)); newGlobal(t, "ILfloat");
			pushString(t, typeStringOf!(ILclampf)); newGlobal(t, "ILclampf");
			pushString(t, typeStringOf!(ILdouble)); newGlobal(t, "ILdouble");
			pushString(t, typeStringOf!(ILclampd)); newGlobal(t, "ILclampd");

			ilFuncs(t);
			iluFuncs(t);

			register(t, "ilGetAlpha", &crocilGetAlpha);
			register(t, "ilGetData", &crocilGetData);
			register(t, "ilGetPalette", &crocilGetPalette);
			register(t, "iluGetImageInfo", &crociluGetImageInfo);
			register(t, "iluRegionfv", &crociluRegionfv);
			register(t, "iluRegioniv", &crociluRegioniv);

			return 0;
		});
	}

	uword crocilGetAlpha(CrocThread* t)
	{
		auto type = cast(ILenum)checkIntParam(t, 1);
		auto ptr = ilGetAlpha(type);

		if(ptr is null)
		{
			version(CrocILCheckErrors)
				throwNamedException(t, "DevILException", "ilGetAlpha - {}", fromStringz(cast(char*)iluErrorString(ilGetError())));
			else
			{
				pushNull(t);
				return 1;
			}
		}

		scope(exit)
			free(ptr);

		// Hhhhhh........ goddammit DevIL, make this easier for me.
		uword size = ilGetInteger(IL_IMAGE_WIDTH) * ilGetInteger(IL_IMAGE_HEIGHT) * ilGetInteger(IL_IMAGE_DEPTH);

		switch(type)
		{
			case IL_SHORT, IL_UNSIGNED_SHORT, IL_HALF: size *= 2; break;
			case IL_INT, IL_UNSIGNED_INT, IL_FLOAT:    size *= 4; break;
			case IL_DOUBLE:                            size *= 8; break;
			default: break;
		}

		auto arr = (cast(ubyte*)ptr)[0 .. size];

		if(optParam(t, 2, CrocValue.Type.Memblock))
		{
			setMemblockType(t, 2, "u8");
			lenai(t, 2, arr.length);
			getMemblockData(t, 2)[] = arr[];
		}
		else
			memblockFromDArray(t, arr);

		return 1;
	}

	uword crocilGetData(CrocThread* t)
	{
		auto ptr = ilGetData();

		if(ptr is null)
		{
			version(CrocILCheckErrors)
				throwNamedException(t, "DevILException", "ilGetData - {}", fromStringz(cast(char*)iluErrorString(ilGetError())));
			else
			{
				pushNull(t);
				return 1;
			}
		}

		uword size = ilGetInteger(IL_IMAGE_SIZE_OF_DATA);
		auto arr = (cast(ubyte*)ptr)[0 .. size];

		if(optParam(t, 1, CrocValue.Type.Memblock))
		{
			memblockReviewDArray(t, 1, arr);
			dup(t, 1);
		}
		else
			memblockViewDArray(t, arr);

		return 1;
	}

	uword crocilGetPalette(CrocThread* t)
	{
		auto ptr = ilGetPalette();

		if(ptr is null)
		{
			version(CrocILCheckErrors)
				throwNamedException(t, "DevILException", "ilGetPalette - {}", fromStringz(cast(char*)iluErrorString(ilGetError())));
			else
			{
				pushNull(t);
				return 1;
			}
		}

		uword size = ilGetInteger(IL_PALETTE_SIZE);
		auto arr = (cast(ubyte*)ptr)[0 .. size];

		if(optParam(t, 1, CrocValue.Type.Memblock))
		{
			memblockReviewDArray(t, 1, arr);
			dup(t, 1);
		}
		else
			memblockViewDArray(t, arr);

		return 1;
	}

	uword crociluGetImageInfo(CrocThread* t)
	{
		ILinfo info;
		info.SizeOfData = ILuint.max;
		iluGetImageInfo(&info);

		if(info.SizeOfData == ILuint.max)
		{
			version(CrocILCheckErrors)
				throwNamedException(t, "DevILException", "iluGetImageInfo - {}", fromStringz(cast(char*)iluErrorString(ilGetError())));
			else
			{
				pushNull(t);
				return 1;
			}
		}

		newTable(t);
			pushInt(t, info.Id);         fielda(t, -2, "Id");
			pushInt(t, info.Width);      fielda(t, -2, "Width");
			pushInt(t, info.Height);     fielda(t, -2, "Height");
			pushInt(t, info.Depth);      fielda(t, -2, "Depth");
			pushInt(t, info.Bpp);        fielda(t, -2, "Bpp");
			pushInt(t, info.SizeOfData); fielda(t, -2, "SizeOfData");
			pushInt(t, info.Format);     fielda(t, -2, "Format");
			pushInt(t, info.Type);       fielda(t, -2, "Type");
			pushInt(t, info.Origin);     fielda(t, -2, "Origin");
			pushInt(t, info.PalType);    fielda(t, -2, "PalType");
			pushInt(t, info.PalSize);    fielda(t, -2, "PalSize");
			pushInt(t, info.CubeFlags);  fielda(t, -2, "CubeFlags");
			pushInt(t, info.NumNext);    fielda(t, -2, "NumNext");
			pushInt(t, info.NumMips);    fielda(t, -2, "NumMips");
			pushInt(t, info.NumLayers);  fielda(t, -2, "NumLayers");
		return 1;
	}

	uword crociluRegionfv(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Array);

		auto arr = allocArray!(ILpointf)(t, cast(uword)len(t, 1));

		scope(exit)
			freeArray(t, arr);

		foreach(i, ref v; arr)
		{
			idxi(t, 1, i);

			if(!isTable(t, -1))
			{
				pushTypeString(t, -1);
				throwStdException(t, "TypeError", "Array element {} is a '{}', not a table", i, getString(t, -1));
			}

			field(t, -1, "x");

			if(isInt(t, -1))
				v.x = cast(ILfloat)getInt(t, -1);
			else if(isFloat(t, -1))
				v.x = cast(ILfloat)getFloat(t, -1);
			else
			{
				pushTypeString(t, -1);
				throwStdException(t, "TypeError", "Array element {}'s 'x' field is a '{}', not a number", i, getString(t, -1));
			}

			pop(t);
			field(t, -1, "y");

			if(isInt(t, -1))
				v.y = cast(ILfloat)getInt(t, -1);
			else if(isFloat(t, -1))
				v.y = cast(ILfloat)getFloat(t, -1);
			else
			{
				pushTypeString(t, -1);
				throwStdException(t, "TypeError", "Array element {}'s 'y' field is a '{}', not a number", i, getString(t, -1));
			}

			pop(t, 2);
		}

		iluRegionfv(arr.ptr, arr.length);

		version(CrocILCheckErrors)
		{
			auto err = ilGetError();

			if(err != IL_NO_ERROR)
				throwNamedException(t, "DevILException", "iluRegionfv - {}", fromStringz(cast(char*)iluErrorString(err)));
		}

		return 0;
	}

	uword crociluRegioniv(CrocThread* t)
	{
		checkParam(t, 1, CrocValue.Type.Array);

		auto arr = allocArray!(ILpointi)(t, cast(uword)len(t, 1));

		scope(exit)
			freeArray(t, arr);

		foreach(i, ref v; arr)
		{
			idxi(t, 1, i);

			if(!isTable(t, -1))
			{
				pushTypeString(t, -1);
				throwStdException(t, "TypeError", "Array element {} is a '{}', not a table", i, getString(t, -1));
			}

			field(t, -1, "x");

			if(isInt(t, -1))
				v.x = cast(ILint)getInt(t, -1);
			else
			{
				pushTypeString(t, -1);
				throwStdException(t, "TypeError", "Array element {}'s 'x' field is a '{}', not an int", i, getString(t, -1));
			}

			pop(t);
			field(t, -1, "y");

			if(isInt(t, -1))
				v.y = cast(ILint)getInt(t, -1);
			else
			{
				pushTypeString(t, -1);
				throwStdException(t, "TypeError", "Array element {}'s 'y' field is a '{}', not an int", i, getString(t, -1));
			}

			pop(t, 2);
		}

		iluRegioniv(arr.ptr, arr.length);

		version(CrocILCheckErrors)
		{
			auto err = ilGetError();

			if(err != IL_NO_ERROR)
				throwNamedException(t, "DevILException", "iluRegioniv - {}", fromStringz(cast(char*)iluErrorString(err)));
		}

		return 0;
	}

	void ilFuncs(CrocThread* t)
	{
		register(t, "ilActiveImage", &wrapIL!(ilActiveImage));
		register(t, "ilActiveLayer", &wrapIL!(ilActiveLayer));
		register(t, "ilActiveMipmap", &wrapIL!(ilActiveMipmap));
		register(t, "ilApplyPal", &wrapIL!(ilApplyPal));
		register(t, "ilApplyProfile", &wrapIL!(ilApplyProfile));
		register(t, "ilBindImage", &wrapIL!(ilBindImage));
		register(t, "ilBlit", &wrapIL!(ilBlit));
		register(t, "ilClearColour", &wrapIL!(ilClearColour));
		register(t, "ilClearImage", &wrapIL!(ilClearImage));
		register(t, "ilCloneCurImage", &wrapIL!(ilCloneCurImage));
		register(t, "ilCompressFunc", &wrapIL!(ilCompressFunc));
		register(t, "ilConvertImage", &wrapIL!(ilConvertImage));
		register(t, "ilConvertPal", &wrapIL!(ilConvertPal));
		register(t, "ilCopyImage", &wrapIL!(ilCopyImage));
		register(t, "ilCopyPixels", &wrapIL!(ilCopyPixels));
		register(t, "ilCreateSubImage", &wrapIL!(ilCreateSubImage));
		register(t, "ilDefaultImage", &wrapIL!(ilDefaultImage));
		register(t, "ilDeleteImage", &wrapIL!(ilDeleteImage));
		register(t, "ilDeleteImages", &wrapIL!(ilDeleteImages));
		register(t, "ilDisable", &wrapIL!(ilDisable));
		register(t, "ilEnable", &wrapIL!(ilEnable));
		register(t, "ilFormatFunc", &wrapIL!(ilFormatFunc));
		register(t, "ilGenImages", &wrapIL!(ilGenImages));
		register(t, "ilGenImage", &wrapIL!(ilGenImage));
		register(t, "ilGetBoolean", &wrapIL!(ilGetBoolean));
		register(t, "ilGetBooleanv", &wrapIL!(ilGetBooleanv));
		register(t, "ilGetDXTCData", &wrapIL!(ilGetDXTCData));
		register(t, "ilGetError", &wrapIL!(ilGetError));
		register(t, "ilGetInteger", &wrapIL!(ilGetInteger));
		register(t, "ilGetIntegerv", &wrapIL!(ilGetIntegerv));
		register(t, "ilGetLumpPos", &wrapIL!(ilGetLumpPos));
		register(t, "ilGetString", &wrapIL!(ilGetString));
		register(t, "ilHint", &wrapIL!(ilHint));
		register(t, "ilInit", &wrapIL!(ilInit));
		register(t, "ilIsDisabled", &wrapIL!(ilIsDisabled));
		register(t, "ilIsEnabled", &wrapIL!(ilIsEnabled));
		register(t, "ilIsImage", &wrapIL!(ilIsImage));
		register(t, "ilIsValid", &wrapIL!(ilIsValid));
		register(t, "ilIsValidL", &wrapIL!(ilIsValidL));
		register(t, "ilKeyColour", &wrapIL!(ilKeyColour));
		register(t, "ilLoad", &wrapIL!(ilLoad));
		register(t, "ilLoadImage", &wrapIL!(ilLoadImage));
		register(t, "ilLoadL", &wrapIL!(ilLoadL));
		register(t, "ilLoadPal", &wrapIL!(ilLoadPal));
		register(t, "ilModAlpha", &wrapIL!(ilModAlpha));
		register(t, "ilOriginFunc", &wrapIL!(ilOriginFunc));
		register(t, "ilOverlayImage", &wrapIL!(ilOverlayImage));
		register(t, "ilPopAttrib", &wrapIL!(ilPopAttrib));
		register(t, "ilPushAttrib", &wrapIL!(ilPushAttrib));
		register(t, "ilSave", &wrapIL!(ilSave));
		register(t, "ilSaveImage", &wrapIL!(ilSaveImage));
		register(t, "ilSaveL", &wrapIL!(ilSaveL));
		register(t, "ilSavePal", &wrapIL!(ilSavePal));
		register(t, "ilSetAlpha", &wrapIL!(ilSetAlpha));
		register(t, "ilSetDuration", &wrapIL!(ilSetDuration));
		register(t, "ilSetInteger", &wrapIL!(ilSetInteger));
		register(t, "ilSetPixels", &wrapIL!(ilSetPixels));
		register(t, "ilSetString", &wrapIL!(ilSetString));
		register(t, "ilShutDown", &wrapIL!(ilShutDown));
		register(t, "ilTexImage", &wrapIL!(ilTexImage));
		register(t, "ilTypeFromExt", &wrapIL!(ilTypeFromExt));
		register(t, "ilTypeFunc", &wrapIL!(ilTypeFunc));
		register(t, "ilLoadData", &wrapIL!(ilLoadData));
		register(t, "ilLoadDataL", &wrapIL!(ilLoadDataL));
		register(t, "ilSaveData", &wrapIL!(ilSaveData));

		// These use C FILE*s.
// 		register(t, "ilDetermineTypeF", &wrapIL!(ilDetermineTypeF));
// 		register(t, "ilIsValidF", &wrapIL!(ilIsValidF));
// 		register(t, "ilLoadF", &wrapIL!(ilLoadF));
// 		register(t, "ilLoadDataF", &wrapIL!(ilLoadDataF));
// 		register(t, "ilSaveF", &wrapIL!(ilSaveF));

		// These all use C function pointers (or are rendered useless because they can only be called from C callbacks).
// 		register(t, "ilSetMemory", &wrapIL!(ilSetMemory));
// 		register(t, "ilSetRead", &wrapIL!(ilSetRead));
// 		register(t, "ilSetWrite", &wrapIL!(ilSetWrite));
// 		register(t, "ilRegisterFormat", &wrapIL!(ilRegisterFormat));
// 		register(t, "ilRegisterLoad", &wrapIL!(ilRegisterLoad));
// 		register(t, "ilRegisterMipNum", &wrapIL!(ilRegisterMipNum));
// 		register(t, "ilRegisterNumImages", &wrapIL!(ilRegisterNumImages));
// 		register(t, "ilRegisterOrigin", &wrapIL!(ilRegisterOrigin));
// 		register(t, "ilRegisterPal", &wrapIL!(ilRegisterPal));
// 		register(t, "ilRegisterSave", &wrapIL!(ilRegisterSave));
// 		register(t, "ilRegisterType", &wrapIL!(ilRegisterType));
// 		register(t, "ilRemoveLoad", &wrapIL!(ilRemoveLoad));
// 		register(t, "ilRemoveSave", &wrapIL!(ilRemoveSave));
// 		register(t, "ilResetRead", &wrapIL!(ilResetRead));
// 		register(t, "ilResetWrite", &wrapIL!(ilResetWrite));

		// This passes off a pointer to the library, which is unsafe. The fix is to dup the memory, buuuut then that makes it
		// no different than ilSetPixels. So.
// 		register(t, "ilSetData", &wrapIL!(ilSetData));

		pushGlobal(t, "ilClearColour"); newGlobal(t, "ilClearColor");
		pushGlobal(t, "ilKeyColour");   newGlobal(t, "ilKeyColor");

		pushBool(t, IL_FALSE); newGlobal(t, "IL_FALSE");
		pushBool(t, IL_TRUE);  newGlobal(t, "IL_TRUE");

		// Matches OpenGL's right now.
		registerConst(t, "IL_COLOUR_INDEX", 0x1900);
		registerConst(t, "IL_COLOR_INDEX", 0x1900);
		registerConst(t, "IL_RGB", 0x1907);
		registerConst(t, "IL_RGBA", 0x1908);
		registerConst(t, "IL_BGR", 0x80E0);
		registerConst(t, "IL_BGRA", 0x80E1);
		registerConst(t, "IL_LUMINANCE", 0x1909);
		registerConst(t, "IL_LUMINANCE_ALPHA", 0x190A);

		registerConst(t, "IL_BYTE", 0x1400);
		registerConst(t, "IL_UNSIGNED_BYTE", 0x1401);
		registerConst(t, "IL_SHORT", 0x1402);
		registerConst(t, "IL_UNSIGNED_SHORT", 0x1403);
		registerConst(t, "IL_INT", 0x1404);
		registerConst(t, "IL_UNSIGNED_INT", 0x1405);
		registerConst(t, "IL_FLOAT", 0x1406);
		registerConst(t, "IL_DOUBLE", 0x140A);
		registerConst(t, "IL_HALF", 0x140B);

		registerConst(t, "IL_VENDOR", 0x1F00);
		registerConst(t, "IL_LOAD_EXT", 0x1F01);
		registerConst(t, "IL_SAVE_EXT", 0x1F02);

		// IL-specific//
		registerConst(t, "IL_VERSION_1_7_3", 1);
		registerConst(t, "IL_VERSION", 173);

		// Attribute Bits
		registerConst(t, "IL_ORIGIN_BIT", 0x00000001);
		registerConst(t, "IL_FILE_BIT", 0x00000002);
		registerConst(t, "IL_PAL_BIT", 0x00000004);
		registerConst(t, "IL_FORMAT_BIT", 0x00000008);
		registerConst(t, "IL_TYPE_BIT", 0x00000010);
		registerConst(t, "IL_COMPRESS_BIT", 0x00000020);
		registerConst(t, "IL_LOADFAIL_BIT", 0x00000040);
		registerConst(t, "IL_FORMAT_SPECIFIC_BIT", 0x00000080);
		registerConst(t, "IL_ALL_ATTRIB_BITS", 0x000FFFFF);

		// Palette types
		registerConst(t, "IL_PAL_NONE", 0x0400);
		registerConst(t, "IL_PAL_RGB24", 0x0401);
		registerConst(t, "IL_PAL_RGB32", 0x0402);
		registerConst(t, "IL_PAL_RGBA32", 0x0403);
		registerConst(t, "IL_PAL_BGR24", 0x0404);
		registerConst(t, "IL_PAL_BGR32", 0x0405);
		registerConst(t, "IL_PAL_BGRA32", 0x0406);

		// Image types
		registerConst(t, "IL_TYPE_UNKNOWN", 0x0000);
		registerConst(t, "IL_BMP", 0x0420);
		registerConst(t, "IL_CUT", 0x0421);
		registerConst(t, "IL_DOOM", 0x0422);
		registerConst(t, "IL_DOOM_FLAT", 0x0423);
		registerConst(t, "IL_ICO", 0x0424);
		registerConst(t, "IL_JPG", 0x0425);
		registerConst(t, "IL_JFIF", 0x0425);
		registerConst(t, "IL_LBM", 0x0426);
		registerConst(t, "IL_PCD", 0x0427);
		registerConst(t, "IL_PCX", 0x0428);
		registerConst(t, "IL_PIC", 0x0429);
		registerConst(t, "IL_PNG", 0x042A);
		registerConst(t, "IL_PNM", 0x042B);
		registerConst(t, "IL_SGI", 0x042C);
		registerConst(t, "IL_TGA", 0x042D);
		registerConst(t, "IL_TIF", 0x042E);
		registerConst(t, "IL_CHEAD", 0x042F);
		registerConst(t, "IL_RAW", 0x0430);
		registerConst(t, "IL_MDL", 0x0431);
		registerConst(t, "IL_WAL", 0x0432);
		registerConst(t, "IL_LIF", 0x0434);
		registerConst(t, "IL_MNG", 0x0435);
		registerConst(t, "IL_JNG", 0x0435);
		registerConst(t, "IL_GIF", 0x0436);
		registerConst(t, "IL_DDS", 0x0437);
		registerConst(t, "IL_DCX", 0x0438);
		registerConst(t, "IL_PSD", 0x0439);
		registerConst(t, "IL_EXIF", 0x043A);
		registerConst(t, "IL_PSP", 0x043B);
		registerConst(t, "IL_PIX", 0x043C);
		registerConst(t, "IL_PXR", 0x043D);
		registerConst(t, "IL_XPM", 0x043E);
		registerConst(t, "IL_HDR", 0x043F);
		registerConst(t, "IL_ICNS", 0x0440);
		registerConst(t, "IL_JP2", 0x0441);
		registerConst(t, "IL_EXR", 0x0442);
		registerConst(t, "IL_WDP", 0x0443);
		registerConst(t, "IL_JASC_PAL", 0x0475);

		// Error Types
		registerConst(t, "IL_NO_ERROR", 0x0000);
		registerConst(t, "IL_INVALID_ENUM", 0x0501);
		registerConst(t, "IL_OUT_OF_MEMORY", 0x0502);
		registerConst(t, "IL_FORMAT_NOT_SUPPORTED", 0x0503);
		registerConst(t, "IL_INTERNAL_ERROR", 0x0504);
		registerConst(t, "IL_INVALID_VALUE", 0x0505);
		registerConst(t, "IL_ILLEGAL_OPERATION", 0x0506);
		registerConst(t, "IL_ILLEGAL_FILE_VALUE", 0x0507);
		registerConst(t, "IL_INVALID_FILE_HEADER", 0x0508);
		registerConst(t, "IL_INVALID_PARAM", 0x0509);
		registerConst(t, "IL_COULD_NOT_OPEN_FILE", 0x050A);
		registerConst(t, "IL_INVALID_EXTENSION", 0x050B);
		registerConst(t, "IL_FILE_ALREADY_EXISTS", 0x050C);
		registerConst(t, "IL_OUT_FORMAT_SAME", 0x050D);
		registerConst(t, "IL_STACK_OVERFLOW", 0x050E);
		registerConst(t, "IL_STACK_UNDERFLOW", 0x050F);
		registerConst(t, "IL_INVALID_CONVERSION", 0x0510);
		registerConst(t, "IL_BAD_DIMENSIONS", 0x0511);
		registerConst(t, "IL_FILE_READ_ERROR", 0x0512);
		registerConst(t, "IL_FILE_WRITE_ERROR", 0x0512);

		registerConst(t, "IL_LIB_GIF_ERROR", 0x05E1);
		registerConst(t, "IL_LIB_JPEG_ERROR", 0x05E2);
		registerConst(t, "IL_LIB_PNG_ERROR", 0x05E3);
		registerConst(t, "IL_LIB_TIFF_ERROR", 0x05E4);
		registerConst(t, "IL_LIB_MNG_ERROR", 0x05E5);
		registerConst(t, "IL_LIB_JP2_ERROR", 0x05E6);
		registerConst(t, "IL_UNKNOWN_ERROR", 0x05FF);

		// Origin Definitions
		registerConst(t, "IL_ORIGIN_SET", 0x0600);
		registerConst(t, "IL_ORIGIN_LOWER_LEFT", 0x0601);
		registerConst(t, "IL_ORIGIN_UPPER_LEFT", 0x0602);
		registerConst(t, "IL_ORIGIN_MODE", 0x0603);

		// Format and Type Mode Definitions
		registerConst(t, "IL_FORMAT_SET", 0x0610);
		registerConst(t, "IL_FORMAT_MODE", 0x0611);
		registerConst(t, "IL_TYPE_SET", 0x0612);
		registerConst(t, "IL_TYPE_MODE", 0x0613);

		// File definitions
		registerConst(t, "IL_FILE_OVERWRITE", 0x0620);
		registerConst(t, "IL_FILE_MODE", 0x0621);

		// Palette definitions
		registerConst(t, "IL_CONV_PAL", 0x0630);

		// Load fail definitions
		registerConst(t, "IL_DEFAULT_ON_FAIL", 0x0632);

		// Key colour definitions
		registerConst(t, "IL_USE_KEY_COLOUR", 0x0635);
		registerConst(t, "IL_USE_KEY_COLOR", 0x0635);

		// Interlace definitions
		registerConst(t, "IL_SAVE_INTERLACED", 0x0639);
		registerConst(t, "IL_INTERLACE_MODE", 0x063A);

		// Quantization definitions
		registerConst(t, "IL_QUANTIZATION_MODE", 0x0640);
		registerConst(t, "IL_WU_QUANT", 0x0641);
		registerConst(t, "IL_NEU_QUANT", 0x0642);
		registerConst(t, "IL_NEU_QUANT_SAMPLE", 0x0643);
		registerConst(t, "IL_MAX_QUANT_INDEXS", 0x0644);

		// Hints
		registerConst(t, "IL_FASTEST", 0x0660);
		registerConst(t, "IL_LESS_MEM", 0x0661);
		registerConst(t, "IL_DONT_CARE", 0x0662);
		registerConst(t, "IL_MEM_SPEED_HINT", 0x0665);
		registerConst(t, "IL_USE_COMPRESSION", 0x0666);
		registerConst(t, "IL_NO_COMPRESSION", 0x0667);
		registerConst(t, "IL_COMPRESSION_HINT", 0x0668);

		// Subimage types
		registerConst(t, "IL_SUB_NEXT", 0x0680);
		registerConst(t, "IL_SUB_MIPMAP", 0x0681);
		registerConst(t, "IL_SUB_LAYER", 0x0682);

		// Compression definitions
		registerConst(t, "IL_COMPRESS_MODE", 0x0700);
		registerConst(t, "IL_COMPRESS_NONE", 0x0701);
		registerConst(t, "IL_COMPRESS_RLE", 0x0702);
		registerConst(t, "IL_COMPRESS_LZO", 0x0703);
		registerConst(t, "IL_COMPRESS_ZLIB", 0x0704);

		// File format-specific values
		registerConst(t, "IL_TGA_CREATE_STAMP", 0x0710);
		registerConst(t, "IL_JPG_QUALITY", 0x0711);
		registerConst(t, "IL_PNG_INTERLACE", 0x0712);
		registerConst(t, "IL_TGA_RLE", 0x0713);
		registerConst(t, "IL_BMP_RLE", 0x0714);
		registerConst(t, "IL_SGI_RLE", 0x0715);
		registerConst(t, "IL_TGA_ID_STRING", 0x0717);
		registerConst(t, "IL_TGA_AUTHNAME_STRING", 0x0718);
		registerConst(t, "IL_TGA_AUTHCOMMENT_STRING", 0x0719);
		registerConst(t, "IL_PNG_AUTHNAME_STRING", 0x071A);
		registerConst(t, "IL_PNG_TITLE_STRING", 0x071B);
		registerConst(t, "IL_PNG_DESCRIPTION_STRING", 0x071C);
		registerConst(t, "IL_TIF_DESCRIPTION_STRING", 0x071D);
		registerConst(t, "IL_TIF_HOSTCOMPUTER_STRING", 0x071E);
		registerConst(t, "IL_TIF_DOCUMENTNAME_STRING", 0x071F);
		registerConst(t, "IL_TIF_AUTHNAME_STRING", 0x0720);
		registerConst(t, "IL_JPG_SAVE_FORMAT", 0x0721);
		registerConst(t, "IL_CHEAD_HEADER_STRING", 0x0722);
		registerConst(t, "IL_PCD_PICNUM", 0x0723);
		registerConst(t, "IL_PNG_ALPHA_INDEX", 0x0724);

		// DXTC definitions
		registerConst(t, "IL_DXTC_FORMAT", 0x0705);
		registerConst(t, "IL_DXT1", 0x0706);
		registerConst(t, "IL_DXT2", 0x0707);
		registerConst(t, "IL_DXT3", 0x0708);
		registerConst(t, "IL_DXT4", 0x0709);
		registerConst(t, "IL_DXT5", 0x070A);
		registerConst(t, "IL_DXT_NO_COMP", 0x070B);
		registerConst(t, "IL_KEEP_DXTC_DATA", 0x070C);
		registerConst(t, "IL_DXTC_DATA_FORMAT", 0x070D);
		registerConst(t, "IL_3DC", 0x070E);
		registerConst(t, "IL_RXGB", 0x070F);
		registerConst(t, "IL_ATI1N", 0x0710);

		// Cube map definitions
		registerConst(t, "IL_CUBEMAP_POSITIVEX", 0x00000400);
		registerConst(t, "IL_CUBEMAP_NEGATIVEX", 0x00000800);
		registerConst(t, "IL_CUBEMAP_POSITIVEY", 0x00001000);
		registerConst(t, "IL_CUBEMAP_NEGATIVEY", 0x00002000);
		registerConst(t, "IL_CUBEMAP_POSITIVEZ", 0x00004000);
		registerConst(t, "IL_CUBEMAP_NEGATIVEZ", 0x00008000);

		// Values
		registerConst(t, "IL_VERSION_NUM", 0x0DE2);
		registerConst(t, "IL_IMAGE_WIDTH", 0x0DE4);
		registerConst(t, "IL_IMAGE_HEIGHT", 0x0DE5);
		registerConst(t, "IL_IMAGE_DEPTH", 0x0DE6);
		registerConst(t, "IL_IMAGE_SIZE_OF_DATA", 0x0DE7);
		registerConst(t, "IL_IMAGE_BPP", 0x0DE8);
		registerConst(t, "IL_IMAGE_BYTES_PER_PIXEL", 0x0DE8);
		registerConst(t, "IL_IMAGE_BITS_PER_PIXEL", 0x0DE9);
		registerConst(t, "IL_IMAGE_FORMAT", 0x0DEA);
		registerConst(t, "IL_IMAGE_TYPE", 0x0DEB);
		registerConst(t, "IL_PALETTE_TYPE", 0x0DEC);
		registerConst(t, "IL_PALETTE_SIZE", 0x0DED);
		registerConst(t, "IL_PALETTE_BPP", 0x0DEE);
		registerConst(t, "IL_PALETTE_NUM_COLS", 0x0DEF);
		registerConst(t, "IL_PALETTE_BASE_TYPE", 0x0DF0);
		registerConst(t, "IL_NUM_IMAGES", 0x0DF1);
		registerConst(t, "IL_NUM_MIPMAPS", 0x0DF2);
		registerConst(t, "IL_NUM_LAYERS", 0x0DF3);
		registerConst(t, "IL_ACTIVE_IMAGE", 0x0DF4);
		registerConst(t, "IL_ACTIVE_MIPMAP", 0x0DF5);
		registerConst(t, "IL_ACTIVE_LAYER", 0x0DF6);
		registerConst(t, "IL_CUR_IMAGE", 0x0DF7);
		registerConst(t, "IL_IMAGE_DURATION", 0x0DF8);
		registerConst(t, "IL_IMAGE_PLANESIZE", 0x0DF9);
		registerConst(t, "IL_IMAGE_BPC", 0x0DFA);
		registerConst(t, "IL_IMAGE_OFFX", 0x0DFB);
		registerConst(t, "IL_IMAGE_OFFY", 0x0DFC);
		registerConst(t, "IL_IMAGE_CUBEFLAGS", 0x0DFD);
		registerConst(t, "IL_IMAGE_ORIGIN", 0x0DFE);
		registerConst(t, "IL_IMAGE_CHANNELS", 0x0DFF);
	}

	void iluFuncs(CrocThread* t)
	{
		register(t, "iluAlienify", &wrapIL!(iluAlienify));
		register(t, "iluBlurAvg", &wrapIL!(iluBlurAvg));
		register(t, "iluBlurGaussian", &wrapIL!(iluBlurGaussian));
		register(t, "iluBuildMipmaps", &wrapIL!(iluBuildMipmaps));
		register(t, "iluColoursUsed", &wrapIL!(iluColoursUsed));
		register(t, "iluCompareImage", &wrapIL!(iluCompareImage));
		register(t, "iluContrast", &wrapIL!(iluContrast));
		register(t, "iluCrop", &wrapIL!(iluCrop));
		register(t, "iluDeleteImage", &wrapIL!(iluDeleteImage));
		register(t, "iluEdgeDetectE", &wrapIL!(iluEdgeDetectE));
		register(t, "iluEdgeDetectP", &wrapIL!(iluEdgeDetectP));
		register(t, "iluEdgeDetectS", &wrapIL!(iluEdgeDetectS));
		register(t, "iluEmboss", &wrapIL!(iluEmboss));
		register(t, "iluEnlargeCanvas", &wrapIL!(iluEnlargeCanvas));
		register(t, "iluEnlargeImage", &wrapIL!(iluEnlargeImage));
		register(t, "iluEqualize", &wrapIL!(iluEqualize));
		register(t, "iluErrorString", &wrapIL!(iluErrorString));
		register(t, "iluConvolution", &wrapIL!(iluConvolution));
		register(t, "iluFlipImage", &wrapIL!(iluFlipImage));
		register(t, "iluGammaCorrect", &wrapIL!(iluGammaCorrect));
		register(t, "iluGenImage", &wrapIL!(iluGenImage));
		register(t, "iluGetInteger", &wrapIL!(iluGetInteger));
		register(t, "iluGetIntegerv", &wrapIL!(iluGetIntegerv));
		register(t, "iluGetString", &wrapIL!(iluGetString));
		register(t, "iluImageParameter", &wrapIL!(iluImageParameter));
		register(t, "iluInit", &wrapIL!(iluInit));
		register(t, "iluInvertAlpha", &wrapIL!(iluInvertAlpha));
		register(t, "iluLoadImage", &wrapIL!(iluLoadImage));
		register(t, "iluMirror", &wrapIL!(iluMirror));
		register(t, "iluNegative", &wrapIL!(iluNegative));
		register(t, "iluNoisify", &wrapIL!(iluNoisify));
		register(t, "iluPixelize", &wrapIL!(iluPixelize));
		register(t, "iluReplaceColour", &wrapIL!(iluReplaceColour));
		register(t, "iluRotate", &wrapIL!(iluRotate));
		register(t, "iluRotate3D", &wrapIL!(iluRotate3D));
		register(t, "iluSaturate1f", &wrapIL!(iluSaturate1f));
		register(t, "iluSaturate4f", &wrapIL!(iluSaturate4f));
		register(t, "iluScale", &wrapIL!(iluScale));
		register(t, "iluScaleColours", &wrapIL!(iluScaleColours));
		register(t, "iluSetLanguage", &wrapIL!(iluSetLanguage));
		register(t, "iluSharpen", &wrapIL!(iluSharpen));
		register(t, "iluSwapColours", &wrapIL!(iluSwapColours));
		register(t, "iluWave", &wrapIL!(iluWave));

		pushGlobal(t, "iluColoursUsed");   newGlobal(t, "iluColorsUsed");
		pushGlobal(t, "iluSwapColours");   newGlobal(t, "iluSwapColors");
		pushGlobal(t, "iluReplaceColour"); newGlobal(t, "iluReplaceColor");
		pushGlobal(t, "iluScaleColours");  newGlobal(t, "iluScaleColors");

	    registerConst(t, "ILU_VERSION_1_7_3", 1);
	    registerConst(t, "ILU_VERSION", 173);

	    registerConst(t, "ILU_FILTER", 0x2600);
	    registerConst(t, "ILU_NEAREST", 0x2601);
	    registerConst(t, "ILU_LINEAR", 0x2602);
	    registerConst(t, "ILU_BILINEAR", 0x2603);
	    registerConst(t, "ILU_SCALE_BOX", 0x2604);
	    registerConst(t, "ILU_SCALE_TRIANGLE", 0x2605);
	    registerConst(t, "ILU_SCALE_BELL", 0x2606);
	    registerConst(t, "ILU_SCALE_BSPLINE", 0x2607);
	    registerConst(t, "ILU_SCALE_LANCZOS3", 0x2608);
	    registerConst(t, "ILU_SCALE_MITCHELL", 0x2609);

	    // Error types
	    registerConst(t, "ILU_INVALID_ENUM", 0x0501);
	    registerConst(t, "ILU_OUT_OF_MEMORY", 0x0502);
	    registerConst(t, "ILU_INTERNAL_ERROR", 0x0504);
	    registerConst(t, "ILU_INVALID_VALUE", 0x0505);
	    registerConst(t, "ILU_ILLEGAL_OPERATION", 0x0506);
	    registerConst(t, "ILU_INVALID_PARAM", 0x0509);

	    // Values
	    registerConst(t, "ILU_PLACEMENT", 0x0700);
	    registerConst(t, "ILU_LOWER_LEFT", 0x0701);
	    registerConst(t, "ILU_LOWER_RIGHT", 0x0702);
	    registerConst(t, "ILU_UPPER_LEFT", 0x0703);
	    registerConst(t, "ILU_UPPER_RIGHT", 0x0704);
	    registerConst(t, "ILU_CENTER", 0x0705);
	    registerConst(t, "ILU_CONVOLUTION_MATRIX", 0x0710);

	    registerConst(t, "ILU_VERSION_NUM", IL_VERSION_NUM);
	    registerConst(t, "ILU_VENDOR", IL_VENDOR);

	    // Languages
	    registerConst(t, "ILU_ENGLISH", 0x800);
	    registerConst(t, "ILU_ARABIC", 0x801);
	    registerConst(t, "ILU_DUTCH", 0x802);
	    registerConst(t, "ILU_JAPANESE", 0x803);
	    registerConst(t, "ILU_SPANISH", 0x804);
	}
}

}
