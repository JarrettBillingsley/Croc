#ifndef CROC_IMGUI_ADDON
#include "croc/api.h"

namespace croc
{
void initImGuiLib(CrocThread* t)
{
	croc_eh_throwStd(t, "ApiError", "Attempting to load the imgui library, but it was not compiled in");
}
}
#else

namespace ImGui
{
	int WindowStackDepth();
	bool IsInitialized();
}

#include "croc/ext/imgui/imgui.h"

#include "croc/api.h"
#include "croc/internal/stack.hpp"
#include "croc/stdlib/helpers/register.hpp"
#include "croc/types/base.hpp"

namespace croc
{
namespace
{

#ifdef CROC_BUILTIN_DOCS
const char* moduleDocs = DModule("imgui")
R"()";
#endif

// =====================================================================================================================
// Helpers

const char* IniFilename = "imgui.IniFilename";
const char* LogFilename = "imgui.LogFilename";
const char* RenderDrawListsCallback = "imgui.RenderDrawListsCallback";
const char* GetClipboardTextCallback = "imgui.GetClipboardTextCallback";
const char* SetClipboardTextCallback = "imgui.SetClipboardTextCallback";
const char* ImeSetInputScreenPosCallback = "imgui.ImeSetInputScreenPosCallback";
const char* ClipboardText = "imgui.ClipboardText";
const char* DrawListVerts = "imgui.DrawListVerts";
const char* DrawListCommands = "imgui.DrawListCommands";

inline crocstr checkCrocstrParam(CrocThread* t, word_t slot)
{
	crocstr ret;
	ret.ptr = cast(const uchar*)croc_ex_checkStringParamn(t, slot, &ret.length);
	return ret;
}

// static! global state! aaaaaaa!
CrocThread* boundVM = nullptr;
bool insideTooltip = false;

inline void checkVM(CrocThread* t)
{
	if(boundVM == nullptr)
		croc_eh_throwStd(t, "StateError", "Attempting to access imgui before initializing");

	if(croc_vm_getMainThread(t) != boundVM)
		croc_eh_throwStd(t, "StateError", "Attempting to access imgui from the wrong Croc VM");
}

word getCallback(CrocThread* t, const char* name)
{
	auto ret = croc_vm_pushRegistry(t);

	if(croc_hasField(t, -1, name))
	{
		croc_field(t, -1, name);
		croc_insertAndPop(t, -2);
	}
	else
	{
		croc_popTop(t);
		croc_pushNull(t);
	}

	return ret;
}

void noRenderDrawLists(ImDrawList** const draw_lists, int count)
{
	(void)draw_lists;
	(void)count;

	assert(boundVM != nullptr);
	auto t = croc_vm_getCurrentThread(boundVM);
	croc_eh_throwStd(t, "StateError", "No RenderDrawLists callback function registered!");
}

void renderDrawLists(ImDrawList** const draw_lists, int count)
{
	assert(boundVM != nullptr);
	auto t = croc_vm_getCurrentThread(boundVM);

	// Make sure we have the command array and vertex data memblock
	auto registry = croc_vm_pushRegistry(t); // reg

	if(!croc_hasField(t, registry, DrawListVerts))
	{
		croc_memblock_new(t, 0);
		croc_fielda(t, registry, DrawListVerts);
	}

	if(!croc_hasField(t, registry, DrawListCommands))
	{
		croc_array_new(t, 0);
		croc_fielda(t, registry, DrawListCommands);
	}

	auto fn = getCallback(t, RenderDrawListsCallback); // reg fn
	croc_pushNull(t); // reg fn null

	// Glob all the verts into one memblock
	auto verts = croc_field(t, registry, DrawListVerts); // reg fn null verts
	uword numVerts = 0;
	uword numCommands = 0;

	for(int i = 0; i < count; i++)
	{
		numVerts += draw_lists[i]->vtx_buffer.size();
		numCommands += draw_lists[i]->commands.size();
	}

	auto newSize = numVerts * sizeof(ImDrawVert);

	if(croc_len(t, verts) < newSize)
		croc_lenai(t, verts, newSize);

	croc_pushInt(t, newSize); // reg fn null verts vertSize

	auto vbuf = cast(uint8_t*)croc_memblock_getData(t, verts);

	for(int i = 0; i < count; i++)
	{
		auto &v = draw_lists[i]->vtx_buffer;
		auto size = v.size() * sizeof(ImDrawVert);
		memcpy(vbuf, v.begin(), size);
		vbuf += size;
	}

	// Convert and glob all the commands into one array
	auto commands = croc_field(t, registry, DrawListCommands); // reg fn null verts vertSize commands
	auto oldLen = croc_len(t, commands);

	if(oldLen < numCommands)
	{
		croc_lenai(t, commands, numCommands);

		for(uword i = oldLen; i < numCommands; i++)
		{
			croc_table_new(t, 5);
			croc_idxai(t, commands, i);
		}
	}

	uword commandIdx = 0;

	for(int i = 0; i < count; i++)
	{
		auto cmds = draw_lists[i]->commands.begin();
		auto cmdsSize = draw_lists[i]->commands.size();

		for(uword j = 0; j < cmdsSize; j++, commandIdx++)
		{
			auto &cmd = cmds[j];
			croc_idxi(t, commands, commandIdx);
			croc_pushInt(t, cmd.vtx_count); croc_fielda(t, -2, "numVerts");
			croc_pushInt(t, cast(crocint)cmd.clip_rect.x); croc_fielda(t, -2, "clipL");
			croc_pushInt(t, cast(crocint)cmd.clip_rect.y); croc_fielda(t, -2, "clipT");
			croc_pushInt(t, cast(crocint)cmd.clip_rect.z); croc_fielda(t, -2, "clipR");
			croc_pushInt(t, cast(crocint)cmd.clip_rect.w); croc_fielda(t, -2, "clipB");
			croc_popTop(t);
		}
	}

	croc_pushInt(t, numCommands); // reg fn null verts vertSize commands numCommands

	// Call it.
	croc_call(t, fn, 0);
	croc_popTop(t); // pop registry
}

const char* getClipboardText()
{
	assert(boundVM != nullptr);
	auto t = croc_vm_getCurrentThread(boundVM);
	auto fn = getCallback(t, GetClipboardTextCallback);
	croc_pushNull(t);
	croc_call(t, fn, 1);

	if(!croc_isString(t, -1))
		croc_eh_throwStd(t, "TypeError", "GetClipboardText callback expected to return a 'string'");

	croc_dupTop(t);
	croc_ex_setRegistryVar(t, ClipboardText);
	return croc_getString(t, -1);
}

void setClipboardText(const char* text)
{
	assert(boundVM != nullptr);
	auto t = croc_vm_getCurrentThread(boundVM);
	auto fn = getCallback(t, SetClipboardTextCallback);
	croc_pushNull(t);
	croc_pushString(t, text);
	croc_call(t, fn, 0);
}

void imeSetInputScreenPos(int x, int y)
{
	assert(boundVM != nullptr);
	auto t = croc_vm_getCurrentThread(boundVM);
	auto fn = getCallback(t, ImeSetInputScreenPosCallback);
	croc_pushNull(t);
	croc_pushInt(t, x);
	croc_pushInt(t, y);
	croc_call(t, fn, 0);
}

inline void checkInsideTooltip(CrocThread* t, bool inside)
{
	if(insideTooltip != inside)
		croc_eh_throwStd(t, "StateError", "Attempting to begin/end a window while inside a tooltip");
}

inline void setInsideTooltip(bool inside)
{
	insideTooltip = inside;
}

inline void checkWindowEndable(CrocThread* t)
{
	if(ImGui::WindowStackDepth() <= 1)
		croc_eh_throwStd(t, "StateError", "No window to end");
}

inline void checkWindowBeginnable(CrocThread* t)
{
	if(ImGui::WindowStackDepth() == 0)
		croc_eh_throwStd(t, "StateError", "Attempting to begin a window outside newFrame/render pair");
}

inline void checkValidNewFrame(CrocThread* t)
{
	if(ImGui::WindowStackDepth() != 0)
		croc_eh_throwStd(t, "StateError", "No window begin..end pairs may be open when starting a new frame");
}

inline void checkValidRender(CrocThread* t)
{
	if(ImGui::WindowStackDepth() != 1)
		croc_eh_throwStd(t, "StateError", "Mismatched window begins/ends");
}

inline void checkHaveWindow(CrocThread* t)
{
	if(ImGui::WindowStackDepth() == 0)
		croc_eh_throwStd(t, "StateError", "No current window available (are you calling this function outside a "
			"newFrame/render pair?)");
}

void newStyle(CrocThread* t)
{
	croc_table_new(t, 21);
	croc_array_new(t, ImGuiCol_COUNT);

	for(int i = 0; i < ImGuiCol_COUNT; i++)
	{
		croc_array_new(t, 4);
		croc_pushFloat(t, 0);
		croc_array_fill(t, -2);
		croc_idxai(t, -2, i);
	}

	croc_fielda(t, -2, "colors");
}

void fillStyle(CrocThread* t, word slot, ImGuiStyle& style)
{
	croc_pushFloat(t, style.Alpha);                  croc_fielda(t, slot, "alpha");
	croc_pushFloat(t, style.WindowFillAlphaDefault); croc_fielda(t, slot, "windowFillAlphaDefault");
	croc_pushFloat(t, style.WindowRounding);         croc_fielda(t, slot, "windowRounding");
	croc_pushFloat(t, style.TreeNodeSpacing);        croc_fielda(t, slot, "treeNodeSpacing");
	croc_pushFloat(t, style.ColumnsMinSpacing);      croc_fielda(t, slot, "columnsMinSpacing");
	croc_pushFloat(t, style.ScrollBarWidth);         croc_fielda(t, slot, "scrollBarWidth");
	croc_pushFloat(t, style.WindowPadding.x);        croc_fielda(t, slot, "windowPaddingX");
	croc_pushFloat(t, style.WindowPadding.y);        croc_fielda(t, slot, "windowPaddingY");
	croc_pushFloat(t, style.WindowMinSize.x);        croc_fielda(t, slot, "windowMinSizeX");
	croc_pushFloat(t, style.WindowMinSize.y);        croc_fielda(t, slot, "windowMinSizeY");
	croc_pushFloat(t, style.FramePadding.x);         croc_fielda(t, slot, "framePaddingX");
	croc_pushFloat(t, style.FramePadding.y);         croc_fielda(t, slot, "framePaddingY");
	croc_pushFloat(t, style.ItemSpacing.x);          croc_fielda(t, slot, "itemSpacingX");
	croc_pushFloat(t, style.ItemSpacing.y);          croc_fielda(t, slot, "itemSpacingY");
	croc_pushFloat(t, style.ItemInnerSpacing.x);     croc_fielda(t, slot, "itemInnerSpacingX");
	croc_pushFloat(t, style.ItemInnerSpacing.y);     croc_fielda(t, slot, "itemInnerSpacingY");
	croc_pushFloat(t, style.TouchExtraPadding.x);    croc_fielda(t, slot, "touchExtraPaddingX");
	croc_pushFloat(t, style.TouchExtraPadding.y);    croc_fielda(t, slot, "touchExtraPaddingY");
	croc_pushFloat(t, style.AutoFitPadding.x);       croc_fielda(t, slot, "autoFitPaddingX");
	croc_pushFloat(t, style.AutoFitPadding.y);       croc_fielda(t, slot, "autoFitPaddingY");

	croc_field(t, slot, "colors");

	for(int i = 0; i < ImGuiCol_COUNT; i++)
	{
		croc_idxi(t, -1, i);
		croc_pushFloat(t, style.Colors[i].x); croc_idxai(t, -2, 0);
		croc_pushFloat(t, style.Colors[i].y); croc_idxai(t, -2, 1);
		croc_pushFloat(t, style.Colors[i].z); croc_idxai(t, -2, 2);
		croc_pushFloat(t, style.Colors[i].w); croc_idxai(t, -2, 3);
		croc_popTop(t);
	}

	croc_popTop(t);
}

void getStyle(CrocThread* t, word slot, ImGuiStyle& style)
{
	croc_field(t, slot, "alpha");                  style.Alpha =                  croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "windowFillAlphaDefault"); style.WindowFillAlphaDefault = croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "windowRounding");         style.WindowRounding =         croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "treeNodeSpacing");        style.TreeNodeSpacing =        croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "columnsMinSpacing");      style.ColumnsMinSpacing =      croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "scrollBarWidth");         style.ScrollBarWidth =         croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "windowPaddingX");         style.WindowPadding.x =        croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "windowPaddingY");         style.WindowPadding.y =        croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "windowMinSizeX");         style.WindowMinSize.x =        croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "windowMinSizeY");         style.WindowMinSize.y =        croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "framePaddingX");          style.FramePadding.x =         croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "framePaddingY");          style.FramePadding.y =         croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "itemSpacingX");           style.ItemSpacing.x =          croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "itemSpacingY");           style.ItemSpacing.y =          croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "itemInnerSpacingX");      style.ItemInnerSpacing.x =     croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "itemInnerSpacingY");      style.ItemInnerSpacing.y =     croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "touchExtraPaddingX");     style.TouchExtraPadding.x =    croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "touchExtraPaddingY");     style.TouchExtraPadding.y =    croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "autoFitPaddingX");        style.AutoFitPadding.x =       croc_getNum(t, -1); croc_popTop(t);
	croc_field(t, slot, "autoFitPaddingY");        style.AutoFitPadding.y =       croc_getNum(t, -1); croc_popTop(t);

	croc_field(t, slot, "colors");

	for(int i = 0; i < ImGuiCol_COUNT; i++)
	{
		croc_idxi(t, -1, i);
		croc_idxi(t, -1, 0); style.Colors[i].x = croc_getNum(t, -1); croc_popTop(t);
		croc_idxi(t, -1, 1); style.Colors[i].y = croc_getNum(t, -1); croc_popTop(t);
		croc_idxi(t, -1, 2); style.Colors[i].z = croc_getNum(t, -1); croc_popTop(t);
		croc_idxi(t, -1, 3); style.Colors[i].w = croc_getNum(t, -1);
		croc_pop(t, 2);
	}

	croc_popTop(t);
}

