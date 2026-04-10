// ============================================================================
// Copyright (c) 2012 by Terasic Technologies Inc.
// ============================================================================
//
// Permission:
//
//   Terasic grants permission to use and modify this code for use
//   in synthesis for all Terasic Development Boards and Altera Development 
//   Kits made by Terasic.  Other use of this code, including the selling 
//   ,duplication, or modification of any portion is strictly prohibited.
//
// Disclaimer:
//
//   This VHDL/Verilog or C/C++ source code is intended as a design reference
//   which illustrates how these types of functions can be implemented.
//   It is the user's responsibility to verify their design for
//   consistency and functionality through the use of formal
//   verification methods.  Terasic provides no warranty regarding the use 
//   or functionality of this code.
//
// ============================================================================
//           
//  Terasic Technologies Inc
//  9F., No.176, Sec.2, Gongdao 5th Rd, East Dist, Hsinchu City, 30070. Taiwan
//
//
//
//                     web: http://www.terasic.com/
//                     email: support@terasic.com
//
// ============================================================================

/*

Function: 
	ADV7513 Video and Audio Control 
	
I2C Configuration Requirements:
	Master Mode
	I2S, 16-bits
	
Clock:
	input Clock 1.536MHz (48K*Data_Width*Channel_Num)
	
Revision:
	1.0, 10/06/2014, Init by Nick
	
Compatibility:
	Quartus 14.0.2

*/

module AUDIO_IF(
	reset_n,
	mclk, // Master Clock for the I2S interface
	sclk, // Serial Clock for the I2S interface
	lrclk, // Left/Right Clock (WS) for the I2S interface
	readclk,//Clock to read the samples (need lrclk / 2 for 11.025KHz)
	i2s, // Serial data for I2S interface,
	clk, // Master clock for the audio interface
	audio_on, // Start/Stop playing sound
	audio2_on, // Need mixage with second sample
	audio_sample,
	audio2_sample,
	audio_channels,
	audio_sample_avail,
	led_audio
);

/*****************************************************************************
 *                             Port Declarations                             *
 *****************************************************************************/
output mclk;
output sclk;
output lrclk;
output readclk;
input reset_n;
output [3:0] i2s;
input clk;
input audio_on;
input audio2_on;
input [31:0] audio_sample;
input [31:0] audio2_sample;
input [2:0] audio_channels;
input audio_sample_avail;
output reg led_audio;

reg [7:0] volume = 255;
reg volume_incdec;// 0 => dec / 1 => inc

//parameter DATA_WIDTH = 8;//incompatible
parameter DATA_WIDTH = 16;
//parameter MCLK_DIVISEUR = 3;
parameter MCLK_DIVISEUR = 1;
//parameter MCLK_DIVISEUR = 7;
//parameter RATE_SPEED = 2;//5 si 8KHz / 1 si 44.1KHz / 2 si 22.05KHz

/*****************************************************************************
 *                 Internal wires and registers Declarations                 *
 *****************************************************************************/
reg lrclk;
reg sclk;
wire readclk;
reg [5:0] sclk_Count;// Utile pour switcher entre les channels L et R
reg [3:0] mclk_Count;// Compteur pour diviser le signal sclk
reg [(DATA_WIDTH - 1):0] Data_Bit;// Va contenir les données à envoyer
reg [(DATA_WIDTH - 1):0] Data_Bit2;// Va contenir les données à envoyer
reg [15:0] filtered;//Permet d'améliorer le son

//wire [15:0] o_dataBit;// Sortie de la rom 16 bits
reg [6:0] Data_Count;// Pointeur vers le bit à envoyer
//reg [18:0] SIN_Count;// Adresse de la donnée à envoyer
//reg [17:0] SIN_Address;// Adresse de la donnée à envoyer
reg lr_state;

reg [3:0] i2s;// Sortie i2s
reg [2:0] speed_Count;//Permet de ralentir la vitesse de lecteur pour gérer les horloges différentes de 44.1KHz

/*****************************************************************************
 *                             Sequential logic                              *
 *****************************************************************************/
