/* ****************************************************************************
-- Source file: axi3_mem_model.v
-- Description: AXI3 slave memory model ( 64 bit, INCR bursts ) for the la16
--              DDR store tests. 2^WORD_BITS words starting at BASE.
--              stall_pct ( 0..99, set from cocotb ) randomly holds back
--              awready / wready / arready / rvalid and delays B responses,
--              like a busy DDR controller. Out of range accesses print an
--              error and count in `errors`.
--              W beats are accepted only once their burst address is known.
-- ***************************************************************************/
`timescale 1 ns/ 1 ps
`default_nettype none

module axi3_mem_model
#(
  parameter        WORD_BITS = 12,
  parameter [31:0] BASE      = 32'h0200_0000
)
(
  input  wire         clk,
  input  wire         reset,
  input  wire [31:0]  awaddr,
  input  wire [3:0]   awlen,
  input  wire         awvalid,
  output wire         awready,
  input  wire [63:0]  wdata,
  input  wire [7:0]   wstrb,
  input  wire         wlast,
  input  wire         wvalid,
  output wire         wready,
  output wire [1:0]   bresp,
  output wire [5:0]   bid,
  output reg          bvalid,
  input  wire         bready,
  input  wire [31:0]  araddr,
  input  wire [3:0]   arlen,
  input  wire         arvalid,
  output wire         arready,
  output reg  [63:0]  rdata,
  output wire [1:0]   rresp,
  output wire [5:0]   rid,
  output reg          rlast,
  output reg          rvalid,
  input  wire         rready
);

  reg  [63:0]  mem [0:(1<<WORD_BITS)-1];
  reg  [7:0]   stall_pct = 0;
  integer      errors = 0;
  integer      bursts_w = 0;
  integer      bursts_r = 0;

  assign bresp = 2'b00;
  assign bid   = 6'd0;
  assign rresp = 2'b00;
  assign rid   = 6'd0;

  function go;
    input dummy;
    begin
      go = ( ( $random & 32'h7FFF_FFFF ) % 100 ) >= stall_pct;
    end
  endfunction

  // Random stall decisions, one per clock and channel
  reg  aw_go = 1, w_go = 1, ar_go = 1, r_go = 1, b_go = 1;
  always @ ( posedge clk ) begin
    aw_go <= go( 0 );
    w_go  <= go( 0 );
    ar_go <= go( 0 );
    r_go  <= go( 0 );
    b_go  <= go( 0 );
  end

  // Write: address queue
  reg  [31:0]  aq_addr [0:15];
  reg  [4:0]   aq_len  [0:15];
  reg  [3:0]   aq_wr = 0, aq_rd = 0;
  reg  [4:0]   aq_cnt = 0;
  reg  [4:0]   wbeat = 0;
  reg  [7:0]   bpend = 0;

  assign awready = aw_go && ( aq_cnt < 16 );
  assign wready  = w_go  && ( aq_cnt != 0 );

  wire [31:0]  waddr = aq_addr[ aq_rd ] + { wbeat, 3'b000 };
  wire [31:0]  wword = ( waddr - BASE ) >> 3;
  integer      i;

  always @ ( posedge clk ) begin : proc_w
    if ( awvalid && awready ) begin
      aq_addr[ aq_wr ] <= awaddr;
      aq_len [ aq_wr ] <= awlen + 1;
      aq_wr <= aq_wr + 1;
      if ( awaddr[2:0] != 0 || awaddr < BASE || awaddr[6:3] + awlen > 15 ) begin
        $display( "AXI MODEL ERROR: write burst %h len %0d leaves its 128 byte block",
                  awaddr, awlen + 1 );
        errors = errors + 1;
      end
    end
    if ( wvalid && wready ) begin
      if ( wword >= ( 1 << WORD_BITS ) || waddr < BASE ) begin
        $display( "AXI MODEL ERROR: write out of range %h", waddr );
        errors = errors + 1;
      end else begin
        for ( i = 0; i < 8; i = i + 1 )
          if ( wstrb[i] ) mem[ wword ][ 8*i +: 8 ] <= wdata[ 8*i +: 8 ];
      end
      if ( wlast != ( wbeat == aq_len[ aq_rd ] - 1 ) ) begin
        $display( "AXI MODEL ERROR: wlast at beat %0d of %0d", wbeat, aq_len[ aq_rd ] );
        errors = errors + 1;
      end
      if ( wbeat == aq_len[ aq_rd ] - 1 ) begin
        wbeat <= 0;
        aq_rd <= aq_rd + 1;
        bursts_w = bursts_w + 1;
      end else begin
        wbeat <= wbeat + 1;
      end
    end
    aq_cnt <= aq_cnt + ( awvalid && awready ) -
              ( wvalid && wready && wbeat == aq_len[ aq_rd ] - 1 );
    bpend  <= bpend + ( wvalid && wready && wbeat == aq_len[ aq_rd ] - 1 ) -
              ( bvalid && bready );
    if ( bvalid && bready ) bvalid <= 1'b0;
    else if ( !bvalid && bpend != 0 && b_go ) bvalid <= 1'b1;
    if ( reset ) begin
      aq_wr <= 0; aq_rd <= 0; aq_cnt <= 0; wbeat <= 0; bpend <= 0; bvalid <= 1'b0;
    end
  end
  initial bvalid = 0;

  // Read: one burst at a time
  reg  [31:0]  r_addr;
  reg  [4:0]   r_left = 0;
  reg          r_act = 0;
  assign arready = ar_go && !r_act;

  always @ ( posedge clk ) begin : proc_r
    if ( arvalid && arready ) begin
      r_addr <= araddr;
      r_left <= arlen + 1;
      r_act  <= 1'b1;
      bursts_r = bursts_r + 1;
    end
    if ( rvalid && rready ) begin
      rvalid <= 1'b0;
      if ( rlast ) r_act <= 1'b0;
    end else if ( r_act && !rvalid && r_go && r_left != 0 ) begin
      rdata  <= mem[ ( r_addr - BASE ) >> 3 ];
      rvalid <= 1'b1;
      rlast  <= ( r_left == 1 );
      r_addr <= r_addr + 8;
      r_left <= r_left - 1;
    end
    if ( reset ) begin
      r_act <= 1'b0; rvalid <= 1'b0; r_left <= 0;
    end
  end
  initial rvalid = 0;

endmodule // axi3_mem_model
`default_nettype wire
