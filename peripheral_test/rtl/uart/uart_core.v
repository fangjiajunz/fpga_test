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

    // RX 接收流接口 (内部自动从 RX FIFO 读出为稳定字节流)
    output reg  [7:0] rx_data,          // 接收到的数据字节
    output reg        rx_valid,         // 数据有效指示（单拍高电平脉冲）
    output wire       rx_empty,         // RX FIFO 空标志
    output wire       rx_full,          // RX FIFO 满标志
    output reg        rx_overflow,      // sticky：因 RX FIFO 满而丢弃了字节
    output reg        rx_frame_error,   // sticky：收到过停止位不是高的帧
    input  wire       rx_overflow_clr,  // 高电平清 rx_overflow
    input  wire       rx_frame_err_clr, // 高电平清 rx_frame_error

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
    // 1. 读写隔离：写端仅在接收到物理层有效字节且 FIFO 未满时发起写入
    wire       rx_fifo_wrreq = rx_raw_valid & ~rx_full;
    wire [7:0] rx_fifo_q;
    wire       rx_fifo_rdreq;

    // 2. Show-Ahead 模式规范：读使能必须用组合逻辑产生，且必须判断空状态 (!rx_empty)
    // 只要 FIFO 非空，在当前时钟上升沿立即弹出当前数据，由下级寄存器锁存输出
    assign rx_fifo_rdreq = !rx_empty;

    fifo_8x64 u_rx_fifo (
        .clock (clk),
        .sclr  (~rst_n),  // 同步复位，低电平有效取反
        .data  (rx_raw_data),
        .wrreq (rx_fifo_wrreq),
        .rdreq (rx_fifo_rdreq),
        .empty (rx_empty),
        .full  (rx_full),
        .q     (rx_fifo_q),
        .usedw ()
    );

    // ---- RX FIFO 自动读驱动 (标准单拍有效流式输出) ----
    // Show-Ahead 模式下，当 rx_fifo_rdreq 有效时，本拍 rx_fifo_q 已经就绪
    // 时钟上升沿锁存当前数据并对外指示有效 (rx_valid)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data  <= 8'h00;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= rx_fifo_rdreq;
            if (rx_fifo_rdreq) begin
                rx_data <= rx_fifo_q;
            end
        end
    end

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
    wire       tx_fifo_rdreq;

    reg  [7:0] tx_data_hold;
    reg        tx_send_flag;

    localparam TX_IDLE      = 2'd0;
    localparam TX_WAIT_BUSY = 2'd1;
    localparam TX_WAIT_DONE = 2'd2;

    reg  [1:0] tx_state;

    // Show-Ahead 模式规范：读使能必须用组合逻辑产生，且必须严格判断空状态 (!tx_fifo_empty)
    // 仅在发送器就绪 (TX_IDLE && tx_in_ready) 且 FIFO 非空时产生单拍读使能
    assign tx_fifo_rdreq = (tx_state == TX_IDLE) && (!tx_fifo_empty) && tx_in_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state     <= TX_IDLE;
            tx_send_flag <= 1'b0;
            tx_data_hold <= 8'd0;
        end else begin
            tx_send_flag <= 1'b0;

            case (tx_state)
                TX_IDLE: begin
                    if (tx_fifo_rdreq) begin
                        // Show-Ahead 模式：本拍 q 就是队首有效数据，同拍直接采走
                        tx_data_hold <= tx_fifo_q;
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
        .rdreq (tx_fifo_rdreq),
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
