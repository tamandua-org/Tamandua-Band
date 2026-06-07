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

     // ------------------------------------------------------------------
    // Master clock PLL / clock wizard
    // ------------------------------------------------------------------
    transmitterClk mclkPll (
        .mclk      (mclk),
        .clk100mhz (clk100mhz)
    );

    // ------------------------------------------------------------------
    // CDC with Vivado FIFO Generator IP
    // ------------------------------------------------------------------
    // Create this IP from Vivado IP Catalog with this component/module name:
    //
    //     audio_sample_fifo
    //
    // Recommended settings:
    //   Interface Type      : Native
    //   FIFO Implementation : Independent Clocks Block RAM
    //   Write Clock         : clk100mhz
    //   Read Clock          : mclk
    //   Write Width         : 24
    //   Read Width          : 24
    //   Write Depth         : 16 or 32
    //   Read Mode           : First Word Fall Through
    //   Reset Type          : Asynchronous reset
    //   Optional ports      : enable wr_rst_busy and rd_rst_busy
    //
    // Why FWFT:
    //   In First Word Fall Through mode, when empty == 0, fifo_dout already
    //   contains the next valid sample. Therefore, the I2S side can latch
    //   fifo_dout directly at bit_cnt == 0 and pulse rd_en to consume it.
    // ------------------------------------------------------------------

    logic [23:0] fifo_dout;
    logic        fifo_full;
    logic        fifo_empty;
    logic        fifo_wr_en;
    logic        fifo_rd_en;
    logic        fifo_wr_rst_busy;
    logic        fifo_rd_rst_busy;

    // One write per ready pulse. If the FIFO is full, the sample is dropped.
    // In the normal design ready should pulse once per audio frame, so the
    // FIFO should not fill unless the producer is running too fast.
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
            // FIFO read enable must be a one-mclk-cycle pulse.
            fifo_rd_en <= 1'b0;

            // ----------------------------------------------------------
            // Generate SCLK from MCLK.
            // Data changes when SCLK is falling, so the DAC can sample it
            // on the rising edge.
            // ----------------------------------------------------------
            if (sclk_cnt == 1) begin
                sclk_cnt <= '0;
                sclk     <= ~sclk;

                // Old sclk == 1 means this mclk edge creates an SCLK fall.
                if (sclk == 1'b1) begin

                    // --------------------------------------------------
                    // bit_cnt == 0: start of left channel / stereo frame.
                    //
                    // Read exactly one new sample from the FIFO here.
                    // Do not read another sample at bit_cnt == 32, because
                    // that would make left and right channels use different
                    // samples and double the effective consumption rate.
                    //
                    // I2S needs a one-SCLK delay after LRCLK changes.
                    // Therefore we load the shift register here and keep
                    // SDATA at 0. The MSB is transmitted at bit_cnt == 1.
                    //
                    // Important: do NOT prepend 1'b0 to the sample. The
                    // delay is made by this idle bit, not by shifting the
                    // sample itself. Prepending 0 corrupts signed samples.
                    // --------------------------------------------------
                    if (bit_cnt == 6'd0) begin
                        lrclk <= 1'b0; // left channel
                        sdata <= 1'b0; // I2S one-bit delay

                        if (!fifo_empty && !fifo_rd_rst_busy) begin
                            current_sample <= fifo_dout;
                            shift_reg      <= {fifo_dout, 8'h00};
                            fifo_rd_en     <= 1'b1;
                        end
                        else begin
                            // If no new sample is available, repeat the
                            // previous one instead of outputting a click.
                            shift_reg <= {current_sample, 8'h00};
                        end
                    end

                    // --------------------------------------------------
                    // bit_cnt == 32: start of right channel.
                    // Send the same sample again, so mono audio appears on
                    // both left and right outputs.
                    // --------------------------------------------------
                    else if (bit_cnt == 6'd32) begin
                        lrclk     <= 1'b1; // right channel
                        sdata     <= 1'b0; // I2S one-bit delay
                        shift_reg <= {current_sample, 8'h00};
                    end

                    // --------------------------------------------------
                    // bit_cnt 1..31 and 33..63: transmit MSB first.
                    // For a 24-bit sample in a 32-bit slot, the 7 remaining
                    // transmitted bits after sample[0] are zero padding.
                    // --------------------------------------------------
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