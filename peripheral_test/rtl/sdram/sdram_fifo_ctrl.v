`timescale 1ns / 1ps

// ==============================================================================
// 模块名称 : sdram_fifo_ctrl
// 模块功能 : 面向 SDRAM 的双异步 FIFO 读写缓存控制器
//   1. 内部集成写 FIFO 与读 FIFO，实现用户时钟域与 SDRAM 控制器时钟域的隔离
//   2. 自动检测写/读 FIFO 水位，自动发起 SDRAM 突发写与突发读
//   3. 支持写优先仲裁机制，优先避免输入端数据溢出
//   4. 地址线性递增与环形回卷 (支持最大边界地址 MAX_ADDR)
// ==============================================================================

module sdram_fifo_ctrl #(
    parameter integer DATA_WIDTH = 16,            // 数据位宽 (16-bit)
    parameter integer FIFO_DEPTH = 512,           // 内部 FIFO 深度
    parameter integer ADDR_WIDTH = 9,             // FIFO 水位指示位宽
    parameter integer BURST_LEN  = 256,           // 单次突发读写长度
    parameter [23:0]  BASE_ADDR  = 24'h000000,    // SDRAM 读写基地址
    parameter [23:0]  MAX_ADDR   = 24'h3FFFFF     // SDRAM 环形边界地址 (4M x 16bit)
) (
    input  wire                  rst_n,           // 全局异步复位 (低有效)

    // =========================================================================
    // 1. 用户写通道 (异步写时钟域 user_wr_clk，例如摄像头像素时钟/ADC采样时钟)
    // =========================================================================
    input  wire                  user_wr_clk,     // 用户写时钟
    input  wire                  user_wr_en,      // 用户写使能
    input  wire [DATA_WIDTH-1:0] user_wr_data,    // 用户写入数据
    output wire                  user_wr_full,    // 用户写满标志
    output wire [ADDR_WIDTH-1:0] user_wr_usedw,   // 用户写已用深度

    // =========================================================================
    // 2. 用户读通道 (异步读时钟域 user_rd_clk，例如 LCD 显示时钟/DAC回放时钟)
    // =========================================================================
    input  wire                  user_rd_clk,     // 用户读时钟
    input  wire                  user_rd_en,      // 用户读使能
    output wire [DATA_WIDTH-1:0] user_rd_data,    // 用户读出数据
    output wire                  user_rd_empty,   // 用户读空标志
    output wire [ADDR_WIDTH-1:0] user_rd_usedw,   // 用户读可用数据量

    // =========================================================================
    // 3. SDRAM 控制器接口 (直连 sdram_top 模块)
    // =========================================================================
    input  wire                  sdram_clk,       // 100MHz SDRAM 控制器工作时钟
    input  wire                  sdram_init_done, // SDRAM 初始化完成标志
    input  wire                  sdram_rw_busy,   // SDRAM 控制器忙标志
    input  wire                  sdram_rw_done,   // SDRAM 单次突发读写完成脉冲
    input  wire                  sdram_wr_ack,    // SDRAM 写应答 (提前1拍取数)
    input  wire                  sdram_rd_ack,    // SDRAM 读应答 (数据有效)
    input  wire [DATA_WIDTH-1:0] sdram_rd_data,   // SDRAM 读回数据

    output reg                   sdram_wr_req,    // SDRAM 突发写请求
    output reg                   sdram_rd_req,    // SDRAM 突发读请求
    output reg  [23:0]           sdram_wr_addr,   // SDRAM 写起始地址
    output reg  [23:0]           sdram_rd_addr,   // SDRAM 读起始地址
    output wire [ 9:0]           sdram_wr_len,    // 突发写长度
    output wire [ 9:0]           sdram_rd_len,    // 突发读长度
    output wire [DATA_WIDTH-1:0] sdram_wr_data    // 送往 SDRAM 的写数据
);

    assign sdram_wr_len = BURST_LEN[9:0];
    assign sdram_rd_len = BURST_LEN[9:0];

    // =========================================================================
    // 内部 FIFO 信号定义
    // =========================================================================
    wire                  wr_fifo_burst_ready;
    wire                  wr_fifo_empty;
    wire                  rd_fifo_burst_ready;
    wire                  rd_fifo_full;

    // =========================================================================
    // 实例化写 FIFO (User -> SDRAM)
    // =========================================================================
    async_fifo_wrapper #(
        .DATA_WIDTH (DATA_WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .BURST_LEN  (BURST_LEN)
    ) u_wr_fifo (
        .rst_n          (rst_n),
        // 用户写端
        .wr_clk         (user_wr_clk),
        .wr_rst_n       (),
        .wr_en          (user_wr_en),
        .wr_data        (user_wr_data),
        .wr_full        (user_wr_full),
        .wr_almost_full (),
        .wr_usedw       (user_wr_usedw),
        .wr_burst_ready (),
        // SDRAM 读端 (通过 sdram_wr_ack 取走数据)
        .rd_clk         (sdram_clk),
        .rd_rst_n       (),
        .rd_en          (sdram_wr_ack),
        .rd_data        (sdram_wr_data),
        .rd_empty       (wr_fifo_empty),
        .rd_almost_empty(),
        .rd_usedw       (),
        .rd_burst_ready (wr_fifo_burst_ready)
    );

    // =========================================================================
    // 实例化读 FIFO (SDRAM -> User)
    // =========================================================================
    async_fifo_wrapper #(
        .DATA_WIDTH (DATA_WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .BURST_LEN  (BURST_LEN)
    ) u_rd_fifo (
        .rst_n          (rst_n),
        // SDRAM 写端 (接收 sdram_rd_ack 数据填入)
        .wr_clk         (sdram_clk),
        .wr_rst_n       (),
        .wr_en          (sdram_rd_ack),
        .wr_data        (sdram_rd_data),
        .wr_full        (rd_fifo_full),
        .wr_almost_full (),
        .wr_usedw       (),
        .wr_burst_ready (),
        // 用户读端
        .rd_clk         (user_rd_clk),
        .rd_rst_n       (),
        .rd_en          (user_rd_en),
        .rd_data        (user_rd_data),
        .rd_empty       (user_rd_empty),
        .rd_almost_empty(),
        .rd_usedw       (user_rd_usedw),
        .rd_burst_ready (rd_fifo_burst_ready)
    );

    // =========================================================================
    // SDRAM 突发调度状态机 (在 sdram_clk 域)
    // =========================================================================
    localparam [1:0] S_IDLE       = 2'd0;
    localparam [1:0] S_WAIT_WRITE = 2'd1;
    localparam [1:0] S_WAIT_READ  = 2'd2;

    reg [1:0] state;

    always @(posedge sdram_clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            sdram_wr_req  <= 1'b0;
            sdram_rd_req  <= 1'b0;
            sdram_wr_addr <= BASE_ADDR;
            sdram_rd_addr <= BASE_ADDR;
        end else begin
            case (state)
                S_IDLE: begin
                    sdram_wr_req <= 1'b0;
                    sdram_rd_req <= 1'b0;

                    if (sdram_init_done && !sdram_rw_busy) begin
                        // 优先级调度：写优先以避免外部输入溢出丢数据
                        if (wr_fifo_burst_ready) begin
                            sdram_wr_req <= 1'b1;
                            state        <= S_WAIT_WRITE;
                        end else if (rd_fifo_burst_ready) begin
                            sdram_rd_req <= 1'b1;
                            state        <= S_WAIT_READ;
                        end
                    end
                end

                S_WAIT_WRITE: begin
                    // 控制器已受理则撤销请求脉冲
                    if (sdram_rw_busy || sdram_wr_ack) begin
                        sdram_wr_req <= 1'b0;
                    end

                    // 突发完成，地址递增并环形回卷
                    if (sdram_rw_done) begin
                        state <= S_IDLE;
                        if (sdram_wr_addr + BURST_LEN >= MAX_ADDR) begin
                            sdram_wr_addr <= BASE_ADDR;
                        end else begin
                            sdram_wr_addr <= sdram_wr_addr + BURST_LEN;
                        end
                    end
                end

                S_WAIT_READ: begin
                    if (sdram_rw_busy || sdram_rd_ack) begin
                        sdram_rd_req <= 1'b0;
                    end

                    if (sdram_rw_done) begin
                        state <= S_IDLE;
                        if (sdram_rd_addr + BURST_LEN >= MAX_ADDR) begin
                            sdram_rd_addr <= BASE_ADDR;
                        end else begin
                            sdram_rd_addr <= sdram_rd_addr + BURST_LEN;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
