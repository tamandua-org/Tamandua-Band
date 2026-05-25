import pixelColor_pkg::*;

module vgaTextInterface #(
    parameter int FREQ_DIV = 4,
    parameter logic [11:0] BGCOLOR = 12'h000,
    parameter logic [11:0] FGCOLOR = 12'h0F0
)(
    // host side
    input  logic        clk,
    input  logic        rst,
    input  logic        clear,
    input  logic        dataRdy,
    input  logic [7:0]  char,
    input  logic [6:0]  x,
    input  logic [4:0]  y,

    output logic [6:0]  col,
    output logic [2:0]  uCol,
    output logic [4:0]  row,
    output logic [3:0]  uRow,

    // VGA side
    output logic        hSync,
    output logic        vSync,
    output logic [11:0] RGB
);

    localparam int COLSxLINE  = 80;
    localparam int ROWSxFRAME = 30;

    logic [9:0] pixel, line;

    logic [6:0] colInt;
    logic [4:0] rowInt;
    logic [2:0] uColInt;
    logic [3:0] uRowInt;

    logic [6:0] clearX;
    logic [4:0] clearY;
    logic       clearing;

    pixelColor_t color;
    logic [11:0] color_flat;
    
    // RAM
    logic [11:0] ramRdAddr, ramWrAddr;
    logic we;
    logic [7:0] asciiCode, ramWrData;
    vgaScreenBuffer screenRAM (.clka(clk), .wea(we), .addra(ramWrAddr), .dina(ramWrData), .clkb(clk), .addrb(ramRdAddr), .doutb(asciiCode));
    
    // ROM
    logic [11:0] romAddr;
    logic [7:0] bitMapLine;
    logic bitMapPixel;

    characterROM bitmapROM (.clka(clk), .addra(romAddr), .douta(bitMapLine));
    assign romAddr = {asciiCode, uRow_d}; // ROM access ( obtain key representation on bitmap)
    
    // VGA refresher
    vgaRefresher screenInteface (
        .clk100mhz(clk),
        .rst(1'b0),
        .pixelColorIn(color),
    
        .hSync(hSync),
        .vSync(vSync),
        .pixel(pixel),
        .line(line),
        .pixelColorOut(RGB)
    );


    // Column / row decoding
    assign colInt = pixel[9:3];
    assign uColInt = pixel[2:0];

    assign rowInt = line[9:4];
    assign uRowInt = line[3:0];
    logic [2:0] uCol_d[0:3];
    logic [0:3] uRow_d;
    
    always_ff @(posedge clk) begin //delay to account for 1 cycle RAM and 2 cycle ROM (1 cycle for uRow, 2+1 for uCol)
      if (rst) begin
          uCol_d[0] <= '0;
          uCol_d[1] <= '0;
          uCol_d[2] <= '0;
          uCol_d[3] <= '0;
        
          uRow_d <= '0;
      end else begin
          uCol_d[0] <= uColInt;
          uCol_d[1] <= uCol_d[0];
          uCol_d[2] <= uCol_d[1];
          uCol_d[3] <= uCol_d[2];
        
          uRow_d <= uRowInt;
      end
    end

    assign col = colInt;
    assign uCol = uColInt;
    assign row = rowInt;
    assign uRow = uRowInt;


    // RAM interface (what key pos we printing)
    assign we = clearing || dataRdy;
    assign ramWrData = clearing ? '0 : char;
    assign ramWrAddr = clearing ? {clearY, clearX} : {y, x};
    assign ramRdAddr = {row, col};

    assign bitMapPixel = bitMapLine[7 - uCol_d[3]];

    assign color.red   = bitMapPixel ? FGCOLOR[11:8] : BGCOLOR[11:8];
    assign color.green = bitMapPixel ? FGCOLOR[7:4]  : BGCOLOR[7:4];
    assign color.blue  = bitMapPixel ? FGCOLOR[3:0]  : BGCOLOR[3:0];


    // Clear logic
    logic overflow;
    always_ff @(posedge clk) begin
        if (rst || (!clear && !clearing)) begin
            clearX <= 0;
            clearY <= 0;
            overflow <= 0;
            clearing <= 0;
        end else if (clear || clearing) begin
            if (clear) clearing <= 1;
            else if (clearX == COLSxLINE - 1 && clearY == ROWSxFRAME - 1) clearing <= 0;
            if (clearX == COLSxLINE - 1) overflow <= 1;
            else overflow <= 0;
            
            clearX <= clearX + 1;
            clearY <= clearY + overflow;
            
        end
    end
 

endmodule