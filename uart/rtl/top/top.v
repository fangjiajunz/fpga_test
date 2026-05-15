module top (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire [3:0] key,
    output wire [3:0] led,
    output wire [7:0] seg_led,
    output wire [5:0] seg_sel,
    input  wire       uart_rxd,
    output wire       uart_txd
);

    wire       tick_1s;
    wire       tick_20ms;

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

    uart_echo_app u_uart_echo_app (
        .clk      (sys_clk),
        .rst_n    (sys_rst_n),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd),
        .led      (led)
    );

endmodule
