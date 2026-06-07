`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/14/2026 03:22:32 PM
// Design Name: 
// Module Name: transmittercu
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
import transmitter_fsm_pkg::*;

module transmittercu (
    input logic clk,
    input logic rst,
    input logic writeTxD,
    input logic dataRdy,
    
    output transmitter_fsm_pkg::dp_ctrl_t dp_ctrl,
    output transmitter_fsm_pkg::status_t  status    
);
    
    logic [3:0] bitPos;
    logic [3:0] nextBitPos;
        
    always_ff @(posedge clk) begin
        if (rst) begin
            bitPos <= '0;
        end 
        else begin
            bitPos <= nextBitPos;
        end
    end

    
    always_comb begin
        nextBitPos = bitPos;

        if (bitPos == 4'd0) begin
            if (dataRdy) 
                nextBitPos = 4'd1;
        end else if (bitPos < 4'd10) begin
            if (writeTxD)
                nextBitPos = bitPos + 1;
        end else begin
            if (writeTxD)
                nextBitPos = '0;
        end
    end
    
    always_comb begin
        dp_ctrl = '0;
        status  = '0;
    
        if (bitPos != 4'd0) begin
            status.busy = 1;
            status.baudCntCE = 1;
        end
    
        if ((bitPos == 4'd0) && dataRdy)
            dp_ctrl.TxDShfLoad = 1;
        else if ((bitPos != 4'd0) && writeTxD) 
            dp_ctrl.TxDShfShift = 1;
    end
 
endmodule
