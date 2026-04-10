	soc_system u0 (
		.clk_clk                 (<connected-to-clk_clk>),                 //         clk.clk
		.fpga_cmd_export         (<connected-to-fpga_cmd_export>),         //    fpga_cmd.export
		.fpga_data_export        (<connected-to-fpga_data_export>),        //   fpga_data.export
		.fpga_debug_export       (<connected-to-fpga_debug_export>),       //  fpga_debug.export
		.gamepad_evt_readdata    (<connected-to-gamepad_evt_readdata>),    // gamepad_evt.readdata
		.gamepad_evt_read        (<connected-to-gamepad_evt_read>),        //            .read
		.gamepad_evt_waitrequest (<connected-to-gamepad_evt_waitrequest>), //            .waitrequest
		.hps_cmd_export          (<connected-to-hps_cmd_export>),          //     hps_cmd.export
		.hps_data_readdata       (<connected-to-hps_data_readdata>),       //    hps_data.readdata
		.hps_data_read           (<connected-to-hps_data_read>),           //            .read
		.hps_data_waitrequest    (<connected-to-hps_data_waitrequest>),    //            .waitrequest
		.memory_mem_a            (<connected-to-memory_mem_a>),            //      memory.mem_a
		.memory_mem_ba           (<connected-to-memory_mem_ba>),           //            .mem_ba
		.memory_mem_ck           (<connected-to-memory_mem_ck>),           //            .mem_ck
		.memory_mem_ck_n         (<connected-to-memory_mem_ck_n>),         //            .mem_ck_n
		.memory_mem_cke          (<connected-to-memory_mem_cke>),          //            .mem_cke
		.memory_mem_cs_n         (<connected-to-memory_mem_cs_n>),         //            .mem_cs_n
		.memory_mem_ras_n        (<connected-to-memory_mem_ras_n>),        //            .mem_ras_n
		.memory_mem_cas_n        (<connected-to-memory_mem_cas_n>),        //            .mem_cas_n
		.memory_mem_we_n         (<connected-to-memory_mem_we_n>),         //            .mem_we_n
		.memory_mem_reset_n      (<connected-to-memory_mem_reset_n>),      //            .mem_reset_n
		.memory_mem_dq           (<connected-to-memory_mem_dq>),           //            .mem_dq
		.memory_mem_dqs          (<connected-to-memory_mem_dqs>),          //            .mem_dqs
		.memory_mem_dqs_n        (<connected-to-memory_mem_dqs_n>),        //            .mem_dqs_n
		.memory_mem_odt          (<connected-to-memory_mem_odt>),          //            .mem_odt
		.memory_mem_dm           (<connected-to-memory_mem_dm>),           //            .mem_dm
		.memory_oct_rzqin        (<connected-to-memory_oct_rzqin>),        //            .oct_rzqin
		.reset_reset_n           (<connected-to-reset_reset_n>),           //       reset.reset_n
		.hps2_data_readdata      (<connected-to-hps2_data_readdata>),      //   hps2_data.readdata
		.hps2_data_read          (<connected-to-hps2_data_read>),          //            .read
		.hps2_data_waitrequest   (<connected-to-hps2_data_waitrequest>),   //            .waitrequest
		.fpga2_req_export        (<connected-to-fpga2_req_export>)         //   fpga2_req.export
	);

