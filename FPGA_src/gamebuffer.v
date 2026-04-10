/*
 *
 * GAME MODE
 * ---------
 *
 *
 *
 * ZOOM x 4
 * --------
 *
 * On applique un zoom par 2 pour grossir le texte
 *
 */
module gamebuffer(
	input wire clk,
	
	input wire [7:0] x,
	input wire [7:0] y,
	
	//input wire [5:0] rd_x,
	//input wire [4:0] rd_y,
	
	output wire [2:0] o_pixel,
	
	input wire mem_wren,
	input wire [2:0] inp_pixel
);

//reg [2:0] o_pixel_value;

wire [15:0] mem_addr;
wire [2:0] mem_wdata;
wire [2:0] mem_rdata;



/*video_ram2 memoire(
	.wraddress(mem_addr),
	.rdaddress(mem_rdaddr),
	.clock(clk),
	.data(mem_wdata),
	.wren(mem_wren),
	.q(mem_rdata)
);*/

video_ram1 memoire(
	.address(mem_addr),
	.clock(clk),
	.data(mem_wdata),
	.wren(mem_wren),
	.q(mem_rdata)
);


always @(posedge clk) begin
	//if(x == y) o_pixel_value <= 3'b111;
	//else o_pixel_value <= 3'b000;
	////mem_addr <= x + y << 6;
	//mem_addr <= x + ( y * 64);
	//if(mem_wren) mem_addr <= 0;
	//if(mem_wren) mem_addr <= x;
	/*if(mem_wren) begin
		mem_addr <= 32;
		//mem_wdata <= {5'b0,inp_pixel};
		mem_wdata <= {5'b0,3'b001};
	end
	else begin
		mem_addr <= 8;
		mem_wdata <= {5'b0,3'b010};
	end	*/
	
	/*if(mem_wren) begin
		//mem_addr <= x*y;
		mem_wdata <= {5'b0,inp_pixel};
	end*/
end

//assign o_pixel = o_pixel_value;
assign o_pixel = mem_rdata[2:0];
assign mem_addr = x + (y * 224);
assign mem_wdata = (y < 34)? inp_pixel :  
						(y < 60)? {2'b00,inp_pixel[0]} : 
						(y < 184)? inp_pixel : 
						(y < 240)? {1'b0,inp_pixel[1],1'b0} : 
						(x > 20 && x < 110)? {1'b0,inp_pixel[1],1'b0} : inp_pixel ;

//assign mem_rdaddr = rd_x + (rd_y << 6);

endmodule