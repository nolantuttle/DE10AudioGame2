library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- uart_rx: 8N1 UART receiver
-- Generic CLKS_PER_BIT = clk_freq / baud_rate
-- e.g. 12MHz / 115200 = 104
entity uart_rx is
    generic (
        CLKS_PER_BIT : integer := 104
    );
    port (
        clk        : in  std_logic;
        rx         : in  std_logic;
        data_out   : out std_logic_vector(7 downto 0);
        data_valid : out std_logic
    );
end uart_rx;

architecture rtl of uart_rx is

    type state_type is (IDLE, START, DATA, STOP);
    signal state    : state_type := IDLE;

    signal clk_cnt  : integer range 0 to CLKS_PER_BIT - 1 := 0;
    signal bit_idx  : integer range 0 to 7 := 0;
    signal rx_shift : std_logic_vector(7 downto 0) := (others => '0');

    -- Two-FF synchronizer for RX line (cross clock domain / metastability)
    signal rx_d1, rx_sync : std_logic := '1';

begin

    -- Synchronize RX input to local clock
    process(clk)
    begin
        if rising_edge(clk) then
            rx_d1   <= rx;
            rx_sync <= rx_d1;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            data_valid <= '0';  -- default: pulse for one cycle only

            case state is

                -- Wait for start bit (line goes low)
                when IDLE =>
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    if rx_sync = '0' then
                        state <= START;
                    end if;

                -- Sample in the middle of the start bit to confirm it's real
                when START =>
                    if clk_cnt = (CLKS_PER_BIT / 2) - 1 then
                        if rx_sync = '0' then
                            clk_cnt <= 0;
                            state   <= DATA;
                        else
                            state <= IDLE;  -- Glitch, ignore
                        end if;
                    else
                        clk_cnt <= clk_cnt + 1;
                    end if;

                -- Receive 8 data bits, LSB first
                when DATA =>
                    if clk_cnt = CLKS_PER_BIT - 1 then
                        clk_cnt              <= 0;
                        rx_shift(bit_idx)    <= rx_sync;
                        if bit_idx = 7 then
                            bit_idx <= 0;
                            state   <= STOP;
                        else
                            bit_idx <= bit_idx + 1;
                        end if;
                    else
                        clk_cnt <= clk_cnt + 1;
                    end if;

                -- Wait for stop bit, then output data
                when STOP =>
                    if clk_cnt = CLKS_PER_BIT - 1 then
                        data_valid <= '1';
                        data_out   <= rx_shift;
                        clk_cnt    <= 0;
                        state      <= IDLE;
                    else
                        clk_cnt <= clk_cnt + 1;
                    end if;

                when others =>
                    state <= IDLE;

            end case;
        end if;
    end process;

end rtl;