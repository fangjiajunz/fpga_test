module uart_core #(
    parameter UART_BPS = 115200,
    parameter CLK_FREQ = 50_000_000,
    // 必须和 fifo_8x64 的 LPM_SHOWAHEAD 配置保持一致：
    //   1 = show-ahead（当前 IP 配置 LPM_SHOWAHEAD="ON"），q 始终显示队首，
    //       rdreq 与取数可以在同一拍完成
    //   0 = 普通 FIFO，rdreq 之后下一拍 q 才更新为弹出的数据
    // 用 MegaWizard 重新生成 FIFO 后请同步修改这个参数。
    parameter FIFO_SHOW_AHEAD = 1
) (
    input wire clk,
    input wire rst_n,

    input  wire rxd,
    output wire txd,

    // RX FIFO 接口
    output wire [7:0] rx_data,          // 读出的数据（rdreq 后下一拍有效）
    output wire       rx_empty,         // RX FIFO 空标志
    output wire       rx_full,          // RX FIFO 满标志
    output reg        rx_overflow,      // sticky：因 RX FIFO 满而丢弃了字节
    output reg        rx_frame_error,   // sticky：收到过停止位不是高的帧
    input  wire       rx_overflow_clr,  // 高电平清 rx_overflow
    input  wire       rx_frame_err_clr, // 高电平清 rx_frame_error
    input  wire       rx_rdreq,         // 读请求

    // TX FIFO 接口
    input  wire [7:0] tx_data,   // 写入的数据
    input  wire       tx_wrreq,  // 写请求
    output wire       tx_full    // TX FIFO 满标志
);

    // ---- uart_rx 原始输出 ----
    wire [7:0] rx_raw_data;
    wire       rx_raw_valid;
    wire       rx_raw_frame_err;

    uart_rx #(
        .UART_BPS(UART_BPS),
        .CLK_FREQ(CLK_FREQ)
    ) u_uart_rx (
        .sys_clk     (clk),
        .sys_rst_n   (rst_n),
        .rx          (rxd),
        .po_data     (rx_raw_data),
        .out_flag    (rx_raw_valid),
        .frame_error (rx_raw_frame_err)
    );

    // ---- RX FIFO ----
    // FIFO 满时直接屏蔽 wrreq（scfifo 满时本身也会忽略写入），丢掉的字节
    // 记在 rx_overflow 里，这样溢出不会再是静默的。
    wire rx_fifo_wrreq = rx_raw_valid & ~rx_full;

    fifo_8x64 u_rx_fifo (
        .clock (clk),
        .sclr  (~rst_n),  // 同步复位，低电平有效取反
        .data  (rx_raw_data),
        .wrreq (rx_fifo_wrreq),
        .rdreq (rx_rdreq),
        .empty (rx_empty),
        .full  (rx_full),
        .q     (rx_data),
        .usedw ()
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_overflow <= 1'b0;
        end else if (rx_overflow_clr) begin
            rx_overflow <= 1'b0;
        end else if (rx_raw_valid && rx_full) begin
            rx_overflow <= 1'b1;
        end
    end

    // uart_rx 的 frame_error 只是一个时钟周期的脉冲，软件按帧轮询很容易漏掉，
    // 所以在这一层锁成 sticky 标志，和 rx_overflow 保持同一套用法。
    // 注意：帧错误的数据已经进了 FIFO（标准 UART 行为），这个标志只负责报告，
    // 丢不丢由上层决定。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_frame_error <= 1'b0;
        end else if (rx_frame_err_clr) begin
            rx_frame_error <= 1'b0;
        end else if (rx_raw_frame_err) begin
            rx_frame_error <= 1'b1;
        end
    end

    // ---- TX FIFO + 发送状态机 ----
    wire [7:0] tx_fifo_q;
    wire       tx_fifo_empty;
    wire       tx_busy;
    wire       tx_in_ready;

    // uart_tx.in_data 由 tx_data_hold 驱动，而不是直接把 tx_fifo_q 接到
    // uart_tx 上。这样 FIFO 的 q 更新时机（show-ahead 还是普通模式）就只影响
    // 本状态机，不会影响 uart_tx 的锁存时刻。
    reg [7:0] tx_data_hold;
    reg       tx_rdreq;
    reg       tx_send_flag;

    localparam TX_IDLE      = 3'd0;
    localparam TX_WAIT_Q    = 3'd1;  // 仅普通 FIFO 模式：等 rdreq 之后 q 更新
    localparam TX_SEND      = 3'd2;  // 仅普通 FIFO 模式：锁存 q 并发出
    localparam TX_WAIT_BUSY = 3'd3;
    localparam TX_WAIT_DONE = 3'd4;

    reg [2:0] tx_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state     <= TX_IDLE;
            tx_rdreq     <= 1'b0;
            tx_send_flag <= 1'b0;
            tx_data_hold <= 8'd0;
        end else begin
            tx_rdreq     <= 1'b0;
            tx_send_flag <= 1'b0;
            case (tx_state)
                TX_IDLE: begin
                    // uart_tx 的 in_ready 就是 !busy，用 in_ready 而不是 !tx_busy，
                    // 接口语义更明确
                    if (!tx_fifo_empty && tx_in_ready) begin
                        tx_rdreq <= 1'b1;  // 弹出队首
                        if (FIFO_SHOW_AHEAD) begin
                            // show-ahead：本拍 q 就是队首，同拍锁存即可
                            tx_data_hold <= tx_fifo_q;
                            tx_send_flag <= 1'b1;
                            tx_state     <= TX_WAIT_BUSY;
                        end else begin
                            // 普通 FIFO：rdreq 之后 q 才更新，先等一拍
                            tx_state <= TX_WAIT_Q;
                        end
                    end
                end
                TX_WAIT_Q: begin
                    tx_state <= TX_SEND;
                end
                TX_SEND: begin
                    tx_data_hold <= tx_fifo_q;  // 此时 q 才是刚弹出的数据
                    tx_send_flag <= 1'b1;
                    tx_state     <= TX_WAIT_BUSY;
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
        .in_data  (tx_data_hold),
        .in_flag  (tx_send_flag),
        .tx       (txd),
        .busy     (tx_busy),
        .in_ready (tx_in_ready)
    );

endmodule