#define MAKE_GET_STATE(TYPE, CTYPE, TYPENAME)\
	CTYPE getState##TYPE(CrocThread* t, word container)\
	{\
		croc_dup(t, container + 1);\
		croc_fieldStk(t, container);\
\
		if(!croc_is##TYPE(t, -1))\
		{\
			croc_pushTypeString(t, -1);\
			croc_eh_throwStd(t, "TypeError", "Expected '" TYPENAME "' for state variable, not '%s'", croc_getString(t, -1));\
		}\
\
		auto ret = cast(CTYPE)croc_get##TYPE(t, -1);\
		croc_popTop(t);\
		return ret;\
	}

#define MAKE_SET_STATE(TYPE, CTYPE)\
	void setState##TYPE(CrocThread* t, word container, CTYPE val)\
	{\
		croc_dup(t, container + 1);\
		croc_push##TYPE(t, val);\
		croc_fieldaStk(t, container);\
	}

MAKE_GET_STATE(Bool, bool, "bool")
MAKE_SET_STATE(Bool, bool)
MAKE_GET_STATE(Int, int, "int")
MAKE_SET_STATE(Int, int)
MAKE_GET_STATE(Float, float, "float")
MAKE_SET_STATE(Float, float)

#define MAKE_GET_STATE_ARRAY(DIM)\
	void getStateFloat##DIM(CrocThread* t, word container, float vals[DIM])\
	{\
		croc_dup(t, container + 1);\
		croc_fieldStk(t, container);\
\
		if(!croc_isArray(t, -1) || croc_len(t, -1) != DIM)\
			croc_eh_throwStd(t, "TypeError", "Expected array of length " #DIM " for state variable");\
\
		for(int i = 0; i < DIM; i++)\
		{\
			croc_idxi(t, -1, i);\
\
			if(!croc_isNum(t, -1))\
				croc_eh_throwStd(t, "TypeError", "All elements of state array must be numbers");\
\
			vals[i] = croc_getNum(t, -1);\
			croc_popTop(t);\
		}\
\
		croc_popTop(t);\
	}

#define MAKE_SET_STATE_ARRAY(DIM)\
	void setStateFloat##DIM(CrocThread* t, word container, float vals[DIM])\
	{\
		croc_dup(t, container + 1);\
		croc_fieldStk(t, container);\
\
		for(int i = 0; i < DIM; i++)\
		{\
			croc_pushFloat(t, vals[i]);\
			croc_idxai(t, -2, i);\
		}\
\
		croc_popTop(t);\
	}

MAKE_GET_STATE_ARRAY(2)
MAKE_GET_STATE_ARRAY(3)
MAKE_GET_STATE_ARRAY(4)
MAKE_SET_STATE_ARRAY(2)
MAKE_SET_STATE_ARRAY(3)
MAKE_SET_STATE_ARRAY(4)

// =====================================================================================================================
// Global funcs

const StdlibRegisterInfo _init_info =
{
	Docstr(DFunc("init")
	R"(\b{Bound VM:} the ImGui library has only a single global state, and has some callback functions which are
	registered with it. Because of those reasons, this library only allows one VM to be "bound" to it any time. You must
	call this function to bind the VM to the library.

	Attempting to call this function again - from the same VM or from another - will throw a \link{StateError}. It is
	currently not possible to switch which VM is bound, short of calling \link{shutdown} in the bound VM and then this
	function in another.

	\throws[StateError] in the situation described above.)"),

	"init", 0
};

word_t _init(CrocThread* t)
{
	if(boundVM != nullptr)
		croc_eh_throwStd(t, "StateError", "Attempting to re-initialize the imgui library");

	boundVM = croc_vm_getMainThread(t);
	insideTooltip = false;

	auto &io = ImGui::GetIO();
	io.RenderDrawListsFn = &noRenderDrawLists;
	return 0;
}

const StdlibRegisterInfo _shutdown_info =
{
	Docstr(DFunc("shutdown")
	R"(\b{Bound VM:} this unbinds the current VM from the library as explained in \link{init}. Any callback functions
	currently registered with the library will be unregistered.)"),

	"shutdown", 0
};

word_t _shutdown(CrocThread* t)
{
	checkVM(t);

	auto &io = ImGui::GetIO();
	io.RenderDrawListsFn = nullptr;
	io.GetClipboardTextFn = nullptr;
	io.SetClipboardTextFn = nullptr;
	io.ImeSetInputScreenPosFn = nullptr;
	ImGui::Shutdown();

	croc_pushNull(t); croc_ex_setRegistryVar(t, RenderDrawListsCallback);
	croc_pushNull(t); croc_ex_setRegistryVar(t, GetClipboardTextCallback);
	croc_pushNull(t); croc_ex_setRegistryVar(t, SetClipboardTextCallback);
	croc_pushNull(t); croc_ex_setRegistryVar(t, ImeSetInputScreenPosCallback);
	insideTooltip = false;

	boundVM = nullptr;
	return 0;
}

const StdlibRegisterInfo _getStyle_info =
{
	Docstr(DFunc("getStyle")
	R"()"),

	"getStyle", 1
};

word_t _getStyle(CrocThread* t)
{
	checkVM(t);

	if(!croc_isValidIndex(t, 1))
		newStyle(t);

	fillStyle(t, 1, ImGui::GetStyle());
	return 1;
}

const StdlibRegisterInfo _setStyle_info =
{
	Docstr(DFunc("setStyle")
	R"()"),

	"setStyle", 1
};

word_t _setStyle(CrocThread* t)
{
	checkVM(t);
	getStyle(t, 1, ImGui::GetStyle());
	return 0;
}

const StdlibRegisterInfo _newFrame_info =
{
	Docstr(DFunc("newFrame")
	R"()"),

	"newFrame", 0
};

word_t _newFrame(CrocThread* t)
{
	checkVM(t);
	checkValidNewFrame(t);
	ImGui::NewFrame();
	return 0;
}

const StdlibRegisterInfo _render_info =
{
	Docstr(DFunc("render")
	R"()"),

	"render", 0
};

word_t _render(CrocThread* t)
{
	checkVM(t);
	checkValidRender(t);

	if(!ImGui::IsInitialized())
		croc_eh_throwStd(t, "StateError", "Attempting to render before calling newFrame at least once");

	ImGui::Render();
	return 0;
}

const StdlibRegisterInfo _showUserGuide_info =
{
	Docstr(DFunc("showUserGuide")
	R"()"),

	"showUserGuide", 0
};

word_t _showUserGuide(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::ShowUserGuide();
	return 0;
}

const StdlibRegisterInfo _showStyleEditor_info =
{
	Docstr(DFunc("showStyleEditor")
	R"()"),

	"showStyleEditor", 1
};

word_t _showStyleEditor(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);

	if(croc_isValidIndex(t, 1))
	{
		ImGuiStyle style;
		getStyle(t, 1, style);
		ImGui::ShowStyleEditor(&style);
		fillStyle(t, 1, style);
	}
	else
		ImGui::ShowStyleEditor(nullptr);

	return 0;
}

const StdlibRegisterInfo _showTestWindow_info =
{
	Docstr(DFunc("showTestWindow")
	R"()"),

	"showTestWindow", 0
};

word_t _showTestWindow(CrocThread* t)
{
	checkVM(t);
	checkInsideTooltip(t, false);
	checkHaveWindow(t);
	ImGui::ShowTestWindow(nullptr);
	return 0;
}

const StdlibRegisterInfo _showTestWindowClosable_info =
{
	Docstr(DFunc("showTestWindowClosable")
	R"()"),

	"showTestWindowClosable", 2
};

word_t _showTestWindowClosable(CrocThread* t)
{
	checkVM(t);
	checkInsideTooltip(t, false);
	checkHaveWindow(t);
	croc_ex_checkParam(t, 2, CrocType_String);
	auto show = getStateBool(t, 1);
	ImGui::ShowTestWindow(&show);
	setStateBool(t, 1, show);
	return 0;
}

const StdlibRegisterInfo _begin_info =
{
	Docstr(DFunc("begin")
	R"()"),

	"begin", 5
};

word_t _begin(CrocThread* t)
{
	checkVM(t);
	checkWindowBeginnable(t);
	checkInsideTooltip(t, false);
	auto name = croc_ex_optStringParam(t, 1, "Debug");
	auto width = croc_ex_optIntParam(t, 2, 0);
	auto height = croc_ex_optIntParam(t, 3, 0);
	auto fillAlpha = croc_ex_optNumParam(t, 4, -1.0);
	auto flags = croc_ex_optIntParam(t, 5, 0);
	croc_pushBool(t, ImGui::Begin(name, nullptr, ImVec2(width, height), fillAlpha, flags));
	return 1;
}

const StdlibRegisterInfo _beginClosable_info =
{
	Docstr(DFunc("beginClosable")
	R"()"),

	"beginClosable", 7
};

word_t _beginClosable(CrocThread* t)
{
	checkVM(t);
	checkWindowBeginnable(t);
	checkInsideTooltip(t, false);
	auto name = croc_ex_optStringParam(t, 1, "Debug");
	croc_ex_checkParam(t, 3, CrocType_String);
	auto width = croc_ex_optIntParam(t, 4, 0);
	auto height = croc_ex_optIntParam(t, 5, 0);
	auto fillAlpha = croc_ex_optNumParam(t, 6, -1.0);
	auto flags = croc_ex_optIntParam(t, 7, 0);
	auto open = getStateBool(t, 2);
	croc_pushBool(t, ImGui::Begin(name, &open, ImVec2(width, height), fillAlpha, flags));
	setStateBool(t, 2, open);
	return 1;
}

const StdlibRegisterInfo _end_info =
{
	Docstr(DFunc("end")
	R"()"),

	"end", 0
};

word_t _end(CrocThread* t)
{
	checkVM(t);
	checkWindowEndable(t);
	ImGui::End();
	return 0;
}

const StdlibRegisterInfo _beginChild_info =
{
	Docstr(DFunc("beginChild")
	R"()"),

	"beginChild", 5
};

word_t _beginChild(CrocThread* t)
{
	checkVM(t);
	checkWindowBeginnable(t);
	auto id = croc_ex_checkStringParam(t, 1);
	auto width = croc_ex_optIntParam(t, 2, 0);
	auto height = croc_ex_optIntParam(t, 3, 0);
	bool border = croc_ex_optBoolParam(t, 4, false);
	auto flags = croc_ex_optIntParam(t, 5, 0);
	ImGui::BeginChild(id, ImVec2(width, height), border, flags);
	return 0;
}

const StdlibRegisterInfo _endChild_info =
{
	Docstr(DFunc("endChild")
	R"()"),

	"endChild", 0
};

word_t _endChild(CrocThread* t)
{
	checkVM(t);
	checkWindowEndable(t);
	ImGui::EndChild();
	return 0;
}

const StdlibRegisterInfo _getWindowIsFocused_info =
{
	Docstr(DFunc("getWindowIsFocused")
	R"()"),

	"getWindowIsFocused", 0
};

word_t _getWindowIsFocused(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	croc_pushBool(t, ImGui::GetWindowIsFocused());
	return 1;
}

const StdlibRegisterInfo _getWindowSize_info =
{
	Docstr(DFunc("getWindowSize")
	R"()"),

	"getWindowSize", 0
};

word_t _getWindowSize(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto size = ImGui::GetWindowSize();
	croc_pushInt(t, cast(crocint)size.x);
	croc_pushInt(t, cast(crocint)size.y);
	return 2;
}

const StdlibRegisterInfo _getWindowWidth_info =
{
	Docstr(DFunc("getWindowWidth")
	R"()"),

	"getWindowWidth", 0
};

word_t _getWindowWidth(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	croc_pushInt(t, cast(crocint)ImGui::GetWindowWidth());
	return 1;
}

const StdlibRegisterInfo _setWindowSize_info =
{
	Docstr(DFunc("setWindowSize")
	R"()"),

	"setWindowSize", 2
};

word_t _setWindowSize(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto x = croc_ex_checkIntParam(t, 1);
	auto y = croc_ex_checkIntParam(t, 2);
	ImGui::SetWindowSize(ImVec2(x, y));
	return 0;
}

const StdlibRegisterInfo _getWindowPos_info =
{
	Docstr(DFunc("getWindowPos")
	R"()"),

	"getWindowPos", 0
};

word_t _getWindowPos(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto size = ImGui::GetWindowPos();
	croc_pushInt(t, cast(crocint)size.x);
	croc_pushInt(t, cast(crocint)size.y);
	return 2;
}

const StdlibRegisterInfo _setWindowPos_info =
{
	Docstr(DFunc("setWindowPos")
	R"()"),

	"setWindowPos", 2
};

word_t _setWindowPos(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto x = croc_ex_checkIntParam(t, 1);
	auto y = croc_ex_checkIntParam(t, 2);
	ImGui::SetWindowPos(ImVec2(x, y));
	return 0;
}

const StdlibRegisterInfo _getWindowContentRegion_info =
{
	Docstr(DFunc("getWindowContentRegion")
	R"()"),

	"getWindowContentRegion", 0
};

word_t _getWindowContentRegion(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto min = ImGui::GetWindowContentRegionMin();
	auto max = ImGui::GetWindowContentRegionMax();
	croc_pushInt(t, cast(crocint)min.x);
	croc_pushInt(t, cast(crocint)min.y);
	croc_pushInt(t, cast(crocint)max.x);
	croc_pushInt(t, cast(crocint)max.y);
	return 4;
}

// TODO: getWindowDrawList (needs window)
// TODO: getWindowFont (needs window)

const StdlibRegisterInfo _getWindowFontSize_info =
{
	Docstr(DFunc("getWindowFontSize")
	R"()"),

	"getWindowFontSize", 0
};

word_t _getWindowFontSize(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	croc_pushFloat(t, ImGui::GetWindowFontSize());
	return 1;
}

const StdlibRegisterInfo _setWindowFontScale_info =
{
	Docstr(DFunc("setWindowFontScale")
	R"()"),

	"setWindowFontScale", 1
};

word_t _setWindowFontScale(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::SetWindowFontScale(cast(float)croc_ex_checkNumParam(t, 1));
	return 0;
}

const StdlibRegisterInfo _setScrollPosHere_info =
{
	Docstr(DFunc("setScrollPosHere")
	R"()"),

	"setScrollPosHere", 0
};

word_t _setScrollPosHere(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::SetScrollPosHere();
	return 0;
}

const StdlibRegisterInfo _setKeyboardFocusHere_info =
{
	Docstr(DFunc("setKeyboardFocusHere")
	R"()"),

	"setKeyboardFocusHere", 1
};

word_t _setKeyboardFocusHere(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::SetKeyboardFocusHere(croc_ex_optIntParam(t, 1, 0));
	return 0;
}

// TODO: setTreeStateStorage (needs window)
// TODO: getTreeStateStorage (needs window)

const StdlibRegisterInfo _pushItemWidth_info =
{
	Docstr(DFunc("pushItemWidth")
	R"()"),

	"pushItemWidth", 1
};

word_t _pushItemWidth(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::PushItemWidth(cast(float)croc_ex_checkNumParam(t, 1));
	return 0;
}

const StdlibRegisterInfo _popItemWidth_info =
{
	Docstr(DFunc("popItemWidth")
	R"()"),

	"popItemWidth", 0
};

word_t _popItemWidth(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::PopItemWidth();
	return 0;
}

const StdlibRegisterInfo _getItemWidth_info =
{
	Docstr(DFunc("getItemWidth")
	R"()"),

	"getItemWidth", 0
};

word_t _getItemWidth(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	croc_pushFloat(t, ImGui::GetItemWidth());
	return 1;
}

const StdlibRegisterInfo _pushAllowKeyboardFocus_info =
{
	Docstr(DFunc("pushAllowKeyboardFocus")
	R"()"),

	"pushAllowKeyboardFocus", 1
};

word_t _pushAllowKeyboardFocus(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::PushAllowKeyboardFocus(croc_ex_checkBoolParam(t, 1));
	return 0;
}

const StdlibRegisterInfo _popAllowKeyboardFocus_info =
{
	Docstr(DFunc("popAllowKeyboardFocus")
	R"()"),

	"popAllowKeyboardFocus", 0
};

word_t _popAllowKeyboardFocus(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::PopAllowKeyboardFocus();
	return 0;
}

const StdlibRegisterInfo _pushStyleColor_info =
{
	Docstr(DFunc("pushStyleColor")
	R"()"),

	"pushStyleColor", 5
};

word_t _pushStyleColor(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto colIdx = croc_ex_checkIntParam(t, 1);
	auto r = croc_ex_checkNumParam(t, 2);
	auto g = croc_ex_checkNumParam(t, 3);
	auto b = croc_ex_checkNumParam(t, 4);
	auto a = croc_ex_optNumParam(t, 5, 1.0);

	if(colIdx < 0 || colIdx >= ImGuiCol_COUNT)
		croc_eh_throwStd(t, "RangeError", "Invalid color index");

	ImGui::PushStyleColor(colIdx, ImVec4(r, g, b, a));
	return 0;
}

const StdlibRegisterInfo _popStyleColor_info =
{
	Docstr(DFunc("popStyleColor")
	R"()"),

	"popStyleColor", 0
};

word_t _popStyleColor(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::PopStyleColor();
	return 0;
}

const StdlibRegisterInfo _setTooltip_info =
{
	Docstr(DFunc("setTooltip")
	R"()"),

	"setTooltip", 1
};

word_t _setTooltip(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::SetTooltip("%s", croc_ex_checkStringParam(t, 1));
	return 0;
}

const StdlibRegisterInfo _beginTooltip_info =
{
	Docstr(DFunc("beginTooltip")
	R"()"),

	"beginTooltip", 0
};

word_t _beginTooltip(CrocThread* t)
{
	checkVM(t);
	checkWindowBeginnable(t);
	checkInsideTooltip(t, false);
	setInsideTooltip(true);
	ImGui::BeginTooltip();
	return 0;
}

const StdlibRegisterInfo _endTooltip_info =
{
	Docstr(DFunc("endTooltip")
	R"()"),

	"endTooltip", 0
};

word_t _endTooltip(CrocThread* t)
{
	checkVM(t);
	checkWindowEndable(t);
	checkInsideTooltip(t, true);
	setInsideTooltip(false);
	ImGui::EndTooltip();
	return 0;
}

const StdlibRegisterInfo _separator_info =
{
	Docstr(DFunc("separator")
	R"()"),

	"separator", 0
};

word_t _separator(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::Separator();
	return 0;
}

const StdlibRegisterInfo _sameLine_info =
{
	Docstr(DFunc("sameLine")
	R"()"),

	"sameLine", 2
};

word_t _sameLine(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto colX = croc_ex_optIntParam(t, 1, 0);
	auto spacingW = croc_ex_optIntParam(t, 2, -1);
	ImGui::SameLine(colX, spacingW);
	return 0;
}

const StdlibRegisterInfo _spacing_info =
{
	Docstr(DFunc("spacing")
	R"()"),

	"spacing", 0
};

word_t _spacing(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::Spacing();
	return 0;
}

const StdlibRegisterInfo _columns_info =
{
	Docstr(DFunc("columns")
	R"()"),

	"columns", 3
};

word_t _columns(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto count = croc_ex_optIntParam(t, 1, 1);
	auto id = croc_ex_optStringParam(t, 2, nullptr);
	bool border = croc_ex_optBoolParam(t, 3, true);
	ImGui::Columns(count, id, border);
	return 0;
}

const StdlibRegisterInfo _nextColumn_info =
{
	Docstr(DFunc("nextColumn")
	R"()"),

	"nextColumn", 0
};

word_t _nextColumn(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::NextColumn();
	return 0;
}

const StdlibRegisterInfo _getColumnOffset_info =
{
	Docstr(DFunc("getColumnOffset")
	R"()"),

	"getColumnOffset", 1
};

word_t _getColumnOffset(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	croc_pushFloat(t, ImGui::GetColumnOffset(croc_ex_optIntParam(t, 1, -1)));
	return 1;
}

const StdlibRegisterInfo _setColumnOffset_info =
{
	Docstr(DFunc("setColumnOffset")
	R"()"),

	"setColumnOffset", 2
};

word_t _setColumnOffset(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto idx = croc_ex_checkIntParam(t, 1);
	auto offset = croc_ex_checkNumParam(t, 2);
	ImGui::SetColumnOffset(idx, offset);
	return 0;
}

const StdlibRegisterInfo _getColumnWidth_info =
{
	Docstr(DFunc("getColumnWidth")
	R"()"),

	"getColumnWidth", 1
};

word_t _getColumnWidth(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	croc_pushFloat(t, ImGui::GetColumnWidth(croc_ex_optIntParam(t, 1, -1)));
	return 1;
}

const StdlibRegisterInfo _getCursorPos_info =
{
	Docstr(DFunc("getCursorPos")
	R"()"),

	"getCursorPos", 0
};

word_t _getCursorPos(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto pos = ImGui::GetCursorPos();
	croc_pushFloat(t, pos.x);
	croc_pushFloat(t, pos.y);
	return 2;
}

const StdlibRegisterInfo _setCursorPos_info =
{
	Docstr(DFunc("setCursorPos")
	R"()"),

	"setCursorPos", 2
};

word_t _setCursorPos(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto x = croc_ex_checkNumParam(t, 1);
	auto y = croc_ex_checkNumParam(t, 2);
	ImGui::SetCursorPos(ImVec2(x, y));
	return 0;
}

const StdlibRegisterInfo _setCursorPosX_info =
{
	Docstr(DFunc("setCursorPosX")
	R"()"),

	"setCursorPosX", 1
};

word_t _setCursorPosX(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::SetCursorPosX(croc_ex_checkNumParam(t, 1));
	return 0;
}

const StdlibRegisterInfo _setCursorPosY_info =
{
	Docstr(DFunc("setCursorPosY")
	R"()"),

	"setCursorPosY", 1
};

word_t _setCursorPosY(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::SetCursorPosY(croc_ex_checkNumParam(t, 1));
	return 0;
}

const StdlibRegisterInfo _getCursorScreenPos_info =
{
	Docstr(DFunc("getCursorScreenPos")
	R"()"),

	"getCursorScreenPos", 0
};

word_t _getCursorScreenPos(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto pos = ImGui::GetCursorScreenPos();
	croc_pushFloat(t, pos.x);
	croc_pushFloat(t, pos.y);
	return 2;
}

const StdlibRegisterInfo _alignFirstTextHeightToWidgets_info =
{
	Docstr(DFunc("alignFirstTextHeightToWidgets")
	R"()"),

	"alignFirstTextHeightToWidgets", 0
};

word_t _alignFirstTextHeightToWidgets(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::AlignFirstTextHeightToWidgets();
	return 0;
}

const StdlibRegisterInfo _getTextLineSpacing_info =
{
	Docstr(DFunc("getTextLineSpacing")
	R"()"),

	"getTextLineSpacing", 0
};

word_t _getTextLineSpacing(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	croc_pushFloat(t, ImGui::GetTextLineSpacing());
	return 1;
}

const StdlibRegisterInfo _getTextLineHeight_info =
{
	Docstr(DFunc("getTextLineHeight")
	R"()"),

	"getTextLineHeight", 0
};

word_t _getTextLineHeight(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	croc_pushFloat(t, ImGui::GetTextLineHeight());
	return 1;
}

const StdlibRegisterInfo _pushID_info =
{
	Docstr(DFunc("pushID")
	R"()"),

	"pushID", 1
};

word_t _pushID(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	croc_ex_checkAnyParam(t, 1);

	if(croc_isInt(t, 1))
		ImGui::PushID(cast(int)croc_getInt(t, 1));
	else if(croc_isString(t, 1))
		ImGui::PushID(croc_getString(t, 1));
	else
		croc_ex_paramTypeError(t, 1, "int|string");

	return 0;
}

const StdlibRegisterInfo _popID_info =
{
	Docstr(DFunc("popID")
	R"()"),

	"popID", 0
};

word_t _popID(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::PopID();
	return 0;
}

const StdlibRegisterInfo _text_info =
{
	Docstr(DFunc("text")
	R"()"),

	"text", 1
};

word_t _text(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::Text("%s", croc_ex_checkStringParam(t, 1));
	return 0;
}

const StdlibRegisterInfo _textColored_info =
{
	Docstr(DFunc("textColored")
	R"()"),

	"textColored", 5
};

word_t _textColored(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto r = croc_ex_checkNumParam(t, 1);
	auto g = croc_ex_checkNumParam(t, 2);
	auto b = croc_ex_checkNumParam(t, 3);
	auto a = croc_ex_checkNumParam(t, 4);
	ImGui::TextColored(ImVec4(r, g, b, a), "%s", croc_ex_checkStringParam(t, 5));
	return 0;
}

const StdlibRegisterInfo _textUnformatted_info =
{
	Docstr(DFunc("textUnformatted")
	R"()"),

	"textUnformatted", 1
};

word_t _textUnformatted(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto str = checkCrocstrParam(t, 1);
	ImGui::TextUnformatted(cast(const char*)str.ptr, cast(const char*)str.ptr + str.length);
	return 0;
}

const StdlibRegisterInfo _labelText_info =
{
	Docstr(DFunc("labelText")
	R"()"),

	"labelText", 2
};

word_t _labelText(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	auto text = croc_ex_checkStringParam(t, 2);
	ImGui::LabelText(label, "%s", text);
	return 0;
}

const StdlibRegisterInfo _bulletText_info =
{
	Docstr(DFunc("bulletText")
	R"()"),

	"bulletText", 1
};

word_t _bulletText(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::BulletText("%s", croc_ex_checkStringParam(t, 1));
	return 0;
}

const StdlibRegisterInfo _button_info =
{
	Docstr(DFunc("button")
	R"()"),

	"button", 4
};

word_t _button(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	auto width = croc_ex_optIntParam(t, 2, 0);
	auto height = croc_ex_optIntParam(t, 3, 0);
	bool repeat = croc_ex_optBoolParam(t, 4, false);
	croc_pushBool(t, ImGui::Button(label, ImVec2(width, height), repeat));
	return 1;
}

const StdlibRegisterInfo _smallButton_info =
{
	Docstr(DFunc("smallButton")
	R"()"),

	"smallButton", 1
};

word_t _smallButton(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	croc_pushBool(t, ImGui::SmallButton(croc_ex_checkStringParam(t, 1)));
	return 1;
}

const StdlibRegisterInfo _collapsingHeader_info =
{
	Docstr(DFunc("collapsingHeader")
	R"()"),

	"collapsingHeader", 4
};

word_t _collapsingHeader(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	auto id = croc_ex_optStringParam(t, 2, nullptr);
	bool displayFrame = croc_ex_optBoolParam(t, 3, true);
	bool defaultOpen = croc_ex_optBoolParam(t, 4, false);
	croc_pushBool(t, ImGui::CollapsingHeader(label, id, displayFrame, defaultOpen));
	return 1;
}

const StdlibRegisterInfo _sliderFloat_info =
{
	Docstr(DFunc("sliderFloat")
	R"()"),

	"sliderFloat", 7
};

word_t _sliderFloat(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto min = cast(float)croc_ex_checkNumParam(t, 4);
	auto max = cast(float)croc_ex_checkNumParam(t, 5);
	auto fmt = croc_ex_optStringParam(t, 6, "%.3f");
	auto power = cast(float)croc_ex_optNumParam(t, 7, 1);
	auto val = getStateFloat(t, 2);
	croc_pushBool(t, ImGui::SliderFloat(label, &val, min, max, fmt, power));
	setStateFloat(t, 2, val);
	return 1;
}

const StdlibRegisterInfo _sliderFloat2_info =
{
	Docstr(DFunc("sliderFloat2")
	R"()"),

	"sliderFloat2", 7
};

word_t _sliderFloat2(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto min = cast(float)croc_ex_checkNumParam(t, 4);
	auto max = cast(float)croc_ex_checkNumParam(t, 5);
	auto fmt = croc_ex_optStringParam(t, 6, "%.3f");
	auto power = cast(float)croc_ex_optNumParam(t, 7, 1);
	float vals[2];
	getStateFloat2(t, 2, vals);
	croc_pushBool(t, ImGui::SliderFloat2(label, vals, min, max, fmt, power));
	setStateFloat2(t, 2, vals);
	return 1;
}

const StdlibRegisterInfo _sliderFloat3_info =
{
	Docstr(DFunc("sliderFloat3")
	R"()"),

	"sliderFloat3", 7
};

word_t _sliderFloat3(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto min = cast(float)croc_ex_checkNumParam(t, 4);
	auto max = cast(float)croc_ex_checkNumParam(t, 5);
	auto fmt = croc_ex_optStringParam(t, 6, "%.3f");
	auto power = cast(float)croc_ex_optNumParam(t, 7, 1);
	float vals[3];
	getStateFloat3(t, 2, vals);
	croc_pushBool(t, ImGui::SliderFloat3(label, vals, min, max, fmt, power));
	setStateFloat3(t, 2, vals);
	return 1;
}

const StdlibRegisterInfo _sliderFloat4_info =
{
	Docstr(DFunc("sliderFloat4")
	R"()"),

	"sliderFloat4", 7
};

word_t _sliderFloat4(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto min = cast(float)croc_ex_checkNumParam(t, 4);
	auto max = cast(float)croc_ex_checkNumParam(t, 5);
	auto fmt = croc_ex_optStringParam(t, 6, "%.3f");
	auto power = cast(float)croc_ex_optNumParam(t, 7, 1);
	float vals[4];
	getStateFloat4(t, 2, vals);
	croc_pushBool(t, ImGui::SliderFloat4(label, vals, min, max, fmt, power));
	setStateFloat4(t, 2, vals);
	return 1;
}

const StdlibRegisterInfo _sliderAngle_info =
{
	Docstr(DFunc("sliderAngle")
	R"()"),

	"sliderAngle", 5
};

word_t _sliderAngle(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto min = cast(float)croc_ex_optNumParam(t, 4, -360);
	auto max = cast(float)croc_ex_optNumParam(t, 5, 360);
	auto val = getStateFloat(t, 2);
	croc_pushBool(t, ImGui::SliderAngle(label, &val, min, max));
	setStateFloat(t, 2, val);
	return 1;
}

const StdlibRegisterInfo _sliderInt_info =
{
	Docstr(DFunc("sliderInt")
	R"()"),

	"sliderInt", 6
};

word_t _sliderInt(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto min = cast(float)croc_ex_checkNumParam(t, 4);
	auto max = cast(float)croc_ex_checkNumParam(t, 5);
	auto fmt = croc_ex_optStringParam(t, 6, "%.0f");
	auto val = getStateInt(t, 2);
	croc_pushBool(t, ImGui::SliderInt(label, &val, min, max, fmt));
	setStateInt(t, 2, val);
	return 1;
}

const StdlibRegisterInfo _plotLines_info =
{
	Docstr(DFunc("plotLines")
	R"()"),

	"plotLines", 9
};

struct PlotFuncData
{
	CrocThread* t;
	bool failed;
	bool first;
	bool rethrow;

	PlotFuncData(CrocThread* t_) :
		t(t_),
		failed(false),
		first(true),
		rethrow(false)
	{}
};

float plotFuncCallback(void* data_, int idx)
{
	auto data = cast(PlotFuncData*)data_;

	if(!data->failed)
	{
		auto t = data->t;

		if(data->first)
			data->first = false;
		else
			croc_popTop(t); // get rid of the value from last iter

		croc_dup(t, 2);
		croc_pushNull(t);
		croc_pushInt(t, idx);
		auto result = croc_tryCall(t, -3, 1);

		if(result == CrocCallRet_Error)
		{
			data->failed = true;
			data->rethrow = true;
		}
		else if(croc_isNum(t, -1))
			return croc_getNum(t, -1);
		else
		{
			croc_pushTypeString(t, -1);
			croc_eh_pushStd(t, "TypeError");
			croc_pushNull(t);
			croc_pushFormat(t, "Callback expected to return a number, not '%s'", croc_getString(t, -3));
			croc_call(t, -3, 1);
			data->failed = true;
		}
	}

	return 0;
}

word_t _plotLines(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	// callable in slot 2
	auto numValues = croc_ex_checkIntParam(t, 3);
	auto valOffset = croc_ex_optIntParam(t, 4, 0);
	auto overlayText = croc_ex_optStringParam(t, 5, nullptr);
	auto scaleMin = croc_ex_optNumParam(t, 6, FLT_MAX);
	auto scaleMax = croc_ex_optNumParam(t, 7, FLT_MAX);
	auto graphWidth = croc_ex_optIntParam(t, 8, 0);
	auto graphHeight = croc_ex_optIntParam(t, 9, 0);

	if(numValues <= 0)
		croc_eh_throwStd(t, "RangeError", "Invalid number of items");

	PlotFuncData data(t);
	ImGui::PlotLines(label, &plotFuncCallback, cast(void*)&data, numValues, valOffset, overlayText, scaleMin, scaleMax,
		ImVec2(graphWidth, graphHeight));

	if(data.failed)
	{
		if(data.rethrow)
			croc_eh_rethrow(t);
		else
			croc_eh_throw(t);
	}

	return 0;
}

const StdlibRegisterInfo _plotHistogram_info =
{
	Docstr(DFunc("plotHistogram")
	R"()"),

	"plotHistogram", 9
};

word_t _plotHistogram(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	// callable in slot 2
	auto numValues = croc_ex_checkIntParam(t, 3);
	auto valOffset = croc_ex_optIntParam(t, 4, 0);
	auto overlayText = croc_ex_optStringParam(t, 5, nullptr);
	auto scaleMin = croc_ex_optNumParam(t, 6, FLT_MAX);
	auto scaleMax = croc_ex_optNumParam(t, 7, FLT_MAX);
	auto graphWidth = croc_ex_optIntParam(t, 8, 0);
	auto graphHeight = croc_ex_optIntParam(t, 9, 0);

	if(numValues < 0)
		croc_eh_throwStd(t, "RangeError", "Invalid number of items");

	PlotFuncData data(t);
	ImGui::PlotHistogram(label, &plotFuncCallback, cast(void*)&data, numValues, valOffset, overlayText, scaleMin,
		scaleMax, ImVec2(graphWidth, graphHeight));

	if(data.failed)
	{
		if(data.rethrow)
			croc_eh_rethrow(t);
		else
			croc_eh_throw(t);
	}

	return 0;
}

const StdlibRegisterInfo _checkbox_info =
{
	Docstr(DFunc("checkbox")
	R"()"),

	"checkbox", 3
};

word_t _checkbox(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto val = getStateBool(t, 2);
	croc_pushBool(t, ImGui::Checkbox(label, &val));
	setStateBool(t, 2, val);
	return 1;
}

const StdlibRegisterInfo _checkboxFlags_info =
{
	Docstr(DFunc("checkboxFlags")
	R"()"),

	"checkboxFlags", 4
};

word_t _checkboxFlags(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto flag = croc_ex_checkIntParam(t, 4);
	auto val = cast(unsigned int)getStateInt(t, 2);
	croc_pushBool(t, ImGui::CheckboxFlags(label, &val, flag));
	setStateInt(t, 2, val);
	return 1;
}

const StdlibRegisterInfo _radioButton_info =
{
	Docstr(DFunc("radioButton")
	R"()"),

	"radioButton", 2
};

word_t _radioButton(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	auto active = croc_ex_checkBoolParam(t, 2);
	croc_pushBool(t, ImGui::RadioButton(label, active));
	return 1;
}

const StdlibRegisterInfo _radioButtonMulti_info =
{
	Docstr(DFunc("radioButtonMulti")
	R"()"),

	"radioButtonMulti", 4
};

word_t _radioButtonMulti(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto buttonIdx = croc_ex_checkIntParam(t, 4);
	auto val = getStateInt(t, 2);
	croc_pushBool(t, ImGui::RadioButton(label, &val, buttonIdx));
	setStateInt(t, 2, val);
	return 1;
}

const StdlibRegisterInfo _inputText_info =
{
	Docstr(DFunc("inputText")
	R"()"),

	"inputText", 3
};

word_t _inputText(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 2, CrocType_Memblock);
	auto flags = croc_ex_optIntParam(t, 3, 0);
	auto buf = croc_memblock_getData(t, 2);
	croc_pushBool(t, ImGui::InputText(label, buf, croc_len(t, 2), flags));
	return 1;
}

