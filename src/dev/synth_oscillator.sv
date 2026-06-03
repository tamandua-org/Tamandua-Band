// =============================================================================
// synth_oscillator.sv  (v3 - generalised multi-slot)
// -----------------------------------------------------------------------------
// Single module containing NUM_SLOTS independent phase accumulators.
// Each slot advances ONLY when slot_en fires for that slot_idx.
// This replaces the generate-loop of 3 separate instances while producing
// identical hardware behaviour.
//
// Ports:
//   slot_en    - pulse: advance phase for slot_idx this cycle
//   slot_idx   - which accumulator to advance / read
//   pitch      - MIDI note for the active slot (registered internally)
//   sample_out - 24-bit signed sample from the currently addressed slot
// =============================================================================

module synth_oscillator #(
    parameter int NUM_SLOTS = 4
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          slot_en,
    input  logic [$clog2(NUM_SLOTS)-1:0]  slot_idx,
    input  logic [6:0]                    pitch,
    output logic signed [23:0]            sample_out
);

    // -------------------------------------------------------------------------
    // Sine LUT: 256 entries, full 24-bit signed range ±8_388_607
    // Generated as: round(8388607 * sin(2π * i / 256))
    // -------------------------------------------------------------------------
    logic signed [23:0] sine_lut [0:255];

    initial begin
        sine_lut[0] = 24'sd0;
        sine_lut[1] = 24'sd205867;
        sine_lut[2] = 24'sd411609;
        sine_lut[3] = 24'sd617104;
        sine_lut[4] = 24'sd822227;
        sine_lut[5] = 24'sd1026855;
        sine_lut[6] = 24'sd1230864;
        sine_lut[7] = 24'sd1434132;
        sine_lut[8] = 24'sd1636536;
        sine_lut[9] = 24'sd1837954;
        sine_lut[10] = 24'sd2038265;
        sine_lut[11] = 24'sd2237349;
        sine_lut[12] = 24'sd2435084;
        sine_lut[13] = 24'sd2631353;
        sine_lut[14] = 24'sd2826037;
        sine_lut[15] = 24'sd3019018;
        sine_lut[16] = 24'sd3210181;
        sine_lut[17] = 24'sd3399410;
        sine_lut[18] = 24'sd3586592;
        sine_lut[19] = 24'sd3771613;
        sine_lut[20] = 24'sd3954362;
        sine_lut[21] = 24'sd4134729;
        sine_lut[22] = 24'sd4312606;
        sine_lut[23] = 24'sd4487885;
        sine_lut[24] = 24'sd4660460;
        sine_lut[25] = 24'sd4830229;
        sine_lut[26] = 24'sd4997087;
        sine_lut[27] = 24'sd5160936;
        sine_lut[28] = 24'sd5321676;
        sine_lut[29] = 24'sd5479210;
        sine_lut[30] = 24'sd5633444;
        sine_lut[31] = 24'sd5784285;
        sine_lut[32] = 24'sd5931641;
        sine_lut[33] = 24'sd6075424;
        sine_lut[34] = 24'sd6215548;
        sine_lut[35] = 24'sd6351927;
        sine_lut[36] = 24'sd6484481;
        sine_lut[37] = 24'sd6613128;
        sine_lut[38] = 24'sd6737792;
        sine_lut[39] = 24'sd6858398;
        sine_lut[40] = 24'sd6974872;
        sine_lut[41] = 24'sd7087145;
        sine_lut[42] = 24'sd7195148;
        sine_lut[43] = 24'sd7298818;
        sine_lut[44] = 24'sd7398091;
        sine_lut[45] = 24'sd7492908;
        sine_lut[46] = 24'sd7583211;
        sine_lut[47] = 24'sd7668946;
        sine_lut[48] = 24'sd7750062;
        sine_lut[49] = 24'sd7826510;
        sine_lut[50] = 24'sd7898243;
        sine_lut[51] = 24'sd7965219;
        sine_lut[52] = 24'sd8027396;
        sine_lut[53] = 24'sd8084739;
        sine_lut[54] = 24'sd8137211;
        sine_lut[55] = 24'sd8184782;
        sine_lut[56] = 24'sd8227422;
        sine_lut[57] = 24'sd8265107;
        sine_lut[58] = 24'sd8297813;
        sine_lut[59] = 24'sd8325521;
        sine_lut[60] = 24'sd8348214;
        sine_lut[61] = 24'sd8365878;
        sine_lut[62] = 24'sd8378503;
        sine_lut[63] = 24'sd8386081;
        sine_lut[64] = 24'sd8388607;
        sine_lut[65] = 24'sd8386081;
        sine_lut[66] = 24'sd8378503;
        sine_lut[67] = 24'sd8365878;
        sine_lut[68] = 24'sd8348214;
        sine_lut[69] = 24'sd8325521;
        sine_lut[70] = 24'sd8297813;
        sine_lut[71] = 24'sd8265107;
        sine_lut[72] = 24'sd8227422;
        sine_lut[73] = 24'sd8184782;
        sine_lut[74] = 24'sd8137211;
        sine_lut[75] = 24'sd8084739;
        sine_lut[76] = 24'sd8027396;
        sine_lut[77] = 24'sd7965219;
        sine_lut[78] = 24'sd7898243;
        sine_lut[79] = 24'sd7826510;
        sine_lut[80] = 24'sd7750062;
        sine_lut[81] = 24'sd7668946;
        sine_lut[82] = 24'sd7583211;
        sine_lut[83] = 24'sd7492908;
        sine_lut[84] = 24'sd7398091;
        sine_lut[85] = 24'sd7298818;
        sine_lut[86] = 24'sd7195148;
        sine_lut[87] = 24'sd7087145;
        sine_lut[88] = 24'sd6974872;
        sine_lut[89] = 24'sd6858398;
        sine_lut[90] = 24'sd6737792;
        sine_lut[91] = 24'sd6613128;
        sine_lut[92] = 24'sd6484481;
        sine_lut[93] = 24'sd6351927;
        sine_lut[94] = 24'sd6215548;
        sine_lut[95] = 24'sd6075424;
        sine_lut[96] = 24'sd5931641;
        sine_lut[97] = 24'sd5784285;
        sine_lut[98] = 24'sd5633444;
        sine_lut[99] = 24'sd5479210;
        sine_lut[100] = 24'sd5321676;
        sine_lut[101] = 24'sd5160936;
        sine_lut[102] = 24'sd4997087;
        sine_lut[103] = 24'sd4830229;
        sine_lut[104] = 24'sd4660460;
        sine_lut[105] = 24'sd4487885;
        sine_lut[106] = 24'sd4312606;
        sine_lut[107] = 24'sd4134729;
        sine_lut[108] = 24'sd3954362;
        sine_lut[109] = 24'sd3771613;
        sine_lut[110] = 24'sd3586592;
        sine_lut[111] = 24'sd3399410;
        sine_lut[112] = 24'sd3210181;
        sine_lut[113] = 24'sd3019018;
        sine_lut[114] = 24'sd2826037;
        sine_lut[115] = 24'sd2631353;
        sine_lut[116] = 24'sd2435084;
        sine_lut[117] = 24'sd2237349;
        sine_lut[118] = 24'sd2038265;
        sine_lut[119] = 24'sd1837954;
        sine_lut[120] = 24'sd1636536;
        sine_lut[121] = 24'sd1434132;
        sine_lut[122] = 24'sd1230864;
        sine_lut[123] = 24'sd1026855;
        sine_lut[124] = 24'sd822227;
        sine_lut[125] = 24'sd617104;
        sine_lut[126] = 24'sd411609;
        sine_lut[127] = 24'sd205867;
        sine_lut[128] = 24'sd0;
        sine_lut[129] = -24'sd205867;
        sine_lut[130] = -24'sd411609;
        sine_lut[131] = -24'sd617104;
        sine_lut[132] = -24'sd822227;
        sine_lut[133] = -24'sd1026855;
        sine_lut[134] = -24'sd1230864;
        sine_lut[135] = -24'sd1434132;
        sine_lut[136] = -24'sd1636536;
        sine_lut[137] = -24'sd1837954;
        sine_lut[138] = -24'sd2038265;
        sine_lut[139] = -24'sd2237349;
        sine_lut[140] = -24'sd2435084;
        sine_lut[141] = -24'sd2631353;
        sine_lut[142] = -24'sd2826037;
        sine_lut[143] = -24'sd3019018;
        sine_lut[144] = -24'sd3210181;
        sine_lut[145] = -24'sd3399410;
        sine_lut[146] = -24'sd3586592;
        sine_lut[147] = -24'sd3771613;
        sine_lut[148] = -24'sd3954362;
        sine_lut[149] = -24'sd4134729;
        sine_lut[150] = -24'sd4312606;
        sine_lut[151] = -24'sd4487885;
        sine_lut[152] = -24'sd4660460;
        sine_lut[153] = -24'sd4830229;
        sine_lut[154] = -24'sd4997087;
        sine_lut[155] = -24'sd5160936;
        sine_lut[156] = -24'sd5321676;
        sine_lut[157] = -24'sd5479210;
        sine_lut[158] = -24'sd5633444;
        sine_lut[159] = -24'sd5784285;
        sine_lut[160] = -24'sd5931641;
        sine_lut[161] = -24'sd6075424;
        sine_lut[162] = -24'sd6215548;
        sine_lut[163] = -24'sd6351927;
        sine_lut[164] = -24'sd6484481;
        sine_lut[165] = -24'sd6613128;
        sine_lut[166] = -24'sd6737792;
        sine_lut[167] = -24'sd6858398;
        sine_lut[168] = -24'sd6974872;
        sine_lut[169] = -24'sd7087145;
        sine_lut[170] = -24'sd7195148;
        sine_lut[171] = -24'sd7298818;
        sine_lut[172] = -24'sd7398091;
        sine_lut[173] = -24'sd7492908;
        sine_lut[174] = -24'sd7583211;
        sine_lut[175] = -24'sd7668946;
        sine_lut[176] = -24'sd7750062;
        sine_lut[177] = -24'sd7826510;
        sine_lut[178] = -24'sd7898243;
        sine_lut[179] = -24'sd7965219;
        sine_lut[180] = -24'sd8027396;
        sine_lut[181] = -24'sd8084739;
        sine_lut[182] = -24'sd8137211;
        sine_lut[183] = -24'sd8184782;
        sine_lut[184] = -24'sd8227422;
        sine_lut[185] = -24'sd8265107;
        sine_lut[186] = -24'sd8297813;
        sine_lut[187] = -24'sd8325521;
        sine_lut[188] = -24'sd8348214;
        sine_lut[189] = -24'sd8365878;
        sine_lut[190] = -24'sd8378503;
        sine_lut[191] = -24'sd8386081;
        sine_lut[192] = -24'sd8388607;
        sine_lut[193] = -24'sd8386081;
        sine_lut[194] = -24'sd8378503;
        sine_lut[195] = -24'sd8365878;
        sine_lut[196] = -24'sd8348214;
        sine_lut[197] = -24'sd8325521;
        sine_lut[198] = -24'sd8297813;
        sine_lut[199] = -24'sd8265107;
        sine_lut[200] = -24'sd8227422;
        sine_lut[201] = -24'sd8184782;
        sine_lut[202] = -24'sd8137211;
        sine_lut[203] = -24'sd8084739;
        sine_lut[204] = -24'sd8027396;
        sine_lut[205] = -24'sd7965219;
        sine_lut[206] = -24'sd7898243;
        sine_lut[207] = -24'sd7826510;
        sine_lut[208] = -24'sd7750062;
        sine_lut[209] = -24'sd7668946;
        sine_lut[210] = -24'sd7583211;
        sine_lut[211] = -24'sd7492908;
        sine_lut[212] = -24'sd7398091;
        sine_lut[213] = -24'sd7298818;
        sine_lut[214] = -24'sd7195148;
        sine_lut[215] = -24'sd7087145;
        sine_lut[216] = -24'sd6974872;
        sine_lut[217] = -24'sd6858398;
        sine_lut[218] = -24'sd6737792;
        sine_lut[219] = -24'sd6613128;
        sine_lut[220] = -24'sd6484481;
        sine_lut[221] = -24'sd6351927;
        sine_lut[222] = -24'sd6215548;
        sine_lut[223] = -24'sd6075424;
        sine_lut[224] = -24'sd5931641;
        sine_lut[225] = -24'sd5784285;
        sine_lut[226] = -24'sd5633444;
        sine_lut[227] = -24'sd5479210;
        sine_lut[228] = -24'sd5321676;
        sine_lut[229] = -24'sd5160936;
        sine_lut[230] = -24'sd4997087;
        sine_lut[231] = -24'sd4830229;
        sine_lut[232] = -24'sd4660460;
        sine_lut[233] = -24'sd4487885;
        sine_lut[234] = -24'sd4312606;
        sine_lut[235] = -24'sd4134729;
        sine_lut[236] = -24'sd3954362;
        sine_lut[237] = -24'sd3771613;
        sine_lut[238] = -24'sd3586592;
        sine_lut[239] = -24'sd3399410;
        sine_lut[240] = -24'sd3210181;
        sine_lut[241] = -24'sd3019018;
        sine_lut[242] = -24'sd2826037;
        sine_lut[243] = -24'sd2631353;
        sine_lut[244] = -24'sd2435084;
        sine_lut[245] = -24'sd2237349;
        sine_lut[246] = -24'sd2038265;
        sine_lut[247] = -24'sd1837954;
        sine_lut[248] = -24'sd1636536;
        sine_lut[249] = -24'sd1434132;
        sine_lut[250] = -24'sd1230864;
        sine_lut[251] = -24'sd1026855;
        sine_lut[252] = -24'sd822227;
        sine_lut[253] = -24'sd617104;
        sine_lut[254] = -24'sd411609;
        sine_lut[255] = -24'sd205867;
    end

    // -------------------------------------------------------------------------
    // Per-slot pitch registers and phase accumulators
    // -------------------------------------------------------------------------
    logic [6:0]  pitch_reg  [0:NUM_SLOTS-1];
    logic [31:0] phase_acc  [0:NUM_SLOTS-1];

    // -------------------------------------------------------------------------
    // Frequency word from pitch LUT (Q17.15)
    // -------------------------------------------------------------------------
    logic [31:0] freq_fixed;
    pitch_to_freq u_p2f (
        .pitch      (pitch),
        .freq_fixed (freq_fixed)
    );

    // phase_inc = (freq_fixed * 89478) >> 15
    logic [47:0] phase_inc_wide;
    logic [31:0] phase_inc;
    assign phase_inc_wide = freq_fixed * 32'd89478;
    assign phase_inc      = phase_inc_wide[46:15];

    // -------------------------------------------------------------------------
    // Phase accumulator update: only the addressed slot advances
    // -------------------------------------------------------------------------
    integer s;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (s = 0; s < NUM_SLOTS; s++) begin
                pitch_reg[s] <= 7'd60;
                phase_acc[s] <= 32'd0;
            end
        end else if (slot_en) begin
            pitch_reg[slot_idx] <= pitch;
            phase_acc[slot_idx] <= phase_acc[slot_idx] + phase_inc;
        end
    end

    // -------------------------------------------------------------------------
    // Output: read the sine LUT for the currently addressed slot
    // Combinational read so sound_generator sees the sample in the same cycle
    // as slot_en (the accumulator was updated on the previous slot_en).
    // -------------------------------------------------------------------------
    assign sample_out = sine_lut[phase_acc[slot_idx][31:24]];

endmodule