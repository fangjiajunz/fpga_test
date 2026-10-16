`timescale 1ns / 1ps

// ==============================================================================
// 模块名称 : async_fifo_wrapper
// 模块功能 : 异步 FIFO 工程化通用封装模块
//   1. 内部例化 Altera 16-bit x 512 深度 dcfifo (Show-ahead 模式)
//   2. 内置写/读双时钟域异步复位同步释放电路 (基于 rst_sync)，杜绝复位亚稳态
//   3. 提供可参数化的几乎满 (almost_full) 与几乎空 (almost_empty) 告警水线
//   4. 专为 SDRAM 突发传输提供 burst_ready 门限指示：
//      - wr_burst_ready: 写端数据已攒够一个突发块，通知控制器可启动 SDRAM 突发写
//      - rd_burst_ready: 读端余量充足容纳一个突发块，通知控制器可启动 SDRAM 突发读
// ==============================================================================

module async_fifo_wrapper #(
    parameter integer DATA_WIDTH          = 16,   // 数据位宽
    parameter integer FIFO_DEPTH          = 512,  // FIFO 存储深度
    parameter integer ADDR_WIDTH          = 9,    // 水位指示宽度 (2^9 = 512)
    parameter integer BURST_LEN           = 256,  // SDRAM 单次突发长度
    parameter integer ALMOST_FULL_THRESH  = 500,  // 几乎满阈值
    parameter integer ALMOST_EMPTY_THRESH = 10    // 几乎空阈值
) (
    // 全局复位输入 (异步低电平有效)
    input wire rst_n,

    // =========================================================================
    // 写通道接口 (写时钟域 wr_clk)
    // =========================================================================
    input  wire                  wr_clk,          // 写时钟
    output wire                  wr_rst_n,        // 写时钟域安全同步复位输出
    input  wire                  wr_en,           // 写使能
    input  wire [DATA_WIDTH-1:0] wr_data,         // 写数据输入
    output wire                  wr_full,         // 写满标志
    output wire                  wr_almost_full,  // 写几乎满标志
    output wire [ADDR_WIDTH-1:0] wr_usedw,        // 写侧已存字数
    output wire                  wr_burst_ready,  // 写端突发就绪指示 (用于触发写 SDRAM)

    // =========================================================================
    // 读通道接口 (读时钟域 rd_clk)
    // =========================================================================
    input  wire                  rd_clk,           // 读时钟
    output wire                  rd_rst_n,         // 读时钟域安全同步复位输出
    input  wire                  rd_en,            // 读使能 (Show-ahead 模式下一拍取走数据)
    output wire [DATA_WIDTH-1:0] rd_data,          // 读数据输出
    output wire                  rd_empty,         // 读空标志
    output wire                  rd_almost_empty,  // 读几乎空标志
    output wire [ADDR_WIDTH-1:0] rd_usedw,         // 读侧已存字数
    output wire                  rd_burst_ready    // 读端突发就绪指示 (用于触发读 SDRAM)
);

    // =========================================================================
    // 1. 双时钟域异步复位同步释放处理 (CDC Reset Synchronizer)
    // =========================================================================
    wire wr_sync_rst_n;
    wire rd_sync_rst_n;

    // 写时钟域复位同步器
    rst_sync #(
        .STAGES(2)
    ) u_rst_sync_wr (
        .clk        (wr_clk),
        .async_rst_n(rst_n),
        .ext_en     (1'b1),
        .sync_rst_n (wr_sync_rst_n)
    );

    // 读时钟域复位同步器
    rst_sync #(
        .STAGES(2)
    ) u_rst_sync_rd (
        .clk        (rd_clk),
        .async_rst_n(rst_n),
        .ext_en     (1'b1),
        .sync_rst_n (rd_sync_rst_n)
    );

    assign wr_rst_n = wr_sync_rst_n;
    assign rd_rst_n = rd_sync_rst_n;

    // 当任意一个时钟域处于复位状态时，保持底层 FIFO 的高电平异步复位 aclr
    wire fifo_aclr;
    assign fifo_aclr = (!wr_sync_rst_n) || (!rd_sync_rst_n);

    // =========================================================================
    // 2. 底层 dcfifo IP 例化
    // =========================================================================
    async_fifo_16x512 u_async_fifo_16x512 (
        .aclr   (fifo_aclr),
        .wrclk  (wr_clk),
        .wrreq  (wr_en),
        .data   (wr_data),
        .wrfull (wr_full),
        .wrusedw(wr_usedw),

        .rdclk  (rd_clk),
        .rdreq  (rd_en),
        .q      (rd_data),
        .rdempty(rd_empty),
        .rdusedw(rd_usedw)
    );

    // =========================================================================
    // 3. 状态门限与 SDRAM 突发指示逻辑
    // =========================================================================
    // 写侧状态
    assign wr_almost_full  = (wr_usedw >= ALMOST_FULL_THRESH[ADDR_WIDTH-1:0]) || wr_full;
    assign wr_burst_ready  = (wr_usedw >= BURST_LEN[ADDR_WIDTH-1:0]);

    // 读侧状态
    assign rd_almost_empty = (rd_usedw <= ALMOST_EMPTY_THRESH[ADDR_WIDTH-1:0]) || rd_empty;
    // 读侧空闲空间大于等于 BURST_LEN 时，说明有充足空间接纳下一次 SDRAM 突发读取
    assign rd_burst_ready  = (rd_usedw <= (FIFO_DEPTH - BURST_LEN));

endmodule
