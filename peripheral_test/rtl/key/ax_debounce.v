module ax_debounce (
    input  wire sys_clk,
    input  wire sys_rst_n,
    input  wire btn_in,
    input  wire timer_tick,
    output reg  btn_edge
);

    reg btn_reg_d0;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            btn_reg_d0 <= 1'b1;
            btn_edge   <= 1'b0;
        end else if (timer_tick) begin
            btn_reg_d0 <= btn_in;
            btn_edge   <= (btn_reg_d0 && !btn_in);
        end else begin
            btn_edge <= 1'b0;
        end
    end

endmodule
