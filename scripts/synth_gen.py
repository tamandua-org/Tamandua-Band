import math

# --- Synthesizer Parameters ---
WAVETABLE_SIZE = 2048
BIT_DEPTH = 24
MAX_AMP = (2 ** (BIT_DEPTH - 1)) - 1 # 8,388,607
MIN_AMP = -(2 ** (BIT_DEPTH - 1))    # -8,388,608

def generate_smooth_rage():
    waveform = []
    
    # We lowered the drive slightly to keep the pitch thick and stable
    DRIVE = 2.8  
    
    for i in range(WAVETABLE_SIZE):
        phase = i / WAVETABLE_SIZE
        
        # 1. The Smooth Core
        # Instead of sharp saws, we use a fundamental Sine wave for the "body"
        fundamental = math.sin(2 * math.pi * phase)
        
        # We add a 2nd harmonic Sine wave (an octave up) for brightness
        harmonic = 0.5 * math.sin(2 * math.pi * phase * 2.0)
        
        core = fundamental + harmonic
        
        # 2. The Saturation
        # Because the core is smooth, the tanh() function acts like a warm analog tube
        # rather than a digital drill. It squares it off nicely.
        distorted = math.tanh(core * DRIVE)
        
        # Scale to 24-bit signed integer
        sample = int(distorted * MAX_AMP)
        
        # Hard clip to prevent overflow
        sample = max(min(sample, MAX_AMP), MIN_AMP)
        waveform.append(sample)
        
    return waveform

def write_coe_file(waveform, filename):
    with open(filename, 'w') as f:
        f.write("; Custom 24-bit FEIN Rage Lead (Anti-Aliased)\n")
        f.write("memory_initialization_radix=10;\n")
        f.write("memory_initialization_vector=\n")
        
        for i, sample in enumerate(waveform):
            if i == len(waveform) - 1:
                f.write(f"{sample};\n") 
            else:
                f.write(f"{sample},\n") 
                
    print(f"Success! Wrote {len(waveform)} samples to {filename}")

if __name__ == "__main__":
    wave = generate_smooth_rage()
    write_coe_file(wave, "fein_v2.coe")