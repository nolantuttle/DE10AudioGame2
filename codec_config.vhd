library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity codec_config is
port (
    clk_50        : in  std_logic;        -- 50 MHz FPGA clock
    reset_n       : in  std_logic;        -- active-low reset
    start_cfg     : in  std_logic;        -- switch to trigger config
    i2c_busy      : in  std_logic;        -- from I2C module
    i2c_done      : in  std_logic;        -- pulse when I2C transaction complete
    i2c_send_flag : out std_logic;        -- trigger I2C send
    i2c_addr      : out std_logic_vector(7 downto 0);
    i2c_data      : out std_logic_vector(15 downto 0);
    config_done   : out std_logic         -- '1' when all registers configured
);
end codec_config;

architecture fsm of codec_config is
    type state_type is (IDLE, SEND_REG, WAIT_ACK, NEXT_REG, DONE);
    signal state      : state_type := IDLE;
    signal cfg_index  : integer range 0 to 8 := 0;
    signal i2c_done_prev : std_logic := '0';  -- Previous value of i2c_done for edge detection
    
    -- WM8731 I2C address: 0x34 (assuming CSB pin is low)
    constant WM8731_ADDR : std_logic_vector(7 downto 0) := "00110100";
    
    -- Configuration registers for I2S mode, 16-bit, 48kHz
    -- Format: [6:0] = register address, [8:0] = register data
    type reg_array is array(0 to 8) of std_logic_vector(15 downto 0);
    constant CFG_WORDS : reg_array := (
        -- Register 15 (0x0F): Reset - clears all registers to default
        "0001111" & "000000000",
        
        -- Register 6 (0x06): Power Down Control
        -- Bit 7: Power off device = 0 (powered)
        -- Bit 4: Clock output = 0 (disabled)
        -- Bit 3: Oscillator = 0 (disabled)
        -- Bit 2: Line output = 1 (enabled)
        -- Bit 1: DAC = 1 (enabled)
        -- Bit 0: ADC = 1 (disabled for playback only)
        "0000110" & "000000111",
        
        -- Register 8 (0x08): Sampling Control
        -- Bit 0: USB/Normal mode = 1 (USB mode for 12MHz clock)
        "0001000" & "000000001",
        
			-- Register 7 (0x07): Digital Audio Interface Format
			-- Bit 7: BCLK invert = 0 (normal)
			-- Bit 6: Master/Slave = 0 (slave mode)
			-- Bit 5: LR swap = 0 (normal)
			-- Bit 4: DACLRC phase = 1 (right channel when DACLRC high = standard I2S)
			-- Bit 3-2: Input word length = 00 (16 bits)
			-- Bit 1-0: Format = 10 (I2S mode)
        "0000111" & "000010010",
        
        -- Register 9 (0x09): Active Control
        -- Bit 0: Active = 1 (activate interface)
        "0001001" & "000000001",
        
        -- Register 2 (0x02): Left Headphone Out
        -- Volume: 121 (0x79) = 0dB
        "0000010" & "101111000",
        
        -- Register 3 (0x03): Right Headphone Out
        -- Volume: 121 (0x79) = 0dB
        "0000011" & "101111000",
        
        -- Register 4 (0x04): Analogue Audio Path Control
        -- Bit 4: DAC select = 1 (select DAC)
        -- Bit 1: Bypass = 0 (disable bypass)
        "0000100" & "000010010",
        
        -- Register 5 (0x05): Digital Audio Path Control
        -- Bit 3: DAC soft mute = 0 (unmute)
        "0000101" & "000000000"
    );
    
begin

    process(clk_50, reset_n)
    begin
        if reset_n = '0' then
            state         <= IDLE;
            cfg_index     <= 0;
            i2c_send_flag <= '0';
            i2c_addr      <= (others => '0');
            i2c_data      <= (others => '0');
            config_done   <= '0';
            i2c_done_prev <= '0';
            
        elsif rising_edge(clk_50) then
            -- Update previous value for edge detection in all states
            i2c_done_prev <= i2c_done;
            
            case state is
                
                when IDLE =>
                    config_done   <= '0';
                    i2c_send_flag <= '0';
                    cfg_index     <= 0;
                    
                    -- Wait for start trigger
                    if start_cfg = '1' then
                        state <= SEND_REG;
                    end if;
                
                when SEND_REG =>
                    -- Set up I2C transaction
                    i2c_addr      <= WM8731_ADDR;
                    i2c_data      <= CFG_WORDS(cfg_index);
                    i2c_send_flag <= '1';
                    state         <= WAIT_ACK;
                
                when WAIT_ACK =>
						  -- Keep sending_flag high until I2C sees it and asserts busy
						 if i2c_busy = '1' then
							  i2c_send_flag <= '0';  -- Now I2C has seen it
						 end if;
                    
                    -- Wait for I2C transaction to complete (edge detection)
                    -- Only advance when i2c_done transitions from '0' to '1'
                    if i2c_done = '1' and i2c_done_prev = '0' then
                        state <= NEXT_REG;
                    end if;
                
                when NEXT_REG =>
                    -- Check if more registers to configure
                    if cfg_index < CFG_WORDS'high then
                        cfg_index <= cfg_index + 1;
                        state     <= SEND_REG;
                    else
                        state <= DONE;
                    end if;
                
                when DONE =>
                    -- Configuration complete
                    config_done <= '1';
                    -- Stay in DONE state (could add logic to reconfigure on reset)
                
                when others =>
                    state <= IDLE;
                    
            end case;
            
        end if;
    end process;

end fsm;
