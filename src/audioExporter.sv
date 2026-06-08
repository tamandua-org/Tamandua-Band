module audioExporter #(
    parameter int FREQ_KHZ = 100_000,
    parameter int BAUDRATE = 921_600
    // FIFO depth is set inside the exportFIFO IP.
    // Target: ceil((48000 - BAUDRATE/20) × max_seconds) ? 32768 for 16 s
)(
    input  logic        clk,
    input  logic        rst,
    input  logic        mode_export,
    input  logic        is_playing,
    input  logic        audio_out_valid,
    input  logic [23:0] sample,
    output logic        TxD
);

    typedef enum logic [2:0] {
        IDLE,
        FETCH,                  // assert rd_en; fifo_dout valid next cycle
        SEND_B0, WAIT_B0,
        SEND_B1, WAIT_B1
    } state_t;
    state_t state;


    logic        fifo_wr_en;
    logic        fifo_rd_en;
    logic        fifo_full;
    logic        fifo_empty;
    logic [15:0] fifo_dout;

    assign fifo_wr_en = (state != IDLE) && is_playing && audio_out_valid && !fifo_full;
    assign fifo_rd_en = (state == FETCH) && !fifo_empty;

    exportFIFO exportQueue (
        .clk   (clk),
        .srst  (rst),               // reset only on hard reset; FSM drains before IDLE
        .din   (sample[23:8]),      // top 16 bits of 24-bit sample
        .wr_en (fifo_wr_en),
        .rd_en (fifo_rd_en),
        .dout  (fifo_dout),
        .full  (fifo_full),
        .empty (fifo_empty)
    );


    logic        readEnable;
    logic [7:0]  dataOut;
    logic        busy;
    logic [15:0] tx_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= IDLE;
            readEnable <= '0;
            dataOut    <= '0;
            tx_reg     <= '0;
        end else begin
            readEnable <= '0;

            case (state)
                IDLE: begin
                    if (mode_export && is_playing)
                        state <= FETCH;
                end

                FETCH: begin
                    if (!fifo_empty)
                        state <= SEND_B0;       // rd_en fired; dout valid next cycle
                    else if (!is_playing)
                        state <= IDLE;          // drained and done
                    // else: FIFO empty but still playing - spin and wait
                end

                SEND_B0: begin                  // fifo_dout valid here
                    if (!busy) begin
                        tx_reg     <= fifo_dout;
                        dataOut    <= fifo_dout[7:0];   // LSB first ? WAV little-endian
                        readEnable <= 1'b1;
                        state      <= WAIT_B0;
                    end
                end

                WAIT_B0: if (busy) state <= SEND_B1;

                SEND_B1: begin
                    if (!busy) begin
                        dataOut    <= tx_reg[15:8];     // MSB
                        readEnable <= 1'b1;
                        state      <= WAIT_B1;
                    end
                end

                WAIT_B1: if (busy) state <= FETCH;

                default: state <= IDLE;
            endcase
        end
    end

    rs232transmitter #(
        .FREQ_KHZ(FREQ_KHZ),
        .BAUDRATE(BAUDRATE)
    ) transmitter (
        .clk    (clk),
        .rst    (rst),
        .dataRdy(readEnable),
        .data   (dataOut),
        .busy   (busy),
        .TxD    (TxD)
    );
endmodule