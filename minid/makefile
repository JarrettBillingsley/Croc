DMD = \dmd\bin\dmd
LIB = \dm\bin\lib
GDC = \gdc\bin\gdc

FLAGS = -debug -g -I"C:\dmd\proj\minid"
GDCFLAGS = -fall-sources -fdebug -g -I "C:\dmd\proj\minid"

#PITAS are files which really don't like to play nicely.

PITAS = types.d state.d
BASEFILES = $(PITAS) opcodes.d
BASEOBJS = state.obj types.obj opcodes.obj
COMPILERFILES = compiler.d
STDLIBFILES = stringlib.d arraylib.d tablelib.d baselib.d mathlib.d charlib.d iolib.d

TESTFILES = test.d $(BASEFILES) $(COMPILERFILES) $(STDLIBFILES)

test:
	@if exist test.exe del test.exe
	-$(DMD) $(FLAGS) -oftest.exe $(TESTFILES)
	@if exist test.obj del *.obj *.map

gnu:
	@if exist test.exe del test.exe
	-$(GDC) $(GDCFLAGS) -o test.exe $(TESTFILES)
	@if exist test.o del *.o
