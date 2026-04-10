	component soc_system is
		port (
			clk_clk                 : in    std_logic                     := 'X';             -- clk
			fpga_cmd_export         : in    std_logic_vector(15 downto 0) := (others => 'X'); -- export
			fpga_data_export        : in    std_logic_vector(31 downto 0) := (others => 'X'); -- export
			fpga_debug_export       : in    std_logic_vector(31 downto 0) := (others => 'X'); -- export
			gamepad_evt_readdata    : out   std_logic_vector(31 downto 0);                    -- readdata
			gamepad_evt_read        : in    std_logic                     := 'X';             -- read
			gamepad_evt_waitrequest : out   std_logic;                                        -- waitrequest
			hps_cmd_export          : out   std_logic_vector(15 downto 0);                    -- export
			hps_data_readdata       : out   std_logic_vector(31 downto 0);                    -- readdata
			hps_data_read           : in    std_logic                     := 'X';             -- read
			hps_data_waitrequest    : out   std_logic;                                        -- waitrequest
			memory_mem_a            : out   std_logic_vector(12 downto 0);                    -- mem_a
			memory_mem_ba           : out   std_logic_vector(2 downto 0);                     -- mem_ba
			memory_mem_ck           : out   std_logic;                                        -- mem_ck
			memory_mem_ck_n         : out   std_logic;                                        -- mem_ck_n
			memory_mem_cke          : out   std_logic;                                        -- mem_cke
			memory_mem_cs_n         : out   std_logic;                                        -- mem_cs_n
			memory_mem_ras_n        : out   std_logic;                                        -- mem_ras_n
			memory_mem_cas_n        : out   std_logic;                                        -- mem_cas_n
			memory_mem_we_n         : out   std_logic;                                        -- mem_we_n
			memory_mem_reset_n      : out   std_logic;                                        -- mem_reset_n
			memory_mem_dq           : inout std_logic_vector(7 downto 0)  := (others => 'X'); -- mem_dq
			memory_mem_dqs          : inout std_logic                     := 'X';             -- mem_dqs
			memory_mem_dqs_n        : inout std_logic                     := 'X';             -- mem_dqs_n
			memory_mem_odt          : out   std_logic;                                        -- mem_odt
			memory_mem_dm           : out   std_logic;                                        -- mem_dm
			memory_oct_rzqin        : in    std_logic                     := 'X';             -- oct_rzqin
			reset_reset_n           : in    std_logic                     := 'X';             -- reset_n
			hps2_data_readdata      : out   std_logic_vector(31 downto 0);                    -- readdata
			hps2_data_read          : in    std_logic                     := 'X';             -- read
			hps2_data_waitrequest   : out   std_logic;                                        -- waitrequest
			fpga2_req_export        : in    std_logic_vector(31 downto 0) := (others => 'X')  -- export
		);
	end component soc_system;

	u0 : component soc_system
		port map (
			clk_clk                 => CONNECTED_TO_clk_clk,                 --         clk.clk
			fpga_cmd_export         => CONNECTED_TO_fpga_cmd_export,         --    fpga_cmd.export
			fpga_data_export        => CONNECTED_TO_fpga_data_export,        --   fpga_data.export
			fpga_debug_export       => CONNECTED_TO_fpga_debug_export,       --  fpga_debug.export
			gamepad_evt_readdata    => CONNECTED_TO_gamepad_evt_readdata,    -- gamepad_evt.readdata
			gamepad_evt_read        => CONNECTED_TO_gamepad_evt_read,        --            .read
			gamepad_evt_waitrequest => CONNECTED_TO_gamepad_evt_waitrequest, --            .waitrequest
			hps_cmd_export          => CONNECTED_TO_hps_cmd_export,          --     hps_cmd.export
			hps_data_readdata       => CONNECTED_TO_hps_data_readdata,       --    hps_data.readdata
			hps_data_read           => CONNECTED_TO_hps_data_read,           --            .read
			hps_data_waitrequest    => CONNECTED_TO_hps_data_waitrequest,    --            .waitrequest
			memory_mem_a            => CONNECTED_TO_memory_mem_a,            --      memory.mem_a
			memory_mem_ba           => CONNECTED_TO_memory_mem_ba,           --            .mem_ba
			memory_mem_ck           => CONNECTED_TO_memory_mem_ck,           --            .mem_ck
			memory_mem_ck_n         => CONNECTED_TO_memory_mem_ck_n,         --            .mem_ck_n
			memory_mem_cke          => CONNECTED_TO_memory_mem_cke,          --            .mem_cke
			memory_mem_cs_n         => CONNECTED_TO_memory_mem_cs_n,         --            .mem_cs_n
			memory_mem_ras_n        => CONNECTED_TO_memory_mem_ras_n,        --            .mem_ras_n
			memory_mem_cas_n        => CONNECTED_TO_memory_mem_cas_n,        --            .mem_cas_n
			memory_mem_we_n         => CONNECTED_TO_memory_mem_we_n,         --            .mem_we_n
			memory_mem_reset_n      => CONNECTED_TO_memory_mem_reset_n,      --            .mem_reset_n
			memory_mem_dq           => CONNECTED_TO_memory_mem_dq,           --            .mem_dq
			memory_mem_dqs          => CONNECTED_TO_memory_mem_dqs,          --            .mem_dqs
			memory_mem_dqs_n        => CONNECTED_TO_memory_mem_dqs_n,        --            .mem_dqs_n
			memory_mem_odt          => CONNECTED_TO_memory_mem_odt,          --            .mem_odt
			memory_mem_dm           => CONNECTED_TO_memory_mem_dm,           --            .mem_dm
			memory_oct_rzqin        => CONNECTED_TO_memory_oct_rzqin,        --            .oct_rzqin
			reset_reset_n           => CONNECTED_TO_reset_reset_n,           --       reset.reset_n
			hps2_data_readdata      => CONNECTED_TO_hps2_data_readdata,      --   hps2_data.readdata
			hps2_data_read          => CONNECTED_TO_hps2_data_read,          --            .read
			hps2_data_waitrequest   => CONNECTED_TO_hps2_data_waitrequest,   --            .waitrequest
			fpga2_req_export        => CONNECTED_TO_fpga2_req_export         --   fpga2_req.export
		);

