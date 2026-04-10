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
	i2s, // Serial data for I2S interface,
	clk, // Master clock for the audio interface
	audio_on, // Start/Stop playing sound
	audio_sample,
	audio_channels,
	audio_sample_avail
);

/*****************************************************************************
 *                             Port Declarations                             *
 *****************************************************************************/
output mclk;
output sclk;
output lrclk;
input reset_n;
output [3:0] i2s;
input clk;
input audio_on;
input [31:0] audio_sample;
input [2:0] audio_channels;
input audio_sample_avail;

parameter DATA_WIDTH = 16;
//parameter SIN_SAMPLE_DATA = 259463;
parameter MCLK_DIVISEUR = 3;
parameter RATE_SPEED = 1;//5 si 8KHz / 1 si 44.1KHz

/*****************************************************************************
 *                 Internal wires and registers Declarations                 *
 *****************************************************************************/
reg lrclk;
reg sclk;
reg [5:0] sclk_Count;// Utile pour switcher entre les channels L et R
reg [3:0] mclk_Count;// Compteur pour diviser le signal sclk
reg [15:0] Data_Bit;// Va contenir les données à envoyer
reg [15:0] Data_Bit2;// Va contenir les données à envoyer
//wire [15:0] o_dataBit;// Sortie de la rom 16 bits
reg [6:0] Data_Count;// Pointeur vers le bit à envoyer
//reg [18:0] SIN_Count;// Adresse de la donnée à envoyer
//reg [17:0] SIN_Address;// Adresse de la donnée à envoyer
reg lr_state;

reg [3:0] i2s;// Sortie i2s
reg [2:0] speed_Count;//Permet de ralentir la vitesse de lecteur pour gérer les 8KHz ou 48KHz

/*****************************************************************************
 *                             Sequential logic                              *
 *****************************************************************************/
initial begin
	mclk_Count <= 0;
	lr_state <= 0;
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
	end
	else if(sclk_Count >= DATA_WIDTH - 1)
	begin
		sclk_Count <= 0;
		lrclk <= ~lrclk;
	end
	else sclk_Count <= sclk_Count + 1;
end

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
		if(lrclk == 0) begin
			i2s[0] <= Data_Bit[~Data_Count];
			i2s[1] <= Data_Bit[~Data_Count];
			i2s[2] <= Data_Bit[~Data_Count];
			i2s[3] <= Data_Bit[~Data_Count];
		end
		else begin
			i2s[0] <= Data_Bit2[~Data_Count];
			i2s[1] <= Data_Bit2[~Data_Count];
			i2s[2] <= Data_Bit2[~Data_Count];
			i2s[3] <= Data_Bit2[~Data_Count];
		end
	end
end

/*always @(negedge lrclk or negedge reset_n or negedge audio_on)
begin
	if (!reset_n || !audio_on)
	begin
		SIN_Count <= 0;
	end
	else begin
		if(speed_Count >= (RATE_SPEED - 1)) begin
			speed_Count <= 0;
			
			if(SIN_Count < SIN_SAMPLE_DATA - 1) SIN_Count <= SIN_Count + 1;
		end
		else speed_Count <= speed_Count + 1;
		
		//SIN_Address <= SIN_Count >> 2;
	end
end*/



/*****************************************************************************
 *                            Combinational logic                            *
 *****************************************************************************/
////always@(o_dataBit)
always@(audio_sample)
begin
	Data_Bit <= audio_sample[15:0];//Pour 16 Bits
	
	if(audio_channels == 2) Data_Bit2 <= audio_sample[31:16];//Pour 16 Bits
	else Data_Bit2 <= audio_sample[15:0];//Pour 16 Bits
	
	
end
 
endmodule