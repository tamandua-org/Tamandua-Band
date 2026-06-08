import serial
import wave
import sys
import argparse

# --- Configuration ---
COM_PORT = 'COM3'         # Update this to your FPGA's COM port
BAUD_RATE = 921600       
SAMPLE_RATE = 48000
BPM = 120                 
TOTAL_STEPS = 64          

# Calculate bytes
SEMIQUAVERS_PER_SEC = (BPM / 60.0) * 4.0
SECONDS_OF_AUDIO = TOTAL_STEPS / SEMIQUAVERS_PER_SEC
TOTAL_BYTES = int(SECONDS_OF_AUDIO * SAMPLE_RATE) * 2 

def capture_audio(output_filename):
    # Safeguard: Ensure the file ends with .wav
    if not output_filename.lower().endswith('.wav'):
        output_filename += '.wav'

    print(f"Opening {COM_PORT} at {BAUD_RATE} baud...")
    try:
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=15)
    except Exception as e:
        print(f"Failed to open port: {e}")
        sys.exit(1)

    print(f"\nREADY! Press your Export key on the FPGA keyboard now.")
    print(f"Waiting to receive {TOTAL_BYTES} bytes ({SECONDS_OF_AUDIO:.2f} seconds of audio)...")
    
    raw_bytes = ser.read(TOTAL_BYTES)
    ser.close()

    if len(raw_bytes) != TOTAL_BYTES:
        print(f"\nERROR: Received {len(raw_bytes)} / {TOTAL_BYTES} bytes.")
        
    print(f"\nFormatting and saving to {output_filename}...")

    # Write the Little-Endian byte stream directly to the file
    with wave.open(output_filename, 'wb') as wav_file:
        wav_file.setnchannels(1)      
        wav_file.setsampwidth(2)      
        wav_file.setframerate(SAMPLE_RATE)
        wav_file.writeframes(raw_bytes)

    print("Success! Audio export complete.")

if __name__ == "__main__":
    # Setup the argument parser
    parser = argparse.ArgumentParser(description="Capture raw RS232 audio from FPGA DAW and save as WAV.")
    
    # Add an optional positional argument for the filename
    parser.add_argument(
        "filename", 
        nargs="?", 
        default="FPGA_Export.wav", 
        help="The name of the output WAV file (e.g., my_beat.wav)"
    )
    
    args = parser.parse_args()
    
    # Run the capture function with the provided filename
    capture_audio(args.filename)