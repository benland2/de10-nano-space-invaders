/**
* CPU 8080
*/
module cpu(
	input wire clk_2MHz,//Devrait èetre une Clock de 2 MHz
	input reset,
	input game_ready, // if 1 => Game Ready to play
	
	output reg [7:0] draw_x,
	output reg [7:0] draw_y,
	output reg [2:0] draw_color,
	output reg draw_clear,
	output reg draw_wren,
	input drawQ_full,
	input drawQ_empty,
	
	input [15:0] gamepad_key,
	output reg led2,
	
	/*input mem_wren,
	input [7:0] mem_wdata,
	input [11:0] mem_waddr,*/
	input [9:0] cpu_instrctionNum,//Vars pour gérer la synchro entre le CPU et HDMI
	output reg [9:0] cpu_instrctionSync,//Vars pour gérer la synchro entre le CPU et HDMI
	input [13:0] VIDEO_mem_rdaddr,
	
	output reg [7:0] cpu_mem_rdata,
	
	output reg videoRam_req,
	output reg [5:0] videoRam_x,
	output reg [4:0] videoRam_y,
	input videoRam_sync,
	input [2:0] videoRam_pixel,
	
	input wire cpu_rom_save,
	input wire [7:0] cpu_rom_wdata,
	input wire [12:0] cpu_rom_waddr,
	
	input [11:0] opcode_counter_debug,
	
	output reg [7:0] sound1_bits,
	output reg [7:0] sound2_bits,
	
	input [7:0] int_rst // Interrupt RST 8 or RST 10
);

// ROM
// $0000-$07ff: invaders.h
// $0800-$0fff: invaders.g
// $1000-$17ff: invaders.f
// $1800-$1fff: invaders.e

// RAM
// $2000 - $23ff: work RAM
// $2400 - $3fff: video RAM
// $4000-: RAM mirror

parameter CYCLE_MULTIPLICATOR = 4;//Nous travaillons avec une clock de 8MHz, donc on multiplie le nombre de cycles pour être synchro avec le cpu 8080
parameter STACK_DEPTH = 10'h3FF;
parameter VIDEO_START = 14'h2400;
parameter RAM_START = 14'h2000;

reg [7:0] CPU_A;
reg [7:0] CPU_B;
reg [7:0] CPU_C;
reg [7:0] CPU_D;
reg [7:0] CPU_E;
reg [7:0] CPU_F;
reg [7:0] CPU_L;
reg [7:0] CPU_H;

reg [15:0] CPU_pc;//program counter

reg CPU_s;//Flag Sign : 1 si négatif (>= 0x80)  / 0 si positif
reg CPU_z;//Flag Zero : 1 si zéro / sinon 0
reg CPU_p;//Flag Parity : 0 si ^X == 1 (impaire) / 1 si ~^X == 1 (paire)
reg CPU_carry;//Flag Carry or Borrow
reg CPU_ac;//Flag for BDC
reg [2:0] CPU_pad;
reg [7:0] tmp;
reg [15:0] tmp2;
reg set_flags;

reg int_enabled;
reg [3:0] cycles_counter;
reg [15:0] cyclesTotal_counter;

reg [15:0] CPU_stack [0 : STACK_DEPTH-1];
reg [15:0]  CPU_stack_ptr;

reg [23:0] OPCODE;// Les instructions peuvent contenir jusqu'à 3 octets
reg opcode_unk;
reg [3:0] cpu_state;
reg [2:0] func_state = 0;

//reg [14:0] CPU_mem_wraddr;
//reg CPU_mem_wren = 0;
//reg [7:0] CPU_mem_wdata;
reg [14:0] DBG_mem_wraddr;
reg DBG_mem_wren = 0;
reg [7:0] DBG_mem_wdata;

reg [14:0] VIDEO_memA_addr;
reg VIDEO_mem_wren;
reg [7:0] VIDEO_mem_wdata;
wire [7:0] VIDEO_memA_rdata;
wire [7:0] VIDEO_memB_rdata;

//reg [14:0] mem_rdaddr;
//wire [7:0] mem_rdata;
reg [12:0] cpu_rom_raddr;
wire [7:0] rom_rdata;
reg cpu_instrctionStep = 0;

reg rom_en;
reg [7:0] rom_wdata;
reg [12:0] rom_waddr;

reg [4:0] cycles_remain;

// Vars for the Shift Register
reg [2:0] ShiftRegister_offset;
reg [15:0] ShiftRegister_value;

// Vars for ISR
reg [3:0] int_newEventId;
reg [3:0] int_nextEventId;
reg [3:0] int_synchEventId;
reg [7:0] int_rst_prev;
reg int_op;

// Vars for instructions in combinational loop
reg [7:0] OP_daa_A;
reg OP_daa_carry;
reg OP_daa_ac;

// Vars for inputs port
/* 
Port 1
 bit 0 = CREDIT (1 if deposit)
 bit 1 = 2P start (1 if pressed)
 bit 2 = 1P start (1 if pressed)
 bit 3 = Always 1
 bit 4 = 1P shot (1 if pressed)
 bit 5 = 1P left (1 if pressed)
 bit 6 = 1P right (1 if pressed)
 bit 7 = Not connected
 
Port 2
 bit 0 = DIP3 00 = 3 ships  10 = 5 ships
 bit 1 = DIP5 01 = 4 ships  11 = 6 ships
 bit 2 = Tilt  (Emulate with button R3. But usually if you shake, slap, or otherwise physically abuse an SI cabinet you will get a TILT message and your game will end)
 bit 3 = DIP6 0 = extra ship at 1500, 1 = extra ship at 1000
 bit 4 = P2 shot (1 if pressed)
 bit 5 = P2 left (1 if pressed)
 bit 6 = P2 right (1 if pressed)
 bit 7 = DIP7 Coin info displayed in demo screen 0=ON
 */
wire BtnCredit;//bit 0
reg BtnP2Start = 1'b0;//bit 1
wire BtnP1Start;//bit 2
wire BtnP1Shot;//bit 4
wire BtnP1Left;//bit 5
wire BtnP1Right;//bit 6 

parameter DIP5_DIP3 = 2'b00;//bit 0 and 1
wire BtnTilt;//bit 2
parameter DIP6 = 1'b0;//bit 3
reg BtnP2Shot = 1'b0;//bit 4
reg BtnP2Left = 1'b0;//bit 5
reg BtnP2Right = 1'b0;//bit 6
parameter DIP7 = 1'b0;//bit 7


integer i;

// Vars for debug
reg [39:0] opcode_val1;
reg can_debug;
reg [15:0] debug_counter1;

// Variables for SIMULATION
reg [8:0] simul_counter1;

//reg [63:0] CHARS[0:15];
//reg [63:0] CHAR_0;
//reg [7:0] CPU_chars [0:15][0:7];
//parameter CHAR_0 = 64'hFF3E4549;//|0|
//parameter CHAR_H[0] = 'hFF3E4549;//|0|
//parameter [7:0] CHAR_H [7 : 0]   = {8'hFF, 8'h3E, 8'h45, 8'h49};
//parameter [63:0] CHAR_H = {8'hFF, 8'h3E, 8'h45, 8'h49, 8'h51, 8'h3E, 8'h00,8'hFF};

parameter CHAR0_H = 'h003E4549;//0
parameter CHAR0_L = 'h513E0000;//0
parameter CHAR1_H = 'h0000217f;//1
parameter CHAR1_L = 'h01000000;//1
parameter CHAR2_H = 'h00234549;//2
parameter CHAR2_L = 'h49310000;//2
parameter CHAR3_H = 'h00424149;//3
parameter CHAR3_L = 'h59660000;//3
parameter CHAR4_H = 'h000C1424;//4
parameter CHAR4_L = 'h7F040000;//4
parameter CHAR5_H = 'h00725151;//5
parameter CHAR5_L = 'h514E0000;//5
parameter CHAR6_H = 'h001E2949;//6
parameter CHAR6_L = 'h49460000;//6
parameter CHAR7_H = 'h00404748;//7
parameter CHAR7_L = 'h50600000;//7
parameter CHAR8_H = 'h00364949;//8
parameter CHAR8_L = 'h49360000;//8
parameter CHAR9_H = 'h00314949;//9
parameter CHAR9_L = 'h4A3C0000;//9
parameter CHARA_H = 'h001F2444;//A
parameter CHARA_L = 'h241F0000;//A
parameter CHARB_H = 'h007F4949;//B
parameter CHARB_L = 'h49360000;//B
parameter CHARC_H = 'h003E4141;//C
parameter CHARC_L = 'h41220000;//C
parameter CHARD_H = 'h007F4141;//D
parameter CHARD_L = 'h413E0000;//D
parameter CHARE_H = 'h007F4949;//E
parameter CHARE_L = 'h49410000;//E
parameter CHARF_H = 'h007F4848;//F
parameter CHARF_L = 'h48400000;//F


initial begin
	
	CPU_pad = 3'b001;
	cpu_instrctionSync = 0;
	
	simul_counter1 = 0;
	cyclesTotal_counter = 0;
	CPU_stack_ptr = 0;
	VIDEO_mem_wren = 0;
	rom_en = 0;
	cycles_remain = 0;
	int_newEventId = 0;
	int_rst_prev = 0;
end


// ** RAM CPU for ROM **
// ROM
// $0000-$07ff: invaders.h
// $0800-$0fff: invaders.g
// $1000-$17ff: invaders.f
// $1800-$1fff: invaders.e
/*cpu_ram1_rom ram1_rom(
	.clock(clk_2MHz),
	.address(game_ready ? cpu_rom_raddr : cpu_rom_waddr),
	.data(cpu_rom_wdata),
	.wren(game_ready? 0 : cpu_rom_save ),
	.q(rom_rdata)
);*/
cpu_ram1_rom ram1_rom(
	.clock(clk_2MHz),
	.address(game_ready ? cpu_rom_raddr : rom_waddr),
	.data(rom_wdata),
	.wren(game_ready? 0 : rom_en ),
	.q(rom_rdata)
);

