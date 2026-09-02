.PHONY: all clean build-ebpf build-client build-operator

CMAKE_FLAGS = -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY

all: build-ebpf build-client

build-ebpf:
	cd ebpf && $(MAKE)

build-client:
	cd client_lib && mkdir -p build && cd build && cmake $(CMAKE_FLAGS) .. && $(MAKE)

build-operator:
	cd operator && $(MAKE) build

clean:
	cd ebpf && $(MAKE) clean
	cd client_lib && rm -rf build
	cd operator && rm -rf bin