const StdlibRegisterInfo _inputFloat_info =
{
	Docstr(DFunc("inputFloat")
	R"()"),

	"inputFloat", 7
};

word_t _inputFloat(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto step = cast(float)croc_ex_optNumParam(t, 4, 0);
	auto stepFast = cast(float)croc_ex_optNumParam(t, 5, 0);
	auto precision = croc_ex_optIntParam(t, 6, -1);
	auto flags = croc_ex_optIntParam(t, 7, 0);
	auto val = getStateFloat(t, 2);
	croc_pushBool(t, ImGui::InputFloat(label, &val, step, stepFast, precision, flags));
	setStateFloat(t, 2, val);
	return 1;
}

const StdlibRegisterInfo _inputFloat2_info =
{
	Docstr(DFunc("inputFloat2")
	R"()"),

	"inputFloat2", 4
};

word_t _inputFloat2(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto precision = croc_ex_optIntParam(t, 4, -1);
	float vals[2];
	getStateFloat2(t, 2, vals);
	croc_pushBool(t, ImGui::InputFloat2(label, vals, precision));
	setStateFloat2(t, 2, vals);
	return 1;
}

const StdlibRegisterInfo _inputFloat3_info =
{
	Docstr(DFunc("inputFloat3")
	R"()"),

	"inputFloat3", 4
};

