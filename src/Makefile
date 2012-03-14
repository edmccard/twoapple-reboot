COMPILE_OPTS = -c -version=CycleAccuracy -op -Jdata -I$(GTKD)/src \
	-I$(GTKD)/srcgl -I$(DERELICT)/import

LINK_OPTS = -L-lpthread -L-lGL -L-ldl -L-lX11 \
   -L-L$(GTKD) -L-lgtkd -L-lgtkdgl \
   -L-L$(DERELICT)/lib -L-lDerelictSDL -L-lDerelictUtil \

ALL_SRC = $(shell find -name "*.d")
ALL_OBJS = $(ALL_SRC:%.d=%.o)

all: ${ALL_OBJS}
	dmd ${ALL_OBJS} -oftwoapple ${LINK_OPTS}

clean:
	rm -rf twoapple ${ALL_OBJS}

%.o: %.d
	dmd $(DFLAGS) -inline -release -O $(COMPILE_OPTS) $<

