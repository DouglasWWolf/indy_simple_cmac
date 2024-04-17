//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 29-Feb-23  DWW     1  Initial creation
//
// 16-Apr-24  DWW     2  sys_reset_out
//===================================================================================================

module cmac_control # (parameter RSFEC = 1, FREQ_HZ = 322265625)
(
    input clk,

    (* X_INTERFACE_INFO = "xilinx.com:*:rs_fec_ports:2.0 rs_fec ctl_rx_rsfec_enable" *)
    output ctl_rx_rsfec_enable,
    
    (* X_INTERFACE_INFO = "xilinx.com:*:rs_fec_ports:2.0 rs_fec ctl_rx_rsfec_enable_correction" *)
    output ctl_rx_rsfec_enable_correction,

    (* X_INTERFACE_INFO = "xilinx.com:*:rs_fec_ports:2.0 rs_fec ctl_rx_rsfec_enable_indication" *)
    output ctl_rx_rsfec_enable_indication,

    (* X_INTERFACE_INFO = "xilinx.com:*:rs_fec_ports:2.0 rs_fec ctl_tx_rsfec_enable" *)
    output ctl_tx_rsfec_enable,

    (* X_INTERFACE_INFO = "xilinx.com:*:ctrl_ports:2.0 ctl_tx ctl_enable" *)
    output ctl_tx_enable, 

    (* X_INTERFACE_INFO = "xilinx.com:*:ctrl_ports:2.0 ctl_tx ctl_tx_send_rfi" *)
    output ctl_tx_send_rfi,

    (* X_INTERFACE_INFO = "xilinx.com:*:ctrl_ports:2.0 ctl_rx ctl_enable" *)
    output ctl_rx_enable,

    // This comes from the stat_rx interface of the CMAC
    input      stat_rx_aligned,

    // This is asserted to drive the reset input of the RX side of the transcievers
    output     sys_reset_out,

    // "axis_rx" from the CMAC connects here
    input[511:0]  rx_in_tdata,
    input[63:0]   rx_in_tkeep,
    input         rx_in_tlast,
    input         rx_in_tuser,
    input         rx_in_tvalid,

    // axis_rx output to the rest of the RTL application connects here
    output[511:0] rx_out_tdata,
    output[63:0]  rx_out_tkeep,
    output        rx_out_tlast,
    output        rx_out_tuser,
    output        rx_out_tvalid
);


//=============================================================================
// The tx_enable and "send remote fault indicator" depend on whether or not
// PCS alignment has been acheived
//=============================================================================
assign ctl_rx_enable   = 1;
assign ctl_tx_enable   = stat_rx_aligned;
assign ctl_tx_send_rfi = ~stat_rx_aligned;
//=============================================================================


//=============================================================================
// Enable or disable forward error correction
//=============================================================================
assign ctl_rx_rsfec_enable            = RSFEC;
assign ctl_rx_rsfec_enable_correction = RSFEC;
assign ctl_rx_rsfec_enable_indication = RSFEC;
assign ctl_tx_rsfec_enable            = RSFEC;
//=============================================================================

// Various timeouts, measured in clock cycles
localparam ALIGNMENT_TIMEOUT = 2 * FREQ_HZ;
localparam RESET_TIMEOUT     = 50;
localparam SILENCE_TIMEOUT   = FREQ_HZ / 1000;

// Countdown timers
reg[31:0] alignment_timer, reset_timer, silence_timer;

//=============================================================================
// AXI-Stream rx_out is driven directly from AXI-Stream rx_in
//=============================================================================
assign rx_out_tdata  = rx_in_tdata;
assign rx_out_tkeep  = rx_in_tkeep;
assign rx_out_tlast  = rx_in_tlast;
assign rx_out_tuser  = rx_in_tuser;
assign rx_out_tvalid = rx_in_tvalid & (silence_timer == 0);
//=============================================================================



// Synchronize "stat_rx_aligned" into "sync_rx_aligned"
wire sync_rx_aligned;
xpm_cdc_single #
(
    .DEST_SYNC_FF  (4),   
    .INIT_SYNC_FF  (0),   
    .SIM_ASSERT_CHK(0), 
    .SRC_INPUT_REG (0)   
)
cdc0
(
    .src_clk (               ),  
    .src_in  (stat_rx_aligned),
    .dest_clk(clk            ), 
    .dest_out(sync_rx_aligned) 
);


// The transceivers are in reset when the timer is non-zero
assign sys_reset_out = (reset_timer != 0);


//=============================================================================
// This state machine waits for alignment to be acheived.  If a timeout
// occurs before that happens, the receive side of the transciever datapath
// gets reset, then we go back to waiting for alignment
//=============================================================================
reg[1:0] fsm_state = 0;
always @(posedge clk) begin

    // Count down while waiting for PCS alignment
    if (alignment_timer)
        alignment_timer <= alignment_timer - 1;

    // Count down while waiting for reset_out to complete
    if (reset_timer)
        reset_timer <= reset_timer - 1;

    // Count down the timer that controls how long rx_out is silent after a reset
    if (silence_timer)
        silence_timer <= silence_timer - 1;

    case (fsm_state)

        // If we're done resetting the CMAC, go wait for PCS alignment
        0:  if (reset_timer == 0) begin
                alignment_timer <= ALIGNMENT_TIMEOUT;
                fsm_state       <= 1;
            end

        // Wait for alignment to occur.  If we don't get PCS alignment
        // before the timeout, reset the CMAC and try again
        1:  if (sync_rx_aligned) begin
                fsm_state     <= 2;
            end else if (alignment_timer == 0) begin
                silence_timer <= SILENCE_TIMEOUT;
                reset_timer   <= RESET_TIMEOUT;
                fsm_state     <= 0;
            end

        // If we lose alignment, reset the CMAC
        2:  if (~sync_rx_aligned) begin
                silence_timer <= SILENCE_TIMEOUT;
                reset_timer   <= RESET_TIMEOUT;
                fsm_state     <= 0;
            end
    endcase
end
//=============================================================================

endmodule