.PHONY: all clean ebpf client benchmarks examples

all: ebpf client benchmarks examples

ebpf:
	$(MAKE) -C ebpf

client:
	$(MAKE) -C client_lib

benchmarks:
	$(MAKE) -C benchmarks

examples:
	$(MAKE) -C examples

clean:
	$(MAKE) -C ebpf clean
	$(MAKE) -C client_lib clean
	$(MAKE) -C benchmarks clean
	$(MAKE) -C examples clean
	rm -rf build/