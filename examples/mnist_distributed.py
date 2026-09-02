#!/usr/bin/env python3
import torch
import torch.nn as nn
import torch.optim as optim
import torch.distributed as dist
import torch.multiprocessing as mp
from torch.nn.parallel import DistributedDataParallel as DDP
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from ml_integration import patch_allreduce

class SimpleCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 32, 3, 1)
        self.conv2 = nn.Conv2d(32, 64, 3, 1)
        self.fc = nn.Linear(64*12*12, 10)
    def forward(self, x):
        x = torch.relu(self.conv1(x))
        x = torch.relu(self.conv2(x))
        x = x.view(-1, 64*12*12)
        return self.fc(x)

def train(rank, world_size):
    patch_allreduce()
    dist.init_process_group("gloo", rank=rank, world_size=world_size)
    model = DDP(SimpleCNN().float())
    optimizer = optim.Adam(model.parameters(), lr=0.001)
    criterion = nn.CrossEntropyLoss()

    for epoch in range(2):
        for step in range(5):
            inputs = torch.randn(8, 1, 28, 28)
            labels = torch.randint(0, 10, (8,))
            optimizer.zero_grad()
            outputs = model(inputs)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()
            if rank == 0:
                print(f"Epoch {epoch}, Step {step}, Loss: {loss.item():.4f}")
    dist.destroy_process_group()

if __name__ == "__main__":
    world_size = int(os.getenv("WORLD_SIZE", "2"))
    mp.spawn(train, args=(world_size,), nprocs=world_size, join=True)