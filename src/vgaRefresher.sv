import pixelColor_pkg::*;

module vgaRefresher (
        input logic clk100mhz,
        input logic rst,
        input pixelColor_t pixelColorIn,

        output logic hSync,
        output logic vSync,
        output logic [9:0] pixel,
        output logic [9:0] line,
        output logic [11:0] pixelColorOut
  );

  logic pixelCntTC, clk25mhz;
  logic [9:0] pixelCntValue, lineCntValue;
  
  logic blanking, hSyncComb, vSyncComb;
  logic [11:0] RGB;

  assign hSyncComb = !(pixelCntValue >= 656 && pixelCntValue < 752);
  assign vSyncComb = !(lineCntValue >= 490 && lineCntValue < 492);
  assign blanking = pixelCntValue >= 640 || lineCntValue >= 480;
  assign RGB = pixelColorIn & {12{~blanking}};
  assign pixel = pixelCntValue;
  assign line = lineCntValue;

  vgaClock clkgen (.clk_out1(clk25mhz), .reset(rst), .clk_in1(clk100mhz));

  modCounter #(.MAXVAL(799)) pixelCnt (.clk(clk25mhz), .rst, .ce(1), .tc(pixelCntTC), .count(pixelCntValue));
  modCounter #(.MAXVAL(524)) lineCnt (.clk(clk25mhz), .rst, .ce(pixelCntTC), .tc(), .count(lineCntValue)); 

//  always_comb begin
//    hSync = hSyncComb;
//    vSync = vSyncComb;
//    pixelColorOut = RGB;
//  end
  
  always_ff @(posedge clk25mhz) begin // es necesario para para que salga todo en su lugar correcto
    if (rst) begin
        hSync <= 1;
        vSync <= 1;
        pixelColorOut <= '0;
    end else begin
        hSync <= hSyncComb;
        vSync <= vSyncComb;
        pixelColorOut <= RGB;
    end
  end
    
endmodule
