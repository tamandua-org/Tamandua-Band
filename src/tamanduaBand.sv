module tamanduaBand (
    input  logic        clk,
    input  logic        rst,
    input  logic        ps2Clk,
    input  logic        ps2Data,
    
    output logic mclk,
    output logic lrclk,
    output logic sclk,
    output logic sdata,
    output logic        hSync,
    output logic        vSync,
    output logic [11:0] RGB
);


  localparam int FREQ_KHZ = 100_000;
  localparam int VGA_KHZ  = 25_000;
  localparam int FREQ_DIV = FREQ_KHZ / VGA_KHZ;

  localparam int COLSxLINE  = 80;
  localparam int ROWSxFRAME = 30;

  localparam logic [11:0] BGCOLOR = '0;
  localparam logic [11:0] FGCOLOR = 'h0F0;

  logic rstSync;

  logic [7:0] key;
  logic keyRdy;

  logic [$clog2(COLSxLINE)-1:0] x = '0;
  logic [$clog2(ROWSxFRAME)-1:0] y = '0;

  logic [$bits(x)-1:0] col;
  logic [$bits(y)-1:0] row;
  logic [3:0] uRow;
  logic [2:0] uCol;
  
  logic [11:0] RGBinterface;

  logic shiftP = 1'b0;
  logic capsOn = 1'b0;

  logic [7:0] char = '0;
  logic charRdy = 1'b0;

  logic clear = 1'b0;
  logic newLine = 1'b0;

  synchronizer #(.STAGES(2), .XPOL('0)) rstSynchronizer (.clk(clk), .x(rst), .xSync (rstSync));
  ps2receiver ps2KeyboardInterface (.clk(clk), .rst(rstSync), .dataRdy(keyRdy), .data(key), .ps2Clk(ps2Clk), .ps2Data(ps2Data));

  // Key Scanner
  typedef enum logic {keyON, keyOFF} state_t;
  state_t state = keyON;

  always_ff @(posedge clk) begin
    if (rstSync) begin
      state    <= keyON;
      shiftP   <= 1'b0;
      capsOn   <= 1'b0;
      charRdy  <= 1'b0;
      newLine  <= 1'b0;
      clear    <= 1'b0;
    end else begin
      charRdy <= 1'b0;
      newLine <= 1'b0;
      clear   <= 1'b0;
      
      if (keyRdy) begin
        case (state)
            keyON: begin
             if (key == 8'hF0) begin
                state <= keyOFF;  // key has been released
              end else begin
                case (key)
                  8'h12, 8'h59: begin // SHIFT (l/r)
                    shiftP <= 1;
                  end
    
                  8'h58: begin // CAPS LOCK
                    capsOn <= ~capsOn;
                  end
    
                  8'h76: begin // ESC
                    clear <= 1;
                  end
    
                  8'h5A: begin // ENTER
                    newLine <= 1;
                  end
    
                  default: begin
                    // char
                    char <= key;
                    charRdy <= 1;
                  end
    
                endcase
              end
            end
            
            keyOFF: begin
              state <= keyON;
    
              case (key)
                8'h12, 8'h59: begin
                  shiftP <= 1'b0;  // shift released
                end
                default: begin // ignore
                end
              endcase
            end
        endcase
      end
    end
  end

  // ROM Address + ASCII
  assign ps2ToAsciiAddr = {capsOn ^ shiftP, char};
  logic [8:0] ps2ToAsciiAddr;
  logic [7:0] asciiCode;

  ps2ToAsciiMap ps2ToAscii (.clk(clk), .a(ps2ToAsciiAddr), .qspo(asciiCode));


logic [$bits(x)-1:0] x_wr;
logic [$bits(y)-1:0] y_wr;

always_ff @(posedge clk) begin //1 key delay to match rom access 
  if (rstSync || clear) begin
    x <= 0;
    y <= 0;
    x_wr <= 0;
    y_wr <= 0;
  end else begin
    if (charRdy) begin
      x_wr <= x;
      y_wr <= y;

      if (x == COLSxLINE - 1) begin
        x <= 0;
        y <= (y == ROWSxFRAME - 1) ? 0 : y + 1;
      end else begin
        x <= x + 1;
      end
    end else if (newLine) begin
      x <= 0;
      y <= (y == ROWSxFRAME - 1) ? 0 : y + 1;
    end
  end
end
    
  logic charRdy_d; //1 cycle delay to match rom access
  always_ff @(posedge clk) begin
    if (rstSync) begin
        charRdy_d <= 0;
    end else begin
        charRdy_d <= charRdy;
    end
  end

  vgaTextInterface #(.FREQ_DIV(FREQ_DIV), .BGCOLOR(BGCOLOR), .FGCOLOR(FGCOLOR)) screenInterface 
    (.clk, .rst(rstSync), .clear, .dataRdy(charRdy_d), .x(x_wr), .y(y_wr), .char(asciiCode), .col, .uCol, .row, .uRow, .hSync, .vSync, .RGB(RGBinterface));

  // Cursor Render
  always_comb begin
    RGB = RGBinterface;
    if (x == col && y == row) begin
        RGB = '1;
    end
  end

endmodule