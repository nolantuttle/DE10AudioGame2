library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
	
-- The WM8731 datasheet: https://www.alldatasheet.com/datasheet-pdf/pdf/174585/WOLFSON/WM8731.html
-- The purpose of this entity is to initiate sending data to the audio codec for configuration over I2C
-- This is done by pulling sda from high to low while SCL is high. 
entity i2c is
	port(
	clk: in std_logic;	-- 50 MHz fpga system clock
	data: in std_logic_vector(15 downto 0);	-- data to be written to register
	reset: in std_logic; -- resets the i2c state machine
	start_flag: in std_logic;
	sda: inout std_logic;
	sclk: out std_logic;	-- The audio codec supports up to a 526kHz frequency for sclk
	busy: out std_logic;
	done: out std_logic
	);
end i2c;

architecture behavioral of i2c is
	signal start_condition: std_logic := '0';	-- Signal that goes high when start_condition flag is set, after immediately goes low
	signal clk_prs: integer range 0 to 249:=0;	-- Clock prescaler (counter that divides a fast clock)
	signal ack_en: std_logic := '0';	-- Signal for when the slave pulls the line low as an ACK
	signal data_index: integer range 0 to 15 := 0;
	type state_type is (IDLE, SEND_ADDR, ACK_ADDR, SEND_DATA1, ACK_DATA1, SEND_DATA2, ACK_DATA2, STOP);
	signal state : state_type := IDLE;
	constant codec_addr : std_logic_vector(7 downto 0) := "00110100";	-- Address for the WM8731
	
begin
	process(clk)	
		begin
			if rising_edge(clk) then
				if(reset = '1') then
                clk_prs    <= 0;
                ack_en     <= '0';
                state      <= IDLE;
                start_condition  <= '0';
                done       <= '0';
                busy       <= '0';
                sda        <= '1';
				else
					-- This runs once per clock cycle, so since we run it 250 times for our prs
					-- period(20 ns) = 1 / frequency (50MHz), 250 * 20 ns = 5.02 us, 1 / 5.02 us = ~200kHz i2c clock
					if(clk_prs < 250) then
						clk_prs <= clk_prs+1;
					else
						clk_prs <= 0;
					end if;
						
					-- Drive sclk @ ~200kHz
					if(clk_prs < 125) then
						sclk <= '1';
					else
						sclk <= '0';
					end if;
					
					-- Send ACK bit after 62 pulses x 20ns = 1.24 microseconds during sclk rising edge
					if(clk_prs = 62) then
						ack_en <= '1';
					else
						ack_en <= '0';
					end if;
					
					-- Triggers transaction start_condition signal when flag and sclk are high
					if(start_condition = '1' and clk_prs = 10) then
							sda <= '0';
							data_index <= 7;	-- This is used for shifting 8 bits into SDA during SEND_ADDR
							start_condition <= '0';
							state <= SEND_ADDR;
							done <= '0';
							busy <= '1';
					end if;
					
					if(clk_prs = 10 and state = STOP) then
						sda <= '1';
						done <= '1';
						busy <= '0';
						state <= IDLE;
					end if;
					
                -- State machine advances when SCL is low
                if clk_prs = 187 then
                    case state is
                        when IDLE =>
                            start_condition <= start_flag;
									 busy <= '0';
									 done <= '0';
                        when SEND_ADDR =>
									sda <= codec_addr(data_index);
										if(data_index > 0) then
											data_index <= data_index - 1;
										else
											sda <= 'Z';	-- Writing 'Z' to the line is high impedance mode, it just floats
											state <= ACK_ADDR;
										end if;
                        when SEND_DATA1 =>
                            sda <= data(data_index);
										if(data_index > 8) then
											data_index <= data_index - 1;
										else
											sda <= 'Z';	-- Writing 'Z' to the line is high impedance mode, it just floats
											state <= ACK_DATA1;
										end if;
                        when SEND_DATA2 =>
                            sda <= data(data_index);
										if(data_index > 0) then
											data_index <= data_index - 1;
										else
											sda <= 'Z';	-- Writing 'Z' to the line is high impedance mode, it just floats
											state <= ACK_DATA2;
										end if;
								when STOP =>
									sda <= '0';
                        when others =>
                            null;
                    end case;
                end if;

                -- ACK checking
                if ack_en = '1' then
                    case state is
                        when ACK_ADDR =>
									if(sda = '0') then
										data_index <= 15;	-- This is now ready to count through 16 bits in MSB
										state <= SEND_DATA1;
									else	-- Slave did not acknowledge, abort condition
										state <= IDLE;
									end if;
                        when ACK_DATA1 =>
									if(sda = '0') then
										state <= SEND_DATA2;
									else	-- Slave did not acknowledge, abort condition
										state <= IDLE;
									end if;
                        when ACK_DATA2 =>
                            if(sda = '0') then
										state <= STOP;
									else	-- Slave did not acknowledge, abort condition
										state <= IDLE;
									end if;
                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end if;
    end process;
end behavioral;