@echo off

set BASEFILES=minid.d types.d compiler.d opcodes.d utils.d stringlib.d oslib.d arraylib.d tablelib.d baselib.d mathlib.d charlib.d iolib.d

rem goto makemdcl
rem goto makeminidc

set DFLAGS=-debug -g -oftest.exe -I"C:\dmd\proj\minid"
set DPROG=test
set DFILES=%DPROG%.d %BASEFILES%
set DLIBS=

call \dmd\proj\maincompile.bat
goto end

:makemdcl
	set DFLAGS=-release -ofmdcl.exe -I"C:\dmd\proj\minid"
	set DPROG=mdcl
	set DFILES=%DPROG%.d %BASEFILES%
	set DLIBS=
	
	call \dmd\proj\maincompile.bat
goto end

:makeminidc
	set DFLAGS=-release -ofminidc.exe -I"C:\dmd\proj\minid"
	set DPROG=minidc
	set DFILES=%DPROG%.d %BASEFILES%
	set DLIBS=
	
	call \dmd\proj\maincompile.bat
goto end

:end