ROOT_NOTE = 60
FRACTION_BITS = 15
BASE_SPEED = 2 ** FRACTION_BITS # 32768

print("const logic [23:0] PITCH_STEP_LUT [0:127] = '{")

for pitch in range(128):
    # Calculate the frequency ratio relative to the root note
    # Formula: 2 ^ ((Pitch - Root) / 12)
    ratio = 2.0 ** ((pitch - ROOT_NOTE) / 12.0)
    
    # Convert to Q.15 fixed-point integer
    step_size = int(round(ratio * BASE_SPEED))
    
    # Format for SystemVerilog
    comma = "," if pitch < 127 else ""
    print(f"    24'd{step_size:<8}{comma} // MIDI {pitch}")

print("};")