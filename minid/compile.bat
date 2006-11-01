@echo off

rem goto makelib

set DFLAGS=-debug -g -oftest.exe -I"C:\dmd\proj\minid"
set DPROG=test
set DFILES=state.d types.d %DPROG%.d compiler.d opcodes.d stringlib.d arraylib.d tablelib.d baselib.d mathlib.d charlib.d iolib.d
rem set DFILES=%DPROG%.d
rem set DLIBS=minid.lib

call \dmd\proj\maincompile.bat
goto end

:makelib
set DFLAGS=-release -g -c -I"C:\dmd\proj\minid"
set DPROG=
set DFILES=state.d types.d compiler.d opcodes.d stringlib.d arraylib.d tablelib.d baselib.d mathlib.d charlib.d iolib.d
set DLIBS=

\dmd\bin\dmd %DFLAGS% %DFILES%
\dm\bin\lib -c minid.lib state.obj types.obj compiler.obj opcodes.obj stringlib.obj arraylib.obj tablelib.obj baselib.obj mathlib.obj charlib.obj iolib.obj
del *.obj
:end