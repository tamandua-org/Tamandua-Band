// =============================================================================
// pitch_to_freq.sv
// -----------------------------------------------------------------------------
// Converts a 7-bit MIDI pitch (0-127) to a fixed-point frequency value.
//
// Formula: freq_hz = 440.0 * 2^((pitch - 69) / 12)
// Output format: Q17.15  →  freq_fixed = round(freq_hz * 2^15)
//
// All 128 values computed exactly in Python with full float64 precision.
// Key reference points:
//   pitch 57 (A4) =  220.0000 Hz → freq_fixed =  7208960  (exact: 220*32768)
//   pitch 69 (A5) =  440.0000 Hz → freq_fixed = 14417920  (exact: 440*32768)
//   pitch 60 (C5) =  261.6256 Hz → freq_fixed =  8572947
// =============================================================================

module pitch_to_freq (
    input  logic [6:0]  pitch,      // MIDI note number 0-127
    output logic [31:0] freq_fixed  // Q17.15 fixed-point frequency
);

    always_comb begin
        case (pitch)
            7'd0: freq_fixed = 32'd267905;  // 8.1758 Hz
            7'd1: freq_fixed = 32'd283835;  // 8.6620 Hz
            7'd2: freq_fixed = 32'd300713;  // 9.1770 Hz
            7'd3: freq_fixed = 32'd318594;  // 9.7227 Hz
            7'd4: freq_fixed = 32'd337539;  // 10.3009 Hz
            7'd5: freq_fixed = 32'd357610;  // 10.9134 Hz
            7'd6: freq_fixed = 32'd378874;  // 11.5623 Hz
            7'd7: freq_fixed = 32'd401403;  // 12.2499 Hz
            7'd8: freq_fixed = 32'd425272;  // 12.9783 Hz
            7'd9: freq_fixed = 32'd450560;  // 13.7500 Hz
            7'd10: freq_fixed = 32'd477352;  // 14.5676 Hz
            7'd11: freq_fixed = 32'd505737;  // 15.4339 Hz
            7'd12: freq_fixed = 32'd535809;  // 16.3516 Hz
            7'd13: freq_fixed = 32'd567670;  // 17.3239 Hz
            7'd14: freq_fixed = 32'd601425;  // 18.3540 Hz
            7'd15: freq_fixed = 32'd637188;  // 19.4454 Hz
            7'd16: freq_fixed = 32'd675077;  // 20.6017 Hz
            7'd17: freq_fixed = 32'd715219;  // 21.8268 Hz
            7'd18: freq_fixed = 32'd757749;  // 23.1247 Hz
            7'd19: freq_fixed = 32'd802807;  // 24.4997 Hz
            7'd20: freq_fixed = 32'd850544;  // 25.9565 Hz
            7'd21: freq_fixed = 32'd901120;  // 27.5000 Hz
            7'd22: freq_fixed = 32'd954703;  // 29.1352 Hz
            7'd23: freq_fixed = 32'd1011473;  // 30.8677 Hz
            7'd24: freq_fixed = 32'd1071618;  // 32.7032 Hz
            7'd25: freq_fixed = 32'd1135340;  // 34.6478 Hz
            7'd26: freq_fixed = 32'd1202851;  // 36.7081 Hz
            7'd27: freq_fixed = 32'd1274376;  // 38.8909 Hz
            7'd28: freq_fixed = 32'd1350154;  // 41.2034 Hz
            7'd29: freq_fixed = 32'd1430439;  // 43.6535 Hz
            7'd30: freq_fixed = 32'd1515497;  // 46.2493 Hz
            7'd31: freq_fixed = 32'd1605613;  // 48.9994 Hz
            7'd32: freq_fixed = 32'd1701088;  // 51.9131 Hz
            7'd33: freq_fixed = 32'd1802240;  // 55.0000 Hz
            7'd34: freq_fixed = 32'd1909407;  // 58.2705 Hz
            7'd35: freq_fixed = 32'd2022946;  // 61.7354 Hz
            7'd36: freq_fixed = 32'd2143237;  // 65.4064 Hz
            7'd37: freq_fixed = 32'd2270680;  // 69.2957 Hz
            7'd38: freq_fixed = 32'd2405702;  // 73.4162 Hz
            7'd39: freq_fixed = 32'd2548752;  // 77.7817 Hz
            7'd40: freq_fixed = 32'd2700309;  // 82.4069 Hz
            7'd41: freq_fixed = 32'd2860878;  // 87.3071 Hz
            7'd42: freq_fixed = 32'd3030994;  // 92.4986 Hz
            7'd43: freq_fixed = 32'd3211227;  // 97.9989 Hz
            7'd44: freq_fixed = 32'd3402176;  // 103.8262 Hz
            7'd45: freq_fixed = 32'd3604480;  // 110.0000 Hz
            7'd46: freq_fixed = 32'd3818814;  // 116.5409 Hz
            7'd47: freq_fixed = 32'd4045892;  // 123.4708 Hz
            7'd48: freq_fixed = 32'd4286473;  // 130.8128 Hz
            7'd49: freq_fixed = 32'd4541360;  // 138.5913 Hz
            7'd50: freq_fixed = 32'd4811404;  // 146.8324 Hz
            7'd51: freq_fixed = 32'd5097505;  // 155.5635 Hz
            7'd52: freq_fixed = 32'd5400618;  // 164.8138 Hz
            7'd53: freq_fixed = 32'd5721755;  // 174.6141 Hz
            7'd54: freq_fixed = 32'd6061989;  // 184.9972 Hz
            7'd55: freq_fixed = 32'd6422453;  // 195.9977 Hz
            7'd56: freq_fixed = 32'd6804352;  // 207.6523 Hz
            7'd57: freq_fixed = 32'd7208960;  // 220.0000 Hz
            7'd58: freq_fixed = 32'd7637627;  // 233.0819 Hz
            7'd59: freq_fixed = 32'd8091784;  // 246.9417 Hz
            7'd60: freq_fixed = 32'd8572947;  // 261.6256 Hz
            7'd61: freq_fixed = 32'd9082720;  // 277.1826 Hz
            7'd62: freq_fixed = 32'd9622807;  // 293.6648 Hz
            7'd63: freq_fixed = 32'd10195009;  // 311.1270 Hz
            7'd64: freq_fixed = 32'd10801236;  // 329.6276 Hz
            7'd65: freq_fixed = 32'd11443511;  // 349.2282 Hz
            7'd66: freq_fixed = 32'd12123977;  // 369.9944 Hz
            7'd67: freq_fixed = 32'd12844906;  // 391.9954 Hz
            7'd68: freq_fixed = 32'd13608704;  // 415.3047 Hz
            7'd69: freq_fixed = 32'd14417920;  // 440.0000 Hz
            7'd70: freq_fixed = 32'd15275254;  // 466.1638 Hz
            7'd71: freq_fixed = 32'd16183568;  // 493.8833 Hz
            7'd72: freq_fixed = 32'd17145893;  // 523.2511 Hz
            7'd73: freq_fixed = 32'd18165441;  // 554.3653 Hz
            7'd74: freq_fixed = 32'd19245614;  // 587.3295 Hz
            7'd75: freq_fixed = 32'd20390018;  // 622.2540 Hz
            7'd76: freq_fixed = 32'd21602472;  // 659.2551 Hz
            7'd77: freq_fixed = 32'd22887021;  // 698.4565 Hz
            7'd78: freq_fixed = 32'd24247954;  // 739.9888 Hz
            7'd79: freq_fixed = 32'd25689813;  // 783.9909 Hz
            7'd80: freq_fixed = 32'd27217409;  // 830.6094 Hz
            7'd81: freq_fixed = 32'd28835840;  // 880.0000 Hz
            7'd82: freq_fixed = 32'd30550508;  // 932.3275 Hz
            7'd83: freq_fixed = 32'd32367136;  // 987.7666 Hz
            7'd84: freq_fixed = 32'd34291786;  // 1046.5023 Hz
            7'd85: freq_fixed = 32'd36330882;  // 1108.7305 Hz
            7'd86: freq_fixed = 32'd38491228;  // 1174.6591 Hz
            7'd87: freq_fixed = 32'd40780036;  // 1244.5079 Hz
            7'd88: freq_fixed = 32'd43204943;  // 1318.5102 Hz
            7'd89: freq_fixed = 32'd45774043;  // 1396.9129 Hz
            7'd90: freq_fixed = 32'd48495909;  // 1479.9777 Hz
            7'd91: freq_fixed = 32'd51379626;  // 1567.9817 Hz
            7'd92: freq_fixed = 32'd54434817;  // 1661.2188 Hz
            7'd93: freq_fixed = 32'd57671680;  // 1760.0000 Hz
            7'd94: freq_fixed = 32'd61101017;  // 1864.6550 Hz
            7'd95: freq_fixed = 32'd64734272;  // 1975.5332 Hz
            7'd96: freq_fixed = 32'd68583572;  // 2093.0045 Hz
            7'd97: freq_fixed = 32'd72661764;  // 2217.4610 Hz
            7'd98: freq_fixed = 32'd76982457;  // 2349.3181 Hz
            7'd99: freq_fixed = 32'd81560072;  // 2489.0159 Hz
            7'd100: freq_fixed = 32'd86409886;  // 2637.0205 Hz
            7'd101: freq_fixed = 32'd91548086;  // 2793.8259 Hz
            7'd102: freq_fixed = 32'd96991818;  // 2959.9554 Hz
            7'd103: freq_fixed = 32'd102759252;  // 3135.9635 Hz
            7'd104: freq_fixed = 32'd108869635;  // 3322.4376 Hz
            7'd105: freq_fixed = 32'd115343360;  // 3520.0000 Hz
            7'd106: freq_fixed = 32'd122202033;  // 3729.3101 Hz
            7'd107: freq_fixed = 32'd129468544;  // 3951.0664 Hz
            7'd108: freq_fixed = 32'd137167144;  // 4186.0090 Hz
            7'd109: freq_fixed = 32'd145323527;  // 4434.9221 Hz
            7'd110: freq_fixed = 32'd153964914;  // 4698.6363 Hz
            7'd111: freq_fixed = 32'd163120144;  // 4978.0317 Hz
            7'd112: freq_fixed = 32'd172819773;  // 5274.0409 Hz
            7'd113: freq_fixed = 32'd183096171;  // 5587.6517 Hz
            7'd114: freq_fixed = 32'd193983636;  // 5919.9108 Hz
            7'd115: freq_fixed = 32'd205518503;  // 6271.9270 Hz
            7'd116: freq_fixed = 32'd217739269;  // 6644.8752 Hz
            7'd117: freq_fixed = 32'd230686720;  // 7040.0000 Hz
            7'd118: freq_fixed = 32'd244404066;  // 7458.6202 Hz
            7'd119: freq_fixed = 32'd258937088;  // 7902.1328 Hz
            7'd120: freq_fixed = 32'd274334289;  // 8372.0181 Hz
            7'd121: freq_fixed = 32'd290647054;  // 8869.8442 Hz
            7'd122: freq_fixed = 32'd307929828;  // 9397.2726 Hz
            7'd123: freq_fixed = 32'd326240288;  // 9956.0635 Hz
            7'd124: freq_fixed = 32'd345639545;  // 10548.0818 Hz
            7'd125: freq_fixed = 32'd366192342;  // 11175.3034 Hz
            7'd126: freq_fixed = 32'd387967272;  // 11839.8215 Hz
            7'd127: freq_fixed = 32'd411037006;  // 12543.8540 Hz
            default: freq_fixed = 32'd8572947;  // fallback: C5
        endcase
    end

endmodule