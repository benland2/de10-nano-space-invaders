
module soc_system (
	clk_clk,
	fpga_cmd_export,
	fpga_data_export,
	fpga_debug_export,
	gamepad_evt_readdata,
	gamepad_evt_read,
	gamepad_evt_waitrequest,
	hps_cmd_export,
	hps_data_readdata,
	hps_data_read,
	hps_data_waitrequest,
	memory_mem_a,
	memory_mem_ba,
	memory_mem_ck,
	memory_mem_ck_n,
	memory_mem_cke,
	memory_mem_cs_n,
	memory_mem_ras_n,
	memory_mem_cas_n,
	memory_mem_we_n,
	memory_mem_reset_n,
	memory_mem_dq,
	memory_mem_dqs,
	memory_mem_dqs_n,
	memory_mem_odt,
	memory_mem_dm,
	memory_oct_rzqin,
	reset_reset_n,
	hps2_data_readdata,
	hps2_data_read,
	hps2_data_waitrequest,
	fpga2_req_export);	

	input		clk_clk;
	input	[15:0]	fpga_cmd_export;
	input	[31:0]	fpga_data_export;
	input	[31:0]	fpga_debug_export;
	output	[31:0]	gamepad_evt_readdata;
	input		gamepad_evt_read;
	output		gamepad_evt_waitrequest;
	output	[15:0]	hps_cmd_export;
	output	[31:0]	hps_data_readdata;
	input		hps_data_read;
	output		hps_data_waitrequest;
	output	[12:0]	memory_mem_a;
	output	[2:0]	memory_mem_ba;
	output		memory_mem_ck;
	output		memory_mem_ck_n;
	output		memory_mem_cke;
	output		memory_mem_cs_n;
	output		memory_mem_ras_n;
	output		memory_mem_cas_n;
	output		memory_mem_we_n;
	output		memory_mem_reset_n;
	inout	[7:0]	memory_mem_dq;
	inout		memory_mem_dqs;
	inout		memory_mem_dqs_n;
	output		memory_mem_odt;
	output		memory_mem_dm;
	input		memory_oct_rzqin;
	input		reset_reset_n;
	output	[31:0]	hps2_data_readdata;
	input		hps2_data_read;
	output		hps2_data_waitrequest;
	input	[31:0]	fpga2_req_export;
endmodule
