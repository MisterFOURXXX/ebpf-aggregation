CLANG ?= clang
ARCH := $(shell uname -m | sed 's/x86_64/x86/;s/aarch64/arm64/')
CFLAGS := -target bpf -D__TARGET_ARCH_$(ARCH) \
          -I/usr/include/$(shell uname -m)-linux-gnu -O2 -g

all: aggregator.bpf.o aggregator_pass.bpf.o

aggregator.bpf.o: aggregator.bpf.c aggregator.h maps_config.h
	$(CLANG) $(CFLAGS) -c $< -o $@

aggregator_pass.bpf.o: aggregator_pass.bpf.c aggregator.h maps_config.h
	$(CLANG) $(CFLAGS) -c $< -o $@

clean:
	rm -f *.o

.PHONY: all clean
