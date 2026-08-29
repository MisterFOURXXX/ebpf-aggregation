# __init__.py - Make ml_integration a package
from .pytorch_hook import patch_allreduce, switchml_allreduce_hook

__all__ = ["patch_allreduce", "switchml_allreduce_hook"]