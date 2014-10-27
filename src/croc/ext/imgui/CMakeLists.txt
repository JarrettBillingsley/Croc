cmake_minimum_required(VERSION 2.8)

set(imgui_SRC
	imconfig.h
	imgui.cpp
	imgui.h
	imgui_user.inl
	stb_textedit.h
)

add_library(imgui ${imgui_SRC})