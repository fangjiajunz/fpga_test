module uart_core #(
    parameter UART_BPS = 115200,
    parameter CLK_FREQ = 50_000_000
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       rxd,
    output wire       txd,

    output wire [7:0] rx_data,
    output wire       rx_valid,

    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output wire       tx_ready
);

    wire tx_busy;

    assign tx_ready = !tx_busy;

    uart_rx #(
        .UART_BPS(UART_BPS),
        .CLK_FREQ(CLK_FREQ)
    ) u_uart_rx (
        .sys_clk  (clk),
        .sys_rst_n(rst_n),
        .rx       (rxd),
        .po_data  (rx_data),
        .out_flag (rx_valid)
    );

    uart_tx #(
        .UART_BPS(UART_BPS),
        .CLK_FREQ(CLK_FREQ)
    ) u_uart_tx (
        .sys_clk  (clk),
        .sys_rst_n(rst_n),
        .in_data  (tx_data),
        .in_flag  (tx_valid),
        .tx       (txd),
        .busy     (tx_busy)
    );

endmodule
