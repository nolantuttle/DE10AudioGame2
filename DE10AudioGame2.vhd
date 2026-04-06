library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DE10AudioGame2 is
    port (
        -- FPGA inputs
        CLOCK_50    : in    std_logic;
        KEY         : in    std_logic_vector(3 downto 0);
        SW          : in    std_logic_vector(9 downto 0);
        LEDR        : out   std_logic_vector(8 downto 0);
        
        UART_RX     : in    std_logic;
        UART_TX     : out   std_logic;
        
        -- I2C for WM8731 configuration
        FPGA_I2C_SCLK : out   std_logic;
        FPGA_I2C_SDAT : inout std_logic;
        
        -- I2S audio output to WM8731
        AUD_BCLK    : out   std_logic;
        AUD_DACLRCK : out   std_logic;
        AUD_DACDAT  : out   std_logic;
        AUD_XCK     : out   std_logic
    );
end DE10AudioGame2;

architecture rtl of DE10AudioGame2 is
    
    -- Reset signal
    signal reset_n : std_logic;
    
    -- I2C signals
    signal i2c_busy      : std_logic;
    signal i2c_done      : std_logic;
    signal i2c_send_flag : std_logic;
    signal i2c_addr      : std_logic_vector(7 downto 0);
    signal i2c_data      : std_logic_vector(15 downto 0);
    
    -- Codec configuration signals
    signal config_done   : std_logic;
    signal start_config  : std_logic;
    
    -- Audio sample signals
    signal audio_sample  : std_logic_vector(15 downto 0);
    signal sample_index  : integer range 0 to 255 := 0;
    constant TONE_NONE   : integer := 4;
    signal selected_tone : integer range 0 to 4 := TONE_NONE;
    signal sample_request : std_logic;
    
    -- Button debouncing
    signal key_prev      : std_logic_vector(3 downto 0) := (others => '1');
    signal key_pressed   : std_logic_vector(3 downto 0) := (others => '0');
    
    -- 12 MHz clock generation
    signal clock_12      : std_logic := '0';
    signal clk_12_div    : integer range 0 to 1 := 0;
    
    -- UART signals (on clock_12 domain)
    signal uart_data     : std_logic_vector(7 downto 0);
    signal uart_valid    : std_logic;
    
    -- CDC: sync selected_tone from clock_12 -> CLOCK_50
    signal selected_tone_50a : integer range 0 to 4 := TONE_NONE;
    signal selected_tone_50  : integer range 0 to 4 := TONE_NONE;
    
    -- Random number generator (LFSR)
    signal lfsr : std_logic_vector(7 downto 0) := "10101010";
    signal random_tone : integer range 0 to 3;
    
    -- Game sequence storage
    type sequence_array is array(0 to 15) of integer range 0 to 3;
    signal game_sequence : sequence_array := (others => 0);
    signal sequence_length : integer range 1 to 16 := 1;
    signal current_index : integer range 0 to 15 := 0;
    
    -- Game state machine (NO IDLE STATE)
    type game_state_type is (GENERATE_SEQ, PLAY_SEQ, WAIT_USER, WIN, LOSE);
    signal game_state : game_state_type := GENERATE_SEQ;
    signal user_index : integer range 0 to 15 := 0;
    signal wrong_button : std_logic := '0';  -- Flag to remember if button was wrong
    
    -- Beep timing
    signal beep_counter : integer range 0 to 12_000_000 := 0;
    signal beep_playing : std_logic := '0';
    signal pause_counter : integer range 0 to 6_000_000 := 0;
    signal in_pause : std_logic := '0';
    
    -- Audio sample lookup tables
    type sample_array is array(0 to 255) of std_logic_vector(15 downto 0);
    
    function generate_sine_440hz return sample_array is
        variable samples : sample_array;
        variable phase : integer;
    begin
        for i in 0 to 255 loop
            phase := (i * 28) mod 256;
            if phase < 64 then
                samples(i) := std_logic_vector(to_signed(phase * 512, 16));
            elsif phase < 128 then
                samples(i) := std_logic_vector(to_signed(32767 - (phase - 64) * 512, 16));
            elsif phase < 192 then
                samples(i) := std_logic_vector(to_signed(-(phase - 128) * 512, 16));
            else
                samples(i) := std_logic_vector(to_signed(-32767 + (phase - 192) * 512, 16));
            end if;
        end loop;
        return samples;
    end function;
    
    function generate_sine_523hz return sample_array is
        variable samples : sample_array;
        variable phase : integer;
    begin
        for i in 0 to 255 loop
            phase := (i * 33) mod 256;
            if phase < 64 then
                samples(i) := std_logic_vector(to_signed(phase * 512, 16));
            elsif phase < 128 then
                samples(i) := std_logic_vector(to_signed(32767 - (phase - 64) * 512, 16));
            elsif phase < 192 then
                samples(i) := std_logic_vector(to_signed(-(phase - 128) * 512, 16));
            else
                samples(i) := std_logic_vector(to_signed(-32767 + (phase - 192) * 512, 16));
            end if;
        end loop;
        return samples;
    end function;
    
    function generate_sine_659hz return sample_array is
        variable samples : sample_array;
        variable phase : integer;
    begin
        for i in 0 to 255 loop
            phase := (i * 42) mod 256;
            if phase < 64 then
                samples(i) := std_logic_vector(to_signed(phase * 512, 16));
            elsif phase < 128 then
                samples(i) := std_logic_vector(to_signed(32767 - (phase - 64) * 512, 16));
            elsif phase < 192 then
                samples(i) := std_logic_vector(to_signed(-(phase - 128) * 512, 16));
            else
                samples(i) := std_logic_vector(to_signed(-32767 + (phase - 192) * 512, 16));
            end if;
        end loop;
        return samples;
    end function;
    
    function generate_sine_784hz return sample_array is
        variable samples : sample_array;
        variable phase : integer;
    begin
        for i in 0 to 255 loop
            phase := (i * 50) mod 256;
            if phase < 64 then
                samples(i) := std_logic_vector(to_signed(phase * 512, 16));
            elsif phase < 128 then
                samples(i) := std_logic_vector(to_signed(32767 - (phase - 64) * 512, 16));
            elsif phase < 192 then
                samples(i) := std_logic_vector(to_signed(-(phase - 128) * 512, 16));
            else
                samples(i) := std_logic_vector(to_signed(-32767 + (phase - 192) * 512, 16));
            end if;
        end loop;
        return samples;
    end function;
    
    constant TONE_0 : sample_array := generate_sine_440hz;
    constant TONE_1 : sample_array := generate_sine_523hz;
    constant TONE_2 : sample_array := generate_sine_659hz;
    constant TONE_3 : sample_array := generate_sine_784hz;
    
    component codec_config is
        port (
            clk_50        : in  std_logic;
            reset_n       : in  std_logic;
            start_cfg     : in  std_logic;
            i2c_busy      : in  std_logic;
            i2c_done      : in  std_logic;
            i2c_send_flag : out std_logic;
            i2c_addr      : out std_logic_vector(7 downto 0);
            i2c_data      : out std_logic_vector(15 downto 0);
            config_done   : out std_logic
        );
    end component;
    
    component i2c is
        port (
            i2c_clk_50    : in    std_logic;
            i2c_data      : in    std_logic_vector(15 downto 0);
            i2c_addr      : in    std_logic_vector(7 downto 0);
            i2c_reset     : in    std_logic;
            i2c_send_flag : in    std_logic;
            i2c_sda       : inout std_logic;
            i2c_scl       : out   std_logic;
            i2c_busy      : out   std_logic;
            i2c_done      : out   std_logic
        );
    end component;
    
    component i2s_tx is
        port (
            clk_50    : in  std_logic;
            reset_n   : in  std_logic;
            enable    : in  std_logic;
            sample_l  : in  std_logic_vector(15 downto 0);
            sample_r  : in  std_logic_vector(15 downto 0);
            sample_request : out std_logic;
            i2s_bclk  : out std_logic;
            i2s_lrck  : out std_logic;
            i2s_sdata : out std_logic
        );
    end component;

