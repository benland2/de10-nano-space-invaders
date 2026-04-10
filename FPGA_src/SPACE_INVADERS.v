/**
Top Module for project Space Invaders

Author: Benoit Gozzo
Date creation: 24/02/2026

**/

module SPACE_INVADERS(
	//** input **
	input wire clock50_1,
	input wire clock50_2,
	input wire rst_n,
	
	// ********************************************** //
	// ** HDMI CONNECTIONS **
	
	// AUDIO
	output HDMI_I2S, // Data I2S
	output HDMI_MCLK,//Master Clock
	output HDMI_LRCLK,//Left and Right Clock
	output HDMI_SCLK,//Serial Clock
	
	// VIDEO
	output [23:0] HDMI_TX_D, // RGBchannel
	output HDMI_TX_VS, // vsync
	output HDMI_TX_HS, // hsync
	output HDMI_TX_DE, // dataEnable
	output HDMI_TX_CLK, // vgaClock
	
	// REGISTERS AND CONFIG LOGIC
	// HPD vient du connecteur
	input HDMI_TX_INT,
	inout HDMI_I2C_SDA, 	// HDMI i2c data
	output HDMI_I2C_SCL, // HDMI i2c clock
	//output READY 			// HDMI is ready signal from i2c module
	output [7:0] led,	// HDMI is ready signal from i2c module
	
	//////////// HPS //////////
    output   [14: 0]    HPS_DDR3_ADDR,
    output   [ 2: 0]    HPS_DDR3_BA,
    output              HPS_DDR3_CAS_N,
    output              HPS_DDR3_CK_N,
    output              HPS_DDR3_CK_P,
    output              HPS_DDR3_CKE,
    output              HPS_DDR3_CS_N,
    output   [ 3: 0]    HPS_DDR3_DM,
    inout    [31: 0]    HPS_DDR3_DQ,
    inout    [ 3: 0]    HPS_DDR3_DQS_N,
    inout    [ 3: 0]    HPS_DDR3_DQS_P,
    output              HPS_DDR3_ODT,
    output              HPS_DDR3_RAS_N,
    output              HPS_DDR3_RESET_N,
    input               HPS_DDR3_RZQ,
    output              HPS_DDR3_WE_N
	
	// ********************************************** //
);

parameter INTRO_LETTERS = 160;
parameter ALERT_LETTERS = 40;
parameter FILESIZE_WIDTH = 25; //(26 - 1)
parameter VIDEO_START = 14'h2400;
parameter AUDIO_BYTES = 1;//On émule des audios de 1 octet

parameter NUM_FCMD_SPEEDTEST = 9;
parameter NUM_FCMD_READ2CHAR = 3;
parameter NUM_FCMD_READ1CHAR = 31;
parameter NUM_FCMD_READ4CHAR = 34;
parameter NUM_FCMD_STOPREAD = 4;
parameter NUM_FCMD_GETSIZE = 6;
parameter NUM_FCMD_GETNBFILES = 1;
parameter NUM_FCMD_GETNAME = 2;
parameter NUM_FCMD_IDLE = 5;

parameter NUM_HPS_READSTOP = 6;
parameter NUM_HPS_FILESIZE = 8;
parameter NUM_HPS_RCV1CHAR = 9;

parameter GAMEPAD_AXE_CENTER = 0;
parameter GAMEPAD_AXE_TOP = 511;//-1
parameter GAMEPAD_AXE_BOTTOM = 1;
parameter GAMEPAD_AXE_LEFT = 511;//-1
parameter GAMEPAD_AXE_RIGHT = 1;
parameter GAMEPAD_AXE_X = 16;
parameter GAMEPAD_AXE_Y = 17;
parameter GAMEPAD_BTN_A = 9'd306;
//parameter GAMEPAD_BTN_A = 9'd290;// for other gamepad
parameter GAMEPAD_BTN_B = 9'd305;
parameter GAMEPAD_BTN_X = 9'd307;
parameter GAMEPAD_BTN_Y = 9'd304;
//parameter GAMEPAD_BTN_Y = 9'd288;// for other gamepad
parameter GAMEPAD_BTN_L1 = 308;
parameter GAMEPAD_BTN_L2 = 310;
parameter GAMEPAD_BTN_L3 = 314;
parameter GAMEPAD_BTN_R1 = 309;
parameter GAMEPAD_BTN_R2 = 9'd311;
parameter GAMEPAD_BTN_R3 = 315;
parameter GAMEPAD_BTN_STA = 313;//Start
parameter GAMEPAD_BTN_SEL = 312;//Select

//Paramètres pour avoir une clock CPU synchro (à 2MHz) avec le CPU HDMI (à 25 MHz) : cela évite d'avoir à gérer les signaux async.
//Penser à adapter selon la fréquence du HDMI.
////parameter CLOCK_DIVISOR1 = 6;
//parameter CLOCK_DIVISOR1 = 12;
parameter CLOCK_DIVISOR1 = 3;
parameter CLOCK_DIVISOR2 = 7;
parameter CLOCK_CATCHUP = 3;


wire rstSys_n,clockAudio,resetAudio_n;
wire rst = ~rst_n;

// ** Variables pour l'écran de démarrage
reg [3:0] system_state;// 0 => Check disc drive, 1 => check if disc inserted, 2 => load game, 3 => ready to play
reg [16:0] sys_Count;
reg hps_ready;
reg led_filer2;

// ** Variables pour générer l'horloge CPU de la borne d'arcade
reg [4:0] clockDivisor_counter;
reg [4:0] clockCatchup_counter;
reg clockDivisor_last;
reg clockCPU;

// ** Gestion de l'audio **
reg sound2_on;
reg [3:0] sound1_wav;
reg [3:0] sound2_wav;
reg sound1_loop;
wire [7:0] cpu_sound1_bits;
reg [7:0] sound1_bits_handle;
wire [7:0] cpu_sound2_bits;
//reg [7:0] sound2_bits_handle;
reg [7:0] sound1_reqId;
reg [7:0] sound2_reqId;
//wire [7:0] cpu_sound2_reqId;
reg [7:0] sound1_reqId_sync;
reg [7:0] sound2_reqId_sync;
wire sound1_inProgress;
wire sound1_changed;
reg sound2_inProgress;
reg [7:0] sound1_prev;
reg [7:0] sound2_prev;
reg request_for_audio;

reg [FILESIZE_WIDTH:0] AUDIO_data_size;
reg [FILESIZE_WIDTH:0] AUDIO2_data_size;
reg [15:0] AUDIO_header_offset;
reg [15:0] AUDIO2_header_offset;
reg [31:0] AUDIO_file_data;//On analyse 4 octets avec cette variable
reg [31:0] AUDIO2_file_data;//On analyse 4 octets avec cette variable
reg [15:0] AUDIO_header_flag;
reg [15:0] AUDIO2_header_flag;
reg [23:0] AUDIO_header_count;
reg [23:0] AUDIO2_header_count;
reg [7:0] AUDIO_fmt_count;
reg [7:0] AUDIO2_fmt_count;
reg [3:0] AUDIO_data_count;
reg [3:0] AUDIO2_data_count;
reg [2:0] AUDIO_channels;
reg [2:0] AUDIO2_channels;
reg [FILESIZE_WIDTH:0] AUDIO_count;
reg [FILESIZE_WIDTH:0] AUDIO2_count;
reg [31:0] AUDIO_data;
wire [31:0] AUDIO_sample;
reg [31:0] AUDIO2_data;
wire [31:0] AUDIO2_sample;
reg AUDIO_wrreq;
reg AUDIO2_wrreq;
wire AUDIO_fifo_full;
wire AUDIO2_fifo_full;
wire AUDIO_samples_empty;
wire AUDIO2_samples_empty;
wire rdclkAudio;

