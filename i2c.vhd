library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity i2c is
port(
i2c_clk_50: in std_logic;	-- 50 MHz fpga system clock
i2c_data: in std_logic_vector(15 downto 0);	-- data to be written to register
i2c_addr: in std_logic_vector(7 downto 0);	-- address of the WM8731
i2c_reset: in std_logic; -- resets the i2c state machine
i2c_send_flag: in std_logic;
i2c_sda: inout std_logic;
i2c_scl: out std_logic;
i2c_busy: out std_logic;
i2c_done: out std_logic
);
end i2c;

architecture behavioral of i2c is
	signal i2c_clk_en: std_logic:='0';	-- Enable for the custom ~200kHz i2c clock
	signal clk_prs: integer range 0 to 300:=0;	-- clock prescaler (counter that divides a fast clock)
	signal clk_en: std_logic:='0';	-- Signal to advance the state machine one 'pulse'
	signal ack_en: std_logic:='0';	-- Signal for when the slave pulls the line low as an ACK
	signal i2c_scl_clk: std_logic:='0';	-- The SCL clock 
	signal get_ack: std_logic:='0';	-- Signals the next bit to sample ACK and not data
	signal data_index: integer range 0 to 15:=0;
	type state_type is (IDLE, START, SEND_ADDR, ACK_ADDR, SEND_DATA1, ACK_DATA1, SEND_DATA2, ACK_DATA2, STOP);
	signal state : state_type := IDLE;
	
begin

process(i2c_clk_50)
begin

if rising_edge(i2c_clk_50) then

	if(clk_prs < 250) then
		clk_prs <= clk_prs+1;
	else
		clk_prs <= 0;
	end if;
	
	if(clk_prs < 125) then
		i2c_scl_clk <= '1';
	else
		i2c_scl_clk <= '0';
	end if;
	
	if(clk_prs = 62) then
		ack_en <= '1';
	else
		ack_en <= '0';
	end if;
	
	if(clk_prs = 187) then 
		clk_en <= '1';
	else
		clk_en <= '0';
	end if;
	
end if;
	
if rising_edge(i2c_clk_50) then
	
	if(i2c_clk_en = '1') then
		i2c_scl <= i2c_scl_clk;
	else
		i2c_scl <= '1';
	end if;
	
	if(clk_en = '1') then
    case state is

        when IDLE =>
            i2c_sda <= '1';
            i2c_busy <= '0';
            if(i2c_send_flag = '1') then
                i2c_done <= '0';
                state <= START;
                i2c_busy <= '1';
            end if;

        when START =>
            i2c_sda <= '0';
            state <= SEND_ADDR;
            data_index <= 7;

        when SEND_ADDR =>
            i2c_clk_en <= '1';
            if(data_index > 0) then
                data_index <= data_index - 1;
                i2c_sda <= i2c_addr(data_index);
            else
                i2c_sda <= i2c_addr(data_index);
                get_ack <= '1';
            end if;

            if(get_ack = '1') then
                get_ack <= '0';
                state <= ACK_ADDR;
                i2c_sda <= 'Z';
            end if;

        when SEND_DATA1 =>
            if(data_index > 8) then
                data_index <= data_index - 1;
                i2c_sda <= i2c_data(data_index);
            else
                i2c_sda <= i2c_data(data_index);
                get_ack <= '1';
            end if;

            if(get_ack = '1') then
                get_ack <= '0';
                state <= ACK_DATA1;
                i2c_sda <= 'Z';
            end if;

        when SEND_DATA2 =>
            if(data_index > 0) then
                data_index <= data_index - 1;
                i2c_sda <= i2c_data(data_index);
            else
                i2c_sda <= i2c_data(data_index);
                get_ack <= '1';
            end if;

            if(get_ack = '1') then
                get_ack <= '0';
                state <= ACK_DATA2;
                i2c_sda <= 'Z';
            end if;

        when STOP =>
            i2c_clk_en <= '0';
            i2c_sda <= '0';
            i2c_busy <= '0';
            state <= IDLE;
            i2c_done <= '1';

        when others =>
            null;

		end case;
	 end if;
	 
	if(ack_en='1')then
		case state is
		when ACK_ADDR=>
				if(i2c_sda='0')then
					state<=SEND_DATA1;
					data_index<=15;			
				else
					i2c_clk_en<='0';
					i2c_busy<='0';
					i2c_done<='0';
					state<=IDLE;
				end if;
				
		when ACK_DATA1=>
				if(i2c_sda='0')then
					state<=SEND_DATA2;
					data_index<=7;			
				else
					i2c_clk_en<='0';
					i2c_busy<='0';
					i2c_done<='0';
					state<=IDLE;
				end if;
				
		when ACK_DATA2 =>
				if(i2c_sda='0')then
					state<=STOP;
				else
					i2c_clk_en<='0';
					i2c_busy<='0';
					i2c_done<='0';
					state<=IDLE;
				end if;	
				
		when others=>NULL;
		end case;
	end if;
end if;
end process;
end behavioral;