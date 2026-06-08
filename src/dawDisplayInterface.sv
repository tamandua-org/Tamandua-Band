import daw_pkg::*;
import pixelColor_pkg::*;

module dawDisplayInterface #(
    parameter int GRID_X = 64,
    parameter int GRID_Y = 106,
    parameter int STEP_W = 8,                 // 64 steps x 8 px = 512 px
    parameter int NOTE_H = 8,                 // 32 visible notes x 8 px = 256 px
    parameter int VISIBLE_NOTES = 32
)(
    input  logic                        clk,
    input  logic                        rst,

    // DAW state
    input  logic [7:0]                  bpm,
    input  logic [NUM_PATTERNS-1:0]     mute_mask,
    input  logic [PATTERN_ID_BITS-1:0]  ui_active_pattern,
    input  instrument_t                 ui_active_instrument,
    input  note_delta_t                 ui_active_note_slot,
    input  logic [3:0]                  current_octave,
    input  logic [2:0]                  master_gain_shift,
    input  logic                        is_playing,
    input  logic                        mode_normal,
    input  logic                        mode_live,
    input  logic                        mode_record,
    input  logic                        export_active,
    input  logic [5:0]                  current_playback_step,

    // patternRamWrapper UI port
    output logic                        ui_req,
    output logic [9:0]                  ui_addr,
    input  pattern_col_t                ui_rdata,
    input  logic                        ui_valid,

    // VGA pins
    output logic                        hSync,
    output logic                        vSync,
    output logic [11:0]                 RGB
);

    localparam int GRID_W = PATTERN_LENGTH * STEP_W;      // 512
    localparam int GRID_H = VISIBLE_NOTES * NOTE_H;       // 256

    // We cache the active pattern for rendering
    pattern_col_t pattern_cache [PATTERN_LENGTH];

    // Pre-rendered piano-roll bitmap for the current 32-note window.
    // note_bitmap[col][row] = 1 means draw a note block at that grid cell.
    // This removes the MAX_NOTES loop and the pattern_cache read from the per-pixel path.
    logic [VISIBLE_NOTES-1:0] note_bitmap [PATTERN_LENGTH];

    typedef enum logic [1:0] {
        CACHE_IDLE,
        CACHE_REQ,
        CACHE_WAIT
    } cache_state_t;

    cache_state_t                 cache_state;
    logic [5:0]                   fetch_col;
    logic [PATTERN_ID_BITS-1:0]   cached_pattern_id;
    note_delta_t                  cached_note_slot;
    logic                         cache_valid;

    logic [6:0]                   visible_min_reg;
    logic [6:0]                   visible_max_reg;
    logic [4:0]                   selected_grid_row;
    
    instrument_t active_instrument_reg;
    
    always_ff @(posedge clk) begin
        if (rst)
            active_instrument_reg <= FIRST_INSTRUMENT;
        else 
            active_instrument_reg <= ui_active_instrument;
     end
    

    function automatic logic [6:0] compute_visible_min(input note_delta_t midi_note);
        begin
            if (midi_note < 7'd16)
                compute_visible_min = 7'd0;
            else if (midi_note > 7'd111)
                compute_visible_min = 7'd96;
            else
                compute_visible_min = midi_note - 7'd16;
        end
    endfunction

    function automatic logic [VISIBLE_NOTES-1:0] make_col_bitmap(
        input pattern_col_t col,
        input logic [6:0] vmin,
        input logic [6:0] vmax
    );
        logic [VISIBLE_NOTES-1:0] bits;
        logic [6:0] pitch;
        logic [6:0] row7;
        begin
            bits = '0;
            for (int n = 0; n < MAX_NOTES; n++) begin
                pitch = col.notes[n].note_delta;
                if (col.notes[n].active && pitch >= vmin && pitch <= vmax) begin
                    row7 = vmax - pitch;
                    bits[row7[4:0]] = 1'b1;
                end
            end
            make_col_bitmap = bits;
        end
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            cache_state   <= CACHE_IDLE;
            fetch_col     <= '0;
            cached_pattern_id <= '0;
            cached_note_slot  <= '0;
            cache_valid       <= 1'b0;
            visible_min_reg   <= 7'd44;   // default for note 60 -> 44..75
            visible_max_reg   <= 7'd75;
            selected_grid_row <= 5'd15;
            ui_req            <= 1'b0;
            ui_addr           <= '0;
            for (int i = 0; i < PATTERN_LENGTH; i++) begin
                pattern_cache[i] <= '0;
                note_bitmap[i]   <= '0;
            end
        end else begin
            ui_req <= 1'b0;

            // If the selected pattern or the 32-note window changes, restart the cache fill.
            // The cache fill also builds note_bitmap so the pixel renderer only does one bitmap lookup.
            if ((ui_active_pattern != cached_pattern_id) || (ui_active_note_slot != cached_note_slot)) begin
                cached_pattern_id <= ui_active_pattern;
                cached_note_slot  <= ui_active_note_slot;
                visible_min_reg   <= compute_visible_min(ui_active_note_slot);
                visible_max_reg   <= compute_visible_min(ui_active_note_slot) + 7'd31;
                selected_grid_row <= (compute_visible_min(ui_active_note_slot) + 7'd31) - ui_active_note_slot;
                fetch_col         <= '0;
                cache_valid       <= 1'b0;
                cache_state       <= CACHE_REQ;
            end else begin
                case (cache_state)
                    CACHE_IDLE: begin
                        // it's okay to always refresh it's lower priority than patternEngine requests
                        fetch_col   <= '0;
                        cache_state <= CACHE_REQ;
                    end

                    CACHE_REQ: begin
                        ui_req      <= 1'b1;
                        ui_addr     <= {cached_pattern_id, fetch_col};
                        cache_state <= CACHE_WAIT;
                    end

                    CACHE_WAIT: begin
                        if (ui_valid) begin
                            pattern_cache[fetch_col] <= ui_rdata;
                            note_bitmap[fetch_col]   <= make_col_bitmap(ui_rdata, visible_min_reg, visible_max_reg);

                            if (fetch_col == PATTERN_LENGTH - 1) begin
                                cache_valid <= 1'b1;
                                cache_state <= CACHE_IDLE;
                            end else begin
                                fetch_col   <= fetch_col + 1'b1;
                                cache_state <= CACHE_REQ;
                            end
                        end
                    end

                    default: cache_state <= CACHE_IDLE;
                endcase
            end
        end
    end

    // VGA timing
    pixelColor_t color;
    logic [9:0] pixel;
    logic [9:0] line;
    logic [11:0] rgb_next;
    logic [11:0] rgb_reg;

    vgaRefresher refresher (
        .clk100mhz     (clk),
        .rst           (rst),
        .pixelColorIn  (color),
        .hSync         (hSync),
        .vSync         (vSync),
        .pixel         (pixel),
        .line          (line),
        .pixelColorOut (RGB)
    );

    assign color.red   = rgb_next[11:8];
    assign color.green = rgb_next[7:4];
    assign color.blue  = rgb_next[3:0];

    // --------------------------------------------------------------------
    // Small 5x7 font. Only one scale is used: 2x, so a char is 10x14 px.
    // --------------------------------------------------------------------
    function automatic logic [4:0] font5x7(input logic [7:0] ch, input logic [2:0] row);
        begin
            font5x7 = 5'b00000;
            unique case (ch)
                8'h20: font5x7 = 5'b00000; // space
                8'h3A: begin // :
                    unique case (row)
                        3'd1, 3'd4: font5x7 = 5'b00100;
                        default:    font5x7 = 5'b00000;
                    endcase
                end
                8'h2D: begin // -
                    font5x7 = (row == 3'd3) ? 5'b11111 : 5'b00000;
                end
                8'h30: begin // 0
                    unique case (row)
                        3'd0: font5x7 = 5'b01110;
                        3'd1: font5x7 = 5'b10001;
                        3'd2: font5x7 = 5'b10011;
                        3'd3: font5x7 = 5'b10101;
                        3'd4: font5x7 = 5'b11001;
                        3'd5: font5x7 = 5'b10001;
                        3'd6: font5x7 = 5'b01110;
                    endcase
                end
                8'h31: begin // 1
                    unique case (row)
                        3'd0: font5x7 = 5'b00100;
                        3'd1: font5x7 = 5'b01100;
                        3'd2: font5x7 = 5'b00100;
                        3'd3: font5x7 = 5'b00100;
                        3'd4: font5x7 = 5'b00100;
                        3'd5: font5x7 = 5'b00100;
                        3'd6: font5x7 = 5'b01110;
                    endcase
                end
                8'h32: begin // 2
                    unique case (row)
                        3'd0: font5x7 = 5'b01110;
                        3'd1: font5x7 = 5'b10001;
                        3'd2: font5x7 = 5'b00001;
                        3'd3: font5x7 = 5'b00010;
                        3'd4: font5x7 = 5'b00100;
                        3'd5: font5x7 = 5'b01000;
                        3'd6: font5x7 = 5'b11111;
                    endcase
                end
                8'h33: begin // 3
                    unique case (row)
                        3'd0: font5x7 = 5'b11110;
                        3'd1: font5x7 = 5'b00001;
                        3'd2: font5x7 = 5'b00001;
                        3'd3: font5x7 = 5'b01110;
                        3'd4: font5x7 = 5'b00001;
                        3'd5: font5x7 = 5'b00001;
                        3'd6: font5x7 = 5'b11110;
                    endcase
                end
                8'h34: begin // 4
                    unique case (row)
                        3'd0: font5x7 = 5'b00010;
                        3'd1: font5x7 = 5'b00110;
                        3'd2: font5x7 = 5'b01010;
                        3'd3: font5x7 = 5'b10010;
                        3'd4: font5x7 = 5'b11111;
                        3'd5: font5x7 = 5'b00010;
                        3'd6: font5x7 = 5'b00010;
                    endcase
                end
                8'h35: begin // 5
                    unique case (row)
                        3'd0: font5x7 = 5'b11111;
                        3'd1: font5x7 = 5'b10000;
                        3'd2: font5x7 = 5'b10000;
                        3'd3: font5x7 = 5'b11110;
                        3'd4: font5x7 = 5'b00001;
                        3'd5: font5x7 = 5'b00001;
                        3'd6: font5x7 = 5'b11110;
                    endcase
                end
                8'h36: begin // 6
                    unique case (row)
                        3'd0: font5x7 = 5'b01110;
                        3'd1: font5x7 = 5'b10000;
                        3'd2: font5x7 = 5'b10000;
                        3'd3: font5x7 = 5'b11110;
                        3'd4: font5x7 = 5'b10001;
                        3'd5: font5x7 = 5'b10001;
                        3'd6: font5x7 = 5'b01110;
                    endcase
                end
                8'h37: begin // 7
                    unique case (row)
                        3'd0: font5x7 = 5'b11111;
                        3'd1: font5x7 = 5'b00001;
                        3'd2: font5x7 = 5'b00010;
                        3'd3: font5x7 = 5'b00100;
                        3'd4: font5x7 = 5'b01000;
                        3'd5: font5x7 = 5'b01000;
                        3'd6: font5x7 = 5'b01000;
                    endcase
                end
                8'h38: begin // 8
                    unique case (row)
                        3'd0: font5x7 = 5'b01110;
                        3'd1: font5x7 = 5'b10001;
                        3'd2: font5x7 = 5'b10001;
                        3'd3: font5x7 = 5'b01110;
                        3'd4: font5x7 = 5'b10001;
                        3'd5: font5x7 = 5'b10001;
                        3'd6: font5x7 = 5'b01110;
                    endcase
                end
                8'h39: begin // 9
                    unique case (row)
                        3'd0: font5x7 = 5'b01110;
                        3'd1: font5x7 = 5'b10001;
                        3'd2: font5x7 = 5'b10001;
                        3'd3: font5x7 = 5'b01111;
                        3'd4: font5x7 = 5'b00001;
                        3'd5: font5x7 = 5'b00001;
                        3'd6: font5x7 = 5'b01110;
                    endcase
                end
                // A-Z
                8'h41: begin unique case (row) 3'd0: font5x7=5'b01110; 3'd1: font5x7=5'b10001; 3'd2: font5x7=5'b10001; 3'd3: font5x7=5'b11111; 3'd4: font5x7=5'b10001; 3'd5: font5x7=5'b10001; 3'd6: font5x7=5'b10001; endcase end
                8'h42: begin unique case (row) 3'd0: font5x7=5'b11110; 3'd1: font5x7=5'b10001; 3'd2: font5x7=5'b10001; 3'd3: font5x7=5'b11110; 3'd4: font5x7=5'b10001; 3'd5: font5x7=5'b10001; 3'd6: font5x7=5'b11110; endcase end
                8'h43: begin unique case (row) 3'd0: font5x7=5'b01111; 3'd1: font5x7=5'b10000; 3'd2: font5x7=5'b10000; 3'd3: font5x7=5'b10000; 3'd4: font5x7=5'b10000; 3'd5: font5x7=5'b10000; 3'd6: font5x7=5'b01111; endcase end
                8'h44: begin unique case (row) 3'd0: font5x7=5'b11110; 3'd1: font5x7=5'b10001; 3'd2: font5x7=5'b10001; 3'd3: font5x7=5'b10001; 3'd4: font5x7=5'b10001; 3'd5: font5x7=5'b10001; 3'd6: font5x7=5'b11110; endcase end
                8'h45: begin unique case (row) 3'd0: font5x7=5'b11111; 3'd1: font5x7=5'b10000; 3'd2: font5x7=5'b10000; 3'd3: font5x7=5'b11110; 3'd4: font5x7=5'b10000; 3'd5: font5x7=5'b10000; 3'd6: font5x7=5'b11111; endcase end
                8'h46: begin unique case (row) 3'd0: font5x7=5'b11111; 3'd1: font5x7=5'b10000; 3'd2: font5x7=5'b10000; 3'd3: font5x7=5'b11110; 3'd4: font5x7=5'b10000; 3'd5: font5x7=5'b10000; 3'd6: font5x7=5'b10000; endcase end
                8'h47: begin unique case (row) 3'd0: font5x7=5'b01111; 3'd1: font5x7=5'b10000; 3'd2: font5x7=5'b10000; 3'd3: font5x7=5'b10011; 3'd4: font5x7=5'b10001; 3'd5: font5x7=5'b10001; 3'd6: font5x7=5'b01110; endcase end
                8'h48: begin unique case (row) 3'd0: font5x7=5'b10001; 3'd1: font5x7=5'b10001; 3'd2: font5x7=5'b10001; 3'd3: font5x7=5'b11111; 3'd4: font5x7=5'b10001; 3'd5: font5x7=5'b10001; 3'd6: font5x7=5'b10001; endcase end
                8'h49: begin unique case (row) 3'd0: font5x7=5'b01110; 3'd1: font5x7=5'b00100; 3'd2: font5x7=5'b00100; 3'd3: font5x7=5'b00100; 3'd4: font5x7=5'b00100; 3'd5: font5x7=5'b00100; 3'd6: font5x7=5'b01110; endcase end
                8'h4A: begin unique case (row) 3'd0: font5x7=5'b00001; 3'd1: font5x7=5'b00001; 3'd2: font5x7=5'b00001; 3'd3: font5x7=5'b00001; 3'd4: font5x7=5'b10001; 3'd5: font5x7=5'b10001; 3'd6: font5x7=5'b01110; endcase end
                8'h4B: begin unique case (row) 3'd0: font5x7=5'b10001; 3'd1: font5x7=5'b10010; 3'd2: font5x7=5'b10100; 3'd3: font5x7=5'b11000; 3'd4: font5x7=5'b10100; 3'd5: font5x7=5'b10010; 3'd6: font5x7=5'b10001; endcase end
                8'h4C: begin unique case (row) 3'd0: font5x7=5'b10000; 3'd1: font5x7=5'b10000; 3'd2: font5x7=5'b10000; 3'd3: font5x7=5'b10000; 3'd4: font5x7=5'b10000; 3'd5: font5x7=5'b10000; 3'd6: font5x7=5'b11111; endcase end
                8'h4D: begin unique case (row) 3'd0: font5x7=5'b10001; 3'd1: font5x7=5'b11011; 3'd2: font5x7=5'b10101; 3'd3: font5x7=5'b10101; 3'd4: font5x7=5'b10001; 3'd5: font5x7=5'b10001; 3'd6: font5x7=5'b10001; endcase end
                8'h4E: begin unique case (row) 3'd0: font5x7=5'b10001; 3'd1: font5x7=5'b11001; 3'd2: font5x7=5'b10101; 3'd3: font5x7=5'b10011; 3'd4: font5x7=5'b10001; 3'd5: font5x7=5'b10001; 3'd6: font5x7=5'b10001; endcase end
                8'h4F: begin unique case (row) 3'd0: font5x7=5'b01110; 3'd1: font5x7=5'b10001; 3'd2: font5x7=5'b10001; 3'd3: font5x7=5'b10001; 3'd4: font5x7=5'b10001; 3'd5: font5x7=5'b10001; 3'd6: font5x7=5'b01110; endcase end
                8'h50: begin unique case (row) 3'd0: font5x7=5'b11110; 3'd1: font5x7=5'b10001; 3'd2: font5x7=5'b10001; 3'd3: font5x7=5'b11110; 3'd4: font5x7=5'b10000; 3'd5: font5x7=5'b10000; 3'd6: font5x7=5'b10000; endcase end
                8'h51: begin unique case (row) 3'd0: font5x7=5'b01110; 3'd1: font5x7=5'b10001; 3'd2: font5x7=5'b10001; 3'd3: font5x7=5'b10001; 3'd4: font5x7=5'b10101; 3'd5: font5x7=5'b10010; 3'd6: font5x7=5'b01101; endcase end
                8'h52: begin unique case (row) 3'd0: font5x7=5'b11110; 3'd1: font5x7=5'b10001; 3'd2: font5x7=5'b10001; 3'd3: font5x7=5'b11110; 3'd4: font5x7=5'b10100; 3'd5: font5x7=5'b10010; 3'd6: font5x7=5'b10001; endcase end
                8'h53: begin unique case (row) 3'd0: font5x7=5'b01111; 3'd1: font5x7=5'b10000; 3'd2: font5x7=5'b10000; 3'd3: font5x7=5'b01110; 3'd4: font5x7=5'b00001; 3'd5: font5x7=5'b00001; 3'd6: font5x7=5'b11110; endcase end
                8'h54: begin unique case (row) 3'd0: font5x7=5'b11111; 3'd1: font5x7=5'b00100; 3'd2: font5x7=5'b00100; 3'd3: font5x7=5'b00100; 3'd4: font5x7=5'b00100; 3'd5: font5x7=5'b00100; 3'd6: font5x7=5'b00100; endcase end
                8'h55: begin unique case (row) 3'd0: font5x7=5'b10001; 3'd1: font5x7=5'b10001; 3'd2: font5x7=5'b10001; 3'd3: font5x7=5'b10001; 3'd4: font5x7=5'b10001; 3'd5: font5x7=5'b10001; 3'd6: font5x7=5'b01110; endcase end
                8'h56: begin unique case (row) 3'd0: font5x7=5'b10001; 3'd1: font5x7=5'b10001; 3'd2: font5x7=5'b10001; 3'd3: font5x7=5'b10001; 3'd4: font5x7=5'b01010; 3'd5: font5x7=5'b01010; 3'd6: font5x7=5'b00100; endcase end
                8'h57: begin unique case (row) 3'd0: font5x7=5'b10001; 3'd1: font5x7=5'b10001; 3'd2: font5x7=5'b10001; 3'd3: font5x7=5'b10101; 3'd4: font5x7=5'b10101; 3'd5: font5x7=5'b10101; 3'd6: font5x7=5'b01010; endcase end
                8'h58: begin unique case (row) 3'd0: font5x7=5'b10001; 3'd1: font5x7=5'b10001; 3'd2: font5x7=5'b01010; 3'd3: font5x7=5'b00100; 3'd4: font5x7=5'b01010; 3'd5: font5x7=5'b10001; 3'd6: font5x7=5'b10001; endcase end
                8'h59: begin unique case (row) 3'd0: font5x7=5'b10001; 3'd1: font5x7=5'b10001; 3'd2: font5x7=5'b01010; 3'd3: font5x7=5'b00100; 3'd4: font5x7=5'b00100; 3'd5: font5x7=5'b00100; 3'd6: font5x7=5'b00100; endcase end
                8'h5A: begin unique case (row) 3'd0: font5x7=5'b11111; 3'd1: font5x7=5'b00001; 3'd2: font5x7=5'b00010; 3'd3: font5x7=5'b00100; 3'd4: font5x7=5'b01000; 3'd5: font5x7=5'b10000; 3'd6: font5x7=5'b11111; endcase end
                default: font5x7 = 5'b00000;
            endcase
        end
    endfunction

    function automatic logic in_rect(
        input logic [9:0] x,
        input logic [9:0] y,
        input int rx,
        input int ry,
        input int rw,
        input int rh
    );
        begin
            in_rect = (x >= rx) && (x < rx + rw) && (y >= ry) && (y < ry + rh);
        end
    endfunction

    function automatic logic border_rect(
        input logic [9:0] x,
        input logic [9:0] y,
        input int rx,
        input int ry,
        input int rw,
        input int rh,
        input int thickness
    );
        begin
            border_rect = in_rect(x, y, rx, ry, rw, rh) &&
                          ((x < rx + thickness) || (x >= rx + rw - thickness) ||
                           (y < ry + thickness) || (y >= ry + rh - thickness));
        end
    endfunction

    function automatic logic char_pixel(
        input logic [9:0] x,
        input logic [9:0] y,
        input int x0,
        input int y0,
        input logic [7:0] ch
    );
        int dx;
        int dy;
        int fx;
        int fy;
        logic [4:0] row_bits;
        begin
            char_pixel = 1'b0;
            if (in_rect(x, y, x0, y0, 10, 14)) begin
                dx = x - x0;
                dy = y - y0;
                fx = dx >> 1;
                fy = dy >> 1;
                if (fx < 5 && fy < 7) begin
                    row_bits   = font5x7(ch, fy[2:0]);
                    char_pixel = row_bits[4 - fx];
                end
            end
        end
    endfunction

    function automatic logic [7:0] digit_ascii(input logic [3:0] d);
        begin
            digit_ascii = 8'h30 + {4'b0000, d};
        end
    endfunction

    function automatic logic octave_is_negative(input note_delta_t midi_note);
        begin
            // Standard MIDI octave numbering: MIDI 60 = C4.
            // Therefore octave = floor(midi_note / 12) - 1.
            octave_is_negative = (midi_note < 7'd12);
        end
    endfunction

    function automatic logic [3:0] octave_abs_digit(input note_delta_t midi_note);
        begin
            // Absolute value of the octave digit for MIDI notes 0..127.
            // 0..11  -> octave -1
            // 12..23 -> octave  0
            // 24..35 -> octave  1
            // ...
            // 120..127 -> octave 9
            if      (midi_note < 7'd12)  octave_abs_digit = 4'd1;
            else if (midi_note < 7'd24)  octave_abs_digit = 4'd0;
            else if (midi_note < 7'd36)  octave_abs_digit = 4'd1;
            else if (midi_note < 7'd48)  octave_abs_digit = 4'd2;
            else if (midi_note < 7'd60)  octave_abs_digit = 4'd3;
            else if (midi_note < 7'd72)  octave_abs_digit = 4'd4;
            else if (midi_note < 7'd84)  octave_abs_digit = 4'd5;
            else if (midi_note < 7'd96)  octave_abs_digit = 4'd6;
            else if (midi_note < 7'd108) octave_abs_digit = 4'd7;
            else if (midi_note < 7'd120) octave_abs_digit = 4'd8;
            else                         octave_abs_digit = 4'd9;
        end
    endfunction

    function automatic logic [7:0] mode_char(input logic normal, input logic live, input logic record, input int idx);
        begin
            mode_char = 8'h20;
            if (normal) begin // NORMAL
                unique case (idx)
                    0: mode_char = 8'h4E; 1: mode_char = 8'h4F; 2: mode_char = 8'h52;
                    3: mode_char = 8'h4D; 4: mode_char = 8'h41; 5: mode_char = 8'h4C;
                    default: mode_char = 8'h20;
                endcase
            end else if (live) begin // LIVE
                unique case (idx)
                    0: mode_char = 8'h4C; 1: mode_char = 8'h49; 2: mode_char = 8'h56; 3: mode_char = 8'h45;
                    default: mode_char = 8'h20;
                endcase
            end else if (record) begin // RECORD
                unique case (idx)
                    0: mode_char = 8'h52; 1: mode_char = 8'h45; 2: mode_char = 8'h43;
                    3: mode_char = 8'h4F; 4: mode_char = 8'h52; 5: mode_char = 8'h44;
                    default: mode_char = 8'h20;
                endcase
            end else begin // record countdown currently has no explicit output from dawController
                unique case (idx) // WAIT
                    0: mode_char = 8'h57; 1: mode_char = 8'h41; 2: mode_char = 8'h49; 3: mode_char = 8'h54;
                    default: mode_char = 8'h20;
                endcase
            end
        end
    endfunction

    function automatic logic [7:0] instrument_char(input instrument_t inst, input int idx);
        begin
            instrument_char = 8'h20;
            unique case (inst)
                PIANO: begin
                    unique case (idx)
                        0: instrument_char = 8'h50; 1: instrument_char = 8'h49; 2: instrument_char = 8'h41;
                        3: instrument_char = 8'h4E; 4: instrument_char = 8'h4F;
                        default: instrument_char = 8'h20;
                    endcase
                end
                SNARE: begin
                    unique case (idx)
                        0: instrument_char = 8'h53; 1: instrument_char = 8'h4E; 2: instrument_char = 8'h41;
                        3: instrument_char = 8'h52; 4: instrument_char = 8'h45;
                        default: instrument_char = 8'h20;
                    endcase
                end
                KICK: begin
                    unique case (idx)
                        0: instrument_char = 8'h4B; 1: instrument_char = 8'h49; 2: instrument_char = 8'h43; 3: instrument_char = 8'h4B;
                        default: instrument_char = 8'h20;
                    endcase
                end
                HIHAT: begin
                    unique case (idx)
                        0: instrument_char = 8'h48; 1: instrument_char = 8'h49; 2: instrument_char = 8'h48;
                        3: instrument_char = 8'h41; 4: instrument_char = 8'h54;
                        default: instrument_char = 8'h20;
                    endcase
                end
                TRUMPET: begin
                    unique case (idx)
                        0: instrument_char = 8'h54; 1: instrument_char = 8'h52; 2: instrument_char = 8'h55;
                        3: instrument_char = 8'h4D; 4: instrument_char = 8'h50; 5: instrument_char = 8'h45; 6: instrument_char = 8'h54;
                        default: instrument_char = 8'h20;
                    endcase
                end
                SYNTH: begin
                    unique case (idx)
                        0: instrument_char = 8'h53; 1: instrument_char = 8'h59; 2: instrument_char = 8'h4E;
                        3: instrument_char = 8'h54; 4: instrument_char = 8'h48;
                        default: instrument_char = 8'h20;
                    endcase
                end
                GUITAR: begin
                    unique case (idx)
                        0: instrument_char = 8'h47; 1: instrument_char = 8'h55; 2: instrument_char = 8'h49;
                        3: instrument_char = 8'h54; 4: instrument_char = 8'h41; 5: instrument_char = 8'h52;
                        default: instrument_char = 8'h20;
                    endcase
                end
                default: instrument_char = 8'h20;
            endcase
        end
    endfunction


    logic [3:0] bpm_hundreds;
    logic [3:0] bpm_tens;
    logic [3:0] bpm_ones;
    
    logic [7:0] bpm_prev;

    logic [3:0] note_hundreds;
    logic [3:0] note_tens;
    logic [3:0] note_ones;
    note_delta_t note_prev;

    always_ff @(posedge clk) begin
        if (rst) begin //we know we are using 120 as default, so might as well maintain it here too
            bpm_hundreds <= 4'd1;
            bpm_tens     <= 4'd2;
            bpm_ones     <= 4'd0;
            bpm_prev     <= 8'd120;
            note_hundreds <= 4'd0;
            note_tens     <= 4'd6;
            note_ones     <= 4'd0;
            note_prev     <= 7'd60;
        end else begin
            if (bpm != bpm_prev) begin
                bpm_prev     <= bpm;
                bpm_hundreds <= bpm / 8'd100;
                bpm_tens     <= (bpm % 8'd100) / 8'd10;
                bpm_ones     <= bpm % 8'd10;
            end

            if (ui_active_note_slot != note_prev) begin
                note_prev     <= ui_active_note_slot;
                note_hundreds <= ui_active_note_slot / 7'd100;
                note_tens     <= (ui_active_note_slot % 7'd100) / 7'd10;
                note_ones     <= ui_active_note_slot % 7'd10;
            end
        end
    end
    

    function automatic int char_idx_12(input int rel_x);
        begin
            char_idx_12 = 0;
            for (int k = 1; k < 16; k++) begin
                if (rel_x >= k*12)
                    char_idx_12 = k;
            end
        end
    endfunction

    function automatic logic [7:0] octave_label_char(input int idx, input logic [3:0] oct);
        begin
            unique case (idx)
                0: octave_label_char = 8'h4F; // O
                1: octave_label_char = 8'h43; // C
                2: octave_label_char = 8'h54; // T
                3: octave_label_char = 8'h3A; // :
                4: octave_label_char = digit_ascii(oct);
                default: octave_label_char = 8'h20;
            endcase
        end
    endfunction

    function automatic logic [7:0] volume_label_char(input int idx);
        begin
            unique case (idx)
                0: volume_label_char = 8'h56; // V
                1: volume_label_char = 8'h4F; // O
                2: volume_label_char = 8'h4C; // L
                3: volume_label_char = 8'h3A; // :
                default: volume_label_char = 8'h20;
            endcase
        end
    endfunction

    function automatic logic [7:0] bpm_label_char(
        input int idx,
        input logic [3:0] hundreds,
        input logic [3:0] tens,
        input logic [3:0] ones
    );
        begin
            unique case (idx)
                0: bpm_label_char = 8'h42; // B
                1: bpm_label_char = 8'h50; // P
                2: bpm_label_char = 8'h4D; // M
                3: bpm_label_char = 8'h3A; // :
                4: bpm_label_char = digit_ascii(hundreds);
                5: bpm_label_char = digit_ascii(tens);
                6: bpm_label_char = digit_ascii(ones);
                default: bpm_label_char = 8'h20;
            endcase
        end
    endfunction

    function automatic logic [7:0] note_label_char(
        input int idx,
        input logic [3:0] hundreds,
        input logic [3:0] tens,
        input logic [3:0] ones
    );
        begin
            unique case (idx)
                0: note_label_char = 8'h4E; // N
                1: note_label_char = 8'h4F; // O
                2: note_label_char = 8'h54; // T
                3: note_label_char = 8'h45; // E
                4: note_label_char = 8'h3A; // :
                5: note_label_char = digit_ascii(hundreds);
                6: note_label_char = digit_ascii(tens);
                7: note_label_char = digit_ascii(ones);
                default: note_label_char = 8'h20;
            endcase
        end
    endfunction

    function automatic logic [7:0] export_mode_char(input int idx);
        begin
            // EXPORTING
            unique case (idx)
                0: export_mode_char = 8'h45; // E
                1: export_mode_char = 8'h58; // X
                2: export_mode_char = 8'h50; // P
                3: export_mode_char = 8'h4F; // O
                4: export_mode_char = 8'h52; // R
                5: export_mode_char = 8'h54; // T
                6: export_mode_char = 8'h49; // I
                7: export_mode_char = 8'h4E; // N
                8: export_mode_char = 8'h47; // G
                default: export_mode_char = 8'h20;
            endcase
        end
    endfunction

    function automatic logic [7:0] mode_label_char(
        input int idx,
        input logic export_active_i,
        input logic normal,
        input logic live,
        input logic record
    );
        begin
            unique case (idx)
                0: mode_label_char = 8'h4D; // M
                1: mode_label_char = 8'h4F; // O
                2: mode_label_char = 8'h44; // D
                3: mode_label_char = 8'h45; // E
                4: mode_label_char = 8'h3A; // :
                5: mode_label_char = 8'h20;
                default: mode_label_char = export_active_i ? export_mode_char(idx - 6) : mode_char(normal, live, record, idx - 6);
            endcase
        end
    endfunction

    function automatic logic [7:0] instr_label_char(input int idx, input instrument_t inst);
        begin
            unique case (idx)
                0: instr_label_char = 8'h49; // I
                1: instr_label_char = 8'h4E; // N
                2: instr_label_char = 8'h53; // S
                3: instr_label_char = 8'h54; // T
                4: instr_label_char = 8'h52; // R
                5: instr_label_char = 8'h3A; // :
                6: instr_label_char = 8'h20;
                default: instr_label_char = instrument_char(inst, idx - 7);
            endcase
        end
    endfunction

    // Combinational renderer
    // Timing-oriented version:
    //   * still uses vgaRefresher for the VGA counters and output registers
    //   * uses note_bitmap instead of scanning MAX_NOTES for every pixel
    //   * tests only one text character per pixel instead of every character string
    always_comb begin
        int local_x;
        int local_y;
        int grid_col;
        int grid_row;
        int bx;
        int btn_idx;
        int btn_local_x;
        int rel_x;
        int char_idx;
        int char_x0;
        int char_y0;
        logic in_grid;
        logic text_hit;
        logic text_candidate;
        logic [7:0] ch;

        rgb_next       = 12'h000;
        text_hit       = 1'b0;
        text_candidate = 1'b0;
        ch             = 8'h20;
        char_x0        = 0;
        char_y0        = 0;

        // Main outer panel
        if (border_rect(pixel, line, 24, 18, 592, 424, 2))
            rgb_next = 12'h333;

        // Piano-roll / pattern grid
        in_grid = in_rect(pixel, line, GRID_X, GRID_Y, GRID_W, GRID_H);
        if (in_grid) begin
            local_x  = pixel - GRID_X;
            local_y  = line  - GRID_Y;
            grid_col = local_x >> 3; // / STEP_W
            grid_row = local_y >> 3; // / NOTE_H

            // background + selected pitch row
            if (grid_row[4:0] == selected_grid_row)
                rgb_next = 12'h112;
            else
                rgb_next = 12'h010;

            // semiquaver/beat/bar grid lines
            if (local_x[2:0] == 3'd0 || local_y[2:0] == 3'd0)
                rgb_next = 12'h222;
            if ((grid_col[1:0] == 2'd0) && (local_x[2:0] < 3'd2))
                rgb_next = 12'h333;
            if ((grid_col[3:0] == 4'd0) && (local_x[2:0] < 3'd3))
                rgb_next = 12'h555;

            // note blocks: one bitmap lookup, no note loop in the pixel path
            if (cache_valid && note_bitmap[grid_col[5:0]][grid_row[4:0]])
                rgb_next = 12'h0C7;

            // playback cursor
            if ((grid_col[5:0] == current_playback_step) && (local_x[2:0] < 3'd2))
                rgb_next = is_playing ? 12'hFF0 : 12'h777;
        end

        // Grid border
        if (border_rect(pixel, line, GRID_X, GRID_Y, GRID_W, GRID_H, 2))
            rgb_next = 12'hAAA;

        // Top pattern buttons: 1 2 3 4 5 6 7 8 9 0
        if ((pixel >= 10'd160) && (pixel < 10'd480) && (line >= 10'd28) && (line < 10'd58)) begin
            local_x     = pixel - 10'd160;
            btn_idx     = local_x >> 5;       // / 32
            btn_local_x = local_x - (btn_idx << 5);
            bx          = 160 + (btn_idx << 5);

            if ((btn_idx >= 0) && (btn_idx < NUM_PATTERNS) && (btn_local_x < 26)) begin
                if (ui_active_pattern == btn_idx[PATTERN_ID_BITS-1:0]) begin
                    if (mute_mask[btn_idx])
                        rgb_next = 12'hC80; // selected + muted: orange
                    else
                        rgb_next = 12'h073; // selected: green
                end else if (mute_mask[btn_idx]) begin
                    rgb_next = 12'h300;     // muted: red
                end else begin
                    rgb_next = 12'h111;     // normal: dark gray
                end

                if ((btn_local_x < 2) || (btn_local_x >= 24) || (line < 10'd30) || (line >= 10'd56)) begin
                    if (ui_active_pattern == btn_idx[PATTERN_ID_BITS-1:0]) begin
                        if (mute_mask[btn_idx])
                            rgb_next = 12'hFA0;
                        else
                            rgb_next = 12'h0F6;
                    end else if (mute_mask[btn_idx]) begin
                        rgb_next = 12'hF33;
                    end else begin
                        rgb_next = 12'h555;
                    end
                end

                ch = (btn_idx == 9) ? 8'h30 : digit_ascii(btn_idx[3:0] + 4'd1);
                if (char_pixel(pixel, line, bx + 8, 36, ch))
                    text_hit = 1'b1;
            end
        end

        // Volume bar under the octave label.
        // master_gain_shift uses the fine-gain table in dspAudioEngine.
        // The bar has 8 segments; more green segments means higher master gain.
        if ((pixel >= 10'd92) && (pixel < 10'd156) && (line >= 10'd56) && (line < 10'd64)) begin
            local_x     = pixel - 10'd92;
            btn_idx     = local_x >> 3;       // 8 segments, 8 px each
            btn_local_x = local_x[2:0];

            // segment border/gap = light gray
            if ((line == 10'd56) || (line == 10'd63) || (btn_local_x == 0) || (btn_local_x == 7))
                rgb_next = 12'h777;
            else if (btn_idx <= master_gain_shift)
                rgb_next = 12'h0D0;
            else
                rgb_next = 12'h333;
        end


        // Text labels. Only one character is decoded per pixel.
        if ((line >= 10'd32) && (line < 10'd46)) begin
            // Top-left octave label: OCT:4
            if ((pixel >= 10'd38) && (pixel < 10'd98)) begin
                rel_x          = pixel - 10'd38;
                char_idx       = char_idx_12(rel_x);
                if (char_idx < 5) begin
                    char_x0        = 38 + char_idx*12;
                    char_y0        = 32;
                    ch             = octave_label_char(char_idx, current_octave);
                    text_candidate = 1'b1;
                end
            end
            // BPM label and value at top right
            else if ((pixel >= 10'd514) && (pixel < 10'd598)) begin
                rel_x          = pixel - 10'd514;
                char_idx       = char_idx_12(rel_x);
                if (char_idx < 7) begin
                    char_x0        = 514 + char_idx*12;
                    char_y0        = 32;
                    ch             = bpm_label_char(char_idx, bpm_hundreds, bpm_tens, bpm_ones);
                    text_candidate = 1'b1;
                end
            end
        end else if ((line >= 10'd52) && (line < 10'd66)) begin
            // Volume label under OCT. The green/gray bar is drawn to the right.
            if ((pixel >= 10'd38) && (pixel < 10'd86)) begin
                rel_x          = pixel - 10'd38;
                char_idx       = char_idx_12(rel_x);
                if (char_idx < 4) begin
                    char_x0        = 38 + char_idx*12;
                    char_y0        = 52;
                    ch             = volume_label_char(char_idx);
                    text_candidate = 1'b1;
                end
            end
        end else if ((line >= 10'd408) && (line < 10'd422)) begin
            // Bottom-left mode label. Export overrides the normal/live/record text.
            if ((pixel >= 10'd38) && (pixel < 10'd218)) begin
                rel_x          = pixel - 10'd38;
                char_idx       = char_idx_12(rel_x);
                if (char_idx < 15) begin
                    char_x0        = 38 + char_idx*12;
                    char_y0        = 408;
                    ch             = mode_label_char(char_idx, export_active, mode_normal, mode_live, mode_record);
                    text_candidate = 1'b1;
                end
            end
            // Bottom-center note label: NOTE:xxx
            else if ((pixel >= 10'd264) && (pixel < 10'd360)) begin
                rel_x          = pixel - 10'd264;
                char_idx       = char_idx_12(rel_x);
                if (char_idx < 8) begin
                    char_x0        = 264 + char_idx*12;
                    char_y0        = 408;
                    ch             = note_label_char(char_idx, note_hundreds, note_tens, note_ones);
                    text_candidate = 1'b1;
                end
            end
            // Bottom-right instrument label: INSTR: XXXXXXX
            else if ((pixel >= 10'd420) && (pixel < 10'd588)) begin
                rel_x          = pixel - 10'd420;
                char_idx       = char_idx_12(rel_x);
                if (char_idx < 14) begin
                    char_x0        = 420 + char_idx*12;
                    char_y0        = 408;
                    ch             = instr_label_char(char_idx, active_instrument_reg);
                    text_candidate = 1'b1;
                end
            end
        end

        if (text_candidate && char_pixel(pixel, line, char_x0, char_y0, ch))
            text_hit = 1'b1;

        if (text_hit)
            rgb_next = 12'hEEE;
    end

endmodule
