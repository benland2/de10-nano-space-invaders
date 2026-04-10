 /**
Description
Module qui synchronise les signaux (hsync et vsync)
d'un contrôleur VGA 640x480 60hz, fonctionne avec une horloge de 25Mhz

Il dispose également des coordonnées des pixels H (axe x)
et des pixels V (axe y). Pour envoyer le signal RVB correspondant
à chaque pixel

------------------------------------------------------------------------------------
vgaHdmi.v
------------------------------------------------------------------------------------
*/

module vgaHdmi(
	// ** input **
	input clock, clock50, reset,
	
	// ** output **
	output reg hsync, vsync,
	output reg dataEnable,
	output vgaClock,//type wire
	output [23:0] RGBchannel,
	
	input [9:0] instructionNum,
	input [9:0] instructionAddr,
	input [7:0] instructionData,
	output reg [9:0] instructionPrev,
	
	input screen_mode,
	
	// ** vars for pixels in game mode
	output reg game_rdreq,
	input [14:0] game_pixel, //draw_color,draw_x,draw_y
	input game_dataEmpty,
	
	// ** vars for renderer
	output reg [9:0] cpu_instrctionNum,//Vars pour gérer la synchro entre le CPU et HDMI
	input [9:0] cpu_instrctionSync,//Vars pour gérer la synchro entre le CPU et HDMI
	output reg [12:0] cpu_mem_rdaddr,
	input cpu_mem_rdren,
	input [7:0] cpu_mem_rdata,
	
	// ** vars for ISR **
	output reg [7:0] cpu_int_rst
	
);

// Videos Modeline
/*parameter h_display = 1024;
parameter h_front_porch = 40;
parameter h_sync = 104;
parameter h_back_porch = 144;
parameter h_total = 1312;

parameter v_display = 600;
parameter v_front_porch = 3;
parameter v_sync = 10;
parameter v_back_porch = 11;
parameter v_total = 624;*/

parameter h_display = 640;
parameter h_front_porch = 16;
parameter h_sync = 96;
parameter h_back_porch = 48;
parameter h_total = 800;

parameter v_display = 480;
parameter v_front_porch = 10;
parameter v_sync = 2;
parameter v_back_porch = 33;
parameter v_total = 525;


reg [10:0] pixelH, pixelV; // état interne des pixels du module
reg [9:0]	pixel_x, pixel_y;// pixel pour la position sur la partie visible
reg [9:0]	pixel_x_de1, pixel_y_de1;
reg [9:0]	pixel_x_de2, pixel_y_de2;

reg [23:0] r_pixel;
wire [2:0] text_pixel;

wire [2:0] draw_color;
wire [7:0] draw_x;
wire [7:0] draw_y;

wire [2:0] gb_color;

reg h_act, v_act;

wire h_max, hs_end, hr_start,hr_end;
wire v_max, vs_end, vr_start,vr_end;

//Gestion des décalages
reg pre1_vga_de, pre2_vga_de, pre3_vga_de;

reg [12:0] frame_waddr;
reg [7:0] frame_wdata;
reg frame_wren;

//Variables game screen
parameter screen_w = 224;
parameter screen_h = 256;
parameter screen_x1 = (h_display - screen_w) >> 1;
//parameter screen_x2 = 432;
parameter screen_x2 = (h_display + screen_w) >> 1;

parameter INSTRUCTION_MAX = 1023;

reg read_for_game = 0;
reg read_for_game_de1 = 0;

// Variables pour la RAM qui sert à l'affichage
reg [2:0] mem_inp_pixel;
reg mem_wren;
reg [7:0] mem_x;
reg [7:0] mem_y;

// Variables pour gérer le rendu vidéo
reg [7:0] cpu_pixelX_start;
reg [7:0] cpu_pixelY_start;
reg [7:0] cpu_pixelX;
reg [7:0] cpu_pixelY;
reg reqNewValue;
reg [16:0] pixel_counter1;


initial begin
	hsync = 1;
	vsync = 1;
	pixelH = 0;
	pixelV = 0;
	dataEnable = 0;
	pre1_vga_de = 0;
	pre2_vga_de = 0;
	pre3_vga_de = 0;
	
	//pour gérer l'écriture dans la la frame
	frame_waddr = 0;
	frame_wdata = 0;
	frame_wren = 0;
	instructionPrev = 0;
	
	pixel_counter1 = 0;
end

// Génération des signaux de synchronisations (logique négative)
assign h_max = pixelH == (h_total - 1);
assign hs_end = pixelH >= (h_sync - 1);
assign hr_start = pixelH == (h_sync + h_back_porch - 3);// - 1 - 2(delay)
assign hr_end = pixelH == (h_sync + h_back_porch - 3 + h_display);

