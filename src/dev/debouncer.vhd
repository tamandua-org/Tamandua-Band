-------------------------------------------------------------------
--
--  Fichero:
--    debouncer.vhd  07/09/2023
--
--    (c) J.M. Mendias
--    Diseño Automático de Sistemas
--    Facultad de Informática. Universidad Complutense de Madrid
--
--  Propósito:
--    Elimina los rebotes de una línea binaria 
--
--  Notas de diseño:
--    Orientado a FPGA Xilinx 7 series: reset sincrono y valor inicial
--
-------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity debouncer is
  generic(
    FREQ_KHZ  : natural;    -- frecuencia de operacion en KHz
    BOUNCE_MS : natural;    -- tiempo de rebote en ms
    XPOL      : std_logic   -- polaridad (valor en reposo) de la señal a la que eliminar rebotes
  );
  port (
    clk  : in  std_logic;   -- reloj del sistema
    rst  : in  std_logic;   -- reset síncrono del sistema
    x    : in  std_logic;   -- entrada binaria a la que deben eliminarse los rebotes
    xDeb : out std_logic    -- salida que sique a la entrada pero sin rebotes
  );
end debouncer;

-------------------------------------------------------------------

use work.common.all;

architecture syn of debouncer is

  signal startTimer, timerEnd: std_logic;
  
begin

  timer:
  process (clk)
    constant CYCLES : natural := ms2cycles(FREQ_KHZ, BOUNCE_MS);
    variable count  : natural range 0 to CYCLES-1 := 0;
  begin
    if count=0 then
      timerEnd <= '1';
    else 
      timerEnd <= '0';
    end if;
    if rising_edge(clk) then
      if rst='1' then
        count := 0;
      else
        if startTimer='1' then
          count := CYCLES-1;
        elsif timerEnd='0' then
          count := count - 1;
        end if;
      end if;
    end if;
  end process;
    
  fsm:
  process (clk, x)
    type states is (waitingKeyDown, keyDownDebouncing, waitingKeyUp, KeyUpDebouncing); 
    variable state: states := waitingKeyDown;
  begin 
    xDeb <= XPOL;
    startTimer <= '0';
    case state is
      when waitingKeyDown =>
        if x=not XPOL then
          startTimer <= '1';
        end if;
      when keyDownDebouncing =>
        xDeb <= not XPOL;
      when waitingKeyUp =>
        xDeb <= not XPOL;
        if x=XPOL then
          startTimer <= '1';
        end if;
      when KeyUpDebouncing =>
        null;
    end case;

    if rising_edge(clk) then
      if rst='1' then
        state := waitingKeyDown;
      else     
        case state is
          when waitingKeyDown =>
            if x=not XPOL then
              state := keyDownDebouncing;
            end if;
          when keyDownDebouncing =>
            if timerEnd='1' then
              state := waitingKeyUp;
            end if;
          when waitingKeyUp =>
            if x=XPOL then
              state := KeyUpDebouncing;
            end if;
          when KeyUpDebouncing =>
            if timerEnd='1' then
              state := waitingKeyDown;
            end if;
        end case;
      end if;
    end if;
  end process;  

end syn;
