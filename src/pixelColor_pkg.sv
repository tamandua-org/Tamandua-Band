`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.04.2026 12:12:27
// Design Name: 
// Module Name: pixelColor_pkg
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


package pixelColor_pkg;
    
typedef struct packed {
    logic [3:0] red;
    logic [3:0] green;
    logic [3:0] blue;
} pixelColor_t;
    
endpackage
