`timescale 1ns / 1ps

module sdram_top #(
    parameter integer CLK_FREQ_MHZ   = 100,                 // 控制器参考时钟频率 (MHz)
    parameter integer WAIT_200US_MAX = CLK_FREQ_MHZ * 200,  // 上电稳定期计数 (仿真可减小)
    parameter integer TRCD_CLK       = 2,                   // 行激活等待周期 (tRCD)
    parameter integer TCL_CLK        = 3,                   // CAS 潜伏期 (CL)
    parameter integer TRP_CLK        = 4,                   // 预充电周期 (tRP)
    parameter integer TRC_CLK        = 6,                   // 自动刷新周期 (tRFC)
    parameter integer TWR_CLK        = 2                    // 写恢复周期 (tWR)
) (
    // 时钟与复位
    input  wire        ref_clk,    // SDRAM 控制器工作基准时钟 (如 100MHz)
    input  wire        out_clk,    // SDRAM 物理芯片时钟 (带相位偏移，如 100MHz -75°)
    input  wire        rst_n,      // 系统复位 (低电平有效)

    // 用户突发读写接口 (无 FIFO 原生接口)
    input  wire        wr_req,     // 突发写请求
    input  wire        rd_req,     // 突发读请求
    input  wire [23:0] wr_addr,    // 突发写线性起始地址 [Bank 2位, Row 13位, Col 9位]
    input  wire [23:0] rd_addr,    // 突发读线性起始地址
    input  wire [ 9:0] wr_len,     // 突发写数据长度
    input  wire [ 9:0] rd_len,     // 突发读数据长度
    input  wire [15:0] wr_data,    // 写入数据输入
    output wire        wr_ack,     // 写应答信号 (指示从数据源拉取下一拍数据)
    output wire        rd_ack,     // 读有效信号 (指示当前读数据有效)
    output wire [15:0] rd_data,    // 读出数据输出
    output wire        rw_busy,    // 控制器忙标志
    output wire        rw_done,    // 单次突发读写完成脉冲
    output wire        init_done,  // SDRAM 初始化完成标志

    // 外部 SDRAM 芯片物理引脚
    output wire        sdram_clk,   // SDRAM 芯片时钟引脚
    output wire        sdram_cke,   // SDRAM 时钟使能
    output wire        sdram_cs_n,  // SDRAM 片选
    output wire        sdram_ras_n, // SDRAM 行有效
    output wire        sdram_cas_n, // SDRAM 列有效
    output wire        sdram_we_n,  // SDRAM 写有效
    output wire [ 1:0] sdram_ba,    // SDRAM Bank 地址
    output wire [12:0] sdram_addr,  // SDRAM 行/列地址
    output wire [ 1:0] sdram_dqm,   // SDRAM 数据掩码
    inout  wire [15:0] sdram_data   // SDRAM 双向数据线
);

    // =========================================================================
    // 内部信号定义
    // =========================================================================

    // 1. 初始化模块 (sdram_init) 接口
    wire [ 3:0] init_cmd;
    wire [12:0] init_addr;
    wire [ 1:0] init_ba;
    wire        init_cke;
    wire [ 1:0] init_dqm;

    // 2. 自动刷新模块 (sdram_refresh) 接口
    wire        ref_req;
    wire        ref_ack;
    wire        ref_done;
    wire [ 3:0] ref_cmd;
    wire [12:0] ref_addr;
    wire [ 1:0] ref_ba;
    wire        ref_cke;
    wire [ 1:0] ref_dqm;

    // 3. 突发读写控制模块 (sdram_rw_ctrl) 接口
    wire        rw_bus_req;
    wire        rw_bus_ack;
    wire [ 3:0] rw_cmd;
    wire [12:0] rw_addr_out;
    wire [ 1:0] rw_ba;
    wire [ 1:0] rw_dqm;
    wire        rw_cke;
    wire        data_out_en;

    // 4. 仲裁器 (sdram_arbiter) 输出至 PHY
    wire [ 3:0] phy_cmd;
    wire [12:0] phy_addr;
    wire [ 1:0] phy_ba;
    wire        phy_cke;
    wire [ 1:0] phy_dqm;
    wire        phy_data_out_en;

    // 芯片时钟驱动 (直接直连相位偏移后的时钟)
    assign sdram_clk = out_clk;

    // =========================================================================
    // 模块例化与互联
    // =========================================================================

    // 1. SDRAM 初始化模块 (上电200us稳定, 预充电, 8次自动刷新, 模式寄存器配置)
    sdram_init #(
        .CLK_FREQ_MHZ   (CLK_FREQ_MHZ),
        .WAIT_200US_MAX (WAIT_200US_MAX),
        .TRP_CLK        (TRP_CLK),
        .TRC_CLK        (TRC_CLK),
        .TRSC_CLK       (6),
        .BURST_TYPE     (0),
        .CAS_LATENCY    (TCL_CLK),
        .BURST_LEN      (7)          // 全页突发
    ) u_sdram_init (
        .clk            (ref_clk),
        .rst_n          (rst_n),
        .init_cmd       (init_cmd),
        .init_addr      (init_addr),
        .init_ba        (init_ba),
        .init_cke       (init_cke),
        .init_dqm       (init_dqm),
        .init_done      (init_done)
    );

    // 2. SDRAM 自动刷新模块 (按 7.812us 定时发出刷新申请与 tRFC 计数)
    sdram_refresh #(
        .CLK_FREQ_MHZ   (CLK_FREQ_MHZ),
        .TRC_CLK        (TRC_CLK)
    ) u_sdram_refresh (
        .clk            (ref_clk),
        .rst_n          (rst_n),
        .init_done      (init_done),
        .ref_req        (ref_req),
        .ref_ack        (ref_ack),
        .ref_cmd        (ref_cmd),
        .ref_addr       (ref_addr),
        .ref_ba         (ref_ba),
        .ref_cke        (ref_cke),
        .ref_dqm        (ref_dqm),
        .ref_done       (ref_done)
    );

    // 3. SDRAM 突发读写控制器 (状态机管理、读写交替优先级调度、突发握手)
    sdram_rw_ctrl #(
        .CLK_FREQ_MHZ   (CLK_FREQ_MHZ),
        .TRCD_CLK       (TRCD_CLK),
        .TCL_CLK        (TCL_CLK),
        .TRP_CLK        (TRP_CLK),
        .TWR_CLK        (TWR_CLK)
    ) u_sdram_rw_ctrl (
        .clk            (ref_clk),
        .rst_n          (rst_n),
        .init_done      (init_done),
        .wr_req         (wr_req),
        .rd_req         (rd_req),
        .wr_addr        (wr_addr),
        .rd_addr        (rd_addr),
        .wr_len         (wr_len),
        .rd_len         (rd_len),
        .wr_ack         (wr_ack),
        .rd_ack         (rd_ack),
        .rw_busy        (rw_busy),
        .rw_done        (rw_done),
        .rw_bus_req     (rw_bus_req),
        .rw_bus_ack     (rw_bus_ack),
        .rw_cmd         (rw_cmd),
        .rw_addr_out    (rw_addr_out),
        .rw_ba          (rw_ba),
        .rw_dqm         (rw_dqm),
        .rw_cke         (rw_cke),
        .data_out_en    (data_out_en)
    );

    // 4. SDRAM 总线仲裁器 (初始化 > 刷新 > 读写 优先级仲裁)
    sdram_arbiter u_sdram_arbiter (
        .clk            (ref_clk),
        .rst_n          (rst_n),
        // 初始化通道
        .init_done      (init_done),
        .init_cmd       (init_cmd),
        .init_addr      (init_addr),
        .init_ba        (init_ba),
        .init_cke       (init_cke),
        .init_dqm       (init_dqm),
        // 自动刷新通道
        .ref_req        (ref_req),
        .ref_ack        (ref_ack),
        .ref_done       (ref_done),
        .ref_cmd        (ref_cmd),
        .ref_addr       (ref_addr),
        .ref_ba         (ref_ba),
        .ref_cke        (ref_cke),
        .ref_dqm        (ref_dqm),
        // 突发读写通道
        .rw_bus_req     (rw_bus_req),
        .rw_bus_ack     (rw_bus_ack),
        .rw_done        (rw_done),
        .rw_cmd         (rw_cmd),
        .rw_addr        (rw_addr_out),
        .rw_ba          (rw_ba),
        .rw_cke         (rw_cke),
        .rw_dqm         (rw_dqm),
        .rw_data_out_en (data_out_en),
        // 仲裁输出至 PHY 物理层
        .phy_cmd        (phy_cmd),
        .phy_addr       (phy_addr),
        .phy_ba         (phy_ba),
        .phy_cke        (phy_cke),
        .phy_dqm        (phy_dqm),
        .phy_data_out_en(phy_data_out_en)
    );

    // 5. SDRAM 物理层接口 (三态双向总线与引脚直连)
    sdram_phy u_sdram_phy (
        .clk            (ref_clk),
        .rst_n          (rst_n),
        .phy_cmd        (phy_cmd),
        .phy_addr       (phy_addr),
        .phy_ba         (phy_ba),
        .phy_cke        (phy_cke),
        .phy_dqm        (phy_dqm),
        .phy_data_out_en(phy_data_out_en),
        .wr_data        (wr_data),
        .rd_data        (rd_data),
        // 外部芯片引脚
        .sdram_cke      (sdram_cke),
        .sdram_cs_n     (sdram_cs_n),
        .sdram_ras_n    (sdram_ras_n),
        .sdram_cas_n    (sdram_cas_n),
        .sdram_we_n     (sdram_we_n),
        .sdram_ba       (sdram_ba),
        .sdram_addr     (sdram_addr),
        .sdram_dqm      (sdram_dqm),
        .sdram_data     (sdram_data)
    );

endmodule