reg [31:0] filer_data_delayed;
reg filer_delayed;
reg [31:0] filer2_data_delayed;
reg filer2_delayed;

// ** Variables pour lire la rom **
reg [FILESIZE_WIDTH:0] FILE_SIZE;
reg [FILESIZE_WIDTH:0] FILE2_size;
reg [FILESIZE_WIDTH:0] ROM_SIZE_OFFSET;
reg game_mem_wren;
reg game_mem_wren_de;
reg [7:0] game_mem_wdata;
reg [11:0] game_mem_waddr;
reg [11:0] rom_addr;
reg [3:0] file_num;

// ** Variables pour écrire la rom en mémoire **
reg cpu_rom_save1;
reg cpu_rom_save2;
reg[7:0] cpu_rom_wdata1;
reg[7:0] cpu_rom_wdata2;
reg[12:0] cpu_rom_waddr1;
reg[12:0] cpu_rom_waddr2;


// ** Variables pour Avalon-MM **
wire [15:0] filer_cmd;
wire [31:0] filer_data;
wire filer_waitrequest;
reg filer_read;
reg filer_data_ready;

reg [15:0] filer_cmd_read;

reg [15:0] fpga_cmd;
reg [31:0] fpga_data;
reg [31:0] fpga_debug;

reg [31:0] fpga2_req;
wire [31:0] filer2_data;
wire filer2_waitrequest;
reg filer2_read;
reg filer2_data_ready;

// ** Variables pour Gamepad **
wire gamepad_evt_waitrequest;
wire [31:0] gamepad_evt_readdata;
reg gamepad_evt_read;
reg gamepad_ready;
reg gamepad_on;
reg [8:0] gamepad_axe;
reg [15:0] gamepad_key = 0;

// ** Variables pour l'affichage **
reg [9:0] vgaInstruction;//Permet de déclencher le calcul de la frame
wire [9:0] vgaInstructionDone;//Permet de déclencher le calcul de la 
reg [9:0] vga_textAddr;//Adresse dans la RAM du VGA
reg [9:0] vga_textAddr_de1;//Adresse dans la RAM du VGA avec 1 delai: 1 pour la ROM

wire [7:0] rom_textVal;
wire [9:0] rom_textAddr;//Adresse dans la rom
reg [9:0] rom_textAddr_de1;//Adresse dans la rom avec décalage de 1

wire [7:0] rom_alertVal;
reg [9:0] rom_alertAddr;//Adresse dans la rom
reg [7:0] rom_alertID;

wire screen_mode;
wire hdmi_rdreq;
wire [14:0] game_pixel;//draw_color,draw_x,draw_y

// Variables pour le rendu vidéo
wire [12:0] cpu_mem_rdaddr;
wire [7:0] cpu_mem_rdata;
wire [9:0] cpu_instrctionNum;//Vars pour gérer la synchro entre le CPU et HDMI
wire [9:0] cpu_instrctionSync;
wire [7:0] cpu_int_rst;//Gestion des interruptions avec l'ISR (déclenché par la vidéo: lignes 96 et 224)

// Variables for SIMULATION
reg [7:0] simul_counter1;
reg drawQ_empty = 1;

initial begin
	system_state = 0;
	fpga_cmd = 0;
	clockDivisor_counter = 0;
	clockCatchup_counter = 0;
	clockDivisor_last = 0;
	clockCPU = 0;
	vgaInstruction = 0;
	file_num = 1;
	//screen_mode = 0;
	sound1_reqId = 0;
	sound2_reqId = 0;
	
	// SIMULATION
	simul_counter1 = 0;
	drawQ_empty = 1;
end

// ** VGA CLOCK **
pll_hdmi pll_hdmi(
	.refclk(clock50_1),
	.rst(rst),
	
	.outclk_0(clockHDMI),
	.locked(locked)
);

// ** AUDIO CLOCK **
pll_audio pll_audio(
	.refclk(clock50_2),
	.rst(rst),
	
	.outclk_0(clockAudio),//11.290322 MHz pour l'audio en 44.1 KHz (Formule: 44.1 * 2 * 16 * (4 * 2) / Freq * nb_channels * sample_size * ((MCLK_DIVISEUR + 1) * 2 ) )
	.locked(resetAudio_n)
);


// ** Boucle test qui génère la clock 2MHz du Space Invaders (en réalité ici c'est 8MHz, on bricole avec une mise en attente sur les cycles coté CPU) **
always @(posedge clock50_1 or negedge rst_n) begin
	if(!rst_n)
	begin
		clockDivisor_counter <= 0;
		clockCatchup_counter <= 0;
		clockDivisor_last <= 0;
		clockCPU <= 0;
	end
	else begin
		
		if(clockDivisor_counter == 0) clockCPU <= ~clockCPU;
		
		if(clockDivisor_counter == (CLOCK_DIVISOR1 - 1) ) begin
			clockDivisor_counter <= 0;
		end
		else clockDivisor_counter <= clockDivisor_counter + 1;
	end
end

// ** Boucle qui génère une clock CPU synchro avec le HDMI
always @(posedge clockHDMI or negedge rst_n) begin
	if(!rst_n)
	begin
		////clockDivisor_counter <= 0;
		////clockCatchup_counter <= 0;
		////clockDivisor_last <= 0;
		////clockCPU <= 0;
	end
	else begin
		
		////if(clockDivisor_counter == 0) clockCPU <= ~clockCPU;
		
		////if(clockDivisor_counter == (CLOCK_DIVISOR1 - 1) ) begin
		////	clockDivisor_counter <= 0;
		////end
		////else clockDivisor_counter <= clockDivisor_counter + 1;
		
		/*if(clockDivisor_last == 0) begin
		
			if(clockCatchup_counter == CLOCK_CATCHUP ) begin
				if(clockDivisor_counter == (CLOCK_DIVISOR2 - 1) ) begin
					clockDivisor_counter <= 0;
					clockCatchup_counter <= 0;
					clockDivisor_last <= 1;
				end
				else clockDivisor_counter <= clockDivisor_counter + 1;
				
			end
			else begin
				if(clockDivisor_counter == (CLOCK_DIVISOR1 - 1) ) begin
					clockDivisor_counter <= 0;
					clockCatchup_counter <= (clockCatchup_counter + 1);
				end
				else clockDivisor_counter <= clockDivisor_counter + 1;
				
			end
			
		end
		else begin
		
			if(clockCatchup_counter == 0 ) begin
				if(clockDivisor_counter == (CLOCK_DIVISOR2 - 1) ) begin
					clockDivisor_counter <= 0;
					clockCatchup_counter <= (clockCatchup_counter + 1);
				end
				else clockDivisor_counter <= clockDivisor_counter + 1;
				
			end
			else begin
				if(clockDivisor_counter == (CLOCK_DIVISOR1 - 1) ) begin
					clockDivisor_counter <= 0;
					
					if(clockCatchup_counter == CLOCK_CATCHUP ) begin
						clockCatchup_counter <= 0;
						clockDivisor_last <= 0;
					end
					else clockCatchup_counter <= (clockCatchup_counter + 1);
				end
				else clockDivisor_counter <= clockDivisor_counter + 1;
				
			end
			
		end*/
		
	end
