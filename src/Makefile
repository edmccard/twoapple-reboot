COMPILE_OPTS = -op -Jdata -I$(GTKD)/src \
	-I$(GTKD)/srcgl -I$(DERELICT)/import \
	-inline -release -O -noboundscheck \
	-version=OpNestedSwitch

LINK_OPTS = -L-lpthread -L-lGL -L-ldl -L-lX11 \
			-L-L$(GTKD) -L-lgtkd -L-lgtkdgl \
			-L-L$(DERELICT)/lib -L-lDerelictSDL -L-lDerelictUtil

ALL_SRC = $(shell find -name "*.d" \! -name "ctfe*")

all: ${ALL_SRC}
	dmd $(COMPILE_OPTS) ${ALL_SRC} -oftwoapple ${LINK_OPTS}

clean:
	rm -rf twoapple twoapple.o

