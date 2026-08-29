CLANG ?= clang
CFLAGS = -O2 -g -target bpf -D__TARGET_ARCH_x86 \
         -I/usr/include/x86_64-linux-gnu \
         -I/usr/lib/llvm-14/include

all: aggregator.bpf.o

aggregator.bpf.o: aggregator.bpf.c aggregator.h
	$(CLANG) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o *.ll