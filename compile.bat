@echo off
set DFLAGS=-debug -g
set DPROG=minid
set DFILES=%DPROG%.d
set DLIBS=

call \dmd\proj\maincompile.bat
