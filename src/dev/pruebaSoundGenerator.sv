module pruebaSoundGenerator (
    input  logic clk,
    input  logic rst,
    input  logic [15:0] sw,
    input  logic btnL,   // kick
    input  logic btnC,   // snare
    input  logic btnR,   // hi-hat

    output logic mclk,
    output logic lrclk,
    output logic sclk,
    output logic sdata,

    output logic [15:0] led
);

    // ------------------------------------------------------------
    // Reset
    // ------------------------------------------------------------
    logic rst;
    logic rst_n;

    assign rst_n = ~rst;

    // ------------------------------------------------------------
    // Debounced button signals
    // ------------------------------------------------------------
    logic kick_db, snare_db, hihat_db;

    debouncer #(.FREQ_KHZ(100000), .BOUNCE_MS(50), .XPOL(0)) u_deb_kick  (.clk(clk), .rst(rst), .x(btnL), .xDeb(kick_db));
    debouncer #(.FREQ_KHZ(100000), .BOUNCE_MS(50), .XPOL(0)) u_deb_snare (.clk(clk), .rst(rst), .x(btnC), .xDeb(snare_db));
    debouncer #(.FREQ_KHZ(100000), .BOUNCE_MS(50), .XPOL(0)) u_deb_hihat (.clk(clk), .rst(rst), .x(btnR), .xDeb(hihat_db));

    // ------------------------------------------------------------
    // One-cycle pulse on rising edge of each debounced button
    // ------------------------------------------------------------
    logic kick_prev,  snare_prev,  hihat_prev;
    logic kick_trig,  snare_trig,  hihat_trig;
    logic any_perc;
   
    

    always_ff @(posedge clk) begin
        if (rst) begin
            kick_prev  <= 1'b0;
            snare_prev <= 1'b0;
            hihat_prev <= 1'b0;
        end else begin
            kick_prev  <= kick_db;
            snare_prev <= snare_db;
            hihat_prev <= hihat_db;
        end
    end

    assign kick_trig  = kick_db  && !kick_prev;
    assign snare_trig = snare_db && !snare_prev;
    assign hihat_trig = hihat_db && !hihat_prev;
    assign any_perc   = kick_trig | snare_trig | hihat_trig;

    // ------------------------------------------------------------
    // Sound generator signals
    // ------------------------------------------------------------
    logic        in_valid;
    logic        in_last;
    logic [7:0]  synth_id;
    logic [6:0]  pitch;

    logic        audio_valid;
    logic signed [23:0] audio_sample;

    // ------------------------------------------------------------
    // Switch groups  (synths)
    // ------------------------------------------------------------
    logic [2:0] synth0_sel, synth1_sel, synth2_sel;

    assign synth0_sel = sw[2:0];
    assign synth1_sel = sw[5:3];
    assign synth2_sel = sw[8:6];

    logic synth0_en, synth1_en, synth2_en;
    logic any_synth_enabled;

    assign synth0_en        = (synth0_sel != 3'b000);
    assign synth1_en        = (synth1_sel != 3'b000);
    assign synth2_en        = (synth2_sel != 3'b000);
    assign any_synth_enabled = synth0_en | synth1_en | synth2_en;

    // ------------------------------------------------------------
    // Note selector
    // ------------------------------------------------------------
    function automatic logic [6:0] pitch_from_sel;
        input logic [2:0] sel;
        case (sel)
            3'b001: pitch_from_sel = 7'd48; // C3
            3'b010: pitch_from_sel = 7'd50; // D3
            3'b011: pitch_from_sel = 7'd52; // E3
            3'b100: pitch_from_sel = 7'd53; // F3
            3'b101: pitch_from_sel = 7'd55; // G3
            3'b110: pitch_from_sel = 7'd57; // A3
            3'b111: pitch_from_sel = 7'd59; // B3
            default: pitch_from_sel = 7'd48;
        endcase
    endfunction

    // ------------------------------------------------------------
    // 48 kHz sample trigger
    // ------------------------------------------------------------
    localparam int DIV_COUNT = 2083;

    logic [11:0] sample_cnt;
    logic        start_sample;

    always_ff @(posedge clk) begin
        if (rst) begin
            sample_cnt <= 12'd0;
        end else begin
            if (sample_cnt == DIV_COUNT - 1)
                sample_cnt <= 12'd0;
            else
                sample_cnt <= sample_cnt + 12'd1;
        end
    end

    assign start_sample = (sample_cnt == DIV_COUNT - 1);

    // ------------------------------------------------------------
    // Latch percussion triggers at the start of each sample period
    // Triggers that arrive between sample periods are held until
    // the next start_sample, ensuring they are always included in
    // a batch and not lost.
    // ------------------------------------------------------------
    logic kick_pending, snare_pending, hihat_pending;

    always_ff @(posedge clk) begin
        if (rst) begin
            kick_pending  <= 1'b0;
            snare_pending <= 1'b0;
            hihat_pending <= 1'b0;
        end else begin
            // Set on trigger, clear when the FSM sends the perc voice
            if (kick_trig)               kick_pending  <= 1'b1;
            else if (state == SEND_KICK) kick_pending  <= 1'b0;

            if (snare_trig)               snare_pending <= 1'b1;
            else if (state == SEND_SNARE) snare_pending <= 1'b0;

            if (hihat_trig)               hihat_pending <= 1'b1;
            else if (state == SEND_HIHAT) hihat_pending <= 1'b0;
        end
    end

    // ------------------------------------------------------------
    // Sequential sender FSM
    // Order: synth0 → synth1 → synth2 → kick → snare → hi-hat
    // Disabled/non-pending slots are skipped.
    // in_last is asserted on whichever is the final active slot.
    // ------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE,
        SEND_SYNTH0,
        SEND_SYNTH1,
        SEND_SYNTH2,
        SEND_KICK,
        SEND_SNARE,
        SEND_HIHAT
    } state_t;

    state_t state, next_state;

    // Helper: which is the last active slot after a given point?
    // Returns the next state to go to after current, or IDLE if none remain.
    function automatic state_t next_after;
        input state_t current;
        input logic s0, s1, s2, kick, snare, hihat;
        case (current)
            SEND_SYNTH0: begin
                if (s1)    next_after = SEND_SYNTH1;
                else if (s2)    next_after = SEND_SYNTH2;
                else if (kick)  next_after = SEND_KICK;
                else if (snare) next_after = SEND_SNARE;
                else if (hihat) next_after = SEND_HIHAT;
                else            next_after = IDLE;
            end
            SEND_SYNTH1: begin
                if (s2)         next_after = SEND_SYNTH2;
                else if (kick)  next_after = SEND_KICK;
                else if (snare) next_after = SEND_SNARE;
                else if (hihat) next_after = SEND_HIHAT;
                else            next_after = IDLE;
            end
            SEND_SYNTH2: begin
                if (kick)       next_after = SEND_KICK;
                else if (snare) next_after = SEND_SNARE;
                else if (hihat) next_after = SEND_HIHAT;
                else            next_after = IDLE;
            end
            SEND_KICK: begin
                if (snare)      next_after = SEND_SNARE;
                else if (hihat) next_after = SEND_HIHAT;
                else            next_after = IDLE;
            end
            SEND_SNARE: begin
                if (hihat)      next_after = SEND_HIHAT;
                else            next_after = IDLE;
            end
            default:            next_after = IDLE;
        endcase
    endfunction

    // is_last: true when there is no active slot after current
    function automatic logic is_last;
        input state_t current;
        input logic s0, s1, s2, kick, snare, hihat;
        is_last = (next_after(current, s0, s1, s2, kick, snare, hihat) == IDLE);
    endfunction

    // Next-state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start_sample) begin
                    if      (synth0_en)    next_state = SEND_SYNTH0;
                    else if (synth1_en)    next_state = SEND_SYNTH1;
                    else if (synth2_en)    next_state = SEND_SYNTH2;
                    else if (kick_pending) next_state = SEND_KICK;
                    else if (snare_pending)next_state = SEND_SNARE;
                    else if (hihat_pending)next_state = SEND_HIHAT;
                end
            end
            SEND_SYNTH0: next_state = next_after(SEND_SYNTH0, synth0_en, synth1_en, synth2_en, kick_pending, snare_pending, hihat_pending);
            SEND_SYNTH1: next_state = next_after(SEND_SYNTH1, synth0_en, synth1_en, synth2_en, kick_pending, snare_pending, hihat_pending);
            SEND_SYNTH2: next_state = next_after(SEND_SYNTH2, synth0_en, synth1_en, synth2_en, kick_pending, snare_pending, hihat_pending);
            SEND_KICK:   next_state = next_after(SEND_KICK,   synth0_en, synth1_en, synth2_en, kick_pending, snare_pending, hihat_pending);
            SEND_SNARE:  next_state = next_after(SEND_SNARE,  synth0_en, synth1_en, synth2_en, kick_pending, snare_pending, hihat_pending);
            SEND_HIHAT:  next_state = IDLE;
            default:     next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    // ------------------------------------------------------------
    // Output logic
    // ------------------------------------------------------------
    always_comb begin
        in_valid = 1'b0;
        in_last  = 1'b0;
        synth_id = 8'd0;
        pitch    = 7'd48;

        case (state)
            SEND_SYNTH0: begin
                in_valid = 1'b1;
                synth_id = 8'd0;  // PIANO
                pitch    = pitch_from_sel(synth0_sel);
                in_last  = is_last(SEND_SYNTH0, synth0_en, synth1_en, synth2_en, kick_pending, snare_pending, hihat_pending);
            end
            SEND_SYNTH1: begin
                in_valid = 1'b1;
                synth_id = 8'd4;  // TRUMPET
                pitch    = pitch_from_sel(synth1_sel);
                in_last  = is_last(SEND_SYNTH1, synth0_en, synth1_en, synth2_en, kick_pending, snare_pending, hihat_pending);
            end
            SEND_SYNTH2: begin
                in_valid = 1'b1;
                synth_id = 8'd5;  // SYNTH
                pitch    = pitch_from_sel(synth2_sel);
                in_last  = is_last(SEND_SYNTH2, synth0_en, synth1_en, synth2_en, kick_pending, snare_pending, hihat_pending);
            end
            SEND_KICK: begin
                in_valid = 1'b1;
                synth_id = 8'd2;  // KICK
                pitch    = 7'd0;  // unused for percussion
                in_last  = is_last(SEND_KICK, synth0_en, synth1_en, synth2_en, kick_pending, snare_pending, hihat_pending);
            end
            SEND_SNARE: begin
                in_valid = 1'b1;
                synth_id = 8'd1;  // SNARE
                pitch    = 7'd0;
                in_last  = is_last(SEND_SNARE, synth0_en, synth1_en, synth2_en, kick_pending, snare_pending, hihat_pending);
            end
            SEND_HIHAT: begin
                in_valid = 1'b1;
                synth_id = 8'd3;  // HIHAT
                pitch    = 7'd0;
                in_last  = 1'b1;  // always last
            end
            default: begin
                in_valid = 1'b0;
                in_last  = 1'b0;
                synth_id = 8'd0;
                pitch    = 7'd48;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Sound generator
    // ------------------------------------------------------------
    sound_generator u_sound_generator (
        .clk        (clk),
        .rst_n      (rst_n),
        .in_valid   (in_valid),
        .in_last    (in_last),
        .synth_id   (synth_id),
        .pitch      (pitch),
        .out_valid  (audio_valid),
        .out_sample (audio_sample)
    );

    // ------------------------------------------------------------
    // Silence handling
    // ------------------------------------------------------------
    logic        silence_valid;
    logic signed [23:0] i2s_sample;
    logic        i2s_ready;

    assign silence_valid = start_sample && !any_synth_enabled && !any_perc;
    assign i2s_ready     = audio_valid | silence_valid;
    assign i2s_sample    = audio_valid ? audio_sample : 24'sd0;

    // ------------------------------------------------------------
    // I2S transmitter
    // ------------------------------------------------------------
    i2s_transmitter u_i2s_transmitter (
        .clk100mhz (clk),
        .rst       (rst),
        .ready     (i2s_ready),
        .sample    (i2s_sample),
        .mclk      (mclk),
        .sclk      (sclk),
        .lrclk     (lrclk),
        .sdata     (sdata)
    );

    // ------------------------------------------------------------
    // Debug LEDs
    // ------------------------------------------------------------
    logic [23:0] led_cnt;
    always_ff @(posedge clk) begin
        if (rst) led_cnt <= 24'd0;
        else     led_cnt <= led_cnt + 24'd1;
    end

    assign led[0]  = rst;
    assign led[1]  = in_valid;
    assign led[2]  = in_last;
    assign led[3]  = audio_valid;
    assign led[4]  = |audio_sample;
    assign led[5]  = kick_trig;
    assign led[6]  = snare_trig;
    assign led[7]  = hihat_trig;
    assign led[8]  = kick_pending;
    assign led[9]  = snare_pending;
    assign led[10] = hihat_pending;
    assign led[13:11] = synth0_sel;
    assign led[14] = silence_valid;
    assign led[15] = led_cnt[23];

endmodule