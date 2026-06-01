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
    input  logic                        is_playing,
    input  logic                        mode_normal,
    input  logic                        mode_live,
    input  logic                        mode_record,
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

    typedef enum logic [1:0] {
        CACHE_IDLE,
        CACHE_REQ,
        CACHE_WAIT
    } cache_state_t;

    cache_state_t                 cache_state;
    logic [5:0]                   fetch_col;
    logic [PATTERN_ID_BITS-1:0]   cached_pattern_id;
    logic                         cache_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            cache_state   <= CACHE_IDLE;
            fetch_col     <= '0;
            cached_pattern_id <= '0;
            cache_valid   <= 1'b0;
            ui_req        <= 1'b0;
            ui_addr       <= '0;
            for (int i = 0; i < PATTERN_LENGTH; i++) begin
                pattern_cache[i] <= '0;
            end
        end else begin
            ui_req <= 1'b0;

            // If the selected pattern changes, restart the cache fill.
            if (ui_active_pattern != cached_pattern_id) begin
                cached_pattern_id <= ui_active_pattern;
                fetch_col     <= '0;
                cache_valid   <= 1'b0;
                cache_state   <= CACHE_REQ;
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

    // --------------------------------------------------------------------
    // VGA timing + renderer pipeline
    //
    // The old version drove the VGA refresher with one big combinational
    // pixel renderer. This version keeps the same 640x480 timing but
    // registers the pixel coordinates, rendered color, sync and blanking.
    //
    // Pipeline at clk25mhz:
    //   counter pixel -> render_x/render_y -> rgb_s1 -> RGB
    //
    // hSync/vSync/blanking are delayed through the same pipeline, so the
    // delayed RGB remains aligned with the delayed VGA timing.
    // --------------------------------------------------------------------
    logic        clk25mhz;

    logic [9:0]  h_cnt;
    logic [9:0]  v_cnt;

    logic [9:0]  render_x;
    logic [9:0]  render_y;

    logic        hsync_s0;
    logic        vsync_s0;
    logic        blank_s0;

    logic        hsync_s1;
    logic        vsync_s1;
    logic        blank_s1;

    logic [11:0] rgb_comb;
    logic [11:0] rgb_s1;

    vgaClock clkgen (
        .clk_out1(clk25mhz),
        .reset   (rst),
        .clk_in1 (clk)
    );

    function automatic logic hsync_for(input logic [9:0] x);
        begin
            hsync_for = !((x >= 10'd656) && (x < 10'd752));
        end
    endfunction

    function automatic logic vsync_for(input logic [9:0] y);
        begin
            vsync_for = !((y >= 10'd490) && (y < 10'd492));
        end
    endfunction

    function automatic logic blank_for(input logic [9:0] x, input logic [9:0] y);
        begin
            blank_for = (x >= 10'd640) || (y >= 10'd480);
        end
    endfunction

    always_ff @(posedge clk25mhz) begin
        if (rst) begin
            h_cnt    <= 10'd0;
            v_cnt    <= 10'd0;

            render_x <= 10'd0;
            render_y <= 10'd0;

            hsync_s0 <= 1'b1;
            vsync_s0 <= 1'b1;
            blank_s0 <= 1'b1;

            hsync_s1 <= 1'b1;
            vsync_s1 <= 1'b1;
            blank_s1 <= 1'b1;

            rgb_s1   <= 12'h000;

            hSync    <= 1'b1;
            vSync    <= 1'b1;
            RGB      <= 12'h000;
        end else begin
            // Stage 0: capture the pixel currently being scanned.
            render_x <= h_cnt;
            render_y <= v_cnt;

            hsync_s0 <= hsync_for(h_cnt);
            vsync_s0 <= vsync_for(v_cnt);
            blank_s0 <= blank_for(h_cnt, v_cnt);

            // Stage 1: capture rendered color for the previously captured pixel.
            rgb_s1   <= rgb_comb;
            hsync_s1 <= hsync_s0;
            vsync_s1 <= vsync_s0;
            blank_s1 <= blank_s0;

            // Output stage: RGB and sync are delayed by the same amount.
            hSync    <= hsync_s1;
            vSync    <= vsync_s1;
            RGB      <= blank_s1 ? 12'h000 : rgb_s1;

            // VGA counters: 800 x 525 total timing.
            if (h_cnt == 10'd799) begin
                h_cnt <= 10'd0;

                if (v_cnt == 10'd524)
                    v_cnt <= 10'd0;
                else
                    v_cnt <= v_cnt + 10'd1;
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

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

    always_ff @(posedge clk) begin
        if (rst) begin //we know we are using 120 as default, so might as well maintain it here too
            bpm_hundreds <= 4'd1;
            bpm_tens     <= 4'd2;
            bpm_ones     <= 4'd0;
            bpm_prev     <= 8'd120;
        end else if (bpm != bpm_prev) begin
            bpm_prev     <= bpm;
    
            bpm_hundreds <= bpm / 8'd100;
            bpm_tens     <= (bpm % 8'd100) / 8'd10;
            bpm_ones     <= bpm % 8'd10;
        end
    end


    // Precompute note display digits and the 32-note visible window outside
    // of the per-pixel renderer. This removes divisions and note-window
    // comparisons from the VGA pixel path.
    logic [3:0] note_hundreds;
    logic [3:0] note_tens;
    logic [3:0] note_ones;
    logic [6:0] visible_min_reg;
    logic [6:0] visible_max_reg;
    logic [5:0] selected_note_row_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            // Default selected note is usually MIDI 60.
            note_hundreds         <= 4'd0;
            note_tens             <= 4'd6;
            note_ones             <= 4'd0;
            visible_min_reg       <= 7'd44;
            visible_max_reg       <= 7'd75;
            selected_note_row_reg <= 6'd15;
        end else begin
            note_hundreds <= ui_active_note_slot / 7'd100;
            note_tens     <= (ui_active_note_slot % 7'd100) / 7'd10;
            note_ones     <= ui_active_note_slot % 7'd10;

            if (ui_active_note_slot < 7'd16) begin
                visible_min_reg       <= 7'd0;
                visible_max_reg       <= 7'd31;
                selected_note_row_reg <= 7'd31 - ui_active_note_slot;
            end else if (ui_active_note_slot > 7'd111) begin
                visible_min_reg       <= 7'd96;
                visible_max_reg       <= 7'd127;
                selected_note_row_reg <= 7'd127 - ui_active_note_slot;
            end else begin
                visible_min_reg       <= ui_active_note_slot - 7'd16;
                visible_max_reg       <= ui_active_note_slot + 7'd15;
                selected_note_row_reg <= 6'd15;
            end
        end
    end

    // Combinational renderer
    always_comb begin
        int local_x;
        int local_y;
        int grid_col;
        int grid_row;
        int bx;
        int note_row;
        int text_idx;
        int text_x;
        int text_y;
        logic in_grid;
        logic note_hit;
        logic text_hit;
        logic [6:0] pitch;
        logic [7:0] ch;

        rgb_comb = 12'h000;
        text_hit = 1'b0;

        // Main outer panel
        if (border_rect(render_x, render_y, 24, 18, 592, 424, 2))
            rgb_comb = 12'h333;

        // Top-left octave label: OCT:4.
        // This uses the octave selected in dawController with comma/dot,
        // not the octave derived from ui_active_note_slot.
        for (int i = 0; i < 5; i++) begin
            unique case (i)
                0: ch = 8'h4F; // O
                1: ch = 8'h43; // C
                2: ch = 8'h54; // T
                3: ch = 8'h3A; // :
                4: ch = digit_ascii(current_octave);
                default: ch = 8'h20;
            endcase

            if (char_pixel(render_x, render_y, 38 + i*12, 32, ch))
                text_hit = 1'b1;
        end

        // Top pattern buttons: 1 2 3 4 5 6 7 8 9 0
        for (int i = 0; i < NUM_PATTERNS; i++) begin
            bx = 160 + (i * 32);

            if (in_rect(render_x, render_y, bx, 28, 26, 30)) begin
                if (ui_active_pattern == i[PATTERN_ID_BITS-1:0])
                    rgb_comb = 12'h073;
                else if (mute_mask[i])
                    rgb_comb = 12'h300;
                else
                    rgb_comb = 12'h111;
            end

            if (border_rect(render_x, render_y, bx, 28, 26, 30, 2)) begin
                if (ui_active_pattern == i[PATTERN_ID_BITS-1:0])
                    rgb_comb = 12'h0F6;
                else if (mute_mask[i])
                    rgb_comb = 12'hF33;
                else
                    rgb_comb = 12'h555;
            end

            ch = (i == 9) ? 8'h30 : digit_ascii(i[3:0] + 4'd1);
            if (char_pixel(render_x, render_y, bx + 8, 36, ch))
                text_hit = 1'b1;
        end

        // BPM label and value at top right
        for (int i = 0; i < 7; i++) begin
            unique case (i)
                0: ch = 8'h42; // B
                1: ch = 8'h50; // P
                2: ch = 8'h4D; // M
                3: ch = 8'h3A; // :
                4: ch = digit_ascii(bpm_hundreds);
                5: ch = digit_ascii(bpm_tens);
                6: ch = digit_ascii(bpm_ones);
                default: ch = 8'h20;
            endcase
            if (char_pixel(render_x, render_y, 514 + i*12, 32, ch))
                text_hit = 1'b1;
        end

        // Piano-roll / pattern grid
        in_grid = in_rect(render_x, render_y, GRID_X, GRID_Y, GRID_W, GRID_H);
        if (in_grid) begin
            local_x  = render_x - GRID_X;
            local_y  = render_y - GRID_Y;
            grid_col = local_x >> 3; // / STEP_W
            grid_row = local_y >> 3; // / NOTE_H

            // background + selected pitch row
            if (grid_row == selected_note_row_reg)
                rgb_comb = 12'h112;
            else
                rgb_comb = 12'h010;

            // semiquaver/beat/bar grid lines
            if (local_x[2:0] == 3'd0 || local_y[2:0] == 3'd0)
                rgb_comb = 12'h222;
            if ((grid_col[1:0] == 2'd0) && (local_x[2:0] < 3'd2))
                rgb_comb = 12'h333;
            if ((grid_col[3:0] == 4'd0) && (local_x[2:0] < 3'd3))
                rgb_comb = 12'h555;

            // note blocks
            note_hit = 1'b0;
            if (cache_valid) begin
                for (int n = 0; n < MAX_NOTES; n++) begin
                    if (pattern_cache[grid_col[5:0]].notes[n].active) begin
                        pitch = pattern_cache[grid_col[5:0]].notes[n].note_delta;
                        if (pitch >= visible_min_reg && pitch <= visible_max_reg) begin
                            note_row = visible_max_reg - pitch;
                            if (grid_row == note_row)
                                note_hit = 1'b1;
                        end
                    end
                end
            end

            if (note_hit)
                rgb_comb = 12'h0C7;

            // playback cursor
            if ((grid_col[5:0] == current_playback_step) && (local_x[2:0] < 3'd2))
                rgb_comb = is_playing ? 12'hFF0 : 12'h777;
        end

        // Grid border
        if (border_rect(render_x, render_y, GRID_X, GRID_Y, GRID_W, GRID_H, 2))
            rgb_comb = 12'hAAA;

        // Bottom-left mode label: MODE: NORMAL/LIVE/RECORD/WAIT
        for (int i = 0; i < 12; i++) begin
            unique case (i)
                0: ch = 8'h4D; // M
                1: ch = 8'h4F; // O
                2: ch = 8'h44; // D
                3: ch = 8'h45; // E
                4: ch = 8'h3A; // :
                5: ch = 8'h20;
                default: ch = mode_char(mode_normal, mode_live, mode_record, i - 6);
            endcase
            if (char_pixel(render_x, render_y, 38 + i*12, 408, ch))
                text_hit = 1'b1;
        end

        // Bottom-center note window label: NOTE:xxx
        for (int i = 0; i < 8; i++) begin
            unique case (i)
                0: ch = 8'h4E; // N
                1: ch = 8'h4F; // O
                2: ch = 8'h54; // T
                3: ch = 8'h45; // E
                4: ch = 8'h3A; // :
                5: ch = digit_ascii(note_hundreds);
                6: ch = digit_ascii(note_tens);
                7: ch = digit_ascii(note_ones);
                default: ch = 8'h20;
            endcase
            if (char_pixel(render_x, render_y, 264 + i*12, 408, ch))
                text_hit = 1'b1;
        end

        // Bottom-right instrument label: INSTR: XXXXXXX
        for (int i = 0; i < 14; i++) begin
            unique case (i)
                0: ch = 8'h49; // I
                1: ch = 8'h4E; // N
                2: ch = 8'h53; // S
                3: ch = 8'h54; // T
                4: ch = 8'h52; // R
                5: ch = 8'h3A; // :
                6: ch = 8'h20;
                default: ch = instrument_char(ui_active_instrument, i - 7);
            endcase
            if (char_pixel(render_x, render_y, 420 + i*12, 408, ch))
                text_hit = 1'b1;
        end

        if (text_hit)
            rgb_comb = 12'hEEE;
    end
endmodule
