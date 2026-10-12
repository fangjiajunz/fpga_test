`timescale 1ns / 1ps
`include "sdram_cmd_def.vh"

module sdram_init #(
    parameter integer CLK_FREQ_MHZ   = 100,                 // 控制器工作时钟 (MHz)
    parameter integer WAIT_200US_MAX = CLK_FREQ_MHZ * 200,  // 200us 等待周期数 (仿真时可缩小)
    parameter integer TRP_CLK        = 4,                   // 预充电周期 (tRP)
    parameter integer TRC_CLK        = 6,                   // 刷新周期 (tRFC)
    parameter integer TRSC_CLK       = 6,                   // 模式寄存器设置周期 (tRSC)
    parameter integer BURST_TYPE     = 0,                   // 0: Sequential, 1: Interleaved
    parameter integer CAS_LATENCY    = 3,                   // CL = 3
    parameter integer BURST_LEN      = 7                    // 3'b111: Full Page; 3'b011: 8
) (
    input wire clk,
    input wire rst_n,

    output reg  [ 3:0] init_cmd,   // {cs_n, ras_n, cas_n, we_n}
    output reg  [12:0] init_addr,  // 地址线
    output reg  [ 1:0] init_ba,    // Bank 地址
    output reg         init_cke,   // 时钟使能
    output reg  [ 1:0] init_dqm,   // 数据掩码
    output wire        init_done   // 初始化完成标志
);

    // 模式寄存器配置字 配置为了 全页突发（Full Page Burst），且采用 顺序连续传输
    localparam [12:0] MODE_REGISTER = {
        3'b000,  // A12-A10: 保留
        1'b0,  // A9: 突发写使能 (0: 突发读/突发写)
        2'b00,  // A8-A7: 标准模式
        CAS_LATENCY[2:0],  // A6-A4: CAS Latency
        BURST_TYPE[0],  // A3: 突发类型
        BURST_LEN[2:0]  // A2-A0: 突发长度
    };

    // 内部状态与计数器
    reg [ 4:0] state;
    reg [ 4:0] next_state;
    reg [15:0] cnt_wait;  // 200us 计数器
    reg [ 3:0] cnt_clk;  // 阶段延时计数器
    reg [ 3:0] cnt_ar;  // 自动刷新次数计数器

    // 上电 200us 计数
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cnt_wait <= 16'd0;
        else if (state == `I_NOP) begin
            if (cnt_wait < WAIT_200US_MAX) cnt_wait <= cnt_wait + 1'b1;
        end else cnt_wait <= 16'd0;
    end

    // 时序等待延时计数器 (cnt_clk)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cnt_clk <= 4'd0;
        else
            case (state)
                `I_TRP:  cnt_clk <= (cnt_clk == TRP_CLK - 1) ? 4'd0 : cnt_clk + 1'b1;
                `I_TRF:  cnt_clk <= (cnt_clk == TRC_CLK - 1) ? 4'd0 : cnt_clk + 1'b1;
                `I_TRSC: cnt_clk <= (cnt_clk == TRSC_CLK - 1) ? 4'd0 : cnt_clk + 1'b1;
                default: cnt_clk <= 4'd0;
            endcase
    end

    // 自动刷新次数计数器 (8 次刷新)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cnt_ar <= 4'd0;
        else if (state == `I_NOP) cnt_ar <= 4'd0;
        else if (state == `I_AR) cnt_ar <= cnt_ar + 1'b1;
    end

    // 状态转移逻辑
    always @(*) begin
        case (state)
            `I_NOP: begin
                if (cnt_wait >= WAIT_200US_MAX) next_state = `I_PRE;
                else next_state = `I_NOP;
            end

            `I_PRE: next_state = `I_TRP;

            `I_TRP: begin
                if (cnt_clk == TRP_CLK - 1) next_state = `I_AR;
                else next_state = `I_TRP;
            end

            `I_AR: next_state = `I_TRF;

            `I_TRF: begin
                if (cnt_clk == TRC_CLK - 1) begin
                    if (cnt_ar >= 4'd8) next_state = `I_MRS;
                    else next_state = `I_AR;
                end else next_state = `I_TRF;
            end

            `I_MRS: next_state = `I_TRSC;

            `I_TRSC: begin
                if (cnt_clk == TRSC_CLK - 1) next_state = `I_DONE;
                else next_state = `I_TRSC;
            end

            `I_DONE: next_state = `I_DONE;

            default: next_state = `I_NOP;
        endcase
    end

    // 状态机时序驱动
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= `I_NOP;
        else state <= next_state;
    end

    // 控制命令与引脚输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {init_cke, init_cmd} <= `CMD_INIT;
            init_addr            <= 13'h1FFF;
            init_ba              <= 2'b11;
            init_dqm             <= 2'b11;
        end else begin
            init_dqm <= 2'b00;  // 正常工作/初始化期间保持低电平允许操作
            case (next_state)
                `I_NOP, `I_TRP, `I_TRF, `I_TRSC, `I_DONE: begin
                    {init_cke, init_cmd} <= `CMD_NOP;
                    init_addr            <= 13'h1FFF;
                    init_ba              <= 2'b11;
                end

                `I_PRE: begin
                    {init_cke, init_cmd} <= `CMD_PRGE;
                    init_addr[10]        <= 1'b1;  // A10=1: 全 Bank 预充电
                    init_ba              <= 2'b11;
                end

                `I_AR: begin
                    {init_cke, init_cmd} <= `CMD_A_REF;
                    init_addr            <= 13'h1FFF;
                    init_ba              <= 2'b11;
                end

                `I_MRS: begin
                    {init_cke, init_cmd} <= `CMD_LMR;
                    init_ba              <= 2'b00;  // LMR 时 BA 须为 00
                    init_addr            <= MODE_REGISTER;
                end

                default: begin
                    {init_cke, init_cmd} <= `CMD_NOP;
                    init_addr            <= 13'h1FFF;
                    init_ba              <= 2'b11;
                end
            endcase
        end
    end

    // 初始化完成指示
    assign init_done = (state == `I_DONE);

endmodule
