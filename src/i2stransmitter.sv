module i2s_transmitter (
    input  logic        clk100mhz,
    input  logic        rst,

    input  logic        ready,
    input  logic [23:0] sample,

    output logic        mclk,
    output logic        sclk,
    output logic        lrclk,
    output logic        sdata
);

    transmitterClk mclkPll (.mclk, .clk100mhz);

    // ----------------------------------------------------------------
    //  SCLK: divide mclk por 4
    // ----------------------------------------------------------------
    logic [1:0] sclk_div;
    always_ff @(posedge mclk) begin
        if (rst) begin
            sclk_div <= 0;
            sclk     <= 0;
        end else begin
            sclk_div <= sclk_div + 1'b1;
            if (sclk_div == 2'd1)
                sclk <= ~sclk;
        end
    end

    logic sclkFall;
    edgeDetector #(.XPOL(0)) sclkEdgeDetector (.clk(mclk), .x(sclk), .xFall(sclkFall));

    // ----------------------------------------------------------------
    //  Pending sample - solo escrito desde clk100mhz
    // ----------------------------------------------------------------
    logic [23:0] pending_sample;
    logic        pending_valid;
    logic        sample_ack;     // pulso desde mclk: "ya cogí el sample"

    always_ff @(posedge clk100mhz) begin
        if (rst) begin
            pending_sample <= 24'd0;
            pending_valid  <= 1'b0;
        end else begin
            if (ready) begin
                pending_sample <= sample;
                pending_valid  <= 1'b1;
            end else if (sample_ack) begin
                pending_valid  <= 1'b0;  // único sitio donde se baja
            end
        end
    end

    // ----------------------------------------------------------------
    //  Shift register - dominio mclk
    // ----------------------------------------------------------------
    logic [23:0] current_sample;
    logic [31:0] shift_reg;
    logic [5:0]  bit_cnt;

    always_ff @(posedge mclk) begin
        if (rst) begin
            bit_cnt        <= '0;
            shift_reg      <= '0;
            lrclk          <= 1'b0;
            sdata          <= 1'b0;
            current_sample <= 24'd0;
            sample_ack     <= 1'b0;
        end
        else begin
            sample_ack <= 1'b0;  // pulso de un ciclo por defecto

            if (sclkFall) begin

                if (bit_cnt == 6'd0) begin
                    if (pending_valid) begin
                        current_sample <= pending_sample;
                        sample_ack     <= 1'b1;  // avisar al dominio clk100mhz
                    end
                    lrclk <= 1'b0;
                end

                if (bit_cnt == 6'd32)
                    lrclk <= 1'b1;

                if (bit_cnt == 6'd0 || bit_cnt == 6'd32)
                    shift_reg <= { 1'b0, current_sample, 7'h00 };
                else begin
                    sdata     <= shift_reg[31];
                    shift_reg <= { shift_reg[30:0], 1'b0 };
                end

                bit_cnt <= bit_cnt + 1'b1;
            end
        end
    end

endmodule