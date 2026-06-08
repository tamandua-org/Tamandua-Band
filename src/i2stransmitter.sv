module i2stransmitter (
    input  logic        clk100mhz,
    input  logic        rst,

    input  logic        ready,
    input  logic [23:0] sample,

    output logic        mclk,
    output logic        sclk,
    output logic        lrclk,
    output logic        sdata
);

    transmitterClk mclkPll (
        .mclk      (mclk),
        .clk100mhz (clk100mhz)
    );

    logic [23:0] fifo_dout;
    logic        fifo_full;
    logic        fifo_empty;
    logic        fifo_wr_en;
    logic        fifo_rd_en;
    logic        fifo_wr_rst_busy;
    logic        fifo_rd_rst_busy;

    assign fifo_wr_en = ready && !fifo_full && !fifo_wr_rst_busy;

    cdcTransmitterFIFO cdcFifo (
        .rst         (rst),

        .wr_clk      (clk100mhz),
        .rd_clk      (mclk),

        .din         (sample),
        .wr_en       (fifo_wr_en),
        .rd_en       (fifo_rd_en),
        .dout        (fifo_dout),

        .full        (fifo_full),
        .empty       (fifo_empty),

        .wr_rst_busy (fifo_wr_rst_busy),
        .rd_rst_busy (fifo_rd_rst_busy)
    );

    logic [1:0] sclk_cnt;

    logic [23:0] current_sample;
    logic [31:0] shift_reg;
    logic [5:0]  bit_cnt;

    always_ff @(posedge mclk) begin
        if (rst) begin
            sclk           <= 1'b0;
            sclk_cnt       <= '0;

            bit_cnt        <= 6'd0;
            lrclk          <= 1'b0;
            sdata          <= 1'b0;
            shift_reg      <= 32'd0;
            current_sample <= 24'd0;
            fifo_rd_en     <= 1'b0;
        end
        else begin
            fifo_rd_en <= 1'b0;

            if (sclk_cnt == 1) begin
                sclk_cnt <= '0;
                sclk     <= ~sclk;

                if (sclk == 1'b1) begin

                    if (bit_cnt == 6'd0) begin
                        lrclk <= 1'b0; // left channel
                        sdata <= 1'b0; // I2S one-bit delay

                        if (!fifo_empty && !fifo_rd_rst_busy) begin
                            current_sample <= fifo_dout;
                            shift_reg      <= {fifo_dout, 8'h00};
                            fifo_rd_en     <= 1'b1;
                        end
                        else begin
                            shift_reg <= {current_sample, 8'h00};
                        end
                    end

                    else if (bit_cnt == 6'd32) begin
                        lrclk     <= 1'b1; // right channel
                        sdata     <= 1'b0; // I2S one-bit delay
                        shift_reg <= {current_sample, 8'h00};
                    end

                    else begin
                        sdata     <= shift_reg[31];
                        shift_reg <= {shift_reg[30:0], 1'b0};
                    end

                    bit_cnt <= bit_cnt + 1'b1;
                end
            end
            else begin
                sclk_cnt <= sclk_cnt + 1'b1;
            end
        end
    end

endmodule