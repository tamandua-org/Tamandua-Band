set_property CFGBVS VCCO [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];

# Reloj del sistema: 100 MHz
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports clk];
create_clock -name sysClk -period 10.0 -waveform {0 5} [get_ports clk];

# Pines conectados a la VGA
set_property -dict { PACKAGE_PIN P19 IOSTANDARD LVCMOS33 } [get_ports hSync];
set_property -dict { PACKAGE_PIN R19 IOSTANDARD LVCMOS33 } [get_ports vSync];
set_property -dict { PACKAGE_PIN N19 IOSTANDARD LVCMOS33 } [get_ports {RGB[11]}];    #R3
set_property -dict { PACKAGE_PIN J19 IOSTANDARD LVCMOS33 } [get_ports {RGB[10]}];    #R2
set_property -dict { PACKAGE_PIN H19 IOSTANDARD LVCMOS33 } [get_ports {RGB[9]}];     #R1
set_property -dict { PACKAGE_PIN G19 IOSTANDARD LVCMOS33 } [get_ports {RGB[8]}];     #R0
set_property -dict { PACKAGE_PIN D17 IOSTANDARD LVCMOS33 } [get_ports {RGB[7]}];     #G3
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } [get_ports {RGB[6]}];     #G2
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {RGB[5]}];     #G1
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports {RGB[4]}];     #G0
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports {RGB[3]}];     #B3
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports {RGB[2]}];     #B2
set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 } [get_ports {RGB[1]}];     #B1
set_property -dict { PACKAGE_PIN N18 IOSTANDARD LVCMOS33 } [get_ports {RGB[0]}];     #B0

set_property -dict { PACKAGE_PIN J1 IOSTANDARD LVCMOS33 } [get_ports mclk]; # master clk
set_property -dict { PACKAGE_PIN L2 IOSTANDARD LVCMOS33 } [get_ports lrclk]; # serial clk
set_property -dict { PACKAGE_PIN J2 IOSTANDARD LVCMOS33 } [get_ports sclk]; # left (low)/right (high) clock stereo
set_property -dict { PACKAGE_PIN G2 IOSTANDARD LVCMOS33 } [get_ports sdata]; # serial data

set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 PULLUP true } [get_ports ps2Clk];
set_property -dict { PACKAGE_PIN B17 IOSTANDARD LVCMOS33 PULLUP true } [get_ports ps2Data];

set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 } [get_ports rst_prueba];    # btnU
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports btnC];    # btnC
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports btnL];    # btnL
set_property -dict { PACKAGE_PIN T17 IOSTANDARD LVCMOS33 } [get_ports btnR];    # btnR


# Para debuggear
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN E19 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN V19 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN V3  IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN W3  IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN U3  IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN P3  IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN N3  IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
set_property -dict { PACKAGE_PIN P1  IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
set_property -dict { PACKAGE_PIN L1  IOSTANDARD LVCMOS33 } [get_ports {led[15]}]

# Switches Basys3
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN W17 IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {sw[5]}]
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports {sw[6]}]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports {sw[7]}]
set_property -dict { PACKAGE_PIN V2  IOSTANDARD LVCMOS33 } [get_ports {sw[8]}]
set_property -dict { PACKAGE_PIN T3  IOSTANDARD LVCMOS33 } [get_ports {sw[9]}]
set_property -dict { PACKAGE_PIN T2  IOSTANDARD LVCMOS33 } [get_ports {sw[10]}]
set_property -dict { PACKAGE_PIN R3  IOSTANDARD LVCMOS33 } [get_ports {sw[11]}]
set_property -dict { PACKAGE_PIN W2  IOSTANDARD LVCMOS33 } [get_ports {sw[12]}]
set_property -dict { PACKAGE_PIN U1  IOSTANDARD LVCMOS33 } [get_ports {sw[13]}]
set_property -dict { PACKAGE_PIN T1  IOSTANDARD LVCMOS33 } [get_ports {sw[14]}]
set_property -dict { PACKAGE_PIN R2  IOSTANDARD LVCMOS33 } [get_ports {sw[15]}]