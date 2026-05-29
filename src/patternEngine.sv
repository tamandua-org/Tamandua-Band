// pattern_engine.sv
// Scans all NUM_PATTERNS each semiquaver tick.
// For each pattern: fetches curr and prev columns from BRAM (one read each),
// then fetches instrument_id from a small register file.
// Fires note_on on rising edges, note_off on falling edges (GATED only).
//
// BRAM layout per pattern:
//   address [0..63] ? pattern_col_t (48 bits: 6 x cell_t)
//
// Instrument register file: instrument_regs[NUM_PATTERNS] - written externally.
//
// Scan cost per pattern: ~4 cycles (EVAL_MUTE ? WAIT_CURR ? READ_PREV ?
//   WAIT_PREV+FETCH_INSTR ? SCAN_NOTES x MAX_NOTES).
// Total worst case: 10 patterns x ~10 cycles = ~100 cycles per semiquaver tick.
// At 120 BPM: 12,500,000 cycles budget - comfortably fits.

import daw_pkg::*;

module patternEngine (
    input  logic                        clk,
    input  logic                        rst,

    // Timing & control
    input  logic                        semiquaver_tick,
    input  logic                        is_playing,
    input  logic step_forward_pulse,
    input  logic step_backward_pulse,
    input  logic [NUM_PATTERNS-1:0]     mute_mask,

    output logic [5:0]                  current_playback_step, // Current playback position (for UI and RAM writer)

    // BRAM handshake for port A.1
    output logic                        ram_req,   
    output logic [9:0]                  ram_addr,  
    input  pattern_col_t                ram_rdata,
    input  logic                        ram_valid,

    // Instrument register file (external, updated by top module based on info from controller)
    input  instrument_t                 instrument_regs [NUM_PATTERNS],

    // Note events to voice allocator
    output note_event_t                 note_on_event,
    output logic                        note_on_valid,
    output note_event_t                 note_off_event,
    output logic                        note_off_valid
);

    // Step counter
    always_ff @(posedge clk) begin
        if (rst) begin
            current_playback_step <= '0;
        end else begin
            if (is_playing && semiquaver_tick) begin
                current_playback_step <= current_playback_step + 1'b1; 
            end else if (!is_playing) begin
                if (step_forward_pulse) begin
                    current_playback_step <= current_playback_step + 1'b1;
                end else if (step_backward_pulse) begin
                    current_playback_step <= current_playback_step - 1'b1;
                end
            end
        end
    end

    logic [5:0] target_prev_step;
    assign target_prev_step = current_playback_step - 1'b1;

    // FSM
    typedef enum logic [2:0] {
        IDLE,
        EVAL_MUTE,
        REQ_CURR,       
        REQ_PREV,       
        WAIT_CURR_DATA, 
        WAIT_PREV_DATA, 
        SCAN_NOTE_ON,
        SCAN_NOTE_OFF
    } state_t;

    state_t                     state;
    logic [PATTERN_ID_BITS-1:0] scan_pattern;
    logic [2:0]                 scan_note;

    pattern_col_t               curr_col;
    pattern_col_t               prev_col;
    instrument_t                scan_instrument;

    always_ff @(posedge clk) begin
        if (rst) begin
            state          <= IDLE;
            scan_pattern   <= '0;
            scan_note      <= '0;
            curr_col       <= '0;
            prev_col       <= '0;
            scan_instrument<= PIANO;
            note_on_valid  <= 1'b0;
            note_off_valid <= 1'b0;
            note_on_event  <= '0;
            note_off_event <= '0;
            ram_req        <= 1'b0;
            ram_addr       <= '0;
        end else begin
            note_on_valid  <= 1'b0;
            note_off_valid <= 1'b0;
            ram_req        <= 1'b0;

            case (state)
                IDLE: begin
                    if (is_playing && semiquaver_tick) begin
                        scan_pattern <= '0;
                        state        <= EVAL_MUTE;
                    end
                end

                EVAL_MUTE: begin
                    if (scan_pattern >= NUM_PATTERNS) begin
                        state <= IDLE;
                    end else if (mute_mask[scan_pattern]) begin // check next pattern
                        scan_pattern <= scan_pattern + 1'b1;
                    end else begin // we need to check this pattern's notes (later we'll come back to this state to check the remaining)
                        state <= REQ_CURR;
                    end
                end

                REQ_CURR: begin
                    ram_req  <= 1'b1;
                    ram_addr <= {scan_pattern, current_playback_step};
                    state    <= REQ_PREV;
                end

                REQ_PREV: begin
                    ram_req  <= 1'b1; // Back-to-back request
                    ram_addr <= {scan_pattern, target_prev_step};
                    state    <= WAIT_CURR_DATA;
                end

                WAIT_CURR_DATA: begin
                    // Wait for "handshake"
                    if (ram_valid) begin
                        curr_col <= ram_rdata;
                        state    <= WAIT_PREV_DATA;
                    end
                end
                
                WAIT_PREV_DATA: begin
                    // Wait for "handshake"
                    if (ram_valid) begin
                        prev_col        <= ram_rdata;                      
                        scan_instrument <= instrument_regs[scan_pattern];  
                        scan_note       <= '0;
                        state           <= SCAN_NOTE_ON;
                    end
                end
 
                SCAN_NOTE_ON: begin
                    if (scan_note == MAX_NOTES) begin
                        scan_note <= '0;
                        state     <= SCAN_NOTE_OFF;
                    end else begin
                        // Check if curr_col.notes[scan_note] is a new note (active in curr but not found anywhere in prev)
                        if (curr_col.notes[scan_note].active) begin
                            logic found_in_prev;
                            found_in_prev = 1'b0;
                            for (int i = 0; i < MAX_NOTES; i++) begin
                                if (prev_col.notes[i].active &&
                                    prev_col.notes[i].note_delta == curr_col.notes[scan_note].note_delta)
                                    found_in_prev = 1'b1;
                            end
 
                            if (!found_in_prev) begin // send pulse of note
                                note_on_valid               <= 1'b1;
                                note_on_event.instrument_id <= scan_instrument;
                                note_on_event.note_delta    <= curr_col.notes[scan_note].note_delta;
                                note_on_event.pattern_id <= scan_pattern;

                            end
                        end
 
                        scan_note <= scan_note + 1'b1;
                    end
                end
 
                SCAN_NOTE_OFF: begin
                    if (scan_note == MAX_NOTES) begin
                        scan_pattern <= scan_pattern + 1'b1;
                        state        <= EVAL_MUTE;
                    end else begin
                        // Check if prev_col.notes[scan_note] ended (active in prev but pitch not found anywhere in curr) (only for GATED notes)
                        if (prev_col.notes[scan_note].active &&
                            get_end_mode(scan_instrument) == GATED) begin
                            logic found_in_curr;
                            found_in_curr = 1'b0;
                            for (int i = 0; i < MAX_NOTES; i++) begin
                                if (curr_col.notes[i].active &&
                                    curr_col.notes[i].note_delta == prev_col.notes[scan_note].note_delta)
                                    found_in_curr = 1'b1;
                            end
 
                            if (!found_in_curr) begin
                                note_off_valid               <= 1'b1;
                                note_off_event.instrument_id <= scan_instrument;
                                note_off_event.note_delta    <= prev_col.notes[scan_note].note_delta;
                                note_off_event.pattern_id <= scan_pattern;

                            end
                        end
 
                        scan_note <= scan_note + 1'b1;
                    end
                end

            endcase
        end
    end

endmodule