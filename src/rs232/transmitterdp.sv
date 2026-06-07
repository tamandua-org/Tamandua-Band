`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/14/2026 03:22:32 PM
// Design Name: 
// Module Name: transmitterdp
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

module transmitterdp(
        input logic clk,
        input logic rst,
        input logic [7:0] data,
        input transmitter_fsm_pkg::dp_ctrl_t dp_ctrl, 
               
        output logic TxD
    );
    
    logic [9:0] TxDShf;
    
    assign TxD = TxDShf[0];
    
    always_ff @(posedge clk) begin
        if (rst)
            TxDShf <= '1;
        else if (dp_ctrl.TxDShfLoad)
            TxDShf <= {1'b1, data, 1'b0};
        else if (dp_ctrl.TxDShfShift)
            TxDShf <= {1'b1, TxDShf[9:1]};
    end
endmodule
