@echo off
set DFLAGS=-debug -g -oftest.exe -I"C:\dmd\proj\minid"
set DPROG=test
set DFILES=state.d types.d %DPROG%.d compiler.d opcodes.d stringlib.d arraylib.d tablelib.d baselib.d
set DLIBS=

call \dmd\proj\maincompile.bat
