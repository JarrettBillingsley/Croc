@echo off

rem goto makelib
rem goto makemdcl

set DFLAGS=-debug -g -oftest.exe -I"C:\dmd\proj\minid"
set DPROG=test
set DFILES=%DPROG%.d state.d types.d compiler.d opcodes.d stringlib.d arraylib.d tablelib.d baselib.d mathlib.d charlib.d iolib.d
rem set DFILES=%DPROG%.d
rem set DLIBS=minid.lib

call \dmd\proj\maincompile.bat
goto end

:makemdcl
set DFLAGS=-release -ofmdcl.exe -I"C:\dmd\proj\minid"
set DPROG=mdcl
set DFILES=%DPROG%.d state.d types.d compiler.d opcodes.d stringlib.d arraylib.d tablelib.d baselib.d mathlib.d charlib.d iolib.d
rem set DFILES=%DPROG%.d
rem set DLIBS=minid.lib

call \dmd\proj\maincompile.bat
goto end

:makelib
set DFLAGS=-release -c -I"C:\dmd\proj\minid"
set DPROG=
set DFILES=state.d types.d opcodes.d
set DLIBS=

\dmd\bin\dmd %DFLAGS% %DFILES%
\dm\bin\lib -c minidbase.lib state.obj types.obj opcodes.obj

rem set DFLAGS=-release -c -I"C:\dmd\proj\minid"
rem set DPROG=
rem set DFILES=compiler.d
rem set DLIBS=
rem
rem \dmd\bin\dmd %DFLAGS% %DFILES%
rem \dm\bin\lib -c minidcompiler.lib compiler.obj

set DFLAGS=-release -c -I"C:\dmd\proj\minid"
set DPROG=
set DFILES=stringlib.d arraylib.d tablelib.d baselib.d mathlib.d charlib.d iolib.d
set DLIBS=

\dmd\bin\dmd %DFLAGS% %DFILES%
\dm\bin\lib -c minidstdlib.lib stringlib.obj arraylib.obj tablelib.obj baselib.obj mathlib.obj charlib.obj iolib.obj
del *.obj
:end