import daw_pkg::*;

module dspAudioEngine (
    input  logic clk,
    input  logic rst,
    
    input  logic tick_48khz, 
    
    // fifo ins
    input  logic        fifo_empty,
    input  note_event_t fifo_dout,
    output logic        fifo_rd_en,
    
    // access to rom
    output logic [23:0]        rom_addr,
    input  logic signed [23:0] rom_rdata, 
    
    // output sample
    output logic signed [23:0] audio_out,
    output logic               audio_out_valid
);

    typedef struct packed {
        note_delta_t                pitch;
        instrument_t                inst;
        logic [PATTERN_ID_BITS-1:0] pattern_id;
    } voice_info_t;

    // voice registers
    env_state_t env_state [NUM_VOICES];
    logic [15:0] env_level [NUM_VOICES];
    logic [38:0] phase_acc [NUM_VOICES]; // Q24.15 {rom_addr, fractional_steps}
    
    voice_info_t voice_info [NUM_VOICES];
    
    // Logic for adding/removing notes
    logic [$clog2(NUM_VOICES)-1:0] input_slot;
    logic [$clog2(NUM_VOICES)-1:0] release_slot;
    logic input_slot_found, release_slot_found;

    always_comb begin //este always_comb y el siguiente podrian combinarse si tuviesemos problemas de luts
        input_slot = '0;
        input_slot_found  = 1'b0;
        
        // find a truly empty slot
        for (int i = 0; i < NUM_VOICES; i++) begin
            if (env_state[i] == ENV_OFF && !input_slot_found) begin
                input_slot = i;
                input_slot_found  = 1'b1;
            end
        end
        // if not possible, steal a slot that is already fading out
        if (!input_slot_found) begin
            for (int i = 0; i < NUM_VOICES; i++) begin
                if (env_state[i] == ENV_RELEASE && !input_slot_found) begin
                    input_slot = i;
                    input_slot_found  = 1'b1;
                end
            end
        end
    end

    always_comb begin
        release_slot  = '0;
        release_slot_found = 1'b0;
        
        // Find the exact note that needs to be turned off
        for (int i = 0; i < NUM_VOICES; i++) begin
            if (env_state[i] != ENV_OFF && 
                voice_info[i].pitch      == fifo_dout.note_delta && 
                voice_info[i].inst       == fifo_dout.instrument_id &&
                voice_info[i].pattern_id == fifo_dout.pattern_id && !release_slot_found) begin
                
                release_slot  = i;
                release_slot_found = 1'b1;
            end
        end
    end

    // FSM
    typedef enum logic [3:0] {
        IDLE,
        DRAIN_FIFO,
        WAIT_FIFO_FWFT,
        EVAL_VOICE,
        WAIT_ROM,
        CALCULATE_ADSR,
        MULTIPLY_AND_MIX
    } state_t;
    
    state_t state;
    
    logic [$clog2(NUM_VOICES):0] scan_idx;
    logic signed [39:0]          mixer_sum;

    logic signed [39:0] dsp_mult_reg;
    logic [38:0]        next_phase_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            state           <= IDLE;
            audio_out <= '0;
            audio_out_valid <= 1'b0;
            fifo_rd_en      <= 1'b0;
            mixer_sum <= '0;
            scan_idx        <= '0;
            dsp_mult_reg    <= '0;
            next_phase_reg  <= '0;
            for (int i = 0; i < NUM_VOICES; i++) begin
                env_state[i] <= ENV_OFF;
                env_level[i] <= '0;
                phase_acc[i] <= '0;
                voice_info[i] <= '0;
            end
        end else begin
            audio_out_valid <= 1'b0; 
            fifo_rd_en      <= 1'b0;

            case (state)
                IDLE: begin
                    if (tick_48khz) state <= DRAIN_FIFO;
                end
                
                // take items from FIFO
                DRAIN_FIFO: begin
                    if (!fifo_empty) begin
                        if (fifo_dout.is_on_event) begin // Initialize new note
                            voice_info[input_slot].pitch      <= fifo_dout.note_delta;
                            voice_info[input_slot].inst       <= fifo_dout.instrument_id;
                            voice_info[input_slot].pattern_id <= fifo_dout.pattern_id;
                            env_state[input_slot]     <= ENV_ATTACK;
                            env_level[input_slot]     <= '0;
                            phase_acc[input_slot]     <= {get_instrument_meta(fifo_dout.instrument_id).start_addr, 15'd0}; //we init 
                            
                        end else if (release_slot_found) // off event -> send note to Release phase
                                env_state[release_slot] <= ENV_RELEASE;
                        
                        fifo_rd_en <= 1'b1;
                        state <= DRAIN_FIFO;
                        
                    end else begin // nothing new to process
                        // we might be in the middle of sending frames through patternEngine, 
                        // however if we miss some it won't matter since they will be kept in the FIFO for the tick
                        // meaning we will not lose notes, but they might be delayed a tick (which is only about 20 microseconds)
                        // since the FIFO is size 64, we will be able to hold all event even in the worst case (we process 1 store 60)
                        // 60 = 59 from pattternEngine + 1 from live_note (since ps2 is very slow)
                        
                        scan_idx <= '0;
                        mixer_sum <= '0; 
                        state <= EVAL_VOICE;
                    end
                end

                WAIT_FIFO_FWFT: begin // i dont think its needed//////////////////// verify 
                    state <= DRAIN_FIFO;
                end

                // tdm math
                EVAL_VOICE: begin
                    if (scan_idx == NUM_VOICES) begin // Master Mixing and Normalization
                        logic signed [39:0] normalized;
                        normalized = mixer_sum >>> 4; // Divide by 16 for headroom
                        
                        if (normalized > 40'd8388607) 
                            audio_out <= 24'd8388607; //max pos int 24
                        else if (normalized < -40'd8388608) 
                            audio_out <= -24'd8388608; //max neg int 24
                        else 
                            audio_out <= normalized[23:0];
                        
                        audio_out_valid <= 1'b1;
                        state <= IDLE;
                    end else if (env_state[scan_idx] != ENV_OFF) begin 
                        rom_addr <= phase_acc[scan_idx][38:15]; // 24 bits from Q24.15
                        state    <= WAIT_ROM;
                    end else begin
                        scan_idx <= scan_idx + 1'b1;
                    end
                end

                WAIT_ROM: state <= CALCULATE_ADSR;

                CALCULATE_ADSR: begin
                    automatic instrument_meta_t meta = get_instrument_meta(voice_info[scan_idx].inst);
                    automatic logic [23:0] step_size = midi_to_pitch_step(voice_info[scan_idx].pitch);
                    automatic logic [15:0] temp_vol  = env_level[scan_idx];

                    // ADSR Math
                    case (env_state[scan_idx])
                        ENV_ATTACK: begin
                            if (temp_vol >= 16'd65535 - meta.attack_rate) begin
                                temp_vol = 16'd65535;
                                env_state[scan_idx] <= ENV_DECAY;
                            end else begin
                                temp_vol = temp_vol + meta.attack_rate;
                            end
                        end
                        
                        ENV_DECAY: begin
                            if (temp_vol <= meta.sustain_level + meta.decay_rate) begin
                                temp_vol = meta.sustain_level;
                                env_state[scan_idx] <= ENV_SUSTAIN;
                            end else begin
                                temp_vol = temp_vol - meta.decay_rate;
                            end
                        end
                        
                        ENV_SUSTAIN: begin end
                        
                        ENV_RELEASE: begin
                            if (temp_vol <= meta.release_rate) begin
                                temp_vol = '0;
                                env_state[scan_idx] <= ENV_OFF;
                            end else begin
                                temp_vol = temp_vol - meta.release_rate;
                            end
                        end
                    endcase
                    
                    env_level[scan_idx] <= temp_vol;
                    
                    // Start pipelining for the final values from this voice entry
                    dsp_mult_reg <= rom_rdata * $signed({1'b0, temp_vol}); // we obtain the voice at the proper volume (we need to shiftr after)
                    
                    // Pre-calculate the next phase position
                    next_phase_reg <= phase_acc[scan_idx] + step_size; // the sum will affect the fractional bits

                    state <= MULTIPLY_AND_MIX;
                end

                MULTIPLY_AND_MIX: begin
                    automatic instrument_meta_t meta = get_instrument_meta(voice_info[scan_idx].inst);

                    mixer_sum <= mixer_sum + (dsp_mult_reg >>> 16); // shiftr data from previous stage

                    if (next_phase_reg[38:15] >= meta.end_addr) begin
                        if (meta.mode == NATURAL) 
                            env_state[scan_idx] <= ENV_OFF; 
                        else
                            phase_acc[scan_idx] <= {meta.loop_start, 15'd0}; 
                            
                    end else begin
                        phase_acc[scan_idx] <= next_phase_reg; 
                    end

                    scan_idx <= scan_idx + 1'b1;
                    state    <= EVAL_VOICE;
                end
            endcase
        end
    end
endmodule