word_t _inputFloat3(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto precision = croc_ex_optIntParam(t, 4, -1);
	float vals[3];
	getStateFloat3(t, 2, vals);
	croc_pushBool(t, ImGui::InputFloat3(label, vals, precision));
	setStateFloat3(t, 2, vals);
	return 1;
}

const StdlibRegisterInfo _inputFloat4_info =
{
	Docstr(DFunc("inputFloat4")
	R"()"),

	"inputFloat4", 4
};

word_t _inputFloat4(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto precision = croc_ex_optIntParam(t, 4, -1);
	float vals[4];
	getStateFloat4(t, 2, vals);
	croc_pushBool(t, ImGui::InputFloat4(label, vals, precision));
	setStateFloat4(t, 2, vals);
	return 1;
}

const StdlibRegisterInfo _inputInt_info =
{
	Docstr(DFunc("inputInt")
	R"()"),

	"inputInt", 6
};

word_t _inputInt(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto step = cast(int)croc_ex_optIntParam(t, 4, 1);
	auto stepFast = cast(int)croc_ex_optIntParam(t, 5, 100);
	auto flags = croc_ex_optIntParam(t, 6, 0);
	auto val = getStateInt(t, 2);
	croc_pushBool(t, ImGui::InputInt(label, &val, step, stepFast, flags));
	setStateInt(t, 2, val);
	return 1;
}

const StdlibRegisterInfo _comboStr_info =
{
	Docstr(DFunc("comboStr")
	R"()"),

	"comboStr", 5
};

word_t _comboStr(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	auto items = checkCrocstrParam(t, 4);
	auto popupHeight = croc_ex_optIntParam(t, 5, 7);

	if(items.length < 2 || items.ptr[items.length - 1] != 0 || items.ptr[items.length - 2] != 0)
		croc_eh_throwStd(t, "ValueError", "Items string must end with two '\\0' characters");

	auto val = getStateInt(t, 2);
	croc_pushBool(t, ImGui::Combo(label, &val, cast(const char*)items.ptr, popupHeight));
	setStateInt(t, 2, val);
	return 1;
}

const StdlibRegisterInfo _comboFunc_info =
{
	Docstr(DFunc("comboFunc")
	R"()"),

	"comboFunc", 6
};

struct ComboFuncData
{
	CrocThread* t;
	bool failed;
	bool first;
	bool rethrow;

	ComboFuncData(CrocThread* t_) :
		t(t_),
		failed(false),
		first(true),
		rethrow(false)
	{}
};

bool comboFuncCallback(void* data_, int idx, const char** outText)
{
	auto data = cast(ComboFuncData*)data_;

	if(!data->failed)
	{
		auto t = data->t;

		if(data->first)
			data->first = false;
		else
			croc_popTop(t); // get rid of the string from last iter

		croc_dup(t, 4);
		croc_pushNull(t);
		croc_pushInt(t, idx);
		auto result = croc_tryCall(t, -3, 1);

		if(result == CrocCallRet_Error)
		{
			data->failed = true;
			data->rethrow = true;
		}
		else if(croc_isNull(t, -1))
			return false;
		else if(croc_isString(t, -1))
			*outText = croc_getString(t, -1);
		else
		{
			croc_pushTypeString(t, -1);
			croc_eh_pushStd(t, "TypeError");
			croc_pushNull(t);
			croc_pushFormat(t, "Callback expected to return a string, not '%s'", croc_getString(t, -3));
			croc_call(t, -3, 1);
			data->failed = true;
		}
	}

	return !data->failed;
}

word_t _comboFunc(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	// callable in slot 4
	auto numItems = croc_ex_checkIntParam(t, 5);
	auto popupHeight = croc_ex_optIntParam(t, 6, 7);

	if(numItems < 0)
		croc_eh_throwStd(t, "RangeError", "Invalid number of items");

	ComboFuncData data(t);
	auto val = getStateInt(t, 2);
	auto ret = ImGui::Combo(label, &val, &comboFuncCallback, cast(void*)&data, numItems, popupHeight);

	if(data.failed)
	{
		if(data.rethrow)
			croc_eh_rethrow(t);
		else
			croc_eh_throw(t);

		return 0; // dummy
	}
	else
	{
		croc_pushBool(t, ret);
		setStateInt(t, 2, val);
		return 1;
	}
}

const StdlibRegisterInfo _colorButton_info =
{
	Docstr(DFunc("colorButton")
	R"()"),

	"colorButton", 6
};

word_t _colorButton(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto r = croc_ex_checkNumParam(t, 1);
	auto g = croc_ex_checkNumParam(t, 2);
	auto b = croc_ex_checkNumParam(t, 3);
	auto a = croc_ex_checkNumParam(t, 4);
	auto smallHeight = croc_ex_optBoolParam(t, 5, false);
	auto outlineBorder = croc_ex_optBoolParam(t, 6, true);
	croc_pushBool(t, ImGui::ColorButton(ImVec4(r, g, b, a), smallHeight, outlineBorder));
	return 1;
}

