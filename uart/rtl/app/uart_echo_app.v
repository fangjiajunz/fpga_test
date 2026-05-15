module uart_echo_app #(
    parameter UART_BPS = 115200,
    parameter CLK_FREQ = 50_000_000
) (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       uart_rxd,
    output wire       uart_txd,

    output reg  [3:0] led
);

    wire [7:0] rx_data;
    wire       rx_valid;
    wire       tx_ready;

    reg  [7:0] tx_data;
    reg        tx_valid;
    reg  [7:0] tx_pending_data;
    reg        tx_pending_valid;

    uart_core #(
        .UART_BPS(UART_BPS),
        .CLK_FREQ(CLK_FREQ)
    ) u_uart_core (
        .clk      (clk),
        .rst_n    (rst_n),
        .rxd      (uart_rxd),
        .txd      (uart_txd),
        .rx_data  (rx_data),
        .rx_valid (rx_valid),
        .tx_data  (tx_data),
        .tx_valid (tx_valid),
        .tx_ready (tx_ready)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            led              <= 4'b0000;
            tx_data          <= 8'h00;
            tx_valid         <= 1'b0;
            tx_pending_data  <= 8'h00;
            tx_pending_valid <= 1'b0;
        end else begin
            tx_valid <= 1'b0;

            if (rx_valid) begin
                tx_pending_data  <= rx_data;
                tx_pending_valid <= 1'b1;
                led              <= rx_data[3:0];
            end

            if (tx_ready && tx_pending_valid && !rx_valid) begin
                tx_data          <= tx_pending_data;
                tx_valid         <= 1'b1;
                tx_pending_valid <= 1'b0;
            end
        end
    end

endmodule