initial begin
	mclk_Count <= 0;
	lr_state <= 0;
	led_audio <= 0;
	volume <= 255;
end

assign mclk = clk;
//assign sclk = clk;


always @(negedge mclk or negedge reset_n)
begin
	if(!reset_n)
	begin
		sclk <= 0;
		mclk_Count <= 0;
	end
	else begin
		if(mclk_Count >= MCLK_DIVISEUR  )
		begin
			mclk_Count <= 0;
			sclk <= ~sclk;
			
		end
		else mclk_Count <= (mclk_Count + 1);
	end
end


always @(negedge sclk or negedge reset_n)
begin
	if(!reset_n)
	begin
		lrclk <= 0;
		sclk_Count <= 0;
		//filtered <= 0;
		volume <= 255;
		volume_incdec <= 1;
	end
	else if(sclk_Count >= DATA_WIDTH - 1)
	begin
		sclk_Count <= 0;
		lrclk <= ~lrclk;
		//if(lrclk == 1) filtered <= filtered + ((Data_Bit - filtered) >>> 3);
		
		if(lrclk == 1) begin
			if(audio_sample[17]) begin
				volume <= 255;
				volume_incdec <= 0;
			end
			else if(audio_sample[16]) begin
				//volume <= 127;
				volume <= 0;
				volume_incdec <= 1;
			end
			else if(volume_incdec && volume < 255) volume <= volume + 1;
			else if(!volume_incdec && volume > 0) volume <= volume - 1;
		end
	end
	else sclk_Count <= sclk_Count + 1;
end

/*always @(negedge lrclk or negedge reset_n)
begin
	if(!reset_n)
	begin
		filtered <= 0;
	end
	else begin
		filtered <= filtered + ((Data_Bit - filtered) >>> 3);
	end
end*/

//wire [(DATA_WIDTH - 1):0] Data_scaled = ((Data_Bit * volume) >>> 8);
//wire [31:0] Data_scaled32B = ((Data_Bit * volume) >>> 8);
wire [15:0] Data_scaled16B = ((audio_sample[7:0] * volume) >>> 8);
wire [7:0] Data_scaled = Data_scaled16B[7:0];

	

always @(negedge sclk or negedge reset_n)
begin
	if(!reset_n)
	begin
		Data_Count <= 0;
	end
	else if(Data_Count >= DATA_WIDTH - 1)
	begin
		Data_Count <= 0;
		
	end
	else Data_Count <= Data_Count + 1;
end


always @(negedge sclk or negedge reset_n)
begin
	if(!reset_n)
	begin
		i2s <= 0;
	end
	else begin
		if(audio_on || audio2_on) begin
		
			led_audio <= 1;
			if(lrclk == 0) begin
				i2s[0] <= Data_Bit[~Data_Count];
				i2s[1] <= Data_Bit[~Data_Count];
				i2s[2] <= Data_Bit[~Data_Count];
				i2s[3] <= Data_Bit[~Data_Count];
				
				/*i2s[0] <= Data_scaled[~Data_Count];
				i2s[1] <= Data_scaled[~Data_Count];
				i2s[2] <= Data_scaled[~Data_Count];
				i2s[3] <= Data_scaled[~Data_Count];*/
			end
			else begin
				i2s[0] <= Data_Bit2[~Data_Count];
				i2s[1] <= Data_Bit2[~Data_Count];
				i2s[2] <= Data_Bit2[~Data_Count];
				i2s[3] <= Data_Bit2[~Data_Count];
			end
			
			/*if(lrclk == 0) begin
				i2s[0] <= filtered[~Data_Count];
				i2s[1] <= filtered[~Data_Count];
				i2s[2] <= filtered[~Data_Count];
				i2s[3] <= filtered[~Data_Count];
			end
			else begin
				i2s[0] <= filtered[~Data_Count];
				i2s[1] <= filtered[~Data_Count];
				i2s[2] <= filtered[~Data_Count];
				i2s[3] <= filtered[~Data_Count];
			end*/
		end
		else led_audio <= 0;
	end
end

