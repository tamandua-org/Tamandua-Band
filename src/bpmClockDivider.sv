import daw_pkg::BPM_BITS;

module bpmClockDivider #(
    parameter int CLK_FREQ_HZ = 100_000_000
) (
    input  logic                clk,
    input  logic                rst,
    input  logic bpmRequired,
    input  logic [BPM_BITS-1:0] currentBpm,         // current BPM (runtime)
    output logic                semiquaver_tick  // one-cycle pulse per semiquaver
);
    
    // we have bpm / 60 x 4 semiquavers/second. 
    // this means we have 60 / (bpm x 4) semiquavers in a second => 15 / bmp semiquavers in a second
    // with a 100 MHz clk, we have 100'000'000 x 15 / bmp cycles for a semiquaver
    // 1'500'000'000 fits in 32 bits
    
    localparam int unsigned TICKS_NUMERATOR = CLK_FREQ_HZ * 15; // 100'000'000 x 15
    
    logic [31:0] period_rom [0:254];
    initial begin
        for (int i = 0; i <= 254; i++) begin
            period_rom[i] = TICKS_NUMERATOR / (i+1);
        end
    end

    logic [31:0] period;      
    logic [31:0] counter;
    
    always_ff @(posedge clk) begin
        period <= period_rom[currentBpm-1];
    end
 
    always_ff @(posedge clk) begin
        if (rst || !bpmRequired) begin
            counter <= 32'd0;
            semiquaver_tick <= 1'b0;
        end else begin
            semiquaver_tick <= 1'b0; // default: no tick
 
            if (counter == 32'd0) begin
                semiquaver_tick <= 1'b1;
                counter <= period - 32'd1;
            end else begin
                counter <= counter - 32'd1;
            end
        end
    end
 
endmodule
