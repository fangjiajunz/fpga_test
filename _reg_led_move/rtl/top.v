module top (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire [3:0] key,
    output reg  [3:0] led,
    output wire [7:0] seg_led,
    output wire [5:0] seg_sel
);

    wire       tick_1s;
    reg  [7:0] _reg_seg_led;
    reg  [5:0] _reg_seg_sel;
    // assign seg_led = _reg_seg_led;
    // assign seg_sel = _reg_seg_sel;

    timer u_timer (
        .sys_clk          (sys_clk),
        .sys_rst_n        (sys_rst_n),
        .led_timer_flag   (tick_1s),
        .button_timer_flag(tick_20ms)
    );

    seg_led seg_led_inst (
        .clk     (sys_clk),
        .rst_n   (sys_rst_n),
        .add_flag(tick_1s),
        .seg_sel (seg_sel),
        .seg_led (seg_led)
    );

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            led <= 4'b0000;
        end else if (tick_1s) begin
            led <= {led[3:1], ~led[0]};
            // _reg_seg_sel <= 6'b111101;
        end
    end



endmodule
