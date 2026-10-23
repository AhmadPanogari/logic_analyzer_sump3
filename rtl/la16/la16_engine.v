/* ****************************************************************************
-- Source file: la16_engine.v
-- Description: la16 protocol engine ( docs/PROTOCOL_LA16.md, v1 ).
--
--   Frames, both directions:  0xA5 type len_lo len_hi payload[len] crc8
--   crc8 = polynomial 0x07, init 0, over type, len and payload.
--
--   Host -> device : 0x01 IDENT  0x02 CONFIG ( 32 byte )  0x03 ARM
--                    0x04 ABORT  0x05 STATUS?
--   Device -> host : 0x81 IDENT  0x82 ACK  0x83 STATUS  0x84 DATA
--                    0x85 TRIGGER  0x86 END  0x8F ERROR
--
--   Capture is done by la16_capture ( BRAM, or PS DDR when USE_DDR = 1 ).
--   After it completes the engine sends
--   STATUS(4), TRIGGER ( only when a trigger condition is set ), DATA frames
--   of up to 256 samples oldest first, END, STATUS(5). STATUS is also sent
--   every 50 ms while capturing and on every state change.
--   Supported in v1: mode 0 ( buffer ), upload format 0 ( raw ) or
--   2 ( auto, sent raw ). Format 1 ( RLE ) and the streaming modes return
--   ERROR 3. END flag bit 0 = DDR write FIFO overflow ( samples lost ).
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module la16_engine
#(
  parameter        W           = 16,          // Sample index bits
  parameter        MAX_SAMPLES = 65536,       // BRAM: 2^W
  parameter        USE_DDR     = 0,
  parameter [31:0] DDR_BASE    = 32'h0200_0000,
  parameter        CLK_HZ      = 100_000_000,
  parameter        BASE_HZ     = 200_000_000  // Two samples per clock
)
(
  input  wire         clk,
  input  wire         reset,
  input  wire [15:0]  s_lo,
  input  wire [15:0]  s_hi,
  input  wire [7:0]   rx_byte,
  input  wire         rx_valid,
  output reg  [7:0]   tx_byte,
  output reg          tx_valid,
  input  wire         tx_ready,
  output wire         armed,                  // Prefill or waiting for trigger
  output wire         busy,                   // Capturing or uploading

  // AXI3 master to the PS DDR ( USE_DDR = 1 )
  output wire [31:0]  m_awaddr,
  output wire [3:0]   m_awlen,
  output wire [2:0]   m_awsize,
  output wire [1:0]   m_awburst,
  output wire [1:0]   m_awlock,
  output wire [3:0]   m_awcache,
  output wire [2:0]   m_awprot,
  output wire [3:0]   m_awqos,
  output wire [5:0]   m_awid,
  output wire         m_awvalid,
  input  wire         m_awready,
  output wire [63:0]  m_wdata,
  output wire [7:0]   m_wstrb,
  output wire         m_wlast,
  output wire [5:0]   m_wid,
  output wire         m_wvalid,
  input  wire         m_wready,
  input  wire [1:0]   m_bresp,
  input  wire [5:0]   m_bid,
  input  wire         m_bvalid,
  output wire         m_bready,
  output wire [31:0]  m_araddr,
  output wire [3:0]   m_arlen,
  output wire [2:0]   m_arsize,
  output wire [1:0]   m_arburst,
  output wire [1:0]   m_arlock,
  output wire [3:0]   m_arcache,
  output wire [2:0]   m_arprot,
  output wire [3:0]   m_arqos,
  output wire [5:0]   m_arid,
  output wire         m_arvalid,
  input  wire         m_arready,
  input  wire [63:0]  m_rdata,
  input  wire [1:0]   m_rresp,
  input  wire [5:0]   m_rid,
  input  wire         m_rlast,
  input  wire         m_rvalid,
  output wire         m_rready
);

  localparam DW    = W + 1;

  localparam [7:0] T_IDENT   = 8'h01, T_CONFIG = 8'h02, T_ARM    = 8'h03,
                   T_ABORT   = 8'h04, T_STATUS = 8'h05;
  localparam [7:0] R_IDENT   = 8'h81, R_ACK    = 8'h82, R_STATUS = 8'h83,
                   R_DATA    = 8'h84, R_TRIG   = 8'h85, R_END    = 8'h86,
                   R_ERROR   = 8'h8F;
  localparam [7:0] E_CRC     = 8'd1,  E_TYPE   = 8'd2,  E_CONFIG = 8'd3,
                   E_BUSY    = 8'd4;

  localparam [31:0] BASE32 = BASE_HZ;
  localparam [31:0] MAX32  = MAX_SAMPLES;
  localparam        IDENT_LEN = 12 + 5 + 12 + 4;
  localparam [8*IDENT_LEN-1:0] IDENT_P =
    { 8'd1, 8'd16,                                          // version, channels
      BASE32[7:0], BASE32[15:8], BASE32[23:16], BASE32[31:24],
      MAX32[7:0],  MAX32[15:8],  MAX32[23:16],  MAX32[31:24],
      8'h01, 8'h00,                                         // features: edge
      "la16", 8'h00, "AntMiner S9", 8'h00, "0.1", 8'h00 };

  localparam MS_DIV     = CLK_HZ / 1000;
  localparam STATUS_MS  = 50;

  function [7:0] crc8;
    input [7:0] c;
    input [7:0] d;
    integer     i;
    reg   [7:0] x;
    begin
      x = c ^ d;
      for ( i = 0; i < 8; i = i + 1 )
        x = x[7] ? ( { x[6:0], 1'b0 } ^ 8'h07 ) : { x[6:0], 1'b0 };
      crc8 = x;
    end
  endfunction

  function [7:0] le_byte;
    input [31:0] v;
    input [1:0]  i;
    begin
      le_byte = v >> ( 8 * i );
    end
  endfunction

  // ---------------------------------------------------------------------
  // Frame receiver
  // ---------------------------------------------------------------------
  localparam RS_SYNC = 3'd0, RS_TYPE = 3'd1, RS_LEN0 = 3'd2, RS_LEN1 = 3'd3,
             RS_PAY  = 3'd4, RS_CRC  = 3'd5;

  reg  [2:0]   rs;
  reg  [7:0]   r_type;
  reg  [15:0]  r_len;
  reg  [15:0]  r_idx;
  reg  [7:0]   r_crc;
  reg  [7:0]   r_buf [0:31];
  reg  [23:0]  r_idle;                         // Inter byte timeout
  reg          cmd_ok;
  reg          cmd_bad_crc;

  always @ ( posedge clk ) begin : proc_rx
    cmd_ok      <= 1'b0;
    cmd_bad_crc <= 1'b0;
    if ( rs != RS_SYNC ) r_idle <= r_idle + 1'b1;
    if ( r_idle == CLK_HZ / 100 ) rs <= RS_SYNC; // 10 ms without a byte
    if ( rx_valid ) begin
      r_idle <= 24'd0;
      case ( rs )
        RS_SYNC : if ( rx_byte == 8'hA5 ) rs <= RS_TYPE;
        RS_TYPE : begin
          r_type <= rx_byte;
          r_crc  <= crc8( 8'h00, rx_byte );
          rs     <= RS_LEN0;
        end
        RS_LEN0 : begin
          r_len[7:0] <= rx_byte;
          r_crc      <= crc8( r_crc, rx_byte );
          rs         <= RS_LEN1;
        end
        RS_LEN1 : begin
          r_len[15:8] <= rx_byte;
          r_crc       <= crc8( r_crc, rx_byte );
          r_idx       <= 16'd0;
          if ( { rx_byte, r_len[7:0] } > 16'd1024 ) begin
            rs <= RS_SYNC;                       // Garbage, resync
          end else begin
            rs <= ( { rx_byte, r_len[7:0] } == 16'd0 ) ? RS_CRC : RS_PAY;
          end
        end
        RS_PAY : begin
          if ( r_idx < 16'd32 ) r_buf[ r_idx[4:0] ] <= rx_byte;
          r_crc <= crc8( r_crc, rx_byte );
          r_idx <= r_idx + 1'b1;
          if ( r_idx + 1'b1 == r_len ) rs <= RS_CRC;
        end
        default : begin
          if ( rx_byte == r_crc ) cmd_ok      <= 1'b1;
          else                    cmd_bad_crc <= 1'b1;
          rs <= RS_SYNC;
        end
      endcase
    end
    if ( reset ) begin
      rs     <= RS_SYNC;
      r_idle <= 24'd0;
    end
  end // proc_rx

  // CONFIG fields ( little endian )
  wire [7:0]   c_mode   = r_buf[0];
  wire [7:0]   c_format = r_buf[1];
  wire [31:0]  c_div    = { r_buf[7],  r_buf[6],  r_buf[5],  r_buf[4]  };
  wire [31:0]  c_total  = { r_buf[11], r_buf[10], r_buf[9],  r_buf[8]  };
  wire [31:0]  c_pre    = { r_buf[15], r_buf[14], r_buf[13], r_buf[12] };
  wire [15:0]  c_tlm    = { r_buf[17], r_buf[16] };
  wire [15:0]  c_tlv    = { r_buf[19], r_buf[18] };
  wire [15:0]  c_trm    = { r_buf[21], r_buf[20] };
  wire [15:0]  c_tfm    = { r_buf[23], r_buf[22] };
  wire [31:0]  c_tmo    = { r_buf[27], r_buf[26], r_buf[25], r_buf[24] };
  wire         c_valid  = ( r_len == 16'd32 ) && ( c_mode == 8'd0 ) &&
                          ( c_format == 8'd0 || c_format == 8'd2 ) &&
                          ( c_total != 32'd0 ) && ( c_total <= MAX_SAMPLES ) &&
                          ( c_pre < c_total );

  // ---------------------------------------------------------------------
  // Configuration and capture
  // ---------------------------------------------------------------------
  // Engine state ( STATUS codes ): 0 idle, 1..3 capture, 4 upload, 5 done
  localparam ES_IDLE = 3'd0, ES_CAP = 3'd1, ES_UPLOAD = 3'd4, ES_DONE = 3'd5;
  reg  [2:0]     es;

  reg  [31:0]    cfg_div;
  reg  [DW-1:0]  cfg_total;
  reg  [DW-1:0]  cfg_pre;
  reg  [15:0]    cfg_tlm, cfg_tlv, cfg_trm, cfg_tfm;
  reg  [31:0]    cfg_tmo;
  reg            cfg_ok;
  reg            cap_arm;
  reg            cap_abort;
  wire [2:0]     cap_state;
  wire [DW-1:0]  cap_count;
  wire           cap_done;
  wire           cap_ready;
  wire           cap_ovf;
  wire [W-1:0]   rd_idx;
  wire [15:0]    rd_data;
  wire           rd_ready;
  wire           has_trig = ( cfg_tlm | cfg_trm | cfg_tfm ) != 16'd0;

  la16_capture #( .W ( W ), .USE_DDR ( USE_DDR ), .DDR_BASE ( DDR_BASE ) ) u_capture
  (
    .clk       ( clk       ),
    .reset     ( reset     ),
    .s_lo      ( s_lo      ),
    .s_hi      ( s_hi      ),
    .divider   ( cfg_div   ),
    .total     ( cfg_total ),
    .pre       ( cfg_pre   ),
    .tl_mask   ( cfg_tlm   ),
    .tl_value  ( cfg_tlv   ),
    .tr_mask   ( cfg_trm   ),
    .tf_mask   ( cfg_tfm   ),
    .arm       ( cap_arm   ),
    .abort     ( cap_abort ),
    .state     ( cap_state ),
    .captured  ( cap_count ),
    .done      ( cap_done  ),
    .ready     ( cap_ready ),
    .overflow  ( cap_ovf   ),
    .rd_en     ( es == ES_UPLOAD ),
    .rd_idx    ( rd_idx    ),
    .rd_data   ( rd_data   ),
    .rd_ready  ( rd_ready  ),
    .m_awaddr  ( m_awaddr  ), .m_awlen   ( m_awlen   ), .m_awsize  ( m_awsize  ),
    .m_awburst ( m_awburst ), .m_awlock  ( m_awlock  ), .m_awcache ( m_awcache ),
    .m_awprot  ( m_awprot  ), .m_awqos   ( m_awqos   ), .m_awid    ( m_awid    ),
    .m_awvalid ( m_awvalid ), .m_awready ( m_awready ), .m_wdata   ( m_wdata   ),
    .m_wstrb   ( m_wstrb   ), .m_wlast   ( m_wlast   ), .m_wid     ( m_wid     ),
    .m_wvalid  ( m_wvalid  ), .m_wready  ( m_wready  ), .m_bresp   ( m_bresp   ),
    .m_bid     ( m_bid     ), .m_bvalid  ( m_bvalid  ), .m_bready  ( m_bready  ),
    .m_araddr  ( m_araddr  ), .m_arlen   ( m_arlen   ), .m_arsize  ( m_arsize  ),
    .m_arburst ( m_arburst ), .m_arlock  ( m_arlock  ), .m_arcache ( m_arcache ),
    .m_arprot  ( m_arprot  ), .m_arqos   ( m_arqos   ), .m_arid    ( m_arid    ),
    .m_arvalid ( m_arvalid ), .m_arready ( m_arready ), .m_rdata   ( m_rdata   ),
    .m_rresp   ( m_rresp   ), .m_rid     ( m_rid     ), .m_rlast   ( m_rlast   ),
    .m_rvalid  ( m_rvalid  ), .m_rready  ( m_rready  )
  );

  wire [2:0]     status_code = ( es == ES_CAP ) ? cap_state : es;
  reg  [2:0]     last_code;

  // Pending device frames
  reg            p_err;   reg [7:0] p_err_code;
  reg            p_ack;   reg [7:0] p_ack_type;
  reg            p_ident;
  reg            p_status;
  reg            p_trig;
  reg            p_end;   reg [7:0] p_end_flags;
  reg            up_abort;
  reg  [DW-1:0]  up_sent;

  reg  [31:0]    ms_div;
  reg  [31:0]    ms_cnt;                       // ms since ARM
  reg  [31:0]    st_ms;                        // ms since last STATUS
  wire           ms_tick = ( ms_div == MS_DIV - 1 );

  // Frame transmitter interface ( see proc_tx )
  reg            tx_start;
  reg  [7:0]     sel_type;
  reg  [7:0]     f_type;
  wire [DW-1:0]  remain = cfg_total - up_sent;
  wire [DW-1:0]  data_n = ( remain > 256 ) ? 256 : remain;

  always @ ( posedge clk ) begin : proc_ctrl
    cap_arm   <= 1'b0;
    cap_abort <= 1'b0;

    ms_div <= ms_tick ? 32'd0 : ms_div + 1'b1;
    if ( ms_tick ) begin
      ms_cnt <= ms_cnt + 1'b1;
      st_ms  <= st_ms + 1'b1;
    end

    // Capture finished / trigger timeout ( before the commands, so an ABORT
    // in the same clock wins )
    if ( es == ES_CAP && !cap_arm ) begin
      if ( cap_done ) begin
        es      <= ES_UPLOAD;
        p_trig  <= has_trig;
        up_sent <= {DW{1'b0}};
      end else if ( cfg_tmo != 32'd0 && ms_cnt >= cfg_tmo &&
                    ( cap_state == 3'd1 || cap_state == 3'd2 ) ) begin
        cap_abort   <= 1'b1;
        es          <= ES_DONE;
        p_end       <= 1'b1;
        p_end_flags <= 8'h04;
      end
    end

    // Commands
    if ( cmd_bad_crc ) begin
      p_err <= 1'b1; p_err_code <= E_CRC;
    end
    if ( cmd_ok ) begin
      case ( r_type )
        T_IDENT  : p_ident <= 1'b1;
        T_STATUS : p_status <= 1'b1;
        T_CONFIG : begin
          if ( es == ES_CAP || es == ES_UPLOAD ) begin
            p_err <= 1'b1; p_err_code <= E_BUSY;
          end else if ( !c_valid ) begin
            p_err <= 1'b1; p_err_code <= E_CONFIG;
          end else begin
            cfg_div   <= c_div;
            cfg_total <= c_total[DW-1:0];
            cfg_pre   <= c_pre[DW-1:0];
            cfg_tlm   <= c_tlm;
            cfg_tlv   <= c_tlv;
            cfg_trm   <= c_trm;
            cfg_tfm   <= c_tfm;
            cfg_tmo   <= c_tmo;
            cfg_ok    <= 1'b1;
            p_ack <= 1'b1; p_ack_type <= T_CONFIG;
          end
        end
        T_ARM : begin
          if ( es == ES_CAP || es == ES_UPLOAD || !cap_ready ) begin
            p_err <= 1'b1; p_err_code <= E_BUSY;
          end else if ( !cfg_ok ) begin
            p_err <= 1'b1; p_err_code <= E_CONFIG;
          end else begin
            p_ack <= 1'b1; p_ack_type <= T_ARM;
            cap_arm  <= 1'b1;
            es       <= ES_CAP;
            ms_cnt   <= 32'd0;
            up_sent  <= {DW{1'b0}};
            up_abort <= 1'b0;
            p_trig   <= 1'b0;
            p_end    <= 1'b0;
          end
        end
        T_ABORT : begin
          p_ack <= 1'b1; p_ack_type <= T_ABORT;
          if ( es == ES_CAP ) begin
            cap_abort   <= 1'b1;
            es          <= ES_DONE;
            p_end       <= 1'b1;
            p_end_flags <= 8'h02;
          end
          if ( es == ES_UPLOAD ) up_abort <= 1'b1;
        end
        default : begin
          p_err <= 1'b1; p_err_code <= E_TYPE;
        end
      endcase
    end

    // STATUS on state change and every STATUS_MS while capturing
    if ( status_code != last_code ) begin
      last_code <= status_code;
      p_status  <= 1'b1;
      st_ms     <= 32'd0;
    end else if ( es == ES_CAP && st_ms >= STATUS_MS ) begin
      p_status  <= 1'b1;
      st_ms     <= 32'd0;
    end

    // Frame selected by the transmitter one clock ago ( f_type latched it;
    // sel_type may already point at a newer, higher priority frame )
    if ( tx_start ) begin
      case ( f_type )
        R_ERROR  : p_err    <= 1'b0;
        R_ACK    : p_ack    <= 1'b0;
        R_IDENT  : p_ident  <= 1'b0;
        R_STATUS : p_status <= 1'b0;
        R_TRIG   : p_trig   <= 1'b0;
        R_DATA   : up_sent  <= up_sent + data_n;
        R_END    : begin
          p_end <= 1'b0;
          es    <= ES_DONE;
        end
        default  : ;
      endcase
    end
    // END after the upload or an abort during it
    if ( es == ES_UPLOAD && !p_end && !p_trig &&
         ( up_abort || ( up_sent == cfg_total && !tx_start ) ) ) begin
      p_end       <= 1'b1;
      p_end_flags <= { 6'd0, up_abort, cap_ovf };
    end

    if ( reset ) begin
      es        <= ES_IDLE;
      last_code <= 3'd0;
      cfg_ok    <= 1'b0;
      cfg_div   <= 32'd0;
      cfg_total <= {DW{1'b0}};
      cfg_pre   <= {DW{1'b0}};
      cfg_tlm   <= 16'd0;
      cfg_tlv   <= 16'd0;
      cfg_trm   <= 16'd0;
      cfg_tfm   <= 16'd0;
      cfg_tmo   <= 32'd0;
      p_err_code  <= 8'd0;
      p_ack_type  <= 8'd0;
      p_end_flags <= 8'd0;
      p_err     <= 1'b0;
      p_ack     <= 1'b0;
      p_ident   <= 1'b0;
      p_status  <= 1'b0;
      p_trig    <= 1'b0;
      p_end     <= 1'b0;
      up_abort  <= 1'b0;
      up_sent   <= {DW{1'b0}};
      ms_div    <= 32'd0;
      ms_cnt    <= 32'd0;
      st_ms     <= 32'd0;
    end
  end // proc_ctrl

  // ---------------------------------------------------------------------
  // Frame transmitter
  // ---------------------------------------------------------------------
  localparam TS_IDLE = 2'd0, TS_PREP = 2'd1, TS_SEND = 2'd2;

  reg  [1:0]     ts;
  reg  [15:0]    f_len;
  reg  [15:0]    bidx;
  reg  [7:0]     t_crc;
  reg  [2:0]     prep;
  reg  [7:0]     f_ack_type, f_err_code, f_end_flags, f_code;
  reg  [31:0]    f_a, f_b;                     // u32 payload fields
  reg  [DW-1:0]  f_base;
  wire           upload_item = ( es == ES_UPLOAD && !up_abort &&
                                 !p_trig && up_sent != cfg_total );

  // Next frame, highest priority first
  always @ ( * ) begin : proc_sel
    if      ( p_err    ) sel_type = R_ERROR;
    else if ( p_ack    ) sel_type = R_ACK;
    else if ( p_ident  ) sel_type = R_IDENT;
    else if ( p_status ) sel_type = R_STATUS;
    else if ( p_trig   ) sel_type = R_TRIG;
    else if ( upload_item ) sel_type = R_DATA;
    else if ( p_end    ) sel_type = R_END;
    else                 sel_type = 8'h00;
  end // proc_sel

  wire [15:0]    k = bidx - 16'd4;             // Payload byte index
  wire [15:0]    s_k = k - 16'd4;              // DATA: byte index in samples
  assign rd_idx = f_base + s_k[15:1];

  reg  [7:0]     payload;
  always @ ( * ) begin : proc_payload
    payload = 8'h00;
    case ( f_type )
      R_IDENT  : payload = IDENT_P >> ( 8 * ( IDENT_LEN - 1 - k ) );
      R_ACK    : payload = f_ack_type;
      R_ERROR  : payload = f_err_code;
      R_STATUS : payload = ( k == 0 ) ? { 5'd0, f_code[2:0] } :
                           ( k <  5 ) ? le_byte( f_a, k - 1 ) :
                                        le_byte( f_b, k - 5 );
      R_TRIG   : payload = le_byte( f_a, k[1:0] );
      R_END    : payload = ( k < 4 ) ? le_byte( f_a, k[1:0] ) : f_end_flags;
      R_DATA   : payload = ( k < 4 ) ? le_byte( f_a, k[1:0] ) :
                           ( s_k[0] ? rd_data[15:8] : rd_data[7:0] );
      default  : ;
    endcase
  end // proc_payload

  always @ ( posedge clk ) begin : proc_tx
    tx_start <= 1'b0;
    case ( ts )
      TS_IDLE : begin
        tx_valid <= 1'b0;
        if ( sel_type != 8'h00 && !tx_start ) begin
          tx_start    <= 1'b1;
          f_type      <= sel_type;
          f_ack_type  <= p_ack_type;
          f_err_code  <= p_err_code;
          f_end_flags <= p_end_flags;
          f_code      <= status_code;
          f_base      <= up_sent;
          case ( sel_type )
            R_IDENT  : f_len <= IDENT_LEN;
            R_ACK    : f_len <= 16'd1;
            R_ERROR  : f_len <= 16'd1;
            R_STATUS : begin
              f_len <= 16'd9;
              f_a   <= cap_count;
              f_b   <= cfg_total;
            end
            R_TRIG   : begin
              f_len <= 16'd4;
              f_a   <= cfg_pre;
            end
            R_END    : begin
              f_len <= 16'd5;
              f_a   <= up_sent;
            end
            default  : begin                    // R_DATA
              f_len <= 16'd4 + { data_n, 1'b0 };
              f_a   <= up_sent;
            end
          endcase
          bidx  <= 16'd0;
          t_crc <= 8'h00;
          prep  <= 3'd0;
          ts    <= TS_PREP;
        end
      end
      TS_PREP : begin                           // Wait for the sample read
        if ( prep != 3'd4 ) prep <= prep + 1'b1;
        if ( prep == 3'd4 && ( rd_ready || f_type != R_DATA || bidx < 16'd8 ||
                               bidx == f_len + 16'd4 ) ) begin
          tx_byte  <= ( bidx == 16'd0 ) ? 8'hA5 :
                      ( bidx == 16'd1 ) ? f_type :
                      ( bidx == 16'd2 ) ? f_len[7:0] :
                      ( bidx == 16'd3 ) ? f_len[15:8] :
                      ( bidx == f_len + 16'd4 ) ? t_crc : payload;
          tx_valid <= 1'b1;
          ts       <= TS_SEND;
        end
      end
      default : begin                           // TS_SEND
        if ( tx_ready ) begin
          tx_valid <= 1'b0;
          if ( bidx != 16'd0 ) t_crc <= crc8( t_crc, tx_byte );
          bidx <= bidx + 1'b1;
          prep <= 3'd0;
          ts   <= ( bidx == f_len + 16'd4 ) ? TS_IDLE : TS_PREP;
        end
      end
    endcase
    if ( reset ) begin
      ts       <= TS_IDLE;
      tx_valid <= 1'b0;
    end
  end // proc_tx

  assign armed = ( es == ES_CAP ) && ( cap_state == 3'd1 || cap_state == 3'd2 );
  assign busy  = ( es == ES_CAP ) || ( es == ES_UPLOAD );

endmodule // la16_engine
`default_nettype wire
