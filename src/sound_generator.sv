// =============================================================================
// sound_generator.sv  (v4)
// -----------------------------------------------------------------------------
// Adds percussion (kick, snare, hi-hat) mixed with the synth oscillators.
//
// Instrument ID map (instrument_t enum):
//   PIANO   = 0  → synth oscillator slot 0
//   SNARE   = 1  → percussion_player (one-shot)
//   KICK    = 2  → percussion_player (one-shot)
//   HIHAT   = 3  → percussion_player (one-shot)
//   TRUMPET = 4  → synth oscillator slot 1  (sine, placeholder)
//   SYNTH   = 5  → synth oscillator slot 2  (sine, placeholder)
//   GUITAR  = 6  → synth oscillator slot 3  (sine, placeholder)
//
// Synth slots: generalised to NUM_SYNTHS=4 using a single oscillator module
// with an internal array of phase accumulators (one per slot).
//
// Mixing:
//   - Synth voices are accumulated and normalised as before.
//   - Percussion output (already mixed inside percussion_player) is added
//     AFTER normalisation, then the whole thing is saturated to 24 bits.
// =============================================================================

module sound_generator (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        in_valid,
    input  logic        in_last,
    input  logic [7:0]  synth_id,
    input  logic [6:0]  pitch,

    output logic        out_valid,
    output logic signed [23:0] out_sample
);

    // =========================================================================
    // Instrument ID constants
    // =========================================================================
    localparam logic [7:0] ID_PIANO   = 8'd0;
    localparam logic [7:0] ID_SNARE   = 8'd1;
    localparam logic [7:0] ID_KICK    = 8'd2;
    localparam logic [7:0] ID_HIHAT   = 8'd3;
    localparam logic [7:0] ID_TRUMPET = 8'd4;
    localparam logic [7:0] ID_SYNTH   = 8'd5;
    localparam logic [7:0] ID_GUITAR  = 8'd6;

    // Map synth IDs to oscillator slot index
    // PIANO→0, TRUMPET→1, SYNTH→2, GUITAR→3
    localparam int NUM_SYNTHS = 4;

    function automatic logic [1:0] id_to_slot;
        input logic [7:0] id;
        case (id)
            ID_PIANO:   id_to_slot = 2'd0;
            ID_TRUMPET: id_to_slot = 2'd1;
            ID_SYNTH:   id_to_slot = 2'd2;
            ID_GUITAR:  id_to_slot = 2'd3;
            default:    id_to_slot = 2'd0;
        endcase
    endfunction

    function automatic logic is_synth;
        input logic [7:0] id;
        is_synth = (id == ID_PIANO   || id == ID_TRUMPET ||
                    id == ID_SYNTH   || id == ID_GUITAR);
    endfunction

    function automatic logic is_percussion;
        input logic [7:0] id;
        is_percussion = (id == ID_SNARE || id == ID_KICK || id == ID_HIHAT);
    endfunction

    // =========================================================================
    // 1.  48 kHz sample-enable
    // =========================================================================
    localparam int DIV_COUNT = 2083;

    logic [11:0] clk_cnt;
    logic        sample_en;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            clk_cnt   <= 12'd0;
            sample_en <= 1'b0;
        end else begin
            if (clk_cnt == DIV_COUNT - 1) begin
                clk_cnt   <= 12'd0;
                sample_en <= 1'b1;
            end else begin
                clk_cnt   <= clk_cnt + 12'd1;
                sample_en <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 2.  Generalised multi-slot oscillator
    //     Single synth_oscillator instance with NUM_SYNTHS internal phase accumulators.
    //     slot_en[i] fires only when that slot's in_valid arrives.
    // =========================================================================
    logic [1:0]  current_slot;
    logic        slot_en;
    logic signed [23:0] osc_out;

    assign current_slot = id_to_slot(synth_id);
    assign slot_en      = in_valid && is_synth(synth_id);

    synth_oscillator #(
        .NUM_SLOTS(NUM_SYNTHS)
    ) u_osc (
        .clk        (clk),
        .rst_n      (rst_n),
        .slot_en    (slot_en),
        .slot_idx   (current_slot),
        .pitch      (pitch),
        .sample_out (osc_out)
    );

    // =========================================================================
    // 3.  Percussion player
    // =========================================================================
    logic signed [23:0] perc_out;

    percussion_player u_perc (
        .clk        (clk),
        .rst_n      (rst_n),
        .sample_en  (sample_en),
        .in_valid   (in_valid && is_percussion(synth_id)),
        .synth_id   (synth_id),
        .out_sample (perc_out)
    );

    // =========================================================================
    // 4.  Accumulator FSM  (synth voices only)
    // =========================================================================
    function automatic logic [2:0] log2_floor;
        input logic [2:0] n;
        if      (n >= 3'd4) log2_floor = 3'd2;
        else if (n >= 3'd2) log2_floor = 3'd1;
        else                log2_floor = 3'd0;
    endfunction

    typedef enum logic [1:0] {
        IDLE      = 2'b00,
        ACCUM     = 2'b01,
        NORMALIZE = 2'b10,
        EMIT      = 2'b11
    } state_t;

    state_t             state;
    logic signed [31:0] acc;
    logic [2:0]         voice_count;
    logic signed [23:0] synth_normalized;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state            <= IDLE;
            acc              <= 32'sd0;
            voice_count      <= 3'd0;
            out_valid        <= 1'b0;
            out_sample       <= 24'sd0;
            synth_normalized <= 24'sd0;
        end else begin
            out_valid <= 1'b0;

            case (state)

                // -------------------------------------------------------------
                IDLE: begin
                    // Accept synth voices; ignore percussion (handled separately)
                    if (in_valid && is_synth(synth_id)) begin
                        acc         <= 32'(signed'(osc_out));
                        voice_count <= 3'd1;
                        state       <= in_last ? NORMALIZE : ACCUM;
                    end else if (in_valid && in_last && is_percussion(synth_id)) begin
                        // Batch with only percussion: emit immediately with silence on synth
                        synth_normalized <= 24'sd0;
                        state            <= EMIT;
                    end
                end

                // -------------------------------------------------------------
                ACCUM: begin
                    if (in_valid && is_synth(synth_id)) begin
                        acc         <= acc + 32'(signed'(osc_out));
                        voice_count <= voice_count + 3'd1;
                        if (in_last) state <= NORMALIZE;
                    end else if (in_valid && in_last && is_percussion(synth_id)) begin
                        // Last voice was percussion: normalise what we have
                        state <= NORMALIZE;
                    end
                end

                // -------------------------------------------------------------
                NORMALIZE: begin
                    begin
                        logic signed [31:0] shifted;
                        shifted          = (voice_count == 0) ? 32'sd0
                                         : acc >>> log2_floor(voice_count);
                        if      (shifted > 32'sd8388607)  synth_normalized <=  24'sd8388607;
                        else if (shifted < -32'sd8388608) synth_normalized <= -24'sd8388608;
                        else                              synth_normalized <= shifted[23:0];
                    end
                    state <= EMIT;
                end

                // -------------------------------------------------------------
                EMIT: begin
                    // Mix synth + percussion, saturate
                    begin
                        logic signed [25:0] mixed;
                        mixed = 26'(signed'(synth_normalized)) + 26'(signed'(perc_out));
                        if      (mixed > 26'sd8388607)  out_sample <=  24'sd8388607;
                        else if (mixed < -26'sd8388608) out_sample <= -24'sd8388608;
                        else                            out_sample <= mixed[23:0];
                    end
                    out_valid   <= 1'b1;
                    acc         <= 32'sd0;
                    voice_count <= 3'd0;
                    state       <= IDLE;
                end

            endcase
        end
    end

endmodule