const StdlibRegisterInfo _colorEdit3_info =
{
	Docstr(DFunc("colorEdit3")
	R"()"),

	"colorEdit3", 3
};

word_t _colorEdit3(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	float color[3];
	getStateFloat3(t, 2, color);
	croc_pushBool(t, ImGui::ColorEdit3(label, color));
	setStateFloat3(t, 2, color);
	return 1;
}

const StdlibRegisterInfo _colorEdit4_info =
{
	Docstr(DFunc("colorEdit4")
	R"()"),

	"colorEdit4", 4
};

word_t _colorEdit4(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	croc_ex_checkParam(t, 3, CrocType_String);
	bool showAlpha = croc_ex_optBoolParam(t, 4, true);
	float color[4];
	getStateFloat4(t, 2, color);
	croc_pushBool(t, ImGui::ColorEdit4(label, color, showAlpha));
	setStateFloat4(t, 2, color);
	return 1;
}

const StdlibRegisterInfo _colorEditMode_info =
{
	Docstr(DFunc("colorEditMode")
	R"()"),

	"colorEditMode", 1
};

word_t _colorEditMode(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto mode = croc_ex_checkIntParam(t, 1);

	if(mode < 0 || mode > 2)
		croc_eh_throwStd(t, "RangeError", "Invalid color edit mode");

	ImGui::ColorEditMode(mode);
	return 0;
}

const StdlibRegisterInfo _treeNode_info =
{
	Docstr(DFunc("treeNode")
	R"()"),

	"treeNode", 1
};

word_t _treeNode(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	croc_pushBool(t, ImGui::TreeNode(croc_ex_checkStringParam(t, 1)));
	return 1;
}

const StdlibRegisterInfo _treeNodeID_info =
{
	Docstr(DFunc("treeNodeID")
	R"()"),

	"treeNodeID", 2
};

word_t _treeNodeID(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 2);

	if(croc_isInt(t, 1))
		croc_pushBool(t, ImGui::TreeNode(cast(void*)croc_getInt(t, 1), label));
	else if(croc_isString(t, 1))
		croc_pushBool(t, ImGui::TreeNode(croc_getString(t, 1), label));
	else
		croc_ex_paramTypeError(t, 1, "int|string");

	return 1;
}

const StdlibRegisterInfo _treePush_info =
{
	Docstr(DFunc("treePush")
	R"()"),

	"treePush", 1
};

word_t _treePush(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);

	if(!croc_isValidIndex(t, 1))
		ImGui::TreePush(cast(void*)nullptr);
	else if(croc_isInt(t, 1))
		ImGui::TreePush(cast(void*)croc_getInt(t, 1));
	else if(croc_isString(t, 1))
		ImGui::TreePush(croc_getString(t, 1));
	else
		croc_ex_paramTypeError(t, 1, "int|string");

	return 0;
}

const StdlibRegisterInfo _treePop_info =
{
	Docstr(DFunc("treePop")
	R"()"),

	"treePop", 0
};

word_t _treePop(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::TreePop();
	return 0;
}

const StdlibRegisterInfo _openNextNode_info =
{
	Docstr(DFunc("openNextNode")
	R"()"),

	"openNextNode", 1
};

word_t _openNextNode(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::OpenNextNode(croc_ex_checkBoolParam(t, 1));
	return 0;
}

const StdlibRegisterInfo _value_info =
{
	Docstr(DFunc("value")
	R"()"),

	"value", 3
};

word_t _value(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);

	croc_ex_checkAnyParam(t, 2);

	switch(croc_type(t, 2))
	{
		case CrocType_Bool: {
			ImGui::Value(label, croc_getBool(t, 2));
			break;
		}
		case CrocType_Int: {
			auto isUnsigned = croc_ex_optBoolParam(t, 3, false);

			if(isUnsigned)
				ImGui::Value(label, cast(unsigned int)croc_getInt(t, 2));
			else
				ImGui::Value(label, cast(int)croc_getInt(t, 2));

			break;
		}
		case CrocType_Float: {
			auto format = croc_ex_optStringParam(t, 3, nullptr);
			ImGui::Value(label, cast(float)croc_getFloat(t, 2), format);
			break;
		}
		default:
			croc_ex_paramTypeError(t, 2, "bool|int|float");
	}

	return 0;
}

const StdlibRegisterInfo _color_info =
{
	Docstr(DFunc("color")
	R"()"),

	"color", 5
};

word_t _color(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	auto r = croc_ex_checkNumParam(t, 2);
	auto g = croc_ex_checkNumParam(t, 3);
	auto b = croc_ex_checkNumParam(t, 4);
	auto a = croc_ex_checkNumParam(t, 5);
	ImGui::Color(label, ImVec4(r, g, b, a));
	return 0;
}

const StdlibRegisterInfo _color32_info =
{
	Docstr(DFunc("color32")
	R"()"),

	"color32", 2
};

word_t _color32(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto label = croc_ex_checkStringParam(t, 1);
	auto color = croc_ex_checkIntParam(t, 2);

	if(color < 0 || color > 0xFFFFFFFF)
		croc_eh_throwStd(t, "RangeError", "Invalid color value");

	ImGui::Color(label, cast(unsigned int)color);
	return 0;
}

const StdlibRegisterInfo _logButtons_info =
{
	Docstr(DFunc("logButtons")
	R"()"),

	"logButtons", 0
};

word_t _logButtons(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	ImGui::LogButtons();
	return 0;
}

const StdlibRegisterInfo _logToTTY_info =
{
	Docstr(DFunc("logToTTY")
	R"()"),

	"logToTTY", 1
};

word_t _logToTTY(CrocThread* t)
{
	// TODO: this logs to C stdout regardless of Croc's stdout. Don't think ImGui provides a way to fix this right now..
	checkVM(t);
	ImGui::LogToTTY(cast(int)croc_ex_optIntParam(t, 1, -1));
	return 0;
}

const StdlibRegisterInfo _logToFile_info =
{
	Docstr(DFunc("logToFile")
	R"()"),

	"logToFile", 2
};

word_t _logToFile(CrocThread* t)
{
	checkVM(t);
	auto depth = cast(int)croc_ex_optIntParam(t, 1, -1);
	auto filename = croc_ex_optStringParam(t, 2, nullptr);
	ImGui::LogToFile(depth, filename);
	return 0;
}

const StdlibRegisterInfo _logToClipboard_info =
{
	Docstr(DFunc("logToClipboard")
	R"()"),

	"logToClipboard", 1
};

word_t _logToClipboard(CrocThread* t)
{
	checkVM(t);
	ImGui::LogToClipboard(cast(int)croc_ex_optIntParam(t, 1, -1));
	return 0;
}

const StdlibRegisterInfo _setNewWindowDefaultPos_info =
{
	Docstr(DFunc("setNewWindowDefaultPos")
	R"()"),

	"setNewWindowDefaultPos", 2
};

word_t _setNewWindowDefaultPos(CrocThread* t)
{
	checkVM(t);
	auto x = croc_ex_checkNumParam(t, 1);
	auto y = croc_ex_checkNumParam(t, 2);
	ImVec2 pos(x, y);
	ImGui::SetNewWindowDefaultPos(pos);
	return 0;
}

const StdlibRegisterInfo _isHovered_info =
{
	Docstr(DFunc("isHovered")
	R"()"),

	"isHovered", 0
};

word_t _isHovered(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	croc_pushBool(t, ImGui::IsHovered());
	return 1;
}

const StdlibRegisterInfo _getItemBox_info =
{
	Docstr(DFunc("getItemBox")
	R"()"),

	"getItemBox", 0
};

word_t _getItemBox(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto min = ImGui::GetItemBoxMin();
	auto max = ImGui::GetItemBoxMax();
	croc_pushInt(t, cast(crocint)min.x);
	croc_pushInt(t, cast(crocint)min.y);
	croc_pushInt(t, cast(crocint)max.x);
	croc_pushInt(t, cast(crocint)max.y);
	return 4;
}

const StdlibRegisterInfo _isClipped_info =
{
	Docstr(DFunc("isClipped")
	R"()"),

	"isClipped", 2
};

word_t _isClipped(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto w = croc_ex_checkNumParam(t, 1);
	auto h = croc_ex_checkNumParam(t, 2);
	croc_pushBool(t, ImGui::IsClipped(ImVec2(w, h)));
	return 1;
}

const StdlibRegisterInfo _isKeyPressed_info =
{
	Docstr(DFunc("isKeyPressed")
	R"()"),

	"isKeyPressed", 2
};

word_t _isKeyPressed(CrocThread* t)
{
	checkVM(t);
	auto key = croc_ex_checkIntParam(t, 1);
	auto repeat = croc_ex_optBoolParam(t, 2, true);

	if(key < 0 || key >= 512)
		croc_eh_throwStd(t, "RangeError", "Invalid key");

	croc_pushBool(t, ImGui::IsKeyPressed(key, repeat));
	return 1;
}

const StdlibRegisterInfo _isMouseClicked_info =
{
	Docstr(DFunc("isMouseClicked")
	R"()"),

	"isMouseClicked", 2
};

word_t _isMouseClicked(CrocThread* t)
{
	checkVM(t);
	auto button = croc_ex_checkIntParam(t, 1);
	auto repeat = croc_ex_optBoolParam(t, 2, true);

	if(button < 0 || button >= 5)
		croc_eh_throwStd(t, "RangeError", "Invalid button");

	croc_pushBool(t, ImGui::IsMouseClicked(button, repeat));
	return 1;
}

const StdlibRegisterInfo _isMouseDoubleClicked_info =
{
	Docstr(DFunc("isMouseDoubleClicked")
	R"()"),

	"isMouseDoubleClicked", 1
};

word_t _isMouseDoubleClicked(CrocThread* t)
{
	checkVM(t);
	auto button = croc_ex_checkIntParam(t, 1);

	if(button < 0 || button >= 5)
		croc_eh_throwStd(t, "RangeError", "Invalid button");

	croc_pushBool(t, ImGui::IsMouseDoubleClicked(button));
	return 1;
}

const StdlibRegisterInfo _isMouseHoveringWindow_info =
{
	Docstr(DFunc("isMouseHoveringWindow")
	R"()"),

	"isMouseHoveringWindow", 0
};

word_t _isMouseHoveringWindow(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	croc_pushBool(t, ImGui::IsMouseHoveringWindow());
	return 1;
}

const StdlibRegisterInfo _isMouseHoveringAnyWindow_info =
{
	Docstr(DFunc("isMouseHoveringAnyWindow")
	R"()"),

	"isMouseHoveringAnyWindow", 0
};

word_t _isMouseHoveringAnyWindow(CrocThread* t)
{
	checkVM(t);
	croc_pushBool(t, ImGui::IsMouseHoveringAnyWindow());
	return 1;
}

const StdlibRegisterInfo _isMouseHoveringBox_info =
{
	Docstr(DFunc("isMouseHoveringBox")
	R"()"),

	"isMouseHoveringBox", 4
};

word_t _isMouseHoveringBox(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto minx = croc_ex_checkNumParam(t, 1);
	auto miny = croc_ex_checkNumParam(t, 2);
	auto maxx = croc_ex_checkNumParam(t, 3);
	auto maxy = croc_ex_checkNumParam(t, 4);
	croc_pushBool(t, ImGui::IsMouseHoveringBox(ImVec2(minx, miny), ImVec2(maxx, maxy)));
	return 1;
}

const StdlibRegisterInfo _isPosHoveringAnyWindow_info =
{
	Docstr(DFunc("isPosHoveringAnyWindow")
	R"()"),

	"isPosHoveringAnyWindow", 2
};

word_t _isPosHoveringAnyWindow(CrocThread* t)
{
	checkVM(t);
	auto x = croc_ex_checkNumParam(t, 1);
	auto y = croc_ex_checkNumParam(t, 2);
	croc_pushBool(t, ImGui::IsPosHoveringAnyWindow(ImVec2(x, y)));
	return 1;
}

const StdlibRegisterInfo _getMousePos_info =
{
	Docstr(DFunc("getMousePos")
	R"()"),

	"getMousePos", 0
};

word_t _getMousePos(CrocThread* t)
{
	checkVM(t);
	auto pos = ImGui::GetMousePos();
	croc_pushInt(t, cast(crocint)pos.x);
	croc_pushInt(t, cast(crocint)pos.y);
	return 2;
}

const StdlibRegisterInfo _getTime_info =
{
	Docstr(DFunc("getTime")
	R"()"),

	"getTime", 0
};

word_t _getTime(CrocThread* t)
{
	checkVM(t);
	croc_pushFloat(t, ImGui::GetTime());
	return 1;
}

const StdlibRegisterInfo _getFrameCount_info =
{
	Docstr(DFunc("getFrameCount")
	R"()"),

	"getFrameCount", 0
};

word_t _getFrameCount(CrocThread* t)
{
	checkVM(t);
	croc_pushInt(t, ImGui::GetFrameCount());
	return 1;
}

const StdlibRegisterInfo _getStyleColorName_info =
{
	Docstr(DFunc("getStyleColorName")
	R"()"),

	"getStyleColorName", 1
};

word_t _getStyleColorName(CrocThread* t)
{
	checkVM(t);
	auto colIdx = croc_ex_checkIntParam(t, 1);

	if(colIdx < 0 || colIdx >= ImGuiCol_COUNT)
		croc_eh_throwStd(t, "RangeError", "Invalid color index");

	croc_pushString(t, ImGui::GetStyleColorName(colIdx));
	return 1;
}

const StdlibRegisterInfo _getDefaultFontInfo_info =
{
	Docstr(DFunc("getDefaultFontInfo")
	R"()"),

	"getDefaultFontInfo", 0
};

word_t _getDefaultFontInfo(CrocThread* t)
{
	checkVM(t);
	const void* ptr;
	unsigned int size;
	ImGui::GetDefaultFontData(&ptr, &size, nullptr, nullptr);
	croc_memblock_fromNativeArray(t, ptr, size);
	return 1;
}

const StdlibRegisterInfo _getDefaultFontData_info =
{
	Docstr(DFunc("getDefaultFontData")
	R"()"),

	"getDefaultFontData", 0
};

