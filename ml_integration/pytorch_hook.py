import torch.distributed as dist
import ctypes
import numpy as np
import os
import torch

lib_path = os.path.join(os.path.dirname(__file__), "../client_lib/libswitchml.so")
lib = ctypes.CDLL(lib_path)

AGG_IP = os.getenv("AGGREGATOR_IP", "192.168.1.100")
AGG_PORT = int(os.getenv("AGGREGATOR_PORT", "9999"))
WORKER_ID = int(os.getenv("WORKER_ID", "0"))

lib.switchml_init.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
lib.switchml_init.restype = ctypes.c_int
lib.switchml_allreduce.argtypes = [ctypes.POINTER(ctypes.c_int32),
                                   ctypes.POINTER(ctypes.c_int32),
                                   ctypes.c_size_t]
lib.switchml_allreduce.restype = ctypes.c_int

def switchml_allreduce_hook(tensor):
    if tensor.is_cuda:
        tensor_cpu = tensor.cpu()
    else:
        tensor_cpu = tensor
    scale = 1000.0
    arr_float = tensor_cpu.detach().numpy().astype(np.float32)
    arr_int = (arr_float * scale).astype(np.int32)

    ret = lib.switchml_allreduce(
        arr_int.ctypes.data_as(ctypes.POINTER(ctypes.c_int32)),
        arr_int.ctypes.data_as(ctypes.POINTER(ctypes.c_int32)),
        arr_int.size
    )
    if ret != 0:
        raise RuntimeError("eBPF-Agg AllReduce failed")
    result_float = arr_int.astype(np.float32) / scale
    tensor.copy_(torch.from_numpy(result_float))

def patch_allreduce():
    original_allreduce = dist.all_reduce
    def patched_allreduce(tensor, op=dist.ReduceOp.SUM, group=None, async_op=False):
        if op == dist.ReduceOp.SUM:
            switchml_allreduce_hook(tensor)
        else:
            original_allreduce(tensor, op, group, async_op)
    dist.all_reduce = patched_allreduce
    print("[eBPF-Agg] PyTorch patched successfully.")

if not hasattr(lib, "_initialized"):
    lib.switchml_init(AGG_IP.encode(), AGG_PORT, WORKER_ID)
    lib._initialized = True