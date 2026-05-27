---------------------------------------------------------------------
--
--  Fichero:
--    common.vhd  07/09/2023
--
--    (c) J.M. Mendias
--    Diseño Automático de Sistemas
--    Facultad de Informática. Universidad Complutense de Madrid
--
--  Propósito:
--    Contiene definiciones de constantes, funciones de utilidad
--    y componentes reusables
--
--  Notas de diseño:
--
---------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package common is

  constant YES  : std_logic := '1';
  constant NO   : std_logic := '0';
  constant HI   : std_logic := '1';
  constant LO   : std_logic := '0';
  constant ONE  : std_logic := '1';
  constant ZERO : std_logic := '0';
  
  -- Calcula el logaritmo en base-2 de un numero.
  function log2(v : in natural) return natural;
  -- Selecciona un entero entre dos.
  function int_select(s : in boolean; a : in integer; b : in integer) return integer;
  -- Convierte un caracter en un std_logic_vector(7 downto 0). 
  function char2slv(c: character) return std_logic_vector; 
  -- Calcula el numero de ciclos de reloj a una frecuencia (en KHz) que equivalen a un tiempo absoluto (en ns) dado. 
  function ns2cycles(fkHz : in natural; tns: in natural) return natural;
  -- Calcula el numero de ciclos de reloj a una frecuencia (en KHz) que equivalen a un tiempo absoluto (en us) dado. 
  function us2cycles(fkHz : in natural; tus: in natural) return natural;
  -- Calcula el numero de ciclos de reloj a una frecuencia (en KHz) que equivalen a un tiempo absoluto (en ms) dado. 
  function ms2cycles(fKHz : in natural; tms: in natural) return natural;
  -- Calcula el numero de ciclos de reloj a una frecuencia (en KHz) que equivalen a un ciclo de otra frecuencia (en Hz) dado. 
  function hz2cycles(fKHz : in natural; fHz: in natural) return natural;
  -- Convierte un real en un signed en punto fijo con qn bits enteros y qm bits decimales. 
  function toFix( d: real; qn : natural; qm : natural ) return signed; 
  
  -- Convierte codigo binario a codigo 7-segmentos
  component bin2segs
    port
    (
      -- host side
      en     : in std_logic;                      -- capacitacion
      bin    : in std_logic_vector(3 downto 0);   -- codigo binario
      dp     : in std_logic;                      -- punto
      -- leds side
      segs_n : out std_logic_vector(7 downto 0)   -- codigo 7-segmentos
    );
  end component;
 
end package common;

-------------------------------------------------------------------

library ieee;
use ieee.numeric_std.all;

package body common is

  function log2(v : in natural) return natural is
    variable n    : natural;
    variable logn : natural;
  begin
    n := 1;
    for i in 0 to 128 loop
      logn := i;
      exit when (n >= v);
      n := n * 2;
    end loop;
    return logn;
  end function log2;
  
  function int_select(s : in boolean; a : in integer; b : in integer) return integer is
  begin
    if s then
      return a;
    else
      return b;
    end if;
    return a;
  end function int_select;
    
  function char2slv(c: character) return std_logic_vector is 
  begin 
    return std_logic_vector(to_unsigned(natural(character'pos(c)),8)); 
  end function;    
  
  function ns2cycles(fKHz : in natural; tns: in natural) return natural is
    constant NORM_NSxKHZ : natural := 1_000_000;  -- Factor de normalización ns * KHz
  begin
    return (tns*fKHz)/NORM_NSxKHZ;  
  end function;
  
  function us2cycles(fKHz : in natural; tus: in natural) return natural is
    constant NORM_USxKHZ : natural := 1_000;  -- Factor de normalización us * KHz
  begin
    return tus*(fKHz/NORM_USxKHZ);  
  end function;
  
  function ms2cycles(fKHz : in natural; tms: in natural) return natural is
  begin
    return tms*fKHz;  
  end function;
  
  function hz2cycles(fKHz : in natural; fHz: in natural) return natural is
  begin
    return fKHz*1000/fHz;
  end function;

  function toFix( d: real; qn : natural; qm : natural ) return signed is 
  begin 
    return to_signed( integer(d*(2.0**qm)), qn+qm );
  end function; 
  
end package body common;