word_t _getDefaultFontData(CrocThread* t)
{
	checkVM(t);
	const void* ptr;
	unsigned int size;
	ImGui::GetDefaultFontData(nullptr, nullptr, &ptr, &size);
	croc_memblock_fromNativeArray(t, ptr, size);
	return 1;
}

const StdlibRegisterInfo _calcTextSize_info =
{
	Docstr(DFunc("calcTextSize")
	R"()"),

	"calcTextSize", 2
};

word_t _calcTextSize(CrocThread* t)
{
	checkVM(t);
	checkHaveWindow(t);
	auto text = checkCrocstrParam(t, 1);
	auto hideAfterHash = croc_ex_optBoolParam(t, 2, true);
	auto size = ImGui::CalcTextSize(cast(const char*)text.ptr, cast(const char*)text.ptr + text.length, hideAfterHash);
	croc_pushInt(t, cast(crocint)size.x);
	croc_pushInt(t, cast(crocint)size.y);
	return 2;
}

const StdlibRegister _globalFuncs[] =
{
	_DListItem(_init),
	_DListItem(_shutdown),
	_DListItem(_getStyle),
	_DListItem(_setStyle),
	_DListItem(_newFrame),
	_DListItem(_render),
	_DListItem(_showUserGuide),
	_DListItem(_showStyleEditor),
	_DListItem(_showTestWindow),
	_DListItem(_showTestWindowClosable),
	_DListItem(_begin),
	_DListItem(_beginClosable),
	_DListItem(_end),
	_DListItem(_beginChild),
	_DListItem(_endChild),
	_DListItem(_getWindowIsFocused),
	_DListItem(_getWindowSize),
	_DListItem(_getWindowWidth),
	_DListItem(_setWindowSize),
	_DListItem(_getWindowPos),
	_DListItem(_setWindowPos),
	_DListItem(_getWindowContentRegion),
	_DListItem(_getWindowFontSize),
	_DListItem(_setWindowFontScale),
	_DListItem(_setScrollPosHere),
	_DListItem(_setKeyboardFocusHere),
	_DListItem(_pushItemWidth),
	_DListItem(_popItemWidth),
	_DListItem(_getItemWidth),
	_DListItem(_pushAllowKeyboardFocus),
	_DListItem(_popAllowKeyboardFocus),
	_DListItem(_pushStyleColor),
	_DListItem(_popStyleColor),
	_DListItem(_setTooltip),
	_DListItem(_beginTooltip),
	_DListItem(_endTooltip),
	_DListItem(_separator),
	_DListItem(_sameLine),
	_DListItem(_spacing),
	_DListItem(_columns),
	_DListItem(_nextColumn),
	_DListItem(_getColumnOffset),
	_DListItem(_setColumnOffset),
	_DListItem(_getColumnWidth),
	_DListItem(_getCursorPos),
	_DListItem(_setCursorPos),
	_DListItem(_setCursorPosX),
	_DListItem(_setCursorPosY),
	_DListItem(_getCursorScreenPos),
	_DListItem(_alignFirstTextHeightToWidgets),
	_DListItem(_getTextLineSpacing),
	_DListItem(_getTextLineHeight),
	_DListItem(_pushID),
	_DListItem(_popID),
	_DListItem(_text),
	_DListItem(_textColored),
	_DListItem(_textUnformatted),
	_DListItem(_labelText),
	_DListItem(_bulletText),
	_DListItem(_button),
	_DListItem(_smallButton),
	_DListItem(_collapsingHeader),
	_DListItem(_sliderFloat),
	_DListItem(_sliderFloat2),
	_DListItem(_sliderFloat3),
	_DListItem(_sliderFloat4),
	_DListItem(_sliderAngle),
	_DListItem(_sliderInt),
	_DListItem(_plotLines),
	_DListItem(_plotHistogram),
	_DListItem(_checkbox),
	_DListItem(_checkboxFlags),
	_DListItem(_radioButton),
	_DListItem(_radioButtonMulti),
	_DListItem(_inputText),
	_DListItem(_inputFloat),
	_DListItem(_inputFloat2),
	_DListItem(_inputFloat3),
	_DListItem(_inputFloat4),
	_DListItem(_inputInt),
	_DListItem(_comboStr),
	_DListItem(_comboFunc),
	_DListItem(_colorButton),
	_DListItem(_colorEdit3),
	_DListItem(_colorEdit4),
	_DListItem(_colorEditMode),
	_DListItem(_treeNode),
	_DListItem(_treeNodeID),
	_DListItem(_treePush),
	_DListItem(_treePop),
	_DListItem(_openNextNode),
	_DListItem(_value),
	_DListItem(_color),
	_DListItem(_color32),
	_DListItem(_logButtons),
	_DListItem(_logToTTY),
	_DListItem(_logToFile),
	_DListItem(_logToClipboard),
	_DListItem(_setNewWindowDefaultPos),
	_DListItem(_isHovered),
	_DListItem(_getItemBox),
	_DListItem(_isClipped),
	_DListItem(_isKeyPressed),
	_DListItem(_isMouseClicked),
	_DListItem(_isMouseDoubleClicked),
	_DListItem(_isMouseHoveringWindow),
	_DListItem(_isMouseHoveringAnyWindow),
	_DListItem(_isMouseHoveringBox),
	_DListItem(_isPosHoveringAnyWindow),
	_DListItem(_getMousePos),
	_DListItem(_getTime),
	_DListItem(_getFrameCount),
	_DListItem(_getStyleColorName),
	_DListItem(_getDefaultFontInfo),
	_DListItem(_getDefaultFontData),
	_DListItem(_calcTextSize),
	_DListEnd
};

// =====================================================================================================================
// io namespace

#ifdef CROC_BUILTIN_DOCS
const char* ioDocs = DNs("io")
R"()";
#endif

const StdlibRegisterInfo _io_setDisplaySize_info =
{
	Docstr(DFunc("setDisplaySize")
	R"()"),

	"setDisplaySize", 2
};

word_t _io_setDisplaySize(CrocThread* t)
{
	checkVM(t);
	auto w = croc_ex_checkNumParam(t, 1);
	auto h = croc_ex_checkNumParam(t, 2);

	if(w <= 0 || h <= 0)
		croc_eh_throwStd(t, "RangeError", "Invalid display size %fx%f", w, h);

	ImGui::GetIO().DisplaySize = ImVec2(cast(float)w, cast(float)h);
	return 0;
}

const StdlibRegisterInfo _io_getDisplaySize_info =
{
	Docstr(DFunc("getDisplaySize")
	R"()"),

	"getDisplaySize", 0
};

word_t _io_getDisplaySize(CrocThread* t)
{
	checkVM(t);
	auto size = ImGui::GetIO().DisplaySize;
	croc_pushFloat(t, size.x);
	croc_pushFloat(t, size.y);
	return 2;
}

const StdlibRegisterInfo _io_setDeltaTime_info =
{
	Docstr(DFunc("setDeltaTime")
	R"()"),

	"setDeltaTime", 1
};

word_t _io_setDeltaTime(CrocThread* t)
{
	checkVM(t);
	auto time = croc_ex_checkNumParam(t, 1);

	if(time <= 0)
		croc_eh_throwStd(t, "RangeError", "Invalid delta time");

	ImGui::GetIO().DeltaTime = time;
	return 0;
}

const StdlibRegisterInfo _io_getDeltaTime_info =
{
	Docstr(DFunc("getDeltaTime")
	R"()"),

	"getDeltaTime", 0
};

word_t _io_getDeltaTime(CrocThread* t)
{
	checkVM(t);
	croc_pushFloat(t, ImGui::GetIO().DeltaTime);
	return 1;
}

const StdlibRegisterInfo _io_setIniSavingRate_info =
{
	Docstr(DFunc("setIniSavingRate")
	R"()"),

	"setIniSavingRate", 1
};

word_t _io_setIniSavingRate(CrocThread* t)
{
	checkVM(t);
	ImGui::GetIO().IniSavingRate = croc_ex_checkNumParam(t, 1);
	return 0;
}

const StdlibRegisterInfo _io_getIniSavingRate_info =
{
	Docstr(DFunc("getIniSavingRate")
	R"()"),

	"getIniSavingRate", 0
};

word_t _io_getIniSavingRate(CrocThread* t)
{
	checkVM(t);
	croc_pushFloat(t, ImGui::GetIO().IniSavingRate);
	return 1;
}

const StdlibRegisterInfo _io_setIniFilename_info =
{
	Docstr(DFunc("setIniFilename")
	R"()"),

	"setIniFilename", 1
};

word_t _io_setIniFilename(CrocThread* t)
{
	checkVM(t);
	ImGui::GetIO().IniFilename = croc_ex_checkStringParam(t, 1);
	// have to do this to keep the name from getting collected
	croc_dup(t, 1);
	croc_ex_setRegistryVar(t, IniFilename);
	return 0;
}

const StdlibRegisterInfo _io_getIniFilename_info =
{
	Docstr(DFunc("getIniFilename")
	R"()"),

	"getIniFilename", 0
};

word_t _io_getIniFilename(CrocThread* t)
{
	checkVM(t);
	croc_pushString(t, ImGui::GetIO().IniFilename);
	return 1;
}

const StdlibRegisterInfo _io_setLogFilename_info =
{
	Docstr(DFunc("setLogFilename")
	R"()"),

	"setLogFilename", 1
};

word_t _io_setLogFilename(CrocThread* t)
{
	checkVM(t);
	ImGui::GetIO().LogFilename = croc_ex_checkStringParam(t, 1);
	// have to do this to keep the name from getting collected
	croc_dup(t, 1);
	croc_ex_setRegistryVar(t, LogFilename);
	return 0;
}

const StdlibRegisterInfo _io_getLogFilename_info =
{
	Docstr(DFunc("getLogFilename")
	R"()"),

	"getLogFilename", 0
};

word_t _io_getLogFilename(CrocThread* t)
{
	checkVM(t);
	croc_pushString(t, ImGui::GetIO().LogFilename);
	return 1;
}

const StdlibRegisterInfo _io_setMouseDoubleClickTime_info =
{
	Docstr(DFunc("setMouseDoubleClickTime")
	R"()"),

	"setMouseDoubleClickTime", 1
};

word_t _io_setMouseDoubleClickTime(CrocThread* t)
{
	checkVM(t);
	ImGui::GetIO().MouseDoubleClickTime = croc_ex_checkNumParam(t, 1);
	return 0;
}

const StdlibRegisterInfo _io_getMouseDoubleClickTime_info =
{
	Docstr(DFunc("getMouseDoubleClickTime")
	R"()"),

	"getMouseDoubleClickTime", 0
};

word_t _io_getMouseDoubleClickTime(CrocThread* t)
{
	checkVM(t);
	croc_pushFloat(t, ImGui::GetIO().MouseDoubleClickTime);
	return 1;
}

const StdlibRegisterInfo _io_setMouseDoubleClickMaxDist_info =
{
	Docstr(DFunc("setMouseDoubleClickMaxDist")
	R"()"),

	"setMouseDoubleClickMaxDist", 1
};

word_t _io_setMouseDoubleClickMaxDist(CrocThread* t)
{
	checkVM(t);
	ImGui::GetIO().MouseDoubleClickMaxDist = croc_ex_checkNumParam(t, 1);
	return 0;
}

const StdlibRegisterInfo _io_getMouseDoubleClickMaxDist_info =
{
	Docstr(DFunc("getMouseDoubleClickMaxDist")
	R"()"),

	"getMouseDoubleClickMaxDist", 0
};

word_t _io_getMouseDoubleClickMaxDist(CrocThread* t)
{
	checkVM(t);
	croc_pushFloat(t, ImGui::GetIO().MouseDoubleClickMaxDist);
	return 1;
}

const StdlibRegisterInfo _io_setKeyMap_info =
{
	Docstr(DFunc("setKeyMap")
	R"()"),

	"setKeyMap", 2
};

word_t _io_setKeyMap(CrocThread* t)
{
	checkVM(t);
	auto key = croc_ex_checkIntParam(t, 1);
	auto mapped = croc_ex_checkIntParam(t, 2);

	if(key < 0 || key >= ImGuiKey_COUNT)
		croc_eh_throwStd(t, "RangeError", "Invalid key");

	ImGui::GetIO().KeyMap[key] = cast(int)mapped;
	return 0;
}

const StdlibRegisterInfo _io_getKeyMap_info =
{
	Docstr(DFunc("getKeyMap")
	R"()"),

	"getKeyMap", 1
};

word_t _io_getKeyMap(CrocThread* t)
{
	checkVM(t);
	auto key = croc_ex_checkIntParam(t, 1);

	if(key < 0 || key >= ImGuiKey_COUNT)
		croc_eh_throwStd(t, "RangeError", "Invalid key");

	croc_pushInt(t, ImGui::GetIO().KeyMap[key]);
	return 1;
}

// TODO: Font

const StdlibRegisterInfo _io_setFontYOffset_info =
{
	Docstr(DFunc("setFontYOffset")
	R"()"),

	"setFontYOffset", 1
};

word_t _io_setFontYOffset(CrocThread* t)
{
	checkVM(t);
	ImGui::GetIO().FontYOffset = croc_ex_checkNumParam(t, 1);
	return 0;
}

const StdlibRegisterInfo _io_getFontYOffset_info =
{
	Docstr(DFunc("getFontYOffset")
	R"()"),

	"getFontYOffset", 0
};

word_t _io_getFontYOffset(CrocThread* t)
{
	checkVM(t);
	croc_pushFloat(t, ImGui::GetIO().FontYOffset);
	return 1;
}

const StdlibRegisterInfo _io_setFontTexUvForWhite_info =
{
	Docstr(DFunc("setFontTexUvForWhite")
	R"()"),

	"setFontTexUvForWhite", 2
};

word_t _io_setFontTexUvForWhite(CrocThread* t)
{
	checkVM(t);
	auto w = croc_ex_checkNumParam(t, 1);
	auto h = croc_ex_checkNumParam(t, 2);
	ImGui::GetIO().FontTexUvForWhite = ImVec2(cast(float)w, cast(float)h);
	return 0;
}

const StdlibRegisterInfo _io_getFontTexUvForWhite_info =
{
	Docstr(DFunc("getFontTexUvForWhite")
	R"()"),

	"getFontTexUvForWhite", 0
};