// ** RAM CPU (32Ko) ** //32768
// Work RAM (Mirror RAM + Stack)
// $2000 - $23ff: work RAM
/*cpu_ram2 memory(
	.clock(clk_2MHz),
	//.wraddress(game_ready? CPU_mem_wraddr : cpu_rom_waddr ),
	.wraddress( CPU_mem_wraddr ),
	//.address(CPU_mem_wren ? CPU_mem_wraddr : (mem_rdaddr + VIDEO_START)),
	//.data(CPU_mem_wren ? CPU_mem_wdata : mem_rddata),
	//.data(game_ready? CPU_mem_wdata : cpu_rom_wdata),
	.data( CPU_mem_wdata ),
	//.wren(CPU_mem_wren ? CPU_mem_wren : mem_wren ),
	//.wren(game_ready? CPU_mem_wren : cpu_rom_save ),
	.wren( CPU_mem_wren ),
	.rdaddress(mem_rdaddr),
	.q(mem_rdata)
);*/


// ** RAM CPU for Work RAM (MirrVIDEO_mem_wdataor RAM + Stack) + VIDEO **
// $2000 - $23ff: work RAM
// $2400-$3fff: VIDEO
cpu_ram2_video VIDEO_mem(
	.clock(clk_2MHz),
	
	//Le port A est utilisé par le CPU pour la lecture et l'écriture
	.wren_a(opcode_unk ? DBG_mem_wren : VIDEO_mem_wren ),
	.data_a(opcode_unk? DBG_mem_wdata : VIDEO_mem_wdata ),
	.address_a(opcode_unk ? DBG_mem_wraddr : VIDEO_memA_addr ),
	.q_a(VIDEO_memA_rdata),
	
	//Le port B ne sert que de lecture pour l'affichage sur le HDMI
	.wren_b(0),
	.data_b(0),
	.address_b(VIDEO_mem_rdaddr),
	.q_b(VIDEO_memB_rdata)
);

/*cpu_ram2_video VIDEO_mem(
	.clock(clk_2MHz),
	.wraddress(opcode_unk ? DBG_mem_wraddr : VIDEO_mem_wraddr ),
	.data(opcode_unk? DBG_mem_wdata : VIDEO_mem_wdata ),
	.wren(opcode_unk ? DBG_mem_wren : VIDEO_mem_wren ),
	.rdaddress(VIDEO_mem_rdaddr),
	.q(VIDEO_mem_rdata)
);*/


// Synchronizer between clock CPU and HDMI
always @(posedge clk_2MHz ) begin
	if(cpu_instrctionSync != cpu_instrctionNum) begin
		if(!VIDEO_mem_wren) begin
			if(!cpu_instrctionStep) cpu_instrctionStep <= 1;//On laisse un cycle pour lire la ram
			else begin
				cpu_instrctionStep <= 0;
				cpu_instrctionSync <= cpu_instrctionNum;
				cpu_mem_rdata <= VIDEO_memB_rdata;
			end
		end
	end
end

