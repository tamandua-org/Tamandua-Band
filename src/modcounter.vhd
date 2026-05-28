---------------------------------------------------------------------
--
--  Fichero:
--    modcounter.vhd  07/09/2023
--
--    (c) J.M. Mendias
--    Diseño Automático de Sistemas
--    Facultad de Informática. Universidad Complutense de Madrid
--
--  Propósito:
--    Contador ascendente genérico (en núm. de bits y valor máximo)
--
--  Notas de diseño:
--    Orientado a FPGA Xilinx 7 series: reset sincrono y valor inicial
--
---------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use work.common.all;

entity modCounter is
  generic
  (
    MAXVAL : natural   -- valor maximo alcanzable
  );
  port
  (
    clk   : in  std_logic;   -- reloj del sistema
    rst   : in  std_logic;   -- reset (puesta a 0) sincrono
    ce    : in  std_logic;   -- capacitacion de cuenta
    tc    : out std_logic;   -- fin de cuenta
    count : out std_logic_vector(log2(MAXVAL)-1 downto 0)   -- cuenta
  );
end modCounter;

---------------------------------------------------------------------

library ieee;
use ieee.numeric_std.all;

architecture syn of modCounter is

  signal cs : unsigned(count'range) := (others => '0');
  
begin

  stateReg:
  process (clk)
  begin
    if rising_edge(clk) then
      if rst='1' then
        cs <= (others => '0');
      elsif ce = '1' then
        cs <= cs + 1;
        if (cs = MAXVAL) then
          cs <= (others => '0');
        end if;
      else 
         cs <= cs;
      end if;
    end if;
  end process;

  count <= std_logic_vector(cs);
  
  tc <= 
    '1' when (cs = MAXVAL) and ce = '1' else --a lo mejor tiene que ser MAXVAL-1 o MAXVAL nu se
    '0'; 

end syn;
