
COMPILER1 =  gcc
COMPILER2 = /usr/local/cuda-5.5/bin/nvcc
OBJS1 = ising.c
OBJS2 = ising2d.cu
LIB = -lm
CFLAG2 = -arch=sm_20
ifdef gflag
 CFLAG += -g
endif

default: clean ising
all: clean ising

ising:	${OBJS}
	${COMPILER1}	${CFLAG}	$(LIB)	${OBJS1}	-O3	-o	ising.o
cuda:	${OBJS}
	${COMPILER2}	${CFLAG2}	${CFLAG}	$(LIB)	${OBJS2}	-O3	-o	ising2d.o
clean:
	-rm	-f	*.o
