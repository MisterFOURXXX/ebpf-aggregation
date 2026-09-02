# ebpf_loader.py - Interact with bpfd gRPC API
import grpc
import logging
import os

# Assuming bpfd protobufs are generated and available
# In real implementation, you'd import bpfd_pb2, bpfd_pb2_grpc
# For now, stub
class BpfdClient:
    def __init__(self, address="bpfd.bpfd.svc:50051"):
        self.address = address
        # self.channel = grpc.insecure_channel(address)
        # self.stub = bpfd_pb2_grpc.BpfdStub(self.channel)
        logging.info(f"BpfdClient created for {address}")

    def load_xdp(self, program_path, interface, pin_path=None):
        # Build LoadXDPRequest
        logging.info(f"Loading XDP program {program_path} on {interface}")
        # return self.stub.LoadXDP(req)
        return True

    def unload_xdp(self, interface):
        logging.info(f"Unloading XDP from {interface}")
        return True

def load_xdp_program(program_path, interface, pin_path=None):
    client = BpfdClient()
    return client.load_xdp(program_path, interface, pin_path)

def unload_xdp_program(interface):
    client = BpfdClient()
    return client.unload_xdp(interface)