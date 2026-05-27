import daw_pkg::*;

module tamanduaBand (
    input  logic        clk,
    input  logic        rst,
    input  logic        ps2Clk,
    input  logic        ps2Data,
    
    output logic        mclk,
    output logic        lrclk,
    output logic        sclk,
    output logic        sdata,
    output logic        hSync,
    output logic        vSync,
    output logic [11:0] RGB
);

    localparam int FREQ_KHZ = 100_000;
    localparam int VGA_KHZ  = 25_000;
    localparam int FREQ_DIV = FREQ_KHZ / VGA_KHZ;
    
    logic rstSync;
    
    synchronizer #(.STAGES(2), .XPOL('0)) rstSynchronizer (.clk(clk), .x(rst), .xSync (rstSync));
    
    logic [7:0] key;
    logic keyRdy;
    
    ps2receiver ps2KeyboardInterface (.clk(clk), .rst(rstSync), .dataRdy(keyRdy), .data(key), .ps2Clk(ps2Clk), .ps2Data(ps2Data));
    
    logic semiquaver_tick;
    logic [7:0] bpm_out;
    
    bpmClockDivider #(.CLK_FREQ_HZ(FREQ_KHZ * 1000)) bpmClkGen (
        .clk(clk), 
        .rst(rstSync), 
        .bpmRequired(1'b1), // for now kept at 1
        .currentBpm(bpm_out), 
        .semiquaver_tick(semiquaver_tick)
    );
    
    logic [NUM_PATTERNS-1:0]    mute_mask;
    logic [PATTERN_ID_BITS-1:0] ui_active_pattern;
    instrument_t                ui_active_instrument;
    note_delta_t                ui_active_note_slot;
    logic                       is_playing;
    logic step_forward_pulse;
    logic step_backward_pulse;
    logic                       mode_normal, mode_live, mode_record;
    logic                       clear_pattern_pulse;
    logic                       live_note_on, live_note_off;
    note_delta_t                live_pitch;
    logic                       ram_write_enable;
    
    dawController controller (
        .clk(clk), 
        .rst(rstSync), 
        .keyRdy(keyRdy), 
        .key(key), 
        .semiquaver_tick(semiquaver_tick),
        // Outputs
        .mute_mask(mute_mask),
        .ui_active_pattern(ui_active_pattern),
        .ui_active_instrument(ui_active_instrument),
        .ui_active_note_slot(ui_active_note_slot),
        .bpm_out,
        .is_playing(is_playing),
        .step_forward_pulse(step_forward_pulse),
        .step_backward_pulse(step_backward_pulse),
        .mode_normal(mode_normal),
        .mode_live(mode_live),
        .mode_record(mode_record),
        .clear_pattern_pulse(clear_pattern_pulse),
        .live_note_on(live_note_on),
        .live_note_off(live_note_off),
        .live_pitch(live_pitch)
    );

    instrument_t instrument_regs [NUM_PATTERNS];

    always_ff @(posedge clk) begin
        if (rstSync) begin
            for (int i = 0; i < NUM_PATTERNS; i++) begin
                instrument_regs[i] <= PIANO;
            end
        end else begin
            instrument_regs[ui_active_pattern] <= ui_active_instrument; // save changed instrument to the current pattern
        end
    end
    
    logic [5:0]  current_playback_step;
    logic        engine_req;
    logic [9:0]  engine_addr;
    pattern_col_t engine_rdata;
    logic        engine_valid;
    
    // outputs for voice allocator
    note_event_t note_on_event, note_off_event;
    logic        note_on_valid, note_off_valid;
    
    patternEngine engine (
        .clk(clk),
        .rst(rstSync),
        .semiquaver_tick(semiquaver_tick),
        .is_playing(is_playing),
        .step_forward_pulse(step_forward_pulse),
        .step_backward_pulse(step_backward_pulse),
        .mute_mask(mute_mask),
        .current_playback_step(current_playback_step),
        
        // handshake interface to BRAM
        .ram_req(engine_req),
        .ram_addr(engine_addr),
        .ram_rdata(engine_rdata),
        .ram_valid(engine_valid),
        
        .instrument_regs(instrument_regs), //we give access to the registers to the pattern engine
        
        .note_on_event(note_on_event),
        .note_on_valid(note_on_valid),
        .note_off_event(note_off_event),
        .note_off_valid(note_off_valid)
    );
    
    logic         ui_req   = 1'b0;
    logic [9:0]   ui_addr  = '0;
    pattern_col_t ui_rdata;
    logic         ui_valid;

    patternRamWrapper memory_wrapper (
        .clk(clk),
        .rst(rstSync),
        
        // Port A.1 pattern engine
        .engine_req(engine_req),
        .engine_addr(engine_addr),
        .engine_rdata(engine_rdata),
        .engine_valid(engine_valid),
        
        // Port A.2 UI
        .ui_req(ui_req),
        .ui_addr(ui_addr),
        .ui_rdata(ui_rdata),
        .ui_valid(ui_valid),
        
        // Port B live writes for record mode
        .semiquaver_tick(semiquaver_tick),
        .record_mode(mode_record), // Map mode_record to the record_mode input
        .current_playback_step(current_playback_step),
        .live_note_on(live_note_on),
        .live_note_off(live_note_off),
        .live_pitch(live_pitch),
        .clear_pattern_pulse(clear_pattern_pulse),
        .ui_active_pattern(ui_active_pattern)
    );
    
    i2s_transmitter i2stransmitter (.clk100mhz(clk), .rst(rstSync), .ready(), .sample(), .mclk, .sclk, .lrclk, .sdata);

endmodule