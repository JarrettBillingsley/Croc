@echo off
set DFLAGS=-debug -g -ofcompiler.exe -I"C:\dmd\proj\minid"
set DPROG=compiler
set DFILES=state.d types.d %DPROG%.d opcodes.d
set DLIBS=

call \dmd\proj\maincompile.bat
