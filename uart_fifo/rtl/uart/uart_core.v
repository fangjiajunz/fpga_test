module uart_core #(
    parameter UART_BPS = 115200,
    parameter CLK_FREQ = 50_000_000
) (
    input wire clk,
    input wire rst_n,

    input  wire rxd,
    output wire txd,

    // RX FIFO 接口
    output wire [7:0] rx_data,   // 读出的数据（rdreq 后下一拍有效）
    output wire       rx_empty,  // RX FIFO 空标志
    input  wire       rx_rdreq,  // 读请求

    // TX FIFO 接口
    input  wire [7:0] tx_data,   // 写入的数据
    input  wire       tx_wrreq,  // 写请求
    output wire       tx_full    // TX FIFO 满标志
);

    // ---- uart_rx 原始输出 ----
    wire [7:0] rx_raw_data;
    wire       rx_raw_valid;

    uart_rx #(
        .UART_BPS(UART_BPS),
        .CLK_FREQ(CLK_FREQ)
    ) u_uart_rx (
        .sys_clk  (clk),
        .sys_rst_n(rst_n),
        .rx       (rxd),
        .po_data  (rx_raw_data),
        .out_flag (rx_raw_valid)
    );

    // ---- RX FIFO ----
    fifo_8x64 u_rx_fifo (
        .clock (clk),
        .sclr  (~rst_n),  // 同步复位，低电平有效取反
        .data  (rx_raw_data),
        .wrreq (rx_raw_valid),
        .rdreq (rx_rdreq),
        .empty (rx_empty),
        .full  (),
        .q     (rx_data),
        .usedw ()
    );

    // ---- TX FIFO + 发送状态机 ----
    wire [7:0] tx_fifo_q;
    wire       tx_fifo_empty;
    wire       tx_busy;

    // FIFO 为 show-ahead 模式，q 在 rdreq 前已经是队首数据。
    // 因此 rdreq 与 uart_tx in_flag 同拍发出，让 uart_tx 锁存被弹出的当前字节。
    localparam TX_IDLE      = 2'd0;
    localparam TX_WAIT_BUSY = 2'd1;
    localparam TX_WAIT_DONE = 2'd2;

    reg [1:0] tx_state;
    reg       tx_rdreq;
    reg       tx_send_flag;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state     <= TX_IDLE;
            tx_rdreq     <= 1'b0;
            tx_send_flag <= 1'b0;
        end else begin
            tx_rdreq     <= 1'b0;
            tx_send_flag <= 1'b0;
            case (tx_state)
                TX_IDLE: begin
                    if (!tx_fifo_empty && !tx_busy) begin
                        tx_rdreq     <= 1'b1;
                        tx_send_flag <= 1'b1;
                        tx_state     <= TX_WAIT_BUSY;
                    end
                end
                TX_WAIT_BUSY: begin
                    if (tx_busy) begin
                        tx_state <= TX_WAIT_DONE;
                    end
                end
                TX_WAIT_DONE: begin
                    if (!tx_busy) begin
                        tx_state <= TX_IDLE;
                    end
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    fifo_8x64 u_tx_fifo (
        .clock (clk),
        .sclr  (~rst_n),  // 同步复位，低电平有效取反
        .data  (tx_data),
        .wrreq (tx_wrreq),
        .rdreq (tx_rdreq),
        .empty (tx_fifo_empty),
        .full  (tx_full),
        .q     (tx_fifo_q),
        .usedw ()
    );

    uart_tx #(
        .UART_BPS(UART_BPS),
        .CLK_FREQ(CLK_FREQ)
    ) u_uart_tx (
        .sys_clk  (clk),
        .sys_rst_n(rst_n),
        .in_data  (tx_fifo_q),
        .in_flag  (tx_send_flag),
        .tx       (txd),
        .busy     (tx_busy)
    );

endmodule
