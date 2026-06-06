import numpy as np
from scipy import signal

def generate_master_rom(filename="master_rom.coe", sample_rate=48000):
    print("Compiling Master ROM...")

    # ---------------------------------------------------------
    # 1. SYNTH (Perfect Sawtooth, 184 samples = ~260.8 Hz / Middle C)
    # ---------------------------------------------------------
    synth_len = 184
    # A saw wave just goes linearly from -1.0 to 1.0
    synth_audio = np.linspace(-1.0, 1.0, synth_len, endpoint=False)

    # ---------------------------------------------------------
    # 2. BRASS (Darker Sawtooth / Triangle hybrid, 184 samples)
    # ---------------------------------------------------------
    brass_len = 184
    # A smoother wave with fewer harsh harmonics
    t_brass = np.linspace(0, 1, brass_len, endpoint=False)
    brass_audio = 1.0 - 2.0 * np.abs(np.cos(np.pi * t_brass)) 

    # ---------------------------------------------------------
    # 3. SNARE (Analog 808-style, 12000 samples = 0.25 seconds)
    # ---------------------------------------------------------

'''
    snare_len = 12000
    t_snare = np.linspace(0, 0.25, snare_len, endpoint=False)
    
    # Body (Pitch sweep)
    freqs = 150 + (100 * np.exp(-t_snare * 40))
    phase = np.cumsum(freqs) / sample_rate * 2 * np.pi
    body = np.sin(phase) * np.exp(-t_snare * 35)
    
    # Snappy (Noise)
    noise = np.random.uniform(-1.0, 1.0, snare_len) * np.exp(-t_snare * 15)
    
    # Mix and normalize snare
    snare_audio = ((body * 0.9) + (noise * 0.1) * 0.9)
    snare_audio /= np.max(np.abs(snare_audio))
'''
    snare_len = 12000
    t_snare = np.linspace(0, 0.25, snare_len, endpoint=False)
    
    # Body (The Crack: Sweeps from 350Hz to 180Hz very fast)
    freqs = 180 + (170 * np.exp(-t_snare * 80))
    phase = np.cumsum(freqs) / sample_rate * 2 * np.pi
    body = np.sin(phase) * np.exp(-t_snare * 45) # Fast body decay
    
    # Snappy (The Wires: High-Pass Filtered Noise)
    raw_noise = np.random.uniform(-1.0, 1.0, snare_len)
    
    # Create a 2000 Hz High-Pass Filter to remove muddy bass from the noise
    sos = signal.butter(4, 2000, 'hp', fs=sample_rate, output='sos')
    filtered_noise = signal.sosfilt(sos, raw_noise)
    
    # Faster decay so it doesn't sound like lingering static
    snappy = filtered_noise * np.exp(-t_snare * 28)
    
    # Mix (60% Body, 40% Snappy)
    snare_audio = (body * 0.6) + (snappy * 0.4)
    snare_audio /= np.max(np.abs(snare_audio)) # Normalize

    # ---------------------------------------------------------
    # STITCH TOGETHER (The Memory Map)
    # ---------------------------------------------------------
    master_audio = np.concatenate([synth_audio, brass_audio, snare_audio])
    
    # Calculate Addresses
    synth_start = 0
    synth_end   = synth_start + synth_len - 1
    
    brass_start = synth_end + 1
    brass_end   = brass_start + brass_len - 1
    
    snare_start = brass_end + 1
    snare_end   = snare_start + snare_len - 1

    print("\n--- COPY THESE INTO daw_pkg.sv ---")
    print(f"SYNTH: return '{{24'd{synth_start}, 24'd{synth_end}, 24'd{synth_start}, GATED,   16'd35,  16'd50, 16'd40000, 16'd40}};")
    print(f"BRASS: return '{{24'd{brass_start}, 24'd{brass_end}, 24'd{brass_start}, GATED,   16'd13,  16'd2,  16'd45874, 16'd3}};")
    print(f"SNARE: return '{{24'd{snare_start}, 24'd{snare_end}, 24'd0, NATURAL, 16'd65000, 16'd0, 16'd65535, 16'd65000}};")
    print("----------------------------------\n")

    # ---------------------------------------------------------
    # EXPORT TO 24-BIT COE
    # ---------------------------------------------------------
    max_24bit = (2**23) - 1
    scaled_data = np.int32(master_audio * max_24bit)

    with open(filename, "w") as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        
        for i, val in enumerate(scaled_data):
            hex_str = f"{val & 0xFFFFFF:06x}"
            if i == len(scaled_data) - 1:
                f.write(f"{hex_str};\n")
            else:
                f.write(f"{hex_str},\n")
                
    print(f"Done! Master ROM size: {len(scaled_data)} words. Make sure your BRAM Depth is at least 16384.")

# Run it!
generate_master_rom()