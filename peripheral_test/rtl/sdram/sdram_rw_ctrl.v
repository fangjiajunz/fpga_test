`timescale 1ns / 1ps
`include "sdram_cmd_def.vh"

module sdram_rw_ctrl #(
    parameter integer CLK_FREQ_MHZ = 100,
    parameter integer TRCD_CLK     = 2,    // 行选通周期 (tRCD)
    parameter integer TCL_CLK      = 3,    // CAS 潜伏期 (CL)
    parameter integer TRP_CLK      = 4,    // 预充电周期 (tRP)
    parameter integer TWR_CLK      = 2     // 写恢复周期 (tWR)
) (
    input wire clk,
    input wire rst_n,
    input wire init_done,

    // 用户读写请求接口
    input wire        wr_req,   // 写请求
    input wire        rd_req,   // 读请求
    input wire [23:0] wr_addr,  // 写线性起始地址
    input wire [23:0] rd_addr,  // 读线性起始地址
    input wire [ 9:0] wr_len,   // 突发写长度
    input wire [ 9:0] rd_len,   // 突发读长度

    output reg  wr_ack,   // 写数据应答 (从写 FIFO 读出一拍数据)
    output reg  rd_ack,   // 读数据有效应答 (向读 FIFO 写入一拍数据)
    output wire rw_busy,  // 读写控制器忙碌标志
    output reg  rw_done,  // 本次突发读/写完成脉冲

    // 仲裁器接口
    output reg  rw_bus_req,  // 向仲裁器申请总线
    input  wire rw_bus_ack,  // 仲裁器授权使用总线

    // 输出到仲裁器的 SDRAM 引脚信号
    output reg [ 3:0] rw_cmd,       // {cs_n, ras_n, cas_n, we_n}
    output reg [12:0] rw_addr_out,  // 驱动 SDRAM 的地址总线
    output reg [ 1:0] rw_ba,        // 驱动 SDRAM 的 Bank 地址
    output reg [ 1:0] rw_dqm,       // 数据掩码
    output reg        rw_cke,       // 时钟有效
    output reg        data_out_en   // 通知 PHY 输出使能 (三态门方向)
);

    // 工作状态机定义 (符合 sdram_cmd_def.vh 约定)
    reg [ 3:0] state;
    reg [ 3:0] next_state;

    reg [ 9:0] cnt_clk;
    reg        rd_or_wr;  // 0: 写操作; 1: 读操作
    reg [23:0] cur_addr;
    reg [ 9:0] cur_len;
    reg        last_rw;  // 记录上次执行的操作 (0: 写, 1: 读)，用于读写交替优先级裁决

    assign rw_busy = (state != `W_IDLE) || rw_bus_req;

    // 读写交替优先级裁决与总线请求生成
    // 原则:
    // 1. 同时出现读、写请求时：若上次是读则本次执行写，若上次是写则本次执行读；
    // 2. 仅单边有请求时：有什么请求就执行什么操作。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rw_bus_req <= 1'b0;
            rd_or_wr   <= 1'b0;
            cur_addr   <= 24'd0;
            cur_len    <= 10'd0;
            last_rw    <= 1'b1;  // 复位默认置 1，若首次同时到来优先执行写
        end else if (init_done && (state == `W_IDLE)) begin
            case ({
                wr_req, rd_req
            })
                2'b11: begin
                    // 读写请求同时有效：按交替原则轮流切换
                    rw_bus_req <= 1'b1;
                    if (last_rw == 1'b0) begin
                        // 上次执行了写操作，本次执行读操作
                        rd_or_wr <= 1'b1;
                        cur_addr <= rd_addr;
                        cur_len  <= rd_len;
                        last_rw  <= 1'b1;
                    end else begin
                        // 上次执行了读操作，本次执行写操作
                        rd_or_wr <= 1'b0;
                        cur_addr <= wr_addr;
                        cur_len  <= wr_len;
                        last_rw  <= 1'b0;
                    end
                end

                2'b10: begin
                    // 仅有写请求
                    rw_bus_req <= 1'b1;
                    rd_or_wr   <= 1'b0;
                    cur_addr   <= wr_addr;
                    cur_len    <= wr_len;
                    last_rw    <= 1'b0;
                end

                2'b01: begin
                    // 仅有读请求
                    rw_bus_req <= 1'b1;
                    rd_or_wr   <= 1'b1;
                    cur_addr   <= rd_addr;
                    cur_len    <= rd_len;
                    last_rw    <= 1'b1;
                end

                default: begin
                    rw_bus_req <= 1'b0;
                end
            endcase
        end else if (rw_bus_ack && (state == `W_ACTIVE)) begin
            rw_bus_req <= 1'b0;  // 已经拿到总线并进入激活状态，撤销请求
        end
    end

    // 时钟计数器 (各阶段延时及突发长度计数)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cnt_clk <= 10'd0;
        else
            case (state)
                `W_ACTIVE: cnt_clk <= 10'd0;
                `W_TRCD: cnt_clk <= (`end_trcd) ? 10'd0 : cnt_clk + 1'b1;
                `W_CL: cnt_clk <= (`end_tcl) ? 10'd0 : cnt_clk + 1'b1;
                `W_RD: cnt_clk <= (cnt_clk == cur_len + 10'd2) ? 10'd0 : cnt_clk + 1'b1;
                `W_WD: cnt_clk <= (cnt_clk == cur_len - 10'd1) ? 10'd0 : cnt_clk + 1'b1;
                `W_TWR: cnt_clk <= (`end_twr) ? 10'd0 : cnt_clk + 1'b1;
                `W_TRP: cnt_clk <= (`end_trp) ? 10'd0 : cnt_clk + 1'b1;
                default: cnt_clk <= 10'd0;
            endcase
    end

    // 状态转移逻辑
    always @(*) begin
        case (state)
            `W_IDLE: begin
                if (rw_bus_ack) next_state = `W_ACTIVE;
                else next_state = `W_IDLE;
            end

            `W_ACTIVE: next_state = `W_TRCD;

            `W_TRCD: begin
                if (cnt_clk == TRCD_CLK - 1) next_state = rd_or_wr ? `W_READ : `W_WRITE;
                else next_state = `W_TRCD;
            end

            // 读支路
            `W_READ: next_state = `W_CL;

            `W_CL: begin
                if (cnt_clk == TCL_CLK - 1) next_state = `W_RD;
                else next_state = `W_CL;
            end

            `W_RD: begin
                if (cnt_clk == cur_len + 10'd2) next_state = `W_PRE;
                else next_state = `W_RD;
            end

            // 写支路
            `W_WRITE: next_state = `W_WD;

            `W_WD: begin
                if (cnt_clk == cur_len - 10'd1) next_state = `W_TWR;
                else next_state = `W_WD;
            end

            `W_TWR: begin
                if (cnt_clk == TWR_CLK) next_state = `W_PRE;
                else next_state = `W_TWR;
            end

            // 统一收尾预充电
            `W_PRE: next_state = `W_TRP;

            `W_TRP: begin
                if (cnt_clk == TRP_CLK) next_state = `W_IDLE;
                else next_state = `W_TRP;
            end

            default: next_state = `W_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= `W_IDLE;
        else state <= next_state;
    end

    // 读写应答信号逻辑 (配合 FIFO 握手)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ack  <= 1'b0;
            rd_ack  <= 1'b0;
            rw_done <= 1'b0;
        end else begin
            // 写响应：在 W_WRITE 及 W_WD 期间从写 FIFO 取出数据 (提前1拍)
            wr_ack  <= ((state == `W_TRCD && next_state == `W_WRITE) ||
                  (state == `W_WRITE) ||
                  (state == `W_WD && cnt_clk < cur_len - 10'd2));

            // 读响应：在 W_RD 期间从 SDRAM 接收有效数据打入读 FIFO (提前对齐首个突发数据)
            rd_ack <= (state == `W_RD && cnt_clk < cur_len);

            // 操作完成指示脉冲
            rw_done <= (state == `W_TRP && next_state == `W_IDLE);
        end
    end

    // 命令与物理地址总线驱动
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {rw_cke, rw_cmd} <= `CMD_INIT;
            rw_addr_out      <= 13'h1FFF;
            rw_ba            <= 2'b11;
            rw_dqm           <= 2'b11;
            data_out_en      <= 1'b0;
        end else begin
            rw_cke <= 1'b1;
            rw_dqm <= 2'b00;

            case (next_state)
                `W_ACTIVE: begin
                    {rw_cke, rw_cmd} <= `CMD_ACTIVE;
                    rw_ba            <= cur_addr[23:22];
                    rw_addr_out      <= cur_addr[21:9];  // 行地址
                    data_out_en      <= 1'b0;
                end

                `W_READ: begin
                    {rw_cke, rw_cmd} <= `CMD_READ;
                    rw_ba            <= cur_addr[23:22];
                    rw_addr_out      <= {4'b0000, cur_addr[8:0]};  // 列地址
                    data_out_en      <= 1'b0;
                end

                `W_RD: begin
                    if (cnt_clk == cur_len - 10'd3) begin
                        {rw_cke, rw_cmd} <= `CMD_B_STOP;  // 提前3拍发读突发终止
                    end else begin
                        {rw_cke, rw_cmd} <= `CMD_NOP;
                    end
                    rw_ba       <= 2'b11;
                    rw_addr_out <= 13'h1FFF;
                    data_out_en <= 1'b0;
                end

                `W_WRITE: begin
                    {rw_cke, rw_cmd} <= `CMD_WRITE;
                    rw_ba            <= cur_addr[23:22];
                    rw_addr_out      <= {4'b0000, cur_addr[8:0]};  // 列地址
                    data_out_en      <= 1'b1;  // 启动写数据输出使能
                end

                `W_WD: begin
                    {rw_cke, rw_cmd} <= `CMD_NOP;
                    rw_ba       <= 2'b11;
                    rw_addr_out <= 13'h1FFF;
                    data_out_en <= 1'b1;
                end

                `W_TWR: begin
                    if (state == `W_WD) begin
                        {rw_cke, rw_cmd} <= `CMD_B_STOP;  // 在进入 W_TWR 的首拍精确发出写突发终止
                    end else begin
                        {rw_cke, rw_cmd} <= `CMD_NOP;
                    end
                    rw_ba       <= 2'b11;
                    rw_addr_out <= 13'h1FFF;
                    data_out_en <= 1'b0;
                end

                `W_PRE: begin
                    {rw_cke, rw_cmd} <= `CMD_PRGE;
                    rw_ba            <= cur_addr[23:22];
                    rw_addr_out      <= 13'h0400;  // A10=1: 全/当前 Bank 预充电
                    data_out_en      <= 1'b0;
                end

                default: begin
                    {rw_cke, rw_cmd} <= `CMD_NOP;
                    rw_ba            <= 2'b11;
                    rw_addr_out      <= 13'h1FFF;
                    data_out_en      <= 1'b0;
                end
            endcase
        end
    end

endmodule
