import numpy as np
N = 256
for x in np.sin(2 * np.pi * np.arange(N) / N):
    val = int(x * (2**23 - 1)) & 0xFFFFFF
    print(f"{val:06X}")