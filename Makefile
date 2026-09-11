.PHONY: all clean build-ebpf build-client build-examples build-benchmarks

CMAKE_FLAGS = -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY

all: build-ebpf build-client

build-ebpf:
	cd ebpf && $(MAKE)

build-client:
	cd client_lib && mkdir -p build && cd build && cmake $(CMAKE_FLAGS) .. >/dev/null && $(MAKE) --no-print-directory

build-examples: build-client
	cd examples && mkdir -p build && cd build && cmake $(CMAKE_FLAGS) .. >/dev/null && $(MAKE) --no-print-directory

build-benchmarks: build-client
	cd benchmarks && mkdir -p build && cd build && cmake $(CMAKE_FLAGS) .. >/dev/null && $(MAKE) --no-print-directory

clean:
	cd ebpf && $(MAKE) clean
	rm -rf client_lib/build
	rm -rf examples/build
	rm -rf benchmarks/build
	rm -rf tests/build
	rm -rf operator/bin
