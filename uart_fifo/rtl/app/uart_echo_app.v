module uart_echo_app #(
    parameter UART_BPS = 3000000,
    parameter CLK_FREQ = 50_000_000
) (
    input wire clk,
    input wire rst_n,

    input  wire uart_rxd,
    output wire uart_txd
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
    localparam ECHO_IDLE = 2'd0;  // 等待 RX FIFO 非空
    localparam ECHO_READ = 2'd1;  // 已发 rdreq，下一拍 rx_data 有效
    localparam ECHO_WRITE = 2'd2;  // 把数据写入 TX FIFO

    reg [1:0] echo_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            echo_state <= ECHO_IDLE;
            rx_rdreq   <= 1'b0;
            tx_wrreq   <= 1'b0;
            tx_data    <= 8'h00;
        end else begin
            rx_rdreq <= 1'b0;
            tx_wrreq <= 1'b0;
            case (echo_state)
                ECHO_IDLE: begin
                    if (!rx_empty && !tx_full) begin
                        rx_rdreq   <= 1'b1;
                        echo_state <= ECHO_READ;
                    end
                end
                ECHO_READ: begin
                    // 等一拍：普通 FIFO 在 rdreq 后下一拍 q 才更新
                    echo_state <= ECHO_WRITE;
                end
                ECHO_WRITE: begin
                    // 此时 rx_data 才是本次真正读出的字节
                    tx_data    <= rx_data;
                    tx_wrreq   <= 1'b1;
                    echo_state <= ECHO_IDLE;
                end
                default: echo_state <= ECHO_IDLE;
            endcase
        end
    end

endmodule