begin
    reset_n  <= SW(0);
    start_config <= '1';
    UART_TX  <= '1';  -- unused, tie high (idle UART line)
    
    -- Convert LFSR to random tone (0-3)
    random_tone <= to_integer(unsigned(lfsr(1 downto 0)));
    
    -- Debug outputs on LEDs
    LEDR(0) <= '1' when game_state = GENERATE_SEQ else '0';
    LEDR(1) <= '1' when game_state = PLAY_SEQ else '0';
    LEDR(2) <= '1' when game_state = WAIT_USER else '0';
    LEDR(3) <= '1' when game_state = WIN else '0';
    LEDR(4) <= '1' when game_state = LOSE else '0';
    LEDR(5) <= '1' when selected_tone /= TONE_NONE else '0';
    LEDR(6) <= key_pressed(0);
    LEDR(7) <= key_pressed(1);
    LEDR(8) <= key_pressed(2);
    
    -------------------------------------------------------------------------
    -- UART RX Instance (running on clock_12)
    -------------------------------------------------------------------------
    uart_rx_inst : entity work.uart_rx
        generic map (
            CLKS_PER_BIT => 104  -- 12MHz / 115200 = 104
        )
        port map (
            clk        => clock_12,
            rx         => UART_RX,
            data_out   => uart_data,
            data_valid => uart_valid
        );
    
    -------------------------------------------------------------------------
    -- LFSR Random Number Generator
    -------------------------------------------------------------------------
    process(CLOCK_50, reset_n)
    begin
        if reset_n = '0' then
            lfsr <= "10101010";
        elsif rising_edge(CLOCK_50) then
            lfsr <= lfsr(6 downto 0) & (lfsr(7) xor lfsr(5) xor lfsr(4) xor lfsr(3));
        end if;
    end process;
    
    -------------------------------------------------------------------------
    -- 12 MHz Clock Generation
    -------------------------------------------------------------------------
    process(CLOCK_50, reset_n)
    begin
        if reset_n = '0' then
            clk_12_div <= 0;
            clock_12   <= '0';
        elsif rising_edge(CLOCK_50) then
            if clk_12_div = 1 then
                clk_12_div <= 0;
                clock_12   <= not clock_12;
            else
                clk_12_div <= clk_12_div + 1;
            end if;
        end if;
    end process;
    
    AUD_XCK <= clock_12;
    
    -------------------------------------------------------------------------
    -- CDC: Sync selected_tone from clock_12 -> CLOCK_50 (two-FF)
    -------------------------------------------------------------------------
    process(CLOCK_50, reset_n)
    begin
        if reset_n = '0' then
            selected_tone_50a <= TONE_NONE;
            selected_tone_50  <= TONE_NONE;
        elsif rising_edge(CLOCK_50) then
            selected_tone_50a <= selected_tone;
            selected_tone_50  <= selected_tone_50a;
        end if;
    end process;
    
    -------------------------------------------------------------------------
    -- Game State Machine - Starts immediately when SW(0) = '1'
    -------------------------------------------------------------------------
    process(clock_12, reset_n)
    begin
        if reset_n = '0' then
            -- Reset to start state (GENERATE_SEQ, not IDLE)
            game_state <= GENERATE_SEQ;
            sequence_length <= 1;
            current_index <= 0;
            user_index <= 0;
            key_prev <= (others => '1');
            key_pressed <= (others => '0');
            selected_tone <= TONE_NONE;
            beep_counter <= 0;
            pause_counter <= 0;
            beep_playing <= '0';
            in_pause <= '0';
            wrong_button <= '0';
            
        elsif rising_edge(clock_12) then
            -- Button edge detection - MODIFIED TO USE UART
            key_prev <= KEY;
            
            -- Default: clear button presses
            key_pressed <= (others => '0');
            
            -- Physical buttons (keep for backup/testing)
            if (not KEY(0)) = '1' and key_prev(0) = '1' then
                key_pressed(0) <= '1';
            end if;
            if (not KEY(1)) = '1' and key_prev(1) = '1' then
                key_pressed(1) <= '1';
            end if;
            if (not KEY(2)) = '1' and key_prev(2) = '1' then
                key_pressed(2) <= '1';
            end if;
            if (not KEY(3)) = '1' and key_prev(3) = '1' then
                key_pressed(3) <= '1';
            end if;
            
            -- UART button presses (override physical buttons)
            if uart_valid = '1' then
                case uart_data is
                    when x"01" => key_pressed(0) <= '1';
                    when x"02" => key_pressed(1) <= '1';
                    when x"04" => key_pressed(2) <= '1';
                    when x"08" => key_pressed(3) <= '1';
                    when others => null;
                end case;
            end if;
            
            case game_state is
                
                when GENERATE_SEQ =>
                    -- Add random tone to sequence
                    game_sequence(sequence_length - 1) <= random_tone;
                    game_state <= PLAY_SEQ;
                    current_index <= 0;
                    beep_playing <= '0';
                    in_pause <= '0';
                
                when PLAY_SEQ =>
                    if current_index < sequence_length then
                        if beep_playing = '0' and in_pause = '0' then
                            -- Start playing next tone
                            selected_tone <= game_sequence(current_index);
                            beep_playing <= '1';
                            beep_counter <= 0;
                        elsif beep_playing = '1' then
                            -- Playing tone
                            if beep_counter < 6_000_000 then  -- 0.5 sec at 12MHz
                                beep_counter <= beep_counter + 1;
                            else
                                -- Done with tone, start pause
                                selected_tone <= TONE_NONE;
                                beep_playing <= '0';
                                in_pause <= '1';
                                pause_counter <= 0;
                            end if;
                        elsif in_pause = '1' then
                            -- Pause between tones
                            if pause_counter < 3_000_000 then  -- 0.25 sec
                                pause_counter <= pause_counter + 1;
                            else
                                -- Move to next tone
                                in_pause <= '0';
                                current_index <= current_index + 1;
                            end if;
                        end if;
                    else
                        -- Done playing sequence
                        game_state <= WAIT_USER;
                        user_index <= 0;
                        selected_tone <= TONE_NONE;
                    end if;
                
                when WAIT_USER =>
                    -- Handle beep playback for user input (runs continuously)
                    if selected_tone /= TONE_NONE then
                        if beep_counter < 3_000_000 then  -- Short beep
                            beep_counter <= beep_counter + 1;
                        else
                            selected_tone <= TONE_NONE;
                            -- After beep finishes, check what to do next
                            if wrong_button = '1' then
                                game_state <= LOSE;
                                wrong_button <= '0';
                            elsif user_index >= sequence_length then
                                game_state <= WIN;
                                pause_counter <= 0;  -- Reset pause counter for WIN state
                            end if;
                        end if;
                    else
                        -- Only accept new button presses when not playing a tone
                        if user_index < sequence_length then
                            -- Check button presses
                            if key_pressed(0) = '1' then
                                selected_tone <= 0;
                                beep_counter <= 0;
                                -- Check if correct BEFORE incrementing
                                if game_sequence(user_index) = 0 then
                                    user_index <= user_index + 1;
                                    wrong_button <= '0';
                                else
                                    wrong_button <= '1';  -- Mark as wrong, but play sound first
                                end if;
                            elsif key_pressed(1) = '1' then
                                selected_tone <= 1;
                                beep_counter <= 0;
                                if game_sequence(user_index) = 1 then
                                    user_index <= user_index + 1;
                                    wrong_button <= '0';
                                else
                                    wrong_button <= '1';
                                end if;
                            elsif key_pressed(2) = '1' then
                                selected_tone <= 2;
                                beep_counter <= 0;
                                if game_sequence(user_index) = 2 then
                                    user_index <= user_index + 1;
                                    wrong_button <= '0';
                                else
                                    wrong_button <= '1';
                                end if;
                            elsif key_pressed(3) = '1' then
                                selected_tone <= 3;
                                beep_counter <= 0;
                                if game_sequence(user_index) = 3 then
                                    user_index <= user_index + 1;
                                    wrong_button <= '0';
                                else
                                    wrong_button <= '1';
                                end if;
                            end if;
                        end if;
                    end if;
                
                when WIN =>
                    selected_tone <= TONE_NONE;
                    if pause_counter < 9_000_000 then
                        pause_counter <= pause_counter + 1;
                    else
                        if sequence_length < 16 then
                            sequence_length <= sequence_length + 1;
                        end if;
                        game_state <= GENERATE_SEQ;
                    end if;
                
                when LOSE =>
                    selected_tone <= TONE_NONE;
                    -- Stay in LOSE state until SW(0) is toggled (reset)
                    
            end case;
        end if;
    end process;
    
    -------------------------------------------------------------------------
    -- Sample Playback
    -------------------------------------------------------------------------
    process(CLOCK_50, reset_n)
    begin
        if reset_n = '0' then
            sample_index  <= 0;
            audio_sample  <= (others => '0');
        elsif rising_edge(CLOCK_50) then
            if sample_request = '1' then
                case selected_tone_50 is
                    when 0 => audio_sample <= TONE_0(sample_index);
                    when 1 => audio_sample <= TONE_1(sample_index);
                    when 2 => audio_sample <= TONE_2(sample_index);
                    when 3 => audio_sample <= TONE_3(sample_index);
                    when 4 => audio_sample <= (others => '0');
                    when others => audio_sample <= (others => '0');
                end case;
                
                if sample_index = 255 then
                    sample_index <= 0;
                else
                    sample_index <= sample_index + 1;
                end if;
            end if;
        end if;
    end process;
    
    -------------------------------------------------------------------------
    -- Component Instantiations
    -------------------------------------------------------------------------
    
    cfg_inst : codec_config
        port map (
            clk_50        => CLOCK_50,
            reset_n       => reset_n,
            start_cfg     => start_config,
            i2c_busy      => i2c_busy,
            i2c_done      => i2c_done,
            i2c_send_flag => i2c_send_flag,
            i2c_addr      => i2c_addr,
            i2c_data      => i2c_data,
            config_done   => config_done
        );
    
    i2c_inst : i2c
        port map (
            i2c_clk_50    => CLOCK_50,
            i2c_data      => i2c_data,
            i2c_addr      => i2c_addr,
            i2c_reset     => reset_n,
            i2c_send_flag => i2c_send_flag,
            i2c_sda       => FPGA_I2C_SDAT,
            i2c_scl       => FPGA_I2C_SCLK,
            i2c_busy      => i2c_busy,
            i2c_done      => i2c_done
        );
    
    i2s_inst : i2s_tx
        port map (
            clk_50    => CLOCK_50,
            reset_n   => reset_n,
            enable    => config_done,
            sample_l  => audio_sample,
            sample_r  => audio_sample,
            i2s_bclk  => AUD_BCLK,
            i2s_lrck  => AUD_DACLRCK,
            i2s_sdata => AUD_DACDAT,
            sample_request => sample_request
        );
        
end rtl;