.PHONY: all clean ebpf

all: ebpf
	mkdir -p build
	cd build && cmake .. -DCMAKE_BUILD_TYPE=Release && make -j$(nproc)

ebpf:
	$(MAKE) -C ebpf

clean:
	$(MAKE) -C ebpf clean
	rm -rf build