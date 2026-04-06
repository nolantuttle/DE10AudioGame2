library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_tx is
    port (
        clk_50         : in  std_logic;  -- 50 MHz FPGA clock
        reset_n        : in  std_logic;  -- active-low reset
        enable         : in  std_logic;  -- enable transmission
        sample_l       : in  std_logic_vector(15 downto 0);  -- left channel sample
        sample_r       : in  std_logic_vector(15 downto 0);  -- right channel sample
        sample_request : out std_logic;  -- pulse when new samples are needed
        i2s_bclk       : out std_logic;  -- bit clock (~1.536 MHz)
        i2s_lrck       : out std_logic;  -- left/right clock (48 kHz)
        i2s_sdata      : out std_logic   -- serial data out
    );
end i2s_tx;

architecture rtl of i2s_tx is
    
    -- Clock divider for BCLK generation
    -- 50MHz / 33 = 1.515 MHz BCLK (close to target 1.536 MHz)
    -- Sample rate = 1.515MHz / 32 = 47.34 kHz (close to target 48 kHz)
    constant BCLK_DIV : integer := 33;
    signal bclk_counter : integer range 0 to BCLK_DIV-1 := 0;
    signal bclk_int     : std_logic := '0';
    signal bclk_prev    : std_logic := '0';
    signal bclk_rising  : std_logic := '0';  -- pulse on BCLK rising edge
    
    -- I2S state machine
    type state_type is (IDLE, SEND_LEFT, SEND_RIGHT);
    signal state : state_type := IDLE;
    
    -- Bit counter: counts 0 to 15 for each channel
    signal bit_counter  : integer range 0 to 15 := 0;
    
    -- Shift registers to hold sample data
    signal shift_reg_l  : std_logic_vector(15 downto 0) := (others => '0');
    signal shift_reg_r  : std_logic_vector(15 downto 0) := (others => '0');
    
    -- Internal signals for outputs
    signal lrck_int        : std_logic := '0';
    signal sdata_int       : std_logic := '0';
    signal sample_req_int  : std_logic := '0';

begin
    
    -- Output assignments
    i2s_bclk       <= bclk_int;
    i2s_lrck       <= lrck_int;
    i2s_sdata      <= sdata_int;
    sample_request <= sample_req_int;

    -------------------------------------------------------------------------
    -- BCLK Generation Process
    -- Generates ~1.515 MHz bit clock from 50 MHz system clock
    -------------------------------------------------------------------------
    bclk_gen : process(clk_50, reset_n)
    begin
        if reset_n = '0' then
            bclk_counter <= 0;
            bclk_int     <= '0';
        elsif rising_edge(clk_50) then
            if bclk_counter = BCLK_DIV-1 then
                bclk_counter <= 0;
                bclk_int     <= not bclk_int;  -- toggle BCLK
            else
                bclk_counter <= bclk_counter + 1;
            end if;
        end if;
    end process;

    -------------------------------------------------------------------------
    -- BCLK Rising Edge Detector
    -- Creates a single-cycle pulse on rising edge of BCLK
    -- This is used to advance the state machine at the correct times
    -------------------------------------------------------------------------
    bclk_edge_detect : process(clk_50, reset_n)
    begin
        if reset_n = '0' then
            bclk_prev   <= '0';
            bclk_rising <= '0';
        elsif rising_edge(clk_50) then
            bclk_prev   <= bclk_int;
            bclk_rising <= bclk_int and (not bclk_prev);  -- rising edge pulse
        end if;
    end process;

    -------------------------------------------------------------------------
    -- I2S Transmission State Machine
    -- Sends 16-bit samples with proper I2S timing
    -- 
    -- I2S Protocol:
    -- - LRCK low  = left channel
    -- - LRCK high = right channel
    -- - Data changes on BCLK falling edge (we use rising edge to send next bit)
    -- - MSB first
    -- 
    -- sample_request pulses high for one 50MHz clock cycle when new samples
    -- are needed (at the start of each new frame, ~47.34 kHz rate)
    -------------------------------------------------------------------------
    i2s_fsm : process(clk_50, reset_n)
    begin
        if reset_n = '0' then
            state           <= IDLE;
            bit_counter     <= 0;
            shift_reg_l     <= (others => '0');
            shift_reg_r     <= (others => '0');
            lrck_int        <= '0';
            sdata_int       <= '0';
            sample_req_int  <= '0';
            
        elsif rising_edge(clk_50) then
            
            -- Default: sample_request is low
            sample_req_int <= '0';
            
            -- Only advance state machine on BCLK rising edges
            if bclk_rising = '1' then
                
                case state is
                    
                    when IDLE =>
                        lrck_int    <= '0';
                        sdata_int   <= '0';
                        bit_counter <= 0;
                        
                        if enable = '1' then
                            -- Load samples into shift registers
                            shift_reg_l <= sample_l;
                            shift_reg_r <= sample_r;
                            state       <= SEND_LEFT;
                            sample_req_int <= '1';  -- Request first samples
                        end if;
                    
                    when SEND_LEFT =>
                        lrck_int <= '0';  -- LRCK low = left channel
                        
                        -- Send MSB first (bit 15 down to bit 0)
                        sdata_int <= shift_reg_l(15);
                        
                        -- Shift register left (next bit moves to MSB position)
                        shift_reg_l <= shift_reg_l(14 downto 0) & '0';
                        
                        if bit_counter = 15 then
                            -- Finished sending all 16 bits of left channel
                            bit_counter <= 0;
                            state       <= SEND_RIGHT;
                        else
                            bit_counter <= bit_counter + 1;
                        end if;
                    
                    when SEND_RIGHT =>
                        lrck_int <= '1';  -- LRCK high = right channel
                        
                        -- Send MSB first (bit 15 down to bit 0)
                        sdata_int <= shift_reg_r(15);
                        
                        -- Shift register left
                        shift_reg_r <= shift_reg_r(14 downto 0) & '0';
                        
                        if bit_counter = 15 then
                            -- Finished sending all 16 bits of right channel
                            bit_counter <= 0;
                            
                            -- Reload samples and continue if still enabled
                            if enable = '1' then
                                shift_reg_l <= sample_l;
                                shift_reg_r <= sample_r;
                                state <= SEND_LEFT;
                                sample_req_int <= '1';  -- Request new samples for next frame
                            else
                                state <= IDLE;
                            end if;
                        else
                            bit_counter <= bit_counter + 1;
                        end if;
                        
                end case;
                
            end if;  -- bclk_rising
            
        end if;  -- rising_edge(clk_50)
    end process;

end rtl;
