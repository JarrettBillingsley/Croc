@echo off
set DFLAGS=-debug -g
set DPROG=compiler
set DFILES=%DPROG%.d types.d opcodes.d
set DLIBS=

call \dmd\proj\maincompile.bat
