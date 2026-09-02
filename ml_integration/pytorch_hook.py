import torch.distributed as dist
import torch

def switchml_allreduce_hook(tensor):
    # Stub – in real use, call C++ library via Python bindings
    dist.all_reduce(tensor)

def patch_allreduce():
    original = dist.all_reduce
    def patched(tensor, op=dist.ReduceOp.SUM, group=None, async_op=False):
        # Use SwitchML for CPU tensors; fall back to NCCL for GPU
        if tensor.is_cuda:
            original(tensor, op, group, async_op)
        else:
            switchml_allreduce_hook(tensor)
    dist.all_reduce = patched