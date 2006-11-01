DMD = \dmd\bin\dmd

PROG = test
FLAGS = -debug -g -of$(PROG).exe -I"C:\dmd\proj\minid"
FILES = state.d types.d $(PROG).d compiler.d opcodes.d stringlib.d arraylib.d tablelib.d baselib.d mathlib.d charlib.d iolib.d

all:
	$(DMD) $(FLAGS) $(FILES)
	del *.obj
	del *.map
