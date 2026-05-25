-------------------------------------------------------------------
--
--  Fichero:
--    edgeDetector.vhd  07/09/2023
--
--    (c) J.M. Mendias
--    Diseño Automático de Sistemas
--    Facultad de Informática. Universidad Complutense de Madrid
--
--  Propósito:
--    Detecta flancos en una entrada binaria lenta
--
--  Notas de diseño:
--    Orientado a FPGA Xilinx 7 series: no reset y valor inicial
--
-------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity edgeDetector is
  generic(
    XPOL  : std_logic         -- polaridad (valor en reposo) de la señal a la que eliminar rebotes
  );
  port (
    clk   : in  std_logic;   -- reloj del sistema
    x     : in  std_logic;   -- entrada binaria con flancos a detectar
    xFall : out std_logic;   -- se activa durante 1 ciclo cada vez que detecta un flanco de subida en x
    xRise : out std_logic    -- se activa durante 1 ciclo cada vez que detecta un flanco de bajada en x
  );
end edgeDetector;

-------------------------------------------------------------------

architecture syn of edgeDetector is 
begin

  process (clk)
    variable aux : std_logic_vector(1 downto 0) := (others => XPOL); 
  begin
    xFall <= not aux(0) and aux(1);
    xRise <= aux(0) and not aux(1);
    if rising_edge(clk) then
      aux(1) := aux(0);
      aux(0) := x;           
    end if;
  end process;

end syn;

