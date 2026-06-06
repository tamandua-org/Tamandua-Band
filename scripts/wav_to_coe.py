import numpy as np
from scipy.io import wavfile
import sys

def wav_to_coe(wav_filename, coe_filename):
    print(f"Reading {wav_filename}...")
    
    # Read the WAV file
    sample_rate, data = wavfile.read(wav_filename)
    
    # If the audio is stereo, keep only the left channel
    if len(data.shape) > 1:
        data = data[:, 0]
        print("Converted stereo to mono.")
        
    # --- FIX 1: Prevent 8-bit unsigned DC offset noise ---
    if data.dtype == np.uint8:
        # 8-bit audio is 0 to 255. We must center it to -128 to 127
        data = data.astype(np.float32) - 128.0
    else:
        # --- FIX 2: Convert to float early to prevent 16-bit np.abs() overflow ---
        data = data.astype(np.float32)
        
    # 1. Normalize the audio to a float between -1.0 and 1.0
    max_val = np.max(np.abs(data))
    if max_val == 0:
        print("Error: Audio file is completely silent!")
        return
        
    normalized_data = data / max_val
    
    # 2. Scale to 24-bit Signed Integer bounds (-8388608 to 8388607)
    max_24bit = (2**23) - 1
    scaled_data = np.int32(normalized_data * max_24bit)
    
    # 3. Write the Vivado .coe file
    print(f"Writing {len(scaled_data)} samples to {coe_filename}...")
    print(f"--> Use 24'd{len(scaled_data)-1} as your end_addr in SystemVerilog!")
    
    with open(coe_filename, "w") as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        
        for i, val in enumerate(scaled_data):
            hex_str = f"{val & 0xFFFFFF:06x}"
            
            if i == len(scaled_data) - 1:
                f.write(f"{hex_str};")
            else:
                f.write(f"{hex_str}, ")
                
    print("Done! Load this .coe file into your Vivado Block Memory Generator.")

# Run it
# wav_to_coe("snare.wav", "audio_rom.coe")
wav_to_coe("../samples/hip-hop-snare2.wav", "audio_rom.coe")