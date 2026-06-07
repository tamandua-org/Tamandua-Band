import daw_pkg::*;

module dspAudioEngine (
    input  logic clk,
    input  logic rst,
    
    input  logic tick_48khz, 
    
    input logic pause_pulse,
    input logic [2:0] master_gain_shift,
    
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
    
    function automatic logic [$clog2(NUM_VOICES)-1:0] find_first_active_bit(input logic [NUM_VOICES-1:0] mask);
        for (int i = 0; i < NUM_VOICES; i++) begin
            if (mask[i]) return i;
        end
        return '0;
    endfunction

    // FSM
    typedef enum logic [3:0] {
        IDLE,             // we need to pipeline the matching of note_event to an idx to avoid extremely high fanout
        READ_FIFO,        // Stage 1
        GENERATE_MASKS,   // Stage 2
        DECODE_SLOT,      // Stage 3
        ADD_EVENT,        // Stage 4
        EVAL_VOICE,
        WAIT_ROM,
        CALCULATE_ADSR,
        MULTIPLY_DSP,
        SUM_VOICE
    } state_t;
    
    state_t state;
    
//    logic [$clog2(NUM_VOICES):0] scan_idx;
    logic [$clog2(NUM_VOICES):0] scan_idx_state;
    logic [$clog2(NUM_VOICES):0] scan_idx_level;
    logic [$clog2(NUM_VOICES):0] scan_idx_phase;
    logic [$clog2(NUM_VOICES):0] scan_idx_info;
    
    logic signed [39:0]          mixer_sum;

    logic signed [39:0] dsp_mult_reg;
    logic [38:0]        next_phase_reg;
    
    note_event_t                   active_event;
    logic [NUM_VOICES-1:0]         empty_mask;
    logic [NUM_VOICES-1:0]         release_mask;
    logic [NUM_VOICES-1:0]         match_mask;
    
    logic [$clog2(NUM_VOICES)-1:0] target_slot;
    logic                          slot_found;
    
    // registers to pipeline access to arrays/reduce fanout
    instrument_meta_t active_meta_reg;
    logic [23:0] active_step_reg;
    logic [15:0] active_vol_reg;
    logic [38:0] active_phase_reg;
    env_state_t active_env_state_reg;
    logic signed [23:0] dsp_rom_reg; // input a 
    logic [15:0]        dsp_vol_reg; // input b

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            audio_out <= '0;
            audio_out_valid <= 1'b0;
            fifo_rd_en <= 1'b0;
            mixer_sum <= '0;
//            scan_idx        <= '0;
            scan_idx_state <= '0;
            scan_idx_level <= '0;
            scan_idx_phase <= '0;
            scan_idx_info <= '0;
            dsp_mult_reg <= '0;
            next_phase_reg <= '0;
            
            for (int i = 0; i < NUM_VOICES; i++) begin
                env_state[i] <= ENV_OFF;
            end   
                 
        end else begin
            audio_out_valid <= 1'b0; 
            fifo_rd_en      <= 1'b0;
            
            if (pause_pulse) begin // looper paused
                for (int i = 0; i < NUM_VOICES; i++) begin
                    env_state[i] <= ENV_OFF;
                end
                
                // reset TDM loop
                state <= IDLE;
                mixer_sum <= '0;
                scan_idx_state <= '0;
                scan_idx_level <= '0;
                scan_idx_phase <= '0;
                scan_idx_info <= '0;
                
            end else begin
            
                case (state)
                    IDLE: begin
                        if (tick_48khz) state <= READ_FIFO; 
                    end
                    
                    // take items from FIFO
                    READ_FIFO: begin
                        if (!fifo_empty) begin
                            active_event <= fifo_dout; // we store fifo value
                            state <= GENERATE_MASKS;
                            fifo_rd_en <= 1'b1; // we remove the item we just obtained (since we are with FWFT)
                        end else begin
    //                        scan_idx <= '0;
                            scan_idx_state <= '0;
                            scan_idx_level <= '0;
                            scan_idx_phase <= '0;
                            scan_idx_info  <= '0;
                            mixer_sum <= '0; 
                            state <= EVAL_VOICE;
                        end
                    end
                    
                    GENERATE_MASKS: begin
                        // simple comparisons in parallel
                        for(int i = 0; i < NUM_VOICES; i++) begin
                            empty_mask[i] <= (env_state[i] == ENV_OFF);
                            release_mask[i] <= (env_state[i] == ENV_RELEASE);
                            match_mask[i] <= (env_state[i] != ENV_OFF) && (env_state[i] != ENV_RELEASE) &&
                                               (voice_info[i].pitch == active_event.note_delta) &&
                                               (voice_info[i].inst == active_event.instrument_id) &&
                                               (voice_info[i].pattern_id == active_event.pattern_id);
                        end
                        state <= DECODE_SLOT;
                    end
                    
                    DECODE_SLOT: begin
                        slot_found  <= 1'b0; // Default
                        
                        if (active_event.is_on_event) begin
                            if (empty_mask != '0) begin
                                target_slot <= find_first_active_bit(empty_mask);
                                slot_found  <= 1'b1;
                            end else if (release_mask != '0) begin
                                target_slot <= find_first_active_bit(release_mask);
                                slot_found  <= 1'b1;
                            end
                        end else begin
                            if (match_mask != '0) begin
                                target_slot <= find_first_active_bit(match_mask);
                                slot_found  <= 1'b1;
                            end
                        end
                        state <= ADD_EVENT;
                    end
                    
                    ADD_EVENT: begin
                        if (slot_found) begin
                            automatic instrument_meta_t inst_meta = get_instrument_meta(active_event.instrument_id);
                            
                            if (active_event.is_on_event) begin
                                voice_info[target_slot].pitch <= active_event.note_delta;
                                voice_info[target_slot].inst <= active_event.instrument_id;
                                voice_info[target_slot].pattern_id <= active_event.pattern_id;
                                env_state[target_slot] <= ENV_ATTACK;
                                env_level[target_slot] <= '0;
                                phase_acc[target_slot] <= {inst_meta.start_addr, 15'd0};
                            end else if (inst_meta.mode != NATURAL) begin // non natural (one shots) ending will only go into release with note off
                                env_state[target_slot] <= ENV_RELEASE;
                            end
                        end
                        
                        state <= READ_FIFO; // read next
                    end
    
                    // tdm math
                    EVAL_VOICE: begin
                        if (scan_idx_state == NUM_VOICES) begin // Master Mixing and Normalization
                            logic signed [47:0] normalized;
                            automatic logic signed [47:0] max_pos = 48'sd8388607;
                            automatic logic signed [47:0] min_neg = -48'sd8388608;

                            // Apply master boost after all voices are mixed. (0 = x1, 1 = x2) we need to account for dB that work with log
                            normalized = ({{8{mixer_sum[39]}}, mixer_sum}) <<< master_gain_shift;
                            
                            if (normalized > max_pos) 
                                audio_out <= 24'h7FFFFF; 
                            else if (normalized < min_neg) 
                                audio_out <= 24'h800000; 
                            else 
                                audio_out <= normalized[23:0];
                            
                            audio_out_valid <= 1'b1;
                            state <= IDLE;
                        end else if (env_state[scan_idx_state] != ENV_OFF) begin 
                            rom_addr <= phase_acc[scan_idx_phase][38:15]; // 24 bits from Q24.15
                            state    <= WAIT_ROM;
                        end else begin
                            scan_idx_state <= scan_idx_state + 1'b1;
                            scan_idx_level <= scan_idx_level + 1'b1;
                            scan_idx_phase <= scan_idx_phase + 1'b1;
                            scan_idx_info  <= scan_idx_info + 1'b1;
                        end
                    end
    
                    WAIT_ROM: begin
                        active_meta_reg <= get_instrument_meta(voice_info[scan_idx_info].inst);
                        active_step_reg <= midi_to_pitch_step(voice_info[scan_idx_info].pitch);
                        active_vol_reg  <= env_level[scan_idx_level];
                        active_phase_reg <= phase_acc[scan_idx_phase];
                        active_env_state_reg <= env_state[scan_idx_state];
                        
                        state <= CALCULATE_ADSR;
                    end
    
                    CALCULATE_ADSR: begin
                        automatic logic [15:0] temp_vol = active_vol_reg;
    
                        // ADSR Math
                        case (active_env_state_reg) // env_state[scan_idx_state]
                            ENV_ATTACK: begin
                                if (temp_vol >= 16'd65535 - active_meta_reg.attack_rate) begin
                                    temp_vol = 16'd65535;
                                    active_env_state_reg <= ENV_DECAY;
                                end else begin
                                    temp_vol = temp_vol + active_meta_reg.attack_rate;
                                end
                            end
                            
                            ENV_DECAY: begin
                                automatic logic [15:0] exp_drop = (temp_vol >>> 10) + active_meta_reg.decay_rate;
    
                                if (temp_vol <= active_meta_reg.sustain_level + exp_drop) begin
                                    temp_vol = active_meta_reg.sustain_level;
                                    active_env_state_reg <= ENV_SUSTAIN;
                                end else begin
                                    temp_vol = temp_vol - exp_drop;
                                end
                            end
                            
                            ENV_SUSTAIN: begin end
                            
                            ENV_RELEASE: begin
                                automatic logic [15:0] exp_drop = (temp_vol >>> 10) + active_meta_reg.release_rate;
    
                                if (temp_vol <= exp_drop) begin
                                    temp_vol = '0;
                                    active_env_state_reg <= ENV_OFF;
                                end else begin
                                    temp_vol = temp_vol - exp_drop;
                                end  
                            end
                        endcase
                        
                        dsp_rom_reg <= rom_rdata;
                        dsp_vol_reg <= temp_vol;
         
                        // Pre-calculate the next phase position
                        next_phase_reg <= active_phase_reg + active_step_reg; // the sum will affect the fractional bits
    
                        state <= MULTIPLY_DSP;
                    end
                    
                    MULTIPLY_DSP: begin
    
                        dsp_mult_reg <= 40'($signed(dsp_rom_reg)) * $signed({1'b0, dsp_vol_reg});
    
                        env_level[scan_idx_level] <= dsp_vol_reg; // to reduce fanout we update it here even though we could've done it earlier
                        env_state[scan_idx_state] <= active_env_state_reg;
                        state <= SUM_VOICE;
                    end
    
                    SUM_VOICE: begin
                        mixer_sum <= mixer_sum + ((dsp_mult_reg + 40'sh8000) >>> 16); // shiftr data from previous stage
    
                        if (next_phase_reg[38:15] >= active_meta_reg.end_addr) begin
                            if (active_meta_reg.mode == NATURAL) 
                                env_state[scan_idx_state] <= ENV_OFF; 
                            else
                                phase_acc[scan_idx_phase] <= {active_meta_reg.loop_start, 15'd0}; 
                                
                        end else begin
                            phase_acc[scan_idx_phase] <= next_phase_reg; 
                        end
    
                        scan_idx_state <= scan_idx_state + 1'b1;
                        scan_idx_level <= scan_idx_level + 1'b1;
                        scan_idx_phase <= scan_idx_phase + 1'b1;
                        scan_idx_info  <= scan_idx_info + 1'b1;
                        state <= EVAL_VOICE;
                    end
                endcase
            end
        end
    end
endmodule