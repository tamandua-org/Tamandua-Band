import daw_pkg::*;

module dspAudioEngine (
    input  logic clk,
    input  logic rst,
    
    input  logic audio_48k_tick, // Pulses 1 cycle high at 48kHz
    
    // --- Inputs from Voice Allocator ---
    input  logic        voice_active     [NUM_VOICES],
    input  note_delta_t voice_pitch      [NUM_VOICES],
    input  instrument_t voice_instrument [NUM_VOICES],
    
    // --- Pitch to Frequency Array ---
    // Connect your pitch_to_freq module's outputs to this array.
    // Index it by MIDI pitch (0-127) to get the step size.
    input  logic [23:0] pitch_step_array [128], 
    
    // --- Audio ROM Interface (2-Cycle Latency) ---
    output logic [23:0]        rom_addr,
    input  logic signed [23:0] rom_rdata, // 24-bit Audio Data
    
    // --- Output to I2S/DAC ---
    output logic signed [23:0] final_audio_out,
    output logic               audio_out_valid
);

    // ========================================================
    // 1. Minimal Instrument Boundaries Lookup
    // ========================================================
    typedef struct packed {
        logic [23:0] start_addr;
        logic [23:0] end_addr;
        logic [23:0] loop_start;
    } inst_bounds_t;

    // Hardcode your audio ROM addresses here for each instrument
    function automatic inst_bounds_t get_inst_bounds(instrument_t inst);
        case (inst)
            //                        START       END         LOOP START (for Gated)
            KICK:    return '{24'd0,      24'd10000,  24'd0};
            SNARE:   return '{24'd10000,  24'd25000,  24'd0};
            PIANO:   return '{24'd25000,  24'd80000,  24'd0};     // Gated (no loop, just cuts on release)
            SYNTH:   return '{24'd80000,  24'd82000,  24'd80500}; // Gated (Loops back to 80500)
            default: return '{24'd0,      24'd1000,   24'd0};
        endcase
    endfunction

    // ========================================================
    // 2. Voice State Memory
    // ========================================================
    // Because we use TDM, the state variables for all 66 voices must 
    // be stored in internal arrays.
    logic [23:0] voice_phase [NUM_VOICES];
    logic        voice_is_playing [NUM_VOICES];

    // ========================================================
    // 3. TDM Scanner FSM
    // ========================================================
    typedef enum logic [2:0] {
        IDLE,
        EVAL_VOICE,
        WAIT_ROM_1,
        WAIT_ROM_2,
        ACCUMULATE
    } state_t;
    
    state_t state;

    logic [$clog2(NUM_VOICES):0] scan_idx; // Can count up to 66
    logic signed [31:0]          mixer_sum; 
    
    inst_bounds_t bounds;
    logic [23:0]  step_size;

    always_ff @(posedge clk) begin
        if (rst) begin
            state           <= IDLE;
            final_audio_out <= '0;
            audio_out_valid <= 1'b0;
            scan_idx        <= '0;
            mixer_sum       <= '0;
            for (int i = 0; i < NUM_VOICES; i++) begin
                voice_phase[i]      <= '0;
                voice_is_playing[i] <= 1'b0;
            end
        end else begin
            audio_out_valid <= 1'b0; // Default clear

            case (state)
                // ----------------------------------------------------
                IDLE: begin
                    if (audio_48k_tick) begin
                        scan_idx  <= '0;
                        mixer_sum <= '0; // Reset mixer for the new 48kHz frame
                        state     <= EVAL_VOICE;
                    end
                end

                // ----------------------------------------------------
                EVAL_VOICE: begin
                    if (scan_idx == NUM_VOICES) begin
                        // We have mixed all 66 voices. Output to DAC!
                        // Apply Saturation (Clamp to 24-bit signed max/min values)
                        if (mixer_sum > 32'sd8388607)       final_audio_out <= 24'sd8388607;
                        else if (mixer_sum < -32'sd8388608) final_audio_out <= -24'sd8388608;
                        else                                final_audio_out <= mixer_sum[23:0];
                        
                        audio_out_valid <= 1'b1;
                        state           <= IDLE;
                    end else begin
                        bounds    = get_inst_bounds(voice_instrument[scan_idx]);
                        step_size = pitch_step_array[voice_pitch[scan_idx]];

                        // Detect Note On (Voice became active)
                        if (voice_active[scan_idx] && !voice_is_playing[scan_idx]) begin
                            voice_phase[scan_idx]      <= bounds.start_addr;
                            voice_is_playing[scan_idx] <= 1'b1;
                        end 
                        
                        // Detect Note Off (Gated release)
                        else if (!voice_active[scan_idx] && get_end_mode(voice_instrument[scan_idx]) == GATED) begin
                            voice_is_playing[scan_idx] <= 1'b0;
                        end

                        // If it is playing, ask the ROM for the audio sample
                        // NOTE: If voice_is_playing just turned high this cycle, we use start_addr
                        if (voice_is_playing[scan_idx] || (voice_active[scan_idx] && !voice_is_playing[scan_idx])) begin
                            rom_addr <= (voice_active[scan_idx] && !voice_is_playing[scan_idx]) ? bounds.start_addr : voice_phase[scan_idx];
                            state    <= WAIT_ROM_1;
                        end else begin
                            scan_idx <= scan_idx + 1'b1; // Empty slot, skip it!
                        end
                    end
                end

                // ----------------------------------------------------
                // Wait for BRAM / Audio ROM Read (2 Cycles)
                WAIT_ROM_1: state <= WAIT_ROM_2;
                WAIT_ROM_2: state <= ACCUMULATE;

                // ----------------------------------------------------
                ACCUMULATE: begin
                    // 1. Add sample to the Master Mix
                    mixer_sum <= mixer_sum + rom_rdata;

                    // 2. Advance the phase
                    begin
                        logic [23:0] next_phase;
                        next_phase = voice_phase[scan_idx] + step_size;
    
                        // 3. Handle End / Looping
                        if (next_phase >= bounds.end_addr) begin
                            if (get_end_mode(voice_instrument[scan_idx]) == NATURAL) begin
                                voice_is_playing[scan_idx] <= 1'b0; // Hit stopped natively
                            end else begin
                                voice_phase[scan_idx] <= bounds.loop_start; // Synth loops!
                            end
                        end else begin
                            voice_phase[scan_idx] <= next_phase; // Continue normally
                        end
                    end

                    scan_idx <= scan_idx + 1'b1;
                    state    <= EVAL_VOICE;
                end
            endcase
        end
    end
endmodule