/* ****************************************************************************
-- Source file: ols_engine.v
-- Description: Logic analyzer capture engine speaking the SUMP / Openbench
--              Logic Sniffer ( OLS ) serial protocol, so PulseView / sigrok
--              ( driver "Openbench Logic Sniffer & SUMP compatibles" ) can
--              control it directly. Written from the public SUMP/OLS protocol
--              description; no third party HDL is used.
--
--   Capture : 16 channels, raw samples into a 2^DEPTH_BITS x 16 ring buffer.
--             Sample clock = clk / ( divider + 1 ), clk must be 100 MHz to
--             match the OLS reference clock assumed by the host.
--   Trigger : 4 SUMP basic trigger stages ( mask / value / level / start ).
--             Pre-trigger samples are collected before the trigger is armed.
--   Readback: newest sample first ( as the protocol requires ), one byte per
--             enabled channel group, little endian.
--
--   Commands ( short = 1 byte, long = 1 byte + 4 data bytes LSB first ):
--     0x00 reset           0x01 arm           0x02 ID ( "1ALS" )
--     0x04 metadata        0x05 finish now ( force trigger )
--     0x80 divider[23:0]   0x81 read[15:0]-1 / delay[31:16]-1 ( x4 samples )
--     0x82 flags           0x83 delay-1 ( 32b, x4 )  0x84 read-1 ( 32b, x4 )
--     0xC0+4*s mask        0xC1+4*s value     0xC2+4*s config ( stage s )
--   Flags used : [5:2] channel group disable, [8] RLE ( not supported, the
--                top bit of each sample is cleared so the host never sees a
--                false RLE count ), [11] internal test pattern.
-- Language:    Verilog-2001
-- ***************************************************************************/
`timescale 1 ns/ 100 ps
`default_nettype none

