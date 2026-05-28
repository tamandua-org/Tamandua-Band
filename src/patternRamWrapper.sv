import daw_pkg::*;

module patternRamWrapper (
    input logic clk,
    input logic rst,

    // Port A.1 - Pattern Engine (Strict Priority)
    input  logic       engine_req,  
    input  logic [9:0] engine_addr, //addr = {pattern_bits, step num}
    output pattern_col_t engine_rdata,
    output logic       engine_valid, 

    // Port A.2 - UI Visualizer (Lower Priority)
    input  logic       ui_req,  
    input  logic [9:0] ui_addr,     //addr = {pattern_bits, step num}
    output pattern_col_t ui_rdata,
    output logic       ui_valid, 

    // Port B - From dawController (meant for writing new notes)
    input logic                       semiquaver_tick,
    input logic record_mode,
    input logic [5:0]                 current_playback_step,
    input logic                       live_note_on,
    input logic                       live_note_off,
    input note_delta_t                live_pitch,
    input logic                       clear_pattern_pulse,
    input logic [PATTERN_ID_BITS-1:0] ui_active_pattern
);

    localparam BRAM_WIDTH = MAX_NOTES * 8; // notes x (size(note_delta) + bit_active)
    localparam BRAM_DEPTH = 1024;

    logic [9:0]              bram_a_addr;
    logic [BRAM_WIDTH-1:0]   bram_a_dout;

    logic [9:0]              bram_b_addr;
    logic                    bram_b_we;
    logic [BRAM_WIDTH-1:0]   bram_b_din;
    logic [BRAM_WIDTH-1:0]   bram_b_dout;

    
    // Port A logic

    // if the engine steals the port, we store the UI request so it isn't lost
    logic       pending_ui_req;
    logic [9:0] pending_ui_addr;

    logic       actual_ui_req;
    logic [9:0] actual_ui_addr;

    // The request to process is either the buffered one (if we were interrupted) or the live one coming directly from the UI controller
    // we know we wont be accessing memory at a fast enough rate were we'd stall ui or override ui requests
    assign actual_ui_req  = pending_ui_req ? 1'b1 : ui_req;
    assign actual_ui_addr = pending_ui_req ? pending_ui_addr : ui_addr;

    always_ff @(posedge clk) begin
        if (rst) begin
            pending_ui_req  <= 1'b0;
            pending_ui_addr <= '0;
        end else begin
            if (engine_req && actual_ui_req) begin // collision
                pending_ui_req  <= 1'b1;
                pending_ui_addr <= actual_ui_addr;
            end else if (!engine_req && actual_ui_req) begin
                pending_ui_req  <= 1'b0;
            end
        end
    end

    // Grant logic to choose who accesses bram
    logic engine_gnt;
    logic ui_gnt;
    
    always_comb begin
        if (engine_req) begin //engine priority
            engine_gnt  = 1'b1;
            ui_gnt      = 1'b0;
            bram_a_addr = engine_addr;
        end else if (actual_ui_req) begin
            engine_gnt  = 1'b0;
            ui_gnt      = 1'b1;
            bram_a_addr = actual_ui_addr;
        end else begin
            engine_gnt  = 1'b0;
            ui_gnt      = 1'b0;
            bram_a_addr = '0;
        end
    end

    // pipeline to track latency for both interfaces
    logic [1:0] engine_valid_shift;
    logic [1:0] ui_valid_shift;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            engine_valid_shift <= 2'b00;
            ui_valid_shift     <= 2'b00;
        end else begin
            engine_valid_shift <= {engine_valid_shift[0], engine_gnt};
            ui_valid_shift     <= {ui_valid_shift[0],     ui_gnt};
        end
    end
    
    // both interfaces receive the data, but only one will receive the valid bit
    assign engine_valid = engine_valid_shift[1];
    assign engine_rdata = pattern_col_t'(bram_a_dout);
    
    assign ui_valid     = ui_valid_shift[1];
    assign ui_rdata     = pattern_col_t'(bram_a_dout);


    // 2 cycle latency bram
    patternRam pRam (
        .clka  (clk),
        .wea   (1'b0), //read only port, we only write with the wrapper when receiving data from dawController
        .addra (bram_a_addr),
        .dina  ({BRAM_WIDTH{1'b0}}),
        .douta (bram_a_dout),

        .clkb  (clk),
        .web   (bram_b_we),
        .addrb (bram_b_addr),
        .dinb  (bram_b_din),
        .doutb (bram_b_dout)
    );


    // PORT B Array notes pressed and FSM
    typedef struct packed {
        logic              active;
        note_delta_t       note_delta;
        logic [5:0]        press_step;
    } held_entry_t;

    held_entry_t held [MAX_NOTES];
    logic [$clog2(MAX_NOTES)-1:0] free_slot;
    logic                         free_slot_found;
    
    always_comb begin // we find the closest free slot
        free_slot       = '0;
        free_slot_found = 1'b0;
        for (int i = 0; i < MAX_NOTES; i++) begin
            if (!held[i].active) begin
                free_slot = i[$clog2(MAX_NOTES)-1:0]; // we obtain the bits that represent i for free slot
                free_slot_found = 1'b1;
            end
        end
    end
    
    logic        do_overflow_clear;
    logic [5:0]  overflow_snap_step;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < MAX_NOTES; i++) held[i] <= '0;
        end else begin
            if (do_overflow_clear) begin
                for (int i = 0; i < MAX_NOTES; i++)
                    if (held[i].active && overflow_snap_step < held[i].press_step)
                        held[i] <= '0;
            end
        
            if (live_note_on && free_slot_found) begin
                held[free_slot].active     <= 1'b1;
                held[free_slot].note_delta <= live_pitch;
                held[free_slot].press_step <= current_playback_step;
            end else if (live_note_off) begin
                for (int i = 0; i < MAX_NOTES; i++) begin
                    if (held[i].active && held[i].note_delta == live_pitch)
                        held[i] <= '0;
                end
            end
        end
    end

    typedef enum logic [2:0] {
        IDLE,
        READ_COL,
        WAIT_COL_1,
        WAIT_COL_2,
        MODIFY_COL,
        CLEAR_LOOP
    } fsm_state_t;


    fsm_state_t                   state;
    logic [$clog2(MAX_NOTES)-1:0] note_idx;
    logic [5:0]                   snap_step;
    logic [PATTERN_ID_BITS-1:0]   snap_pattern;
    logic [5:0]                   clear_col;
    pattern_col_t                 ram_step;

    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            note_idx     <= '0;
            snap_step    <= '0;
            snap_pattern <= '0;
            clear_col    <= '0;
            ram_step    <= '0;
            bram_b_we    <= 1'b0;
            bram_b_addr  <= '0;
            bram_b_din   <= '0;
        end else begin
            bram_b_we <= 1'b0;
            do_overflow_clear  <= 1'b0;

            case (state)
                IDLE: begin
                //either we are clearing or recording, but since both can't happen at the same time we will not run into issues where one hides the other
                    if (clear_pattern_pulse) begin 
                        snap_pattern <= ui_active_pattern;
                        clear_col    <= '0;
                        state        <= CLEAR_LOOP;
                    end else if (record_mode && semiquaver_tick) begin
                        snap_step    <= current_playback_step;
                        snap_pattern <= ui_active_pattern;
                        note_idx     <= '0;
                        state        <= READ_COL;
                    end
                end

                READ_COL: begin
                    bram_b_addr <= (snap_pattern * PATTERN_LENGTH) + snap_step;
                   
                    // Signal the held block to clear overflowed entries
                    do_overflow_clear  <= 1'b1;
                    overflow_snap_step <= snap_step;
                    state              <= WAIT_COL_1;
                end

 
                WAIT_COL_1: state <= WAIT_COL_2;
                WAIT_COL_2: state <= MODIFY_COL;
 
                MODIFY_COL: begin
                    if (note_idx == MAX_NOTES) begin
                        bram_b_addr <= (snap_pattern * PATTERN_LENGTH) + snap_step;
                        bram_b_din  <= ram_step; //pattern_col_t must have same size
                        bram_b_we   <= 1'b1;
                        state       <= IDLE;
                    end else begin
                        // on first iteration base is RAM output. for the rest, base is ram_step.
                        automatic pattern_col_t base;
                        base = (note_idx == '0) ? pattern_col_t'(bram_b_dout) : ram_step;
 
                        if (held[note_idx].active) begin
                            for (int i = 0; i < MAX_NOTES; i++) begin // find first empty slot in base and insert
                                if (!base.notes[i].active) begin
                                    base.notes[i].active = 1'b1;
                                    base.notes[i].note_delta = held[note_idx].note_delta;
                                    break;
                                end
                            end
                        end
 
                        ram_step <= base;
                        note_idx  <= note_idx + 1'b1;
                    end
                end
 
                CLEAR_LOOP: begin
                    bram_b_addr <= (snap_pattern * PATTERN_LENGTH) + clear_col; //cambiar por dsp
                    bram_b_din  <= '0;
                    bram_b_we   <= 1'b1;

                    if (clear_col == PATTERN_LENGTH - 1)
                        state <= IDLE;
                    else begin
                        clear_col <= clear_col + 1'b1;
                        state <= CLEAR_LOOP;
                    end
                end
            endcase
        end
    end
endmodule