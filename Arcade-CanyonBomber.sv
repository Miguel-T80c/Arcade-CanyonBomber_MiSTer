//============================================================================
//  Canyon Bomber port to MiSTer
//  Copyright (c) 2019 Alan Steremberg - alanswx
//
//   
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output [11:0] VIDEO_ARX,
	output [11:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	// Use framebuffer from DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of 16 bytes.
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	
	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign VGA_SCALER= 0;

assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = lamp;
assign {FB_PAL_CLK, FB_FORCE_BLANK, FB_PAL_ADDR, FB_PAL_DOUT, FB_PAL_WR} = '0;

wire [1:0] ar = status[15:14];

assign VIDEO_ARX =  (!ar) ? ( 8'd4) : (ar - 1'd1);
assign VIDEO_ARY =  (!ar) ? ( 8'd3) : 12'd0;


`include "build_id.v"
localparam CONF_STR = {
	"A.CANYON;;",
	"-;",
	"H0OEF,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",  
	"-;",
	//"OCD,Language,English,German,French,Spanish;", // broken?
	"O89,Misses,Three,Four,Five,Six;",
	"OA,Test,Off,On;",
	"-;",
	"R0,Reset;",
	"J1,Fire,Start 1P,Start 2P,Coin;",
	"jn,A,Start,Select,R;",
	"V,v",`BUILD_DATE
};


wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;


wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [7:0] ioctl_data;

wire [15:0] joystick_0, joystick_1;

wire [21:0] gamma_bus;



hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.status_menumask(direct_video),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1)
);




wire m_fire     = joystick_0[4];
wire m_fire_2   = joystick_1[4];



wire m_start1 = joystick_0[5];
wire m_start2 = joystick_1[5];
wire m_coin   = joystick_0[6] | joystick_1[6];



/*
-- Configuration DIP switches, these can be brought out to external switches if desired
-- See Canyon Bomber manual for complete information. Active low (0 = On, 1 = Off)
--    8 	7							Game Cost			(10-1 Coin per player, 11-Two coins per player, 01-Two players per coin, 00-Free Play)
--				6	5					Misses Per Play   (00-Three, 01-Four, 10-Five, 11-Six)
--   					4	3			Not Used
--								2	1	Language				(00-English, 10-French, 01-Spanish, 11-German)
--										
DIP_Sw <= "10100000"; -- Config dip switches


*/

wire [7:0] SW1 = {1'b1,1'b0,status[9:8],1'b0,1'b0,status[13:12]};




wire clk_6;
wire videowht,videoblk,compositesync,lamp,lamp2;
canyon_bomber canyon_bomber(
	.Clk_50_I(CLK_50M),
	.Reset_I(~(RESET | status[0] | buttons[1] | ioctl_download)),
	
	.dn_addr(ioctl_addr[16:0]),
	.dn_data(ioctl_data),
	.dn_wr(ioctl_wr),

	
	.clk_12(clk_12),
	.VideoW_O(videowht),
	.VideoB_O(videoblk),
	.Sync_O(compositesync),
	.Audio1_O(audio1),
	.Audio2_O(audio2),
	.Coin1_I(~(m_coin)),
	.Coin2_I(1'b1),
	.Start1_I(~(m_start1)),
	.Start2_I(~(m_start2)),
	.Fire1_I(~m_fire),
	.Fire2_I(~m_fire_2),
	.Slam_I(1),
	.Test_I(~status[10]),
	.clk_6_O(clk_6),
	.Lamp1_O(lamp),
	.Lamp2_O(lamp2),
	.hs_O(hs),
	.vs_O(vs),
	.hblank_O(hblank),
	.vblank_O(vblank),
	.DIP_Sw(SW1)
);

			
wire [6:0] audio1;
wire [6:0] audio2;
wire [1:0] video;

///////////////////////////////////////////////////
wire clk_48,clk_12;
wire clk_sys,locked;
reg [7:0] vid_mono;

always @(posedge clk_sys) begin
		casex({videowht,videoblk})
			2'b01: vid_mono<=8'b01110000;
			2'b10: vid_mono<=8'b10000110;
			2'b11: vid_mono<=8'b11111111;
			2'b00: vid_mono<=8'b00000000;
		endcase
end

assign r=vid_mono[7:5];
assign g=vid_mono[7:5];
assign b=vid_mono[7:5];

assign AUDIO_L={audio1,1'b0,8'b00000000};
assign AUDIO_R={audio2,1'b0,8'b00000000};
assign AUDIO_S = 0;


wire hblank, vblank;
wire hs, vs;
wire [2:0] r,g,b;

reg ce_pix;
always @(posedge clk_48) begin
        reg [2:0] div;

        div <= div + 1'd1;
        ce_pix <= !div;
end



arcade_video #(298,9) arcade_video
(
        .*,

        .clk_video(clk_48),

	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),        
		  
	.fx(status[5:3])
);


pll pll (
	.refclk ( CLK_50M   ),
	.rst(0),
	.locked 	( locked    ),        // PLL is running stable
	.outclk_0	( clk_48	),        // 48 MHz
	.outclk_1	( clk_12	)        // 12 MHz
	 );

assign clk_sys=clk_12;


endmodule
