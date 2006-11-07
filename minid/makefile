DMD = \dmd\bin\dmd
LIB = \dm\bin\lib

FLAGS = -debug -g -I"C:\dmd\proj\minid"

#PITAS are files which really don't like to play nicely.

PITAS = state.d types.d
BASEFILES = $(PITAS) opcodes.d
BASEOBJS = state.obj types.obj opcodes.obj
COMPILERFILES = compiler.d
STDLIBFILES = stringlib.d arraylib.d tablelib.d baselib.d mathlib.d charlib.d iolib.d

TESTFILES = test.d $(BASEFILES) $(COMPILERFILES) $(STDLIBFILES)

test:
	@if exist test.exe del test.exe
	-$(DMD) $(FLAGS) -oftest.exe $(TESTFILES)
	@if exist test.obj del *.obj *.map
