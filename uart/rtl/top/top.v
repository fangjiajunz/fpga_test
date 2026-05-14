module top (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire [3:0] key,
    output reg  [3:0] led,
    output wire [7:0] seg_led,
    output wire [5:0] seg_sel,
    input  wire       uart_rxd,
    output wire       uart_txd
);

    wire       tick_1s;
    wire       tick_20ms;
    wire [7:0] rx_data;
    wire       rx_flag;
    wire       tx_busy;
    reg  [7:0] tx_data;
    reg        tx_flag;
    reg  [7:0] tx_pending_data;
    reg        tx_pending_flag;

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
        .in_flag  (tx_flag),
        .tx       (uart_txd),
        .busy     (tx_busy)
    );

    uart_rx uart_rx_inst (
        .sys_clk  (sys_clk),
        .sys_rst_n(sys_rst_n),
        .rx       (uart_rxd),
        .po_data  (rx_data),
        .out_flag (rx_flag)
    );

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            led             <= 4'b0000;
            tx_data         <= 8'h00;
            tx_flag         <= 1'b0;
            tx_pending_data <= 8'h00;
            tx_pending_flag <= 1'b0;
        end else begin
            if (rx_flag) begin
                tx_pending_data <= rx_data;
                tx_pending_flag <= 1'b1;
                led             <= rx_data[3:0];
            end

            if (!tx_busy && tx_pending_flag && !rx_flag) begin
                tx_data         <= tx_pending_data;
                tx_flag         <= 1'b1;
                tx_pending_flag <= 1'b0;
            end else begin
                tx_flag <= 1'b0;
            end
        end
    end

endmodule
