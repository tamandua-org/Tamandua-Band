import daw_pkg::*;

module dawController (
    input  logic        clk,
    input  logic        rst,
    
    input  logic        keyRdy,
    input  logic [7:0]  key,       
    
    input logic semiquaver_tick,
    
    // --- Global DAW State Outputs ---
    output logic [NUM_PATTERNS-1:0]  mute_mask,
    output logic [PATTERN_ID_BITS-1:0] ui_active_pattern,
    output instrument_t              ui_active_instrument,
    output note_delta_t               ui_active_note_slot,
    output logic [3:0]               current_octave,
    output logic [7:0]               bpm_out,
    output logic                     is_playing,        // 1 = Sequencer running, 0 = Paused
    output logic step_forward_pulse,
    output logic step_backward_pulse,
    
    output instrument_t                instrument_regs [NUM_PATTERNS],
    
    // --- Mode Flags (For the Visualizer) ---
    output logic        mode_normal,
    output logic        mode_live,
    output logic        mode_record,
    
    // --- Action Pulses ---
    output logic        clear_pattern_pulse, // Tells the RAM to wipe the current pattern
    output logic live_valid,
    output note_event_t live_note
);

    localparam logic [7:0] NOTE_MAPPED_KEYS [0:12] = '{
        8'h1C, // 0: A (Do)
        8'h1D, // 1: W (Do#)
        8'h1B, // 2: S (Re)
        8'h24, // 3: E (Re#)
        8'h23, // 4: D (Mi)
        8'h2B, // 5: F (Fa)
        8'h2C, // 6: T (Fa#)
        8'h34, // 7: G (Sol)
        8'h35, // 8: Y (Sol#)
        8'h33, // 9: H (La)
        8'h3C, // 10: U (La#)
        8'h3B, // 11: J (Si)
        8'h42  // 12: K (Do - Octave up)
    };

    typedef enum logic [1:0] {
        PS2_IDLE,
        PS2_BREAK_WAIT    
    } ps2_state_t;

    ps2_state_t ps2_state;
    
    // Clean, 1-cycle pulses for the DAW logic
    logic key_pressed;
    logic key_released;
    logic [7:0] active_scancode;
    
    // Bit array to track which keys are currently physically held down.
    // This prevents Typematic Repeat from re-triggering synth notes.
    logic [255:0] key_is_down; 

    always_ff @(posedge clk) begin     // FSM PS/2 Decoder (teniendo en cuenta que se pueden pulsar multiples a la vez)
        if (rst) begin
            ps2_state <= PS2_IDLE;
            key_pressed <= '0;
            key_released <= '0;
            key_is_down <= '0;
            active_scancode <= '0;
        end else begin
            key_pressed <= '0;
            key_released <= '0;

            if (keyRdy) begin
                case (ps2_state)
                    PS2_IDLE: begin
                        if (key == 8'hF0) begin
                            ps2_state <= PS2_BREAK_WAIT; // Key release coming
                        end else begin
                            if (!key_is_down[key]) begin
                                key_pressed <= 1'b1;
                                active_scancode <= key;
                                key_is_down[key] <= 1'b1;
                            end
                        end
                    end
                    
                    PS2_BREAK_WAIT: begin //key released
                        key_released     <= 1'b1;
                        active_scancode  <= key;
                        key_is_down[key] <= 1'b0;
                        ps2_state        <= PS2_IDLE;
                    end
                endcase
            end
        end
    end

    typedef enum logic [1:0] {
        MODE_NORMAL, // Default, navigation, muting
        MODE_LIVE,   // live playing without recording new patterns
        MODE_RECORD_COUNTDOWN, // waiting for spacebar
        MODE_RECORD  // pattern creation
    } daw_mode_t;

    daw_mode_t current_mode;
    
    assign mode_normal = (current_mode == MODE_NORMAL);
    assign mode_live   = (current_mode == MODE_LIVE);
    assign mode_record = (current_mode == MODE_RECORD);
    
    assign ui_active_instrument = instrument_regs[ui_active_pattern];

    //note_delta_t ui_active_note_slot;
    logic [4:0] countdown_timer;
    logic       countdown_active;

    always_ff @(posedge clk) begin
        if (rst) begin
            current_mode         <= MODE_NORMAL;
            mute_mask            <= '0; 
            ui_active_pattern    <= '0;
            bpm_out              <= 8'd120;
            is_playing           <= 1'b0;
            step_forward_pulse   <= '0;
            step_backward_pulse   <= '0;
            clear_pattern_pulse  <= 1'b0;
            live_note      <= '0;
            live_valid       <= 1'b0;
            current_octave       <= 3'd4; 
            ui_active_note_slot  <= 7'd60; // start at Do4        
            countdown_active     <= 1'b0;
            countdown_timer      <= '0;
            for (int i = 0; i < NUM_PATTERNS; i++)
                instrument_regs[i] <= PIANO;

        end else begin
            // Reset 1-cycle pulses
            clear_pattern_pulse <= 1'b0;
            live_note      <= '0;
            live_valid       <= 1'b0;
            step_forward_pulse  <= 1'b0;
            step_backward_pulse <= 1'b0;

            // RECORDING COUNTDOWN TIMER LOGIC
            // This runs independently of user input
            if (countdown_active && semiquaver_tick) begin
                if (countdown_timer == 5'd0) begin
                    countdown_active <= 1'b0;
                    is_playing       <= 1'b1;            // Start sequencer playback
                    current_mode     <= MODE_RECORD;     // Push FSM into active recording state
                end else
                    countdown_timer <= countdown_timer - 1'b1;
            end
            
            if (key_pressed) begin // keyboard input

                // back to normal mode, pauses everything
                if (active_scancode == 8'h76) begin // ESC
                    current_mode <= MODE_NORMAL;
                    countdown_active <= 1'b0; // abort countdown if running
                end else begin
                    case (current_mode)
                        MODE_NORMAL: begin
                            case (active_scancode)
                                // mode switch
                                8'h2D: begin // R
                                    current_mode <= MODE_RECORD_COUNTDOWN; 
                                    is_playing   <= 1'b0; // Pause playback
                                end
                                8'h43: begin // I
                                    current_mode <= MODE_LIVE;   
                                    is_playing   <= 1'b1; 
                                end
                                
                                // playback 
                                8'h29: is_playing <= ~is_playing; // Space
                                
                                // pattern ops
                                8'h3A: mute_mask[ui_active_pattern] <= ~mute_mask[ui_active_pattern]; // M
                                8'h21: clear_pattern_pulse <= 1'b1; // C
                                
                                // pattern selection (keys 1, 2, 3... up to 0)
                                8'h16: ui_active_pattern <= 4'd0;
                                8'h1E: ui_active_pattern <= 4'd1;
                                8'h26: ui_active_pattern <= 4'd2;
                                8'h25: ui_active_pattern <= 4'd3;
                                8'h2E: ui_active_pattern <= 4'd4;
                                8'h36: ui_active_pattern <= 4'd5;
                                8'h3D: ui_active_pattern <= 4'd6;
                                8'h3E: ui_active_pattern <= 4'd7;
                                8'h46: ui_active_pattern <= 4'd8;
                                8'h45: ui_active_pattern <= 4'd9;

                                
                                // vim-like navigation
                                8'h33: if (!is_playing) step_backward_pulse <= 1'b1; // H (step back)
                                8'h4B: if (!is_playing) step_forward_pulse  <= 1'b1; // L (step forward)
                                8'h3B: if (ui_active_note_slot > 0) ui_active_note_slot <= ui_active_note_slot - 1; // J (Note Down)
                                8'h42: if (ui_active_note_slot < 127) ui_active_note_slot <= ui_active_note_slot + 1; // K (Note Up)

                                // instrument selection 
                                8'h0D: begin // tab
                                    if (ui_active_instrument == LAST_INSTRUMENT) 
                                        instrument_regs[ui_active_pattern] <= FIRST_INSTRUMENT;
                                    else 
                                        instrument_regs[ui_active_pattern] <= instrument_t'(ui_active_instrument + 1'b1);
                                end

                                // octave selection
                                8'h41: if (current_octave > 0) current_octave <= current_octave - 1'b1; // , (comma)
                                8'h49: if (current_octave < 8) current_octave <= current_octave + 1'b1; // . (dot)

                                // bpm modify
                                8'h1D: if (bpm_out < 255) bpm_out <= bpm_out + 1'b1; // W
                                8'h1B: if (bpm_out > 1)   bpm_out <= bpm_out - 1'b1; // S
                                
                            endcase
                        end

                        MODE_RECORD_COUNTDOWN: begin
                            case (active_scancode)
                                // Space starts the 4-beat countdown
                                8'h29: begin 
                                    if (!is_playing && !countdown_active) begin
                                        countdown_active <= 1'b1;
                                        countdown_timer  <= 5'd15; // 16 semiquavers - 1 = 15
                                    end
                                end

                                // allow configuration while waiting
                                8'h0D: begin // tab
                                    if (ui_active_instrument == LAST_INSTRUMENT) 
                                        instrument_regs[ui_active_pattern] <= FIRST_INSTRUMENT;
                                    else 
                                        instrument_regs[ui_active_pattern] <= instrument_t'(ui_active_instrument + 1'b1);
                                end
                                8'h41: if (current_octave > 0) current_octave <= current_octave - 1'b1; // ,
                                8'h49: if (current_octave < 8) current_octave <= current_octave + 1'b1; // .
                                
                                8'h33: if (!is_playing) step_backward_pulse <= 1'b1; // H (step back)
                                8'h4B: if (!is_playing) step_forward_pulse  <= 1'b1; // L (step forward)
                                
                            endcase
                        end
                        
                        MODE_RECORD, MODE_LIVE: begin
                            case (active_scancode)
                                8'h0D: begin // tab allowed only if live mode
                                    if (current_mode == MODE_LIVE) begin
                                        if (ui_active_instrument == LAST_INSTRUMENT) 
                                            instrument_regs[ui_active_pattern] <= FIRST_INSTRUMENT;
                                        else 
                                            instrument_regs[ui_active_pattern] <= instrument_t'(ui_active_instrument + 1'b1);
                                    end
                                end
                                8'h41: if (current_octave > 0) current_octave <= current_octave - 1'b1; // ,
                                8'h49: if (current_octave < 8) current_octave <= current_octave + 1'b1; // .

                                // A base pitch is calculated: (Octave * 12) + 12
                                default: begin
                                    for (int i = 0; i < 13; i++) begin
                                        if (active_scancode == NOTE_MAPPED_KEYS[i]) begin
                                            live_valid <= 1'b1;
                                            live_note.is_on_event <= 1'b1;
                                            live_note.note_delta <= (current_octave * 7'd12) + 7'd12 + 7'(i);
                                            live_note.instrument_id <= ui_active_instrument;
                                            //mark it as live event (this id is only used by the dsp audio engine to know when to cut live notes)
                                            live_note.pattern_id <= current_mode == MODE_LIVE ? '1 : ui_active_pattern;
                                        end
                                    end
                                end
                        endcase
                    end
                endcase
                end
           end else if (key_released) begin
                for (int i = 0; i < 13; i++) begin 
                    if (active_scancode == NOTE_MAPPED_KEYS[i]) begin
                        // maybe a bug when changing the octave mid note playing may start at Do5 and move to Do6 then release key, 
                        // and we will remove Do6 and Do5 will keep playing ? not sure because it depends on how we handle key presses.
                        live_valid <= 1'b1;
                        live_note.is_on_event <= 1'b0; //mark it as key release
                        live_note.note_delta <= (current_octave * 7'd12) + 7'd12 + 7'(i);
                        live_note.instrument_id <= ui_active_instrument;
                        live_note.pattern_id <= current_mode == MODE_LIVE ? '1 : ui_active_pattern;
                    end
                end
                
            end
        end
    end
endmodule