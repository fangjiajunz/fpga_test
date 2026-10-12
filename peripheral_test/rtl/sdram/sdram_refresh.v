`timescale 1ns / 1ps
`include "sdram_cmd_def.vh"

module sdram_refresh #(
    parameter integer CLK_FREQ_MHZ     = 100,                                 // 系统时钟频率 (MHz)
    parameter integer REF_INTERVAL_CNT = (CLK_FREQ_MHZ * 7812) / 1000,        // 刷新周期 7.812us 对应的时钟数 (100MHz 下约 781 拍)
    parameter integer TRC_CLK          = 6                                    // 自动刷新周期 tRFC (100MHz 下 6 拍约 60ns)
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        init_done,       // SDRAM 初始化完成标志 (来自 sdram_init)

    output reg         ref_req,         // 刷新请求信号 (送往仲裁器)
    input  wire        ref_ack,         // 仲裁器响应许可信号 (允许开始刷新)

    output reg  [ 3:0] ref_cmd,         // 刷新操作指令 {cs_n, ras_n, cas_n, we_n}
    output reg  [12:0] ref_addr,        // 刷新时的地址总线
    output reg  [ 1:0] ref_ba,          // 刷新时的 Bank 地址
    output reg         ref_cke,         // 刷新时的时钟有效信号
    output reg  [ 1:0] ref_dqm,         // 刷新时的数据掩码
    output wire        ref_done         // 单次刷新操作完成标志
);

    // 状态机编码定义
    localparam [1:0] S_IDLE = 2'd0;     // 空闲 / 等待仲裁许可
    localparam [1:0] S_REF  = 2'd1;     // 发出自动刷新指令 (1拍)
    localparam [1:0] S_TRFC = 2'd2;     // 等待自动刷新完成 tRFC (6拍)

    reg [ 1:0] state;
    reg [ 1:0] next_state;

    reg [10:0] cnt_ref;                 // 7.812us 定时计数器
    reg [ 3:0] cnt_clk;                 // tRFC 等待计数器

    // =========================================================================
    // 1. 定时刷新计数器与请求产生 (64ms / 8192行 = 7.812us)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt_ref <= 11'd0;
        else if (init_done) begin
            if (cnt_ref >= REF_INTERVAL_CNT - 1)
                cnt_ref <= 11'd0;
            else
                cnt_ref <= cnt_ref + 1'b1;
        end else
            cnt_ref <= 11'd0;
    end

    // 刷新请求生成与握手撤销
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ref_req <= 1'b0;
        else if (!init_done)
            ref_req <= 1'b0;
        else if (cnt_ref == REF_INTERVAL_CNT - 1)
            ref_req <= 1'b1;             // 定时达到 7.812us，向仲裁器举手发起请求
        else if (ref_ack)
            ref_req <= 1'b0;             // 获得仲裁器响应，立即撤销请求
    end

    // =========================================================================
    // 2. 刷新执行等待计数器 (cnt_clk)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt_clk <= 4'd0;
        else if (state == S_TRFC)
            cnt_clk <= (cnt_clk == TRC_CLK - 1) ? 4'd0 : cnt_clk + 1'b1;
        else
            cnt_clk <= 4'd0;
    end

    // =========================================================================
    // 3. 刷新执行三段式状态机
    // =========================================================================
    always @(*) begin
        case (state)
            S_IDLE: begin
                // 收到仲裁许可后，立即切入刷新执行状态
                if (ref_ack)
                    next_state = S_REF;
                else
                    next_state = S_IDLE;
            end

            S_REF: begin
                // 发出 CMD_A_REF 命令 1 拍后，立即进入 tRFC 等待
                next_state = S_TRFC;
            end

            S_TRFC: begin
                // 等满 TRC_CLK 拍后，刷新完成，返回空闲
                if (cnt_clk == TRC_CLK - 1)
                    next_state = S_IDLE;
                else
                    next_state = S_TRFC;
            end

            default: next_state = S_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // =========================================================================
    // 4. 命令与控制总线输出
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {ref_cke, ref_cmd} <= `CMD_INIT;
            ref_addr           <= 13'h1FFF;
            ref_ba             <= 2'b11;
            ref_dqm            <= 2'b11;
        end else begin
            ref_dqm <= 2'b00;
            case (next_state)
                S_REF: begin
                    // 发出单拍自动刷新指令
                    {ref_cke, ref_cmd} <= `CMD_A_REF;
                    ref_addr           <= 13'h1FFF;
                    ref_ba             <= 2'b11;
                end

                S_IDLE, S_TRFC: begin
                    // 其余时间在总线上输出 NOP
                    {ref_cke, ref_cmd} <= `CMD_NOP;
                    ref_addr           <= 13'h1FFF;
                    ref_ba             <= 2'b11;
                end

                default: begin
                    {ref_cke, ref_cmd} <= `CMD_NOP;
                    ref_addr           <= 13'h1FFF;
                    ref_ba             <= 2'b11;
                end
            endcase
        end
    end

    // 单次刷新完成脉冲 (在 S_TRFC 最后一拍拉高)
    assign ref_done = (state == S_TRFC) && (cnt_clk == TRC_CLK - 1);

endmodule
