@echo off

set BASEFILES=minid\arraylib.d
set BASEFILES=%BASEFILES% minid\baselib.d
set BASEFILES=%BASEFILES% minid\charlib.d
set BASEFILES=%BASEFILES% minid\compiler.d
set BASEFILES=%BASEFILES% minid\iolib.d
set BASEFILES=%BASEFILES% minid\mathlib.d
set BASEFILES=%BASEFILES% minid\minid.d
set BASEFILES=%BASEFILES% minid\opcodes.d
set BASEFILES=%BASEFILES% minid\oslib.d
set BASEFILES=%BASEFILES% minid\regexplib.d
set BASEFILES=%BASEFILES% minid\stringlib.d
set BASEFILES=%BASEFILES% minid\tablelib.d
set BASEFILES=%BASEFILES% minid\types.d
set BASEFILES=%BASEFILES% minid\utils.d

rem goto makemdcl
rem goto makeminidc

:maketest
	set DFLAGS=-debug -g -oftest.exe
	set DPROG=test
	set DFILES=%DPROG%.d %BASEFILES%
	set DLIBS=
	
	call \dmd\proj\maincompile.bat
goto end

:makemdcl
	set DFLAGS=-release -ofmdcl.exe
	set DPROG=mdcl
	set DFILES=%DPROG%.d %BASEFILES%
	set DLIBS=
	
	call \dmd\proj\maincompile.bat
goto end

:makeminidc
	set DFLAGS=-release -ofminidc.exe
	set DPROG=minidc
	set DFILES=%DPROG%.d %BASEFILES%
	set DLIBS=
	
	call \dmd\proj\maincompile.bat
goto end

:end