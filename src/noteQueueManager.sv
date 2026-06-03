import daw_pkg::*;

module noteQueueManager (
    input  logic        clk,
    input  logic        rst,
    
    // live stream (from dawController)
    input  logic        live_valid,
    input  note_event_t live_event,
    
    // sequencer stream (from patternEngine)
    input  logic        seq_valid,
    input  note_event_t seq_event,
    
    // to dsp engine
    input  logic        fifo_rd_en,
    output note_event_t fifo_dout,
    output logic        fifo_empty
);

    // fifo writing
    logic        fifo_wr_en;
    note_event_t fifo_din;
    logic        fifo_full;

    logic        pending_live_valid;
    note_event_t pending_live_event;

    always_ff @(posedge clk) begin
        if (rst) begin
            fifo_wr_en         <= 1'b0;
            fifo_din           <= '0;
            pending_live_valid <= 1'b0;
            pending_live_event <= '0;
        end else begin
            fifo_wr_en <= 1'b0; // Default

            // if fifo full we drop incoming packets (should never happen with a fifo size 16) if we can process/II an item per cycle
            if (!fifo_full) begin
                
                if (seq_valid) begin // we give higher priority to seq since live notes happen at a much lower rate (ps2 @ ~16KHz)
                    fifo_wr_en <= 1'b1;
                    fifo_din   <= seq_event;
                                       
                    if (live_valid) begin // if collision store live event
                        pending_live_valid <= 1'b1;
                        pending_live_event <= live_event;
                    end
                
                end else if (pending_live_valid) begin
                    fifo_wr_en         <= 1'b1;
                    fifo_din           <= pending_live_event;
                    
                    // if another live note arrives while we empty this one (tbh don't think its possible but just in case)
                    if (live_valid) pending_live_event <= live_event;
                    else            pending_live_valid <= 1'b0;
                
                end else if (live_valid) begin
                    fifo_wr_en <= 1'b1;
                    fifo_din   <= live_event;
                end
            end
        end
    end
    
    // fifo is in fwft
    voiceAllocatorFIFO allocatorQueue ( // for now we are using DRAM, change?
        .clk   (clk),
        .srst  (rst),
        .din   (fifo_din),
        .wr_en (fifo_wr_en),
        .rd_en (fifo_rd_en),
        .dout  (fifo_dout),
        .full  (fifo_full),
        .empty (fifo_empty)
    );

endmodule