word_t _io_getFontTexUvForWhite(CrocThread* t)
{
	checkVM(t);
	auto size = ImGui::GetIO().FontTexUvForWhite;
	croc_pushFloat(t, size.x);
	croc_pushFloat(t, size.y);
	return 2;
}

const StdlibRegisterInfo _io_setFontBaseScale_info =
{
	Docstr(DFunc("setFontBaseScale")
	R"()"),

	"setFontBaseScale", 1
};

word_t _io_setFontBaseScale(CrocThread* t)
{
	checkVM(t);
	auto scale = croc_ex_checkNumParam(t, 1);

	if(scale <= 0)
		croc_eh_throwStd(t, "RangeError", "Invalid font scale");

	ImGui::GetIO().FontBaseScale = scale;
	return 0;
}

const StdlibRegisterInfo _io_getFontBaseScale_info =
{
	Docstr(DFunc("getFontBaseScale")
	R"()"),

	"getFontBaseScale", 0
};

word_t _io_getFontBaseScale(CrocThread* t)
{
	checkVM(t);
	croc_pushFloat(t, ImGui::GetIO().FontBaseScale);
	return 1;
}

const StdlibRegisterInfo _io_setFontAllowUserScaling_info =
{
	Docstr(DFunc("setFontAllowUserScaling")
	R"()"),

	"setFontAllowUserScaling", 1
};

word_t _io_setFontAllowUserScaling(CrocThread* t)
{
	checkVM(t);
	ImGui::GetIO().FontAllowUserScaling = croc_ex_checkBoolParam(t, 1);
	return 0;
}

const StdlibRegisterInfo _io_getFontAllowUserScaling_info =
{
	Docstr(DFunc("getFontAllowUserScaling")
	R"()"),

	"getFontAllowUserScaling", 0
};

word_t _io_getFontAllowUserScaling(CrocThread* t)
{
	checkVM(t);
	croc_pushBool(t, ImGui::GetIO().FontAllowUserScaling);
	return 1;
}

const StdlibRegisterInfo _io_setFontFallbackGlyph_info =
{
	Docstr(DFunc("setFontFallbackGlyph")
	R"()"),

	"setFontFallbackGlyph", 1
};

word_t _io_setFontFallbackGlyph(CrocThread* t)
{
	checkVM(t);
	auto ch = croc_ex_checkCharParam(t, 1);

	if(ch > 0xffff)
		croc_eh_throwStd(t, "RangeError", "Fallback glyph must fall in the range U+000000 to U+00FFFF");

	ImGui::GetIO().FontFallbackGlyph = cast(ImWchar)ch;
	return 0;
}

const StdlibRegisterInfo _io_getFontFallbackGlyph_info =
{
	Docstr(DFunc("getFontFallbackGlyph")
	R"()"),

	"getFontFallbackGlyph", 0
};

word_t _io_getFontFallbackGlyph(CrocThread* t)
{
	checkVM(t);
	croc_pushChar(t, cast(crocchar)ImGui::GetIO().FontFallbackGlyph);
	return 1;
}

const StdlibRegisterInfo _io_setPixelCenterOffset_info =
{
	Docstr(DFunc("setPixelCenterOffset")
	R"()"),

	"setPixelCenterOffset", 1
};

word_t _io_setPixelCenterOffset(CrocThread* t)
{
	checkVM(t);
	ImGui::GetIO().PixelCenterOffset = croc_ex_checkNumParam(t, 1);
	return 0;
}

const StdlibRegisterInfo _io_getPixelCenterOffset_info =
{
	Docstr(DFunc("getPixelCenterOffset")
	R"()"),

	"getPixelCenterOffset", 0
};

word_t _io_getPixelCenterOffset(CrocThread* t)
{
	checkVM(t);
	croc_pushFloat(t, ImGui::GetIO().PixelCenterOffset);
	return 1;
}

const StdlibRegisterInfo _io_setRenderDrawListsCallback_info =
{
	Docstr(DFunc("setRenderDrawListsCallback")
	R"()"),

	"setRenderDrawListsCallback", 1
};

word_t _io_setRenderDrawListsCallback(CrocThread* t)
{
	checkVM(t);
	auto haveFunc = croc_ex_optParam(t, 1, CrocType_Function);
	croc_dup(t, 1);
	croc_ex_setRegistryVar(t, RenderDrawListsCallback);

	if(haveFunc)
		ImGui::GetIO().RenderDrawListsFn = &renderDrawLists;
	else
		ImGui::GetIO().RenderDrawListsFn = &noRenderDrawLists;

	return 0;
}

const StdlibRegisterInfo _io_getRenderDrawListsCallback_info =
{
	Docstr(DFunc("getRenderDrawListsCallback")
	R"()"),

	"getRenderDrawListsCallback", 0
};

word_t _io_getRenderDrawListsCallback(CrocThread* t)
{
	checkVM(t);
	getCallback(t, RenderDrawListsCallback);
	return 1;
}

const StdlibRegisterInfo _io_setSetClipboardTextCallback_info =
{
	Docstr(DFunc("setSetClipboardTextCallback")
	R"()"),

	"setSetClipboardTextCallback", 1
};

word_t _io_setSetClipboardTextCallback(CrocThread* t)
{
	checkVM(t);
	auto haveFunc = croc_ex_optParam(t, 1, CrocType_Function);
	croc_dup(t, 1);
	croc_ex_setRegistryVar(t, SetClipboardTextCallback);

	if(haveFunc)
		ImGui::GetIO().SetClipboardTextFn = &setClipboardText;
	else
		ImGui::GetIO().SetClipboardTextFn = nullptr;

	return 0;
}

const StdlibRegisterInfo _io_getSetClipboardTextCallback_info =
{
	Docstr(DFunc("getSetClipboardTextCallback")
	R"()"),

	"getSetClipboardTextCallback", 0
};

word_t _io_getSetClipboardTextCallback(CrocThread* t)
{
	checkVM(t);
	getCallback(t, SetClipboardTextCallback);
	return 1;
}

const StdlibRegisterInfo _io_setGetClipboardTextCallback_info =
{
	Docstr(DFunc("setGetClipboardTextCallback")
	R"()"),

	"setGetClipboardTextCallback", 1
};

word_t _io_setGetClipboardTextCallback(CrocThread* t)
{
	checkVM(t);
	auto haveFunc = croc_ex_optParam(t, 1, CrocType_Function);
	croc_dup(t, 1);
	croc_ex_setRegistryVar(t, GetClipboardTextCallback);

	if(haveFunc)
		ImGui::GetIO().GetClipboardTextFn = &getClipboardText;
	else
		ImGui::GetIO().GetClipboardTextFn = nullptr;

	return 0;
}

const StdlibRegisterInfo _io_getGetClipboardTextCallback_info =
{
	Docstr(DFunc("getGetClipboardTextCallback")
	R"()"),

	"getGetClipboardTextCallback", 0
};

word_t _io_getGetClipboardTextCallback(CrocThread* t)
{
	checkVM(t);
	getCallback(t, GetClipboardTextCallback);
	return 1;
}

const StdlibRegisterInfo _io_setImeSetInputScreenPosCallback_info =
{
	Docstr(DFunc("setImeSetInputScreenPosCallback")
	R"()"),

	"setImeSetInputScreenPosCallback", 1
};

word_t _io_setImeSetInputScreenPosCallback(CrocThread* t)
{
	checkVM(t);
	auto haveFunc = croc_ex_optParam(t, 1, CrocType_Function);
	croc_dup(t, 1);
	croc_ex_setRegistryVar(t, ImeSetInputScreenPosCallback);

	if(haveFunc)
		ImGui::GetIO().ImeSetInputScreenPosFn = &imeSetInputScreenPos;
	else
		ImGui::GetIO().ImeSetInputScreenPosFn = nullptr;

	return 0;
}

const StdlibRegisterInfo _io_getImeSetInputScreenPosCallback_info =
{
	Docstr(DFunc("getImeSetInputScreenPosCallback")
	R"()"),

	"getImeSetInputScreenPosCallback", 0
};

word_t _io_getImeSetInputScreenPosCallback(CrocThread* t)
{
	checkVM(t);
	getCallback(t, ImeSetInputScreenPosCallback);
	return 1;
}

const StdlibRegisterInfo _io_setMousePos_info =
{
	Docstr(DFunc("setMousePos")
	R"()"),

	"setMousePos", 2
};

word_t _io_setMousePos(CrocThread* t)
{
	checkVM(t);
	auto w = croc_ex_checkNumParam(t, 1);
	auto h = croc_ex_checkNumParam(t, 2);
	ImGui::GetIO().MousePos = ImVec2(cast(float)w, cast(float)h);
	return 0;
}

const StdlibRegisterInfo _io_setMouseDown_info =
{
	Docstr(DFunc("setMouseDown")
	R"()"),

	"setMouseDown", 2
};

word_t _io_setMouseDown(CrocThread* t)
{
	checkVM(t);
	auto button = croc_ex_checkIntParam(t, 1);
	auto down = croc_ex_checkBoolParam(t, 2);

	if(button < 0 || button >= 5)
		croc_eh_throwStd(t, "RangeError", "Invalid button");

	ImGui::GetIO().MouseDown[button] = down;
	return 0;
}

const StdlibRegisterInfo _io_setMouseWheel_info =
{
	Docstr(DFunc("setMouseWheel")
	R"()"),

	"setMouseWheel", 1
};

word_t _io_setMouseWheel(CrocThread* t)
{
	checkVM(t);
	ImGui::GetIO().MouseWheel = croc_ex_checkIntParam(t, 1);
	return 0;
}

const StdlibRegisterInfo _io_setKeyCtrl_info =
{
	Docstr(DFunc("setKeyCtrl")
	R"()"),

	"setKeyCtrl", 1
};

word_t _io_setKeyCtrl(CrocThread* t)
{
	checkVM(t);
	ImGui::GetIO().KeyCtrl = croc_ex_checkBoolParam(t, 1);
	return 0;
}

const StdlibRegisterInfo _io_setKeyShift_info =
{
	Docstr(DFunc("setKeyShift")
	R"()"),

	"setKeyShift", 1
};

word_t _io_setKeyShift(CrocThread* t)
{
	checkVM(t);
	ImGui::GetIO().KeyShift = croc_ex_checkBoolParam(t, 1);
	return 0;
}

const StdlibRegisterInfo _io_setKeysDown_info =
{
	Docstr(DFunc("setKeysDown")
	R"()"),

	"setKeysDown", 2
};

word_t _io_setKeysDown(CrocThread* t)
{
	checkVM(t);
	auto key = croc_ex_checkIntParam(t, 1);
	auto down = croc_ex_checkBoolParam(t, 2);

	if(key < 0 || key >= 512)
		croc_eh_throwStd(t, "RangeError", "Invalid key");

	ImGui::GetIO().KeysDown[key] = down;
	return 0;
}

const StdlibRegisterInfo _io_addInputCharacter_info =
{
	Docstr(DFunc("addInputCharacter")
	R"()"),

	"addInputCharacter", 1
};

word_t _io_addInputCharacter(CrocThread* t)
{
	checkVM(t);
	auto ch = croc_ex_checkCharParam(t, 1);

	if(ch > 0xffff)
		croc_eh_throwStd(t, "RangeError", "Input character must fall in the range U+000000 to U+00FFFF");

	ImGui::GetIO().AddInputCharacter(ch);
	return 0;
}

const StdlibRegisterInfo _io_getWantCaptureMouse_info =
{
	Docstr(DFunc("getWantCaptureMouse")
	R"()"),

	"getWantCaptureMouse", 0
};

word_t _io_getWantCaptureMouse(CrocThread* t)
{
	checkVM(t);
	croc_pushBool(t, ImGui::GetIO().WantCaptureMouse);
	return 1;
}

const StdlibRegisterInfo _io_getWantCaptureKeyboard_info =
{
	Docstr(DFunc("getWantCaptureKeyboard")
	R"()"),

	"getWantCaptureKeyboard", 0
};

word_t _io_getWantCaptureKeyboard(CrocThread* t)
{
	checkVM(t);
	croc_pushBool(t, ImGui::GetIO().WantCaptureKeyboard);
	return 1;
}

const StdlibRegister _ioFuncs[] =
{
	_DListItem(_io_setDisplaySize),
	_DListItem(_io_getDisplaySize),
	_DListItem(_io_setDeltaTime),
	_DListItem(_io_getDeltaTime),
	_DListItem(_io_setIniSavingRate),
	_DListItem(_io_getIniSavingRate),
	_DListItem(_io_setIniFilename),
	_DListItem(_io_getIniFilename),
	_DListItem(_io_setLogFilename),
	_DListItem(_io_getLogFilename),
	_DListItem(_io_setMouseDoubleClickTime),
	_DListItem(_io_getMouseDoubleClickTime),
	_DListItem(_io_setMouseDoubleClickMaxDist),
	_DListItem(_io_getMouseDoubleClickMaxDist),
	_DListItem(_io_setKeyMap),
	_DListItem(_io_getKeyMap),
	_DListItem(_io_setFontYOffset),
	_DListItem(_io_getFontYOffset),
	_DListItem(_io_setFontTexUvForWhite),
	_DListItem(_io_getFontTexUvForWhite),
	_DListItem(_io_setFontBaseScale),
	_DListItem(_io_getFontBaseScale),
	_DListItem(_io_setFontAllowUserScaling),
	_DListItem(_io_getFontAllowUserScaling),
	_DListItem(_io_setFontFallbackGlyph),
	_DListItem(_io_getFontFallbackGlyph),
	_DListItem(_io_setPixelCenterOffset),
	_DListItem(_io_getPixelCenterOffset),
	_DListItem(_io_setRenderDrawListsCallback),
	_DListItem(_io_getRenderDrawListsCallback),
	_DListItem(_io_setSetClipboardTextCallback),
	_DListItem(_io_getSetClipboardTextCallback),
	_DListItem(_io_setGetClipboardTextCallback),
	_DListItem(_io_getGetClipboardTextCallback),
	_DListItem(_io_setImeSetInputScreenPosCallback),
	_DListItem(_io_getImeSetInputScreenPosCallback),
	_DListItem(_io_setMousePos),
	_DListItem(_io_setMouseDown),
	_DListItem(_io_setMouseWheel),
	_DListItem(_io_setKeyCtrl),
	_DListItem(_io_setKeyShift),
	_DListItem(_io_setKeysDown),
	_DListItem(_io_addInputCharacter),
	_DListItem(_io_getWantCaptureMouse),
	_DListItem(_io_getWantCaptureKeyboard),
	_DListEnd
};

