@echo off
set DFLAGS=-debug -g -ofcompiler.exe
set DPROG=compiler
set DFILES=state.d types.d %DPROG%.d opcodes.d vm.d
set DLIBS=

call \dmd\proj\maincompile.bat
