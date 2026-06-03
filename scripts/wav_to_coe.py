import numpy as np
from scipy.io import wavfile
import sys

def wav_to_coe(wav_filename, coe_filename):
    print(f"Reading {wav_filename}...")
    
    # Read the WAV file (pip install scipy numpy)
    sample_rate, data = wavfile.read(wav_filename)
    
    # If the audio is stereo, keep only the left channel
    if len(data.shape) > 1:
        data = data[:, 0]
        print("Converted stereo to mono.")
        
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
    with open(coe_filename, "w") as f:
        # The required Vivado Header
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        
        for i, val in enumerate(scaled_data):
            # Bitwise AND masks it to exactly 24 bits (handles negative Two's Complement cleanly)
            hex_str = f"{val & 0xFFFFFF:06x}"
            
            # The last value must end with a semicolon, everything else gets a comma
            if i == len(scaled_data) - 1:
                f.write(f"{hex_str};\n")
            else:
                f.write(f"{hex_str},\n")
                
    print("Done! Load this .coe file into your Vivado Block Memory Generator.")

# --- RUN SCRIPT ---
# Example: wav_to_coe("piano_C4.wav", "audio_rom.coe")
wav_to_coe("your_audio_file.wav", "audio_rom.coe")