// =====================================================================================================================
// TextFilter class

#if CROC_BUILTIN_DOCS
const char* TextFilterDocs = DClass("TextFilter")
R"()";
#endif

const char* _Obj = "filterObj";

ImGuiTextFilter* getThis(CrocThread* t)
{
	croc_ex_checkInstParam(t, 0, "TextFilter");
	croc_hfield(t, 0, _Obj);

	if(croc_isNull(t, -1))
		croc_eh_throwStd(t, "StateError", "Attempting to call method on an uninitialized TextFilter instance");

	auto ret = cast(ImGuiTextFilter*)croc_memblock_getData(t, -1);
	croc_popTop(t);
	return ret;
}

const StdlibRegisterInfo TextFilter_constructor_info =
{
	Docstr(DFunc("constructor")
	R"()"),

	"constructor", 0
};

word_t TextFilter_constructor(CrocThread* t)
{
	croc_ex_checkInstParam(t, 0, "TextFilter");
	croc_hfield(t, 0, _Obj);

	if(!croc_isNull(t, -1))
		croc_eh_throwStd(t, "StateError", "Attempting to call constructor on an already-initialized TextFilter");

	croc_popTop(t);
	croc_memblock_new(t, sizeof(ImGuiTextFilter));
	auto filter = cast(ImGuiTextFilter*)croc_memblock_getData(t, -1);
	new(filter) ImGuiTextFilter;
	croc_hfielda(t, 0, _Obj);
	return 0;
}

const StdlibRegisterInfo TextFilter_finalizer_info =
{
	Docstr(DFunc("finalizer")
	R"()"),

	"finalizer", 0
};

word_t TextFilter_finalizer(CrocThread* t)
{
	croc_hfield(t, 0, _Obj);

	if(!croc_isNull(t, -1))
	{
		auto &filter = *cast(ImGuiTextFilter*)croc_memblock_getData(t, -1);
		filter.Clear();
		croc_pushNull(t);
		croc_hfielda(t, 0, _Obj);
	}

	return 0;
}

const StdlibRegisterInfo TextFilter_clear_info =
{
	Docstr(DFunc("clear")
	R"()"),

	"clear", 0
};

word_t TextFilter_clear(CrocThread* t)
{
	getThis(t)->Clear();
	return 0;
}

const StdlibRegisterInfo TextFilter_draw_info =
{
	Docstr(DFunc("draw")
	R"()"),

	"draw", 2
};

word_t TextFilter_draw(CrocThread* t)
{
	auto filter = getThis(t);
	auto label = croc_ex_optStringParam(t, 1, "Filter (inc,-exc)");
	auto width = croc_ex_optNumParam(t, 2, -1);
	filter->Draw(label, width);
	return 0;
}

const StdlibRegisterInfo TextFilter_passFilter_info =
{
	Docstr(DFunc("passFilter")
	R"()"),

	"passFilter", 1
};

word_t TextFilter_passFilter(CrocThread* t)
{
	croc_pushBool(t, getThis(t)->PassFilter(croc_ex_checkStringParam(t, 1)));
	return 1;
}

const StdlibRegisterInfo TextFilter_isActive_info =
{
	Docstr(DFunc("isActive")
	R"()"),

	"isActive", 0
};

word_t TextFilter_isActive(CrocThread* t)
{
	croc_pushBool(t, getThis(t)->IsActive());
	return 1;
}

const StdlibRegisterInfo TextFilter_build_info =
{
	Docstr(DFunc("build")
	R"()"),

	"build", 0
};

word_t TextFilter_build(CrocThread* t)
{
	getThis(t)->Build();
	return 0;
}

const StdlibRegister TextFilter_methodFuncs[] =
{
	_DListItem(TextFilter_constructor),
	_DListItem(TextFilter_finalizer),
	_DListItem(TextFilter_clear),
	_DListItem(TextFilter_draw),
	_DListItem(TextFilter_passFilter),
	_DListItem(TextFilter_isActive),
	_DListItem(TextFilter_build),
	_DListEnd
};

// =====================================================================================================================
// Constants

void registerConstants(CrocThread* t)
{
	croc_pushInt(t, ImGuiWindowFlags_ShowBorders);         croc_newGlobal(t, "WindowFlags_ShowBorders");
	croc_pushInt(t, ImGuiWindowFlags_NoTitleBar);          croc_newGlobal(t, "WindowFlags_NoTitleBar");
	croc_pushInt(t, ImGuiWindowFlags_NoResize);            croc_newGlobal(t, "WindowFlags_NoResize");
	croc_pushInt(t, ImGuiWindowFlags_NoMove);              croc_newGlobal(t, "WindowFlags_NoMove");
	croc_pushInt(t, ImGuiWindowFlags_NoScrollbar);         croc_newGlobal(t, "WindowFlags_NoScrollbar");
	croc_pushInt(t, ImGuiInputTextFlags_CharsDecimal);     croc_newGlobal(t, "InputTextFlags_CharsDecimal");
	croc_pushInt(t, ImGuiInputTextFlags_CharsHexadecimal); croc_newGlobal(t, "InputTextFlags_CharsHexadecimal");
	croc_pushInt(t, ImGuiInputTextFlags_AutoSelectAll);    croc_newGlobal(t, "InputTextFlags_AutoSelectAll");
	croc_pushInt(t, ImGuiInputTextFlags_EnterReturnsTrue); croc_newGlobal(t, "InputTextFlags_EnterReturnsTrue");
	croc_pushInt(t, ImGuiKey_Tab);                         croc_newGlobal(t, "Key_Tab");
	croc_pushInt(t, ImGuiKey_LeftArrow);                   croc_newGlobal(t, "Key_LeftArrow");
	croc_pushInt(t, ImGuiKey_RightArrow);                  croc_newGlobal(t, "Key_RightArrow");
	croc_pushInt(t, ImGuiKey_UpArrow);                     croc_newGlobal(t, "Key_UpArrow");
	croc_pushInt(t, ImGuiKey_DownArrow);                   croc_newGlobal(t, "Key_DownArrow");
	croc_pushInt(t, ImGuiKey_Home);                        croc_newGlobal(t, "Key_Home");
	croc_pushInt(t, ImGuiKey_End);                         croc_newGlobal(t, "Key_End");
	croc_pushInt(t, ImGuiKey_Delete);                      croc_newGlobal(t, "Key_Delete");
	croc_pushInt(t, ImGuiKey_Backspace);                   croc_newGlobal(t, "Key_Backspace");
	croc_pushInt(t, ImGuiKey_Enter);                       croc_newGlobal(t, "Key_Enter");
	croc_pushInt(t, ImGuiKey_Escape);                      croc_newGlobal(t, "Key_Escape");
	croc_pushInt(t, ImGuiKey_A);                           croc_newGlobal(t, "Key_A");
	croc_pushInt(t, ImGuiKey_C);                           croc_newGlobal(t, "Key_C");
	croc_pushInt(t, ImGuiKey_V);                           croc_newGlobal(t, "Key_V");
	croc_pushInt(t, ImGuiKey_X);                           croc_newGlobal(t, "Key_X");
	croc_pushInt(t, ImGuiKey_Y);                           croc_newGlobal(t, "Key_Y");
	croc_pushInt(t, ImGuiKey_Z);                           croc_newGlobal(t, "Key_Z");
	croc_pushInt(t, ImGuiCol_Text);                        croc_newGlobal(t, "Col_Text");
	croc_pushInt(t, ImGuiCol_WindowBg);                    croc_newGlobal(t, "Col_WindowBg");
	croc_pushInt(t, ImGuiCol_Border);                      croc_newGlobal(t, "Col_Border");
	croc_pushInt(t, ImGuiCol_BorderShadow);                croc_newGlobal(t, "Col_BorderShadow");
	croc_pushInt(t, ImGuiCol_FrameBg);                     croc_newGlobal(t, "Col_FrameBg");
	croc_pushInt(t, ImGuiCol_TitleBg);                     croc_newGlobal(t, "Col_TitleBg");
	croc_pushInt(t, ImGuiCol_TitleBgCollapsed);            croc_newGlobal(t, "Col_TitleBgCollapsed");
	croc_pushInt(t, ImGuiCol_ScrollbarBg);                 croc_newGlobal(t, "Col_ScrollbarBg");
	croc_pushInt(t, ImGuiCol_ScrollbarGrab);               croc_newGlobal(t, "Col_ScrollbarGrab");
	croc_pushInt(t, ImGuiCol_ScrollbarGrabHovered);        croc_newGlobal(t, "Col_ScrollbarGrabHovered");
	croc_pushInt(t, ImGuiCol_ScrollbarGrabActive);         croc_newGlobal(t, "Col_ScrollbarGrabActive");
	croc_pushInt(t, ImGuiCol_ComboBg);                     croc_newGlobal(t, "Col_ComboBg");
	croc_pushInt(t, ImGuiCol_CheckHovered);                croc_newGlobal(t, "Col_CheckHovered");
	croc_pushInt(t, ImGuiCol_CheckActive);                 croc_newGlobal(t, "Col_CheckActive");
	croc_pushInt(t, ImGuiCol_SliderGrab);                  croc_newGlobal(t, "Col_SliderGrab");
	croc_pushInt(t, ImGuiCol_SliderGrabActive);            croc_newGlobal(t, "Col_SliderGrabActive");
	croc_pushInt(t, ImGuiCol_Button);                      croc_newGlobal(t, "Col_Button");
	croc_pushInt(t, ImGuiCol_ButtonHovered);               croc_newGlobal(t, "Col_ButtonHovered");
	croc_pushInt(t, ImGuiCol_ButtonActive);                croc_newGlobal(t, "Col_ButtonActive");
	croc_pushInt(t, ImGuiCol_Header);                      croc_newGlobal(t, "Col_Header");
	croc_pushInt(t, ImGuiCol_HeaderHovered);               croc_newGlobal(t, "Col_HeaderHovered");
	croc_pushInt(t, ImGuiCol_HeaderActive);                croc_newGlobal(t, "Col_HeaderActive");
	croc_pushInt(t, ImGuiCol_Column);                      croc_newGlobal(t, "Col_Column");
	croc_pushInt(t, ImGuiCol_ColumnHovered);               croc_newGlobal(t, "Col_ColumnHovered");
	croc_pushInt(t, ImGuiCol_ColumnActive);                croc_newGlobal(t, "Col_ColumnActive");
	croc_pushInt(t, ImGuiCol_ResizeGrip);                  croc_newGlobal(t, "Col_ResizeGrip");
	croc_pushInt(t, ImGuiCol_ResizeGripHovered);           croc_newGlobal(t, "Col_ResizeGripHovered");
	croc_pushInt(t, ImGuiCol_ResizeGripActive);            croc_newGlobal(t, "Col_ResizeGripActive");
	croc_pushInt(t, ImGuiCol_CloseButton);                 croc_newGlobal(t, "Col_CloseButton");
	croc_pushInt(t, ImGuiCol_CloseButtonHovered);          croc_newGlobal(t, "Col_CloseButtonHovered");
	croc_pushInt(t, ImGuiCol_CloseButtonActive);           croc_newGlobal(t, "Col_CloseButtonActive");
	croc_pushInt(t, ImGuiCol_PlotLines);                   croc_newGlobal(t, "Col_PlotLines");
	croc_pushInt(t, ImGuiCol_PlotLinesHovered);            croc_newGlobal(t, "Col_PlotLinesHovered");
	croc_pushInt(t, ImGuiCol_PlotHistogram);               croc_newGlobal(t, "Col_PlotHistogram");
	croc_pushInt(t, ImGuiCol_PlotHistogramHovered);        croc_newGlobal(t, "Col_PlotHistogramHovered");
	croc_pushInt(t, ImGuiCol_TextSelectedBg);              croc_newGlobal(t, "Col_TextSelectedBg");
	croc_pushInt(t, ImGuiCol_TooltipBg);                   croc_newGlobal(t, "Col_TooltipBg");
	croc_pushInt(t, ImGuiColorEditMode_UserSelect);        croc_newGlobal(t, "ColorEditMode_UserSelect");
	croc_pushInt(t, ImGuiColorEditMode_RGB);               croc_newGlobal(t, "ColorEditMode_RGB");
	croc_pushInt(t, ImGuiColorEditMode_HSV);               croc_newGlobal(t, "ColorEditMode_HSV");
	croc_pushInt(t, ImGuiColorEditMode_HEX);               croc_newGlobal(t, "ColorEditMode_HEX");
}

// =====================================================================================================================
// Loader

word loader(CrocThread* t)
{
	registerConstants(t);
	registerGlobals(t, _globalFuncs);

	croc_namespace_newNoParent(t, "io");
		registerFields(t, _ioFuncs);
	croc_newGlobal(t, "io");

	croc_class_new(t, "TextFilter", 0);
		croc_pushNull(t); croc_class_addHField(t, -2, _Obj);
		registerMethods(t, TextFilter_methodFuncs);
	croc_newGlobal(t, "TextFilter");

#ifdef CROC_BUILTIN_DOCS
	CrocDoc doc;
	croc_ex_doc_init(t, &doc, __FILE__);
	croc_dup(t, 0);
		croc_ex_doc_push(&doc, moduleDocs);
			docGlobals(&doc, _globalFuncs);
		croc_ex_doc_pop(&doc, -1);

		croc_field(t, -1, "io");
			croc_ex_doc_push(&doc, ioDocs);
				docFields(&doc, _ioFuncs);
			croc_ex_doc_pop(&doc, -1);
		croc_popTop(t);

		croc_field(t, -1, "TextFilter");
			croc_ex_doc_push(&doc, TextFilterDocs);
				docFields(&doc, TextFilter_methodFuncs);
			croc_ex_doc_pop(&doc, -1);
		croc_popTop(t);
	croc_ex_doc_finish(&doc);
	croc_popTop(t);
#endif

	return 0;
}
}

void initImGuiLib(CrocThread* t)
{
	croc_ex_makeModule(t, "imgui", &loader);
}
}
#endif