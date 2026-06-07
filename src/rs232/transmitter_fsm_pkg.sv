//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/14/2026 03:27:17 PM
// Design Name: 
// Module Name: transmitter_fsm_pkg
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

package transmitter_fsm_pkg;

typedef struct packed {
    logic TxDShfLoad;
    logic TxDShfShift;
} dp_ctrl_t;

typedef struct packed {
    logic busy;
    logic baudCntCE;
} status_t;

endpackage