/*always @(negedge lrclk or negedge reset_n )
begin 
	if(!reset_n) begin
		readclk <= 0;
		speed_Count <= 0;
	end
	else begin
		if(speed_Count > 0) begin
			readclk <= ~readclk;//Permet d'avoir le clock lrclk divisée par 4
			speed_Count <= 0;
		end
		else speed_Count <= speed_Count + 1;
	end
end*/

assign readclk = lrclk;

/*****************************************************************************
 *                            Combinational logic                            *
 *****************************************************************************/

wire signed [8:0] audio1_s = {1'b0,audio_sample[7:0]} - 9'd128;
wire signed [8:0] audio2_s = {1'b0,audio2_sample[7:0]} - 9'd128;

wire signed [9:0] sum_audios;
 
//assign sum_audios = audio_sample[7:0] + audio2_sample[7:0];
//assign sum_audios = audio1_s + audio2_s;
assign sum_audios = (audio1_s + audio2_s) >>> 1;
 
////always@(o_dataBit)
//always@(audio_sample,audio2_sample,audio_on,audio2_on)
always@(*)
begin
	
	//Version 16 Bits
	/*Data_Bit <= audio_sample[15:0];//Pour 16 Bits
	
	if(audio_channels == 2) Data_Bit2 <= audio_sample[31:16];//Pour 16 Bits
	else Data_Bit2 <= audio_sample[15:0];//Pour 16 Bits*/
	
	
	//Version 8 Bits
	/*Data_Bit <= (audio_sample[7:0] - 8'd128) <<< 8;
	Data_Bit2 <= (audio_sample[7:0] - 8'd128) <<< 8;*/
	
	//if(audio_on || audio2_on) begin
	//if(audio_on & audio2_on) begin
	if(1) begin
		//Data_Bit =  (((audio_sample[7:0] + audio2_sample[7:0]) >>> 1) - 8'd128) <<< 8;
		//Data_Bit2 = (((audio_sample[7:0] + audio2_sample[7:0]) >>> 1) - 8'd128) <<< 8;
		
		//if(audio_sample[16]) volume = 1;
		//else if(volume < 255) volume = volume + 1;
		
		/*if(sum_audios > 127) begin
			//Data_Bit = (((255 - 8'd128) <<< 8)*volume) >> 8;
			//Data_Bit2 = (((255 - 8'd128) <<< 8)*volume) >> 8;
			Data_Bit = (((255 - 8'd128) <<< 6 )*volume) >> 8;
			Data_Bit2 = (((255 - 8'd128) <<< 6 )*volume) >> 8;
		end
		else if(sum_audios < -128) begin
			//Data_Bit = (((0 - 8'd128) <<< 8)*volume) >> 8;
			//Data_Bit2 = (((0 - 8'd128) <<< 8)*volume) >> 8;
			Data_Bit = (((0 - 8'd128) <<< 6 )*volume) >> 8;
			Data_Bit2 = (((0 - 8'd128) <<< 6 )*volume) >> 8;
		end
		else begin
			//Data_Bit = (((sum_audios[7:0] + 128 - 8'd128) <<< 8)*volume) >> 8;
			//Data_Bit2 = (((sum_audios[7:0] + 128 - 8'd128) <<< 8)*volume) >> 8;
			Data_Bit = (((sum_audios[7:0] + 128 - 8'd128) <<< 6 )*volume) >> 8;
			Data_Bit2 = (((sum_audios[7:0] + 128 - 8'd128) <<< 6 )*volume) >> 8;
		end*/
		
		//if(audio2_sample[16]) volume = 0;
		//else if(volume < 255) volume = volume + 1;
		
		/*if(sum_audios > 127) begin
			Data_Bit = (((255 - 8'd128) <<< 8));
			Data_Bit2 = (((255 - 8'd128) <<< 8));
		end
		else if(sum_audios < -128) begin
			Data_Bit = (((0 - 8'd128) <<< 8));
			Data_Bit2 = (((0 - 8'd128) <<< 8));
		end
		else begin
			Data_Bit = (((sum_audios[7:0] + 128 - 8'd128) <<< 8));
			Data_Bit2 = (((sum_audios[7:0] + 128 - 8'd128) <<< 8));
		end*/
		
		/*if(sum_audios > 127) begin
			Data_Bit = (((255 - 8'd128) <<< 7 ));
			Data_Bit2 = (((255 - 8'd128) <<< 7 ));
		end
		else if(sum_audios < -128) begin
			Data_Bit = (((0 - 8'd128) <<< 7 ));
			Data_Bit2 = (((0 - 8'd128) <<< 7 ));
		end
		else begin
			Data_Bit = (((sum_audios[7:0] + 128  - 8'd128 ) <<< 7 ));
			Data_Bit2 = (((sum_audios[7:0] + 128  - 8'd128 ) <<< 7 ));
		end*/
		
		//Data_Bit = (((sum_audios[7:0] + 128 - 8'd128) <<< 7 ));
		//Data_Bit2 = (((sum_audios[7:0] + 128 - 8'd128) <<< 7 ));
		
		//Data_Bit = (sum_audios[7:0] - 8'd128) <<< 8;
		//Data_Bit2 = (sum_audios[7:0] - 8'd128) <<< 8;
		
		//Data_Bit = ((audio_sample[7:0] + audio2_sample[7:0]) - ((audio_sample[7:0]*audio2_sample[7:0]) >> 8) );
		//Data_Bit2 = ((audio_sample[7:0] + audio2_sample[7:0]) - ((audio_sample[7:0]*audio2_sample[7:0]) >> 8) );
		
		//Data_Bit = (((audio_sample[7:0] + audio2_sample[7:0]) - ((audio_sample[7:0]*audio2_sample[7:0]) >> 8) ) - 8'd128) <<< 8;
		//Data_Bit2 = (((audio_sample[7:0] + audio2_sample[7:0]) - ((audio_sample[7:0]*audio2_sample[7:0]) >> 8) ) - 8'd128) <<< 8;
		
		//Data_Bit = (((audio_sample[7:0] - 8'd128) <<< 7)*volume) >> 8 ;
		//Data_Bit = (((audio_sample[7:0] - 8'd128) <<< 7)*255) >> 8 ;
		//Data_Bit = (audio_sample[7:0] - 8'd128) <<< 7;
		Data_Bit = (Data_scaled[7:0] - 8'd128) <<< 7;
		Data_Bit2 = (audio2_sample[7:0] - 8'd128) <<< 8;

	end
	else if(audio_on) begin
		//Data_Bit = (audio_sample[7:0] - 8'd128) <<< 8;
		//Data_Bit2 = (audio_sample[7:0] - 8'd128) <<< 8;
		////Data_Bit = (audio_sample[7:0] - 8'd128) <<< 7 ;
		////Data_Bit2 = (audio_sample[7:0] - 8'd128) <<< 7 ;
		
		Data_Bit = (((audio_sample[7:0] - 8'd128) <<< 7)*volume) >> 8 ;
		Data_Bit2 = (((audio_sample[7:0] - 8'd128) <<< 7)*volume) >> 8 ;
		//Data_Bit = (((audio_sample[7:0] - 8'd128) <<< 7)*255) >> 8 ;
		//Data_Bit2 = (((audio_sample[7:0] - 8'd128) <<< 7)*255) >> 8 ;
		//Data_Bit = audio_sample[7:0];
		//Data_Bit2 = audio_sample[7:0];
	end
	else begin
		//Data_Bit = (audio2_sample[7:0] - 8'd128) <<< 8;
		//Data_Bit2 = (audio2_sample[7:0] - 8'd128) <<< 8;
		Data_Bit = (audio2_sample[7:0] - 8'd128) <<< 8;
		Data_Bit2 = (audio2_sample[7:0] - 8'd128) <<< 8;
		//Data_Bit = audio2_sample[7:0] ;
		//Data_Bit2 = audio2_sample[7:0];
	end
	/*if(audio_channels == 2) Data_Bit2 <= audio_sample[15:8] << 8;
	else Data_Bit2 <= audio_sample[7:0] * audio_sample[7:0];*/
	
	
end
 
endmodule