// Lecture des instructions (opcodes)
always @(posedge clk_2MHz or posedge reset) begin
	if(reset) begin
		opcode_unk <= 0;
		CPU_pc <= 0;
		cpu_state <= 0;
		opcode_val1 <= 0;
		cyclesTotal_counter <= 0;
		cycles_remain <= 0;
		//sound1_on <= 0;
		int_enabled <= 0;
		int_nextEventId <= 1;
		int_synchEventId <= 0;
		int_op <= 0;
		ShiftRegister_value <= 0;
		can_debug <= 0;
	end
	else begin
		if(game_ready) begin
			led2 <= 1;
			
			if(!opcode_unk) begin
				cyclesTotal_counter <= cyclesTotal_counter + 1;
				if(cycles_remain > 0) cycles_remain <= (cycles_remain - 1);
				
				if( can_debug ) begin
				//if(CPU_pc ==  'h17D2 ) begin
					opcode_unk <= 1;//Debug
					//opcode_val1 <= {CPU_H,CPU_L,CPU_pc[15:8],CPU_pc[7:0],OPCODE[7:0]};
					//opcode_val1 <= {CPU_D,CPU_E,VIDEO_memA_rdata,CPU_A,OPCODE[7:0]};
					opcode_val1 <= {CPU_A,CPU_H,CPU_pc[15:8],CPU_pc[7:0],OPCODE[7:0]};
				end
				else if(cpu_state == 0) begin
					if(cycles_remain == 0) begin
						if(CPU_stack_ptr <=  8) begin
							debug_counter1 <= debug_counter1 + 1;
						end
						
						cpu_rom_raddr <= CPU_pc;
						cpu_state <= 1;
						
						// ** Gestion de l'ISR **
						if(int_enabled && int_rst != int_rst_prev) begin
							int_enabled <= 0;
							int_op <= 1;
						end
						
						if(int_rst != int_rst_prev) int_rst_prev <= int_rst;
						
						/*if(int_enabled) begin
							if(int_newEventId != int_synchEventId) begin // Interrupt triggerd
								int_synchEventId <= int_newEventId;
								int_nextEventId <= int_newEventId + 1;
								
								int_enabled <= 0;
								int_op <= 1;
								
								// !!!! Penser à stoquer le CPU_pc dans la stack avant de lire l'opcode
								//CPU_pc <= int_rst;
								//cpu_rom_raddr <= int_rst;
							end
						end*/
						
					end
				end
				else if(cpu_state == 1) begin //Laisse un cycle pour lire la mémoire
					if(int_op) begin
						if(func_state == 0) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= CPU_stack_ptr - 1;
							VIDEO_mem_wdata <= CPU_pc[15:8];
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= CPU_stack_ptr - 2;
							VIDEO_mem_wdata <= CPU_pc[7:0];
							
							func_state <= 2;
						end
						else begin
							VIDEO_mem_wren <= 0;
							CPU_stack_ptr <= CPU_stack_ptr - 2;
							
							CPU_pc <= int_rst;
							
							int_op <= 0;
							cpu_state <= 0;
							func_state <= 0;
						end
					end
					else begin
						cpu_rom_raddr <= (CPU_pc + 1);
						cpu_state <= 2;
					end
				end
				else if(cpu_state == 2) begin 
					cpu_rom_raddr <= (CPU_pc + 2);
					OPCODE[7:0] <= rom_rdata;// lit le 1er octet de l'instruction
					cpu_state <= 3;
					
					// Decode opcode de 1 octet qui font un Set Flags sur CPU_A
					if(rom_rdata == 8'h85) begin
						// 1 octet / 4 cycles
						{CPU_carry,CPU_A} <= CPU_A + CPU_L;
						tmp <= CPU_A + CPU_L;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'h80) begin
						// 1 octet / 4 cycles
						{CPU_carry,CPU_A} <= CPU_A + CPU_B;
						tmp <= CPU_A + CPU_B;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'h81) begin
						// 1 octet / 4 cycles
						{CPU_carry,CPU_A} <= CPU_A + CPU_C;
						tmp <= CPU_A + CPU_C;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'h82) begin
						// 1 octet / 4 cycles
						{CPU_carry,CPU_A} <= CPU_A + CPU_D;
						tmp <= CPU_A + CPU_D;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'h83) begin
						// 1 octet / 4 cycles
						{CPU_carry,CPU_A} <= CPU_A + CPU_E;
						tmp <= CPU_A + CPU_E;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'h8A) begin
						// 1 octet / 4 cycles
						{CPU_carry,CPU_A} <= CPU_A + CPU_D + CPU_carry;
						tmp <= CPU_A + CPU_D + CPU_carry;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'h8B) begin
						// 1 octet / 4 cycles
						{CPU_carry,CPU_A} <= CPU_A + CPU_E + CPU_carry;
						tmp <= CPU_A + CPU_E + CPU_carry;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'hA0) begin
						// 1 octet / 4 cycles
						CPU_A <= CPU_A & CPU_B;
						tmp <= CPU_A & CPU_B;
						CPU_carry <= 0;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'h0C) begin
						// 1 octet / 5 cycles
						CPU_C <= CPU_C + 1;
						tmp <= CPU_C + 1;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'h1C) begin
						// 1 octet / 5 cycles
						CPU_E <= CPU_E + 1;
						tmp <= CPU_E + 1;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'h2C) begin
						// 1 octet / 5 cycles
						CPU_L <= CPU_L + 1;
						tmp <= CPU_L + 1;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'h3C) begin
						// 1 octet / 5 cycles
						CPU_A <= CPU_A + 1;
						tmp <= CPU_A + 1;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'h97) begin
						// 1 octet / 4 cycles
						CPU_A <= CPU_A - CPU_A;
						tmp <= CPU_A - CPU_A;
						CPU_carry <= 0;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'hB8) begin
						// 1 octet / 4 cycles
						tmp <= CPU_A - CPU_B;
						CPU_carry <= (CPU_A < CPU_B) ? 1 : 0;
						
						set_flags <= 1;
					end
					else if(rom_rdata == 8'hBC) begin
						// 1 octet / 4 cycles
						tmp <= CPU_A - CPU_H;
						CPU_carry <= (CPU_A < CPU_H) ? 1 : 0;
						
						set_flags <= 1;
					end
					else set_flags <= 0;
					
				end
				else if(cpu_state == 3) begin // Décode l'opcode / lit 2ème opcode
					cycles_remain <= 4*CYCLE_MULTIPLICATOR - 4;//Nombre de cycles à calculer selon l'opcode (-4 car à ce stade on est au 4ème cycle)
					//cycles_remain <= 4;//Nombre de cycles à calculer selon l'opcode
					
					if(set_flags) begin
						//set flags						
						CPU_s <= tmp[7];
						CPU_z <= (tmp == 0)? 1 : 0;
						CPU_p <= ~^tmp;
						CPU_ac <= (tmp[3:0] > 9) ? 1 : 0;
						
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h0) begin
						// 1 octet / 4 cycles
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h0A) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							cpu_rom_raddr <= {CPU_B[7:0],CPU_C[7:0]};
							func_state <= 1;
						end
						else if(func_state == 1) begin// Laisse un cycle pour lire la mémoire {DE}
							func_state <= 2;
						end
						else begin
							CPU_A <= rom_rdata;
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if(OPCODE[7:0] == 8'h02) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= {CPU_B,CPU_C};
							VIDEO_mem_wdata <= CPU_A;
							
							func_state <= 1;
						end
						else begin
							VIDEO_mem_wren <= 0;
							VIDEO_mem_wren <= 0;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if(OPCODE[7:0] == 8'h12) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= {CPU_D,CPU_E};
							VIDEO_mem_wdata <= CPU_A;
							
							func_state <= 1;
						end
						else begin
							VIDEO_mem_wren <= 0;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if(OPCODE[7:0] == 8'h1A) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							if({CPU_D[7:0],CPU_E[7:0]} >= RAM_START) VIDEO_memA_addr <= {CPU_D[7:0],CPU_E[7:0]};
							else cpu_rom_raddr <= {CPU_D[7:0],CPU_E[7:0]};
							
							func_state <= 1;
						end
						else if(func_state == 1) begin// Laisse un cycle pour lire la mémoire {DE}
							func_state <= 2;
						end
						else begin
							if({CPU_D[7:0],CPU_E[7:0]} >= RAM_START) CPU_A <= VIDEO_memA_rdata;
							else CPU_A <= rom_rdata;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if(OPCODE[7:0] == 8'h70) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= {CPU_H,CPU_L};
							VIDEO_mem_wdata <= CPU_B;
							
							func_state <= 1;
						end
						else begin
							VIDEO_mem_wren <= 0;
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if(OPCODE[7:0] == 8'h71) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= {CPU_H,CPU_L};
							VIDEO_mem_wdata <= CPU_C;
							
							func_state <= 1;
						end
						else begin
							VIDEO_mem_wren <= 0;
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if(OPCODE[7:0] == 8'h77) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= {CPU_H,CPU_L};
							VIDEO_mem_wdata <= CPU_A;
							
							func_state <= 1;
						end
						else begin
							VIDEO_mem_wren <= 0;
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if(OPCODE[7:0] == 8'h23) begin
						// 1 octet / 5 cycles
						{CPU_H[7:0],CPU_L[7:0]} <= ({CPU_H[7:0],CPU_L[7:0]} + 1);
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h03) begin
						// 1 octet / 5 cycles
						{CPU_B[7:0],CPU_C[7:0]} <= ({CPU_B[7:0],CPU_C[7:0]} + 1);
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h13) begin
						// 1 octet / 5 cycles
						{CPU_D[7:0],CPU_E[7:0]} <= ({CPU_D[7:0],CPU_E[7:0]} + 1);
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h78) begin
						// 1 octet / 5 cycles
						CPU_A <= CPU_B;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h79) begin
						// 1 octet / 5 cycles
						CPU_A <= CPU_C;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h7A) begin
						// 1 octet / 5 cycles
						CPU_A <= CPU_D;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h7B) begin
						// 1 octet / 5 cycles
						CPU_A <= CPU_E;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h7C) begin
						// 1 octet / 5 cycles
						CPU_A <= CPU_H;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h7D) begin
						// 1 octet / 5 cycles
						CPU_A <= CPU_L;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h04) begin
						// 1 octet / 5 cycles
						if(func_state == 0) begin
							CPU_B <= CPU_B + 1;
							func_state <= 1;
						end
						else begin
							//set flags
							CPU_s <= CPU_B[7];
							CPU_z <= (CPU_B == 0) ? 1 : 0;
							CPU_p <= ~^CPU_B;
							CPU_ac <= (CPU_B[3:0] > 9) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'h14) begin
						// 1 octet / 5 cycles
						if(func_state == 0) begin
							CPU_D <= CPU_D + 1;
							func_state <= 1;
						end
						else begin
							//set flags
							CPU_s <= CPU_D[7];
							CPU_z <= (CPU_D == 0) ? 1 : 0;
							CPU_p <= ~^CPU_D;
							CPU_ac <= (CPU_D[3:0] > 9) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'h24) begin
						// 1 octet / 5 cycles
						if(func_state == 0) begin
							CPU_H <= CPU_H + 1;
							func_state <= 1;
						end
						else begin
							//set flags
							CPU_s <= CPU_H[7];
							CPU_z <= (CPU_H == 0) ? 1 : 0;
							CPU_p <= ~^CPU_H;
							CPU_ac <= (CPU_H[3:0] > 9) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'h05) begin
						// 1 octet / 5 cycles
						if(func_state == 0) begin
							CPU_B <= CPU_B - 1;
							func_state <= 1;
						end
						else begin
							//set flags
							CPU_s <= CPU_B[7];
							CPU_z <= (CPU_B == 0) ? 1 : 0;
							CPU_p <= ~^CPU_B;
							CPU_ac <= (CPU_B[3:0] > 9) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if(OPCODE[7:0] == 8'h15) begin
						// 1 octet / 5 cycles
						if(func_state == 0) begin
							CPU_D <= CPU_D - 1;
							func_state <= 1;
						end
						else begin
							//set flags
							CPU_s <= CPU_D[7];
							CPU_z <= (CPU_D == 0) ? 1 : 0;
							CPU_p <= ~^CPU_D;
							CPU_ac <= (CPU_D[3:0] > 9) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if(OPCODE[7:0] == 8'h0D) begin
						// 1 octet / 5 cycles
						if(func_state == 0) begin
							CPU_C <= CPU_C - 1;
							func_state <= 1;
						end
						else begin
							//set flags
							CPU_s <= CPU_C[7];
							CPU_z <= (CPU_C == 0) ? 1 : 0;
							CPU_p <= ~^CPU_C;
							CPU_ac <= (CPU_C[3:0] > 9) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if(OPCODE[7:0] == 8'h27) begin //DAA
						// 1 octet / 4 cycles
						CPU_ac <= OP_daa_ac;
						CPU_carry <= OP_daa_carry;
						CPU_A <= OP_daa_A;
						
						CPU_s <= OP_daa_A[7];
						CPU_z <= (OP_daa_A == 0);
						CPU_p <= ~^OP_daa_A;
						
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
						
					end
					else if(OPCODE[7:0] == 8'h0B) begin
						// 1 octet / 5 cycles
						{CPU_B,CPU_C} <= {CPU_B,CPU_C} - 1;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;						
					end
					else if(OPCODE[7:0] == 8'h1B) begin
						// 1 octet / 5 cycles
						{CPU_D,CPU_E} <= {CPU_D,CPU_E} - 1;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;						
					end
					else if(OPCODE[7:0] == 8'h2B) begin
						// 1 octet / 5 cycles
						{CPU_H,CPU_L} <= {CPU_H,CPU_L} - 1;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
						
					end
					else if(OPCODE[7:0] == 8'h37) begin
						// 1 octet / 4 cycles
						CPU_carry <= 1;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
						
					end
					else if(OPCODE[7:0] == 8'h3D) begin
						// 1 octet / 5 cycles
						if(func_state == 0) begin
							CPU_A <= CPU_A - 1;
							func_state <= 1;
						end
						else begin
							//set flags
							CPU_s <= CPU_A[7];
							CPU_z <= (CPU_A == 0) ? 1 : 0;
							CPU_p <= ~^CPU_A;
							CPU_ac <= (CPU_A[3:0] > 9) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if(OPCODE[7:0] == 8'hC9 ) begin //C9
						// 1 octet / 10 cycles
						if(func_state == 0) begin
							VIDEO_memA_addr <= CPU_stack_ptr;
							func_state <= 1;
							tmp2 <= CPU_pc;
						end
						else if(func_state == 1) begin// Laisse un cycle pour lire la mémoire
							//VIDEO_memA_addr <= CPU_stack_ptr + 1;
							func_state <= 2;
						end
						else if(func_state == 2) begin
							CPU_pc[7:0] <= VIDEO_memA_rdata;
							VIDEO_memA_addr <= CPU_stack_ptr + 1;
							func_state <= 3;
						end
						else if(func_state == 3) begin// Laisse un cycle pour lire la mémoire
							func_state <= 4;
						end
						else if(func_state == 4) begin
							CPU_pc[15:8] <= VIDEO_memA_rdata;
							func_state <= 5;
						end
						else begin
							CPU_stack_ptr <= (CPU_stack_ptr + 2);
							func_state <= 0;
							cpu_state <= 0;
							
						end
						
					end
					else if( OPCODE[7:0] == 8'hE9) begin
						// 1 octet / 5 cycles
						CPU_pc <= {CPU_H,CPU_L};
						cpu_state <= 0;
					end
					else if( OPCODE[7:0] == 8'hD5) begin
						// 1 octet / 11 cycles
						if(func_state == 0) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= CPU_stack_ptr - 1;
							VIDEO_mem_wdata <= CPU_D;
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= CPU_stack_ptr - 2;
							VIDEO_mem_wdata <= CPU_E;
							
							func_state <= 2;
						end
						else begin
							VIDEO_mem_wren <= 0;
							CPU_stack_ptr <= CPU_stack_ptr - 2;
							func_state <= 0;
							cpu_state <= 0;
							CPU_pc <= CPU_pc + 1;
						end
						
					end
					else if( OPCODE[7:0] == 8'hF5) begin //PUSH PSW
						// 1 octet / 11 cycles
						if(func_state == 0) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= CPU_stack_ptr - 1;
							VIDEO_mem_wdata <= CPU_A;
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= CPU_stack_ptr - 2;
							VIDEO_mem_wdata <= {CPU_s,CPU_z,1'b0,CPU_ac,1'b0,CPU_p,1'b1,CPU_carry};
							
							func_state <= 2;
						end
						else begin
							VIDEO_mem_wren <= 0;
							CPU_stack_ptr <= CPU_stack_ptr - 2;
							func_state <= 0;
							cpu_state <= 0;
							CPU_pc <= CPU_pc + 1;
						end
						
					end
					else if( OPCODE[7:0] == 8'hC5) begin
						// 1 octet / 11 cycles
						if(func_state == 0) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= CPU_stack_ptr - 1;
							VIDEO_mem_wdata <= CPU_B;
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= CPU_stack_ptr - 2;
							VIDEO_mem_wdata <= CPU_C;
							
							func_state <= 2;
						end
						else begin
							VIDEO_mem_wren <= 0;
							CPU_stack_ptr <= CPU_stack_ptr - 2;
							func_state <= 0;
							cpu_state <= 0;
							CPU_pc <= CPU_pc + 1;
						end
						
					end
					else if( OPCODE[7:0] == 8'hE5) begin
						// 1 octet / 11 cycles
						if(func_state == 0) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= CPU_stack_ptr - 1;
							VIDEO_mem_wdata <= CPU_H;
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= CPU_stack_ptr - 2;
							VIDEO_mem_wdata <= CPU_L;
							
							func_state <= 2;
						end
						else begin
							VIDEO_mem_wren <= 0;
							CPU_stack_ptr <= CPU_stack_ptr - 2;
							func_state <= 0;
							cpu_state <= 0;
							CPU_pc <= CPU_pc + 1;
						end
						
					end
					else if( OPCODE[7:0] == 8'hC0) begin
						// 1 octet / 11 or 5 cycles
						if(func_state == 0) begin
							if(CPU_z == 0) begin
								VIDEO_memA_addr <= CPU_stack_ptr;
								func_state <= 1;
							end
							else begin
								cpu_state <= 0;
								CPU_pc <= CPU_pc + 1;
							end
						end
						else if(func_state == 1) begin// Laisse un cycle pour lire la mémoire
							VIDEO_memA_addr <= CPU_stack_ptr + 1;
							func_state <= 2;
						end
						else if(func_state == 2) begin
							CPU_pc[7:0] <= VIDEO_memA_rdata;
							func_state <= 3;
						end
						else if(func_state == 3) begin
							CPU_pc[15:8] <= VIDEO_memA_rdata;
							func_state <= 4;
						end
						else begin
							CPU_stack_ptr <= (CPU_stack_ptr + 2);
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if( OPCODE[7:0] == 8'hD0) begin
						// 1 octet / 11 or 5 cycles
						if(func_state == 0) begin
							if(CPU_carry == 0) begin
								VIDEO_memA_addr <= CPU_stack_ptr;
								func_state <= 1;
							end
							else begin
								cpu_state <= 0;
								CPU_pc <= CPU_pc + 1;
							end
						end
						else if(func_state == 1) begin// Laisse un cycle pour lire la mémoire
							VIDEO_memA_addr <= CPU_stack_ptr + 1;
							func_state <= 2;
						end
						else if(func_state == 2) begin
							CPU_pc[7:0] <= VIDEO_memA_rdata;
							func_state <= 3;
						end
						else if(func_state == 3) begin
							CPU_pc[15:8] <= VIDEO_memA_rdata;
							func_state <= 4;
						end
						else begin
							CPU_stack_ptr <= (CPU_stack_ptr + 2);
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if( OPCODE[7:0] == 8'hC8) begin
						// 1 octet / 11 or 5 cycles
						if(func_state == 0) begin
							if(CPU_z == 1) begin
								VIDEO_memA_addr <= CPU_stack_ptr;
								func_state <= 1;
							end
							else begin
								cpu_state <= 0;
								CPU_pc <= CPU_pc + 1;
							end
						end
						else if(func_state == 1) begin// Laisse un cycle pour lire la mémoire
							VIDEO_memA_addr <= CPU_stack_ptr + 1;
							func_state <= 2;
						end
						else if(func_state == 2) begin
							CPU_pc[7:0] <= VIDEO_memA_rdata;
							func_state <= 3;
						end
						else if(func_state == 3) begin
							CPU_pc[15:8] <= VIDEO_memA_rdata;
							func_state <= 4;
						end
						else begin
							CPU_stack_ptr <= (CPU_stack_ptr + 2);
							func_state <= 0;
							cpu_state <= 0;
							if (CPU_stack_ptr + 2 == 6) can_debug <= 1;
						end
						
					end
					else if( OPCODE[7:0] == 8'hD8) begin
						// 1 octet / 11 or 5 cycles
						if(func_state == 0) begin
							if(CPU_carry == 1) begin
								VIDEO_memA_addr <= CPU_stack_ptr;
								func_state <= 1;
							end
							else begin
								cpu_state <= 0;
								CPU_pc <= CPU_pc + 1;
							end
						end
						else if(func_state == 1) begin// Laisse un cycle pour lire la mémoire
							VIDEO_memA_addr <= CPU_stack_ptr + 1;
							func_state <= 2;
						end
						else if(func_state == 2) begin
							CPU_pc[7:0] <= VIDEO_memA_rdata;
							func_state <= 3;
						end
						else if(func_state == 3) begin
							CPU_pc[15:8] <= VIDEO_memA_rdata;
							func_state <= 4;
						end
						else begin
							CPU_stack_ptr <= (CPU_stack_ptr + 2);
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if( OPCODE[7:0] == 8'hC1) begin
						// 1 octet / 11 cycles
						if(func_state == 0) begin
							VIDEO_memA_addr <= CPU_stack_ptr;
							func_state <= 1;
						end
						else if(func_state == 1) begin// Laisse un cycle pour lire la mémoire
							VIDEO_memA_addr <= CPU_stack_ptr + 1;
							func_state <= 2;
						end
						else if(func_state == 2) begin
							CPU_C <= VIDEO_memA_rdata;
							func_state <= 3;
						end
						else if(func_state == 3) begin
							CPU_B <= VIDEO_memA_rdata;
							func_state <= 4;
						end
						else begin
							CPU_stack_ptr <= (CPU_stack_ptr + 2);
							func_state <= 0;
							cpu_state <= 0;
							CPU_pc <= CPU_pc + 1;
						end
						
					end
					else if( OPCODE[7:0] == 8'hD1) begin
						// 1 octet / 10 cycles
						if(func_state == 0) begin
							VIDEO_memA_addr <= CPU_stack_ptr;
							func_state <= 1;
						end
						else if(func_state == 1) begin// Laisse un cycle pour lire la mémoire
							VIDEO_memA_addr <= CPU_stack_ptr + 1;
							func_state <= 2;
						end
						else if(func_state == 2) begin
							CPU_E <= VIDEO_memA_rdata;
							func_state <= 3;
						end
						else if(func_state == 3) begin
							CPU_D <= VIDEO_memA_rdata;
							func_state <= 4;
						end
						else begin
							CPU_stack_ptr <= (CPU_stack_ptr + 2);
							func_state <= 0;
							cpu_state <= 0;
							CPU_pc <= CPU_pc + 1;
						end
						
					end
					else if( OPCODE[7:0] == 8'hE1) begin
						// 1 octet / 10 cycles
						if(func_state == 0) begin
							VIDEO_memA_addr <= CPU_stack_ptr;
							func_state <= 1;
						end
						else if(func_state == 1) begin// Laisse un cycle pour lire la mémoire
							VIDEO_memA_addr <= CPU_stack_ptr + 1;
							func_state <= 2;
						end
						else if(func_state == 2) begin
							CPU_L <= VIDEO_memA_rdata;
							func_state <= 3;
						end
						else if(func_state == 3) begin
							CPU_H <= VIDEO_memA_rdata;
							func_state <= 4;
						end
						else begin
							CPU_stack_ptr <= (CPU_stack_ptr + 2);
							func_state <= 0;
							cpu_state <= 0;
							CPU_pc <= CPU_pc + 1;
						end
						
					end
					else if( OPCODE[7:0] == 8'hF1) begin // POP PSW
						// 1 octet / 10 cycles
						if(func_state == 0) begin
							VIDEO_memA_addr <= CPU_stack_ptr;
							func_state <= 1;
						end
						else if(func_state == 1) begin// Laisse un cycle pour lire la mémoire
							VIDEO_memA_addr <= CPU_stack_ptr + 1;
							func_state <= 2;
						end
						else if(func_state == 2) begin
							//{CPU_s,CPU_z,1'b0,CPU_ac,1'b0,CPU_p,1'b1,CPU_carry}
							CPU_carry <= VIDEO_memA_rdata[0];
							CPU_p <= VIDEO_memA_rdata[2];
							CPU_ac <= VIDEO_memA_rdata[4];
							CPU_z <= VIDEO_memA_rdata[6];
							CPU_s <= VIDEO_memA_rdata[7];
							
							func_state <= 3;
						end
						else if(func_state == 3) begin
							CPU_A <= VIDEO_memA_rdata;
							func_state <= 4;
						end
						else begin
							CPU_stack_ptr <= (CPU_stack_ptr + 2);
							func_state <= 0;
							cpu_state <= 0;
							CPU_pc <= CPU_pc + 1;
						end
						
					end
					else if(OPCODE[7:0] == 8'h07) begin
						// 1 octet / 4 cycles
						CPU_A <= {CPU_A[6:0],CPU_A[7]};
						CPU_carry <= CPU_A[7];
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h0F) begin
						// 1 octet / 4 cycles
						CPU_carry <= CPU_A[0];
						CPU_A <= {CPU_A[0],CPU_A[7:1]};
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h1F) begin
						// 1 octet / 4 cycles
						CPU_carry <= CPU_A[0];
						CPU_A <= {CPU_carry,CPU_A[7:1]};
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h2F) begin
						// 1 octet / 4 cycles
						CPU_A <= ~CPU_A;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h4E) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							if({CPU_H,CPU_L} >= RAM_START) VIDEO_memA_addr <= {CPU_H,CPU_L};
							else cpu_rom_raddr <= {CPU_H,CPU_L};
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							func_state <= 2;//Laisse un 1 cycle pour lire la mémoire
						end
						else begin
							if({CPU_H,CPU_L} >= RAM_START) CPU_C <= VIDEO_memA_rdata;
							else CPU_C <= rom_rdata;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'h41) begin
						// 1 octet / 5 cycles
						CPU_B <= CPU_C;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h47) begin
						// 1 octet / 5 cycles
						CPU_B <= CPU_A;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h48) begin
						// 1 octet / 5 cycles
						CPU_C <= CPU_B;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h4F) begin
						// 1 octet / 5 cycles
						CPU_C <= CPU_A;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h51) begin
						// 1 octet / 5 cycles
						CPU_D <= CPU_C;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h5F) begin
						// 1 octet / 5 cycles
						CPU_E <= CPU_A;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h61) begin
						// 1 octet / 5 cycles
						CPU_H <= CPU_C;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h68) begin
						// 1 octet / 5 cycles
						CPU_L <= CPU_B;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h69) begin
						// 1 octet / 5 cycles
						CPU_L <= CPU_C;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h6A) begin
						// 1 octet / 5 cycles
						CPU_L <= CPU_D;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h6B) begin
						// 1 octet / 5 cycles
						CPU_L <= CPU_E;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h6F) begin
						// 1 octet / 5 cycles
						CPU_L <= CPU_A;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h7F) begin
						// 1 octet / 5 cycles
						CPU_A <= CPU_A;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h09) begin
						// 1 octet / 10 cycles
						{CPU_carry,CPU_H,CPU_L} <= {CPU_H,CPU_L} + {CPU_B,CPU_C};
						
						/*if(CPU_H > 0 || CPU_B > 0) CPU_carry <= 1;
						else CPU_carry <=  ((CPU_L + CPU_C) >> 8 )? 1 : 0;*/
						
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h19) begin
						// 1 octet / 10 cycles
						{CPU_carry,CPU_H,CPU_L} <= {CPU_H,CPU_L} + {CPU_D,CPU_E};
						
						/*if(CPU_H > 0 || CPU_D > 0) CPU_carry <= 1;
						else CPU_carry <=  ((CPU_L + CPU_E) >> 8 )? 1 : 0;*/
						
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h29) begin
						// 1 octet / 10 cycles
						{CPU_carry,CPU_H,CPU_L} <= {CPU_H,CPU_L} + {CPU_H,CPU_L};
						//CPU_carry <= ({CPU_H,CPU_L} >= 16'h8000)? 1 : 0;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h86) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							VIDEO_memA_addr <= {CPU_H,CPU_L};
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							func_state <= 2;//Laisse un 1 cycle pour lire la mémoire
						end
						else if(func_state == 2) begin
							{CPU_carry,CPU_A} <= CPU_A + VIDEO_memA_rdata;
							func_state <= 3;
						end
						else begin
							CPU_s <= CPU_A[7];
							CPU_z <= (CPU_A == 0)? 1 : 0;
							CPU_p <= ~^CPU_A;
							CPU_ac <= (CPU_A[3:0] > 9) ? 1 : 0;;
							
							func_state <= 0;
							CPU_pc <= CPU_pc + 1;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'hA6) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							VIDEO_memA_addr <= {CPU_H,CPU_L};
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							func_state <= 2;//Laisse un 1 cycle pour lire la mémoire
						end
						else if(func_state == 2) begin
							CPU_A <= CPU_A & VIDEO_memA_rdata;
							
							func_state <= 3;
						end
						else begin
							CPU_s <= CPU_A[7];
							CPU_z <= (CPU_A == 0)? 1 : 0;
							CPU_p <= ~^CPU_A;
							CPU_ac <= 0;
							CPU_carry <= 0;
							
							func_state <= 0;
							CPU_pc <= CPU_pc + 1;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'hB6) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							VIDEO_memA_addr <= {CPU_H,CPU_L};
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							func_state <= 2;//Laisse un 1 cycle pour lire la mémoire
						end
						else if(func_state == 2) begin
							CPU_A <= CPU_A | VIDEO_memA_rdata;
							func_state <= 3;
						end
						else begin
							CPU_s <= CPU_A[7];
							CPU_z <= (CPU_A == 0)? 1 : 0;
							CPU_p <= ~^CPU_A;
							CPU_ac <= 0;
							CPU_carry <= 0;
							
							func_state <= 0;
							CPU_pc <= CPU_pc + 1;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'hB4) begin
						// 1 octet / 4 cycles
						CPU_A <= CPU_A | CPU_H;
						
						CPU_s <= CPU_A[7]| CPU_H[7];
						CPU_z <= ((CPU_A | CPU_H) == 0);
						CPU_p <= ~^(CPU_A | CPU_H);
						CPU_ac <= 0;
						CPU_carry <= 0;
							
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'hA7) begin
						// 1 octet / 4 cycles
						CPU_A <= CPU_A & CPU_A;
						
						//set flags						
						CPU_s <= CPU_A[7];
						CPU_z <= (CPU_A == 0)? 1 : 0;
						CPU_p <= ~^CPU_A;
						CPU_ac <= 0;
						CPU_carry <= 0;
							
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'hA8) begin
						// 1 octet / 4 cycles
						CPU_A <= CPU_A ^ CPU_B;
						
						//set flags						
						CPU_s <= CPU_A[7] ^ CPU_B[7];
						CPU_z <= ((CPU_A ^ CPU_B) == 0) ? 1 : 0;
						CPU_p <= ~^(CPU_A ^ CPU_B);
						CPU_ac <= 0;
						CPU_carry <= 0;
							
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'hAF) begin
						// 1 octet / 4 cycles
						CPU_A <= CPU_A ^ CPU_A;
						
						//set flags						
						CPU_s <= 0;
						CPU_z <= 1;
						CPU_p <= 1;
						CPU_ac <= 0;
						CPU_carry <= 0;
							
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'hB0) begin
						// 1 octet / 4 cycles
						CPU_A <= CPU_B | CPU_A;
						
						//set flags						
						CPU_s <= CPU_B[7] | CPU_A[7];
						CPU_z <= ((CPU_A == 0) && (CPU_B == 0))? 1 : 0;
						CPU_p <= ~^(CPU_B | CPU_A);
						CPU_ac <= 0;
						CPU_carry <= 0;
							
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'hEB) begin
						// 1 octet / 5 cycles
						{CPU_H,CPU_L} <= {CPU_D,CPU_E};
						{CPU_D,CPU_E} <= {CPU_H,CPU_L};
						
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'hFB) begin
						// 1 octet / 4 cycles
						int_enabled <= 1;
						
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h34) begin
						// 1 octet / 10 cycles
						if(func_state == 0) begin
							VIDEO_memA_addr <= {CPU_H,CPU_L};
							func_state <= 1;
						end
						else if(func_state == 1) begin
							func_state <= 2;//Laisse un 1 cycle pour lire la mémoire
						end
						else if(func_state == 2) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= {CPU_H,CPU_L};
							VIDEO_mem_wdata <= VIDEO_memA_rdata + 1;
							tmp <= VIDEO_memA_rdata + 1;
							
							func_state <= 3;
						end
						else begin
							VIDEO_mem_wren <= 0;
							
							//set flags						
							CPU_s <= tmp[7];
							CPU_z <= (tmp == 0) ? 1 : 0;
							CPU_p <= ~^tmp;
							CPU_ac <= (tmp[3:0] > 9) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'h35) begin
						// 1 octet / 10 cycles
						if(func_state == 0) begin
							VIDEO_memA_addr <= {CPU_H,CPU_L};
							func_state <= 1;
						end
						else if(func_state == 1) begin
							func_state <= 2;//Laisse un 1 cycle pour lire la mémoire
						end
						else if(func_state == 2) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= {CPU_H,CPU_L};
							VIDEO_mem_wdata <= VIDEO_memA_rdata - 1;
							tmp <= VIDEO_memA_rdata - 1;
							
							func_state <= 3;
						end
						else begin
							VIDEO_mem_wren <= 0;
							
							//set flags						
							CPU_s <= tmp[7];
							CPU_z <= (tmp == 0) ? 1 : 0;
							CPU_p <= ~^tmp;
							CPU_ac <= (tmp[3:0] > 9) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'h56) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							if({CPU_H,CPU_L} >= RAM_START) VIDEO_memA_addr <= {CPU_H,CPU_L};
							else cpu_rom_raddr <= {CPU_H,CPU_L};
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							func_state <= 2;//Laisse un 1 cycle pour lire la mémoire
						end
						else begin
							if({CPU_H,CPU_L} >= RAM_START) CPU_D <= VIDEO_memA_rdata;
							else CPU_D <= rom_rdata;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'h5E) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							if({CPU_H,CPU_L} >= RAM_START) VIDEO_memA_addr <= {CPU_H,CPU_L};
							else cpu_rom_raddr <= {CPU_H,CPU_L};
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							func_state <= 2;//Laisse un 1 cycle pour lire la mémoire
						end
						else begin
							if({CPU_H,CPU_L} >= RAM_START) CPU_E <= VIDEO_memA_rdata;
							else CPU_E <= rom_rdata;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'h62) begin
						// 1 octet / 5 cycles
						CPU_H <= CPU_D;
						
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h63) begin
						// 1 octet / 5 cycles
						CPU_H <= CPU_E;
						
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h65) begin
						// 1 octet / 5 cycles
						CPU_H <= CPU_L;
						
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h66) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							if({CPU_H,CPU_L} >= RAM_START) VIDEO_memA_addr <= {CPU_H,CPU_L};
							else cpu_rom_raddr <= {CPU_H,CPU_L};
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							func_state <= 2;//Laisse un 1 cycle pour lire la mémoire
						end
						else begin
							if({CPU_H,CPU_L} >= RAM_START) CPU_H <= VIDEO_memA_rdata;
							else CPU_H <= rom_rdata;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'h47) begin
						// 1 octet / 5 cycles
						CPU_B <= CPU_A;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h57) begin
						// 1 octet / 5 cycles
						CPU_D <= CPU_A;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h67) begin
						// 1 octet / 5 cycles
						CPU_H <= CPU_A;
						CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h46) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							if({CPU_H,CPU_L} >= RAM_START) VIDEO_memA_addr <= {CPU_H,CPU_L};
							else cpu_rom_raddr <= {CPU_H,CPU_L};
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							func_state <= 2;//Laisse un 1 cycle pour lire la mémoire
						end
						else begin
							if({CPU_H,CPU_L} >= RAM_START) CPU_B <= VIDEO_memA_rdata;
							else CPU_B <= rom_rdata;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'h7E) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							if({CPU_H,CPU_L} >= RAM_START) VIDEO_memA_addr <= {CPU_H,CPU_L};
							else cpu_rom_raddr <= {CPU_H,CPU_L};
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							func_state <= 2;//Laisse un 1 cycle pour lire la mémoire
						end
						else begin
							if({CPU_H,CPU_L} >= RAM_START) CPU_A <= VIDEO_memA_rdata;
							else CPU_A <= rom_rdata;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'hBE) begin
						// 1 octet / 7 cycles
						if(func_state == 0) begin
							if({CPU_H,CPU_L} >= RAM_START) VIDEO_memA_addr <= {CPU_H,CPU_L};
							else cpu_rom_raddr <= {CPU_H,CPU_L};
							
							func_state <= 1;
						end
						else if(func_state == 1) begin
							func_state <= 2;//Laisse un 1 cycle pour lire la mémoire
						end
						else if(func_state == 2) begin
							if({CPU_H,CPU_L} >= RAM_START) begin
								tmp <= CPU_A - VIDEO_memA_rdata;
								CPU_carry <= (CPU_A < VIDEO_memA_rdata) ? 1 : 0;
							end
							else begin
								tmp <= CPU_A - rom_rdata;
								CPU_carry <= (CPU_A < rom_rdata) ? 1 : 0;
							end
							
							func_state <= 3;
						end
						else begin
							CPU_s <= tmp[7];
							CPU_z <= (tmp == 0) ? 1 : 0;
							CPU_p <= ~^tmp;
							CPU_ac <= (tmp[3:0] > 9) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'hE3) begin
						// 1 octet / 18 cycles
						if(func_state == 0) begin
							VIDEO_memA_addr <= CPU_stack_ptr;
							func_state <= 1;
						end
						else if(func_state == 1) begin// Laisse un cycle pour lire la mémoire
							VIDEO_memA_addr <= CPU_stack_ptr + 1;
							func_state <= 2;
						end
						else if(func_state == 2) begin
							tmp2[7:0] <= VIDEO_memA_rdata;
							func_state <= 3;
						end
						else if(func_state == 3) begin
							tmp2[15:8] <= VIDEO_memA_rdata;
							func_state <= 4;
						end
						else if(func_state == 4) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= CPU_stack_ptr + 1;
							VIDEO_mem_wdata <= CPU_H;
							
							func_state <= 5;
						end
						else if(func_state == 5) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= CPU_stack_ptr;
							VIDEO_mem_wdata <= CPU_L;
							
							func_state <= 6;
						end
						else begin
							{CPU_H,CPU_L} <= tmp2;
							
							VIDEO_mem_wren <= 0;							
							CPU_pc <= CPU_pc + 1;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'h06) begin
						// 2 octets
						
						OPCODE[15:8] <= rom_rdata;
						cpu_state <= 4;
					end
					else if(OPCODE[7:0] == 8'h16) begin
						// 2 octets
						
						OPCODE[15:8] <= rom_rdata;
						cpu_state <= 4;
					end
					else if(OPCODE[7:0] == 8'h26) begin
						// 2 octets
						
						OPCODE[15:8] <= rom_rdata;
						cpu_state <= 4;
					end
					else if(OPCODE[7:0] == 8'h36) begin
						// 2 octets
						
						OPCODE[15:8] <= rom_rdata;
						cpu_state <= 4;
					end
					else if(OPCODE[7:0] == 8'hE6) begin
						// 2 octets
						OPCODE[15:8] <= rom_rdata;
						cpu_state <= 4;
					end
					else if(OPCODE[7:0] == 8'hF6) begin
						// 2 octets
						OPCODE[15:8] <= rom_rdata;
						cpu_state <= 4;
					end
					else if(OPCODE[7:0] == 8'hFE) begin
						// 2 octets
						
						OPCODE[15:8] <= rom_rdata;
						cpu_state <= 4;
					end
					else if(OPCODE[7:0] == 8'h0E) begin
						// 2 octets
						
						OPCODE[15:8] <= rom_rdata;
						cpu_state <= 4;
					end
					else begin
						case(OPCODE[7:0]) 
							8'h2E : begin
								// 2 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'h3E : begin
								// 2 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hC6 : begin
								// 2 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hC3 : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hC4 : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hD3 : begin
								// 2 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hD6 : begin
								// 2 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hDB : begin
								// 2 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hDE : begin
								// 2 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'h31 : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'h22 : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'h2A : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'h32 : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'h3A : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hCC : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hCD : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hD2 : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hD4 : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hDA : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hFA : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'h11 : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'h21 : begin
								// 3 octets
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hC2 : begin
								// 3 octets						
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'hCA : begin
								// 3 octets						
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							8'h01 : begin
								// 3 octets						
								OPCODE[15:8] <= rom_rdata;
								cpu_state <= 4;
							end
							default : begin
								opcode_unk <= 1;
								//opcode_val1 <= {16'b0,OPCODE[7:0]};
								//opcode_val1 <= {cyclesTotal_counter[7:0],CPU_A[7:0],OPCODE[7:0]};
								//opcode_val1 <= {CPU_H[7:0],CPU_L[7:0],OPCODE[7:0]};
								//opcode_val1 <= {cyclesTotal_counter[15:8],cyclesTotal_counter[7:0],CPU_pc[15:8],CPU_pc[7:0],OPCODE[7:0]};
								opcode_val1 <= {int_enabled,int_rst,CPU_pc[15:8],CPU_pc[7:0],OPCODE[7:0]};
								
							end
						endcase
					end
					
					
				end
				else if(cpu_state == 4) begin // lit le 3ème octet de l'instruction / décode opcode 2 octets
					OPCODE[23:16] <= rom_rdata;
					
					if(OPCODE[7:0] == 8'h06) begin
						// 7 cycles
						CPU_pc <= CPU_pc + 2;
						CPU_B <= OPCODE[15:8];
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h16) begin
						// 7 cycles
						CPU_pc <= CPU_pc + 2;
						CPU_D <= OPCODE[15:8];
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h26) begin
						// 7 cycles
						CPU_H <= OPCODE[15:8];
						CPU_pc <= CPU_pc + 2;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'hDB) begin
						// 10 cycles
						if(OPCODE[15:8] == 1) CPU_A <= {1'b0,BtnP1Right,BtnP1Left,BtnP1Shot,1'b1,BtnP1Start,BtnP2Start,BtnCredit};
						else if(OPCODE[15:8] == 2) CPU_A <= {DIP7,BtnP2Right,BtnP2Left,BtnP2Shot,DIP6,BtnTilt,DIP5_DIP3};
						else if(OPCODE[15:8] == 3) begin
							for(i = 0;i <= 7;i = i + 1) begin
								CPU_A[7 - i] <= ShiftRegister_value[15 - i - ShiftRegister_offset];
							end
						end
						else begin
							opcode_unk <= 1;
							opcode_val1 <= {OPCODE[15:8],int_rst,CPU_pc[15:8],CPU_pc[7:0],OPCODE[7:0]};
						end
						
						CPU_pc <= CPU_pc + 2;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'hDE) begin
						// 7 cycles
						if(func_state == 0) begin
							CPU_A <= CPU_A - (OPCODE[15:8] + CPU_carry);
							CPU_carry <= (CPU_A < (OPCODE[15:8] + CPU_carry));
							func_state <= 1;
						end
						else begin
							//set flags						
							CPU_s <= CPU_A[7];
							CPU_z <= (CPU_A == 0) ? 1 : 0;
							CPU_p <= ~^CPU_A;
							CPU_ac <= (CPU_A[3:0] > 9) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 2;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else if(OPCODE[7:0] == 8'hE6) begin
						// 7 cycles
						if(func_state == 0) begin
							CPU_A <= CPU_A & OPCODE[15:8];
							func_state <= 1;
						end
						else begin
							//set flags						
							CPU_s <= CPU_A[7];
							CPU_z <= (CPU_A == 0) ? 1 : 0;
							CPU_p <= ~^CPU_A;
							CPU_ac <= (CPU_A[3:0] > 9) ? 1 : 0;
							CPU_carry <= 0;
							
							CPU_pc <= CPU_pc + 2;
							func_state <= 0;
							cpu_state <= 0;
						end
												
					end
					else if(OPCODE[7:0] == 8'hF6) begin
						// 7 cycles
						if(func_state == 0) begin
							CPU_A <= CPU_A | OPCODE[15:8];
							func_state <= 1;
						end
						else begin
							//set flags						
							CPU_s <= CPU_A[7];
							CPU_z <= (CPU_A == 0) ? 1 : 0;
							CPU_p <= ~^CPU_A;
							CPU_ac <= (CPU_A[3:0] > 9) ? 1 : 0;
							CPU_carry <= 0;
							
							CPU_pc <= CPU_pc + 2;
							func_state <= 0;
							cpu_state <= 0;
						end
												
					end
					else if(OPCODE[7:0] == 8'h36) begin
						// 10 cycles
						if(func_state == 0) begin
							VIDEO_mem_wren <= 1;
							VIDEO_memA_addr <= {CPU_H,CPU_L};
							VIDEO_mem_wdata <= OPCODE[15:8];
							
							func_state <= 1;
								
						end
						else begin
							VIDEO_mem_wren <= 0;
							CPU_pc <= CPU_pc + 2;
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if(OPCODE[7:0] == 8'hC6) begin
						// 7 cycles
						if(func_state == 0) begin
							{CPU_carry,CPU_A} <= CPU_A + OPCODE[15:8];
							func_state <= 1;
						end
						else begin
							//set flags
							CPU_s <= CPU_A[7];
							CPU_z <= (CPU_A == 0) ? 1 : 0;
							CPU_p <= ~^CPU_A;
							CPU_ac <= (CPU_A[3:0] > 9) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 2;
							func_state <= 0;
							cpu_state <= 0;
						end
						
					end
					else if(OPCODE[7:0] == 8'hFE) begin
						// 7 cycles
						
						if(func_state == 0) begin
							tmp <= (CPU_A - OPCODE[15:8]);
							func_state <= 1;
						end
						else begin
							//set flags
							CPU_s <= tmp[7];
							CPU_z <= (tmp == 0) ? 1 : 0;
							CPU_p <= ~^tmp;
							CPU_ac <= (tmp[3:0] > 9) ? 1 : 0;
							CPU_carry <= (CPU_A < OPCODE[15:8]) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 2;
							func_state <= 0;
							cpu_state <= 0;
							
						end
						
						/*if(CPU_L > 3) begin
							opcode_unk <= 1;//Debug
							opcode_val1 <= {cyclesTotal_counter[7:0],CPU_A[7:0],CPU_L[7:0],OPCODE[7:0]};
						end*/
					end
					else if(OPCODE[7:0] == 8'h0E ) begin
						//7 cycles
						CPU_C <= OPCODE[15:8];
						CPU_pc <= CPU_pc + 2;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h1E ) begin
						//7 cycles
						CPU_E <= OPCODE[15:8];
						CPU_pc <= CPU_pc + 2;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h2E ) begin
						//7 cycles
						CPU_L <= OPCODE[15:8];
						CPU_pc <= CPU_pc + 2;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'h3E ) begin
						//7 cycles
						CPU_A <= OPCODE[15:8];
						CPU_pc <= CPU_pc + 2;
						cpu_state <= 0;
					end
					else if(OPCODE[7:0] == 8'hD3 ) begin
						//10 cycles
						if(OPCODE[15:8] == 'h6) begin // WATCH-DOG (ignored)
							CPU_pc <= CPU_pc + 2;
							cpu_state <= 0;
						end
						else if(OPCODE[15:8] == 'h2) begin // Shift amount
							ShiftRegister_offset <= CPU_A;
							CPU_pc <= CPU_pc + 2;
							cpu_state <= 0;
						end
						else if(OPCODE[15:8] == 'h3 ) begin // SOUND1
							sound1_bits <= CPU_A;
							
							CPU_pc <= CPU_pc + 2;
							cpu_state <= 0;
						end
						else if(OPCODE[15:8] == 'h4) begin // Shift data
							ShiftRegister_value <= {CPU_A,ShiftRegister_value[15:8]};
							
							CPU_pc <= CPU_pc + 2;
							cpu_state <= 0;
						end
						else if(OPCODE[15:8] == 'h5 ) begin // SOUND2
						//else if(OPCODE[15:8] == 'h5 && (CPU_A == 0 || CPU_A==8'h01 || CPU_A==8'h02 || CPU_A==8'h04 || CPU_A==8'h08 || CPU_A[4]) ) begin // SOUND2
							//sound2_on <= 1;//Le son du port 5 doit toujours être actif
							
							sound2_bits <= CPU_A;
							
							// 01 => invadermove1
							// 02 => invadermove2
							// 04 => invadermove3
							// 08 => invadermove4
							// 10 => ufohit
							
							CPU_pc <= CPU_pc + 2;
							cpu_state <= 0;
						end
						else begin
							opcode_unk <= 1;
							opcode_val1 <= {OPCODE[15:8],CPU_A,CPU_pc[15:8],CPU_pc[7:0],OPCODE[7:0]};
						end
					end
					else if(OPCODE[7:0] == 8'hD6 ) begin
						if(func_state == 0) begin
							CPU_A <= CPU_A - OPCODE[15:8];
							CPU_carry = (OPCODE[15:8] > CPU_A)? 1 : 0;
							func_state <= 1;
						end
						else begin
							//set flags
							CPU_s <= CPU_A[7];
							CPU_z <= (CPU_A == 0) ? 1 : 0;
							CPU_p <= ~^CPU_A;
							CPU_ac <= (CPU_A[3:0] > 9) ? 1 : 0;
							
							CPU_pc <= CPU_pc + 2;
							func_state <= 0;
							cpu_state <= 0;
						end
					end
					else begin
						if(OPCODE[7:0] == 8'hC4) begin
							CPU_pc <= CPU_pc + 3;
							func_state <= 0;
						end
						else if(OPCODE[7:0] == 8'hCC) begin
							CPU_pc <= CPU_pc + 3;
							func_state <= 0;
						end
						else if(OPCODE[7:0] == 8'hCD) begin
							CPU_pc <= CPU_pc + 3;
							func_state <= 0;
						end
						else if(OPCODE[7:0] == 8'hD4) begin
							CPU_pc <= CPU_pc + 3;
							func_state <= 0;
						end
						
						cpu_state <= 5;
					end
				end
				else if(cpu_state == 5) begin // Décode l'opcode >= 3 octets
					
					case(OPCODE[7:0])
						8'h01: begin
							// 10 cycles
							CPU_pc <= CPU_pc + 3;
							{CPU_B,CPU_C} <= OPCODE[23:8];
							cpu_state <= 0;
						end
						8'hC3: begin
							// 10 cycles
							CPU_pc <= OPCODE[23:8];
							cpu_state <= 0;
						end
						8'h31: begin
							// 10 cycles
							CPU_pc <= CPU_pc + 3;
							CPU_stack_ptr <= OPCODE[23:8];
							cpu_state <= 0;
						end
						8'h32: begin
							// 13 cycles
							if(func_state == 0) begin
								VIDEO_mem_wren <= 1;
								VIDEO_memA_addr <= OPCODE[23:8];
								VIDEO_mem_wdata <= CPU_A;
								
								func_state <= 1;
							end
							else begin
								VIDEO_mem_wren <= 0;
								CPU_pc <= CPU_pc + 3;
								func_state <= 0;
								cpu_state <= 0;
							end
						end
						8'h22: begin
							// 16 cycles
							if(func_state == 0) begin
								VIDEO_mem_wren <= 1;
								VIDEO_memA_addr <= OPCODE[23:8];
								VIDEO_mem_wdata <= CPU_L;
								
								func_state <= 1;
							end
							else if(func_state == 1) begin
								VIDEO_mem_wren <= 1;
								VIDEO_memA_addr <= OPCODE[23:8] + 1;
								VIDEO_mem_wdata <= CPU_H;
								
								func_state <= 2;
							end
							else begin
								VIDEO_mem_wren <= 0;
								
								CPU_pc <= CPU_pc + 3;
								func_state <= 0;
								cpu_state <= 0;
							end
						end
						8'h2A: begin
							// 16 cycles
							if(func_state == 0) begin
								if(OPCODE[23:8] >= RAM_START) VIDEO_memA_addr <= OPCODE[23:8];
								else cpu_rom_raddr <= OPCODE[23:8];
								
								func_state <= 1;
							end
							else if(func_state == 1) begin //Laisse un 1 cycle pour lire la mémoire
								if(OPCODE[23:8] >= RAM_START) VIDEO_memA_addr <= OPCODE[23:8] + 1;
								else cpu_rom_raddr <= OPCODE[23:8] + 1;
								
								func_state <= 2;
							end
							else if(func_state == 2) begin
								if(OPCODE[23:8] >= RAM_START) CPU_L <= VIDEO_memA_rdata;
								else CPU_L <= rom_rdata;
								
								func_state <= 3;
							end
							else begin
								if(OPCODE[23:8] >= RAM_START) CPU_H <= VIDEO_memA_rdata;
								else CPU_H <= rom_rdata;
								
								CPU_pc <= CPU_pc + 3;
								func_state <= 0;
								cpu_state <= 0;
							end
						end
						8'h3A: begin
							// 13 cycles
							if(func_state == 0) begin
								if(OPCODE[23:8] >= RAM_START) VIDEO_memA_addr <= OPCODE[23:8];
								else cpu_rom_raddr <= OPCODE[23:8];
								
								func_state <= 1;
							end
							else if(func_state == 1) begin //Laisse un 1 cycle pour lire la mémoire
								func_state <= 2;
							end
							else begin
								if(OPCODE[23:8] >= RAM_START) CPU_A <= VIDEO_memA_rdata;
								else CPU_A <= rom_rdata;
								
								CPU_pc <= CPU_pc + 3;
								func_state <= 0;
								cpu_state <= 0;
							end
						end
						8'hC4: begin
							// 17 ou 11 cycles
							if(CPU_z == 0) begin
								if(func_state == 0) begin
									VIDEO_mem_wren <= 1;
									VIDEO_memA_addr <= CPU_stack_ptr - 1;
									VIDEO_mem_wdata <= CPU_pc[15:8];
									
									func_state <= 1;
								end
								else if(func_state == 1) begin
									VIDEO_mem_wren <= 1;
									VIDEO_memA_addr <= CPU_stack_ptr - 2;
									VIDEO_mem_wdata <= CPU_pc[7:0];
									func_state <= 2;
								end
								else begin
									CPU_stack_ptr <= (CPU_stack_ptr - 2);
									VIDEO_mem_wren <= 0;
									CPU_pc <= OPCODE[23:8];
									func_state <= 0;
									cpu_state <= 0;
								end
							end
							else begin
								cpu_state <= 0;
							end
						end
						8'hCC: begin
							// 17 ou 11 cycles
							if(CPU_z == 1) begin
								if(func_state == 0) begin
									VIDEO_mem_wren <= 1;
									VIDEO_memA_addr <= CPU_stack_ptr - 1;
									VIDEO_mem_wdata <= CPU_pc[15:8];
									
									func_state <= 1;
								end
								else if(func_state == 1) begin
									VIDEO_mem_wren <= 1;
									VIDEO_memA_addr <= CPU_stack_ptr - 2;
									VIDEO_mem_wdata <= CPU_pc[7:0];
									func_state <= 2;
								end
								else begin
									CPU_stack_ptr <= (CPU_stack_ptr - 2);
									VIDEO_mem_wren <= 0;
									CPU_pc <= OPCODE[23:8];
									func_state <= 0;
									cpu_state <= 0;
								end
							end
							else begin
								cpu_state <= 0;
							end
						end
						8'hCD: begin
							// 17 cycles
							if(func_state == 0) begin
								VIDEO_mem_wren <= 1;
								VIDEO_memA_addr <= CPU_stack_ptr - 1;
								VIDEO_mem_wdata <= CPU_pc[15:8];
								
								func_state <= 1;
							end
							else if(func_state == 1) begin
								VIDEO_mem_wren <= 1;
								VIDEO_memA_addr <= CPU_stack_ptr - 2;
								VIDEO_mem_wdata <= CPU_pc[7:0];
								func_state <= 2;
							end
							else begin
								CPU_stack_ptr <= (CPU_stack_ptr - 2);
								VIDEO_mem_wren <= 0;
								CPU_pc <= OPCODE[23:8];
								func_state <= 0;
								cpu_state <= 0;
							end
						end
						8'hD2: begin
							// 10 cycles
							if(CPU_carry == 0) CPU_pc <= OPCODE[23:8];
							else CPU_pc <= CPU_pc + 3;
							
							cpu_state <= 0;
						end
						8'hD4: begin
							// 17 ou 11 cycles
							if(func_state == 0) begin
								if(CPU_carry == 0) begin
									VIDEO_mem_wren <= 1;
									VIDEO_memA_addr <= CPU_stack_ptr - 1;
									VIDEO_mem_wdata <= CPU_pc[15:8];
									
									func_state <= 1;
								end
								else begin
									//CPU_pc <= CPU_pc + 3;//CPU_pc est changé à l'étape précédente
									cpu_state <= 0;
								end
							end
							else if(func_state == 1) begin
								VIDEO_mem_wren <= 1;
								VIDEO_memA_addr <= CPU_stack_ptr - 2;
								VIDEO_mem_wdata <= CPU_pc[7:0];
								func_state <= 2;
							end
							else begin
								CPU_stack_ptr <= (CPU_stack_ptr - 2);
								VIDEO_mem_wren <= 0;
								CPU_pc <= OPCODE[23:8];
								func_state <= 0;
								cpu_state <= 0;
							end
						end
						8'hDA: begin
							// 10 cycles
							if(CPU_carry) CPU_pc <= OPCODE[23:8];
							else CPU_pc <= CPU_pc + 3;
							
							cpu_state <= 0;
						end
						8'h11: begin
							// 10 cycles
							CPU_D <= OPCODE[23:16];
							CPU_E <= OPCODE[15:8];
							CPU_pc <= CPU_pc + 3;
							cpu_state <= 0;
						end
						8'h21: begin
							// 10 cycles
							CPU_H <= OPCODE[23:16];
							CPU_L <= OPCODE[15:8];
							CPU_pc <= CPU_pc + 3;
							cpu_state <= 0;
						end
						8'hC2: begin
							// 10 cycles
							CPU_pc <= CPU_z ? (CPU_pc + 3) : OPCODE[23:8];
							cpu_state <= 0;
						end
						8'hCA: begin
							// 10 cycles
							CPU_pc <= CPU_z ? OPCODE[23:8] : (CPU_pc + 3);
							cpu_state <= 0;
						end
						8'hFA: begin
							// 10 cycles
							CPU_pc <= CPU_s ? OPCODE[23:8] : (CPU_pc + 3);
							cpu_state <= 0;
						end
					endcase
					
				end
				
				/*else if(cpu_state == 1) begin // lit le 1er octet de l'instruction
					OPCODE[7:0] <= rom_rdata;
					cpu_state <= 2;
				end
				else if(cpu_state == 2) begin // Décrypte l'opcode
					if(OPCODE[7:0] == 8'h0) begin
						// 4 cycles
						if(CPU_pc <= 'h1ffe) CPU_pc <= CPU_pc + 1;
						cpu_state <= 0;
					end
					else begin
						opcode_unk <= 1;
						opcode_val1 <= OPCODE[7:0];
					end
					
				end*/
				
				/*else if(cpu_state == 1) begin //Laisse un cycle pour lire la mémoire
					if(CPU_pc <= 'h1ff8) cpu_rom_raddr <= (CPU_pc + 1);
					cpu_state <= 2;
				end
				else if(cpu_state == 2) begin // lit le 1er octet de l'instruction
					OPCODE[7:0] <= rom_rdata;
					cpu_state <= 3;
				end
				else if(cpu_state == 3) begin // Décrypte l'opcode
					if(OPCODE[7:0] == 8'h0) begin
						// 4 cycles
						CPU_pc <= CPU_pc + 1;
					end
					else begin
						opcode_unk <= 1;
						opcode_val1 <= OPCODE[7:0];
					end
					
				end*/
			end
		end
		else begin
			CPU_pc <= 0;
			cpu_state <= 0;
			opcode_unk <= 0;
		end
	end
end

// SIMULATION
always @(posedge clk_2MHz or posedge reset) begin
	if(reset) begin
		simul_counter1 <= 0;
		
		//CHARS[0] <= 64'hff3e4549513e00ff;//|0|
	end
	else begin
		if(game_ready) begin
			
			//if(opcode_unk && simul_counter1 <= 127) begin
			if(opcode_unk && simul_counter1 <= 79) begin
				//On insert dans la mémoire vidéo le chiffre 0
				DBG_mem_wren <= 1;
				DBG_mem_wraddr <= VIDEO_START + (simul_counter1*32);//256/8
				
				
				case(
					(simul_counter1 < 8) ? opcode_val1[39:36] : 
					(simul_counter1 < 16) ? opcode_val1[35:32] : 
					(simul_counter1 < 24) ? opcode_val1[31:28] : 
					(simul_counter1 < 32) ? opcode_val1[27:24] : 
					(simul_counter1 < 40) ? opcode_val1[23:20] : 
					(simul_counter1 < 48) ? opcode_val1[19:16] : 
					(simul_counter1 < 56) ? opcode_val1[15:12] : 
					(simul_counter1 < 64) ? opcode_val1[11:8] : 
					(simul_counter1 < 72) ? opcode_val1[7:4] : opcode_val1[3:0]
					)
					0 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHAR0_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHAR0_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					1 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHAR1_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHAR1_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					2 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHAR2_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHAR2_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					3 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHAR3_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHAR3_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					4 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHAR4_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHAR4_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					5 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHAR5_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHAR5_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					6 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHAR6_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHAR6_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					7 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHAR7_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHAR7_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					8 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHAR8_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHAR8_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					9 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHAR9_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHAR9_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					10 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHARA_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHARA_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					11 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHARB_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHARB_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					12 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHARC_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHARC_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					13 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHARD_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHARD_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					14 : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHARE_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHARE_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
					default : begin
						if(simul_counter1[2:0] < 4) DBG_mem_wdata <= CHARF_H[8*(3 - simul_counter1[2:0]) +: 8];
						else DBG_mem_wdata <= CHARF_L[8*(3 - simul_counter1[2:0]) +: 8];
					end
				endcase
				
				
			end
			else begin
				DBG_mem_wren <= 0;
			end
			
			if(opcode_unk && simul_counter1 <= 86) simul_counter1 <= simul_counter1 + 1;
		end
		else simul_counter1 <= 0;
	end
end


// ** Boucle qui écrit la ROM dans la mémoire **
always @(posedge clk_2MHz) begin
	if(cpu_rom_save) begin
		rom_wdata <= cpu_rom_wdata;		
		rom_waddr <= cpu_rom_waddr;
		/*rom_wdata[7:4] <= cpu_rom_wdata[7:4];
		rom_wdata[3:0] <= cpu_rom_wdata[3:0];
		rom_waddr[7:4] <= cpu_rom_waddr[7:4];
		rom_waddr[3:0] <= cpu_rom_waddr[3:0];*/
		rom_en <= 1;
	end
	else rom_en <= 0;
end

// ** Gestion de l'ISR **
/*always @(int_rst,int_enabled) begin
	if(int_enabled && int_rst != int_rst_prev) begin
		int_newEventId = int_nextEventId;
	end
	else begin
		int_newEventId = int_newEventId + 0;
	end
	
	int_rst_prev = int_rst;
end*/

// ** Gestion du DAA **
always @(CPU_A,CPU_ac,CPU_carry) begin
	
	if(CPU_A[3:0] > 9 || CPU_ac) begin
		OP_daa_ac = (CPU_A[3:0] >= 9) ? 1 : 0;
		OP_daa_A = CPU_A + 6;
	end
	else begin
		OP_daa_ac = 0;
		OP_daa_A = CPU_A;
	end
	/*else if(CPU_A[7:4] > 9 || CPU_carry) begin
		CPU_carry <= (CPU_A[7:4] >= 9) ? 1 : 0;
		CPU_A <= {(CPU_A[7:4] + 6),CPU_A[3:0]};
	end*/
	
	if(OP_daa_A[7:4] > 9 || CPU_carry) begin
		OP_daa_carry = (OP_daa_A[7:4] >= 9) ? 1 : 0;
		OP_daa_A = OP_daa_A + 8'h60;// {(OP_daa_A[7:4] + 6),OP_daa_A[3:0]};
	end
	else begin
		OP_daa_carry = 0;
		OP_daa_A = OP_daa_A + 0;
	end
end
						
// ** Gestion des boutons **
assign BtnP1Start = gamepad_key[15];//Start
assign BtnP1Shot = gamepad_key[5];//A
assign BtnP1Left = gamepad_key[4];
assign BtnP1Right = gamepad_key[6];
assign BtnCredit = gamepad_key[13];//R2
assign BtnTilt = gamepad_key[14];//R3


endmodule