CLANG ?= clang
ARCH := $(shell uname -m | sed 's/x86_64/x86/')
CFLAGS := -target bpf -D__TARGET_ARCH_$(ARCH) -I/usr/include/$(ARCH)-linux-gnu -O2 -g

all: aggregator.bpf.o

aggregator.bpf.o: aggregator.bpf.c aggregator.h maps_config.h
	$(CLANG) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o