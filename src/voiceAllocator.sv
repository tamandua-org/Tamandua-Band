import daw_pkg::*;

module voiceAllocator #(
    parameter int NUM_VOICES = 16
)(
    input  logic        clk,
    input  logic        rst,
    
    // --- Live Inputs (Direct from dawController) ---
    input  logic        live_note_on,
    input  logic        live_note_off,
    input  note_delta_t live_pitch,
    input  instrument_t ui_active_instrument,
    
    // --- Sequencer Inputs (From patternEngine) ---
    input  logic        seq_note_on_valid,
    input  note_event_t seq_note_on_event,
    input  logic        seq_note_off_valid,
    input  note_event_t seq_note_off_event,
    
    // --- Outputs (To TDM Audio Engine) ---
    output logic        voice_active     [NUM_VOICES],
    output note_delta_t voice_pitch      [NUM_VOICES],
    output instrument_t voice_instrument [NUM_VOICES]
);

    // ========================================================
    // 1. Sequencer Collision Buffer
    // ========================================================
    // If a live note arrives at the exact same cycle as a sequence note, 
    // we process the live one immediately and push the sequence note here.
    logic        buf_seq_on_valid;
    note_event_t buf_seq_on_event;

    always_ff @(posedge clk) begin
        if (rst) begin
            buf_seq_on_valid <= 1'b0;
        end else begin
            if (seq_note_on_valid && live_note_on) begin
                buf_seq_on_valid <= 1'b1;
                buf_seq_on_event <= seq_note_on_event;
            end else if (!live_note_on && buf_seq_on_valid) begin
                buf_seq_on_valid <= 1'b0; // Buffered note consumed
            end
        end
    end

    // Process router for Note Ons
    logic        process_on_valid;
    note_delta_t process_on_pitch;
    instrument_t process_on_inst;

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

    // ========================================================
    // 2. The Voice Register File
    // ========================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < NUM_VOICES; i++) begin
                voice_active[i]     <= 1'b0;
                voice_pitch[i]      <= '0;
                voice_instrument[i] <= PIANO;
            end
        end else begin
            
            // --- Highest Priority: Note Offs ---
            // (We scan the array to kill the matching voice)
            for (int i = 0; i < NUM_VOICES; i++) begin
                if (voice_active[i]) begin
                    
                    // Did the user release a live key?
                    if (live_note_off && voice_pitch[i] == live_pitch && voice_instrument[i] == ui_active_instrument) begin
                        voice_active[i] <= 1'b0;
                    end 
                    
                    // Did the sequencer release a note?
                    if (seq_note_off_valid && voice_pitch[i] == seq_note_off_event.note_delta && voice_instrument[i] == seq_note_off_event.instrument_id) begin
                        voice_active[i] <= 1'b0;
                    end
                end
            end
            
            // --- Lower Priority: Note Ons ---
            // Find the first empty slot and assign it
            if (process_on_valid) begin
                for (int i = 0; i < NUM_VOICES; i++) begin
                    // We also ensure we aren't trying to turn off this slot on the exact same cycle
                    // to prevent a race condition.
                    if (!voice_active[i]) begin
                        voice_active[i]     <= 1'b1;
                        voice_pitch[i]      <= process_on_pitch;
                        voice_instrument[i] <= process_on_inst;
                        break; 
                    end
                end
            end
            
        end
    end

endmodule