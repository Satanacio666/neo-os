CC = aarch64-linux-gnu-gcc
AR = aarch64-linux-gnu-ar
CFLAGS = -fshort-wchar -fno-strict-aliasing -ffreestanding -fno-stack-protector -fno-stack-check \
         -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -I. -D__aarch64__ -fpic -fPIC -O2

# Pure freestanding algorithmic Lua core (no host OS file handles or system() calls)
SRCS = lapi.c lauxlib.c lbaselib.c lcode.c lcorolib.c lctype.c ldblib.c ldebug.c ldo.c ldump.c \
       lfunc.c lgc.c linit.c llex.c lmathlib.c lmem.c lobject.c lopcodes.c \
       lparser.c lstate.c lstring.c lstrlib.c ltable.c ltablib.c ltm.c lundump.c \
       lutf8lib.c lvm.c lzio.c
OBJS = $(SRCS:.c=.o)

all: liblua.a

liblua.a: $(OBJS)
	$(AR) rcs $@ $(OBJS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) liblua.a
