module uart_echo_app #(
    parameter UART_BPS = 115200,
    parameter CLK_FREQ = 50_000_000
) (
    input wire clk,
    input wire rst_n,

    input  wire uart_rxd,
    output wire uart_txd,

    output reg  [7:0] echo_data,
    output reg        echo_valid
);

    wire [7:0] rx_data;
    wire       rx_empty;
    wire       tx_full;

    reg        rx_rdreq;
    reg  [7:0] tx_data;
    reg        tx_wrreq;

    uart_core #(
        .UART_BPS(UART_BPS),
        .CLK_FREQ(CLK_FREQ)
    ) u_uart_core (
        .clk     (clk),
        .rst_n   (rst_n),
        .rxd     (uart_rxd),
        .txd     (uart_txd),
        .rx_data (rx_data),
        .rx_empty(rx_empty),
        .rx_rdreq(rx_rdreq),
        .tx_data (tx_data),
        .tx_wrreq(tx_wrreq),
        .tx_full (tx_full)
    );

    // RX -> TX echo 状态机：每次只读一个字节并写入 TX FIFO
    // show-ahead FIFO：q 始终显示头部数据，rdreq 用于弹出并更新 q
    localparam ECHO_IDLE = 1'd0;  // 等待 RX FIFO 非空
    localparam ECHO_SEND = 1'd1;  // 采样 rx_data 并发 rdreq 弹出

    reg echo_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            echo_state <= ECHO_IDLE;
            rx_rdreq   <= 1'b0;
            tx_wrreq   <= 1'b0;
            tx_data    <= 8'h00;
            echo_data  <= 8'h00;
            echo_valid <= 1'b0;
        end else begin
            rx_rdreq <= 1'b0;
            tx_wrreq <= 1'b0;
            echo_valid <= 1'b0;
            case (echo_state)
                ECHO_IDLE: begin
                    if (!rx_empty && !tx_full) begin
                        // show-ahead：rx_data 已经是 FIFO 头部数据，先采样
                        tx_data    <= rx_data;
                        echo_data  <= rx_data;
                        rx_rdreq   <= 1'b1;  // 发 rdreq 弹出，下一拍 q 更新
                        echo_state <= ECHO_SEND;
                    end
                end
                ECHO_SEND: begin
                    // 写入 TX FIFO
                    tx_wrreq   <= 1'b1;
                    echo_valid <= 1'b1;
                    echo_state <= ECHO_IDLE;
                end
                default: echo_state <= ECHO_IDLE;
            endcase
        end
    end

endmodule