assign v_max = pixelV == (v_total - 1);
assign vs_end = pixelV >= (v_sync - 1);
assign vr_start = pixelV == (v_sync + v_back_porch - 1);
assign vr_end = pixelV == (v_sync + v_back_porch - 1 + v_display);

always @(posedge clock or posedge reset) begin
	if(reset) begin
		hsync <= 1;
		vsync <= 1;
		pixelH <= 0;
		pixelV <= 0;
	end
	else begin
		pixel_x_de2 <= pixel_x_de1;
		pixel_y_de2 <= pixel_y_de1;
		pixel_x_de1 <= pixel_x;
		pixel_y_de1 <= pixel_y;
		
		// Gestion du signal Horizontal		
		if(h_max)
			pixelH <= 11'b0;
		else
			pixelH <= pixelH + 11'b1;
			
		if (h_act)
			pixel_x	<=	pixel_x + 11'b1;
		else
			pixel_x	<=	11'b0;
		
		if(hs_end && !h_max)
			hsync  <= 1'b1;
		else 
			hsync <= 1'b0;
			
		if(hr_start)
			h_act <= 1'b1;
		else if(hr_end)
			h_act <= 1'b0;

		// Gestion du signal vertical
		if (h_max)
		begin
			if(v_max)
				pixelV <= 11'b0;
			else
				pixelV <= pixelV + 11'b1;
				
			if (v_act)
				pixel_y	<=	pixel_y + 11'b1;
			else
				pixel_y	<=	11'b0;
				
			if(vs_end && !v_max)
				vsync  <= 1'b1;
			else 
				vsync <= 1'b0;
				
			if(vr_start)
				v_act <= 1'b1;
			else if(vr_end)
				v_act <= 1'b0;
		end
	end
end

// dataEnable signal
always @(posedge clock or posedge reset) begin
	if(reset) begin
		dataEnable <= 0;
		pre1_vga_de <= 0;
		pre2_vga_de <= 0;
		pre3_vga_de <= 0;
	end
	else begin
		//2 pixels de décalage pour se synchroniser avec framework (1 délai pour les coordonnées x,y + 1 délay pour la rom +  + 1 délay pour la ram)
		dataEnable <= pre3_vga_de;
		pre2_vga_de <= pre1_vga_de;
		pre3_vga_de <= pre2_vga_de;
		
		pre1_vga_de <= v_act && h_act;
	end
end

assign vgaClock = clock;

assign frame = (hr_start) && (pixelV == (v_sync + v_back_porch + v_display));

framebuffer fb(
	.clk(clock),
	.wrclk(clock50),
	.x(pixel_x),
	.y(pixel_y),
	.o_pixel(text_pixel),
	.ram_waddr(frame_waddr),
	.ram_wdata(frame_wdata),
	.ram_wren(frame_wren)
);

gamebuffer gb(
	.clk(clock),
	.x( mem_wren ? mem_x : (pixel_x_de2 - screen_x1) ),
	.y( mem_wren ? mem_y : (pixel_y_de2) ),
	
	.o_pixel(gb_color),
	
	.mem_wren(mem_wren),
	.inp_pixel(mem_inp_pixel)
);

/* boucle qui calcul la frame à afficher sur l'écran de démarrage (cette frame est écrite en RAM) */
always @(posedge clock50) begin
	if(instructionNum != instructionPrev) begin // Détecte une nouvelle instruction
		frame_waddr <= instructionAddr;
		frame_wren <= 1;
		frame_wdata <= instructionData;
		
		instructionPrev <= instructionNum;
	end
	else begin
		frame_wren <= 0;
	end
end

