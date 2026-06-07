module top (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    output wire [7:0] seg_led,
    output wire [5:0] seg_sel,
    input  wire       uart_rxd,
    output wire       uart_txd
);

    wire tick_1s;

    tick_gen #(
        .MAX_COUNT(50_000_000 - 1)  //1s
    ) u_tick_1s (
        .clk  (sys_clk),
        .rst_n(sys_rst_n),
        .tick (tick_1s)
    );

    seg_led seg_led_inst (
        .clk     (sys_clk),
        .rst_n   (sys_rst_n),
        .add_flag(tick_1s),
        .seg_sel (seg_sel),
        .seg_led (seg_led)
    );

    uart_echo_app u_uart_echo_app (
        .clk     (sys_clk),
        .rst_n   (sys_rst_n),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd)
    );

endmodule