end

// ** ROM for introduction page
rom_intro rom_intro(
	.address(rom_textAddr),
	.clock(clockCPU),
	.q(rom_textVal)
);

// ** ROM for alerts
rom_alerts rom_alerts(
	.address(rom_alertAddr + rom_alertID),
	.clock(clockCPU),
	.q(rom_alertVal)
);

// ** VGA MAIN CONTROLLER **
vgaHdmi vgaHdmi (
	// input
	.clock	(clockHDMI),
	.clock50	(clock50_1),
	.reset	(~locked),
	
	// ouput
	.hsync	(HDMI_TX_HS),
	.vsync	(HDMI_TX_VS),
	.dataEnable	(HDMI_TX_DE),
	.vgaClock	(HDMI_TX_CLK),
	.RGBchannel	(HDMI_TX_D),
	
	// instructions pour dessin de l'écran
	.screen_mode(screen_mode),
	.instructionNum ( (vgaInstruction > 0) ? vgaInstruction : vgaInstructionDone),//On commence à dessiner seulement si on a le 1er texte de la ROM
	.instructionPrev (vgaInstructionDone),
	.instructionAddr(vga_textAddr_de1),
	.instructionData( (vgaInstruction <= INTRO_LETTERS)? rom_textVal : rom_alertVal  ),
	
	// Vars to draw GAME pixels
	.game_rdreq(hdmi_rdreq),
	.game_pixel(game_pixel),
	.game_dataEmpty(drawQ_empty),
	
	// Variables pour gérer le rendu
	.cpu_instrctionNum(cpu_instrctionNum),
	.cpu_instrctionSync(cpu_instrctionSync),
	.cpu_mem_rdaddr(cpu_mem_rdaddr),
	.cpu_mem_rdata(cpu_mem_rdata),
	.cpu_int_rst(cpu_int_rst)
	
);

// ** I2C Interface for ADV7513 initial config **
I2C_HDMI_Config I2C_HDMI_Config(
	.iCLK				(clock50_1),
	.iRST_N			(rst_n),
	.I2C_SCLK		(HDMI_I2C_SCL),
	.I2C_SDAT		(HDMI_I2C_SDA),
	.HDMI_TX_INT	(HDMI_TX_INT),
	.READY			(led[7:6])
);

soc_system u0(
	//SD Controller
	.hps_cmd_export(filer_cmd),
	.hps_data_readdata(filer_data),
	.hps_data_read(filer_read),
	.hps_data_waitrequest(filer_waitrequest),
	
	.fpga_cmd_export(fpga_cmd),
	.fpga_data_export(fpga_data),
	.fpga_debug_export(fpga_debug),

	//Gamepad
	.gamepad_evt_readdata(gamepad_evt_readdata),
	.gamepad_evt_read(gamepad_evt_read),
	.gamepad_evt_waitrequest(gamepad_evt_waitrequest),
	
	//Output Port 5
	.fpga2_req_export(fpga2_req),
	.hps2_data_readdata(filer2_data),
	.hps2_data_read(filer2_read),
	.hps2_data_waitrequest(filer2_waitrequest),

	//Clock&Reset
	.clk_clk(clockCPU),                                      //                            clk.clk
	.reset_reset_n(rst_n),                            //                          reset.reset_n
	//HPS ddr3
	.memory_mem_a(HPS_DDR3_ADDR),                                //                         memory.mem_a
	.memory_mem_ba(HPS_DDR3_BA),                                 //                               .mem_ba
	.memory_mem_ck(HPS_DDR3_CK_P),                               //                               .mem_ck
	.memory_mem_ck_n(HPS_DDR3_CK_N),                             //                               .mem_ck_n
	.memory_mem_cke(HPS_DDR3_CKE),                               //                               .mem_cke
	.memory_mem_cs_n(HPS_DDR3_CS_N),                             //                               .mem_cs_n
	.memory_mem_ras_n(HPS_DDR3_RAS_N),                           //                               .mem_ras_n
	.memory_mem_cas_n(HPS_DDR3_CAS_N),                           //                               .mem_cas_n
	.memory_mem_we_n(HPS_DDR3_WE_N),                             //                               .mem_we_n
	.memory_mem_reset_n(HPS_DDR3_RESET_N),                       //                               .mem_reset_n
	.memory_mem_dq(HPS_DDR3_DQ),                                 //                               .mem_dq
	.memory_mem_dqs(HPS_DDR3_DQS_P),                             //                               .mem_dqs
	.memory_mem_dqs_n(HPS_DDR3_DQS_N),                           //                               .mem_dqs_n
	.memory_mem_odt(HPS_DDR3_ODT),                               //                               .mem_odt
	.memory_mem_dm(HPS_DDR3_DM),                                 //                               .mem_dm
	.memory_oct_rzqin(HPS_DDR3_RZQ),                             //                               .oct_rzqin

);

// ** CPU - Space Invaders **
cpu cpu0(
	.clk_2MHz(clockCPU),
	.reset(rst),
	.game_ready(screen_mode),
	
	.draw_x(draw_x),
	.draw_y(draw_y),
	.draw_color(draw_color),
	.draw_clear(draw_clear),
	.draw_wren(draw_wren),
	.drawQ_full(drawQ_full),
	.drawQ_empty(drawQ_empty),
	
	.gamepad_key(gamepad_key),
	.led2(led[2]),
	
	.VIDEO_mem_rdaddr(cpu_mem_rdaddr + VIDEO_START),
	.cpu_mem_rdata(cpu_mem_rdata),
	.cpu_instrctionNum(cpu_instrctionNum),
	.cpu_instrctionSync(cpu_instrctionSync),
	
	.cpu_rom_save(cpu_rom_save1),
	.cpu_rom_wdata(cpu_rom_wdata1),
	.cpu_rom_waddr(cpu_rom_waddr1),
	
	.sound1_bits(cpu_sound1_bits),
	.sound2_bits(cpu_sound2_bits),
	
	.int_rst(cpu_int_rst)
);

assign screen_mode = (system_state == 3) ? 1 : 0;


