`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.03.2026 11:33:54
// Design Name: 
// Module Name: rs232transmitter
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

module rs232transmitter #(
    parameter int FREQ_KHZ = 100_000,  
    parameter int BAUDRATE = 1200
)(
    input  logic        clk,
    input  logic        rst,
    input  logic        dataRdy,
    input  logic [7:0]  data,
    
    output logic        busy,

    output logic        TxD
    );
    
    localparam CYCLES = (FREQ_KHZ*1000)/BAUDRATE;
    
    logic writeTxD;
    logic [$clog2(CYCLES)-1:0] count;
    
    transmitter_fsm_pkg::dp_ctrl_t dp_ctrl;
    transmitter_fsm_pkg::status_t  status;
    
    assign writeTxD = status.baudCntCE && (count == CYCLES - 1);
    assign busy = status.busy;
    
    transmittercu controlUnit (.clk, .rst, .writeTxD, .dataRdy, .dp_ctrl, .status);
    transmitterdp dataPath (.clk, .rst, .data, .dp_ctrl, .TxD);

    always_ff @(posedge clk) begin
        if (rst)
            count <= 0;
        else if (status.baudCntCE) begin
            count <= count + 1; 
            if (count == CYCLES - 1)
                count <= 0;
        end else 
            count <= 0;
    end;
        
endmodule