module ols_engine
#(
  parameter DEPTH_BITS = 16                // 65536 samples x 16 channels
)
(
  input  wire         clk,
  input  wire         reset,
  input  wire [15:0]  samples,             // Synchronized probe inputs
  input  wire [7:0]   rx_byte,
  input  wire         rx_valid,
  output reg  [7:0]   tx_byte,
  output reg          tx_valid,
  input  wire         tx_ready,
  output wire         test_mode,           // Host selected internal pattern
  output wire         armed,               // Waiting for trigger
  output wire         capturing            // Armed or post trigger
);

  localparam DEPTH = ( 1 << DEPTH_BITS );

  // ---------------------------------------------------------------------
  // Metadata ( OLS tokens ). Integers are sent MSB first.
  // ---------------------------------------------------------------------
  localparam [8*14-1:0] DEV_NAME = "AntMiner S9 LA";
  localparam [8*3-1:0]  FW_VER   = "1.0";
  localparam [31:0]     MEM_BYTES = 2 * DEPTH;
  // name token ( 1+14+1 ) + version token ( 1+3+1 ) + 4 integer tokens + end
  localparam            META_LEN = 16 + 5 + 4*5 + 1;
  localparam [8*META_LEN-1:0] META =
    { 8'h01, DEV_NAME, 8'h00,                 // Device name
      8'h02, FW_VER,   8'h00,                 // FPGA version
      8'h20, 32'd16,                          // Number of probes
      8'h21, MEM_BYTES,                       // Sample memory ( bytes )
      8'h23, 32'd100_000_000,                 // Max sample rate ( Hz )
      8'h24, 32'd2,                           // Protocol version
      8'h00 };                                // End
  localparam [8*4-1:0]  ID_STR   = "1ALS";

  // ---------------------------------------------------------------------
  // Configuration registers
  // ---------------------------------------------------------------------
  reg  [23:0]  divider;
  reg  [33:0]  read_cnt;                    // Samples to send back
  reg  [33:0]  delay_cnt;                   // Samples from trigger to end
  reg  [15:0]  flags;
  reg  [15:0]  trig_mask  [0:3];
  reg  [15:0]  trig_value [0:3];
  reg  [1:0]   trig_level [0:3];
  reg  [3:0]   trig_start;
  reg  [3:0]   trig_en;

  assign test_mode = flags[11];

  // ---------------------------------------------------------------------
  // Command parser
  // ---------------------------------------------------------------------
  reg  [7:0]   opcode;
  reg  [2:0]   byte_idx;
  reg  [23:0]  arg_lo;
  wire [31:0]  arg = { rx_byte, arg_lo };   // Valid on the 4th data byte
  reg          cmd_reset;
  reg          cmd_arm;
  reg          cmd_id;
  reg          cmd_meta;
  reg          cmd_finish;
  integer      s;

  always @ ( posedge clk ) begin : proc_cmd
    cmd_reset  <= 0;
    cmd_arm    <= 0;
    cmd_id     <= 0;
    cmd_meta   <= 0;
    cmd_finish <= 0;
    if ( rx_valid == 1 ) begin
      if ( byte_idx == 3'd0 ) begin
        if ( rx_byte[7] == 0 ) begin
          case ( rx_byte )
            8'h00   : cmd_reset  <= 1;
            8'h01   : cmd_arm    <= 1;
            8'h02   : cmd_id     <= 1;
            8'h04   : cmd_meta   <= 1;
            8'h05   : cmd_finish <= 1;
            default : ;                       // XON/XOFF etc. ignored
          endcase
        end else begin
          opcode   <= rx_byte;
          byte_idx <= 3'd1;
        end
      end else begin
        case ( byte_idx )
          3'd1    : arg_lo[7:0]   <= rx_byte;
          3'd2    : arg_lo[15:8]  <= rx_byte;
          3'd3    : arg_lo[23:16] <= rx_byte;
          default : ;
        endcase
        byte_idx <= byte_idx + 1;
        if ( byte_idx == 3'd4 ) begin
          byte_idx <= 3'd0;
          case ( opcode )
            8'h80 : divider <= arg[23:0];
            8'h81 : begin
                      read_cnt  <= { 16'd0, arg[15:0]  , 2'b00 } + 34'd4;
                      delay_cnt <= { 16'd0, arg[31:16] , 2'b00 } + 34'd4;
                    end
            8'h82 : flags     <= arg[15:0];
            8'h83 : delay_cnt <= { arg, 2'b00 } + 34'd4;
            8'h84 : read_cnt  <= { arg, 2'b00 } + 34'd4;
            default : begin
              if ( opcode[7:4] == 4'hC ) begin
                case ( opcode[1:0] )
                  2'd0 : trig_mask [ opcode[3:2] ] <= arg[15:0];
                  2'd1 : trig_value[ opcode[3:2] ] <= arg[15:0];
                  2'd2 : begin
                           trig_level[ opcode[3:2] ] <= arg[17:16];
                           trig_start[ opcode[3:2] ] <= arg[27];
                           trig_en   [ opcode[3:2] ] <= 1;
                         end
                  default : ;
                endcase
              end
            end
          endcase
        end
      end
    end
    // A reset clears the trigger stages so stale stages can not fire
    if ( cmd_reset == 1 ) begin
      trig_en    <= 4'd0;
      trig_start <= 4'd0;
      for ( s = 0; s < 4; s = s + 1 ) begin
        trig_mask[s]  <= 16'd0;
        trig_value[s] <= 16'd0;
        trig_level[s] <= 2'd0;
      end
    end
    if ( reset == 1 ) begin
      byte_idx   <= 3'd0;
      divider    <= 24'd0;
      read_cnt   <= 34'd4096;
      delay_cnt  <= 34'd4096;
      flags      <= 16'd0;
      trig_en    <= 4'd0;
      trig_start <= 4'd0;
      for ( s = 0; s < 4; s = s + 1 ) begin
        trig_mask[s]  <= 16'd0;
        trig_value[s] <= 16'd0;
        trig_level[s] <= 2'd0;
      end
    end
  end // proc_cmd


  // ---------------------------------------------------------------------
  // Sample memory ( inferred block RAM, 1 cycle read latency )
  // ---------------------------------------------------------------------
  reg  [15:0]            mem [0:DEPTH-1];
  reg  [DEPTH_BITS-1:0]  wr_addr;
  reg  [DEPTH_BITS-1:0]  rd_addr;
  reg  [15:0]            rd_data;
  reg                    wr_en;
  reg  [15:0]            wr_data;

  always @ ( posedge clk ) begin : proc_mem
    if ( wr_en == 1 ) begin
      mem[ wr_addr ] <= wr_data;
    end
    rd_data <= mem[ rd_addr ];
  end // proc_mem


  // ---------------------------------------------------------------------
  // Capture and readback state machine
  // ---------------------------------------------------------------------
  localparam ST_IDLE    = 3'd0,
             ST_ARMED   = 3'd1,   // Collect pre-trigger, wait for trigger
             ST_POST    = 3'd2,   // Capture after the trigger
             ST_FETCH   = 3'd3,   // Readback: memory read
             ST_WAIT    = 3'd4,   // Readback: read latency
             ST_SEND    = 3'd5,   // Readback: send group bytes
             ST_STR     = 3'd6;   // Sending ID or metadata

  reg  [2:0]             state;
  reg  [23:0]            div_cnt;
  reg                    tick;
  reg  [DEPTH_BITS:0]    read_len;
  reg  [DEPTH_BITS:0]    delay_len;
  reg  [DEPTH_BITS:0]    pre_cnt;      // Samples still needed before trigger
  reg  [DEPTH_BITS:0]    post_cnt;
  reg  [DEPTH_BITS:0]    send_cnt;
  reg  [1:0]             cur_level;
  reg  [1:0]             grp;
  reg  [15:0]            send_sample;
  reg  [7:0]             str_idx;
  reg  [7:0]             str_len;
  reg                    str_is_meta;
  reg                    force_trig;

  wire [3:0]  grp_en      = ~flags[5:2] | { 3'b000, ( flags[5:2] == 4'hF ) };
  wire [33:0] depth_34    = DEPTH;

  // Trigger stage evaluation on the current sample
  reg  [3:0]  stage_hit;
  integer     t;
  always @ ( * ) begin : proc_trig
    for ( t = 0; t < 4; t = t + 1 ) begin
      stage_hit[t] = trig_en[t] && ( trig_level[t] == cur_level ) &&
                     ( ( ( samples ^ trig_value[t] ) & trig_mask[t] ) == 16'd0 );
    end
  end // proc_trig
  wire trig_fire  = |( stage_hit & trig_start ) | force_trig;
  wire trig_level_up = |( stage_hit & ~trig_start );

  // Highest enabled group, its byte carries the RLE flag bit on the host
  wire [1:0] top_grp = grp_en[3] ? 2'd3 : grp_en[2] ? 2'd2 :
                       grp_en[1] ? 2'd1 : 2'd0;

  // Next enabled group after grp ( 3'd4 = none )
  reg  [2:0] next_grp;
  always @ ( * ) begin : proc_next_grp
    next_grp = 3'd4;
    if      ( grp < 2'd1 && grp_en[1] ) next_grp = 3'd1;
    else if ( grp < 2'd2 && grp_en[2] ) next_grp = 3'd2;
    else if ( grp < 2'd3 && grp_en[3] ) next_grp = 3'd3;
  end // proc_next_grp

  wire [2:0] first_grp = grp_en[0] ? 3'd0 : grp_en[1] ? 3'd1 :
                         grp_en[2] ? 3'd2 : 3'd3;

  reg  [7:0] grp_byte;
  always @ ( * ) begin : proc_grp_byte
    case ( grp )
      2'd0    : grp_byte = send_sample[7:0];
      2'd1    : grp_byte = send_sample[15:8];
      default : grp_byte = 8'h00;              // Only 16 channels exist
    endcase
    if ( flags[8] == 1 && grp == top_grp ) begin
      grp_byte[7] = 1'b0;                      // Never look like an RLE count
    end
  end // proc_grp_byte

  assign armed     = ( state == ST_ARMED );
  assign capturing = ( state == ST_ARMED ) || ( state == ST_POST );

  always @ ( posedge clk ) begin : proc_fsm
    wr_en    <= 0;
    tick     <= 0;

    // Sample clock enable: clk / ( divider + 1 )
    if ( div_cnt == 24'd0 ) begin
      div_cnt <= divider;
      tick    <= 1;
    end else begin
      div_cnt <= div_cnt - 1;
    end

    if ( tx_valid == 1 && tx_ready == 1 ) begin
      tx_valid <= 0;
    end

    case ( state )
      ST_IDLE : begin
        force_trig <= 0;
        if ( cmd_arm == 1 ) begin
          // Clamp the requested sizes to the memory
          if ( read_cnt > depth_34 ) begin
            read_len <= DEPTH;
          end else begin
            read_len <= read_cnt[DEPTH_BITS:0];
          end
          if ( delay_cnt > read_cnt || delay_cnt > depth_34 ) begin
            delay_len <= ( read_cnt > depth_34 ) ? DEPTH : read_cnt[DEPTH_BITS:0];
          end else begin
            delay_len <= delay_cnt[DEPTH_BITS:0];
          end
          cur_level <= 2'd0;
          div_cnt   <= 24'd0;
          state     <= ST_ARMED;
          pre_cnt   <= {(DEPTH_BITS+1){1'b1}};  // Set on the first tick below
        end else if ( cmd_id == 1 ) begin
          str_is_meta <= 0;
          str_idx     <= 8'd0;
          str_len     <= 8'd4;
          state       <= ST_STR;
        end else if ( cmd_meta == 1 ) begin
          str_is_meta <= 1;
          str_idx     <= 8'd0;
          str_len     <= META_LEN;
          state       <= ST_STR;
        end
      end

      ST_ARMED : begin
        if ( pre_cnt == {(DEPTH_BITS+1){1'b1}} ) begin
          pre_cnt <= read_len - delay_len;     // Pre-trigger samples needed
        end
        if ( cmd_finish == 1 ) begin
          force_trig <= 1;
        end
        if ( tick == 1 && pre_cnt != {(DEPTH_BITS+1){1'b1}} ) begin
          wr_en   <= 1;
          wr_data <= samples;
          wr_addr <= wr_addr + 1;
          if ( pre_cnt != 0 ) begin
            pre_cnt <= pre_cnt - 1;            // Trigger not armed yet
          end else if ( trig_fire == 1 ) begin
            post_cnt <= delay_len - 1;         // Trigger sample counts
            if ( delay_len <= 1 ) begin
              state <= ST_FETCH;
              send_cnt <= read_len;
              rd_addr  <= wr_addr + 1;         // Newest sample
            end else begin
              state <= ST_POST;
            end
          end else if ( trig_level_up == 1 && cur_level != 2'd3 ) begin
            cur_level <= cur_level + 1;
          end
        end
      end

      ST_POST : begin
        if ( tick == 1 ) begin
          wr_en    <= 1;
          wr_data  <= samples;
          wr_addr  <= wr_addr + 1;
          post_cnt <= post_cnt - 1;
          if ( post_cnt == 1 ) begin
            state    <= ST_FETCH;
            send_cnt <= read_len;
            rd_addr  <= wr_addr + 1;           // Newest sample
          end
        end
      end

      ST_FETCH : begin                         // rd_addr presented
        // Wait for the last sample write to land before reading it back
        if ( wr_en == 0 ) begin
          state <= ST_WAIT;
        end
      end

      ST_WAIT : begin                          // rd_data valid next cycle
        state <= ST_SEND;
        grp   <= first_grp[1:0];
        send_sample <= rd_data;
      end

      ST_SEND : begin
        if ( tx_valid == 0 || tx_ready == 1 ) begin
          if ( tx_valid == 0 ) begin
            tx_byte  <= grp_byte;
            tx_valid <= 1;
            if ( next_grp == 3'd4 ) begin
              // Last byte of this sample
              send_cnt <= send_cnt - 1;
              if ( send_cnt == 1 ) begin
                state <= ST_IDLE;
              end else begin
                rd_addr <= rd_addr - 1;        // Older sample
                state   <= ST_FETCH;
              end
            end else begin
              grp <= next_grp[1:0];
            end
          end
        end
      end

      ST_STR : begin
        if ( tx_valid == 0 ) begin
          if ( str_idx == str_len ) begin
            state <= ST_IDLE;
          end else begin
            tx_byte  <= str_is_meta ? META  [ (META_LEN-1-str_idx)*8 +: 8 ]
                                    : ID_STR[ (3-str_idx)*8 +: 8 ];
            tx_valid <= 1;
            str_idx  <= str_idx + 1;
          end
        end
      end

      default : state <= ST_IDLE;
    endcase

    // Reset command aborts anything, including a running readback
    if ( cmd_reset == 1 || reset == 1 ) begin
      state      <= ST_IDLE;
      force_trig <= 0;
    end
    if ( reset == 1 ) begin
      tx_valid <= 0;
      wr_addr  <= {DEPTH_BITS{1'b0}};
      rd_addr  <= {DEPTH_BITS{1'b0}};
      div_cnt  <= 24'd0;
    end
  end // proc_fsm

endmodule // ols_engine
`default_nettype wire