//Boucle système qui va gérer l'affichage du texte
always @(posedge clockCPU or negedge rst_n)
begin
	if(!rst_n)
	begin
		sys_Count <= 0;
		//screen_mode <= 0;
		//vgaInstruction <= 0;
	end
	else begin
		if(sys_Count == 0) begin
			//if (system_state == 3) begin
			if (screen_mode == 1) begin
				//Affichage de l'écran de Space Invaders
				//screen_mode <= 1;
			end
			else begin
				//Envoi d'instruction au VGA
				if(vgaInstruction < (INTRO_LETTERS) ) begin // Affichage du texte d'intro
					//Permet d'assurer la synchro
					if(vgaInstruction == 0 || vgaInstruction == vgaInstructionDone)
					begin 
						// si rom_textAddr_de1 = 0: on n'a pas encore la 1ère valeur de la ROM, donc pas d'instruction
						if(rom_textAddr_de1 > 0) begin
							vga_textAddr_de1 <= vga_textAddr - 1;
							
							//Le changement de valeur sur vgaInstruction permet de faire exécuter une nouvelle tache au module VGA
							vgaInstruction <= vgaInstruction + 1;
						end
						
						rom_textAddr_de1 <= rom_textAddr_de1 + 1;
						
						//vga_textAddr permet de calculer la prochaine position dans la RAM
						if(vgaInstruction == (INTRO_LETTERS - 1) ) begin
							//Affichage des infos après l'intro
							rom_alertAddr <= 0;//Prépare l'adresse pour la prochaine lecture
							vga_textAddr <= vga_textAddr + 1;
							
							if (system_state == 0) begin
								rom_alertID <= 0;//Connect disc drive
							end
							else if (system_state == 1) begin
								rom_alertID <= 40;//Please insert disc
							end
							else begin
								rom_alertID <= 80;//None
							end
						end
						else begin
							vga_textAddr <= vga_textAddr + 1;
						end
					end
				end
				else begin
					//Affichage des alertes ou infos	
					if(vgaInstruction < (INTRO_LETTERS + ALERT_LETTERS) ) begin
						if(vgaInstruction == vgaInstructionDone) begin
							vga_textAddr_de1 <= vga_textAddr - 1;
							vgaInstruction <= vgaInstruction + 1;
							vga_textAddr <= vga_textAddr + 1;
							
							rom_alertAddr <= rom_alertAddr + 1;
							if(vgaInstruction == (INTRO_LETTERS + ALERT_LETTERS - 1) ) begin
								rom_alertAddr <= 0;//Prépare l'adresse pour la prochaine lecture
								
								if (system_state == 0) begin
									rom_alertID <= 0;//Connect disc drive
								end
								else if (system_state == 1) begin
									rom_alertID <= 40;//Please insert disc
								end
								else begin
									rom_alertID <= 80;//None
								end
							end
							
						end
					end
					else begin
						if(vgaInstruction == vgaInstructionDone) begin
							vgaInstruction <= INTRO_LETTERS + 1;
							rom_alertAddr <= rom_alertAddr + 1;//Prépare l'adresse pour la prochaine lecture
							vga_textAddr <= INTRO_LETTERS + 2;
							vga_textAddr_de1 <= INTRO_LETTERS + 0;
						end
					end
				end
			end
		end
		
		if(sys_Count >= 17'd49999) begin
			sys_Count <= 0;
			
			// SIMULATION
			//if(simul_counter1 < 100) simul_counter1 <= simul_counter1 + 1;
			//if(simul_counter1 == 90) FILE_SIZE <= 1;
			
		end
		else sys_Count <= sys_Count + 1;
	end
end

// Boucle pour gérer le disc drive
/*always @(filer_cmd, filer_data, file_num) begin
	if(file_num > 4 && filer_cmd == 7) system_state <= 3;
	else if(filer_cmd == 1) begin
		system_state <= 1;
	end
	else begin
		if(filer_cmd == 2) begin
			if(filer_data == 0) system_state <= 1;
			else system_state <= 2;
		end
		else if(filer_cmd == 7) system_state <= 1;
		else if(filer_cmd == 8) system_state <= 2;
		else if(filer_cmd == 6) system_state <= 2;
		else system_state <= 0;
	end
	
end*/

fifo_audio fifo_audio1(
	.data(AUDIO_data),
	.wrclk(clockCPU),
	.wrreq(AUDIO_wrreq),
	
	//.rdclk(HDMI_LRCLK),
	.rdclk(rdclkAudio),
	.rdreq(request_for_audio),
	.q(AUDIO_sample),
	
	.rdempty(AUDIO_samples_empty),
	.wrfull(AUDIO_fifo_full)
);

fifo_audio fifo_audio2(
	.data(AUDIO2_data),
	.wrclk(clockCPU),
	.wrreq(AUDIO2_wrreq),
	
	.rdclk(rdclkAudio),
	.rdreq(sound2_inProgress),
	.q(AUDIO2_sample),
	
	.rdempty(AUDIO2_samples_empty),
	.wrfull(AUDIO2_fifo_full)
);


// ** AUDIO **
AUDIO_IF u_AVG(
	.clk(clockAudio),
	.reset_n(resetAudio_n),// ON par défaut
	.mclk(HDMI_MCLK),
	.sclk(HDMI_SCLK),
	.lrclk(HDMI_LRCLK),
	.readclk(rdclkAudio),
	.i2s(HDMI_I2S),
	.audio_on(request_for_audio),
	.audio2_on(sound2_on),
	.audio_sample(AUDIO_sample),
	.audio2_sample(AUDIO2_sample),
	
	.audio_channels(1),
	.audio_sample_avail(~audio_samples_empty),
	.led_audio(led[5])
);

assign sound1_inProgress = ( AUDIO_header_flag==3 && filer_cmd == NUM_HPS_RCV1CHAR );
//assign sound1_changed = (sound1_reqId != sound1_reqId_sync && sound1_prev != cpu_sound1_bits);
assign sound1_changed = (sound1_reqId != sound1_reqId_sync);

//Boucle système qui lit les events en attente de la carte SD
always @(posedge clockCPU or negedge rst_n)
begin
	if(!rst_n)
	begin
		filer_read <= 0;
		FILE_SIZE <= 0;
		ROM_SIZE_OFFSET <= 0;
		hps_ready <= 0;
		fpga_cmd <= 0;
		fpga_debug <= 0;
		file_num <= 1;
		cpu_rom_save1 <= 0;
		cpu_rom_save2 <= 0;
		system_state <= 0;
		sound1_reqId_sync <= 0;
		request_for_audio <= 0;
		AUDIO_wrreq <= 0;
		filer_delayed <= 0;
		//sound1_inProgress <= 0;
	end
	else begin
		filer_data_ready <= !filer_waitrequest;//Permet de rattraper le décalage lié à la FIFO
		
		if(!filer_waitrequest) begin
				filer_read <= 1;
		end
		else begin
			//if(system_state == 3 && !request_for_audio) filer_read <= 0;//Plus besoin de continuer à lire la carte SD
			//else filer_read <= 1;
			
			/*if(cpu_rom_save1) begin // Copie la rom avec un décalage pour éviter la métastabilité
				cpu_rom_save2 <= 1;
				cpu_rom_wdata2 <= cpu_rom_wdata1;
				cpu_rom_waddr2 <= cpu_rom_waddr1;
			end
			else cpu_rom_save2 <= 0;*/
			
			if(filer_data_ready || filer_delayed) begin
				if(filer_delayed) filer_delayed <= 0;
				
				if(filer_cmd == 1) begin
					file_num <= 1;
					hps_ready <= 0;
					AUDIO_header_flag <= 0;
					fpga_debug <= NUM_FCMD_GETNBFILES;
					fpga_cmd <= NUM_FCMD_GETNBFILES;
					system_state <= 1;
				end
				else begin
					//if (system_state == 3 && (cpu_sound1_reqId != sound1_reqId_sync && sound1_prev != cpu_sound1_bits ) && !sound1_inProgress) begin
					if (system_state == 3 && sound1_changed && !sound1_inProgress) begin
					//if (system_state == 3 && (sound1_reqId != sound1_reqId_sync ) && !sound1_inProgress ) begin
						// ** Bloque qui gère les sons du CPU **
						//Si un son est en cours: on attend la solution de lissage
						
						if(filer_cmd == 5 || filer_cmd == 10 || filer_cmd == NUM_HPS_RCV1CHAR ) begin // Un son est en cours, il faut l'interrompre
						//if(0) begin
							fpga_cmd <= NUM_FCMD_STOPREAD;
							fpga_debug <= sound1_reqId;
							
						end
						else begin
							//On récupère les datas de l'audio à lire							
							request_for_audio <= (sound1_bits_handle != 0);
							
							sound1_reqId_sync <= sound1_reqId;
							
							//Get size of file on Output 3 {cpu_sound1_wav}
							fpga_data <= sound1_wav;
							fpga_cmd <= NUM_FCMD_GETSIZE;
							fpga_debug <= sound1_bits_handle;
								
						end
					end
					else if(filer_cmd == 2) begin //Return nb files						
						if(filer_data == 0) begin
							fpga_debug <= NUM_FCMD_GETNBFILES;
							fpga_cmd <= NUM_FCMD_GETNBFILES;
						end
						else begin 
							fpga_data <= file_num;//Get size of file number {file_num}
							fpga_debug <= NUM_FCMD_GETSIZE;
							fpga_cmd <= NUM_FCMD_GETSIZE;
						end
					end
					else if(filer_cmd == 8) begin // size file received
						hps_ready <= 1;
						FILE_SIZE <= filer_data[FILESIZE_WIDTH:0];
						
						if(request_for_audio) begin
							AUDIO_data_size <= 0;//DataSize inconnu
							AUDIO_header_flag <= 0;// Recherche du bloc fmt_
							AUDIO_header_count <= 0;
							AUDIO_data_count <= 0;
							AUDIO_file_data <= 0;
						end
						else begin
							if(file_num == 1) ROM_SIZE_OFFSET <= 0;
							else ROM_SIZE_OFFSET <= ROM_SIZE_OFFSET + FILE_SIZE;
							
							rom_addr <= 0;
							fpga_debug <= filer_data[FILESIZE_WIDTH:0];
						end
						
						fpga_data <= 0;
						fpga_cmd <= NUM_FCMD_READ1CHAR;
					end
					else if(filer_cmd == 5 || filer_cmd == 10 || sound1_inProgress ) begin // 2 or 4 char received => audio content
						
						if(filer_delayed) begin
							if(AUDIO_channels == 2) AUDIO_data <= filer_data_delayed[31:0];
							else AUDIO_data <= {14'd0,filer_data_delayed[17:0]};
							
							fpga_debug <= {16'd0,filer_data_delayed[15:0]};
						end
						else begin
							if(AUDIO_channels == 2) AUDIO_data <= filer_data[31:0];
							else begin
								if(sound1_changed && (AUDIO_data_size - AUDIO_count > 255) ) begin
									//On déclenche un lissage anticipé
									AUDIO_data_size  <= AUDIO_count + 255;
									AUDIO_data <= {14'd0,1'b1,1'b0,filer_data[15:0]};
								end
								else AUDIO_data <= {14'd0,(AUDIO_data_size - AUDIO_count)==255,(AUDIO_count==0),filer_data[15:0]};//Les bits 16 et 17 est utilisé pour le smoothing
							end
						end
						
						if(AUDIO_fifo_full == 0) begin
							AUDIO_wrreq <= 1;//Permet de stoquer les samples dans la FIFO pour l'audio
							
							// Continue to read file at pos arg1 + 1 or 2 (car on ne lit que les audios en 8 bits)
							if(AUDIO_channels == 2) begin
								fpga_data <= AUDIO_count + 2 + AUDIO_header_offset;
							end
							else begin
								//fpga_data <= AUDIO_count + 2 + AUDIO_header_offset;
								fpga_data <= AUDIO_count + 1 + AUDIO_header_offset;
							end
							
							//fpga_cmd <= (AUDIO_channels == 2)? NUM_FCMD_READ4CHAR : NUM_FCMD_READ2CHAR;
							fpga_cmd <= (AUDIO_BYTES == 2)? NUM_FCMD_READ2CHAR : NUM_FCMD_READ1CHAR;
							
							if( AUDIO_count < (AUDIO_data_size - AUDIO_BYTES) ) begin
								AUDIO_count <= AUDIO_count + AUDIO_BYTES;
							end
							else begin 
								fpga_cmd <= NUM_FCMD_STOPREAD;//Close file
								fpga_data <= AUDIO_data_size;//Pour debuggage
							end
							
						end
						else begin
							AUDIO_wrreq <= 0;//On fait un coup d'attente
							
							filer_delayed <= 1;
							//filer_data_delayed <= filer_data;
							
							if(sound1_changed && (AUDIO_data_size - AUDIO_count > 255) ) begin
								//On déclenche un lissage anticipé
								AUDIO_data_size  <= AUDIO_count + 255;
								filer_data_delayed <= {1'b1,1'b0,filer_data[15:0]};
							end
							else filer_data_delayed <= {((AUDIO_data_size - AUDIO_count)==255),(AUDIO_count==0),filer_data[15:0]};//Les bits 16 et 17 est utilisé pour le smoothing
							
						end
					end
					else if(filer_cmd == NUM_HPS_RCV1CHAR) begin // 1 char received => rom content
					
						if(request_for_audio) begin // Bloc Audio
							//fpga_debug <= filer_data[7:0];
							fpga_debug <= AUDIO_header_flag;
							
							if(AUDIO_header_flag == 1) AUDIO_fmt_count <= AUDIO_fmt_count + 1;
							if(AUDIO_header_flag == 2) AUDIO_data_count <= AUDIO_data_count + 1;
							
							if(AUDIO_header_flag == 2  && AUDIO_data_count == 3 ) begin // datasize
								//Ready to play audio
								
								AUDIO_data_size <= {filer_data[7:0],AUDIO_file_data[31:8]};
								AUDIO_header_offset <= (AUDIO_header_count + 1);

								AUDIO_count <= 0;
								
								//fpga_cmd <= (AUDIO_channels == 2)? NUM_FCMD_READ4CHAR : NUM_FCMD_READ2CHAR;
								fpga_cmd <= (AUDIO_BYTES == 2)? NUM_FCMD_READ2CHAR : NUM_FCMD_READ1CHAR;
								fpga_data <= 0 + (AUDIO_header_count + 1);//Start audio from pos 0 + HEADER_OFFSET
								
								AUDIO_header_flag <= 3;
							end
							else if(AUDIO_header_flag == 1  && ({filer_data[7:0],AUDIO_file_data[31:8]} == 32'h61746164) ) begin // data found
								//On recherche le "data" (32'h64617461 soit 32'h61746164 dans notre cas)
								AUDIO_header_count <= AUDIO_header_count + 1;
								AUDIO_header_flag <= 2;//bloc data found
								
								AUDIO_header_count <= AUDIO_header_count + 1;
								
								fpga_cmd <= NUM_FCMD_READ1CHAR;// Continue to read 1 char
								fpga_data <= AUDIO_header_count + 1;
							end
							else if(AUDIO_header_flag == 1  && AUDIO_fmt_count == 7 ) begin //Nb channels
								AUDIO_channels <= {filer_data[7:0],AUDIO_file_data[31:24]};
								
								AUDIO_file_data <= AUDIO_file_data >> 8;//Décalage à droite
								AUDIO_file_data[31:24] <= filer_data[7:0];
								
								AUDIO_header_count <= AUDIO_header_count + 1;
								
								fpga_cmd <= NUM_FCMD_READ1CHAR;// Continue to read 1 char
								fpga_data <= AUDIO_header_count + 1;
							end
							else if(AUDIO_header_flag == 0  && ({filer_data[7:0],AUDIO_file_data[31:8]} == 32'h20746D66) ) begin //fmt_ found
								//On recherche le "fmt_" (32'h666D7420 soit 32'h20746D66 dans notre cas)
								AUDIO_header_flag <= 1;//FMT_ Found
								AUDIO_fmt_count <= 0;
								
								AUDIO_file_data <= AUDIO_file_data >> 8;//Décalage à droite
								AUDIO_file_data[31:24] <= filer_data[7:0];
								
								AUDIO_header_count <= AUDIO_header_count + 1;
								
								fpga_cmd <= NUM_FCMD_READ1CHAR;// Continue to read 1 char
								fpga_data <= AUDIO_header_count + 1;
							end
							else if( AUDIO_header_count < (FILE_SIZE - 1)) begin // Condition qui recherche fmt_
								AUDIO_file_data <= AUDIO_file_data >> 8;//Décalage à droite
								AUDIO_file_data[31:24] <= filer_data[7:0];
								
								AUDIO_header_count <= AUDIO_header_count + 1;
								
								fpga_cmd <= NUM_FCMD_READ1CHAR;// Continue to read 1 char
								fpga_data <= (AUDIO_header_count + 1);
							end
							else begin // FMT non trouvé
								fpga_cmd <= NUM_FCMD_STOPREAD;//Close file
								fpga_data <= AUDIO_header_flag;//Pour avoir du debuggage
							end
						end
						else begin // Bloc ROM
							//Save rom data in memory
							if(file_num <= 4) cpu_rom_save1 <= 1;
							else cpu_rom_save1 <= 0;
							
							cpu_rom_wdata1 <= filer_data[7:0];
							cpu_rom_waddr1 <= ROM_SIZE_OFFSET + rom_addr;
							
							fpga_debug <= filer_data[7:0];
							
							if(rom_addr == (FILE_SIZE - 1)) begin
								fpga_cmd <= NUM_FCMD_STOPREAD;
							end
							else begin
								fpga_data <= rom_addr + 1;
								rom_addr <= rom_addr + 1;
								fpga_cmd <= NUM_FCMD_READ1CHAR;
							end
						end
					end
					else if(filer_cmd == NUM_HPS_READSTOP) begin // lecture de la rom ou de l'audio terminée
						
						if(request_for_audio) begin
							if(sound1_loop) begin // on relance la lecture
								AUDIO_count <= 0;
								
								fpga_cmd <= (AUDIO_BYTES == 2)? NUM_FCMD_READ2CHAR : NUM_FCMD_READ1CHAR;
								fpga_data <= AUDIO_header_offset;//Start audio from pos 0 + HEADER_OFFSET
							end
							else begin
								request_for_audio <= 0;
								AUDIO_wrreq <= 0;
								fpga_cmd <= NUM_FCMD_IDLE;
							end
						end
						else begin
							cpu_rom_save1 <= 0;

							if(file_num <= 3) begin
								fpga_data <= file_num + 1;//Get size of file number {file_num + 1}
								fpga_cmd <= NUM_FCMD_GETSIZE;
							end
							else fpga_cmd <= NUM_FCMD_IDLE;
							
							if(file_num <= 4 && FILE_SIZE && rom_addr == (FILE_SIZE - 1) ) file_num <= file_num + 1;
						end
						
						//fpga_cmd <= NUM_FCMD_IDLE;
					end
					else if(filer_cmd == 7) begin
						//if(FILE_SIZE && rom_addr == (FILE_SIZE - 1) || (file_num > 4) ) begin
						if(file_num > 4 ) begin
							fpga_cmd <= NUM_FCMD_IDLE;
						end
						else fpga_cmd <= NUM_FCMD_GETNBFILES;
						
						if(file_num > 4) system_state <= 3;
						else system_state <= 2;
						
						
					end
				end
			end
		end
	end
end

// ** Boucle qui récupère les events du Gamepad **
/******
bit0  => 
bit1  => 
bit2  => Up
bit3  => 
bit4  => <-- 
bit5  => A (Shot)
bit6  => -->
bit7  => 
bit8  => Down
bit13 => R2 (Credit)
bit14 => R3 (Tilt)
bit15 => Start

*******/
always @(posedge clockCPU or negedge rst_n)
begin
	if(!rst_n)
	begin
		gamepad_evt_read <= 0;
		gamepad_ready <= 0;
		gamepad_on <= 0;
	end
	else begin
		if(gamepad_evt_read == 1) begin //Il y a une donnée à lire
			
			case(gamepad_evt_readdata[10:9])
			0 : begin  // Axe X triggered
				if(gamepad_evt_readdata[8:0] == GAMEPAD_AXE_LEFT) gamepad_key[4] <= 1;
				else if(gamepad_evt_readdata[8:0] == GAMEPAD_AXE_RIGHT) gamepad_key[6] <= 1;
				else {gamepad_key[4],gamepad_key[6],gamepad_key[2],gamepad_key[8]} <= 4'b0000;
			end
			1 : begin // Axe Y triggered
				if(gamepad_evt_readdata[8:0] == GAMEPAD_AXE_TOP) gamepad_key[2] <= 1;
				else if(gamepad_evt_readdata[8:0] == GAMEPAD_AXE_BOTTOM) gamepad_key[8] <= 1;
				else {gamepad_key[4],gamepad_key[6],gamepad_key[2],gamepad_key[8]} <= 4'b0000;
			end
			3 : begin // Btn pressed
				case(gamepad_evt_readdata[8:0])
					GAMEPAD_BTN_A : gamepad_key[5] <= 1;
					GAMEPAD_BTN_B : gamepad_key[3] <= 1;
					GAMEPAD_BTN_X : gamepad_key[9] <= 1;
					GAMEPAD_BTN_Y : gamepad_key[0] <= 1;
					GAMEPAD_BTN_L1 : gamepad_key[1] <= 1;
					GAMEPAD_BTN_L2 : gamepad_key[7] <= 1;
					GAMEPAD_BTN_L3 : gamepad_key[10] <= 1;
					GAMEPAD_BTN_R1 : gamepad_key[12] <= 1;
					GAMEPAD_BTN_R2 : gamepad_key[13] <= 1;
					GAMEPAD_BTN_R3 : gamepad_key[14] <= 1;
					GAMEPAD_BTN_STA : gamepad_key[15] <= 1;
					GAMEPAD_BTN_SEL : gamepad_key[11] <= 1;
				endcase
			end
			default : begin // Btn released
				case(gamepad_evt_readdata[8:0])
					GAMEPAD_BTN_A : gamepad_key[5] <= 0;
					GAMEPAD_BTN_B : gamepad_key[3] <= 0;
					GAMEPAD_BTN_X : gamepad_key[9] <= 0;
					GAMEPAD_BTN_Y : gamepad_key[0] <= 0;
					GAMEPAD_BTN_L1 : gamepad_key[1] <= 0;
					GAMEPAD_BTN_L2 : gamepad_key[7] <= 0;
					GAMEPAD_BTN_L3 : gamepad_key[10] <= 0;
					GAMEPAD_BTN_R1 : gamepad_key[12] <= 0;
					GAMEPAD_BTN_R2 : gamepad_key[13] <= 0;
					GAMEPAD_BTN_R3 : gamepad_key[14] <= 0;
					GAMEPAD_BTN_STA : gamepad_key[15] <= 0;
					GAMEPAD_BTN_SEL : gamepad_key[11] <= 0;
				endcase
			end
			
			endcase
			
			gamepad_evt_read <= 0;//on libère la lecture et on attend la prochaine
		end
		
		if(!gamepad_evt_waitrequest) begin
			gamepad_ready <= 1;
			gamepad_evt_read <= 1;//On lira la donnée au prochain cycle
		end
		else begin
			if(gamepad_evt_read == 1) begin
				gamepad_evt_read <= 0;
			end
		end
	end
end


// ** Boucle qui gère les sons de la sortie port 3 **
always @(posedge clockCPU or negedge rst_n)
begin
	if(!rst_n)
	begin
		sound1_reqId <= 0;
	end
	else begin
		if(cpu_sound1_bits != sound1_prev && sound1_reqId == sound1_reqId_sync) begin
			if(cpu_sound1_bits[2]) begin
				if(sound1_prev[2] == 0) begin
					sound1_wav <= 11;//playerdied.wav
					sound1_reqId <= sound1_reqId + 1;
					sound1_bits_handle <= cpu_sound1_bits;
					sound1_loop <= 0;
				end
			end
			else if(cpu_sound1_bits[4]) begin
				if(sound1_prev[4] == 0) begin
					sound1_wav <= 14;//extendedplay.wav
					sound1_reqId <= sound1_reqId + 1;
					sound1_bits_handle <= cpu_sound1_bits;
					sound1_loop <= 0;
				end
			end
			else if(cpu_sound1_bits[0]) begin
				if(sound1_prev[0] == 0) begin
					sound1_wav <= 12;//ufo.wav start
					sound1_reqId <= sound1_reqId + 1;
					sound1_bits_handle <= cpu_sound1_bits;
					sound1_loop <= 1;
				end
			end
			else if(sound1_prev[0]) begin //ufo.wav stop
				if(cpu_sound1_bits[0] == 0) begin
					sound1_loop <= 0;
				end
			end
			else if(cpu_sound1_bits[3]) begin
				if(sound1_prev[3] == 0) begin
					sound1_wav <= 10;//invaderkilled.wav
					sound1_reqId <= sound1_reqId + 1;
					sound1_bits_handle <= cpu_sound1_bits;
					sound1_loop <= 0;
				end
			end
			else if(cpu_sound1_bits[1]) begin
				if(sound1_prev[1] == 0) begin
					sound1_wav <= 9;//shot.wav
					sound1_reqId <= sound1_reqId + 1;
					sound1_bits_handle <= cpu_sound1_bits;
					sound1_loop <= 0;
				end
			end
			else sound1_loop <= 0;
			
			sound1_prev <= cpu_sound1_bits;
		end
	end
end



// ** Boucle qui gère les sons de la sortie port 5 **
always @(posedge clockCPU or negedge rst_n)
begin
	if(!rst_n)
	begin
		sound2_reqId_sync <= 0;
		sound2_inProgress <= 0;
		filer2_delayed <= 0;
		led_filer2 <= 0;
		filer2_data_ready <= 0;
	end
	else begin
		if(filer2_data_ready || filer2_delayed) begin //Il y a une donnée à lire
			if(filer2_delayed) filer2_delayed <= 0;
			
			case(filer2_data[7:0])  //Lit la commande du HPS
				1: fpga2_req <= NUM_FCMD_IDLE;
				
				NUM_HPS_FILESIZE: begin
					FILE2_size <= filer2_data[31:8];
						
					AUDIO2_data_size <= 0;//DataSize inconnu
					AUDIO2_header_flag <= 0;// Recherche du bloc fmt_
					AUDIO2_header_count <= 0;
					AUDIO2_data_count <= 0;
					AUDIO2_file_data <= 0;
						
					fpga2_req[31:8] <= 0;
					fpga2_req[7:0] <= NUM_FCMD_READ1CHAR;
				end
				
				NUM_HPS_READSTOP: begin
					sound2_inProgress <= 0;
					AUDIO2_wrreq <= 0;
					fpga2_req[7:0] <= NUM_FCMD_IDLE;
				end
				
				NUM_HPS_RCV1CHAR: begin // 1 char received
						
					if(AUDIO2_header_flag == 1) AUDIO2_fmt_count <= AUDIO2_fmt_count + 1;
					if(AUDIO2_header_flag == 2) AUDIO2_data_count <= AUDIO2_data_count + 1;
					
					if(AUDIO2_header_flag == 3) begin
						if(filer2_delayed) begin
							if(AUDIO2_channels == 2) AUDIO2_data <= filer2_data_delayed[31:0];
							else AUDIO2_data <= {15'd0,filer2_data_delayed[16:0]};//Le bit 16 est utilisé pour le smoothing
							//else AUDIO2_data <= {16'd0,filer2_data_delayed[15:0]};//Le bit 16 est utilisé pour le smoothing
							////else AUDIO2_data <= {15'd0,filer2_data_delayed[16:0]};//Le bit 16 est utilisé pour le smoothing
						end
						else begin
							if(AUDIO2_channels == 2) AUDIO2_data <= filer2_data[31:8];
							else AUDIO2_data <= {15'd0,(AUDIO2_count==0),filer2_data[23:8]};//Le bit 16 est utilisé pour le smoothing
							//else AUDIO2_data <= {16'd0,filer2_data[23:8]};//Le bit 16 est utilisé pour le smoothing
							////else AUDIO2_data <= {15'd0,(AUDIO2_count==0),filer2_data[23:8]};//Le bit 16 est utilisé pour le smoothing
						end
						
						if(AUDIO2_fifo_full == 0) begin
							AUDIO2_wrreq <= 1;//Permet de stoquer les samples dans la FIFO pour l'audio
							
							// Continue to read file at pos arg1 + 1 or 2 (car on ne lit que les audios en 8 bits)
							if(AUDIO2_channels == 2) begin
								fpga2_req[31:8] <= AUDIO2_count + 2 + AUDIO2_header_offset;
							end
							else begin
								fpga2_req[31:8] <= AUDIO2_count + 1 + AUDIO2_header_offset;
							end
							
							fpga2_req[7:0] <= (AUDIO_BYTES == 2)? NUM_FCMD_READ2CHAR : NUM_FCMD_READ1CHAR;
							
							if( AUDIO2_count < (AUDIO2_data_size - AUDIO_BYTES) ) begin
								AUDIO2_count <= AUDIO2_count + AUDIO_BYTES;
							end
							else begin 
								fpga2_req[7:0] <= NUM_FCMD_STOPREAD;//Close file
								fpga2_req[31:8] <= AUDIO2_data_size;//Pour debuggage
							end
							
						end
						else begin
							AUDIO2_wrreq <= 0;//On fait un coup d'attente
							
							filer2_delayed <= 1;
							if(AUDIO2_channels == 2) filer2_data_delayed <= filer2_data[31:8];
							else filer2_data_delayed <= {(AUDIO2_count==0),filer2_data[23:8]};//Le bit 16 est utilisé pour le smoothing
							//else filer2_data_delayed <= filer2_data[23:8];
							////else filer2_data_delayed <= {(AUDIO2_count==0),filer2_data[23:8]};//Le bit 16 est utilisé pour le smoothing
							
						end
					end
					else if(AUDIO2_header_flag == 2  && AUDIO2_data_count == 3 ) begin // datasize
						//Ready to play audio
						
						AUDIO2_data_size <= {filer2_data[15:8],AUDIO2_file_data[31:8]};
						AUDIO2_header_offset <= (AUDIO2_header_count + 1);

						AUDIO2_count <= 0;
						
						//fpga_cmd <= (AUDIO_channels == 2)? NUM_FCMD_READ4CHAR : NUM_FCMD_READ2CHAR;
						fpga2_req[7:0] <= (AUDIO_BYTES == 2)? NUM_FCMD_READ2CHAR : NUM_FCMD_READ1CHAR;
						fpga2_req[31:8] <= 0 + (AUDIO2_header_count + 1);//Start audio from pos 0 + HEADER_OFFSET
						
						AUDIO2_header_flag <= 3;
					end
					else if(AUDIO2_header_flag == 1  && ({filer2_data[15:8],AUDIO2_file_data[31:8]} == 32'h61746164) ) begin // data found
						//On recherche le "data" (32'h64617461 soit 32'h61746164 dans notre cas)
						AUDIO2_header_count <= AUDIO2_header_count + 1;
						AUDIO2_header_flag <= 2;//bloc data found
						
						AUDIO2_header_count <= AUDIO2_header_count + 1;
						
						fpga2_req[7:0] <= NUM_FCMD_READ1CHAR;// Continue to read 1 char
						fpga2_req[31:8] <= AUDIO2_header_count + 1;
					end
					else if(AUDIO2_header_flag == 1  && AUDIO2_fmt_count == 7 ) begin //Nb channels
						AUDIO2_channels <= {filer2_data[15:8],AUDIO2_file_data[31:24]};
						
						AUDIO2_file_data <= AUDIO2_file_data >> 8;//Décalage à droite
						AUDIO2_file_data[31:24] <= filer2_data[15:8];
						
						AUDIO2_header_count <= AUDIO2_header_count + 1;
						
						fpga2_req[7:0] <= NUM_FCMD_READ1CHAR;// Continue to read 1 char
						fpga2_req[31:8] <= AUDIO2_header_count + 1;
					end
					else if(AUDIO2_header_flag == 0  && ({filer2_data[15:8],AUDIO2_file_data[31:8]} == 32'h20746D66) ) begin //fmt_ found
						//On recherche le "fmt_" (32'h666D7420 soit 32'h20746D66 dans notre cas)
						AUDIO2_header_flag <= 1;//FMT_ Found
						AUDIO2_fmt_count <= 0;
						
						AUDIO2_file_data <= AUDIO2_file_data >> 8;//Décalage à droite
						AUDIO2_file_data[31:24] <= filer2_data[15:8];
						
						AUDIO2_header_count <= AUDIO2_header_count + 1;
						
						fpga2_req[7:0] <= NUM_FCMD_READ1CHAR;// Continue to read 1 char
						fpga2_req[31:8] <= AUDIO2_header_count + 1;
					end
					else if( AUDIO2_header_count < (FILE2_size - 1)) begin // Condition qui recherche fmt_
						AUDIO2_file_data <= AUDIO2_file_data >> 8;//Décalage à droite
						AUDIO2_file_data[31:24] <= filer2_data[15:8];
						
						AUDIO2_header_count <= AUDIO2_header_count + 1;
						
						fpga2_req[7:0] <= NUM_FCMD_READ1CHAR;// Continue to read 1 char
						fpga2_req[31:8] <= (AUDIO2_header_count + 1);
					end
					else begin // FMT non trouvé
						fpga2_req[7:0] <= NUM_FCMD_STOPREAD;//Close file
						fpga2_req[31:8] <= AUDIO2_header_flag;//Pour avoir du debuggage
					end
				
				end
				
				default : begin
					if (system_state == 3 ) begin
						if(sound2_reqId != sound2_reqId_sync ) begin
							sound2_inProgress <= sound2_on;
							sound2_reqId_sync <= sound2_reqId;
							
							if(sound2_on) begin
								fpga2_req[31:8] <= sound2_wav;//Get size of file on Output 5 {sound2_wav}
								fpga2_req[7:0] <= NUM_FCMD_GETSIZE;
							end
						end
						else begin
							fpga2_req[31:8] <= sound2_reqId_sync;
							fpga2_req[7:0] <= NUM_FCMD_IDLE;
							//fpga2_req[7:0] <= 51;
						end
					end
					else fpga2_req <= NUM_FCMD_IDLE;
				end
			endcase
		end
		
		filer2_data_ready <= !filer2_waitrequest;//Permet de rattraper le décalage lié à la FIFO
		
		if(!filer2_waitrequest) begin
			led_filer2 <= 1;
			filer2_read <= 1;//On lira la donnée au prochain cycle
		end
	end
end

always @(posedge clockCPU or negedge rst_n)
begin
	if(!rst_n)
	begin
		sound2_reqId <= 0;
	end
	else begin
		if(cpu_sound2_bits != sound2_prev && sound2_reqId == sound2_reqId_sync) begin
			sound2_on <= 1;
			
			if(cpu_sound2_bits[4]) begin
				if(sound2_prev[4] == 0) begin
					sound2_wav <= 13;//ufohit.wav
					sound2_reqId <= sound2_reqId + 1;
				end
			end
			else if(cpu_sound2_bits[0]) begin
				if(sound2_prev[0] == 0) begin
					sound2_wav <= 5;//invadermove1.wav
					sound2_reqId <= sound2_reqId + 1;
				end
			end
			else if(cpu_sound2_bits[1]) begin
				if(sound2_prev[1] == 0) begin
					sound2_wav <= 6;//invadermove2.wav
					sound2_reqId <= sound2_reqId + 1;
				end
			end
			else if(cpu_sound2_bits[2]) begin
				if(sound2_prev[2] == 0) begin
					sound2_wav <= 7;//invadermove3.wav
					sound2_reqId <= sound2_reqId + 1;
				end
			end
			else if(cpu_sound2_bits[3]) begin
				if(sound2_prev[3] == 0) begin
					sound2_wav <= 8;//invadermove4.wav
					sound2_reqId <= sound2_reqId + 1;
				end
			end
			
			sound2_prev <= cpu_sound2_bits;
		end
	end
end

// ** Boucle qui envoi l'échantillon audio au module AUDIO
/*
always @(posedge clockAudio or negedge resetAudio_n)
begin
	if(!resetAudio_n)
	begin
		
	end
	else begin
		
	end
end
*/


assign rom_textAddr = (rom_textAddr_de1 == 0) ? rom_textAddr_de1 : (rom_textAddr_de1 - 1);
assign led[0] = hps_ready;
assign led[1] = led_filer2;

// SIMULATION
//assign filer_cmd = (simul_counter1 >= 90)? 7 : simul_counter1 / 12 ;


endmodule