module top (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire [3:0] key,
    output reg  [3:0] led,
    output wire [7:0] seg_led,
    output wire [5:0] seg_sel,
    output wire       uart_txd
);

    wire       tick_1s;
    wire       tick_20ms;
    reg  [7:0] tx_data;

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

    uart_tx uart_tx_inst (
        .sys_clk  (sys_clk),
        .sys_rst_n(sys_rst_n),
        .in_data  (tx_data),
        .in_flag  (tick_1s),
        .tx       (uart_txd)
    );

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            led     <= 4'b0000;
            tx_data <= 8'h55;
        end else if (tick_1s) begin
            led     <= {led[2:0], ~led[3]};
            tx_data <= tx_data + 1'b1;
        end
    end

endmodule
