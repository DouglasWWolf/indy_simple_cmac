module data_generator # (parameter DW=512)
(
    input clk, start,

    output [DW-1:0]     AXIS_OUT_TDATA,
    output [(DW/8)-1:0] AXIS_OUT_TKEEP,
    output              AXIS_OUT_TLAST,
    output              AXIS_OUT_TVALID,
    input               AXIS_OUT_TREADY
);


reg fsm_state;
reg[63:0] data;

assign AXIS_OUT_TDATA  = data;
assign AXIS_OUT_TKEEP  = -1;
assign AXIS_OUT_TLAST  = (data[3:0] == 4'b1111);
assign AXIS_OUT_TVALID = (fsm_state == 1);


always @(posedge clk) begin
    case (fsm_state)
        0:  if (start) begin
                data      <= 0;
                fsm_state <= 1;
            end
        
        1:  if (AXIS_OUT_TVALID & AXIS_OUT_TREADY) begin
                data <= data + 1;
            end

    endcase
end




endmodule
