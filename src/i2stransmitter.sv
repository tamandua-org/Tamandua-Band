module i2s_transmitter (
    input  logic        clk100mhz,
    input  logic        rst,

    // User interface
    input  logic        ready,       // pulse high for one clk_100m cycle when sample is valid
    input  logic [23:0] sample,      // 24-bit signed audio sample

    // I2S outputs
    output logic        mclk,
    output logic        sclk,
    output logic        lrclk,
    output logic        sdata
);
    
    transmitterClk mclkPll (.mclk, .clk100mhz);
    
    logic [1:0] sclk_div;
    always_ff @(posedge mclk) begin
        if (rst) begin
            sclk_div <= 0;
            sclk     <= 0;
        end
        else begin
            sclk_div <= sclk_div + 1'b1;

            if (sclk_div == 2'd1)
                sclk <= ~sclk;
        end
    end
    
    logic sclkFall;
    edgeDetector #(.XPOL(0)) sclkEdgeDetector (.clk(mclk), .x(sclk), .xFall(sclkFall));

    logic [23:0] pending_sample;
    logic pending_valid;

    logic [23:0] current_sample;

    always_ff @(posedge clk100mhz) begin
        if (rst) begin
            pending_sample <= 24'd0;
            pending_valid  <= 1'b0;
        end
        else begin
            if (ready) begin
                pending_sample <= sample;
                pending_valid  <= 1'b1;
            end
        end
    end

    logic [31:0] shift_reg;
    logic [5:0]  bit_cnt;

    always_ff @(posedge mclk) begin
        if (rst) begin
            bit_cnt <= '0;
            shift_reg <= '0;

            lrclk <= 1'b0;
            sdata <= 1'b0;

            current_sample <= 24'd0;
        end
        else begin

            ////////////////////////////////////////////////////
            // Only update on SCLK falling edge
            //
            // I2S changes data on falling edge
            // Receiver samples on rising edge
            ////////////////////////////////////////////////////

            if (sclkFall) begin
                // START OF FRAME
                if (bit_cnt == 6'd0) begin // left channel
                    // Safely swap in newest sample
                    if (pending_valid) begin
                        current_sample <= pending_sample;
                        pending_valid  <= 1'b0;
                    end

                    shift_reg <= { 1'b0, current_sample, 7'h00 }; // bit delay + sample + padding
                    
                    lrclk <= 1'b0;
                end
                
                if (bit_cnt == 6'd32) begin // right channel
                    lrclk <= 1'b1;
                    shift_reg <= { 1'b0, current_sample, 7'h00 }; // bit delay + sample + padding
                end

                sdata <= shift_reg[31];

                shift_reg <= { shift_reg[30:0], 1'b0 };

                bit_cnt <= bit_cnt + 1'b1;
            end
        end
    end

//    logic [4:0] lrclk_counter = '0;

//    always_ff @(posedge sclk) begin
//        if (rst) begin
//            lrclk_counter <= '0;
//            lrclk <= '0;
//        end else begin
//            lrclk_counter <= lrclk_counter + 1'b1;
//            if (lrclk_counter == 5'd31)
//                lrclk <= ~lrclk;
//        end
//    end


//    logic [23:0] current_sample;
//    logic [31:0] shift_reg;
//    logic [5:0] bit_cnt;
    
//    logic sample_pending  = 1'b0;
//    logic frame_started;

//    assign frame_started = (bit_cnt != '0);

//    always_ff @(posedge clk100mhz) begin
//        if (rst || !sample_pending && !frame_started) begin
//            current_sample <= '0;
//            sample_pending <= '0;
//        end else begin
//            if (ready) begin
//                current_sample <= sample;
//                sample_pending <= 1'b1;
//            end else if (frame_started)
//                sample_pending <= 1'b0;
//        end
//    end
    
//    // Shift register and SDATA
//    always_ff @(negedge sclk) begin
//        if (rst || !ready && !frame_started) begin
//            bit_cnt   <= '0;
//            shift_reg <= '0;
//            sdata     <= '0;
//        end else begin
//            if (bit_cnt == 6'd0)        // left channel
//                shift_reg <= {current_sample, 8'h00};
//            else if (bit_cnt == 6'd32)  // right channel
//                shift_reg <= {current_sample, 8'h00};

//            // MSB a LSB
//            sdata     <= shift_reg[31];
//            shift_reg <= {shift_reg[30:0], 1'b0};

//            bit_cnt <= bit_cnt + 1;
//        end
//    end

endmodule