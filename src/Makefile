DMD_OPTS = -c -version=CycleAccuracy -op -Jdata -I$(GTKD)/src -I$(GTKD)/srcgl \
	   -I$(DERELICT)/import

GCC_OPTS = -lpthread -lm -lGL -ldl -lX11 -lrt \
	   -L$(GTKD) -lgtkd -lgtkdgl \
	   -L$(DERELICT)/lib -lDerelictSDL -lDerelictUtil \
	   -lphobos2 -ldruntime

ALL_SRC = $(shell find -name "*.d")
ALL_OBJS = $(ALL_SRC:%.d=%.o)

all: ${ALL_OBJS}
	gcc ${ALL_OBJS} -o twoapple ${GCC_OPTS}

clean:
	rm -rf twoapple ${ALL_OBJS}

twoapple.o: twoapple.d
	dmd $(DFLAGS) -inline -O $(DMD_OPTS) $<

%.o: %.d
	dmd $(DFLAGS) -inline -release -O $(DMD_OPTS) $<