// Affichage des pixels
always @(posedge clock or posedge reset) begin
	if(reset) begin
		game_rdreq <= 0;
		cpu_mem_rdaddr <= 0;
		cpu_instrctionNum <= 0;
		reqNewValue <= 0;
		cpu_int_rst <= 0;
	end
	else begin
		if(screen_mode == 1) begin // Mode video game
			// Gestion de l'ISR
			if(pixel_y_de2 == 96 && pixel_x_de2 == 1) cpu_int_rst <= 'h8;
			if(pixel_y_de2 == 224 && pixel_x_de2 == 1) cpu_int_rst <= 'h10;
			
			//if(pixel_x_de2 > ((h_display - screen_w) >> 1)  && pixel_x_de2 <= ((h_display + screen_w) >> 1) && pixel_y_de2 < screen_h ) begin
			if(pixel_y_de2 < screen_h ) begin
				if((pixel_x_de2 > screen_x1) && pixel_x_de2 <= screen_x2 ) begin
					// Screen game
					game_rdreq <= 0;
					r_pixel[23:16] <= 8'd255 * gb_color[0];
					r_pixel[15:8] <= 8'd255 * gb_color[1];
					r_pixel[7:0] <= 8'd255 * gb_color[2];
				end
				else begin
					r_pixel[23:16] <= 8'd144;
					r_pixel[15:8] <= 8'd145;
					r_pixel[7:0] <= 8'd216;
				end
			end
			else begin
				r_pixel[23:16] <= 8'd144;
				r_pixel[15:8] <= 8'd145;
				r_pixel[7:0] <= 8'd216;
				
				if(pixel_y_de2 == screen_h) pixel_counter1 <= 0;//On réinitialise le pixel_counter1 avant la récup des infos en mémoire
				
				// Dans ce block, on récupère les infos du cpu pour écrire dans la mémoire du gamebuffer
				//if(pixel_y_de2 >= (screen_h + 1) &&  pixel_y_de2 <= (screen_h + 72)) begin
				if(pixel_y_de2 >= (screen_h + 1) &&  pixel_y_de2 <= (screen_h + 200)) begin // 260
					game_rdreq <= 1;
					
				end
				else begin
					game_rdreq <= 0;
				end
			end
			
			if(game_rdreq & !game_dataEmpty) begin
				mem_wren <= 1;
				mem_inp_pixel <= draw_color;
				mem_x <= draw_x;
				mem_y <= draw_y;
			end
			else mem_wren <= 0;
			
			// Synchro de la RAM CPU avec la RAM VIDEO
			//if(simul_counter1 < 4096) begin
			//if(simul_counter1 < 32768) begin
			//if(simul_counter1 < 32769 && simul_counter1 != 32768) begin
			//if(pixel_counter1 <= 32767) begin
			if(pixel_counter1 <= 57343) begin
			//if(simul_counter1 < 27386) begin
				if(game_rdreq ) begin
					
					if(pixel_counter1[2:0] == 0) begin
						if(cpu_instrctionNum == 0 || cpu_instrctionNum == cpu_instrctionSync) begin
							cpu_mem_rdaddr <= pixel_counter1 >> 3;
							if(cpu_instrctionNum == INSTRUCTION_MAX) cpu_instrctionNum <= 1;
							else cpu_instrctionNum <= cpu_instrctionNum + 1;
							
							//cpu_pixelX_start <= pixel_counter1[7:0];//Position avant rotation
							//cpu_pixelY <= pixel_counter1 >> 8;//Position avant rotation
							
							cpu_pixelX <= pixel_counter1 >> 8;
							cpu_pixelY_start <= screen_h - 1 - pixel_counter1[7:0];
							//cpu_pixelY_start <= 10;
							
							reqNewValue <= 1;
						end
					end
					
					if(reqNewValue && cpu_instrctionNum == cpu_instrctionSync) begin
						
						pixel_counter1 <= (pixel_counter1 + 1);
						if(pixel_counter1[2:0] == 7) reqNewValue <= 0;
						
						//if(cpu_pixelX_start < 224) mem_wren <= 1;// Rotation non géré: on n'affiche que les pixels qui rentrent dans le cadre
						mem_wren <= 1;
							
						mem_inp_pixel <= cpu_mem_rdata[pixel_counter1[2:0]]*3'b111;//!!! Ici le pixel devrait etre lu dans l'ordre inverse
						//mem_x <= cpu_pixelX_start + pixel_counter1[2:0];
						//mem_y <= cpu_pixelY;
						mem_x <= cpu_pixelX;
						mem_y <= cpu_pixelY_start - pixel_counter1[2:0];
						
					end
					
					//On affiche des bords
					/*mem_inp_pixel <= 3'b111;
					mem_x <= pixel_counter1[0]*223;
					mem_y <= pixel_counter1 >> 1;*/
					
				end
				else mem_wren <= 0;
			end
			else reqNewValue <= 0;
			// /SIMULATION
			
		end
		else begin // Mode text	
			if(text_pixel != 0) begin
				r_pixel[23:16] <= 8'd50 * text_pixel[2];
				r_pixel[15:8] <= 8'd50 * text_pixel[1];
				r_pixel[7:0] <= 8'd224 * text_pixel[0];
			end
			else begin
				r_pixel[23:16] <= 8'd184;
				r_pixel[15:8] <= 8'd179;
				r_pixel[7:0] <= 8'd246;
			end
		end
		
	end
end

assign RGBchannel[23:16] = r_pixel[23:16];
assign RGBchannel[15:8] = r_pixel[15:8];
assign RGBchannel[7:0] = r_pixel[7:0];

assign {draw_color,draw_x,draw_y} = game_pixel;

endmodule