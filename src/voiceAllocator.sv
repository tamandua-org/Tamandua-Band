import daw_pkg::*;

module voiceAllocator (
    input  logic        clk,
    input  logic        rst,
    
    // inputs from dawController
    input  logic        live_note_on,
    input  logic        live_note_off,
    input  note_delta_t live_pitch,
    input  instrument_t ui_active_instrument,
    
    // inputs from patternEngine (stored pattern values)
    input  logic        seq_note_on_valid,
    input  note_event_t seq_note_on_event,
    input  logic        seq_note_off_valid,
    input  note_event_t seq_note_off_event,
    
    // outputs to dspAudioEngine
    output logic        voice_active     [NUM_VOICES],
    output note_delta_t voice_pitch      [NUM_VOICES],
    output instrument_t voice_instrument [NUM_VOICES]
);

    // ========================================================
    // 1. Sequencer Collision Buffer
    // ========================================================
    logic        buf_seq_on_valid;
    note_event_t buf_seq_on_event;

    logic        buf_seq_off_valid;
    note_event_t buf_seq_off_event;

    always_ff @(posedge clk) begin
        if (rst) begin
            buf_seq_on_valid  <= 1'b0;
            buf_seq_off_valid <= 1'b0;
        end else begin
            // Buffer Note Ons
            if (seq_note_on_valid && live_note_on) begin
                buf_seq_on_valid <= 1'b1;
                buf_seq_on_event <= seq_note_on_event;
            end else if (!live_note_on && buf_seq_on_valid) begin
                buf_seq_on_valid <= 1'b0; 
            end

            // Buffer Note Offs
            if (seq_note_off_valid && live_note_off) begin
                buf_seq_off_valid <= 1'b1;
                buf_seq_off_event <= seq_note_off_event;
            end else if (!live_note_off && buf_seq_off_valid) begin
                buf_seq_off_valid <= 1'b0; 
            end
        end
    end

    // ========================================================
    // 2. Processing Routers
    // ========================================================
    logic        process_on_valid;
    note_delta_t process_on_pitch;
    instrument_t process_on_inst;

    logic        process_off_valid;
    note_delta_t process_off_pitch;
    instrument_t process_off_inst;

    always_comb begin
        if (live_note_on) begin
            process_on_valid = 1'b1;
            process_on_pitch = live_pitch;
            process_on_inst  = ui_active_instrument;
        end else if (buf_seq_on_valid) begin
            process_on_valid = 1'b1;
            process_on_pitch = buf_seq_on_event.note_delta;
            process_on_inst  = buf_seq_on_event.instrument_id;
        end else if (seq_note_on_valid) begin
            process_on_valid = 1'b1;
            process_on_pitch = seq_note_on_event.note_delta;
            process_on_inst  = seq_note_on_event.instrument_id;
        end else begin
            process_on_valid = 1'b0;
            process_on_pitch = '0;
            process_on_inst  = PIANO;
        end
    end

    always_comb begin
        if (live_note_off) begin
            process_off_valid = 1'b1;
            process_off_pitch = live_pitch;
            process_off_inst  = ui_active_instrument;
        end else if (buf_seq_off_valid) begin
            process_off_valid = 1'b1;
            process_off_pitch = buf_seq_off_event.note_delta;
            process_off_inst  = buf_seq_off_event.instrument_id;
        end else if (seq_note_off_valid) begin
            process_off_valid = 1'b1;
            process_off_pitch = seq_note_off_event.note_delta;
            process_off_inst  = seq_note_off_event.instrument_id;
        end else begin
            process_off_valid = 1'b0;
            process_off_pitch = '0;
            process_off_inst  = PIANO;
        end
    end

    // ========================================================
    // 3. The Voice Register File
    // ========================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < NUM_VOICES; i++) begin
                voice_active[i]     <= 1'b0;
                voice_pitch[i]      <= '0;
                voice_instrument[i] <= PIANO;
            end
        end else begin
            for (int i = 0; i < NUM_VOICES; i++) begin
                // Priority 1: Note Offs
                if (process_off_valid && voice_active[i] && 
                    voice_pitch[i] == process_off_pitch && 
                    voice_instrument[i] == process_off_inst) begin
                    
                    voice_active[i] <= 1'b0;
                end 
                
                // Priority 2: Note Ons
                else if (process_on_valid) begin
                    logic slot_assigned;
                    slot_assigned = 1'b0;
                    
                    for (int j = 0; j < NUM_VOICES; j++) begin
                        if (!voice_active[j] && !slot_assigned) begin
                            if (i == j) begin 
                                voice_active[i]     <= 1'b1;
                                voice_pitch[i]      <= process_on_pitch;
                                voice_instrument[i] <= process_on_inst;
                            end
                            slot_assigned = 1'b1;
                        end
                    end
                end
            end
        end
    end
endmodule