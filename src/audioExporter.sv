module audioExporter #(
    parameter int FREQ_KHZ = 100_000,
    parameter int BAUDRATE = 2_000_000
)(
    input  logic        clk,
    input  logic        rst,

    // Status flags from dawController
    input  logic        mode_export,
    input  logic        is_playing,

    // Audio stream from dspAudioEngine
    input  logic        audio_out_valid,
    input  logic [23:0] sample,

    // Physical UART Output
    output logic        TxD
);

    // --- Internal UART Signals ---
    logic       readEnable;
    logic [7:0] dataFifoOut;
    logic       busy;

    // --- Export FSM Registers ---
    logic [23:0] export_sample_reg;

    typedef enum logic [2:0] { 
        UART_IDLE, 
        UART_START_B0, UART_WAIT_B0, 
        UART_START_B1, UART_WAIT_B1, 
        UART_START_B2, UART_WAIT_B2 
    } uart_state_t;

    uart_state_t uart_state;

    always_ff @(posedge clk) begin
        if (rst) begin
            uart_state <= UART_IDLE;
            readEnable <= 1'b0;
            export_sample_reg <= '0;
            dataFifoOut <= '0;
        end else begin
            readEnable <= 1'b0; // Default off to ensure clean 1-cycle pulses

            case (uart_state)
                UART_IDLE: begin
                    // Lock the sample when the engine is actively playing in export mode
                    if (mode_export && is_playing && audio_out_valid) begin
                        export_sample_reg <= sample; 
                        uart_state        <= UART_START_B0;
                    end
                end
                
                // --- SEND BYTE 0 (LSB First for native .wav compatibility) ---
                UART_START_B0: begin
                    if (!busy) begin
                        dataFifoOut <= export_sample_reg[7:0];
                        readEnable  <= 1'b1;
                        uart_state  <= UART_WAIT_B0;
                    end
                end
                // Wait for the UART to acknowledge the byte and raise the busy flag
                UART_WAIT_B0: if (busy) uart_state <= UART_START_B1; 

                // --- SEND BYTE 1 (Middle) ---
                UART_START_B1: begin
                    if (!busy) begin
                        dataFifoOut <= export_sample_reg[15:8];
                        readEnable  <= 1'b1;
                        uart_state  <= UART_WAIT_B1;
                    end
                end
                UART_WAIT_B1: if (busy) uart_state <= UART_START_B2;

                // --- SEND BYTE 2 (MSB Last) ---
                UART_START_B2: begin
                    if (!busy) begin
                        dataFifoOut <= export_sample_reg[23:16];
                        readEnable  <= 1'b1;
                        uart_state  <= UART_WAIT_B2;
                    end
                end
                // Once the final byte is acknowledged, wait for the next audio sample
                UART_WAIT_B2: if (busy) uart_state <= UART_IDLE; 
            endcase
        end
    end

    rs232transmitter #(
        .FREQ_KHZ(FREQ_KHZ),
        .BAUDRATE(BAUDRATE)
    ) transmitter (
        .clk(clk), 
        .rst(rst), 
        .dataRdy(readEnable), 
        .data(dataFifoOut), 
        .busy(busy), 
        .TxD(TxD)
    );

endmodule