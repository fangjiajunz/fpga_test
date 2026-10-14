`timescale 1ns / 1ps
`include "sdram_cmd_def.vh"

module sdram_arbiter (
    input wire clk,
    input wire rst_n,

    // 1. 初始化通道 (来自 sdram_init, 绝对最高优先级)
    input wire        init_done,
    input wire [ 3:0] init_cmd,
    input wire [12:0] init_addr,
    input wire [ 1:0] init_ba,
    input wire        init_cke,
    input wire [ 1:0] init_dqm,

    // 2. 刷新通道 (来自 sdram_refresh, 次高优先级)
    input  wire        ref_req,
    output reg         ref_ack,
    input  wire        ref_done,
    input  wire [ 3:0] ref_cmd,
    input  wire [12:0] ref_addr,
    input  wire [ 1:0] ref_ba,
    input  wire        ref_cke,
    input  wire [ 1:0] ref_dqm,

    // 3. 读写通道 (来自 sdram_rw_ctrl, 普通优先级)
    input  wire        rw_bus_req,
    output reg         rw_bus_ack,
    input  wire        rw_done,
    input  wire [ 3:0] rw_cmd,
    input  wire [12:0] rw_addr,
    input  wire [ 1:0] rw_ba,
    input  wire        rw_cke,
    input  wire [ 1:0] rw_dqm,
    input  wire        rw_data_out_en,

    // 4. 仲裁输出 (送往 sdram_phy 物理层)
    output reg [ 3:0] phy_cmd,
    output reg [12:0] phy_addr,
    output reg [ 1:0] phy_ba,
    output reg        phy_cke,
    output reg [ 1:0] phy_dqm,
    output reg        phy_data_out_en
);

    // 仲裁状态定义
    localparam [1:0] S_INIT = 2'd0;  // 独占初始化阶段
    localparam [1:0] S_IDLE = 2'd1;  // 空闲待命与仲裁决策
    localparam [1:0] S_REF = 2'd2;  // 授权自动刷新
    localparam [1:0] S_RW = 2'd3;  // 授权突发读写

    reg [1:0] state;
    reg [1:0] next_state;

    // 状态转移逻辑
    always @(*) begin
        case (state)
            S_INIT: begin
                if (init_done) next_state = S_IDLE;
                else next_state = S_INIT;
            end

            S_IDLE: begin
                // 优先级裁决: 刷新 > 读写
                if (ref_req) next_state = S_REF;
                else if (rw_bus_req) next_state = S_RW;
                else next_state = S_IDLE;
            end

            S_REF: begin
                if (ref_done) next_state = S_IDLE;
                else next_state = S_REF;
            end

            S_RW: begin
                if (rw_done) next_state = S_IDLE;
                else next_state = S_RW;
            end

            default: next_state = S_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_INIT;
        else state <= next_state;
    end

    // 仲裁应答握手信号
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ref_ack    <= 1'b0;
            rw_bus_ack <= 1'b0;
        end else begin
            // 产生单拍授权脉冲
            ref_ack    <= (state == S_IDLE) && (next_state == S_REF);
            rw_bus_ack <= (state == S_IDLE) && (next_state == S_RW);
        end
    end

    // 物理总线多路选择器 (MUX)
    always @(*) begin
        case (state)
            S_INIT: begin
                phy_cmd         = init_cmd;
                phy_addr        = init_addr;
                phy_ba          = init_ba;
                phy_cke         = init_cke;
                phy_dqm         = init_dqm;
                phy_data_out_en = 1'b0;
            end

            S_REF: begin
                phy_cmd         = ref_cmd;
                phy_addr        = ref_addr;
                phy_ba          = ref_ba;
                phy_cke         = ref_cke;
                phy_dqm         = ref_dqm;
                phy_data_out_en = 1'b0;
            end

            S_RW: begin
                phy_cmd         = rw_cmd;
                phy_addr        = rw_addr;
                phy_ba          = rw_ba;
                phy_cke         = rw_cke;
                phy_dqm         = rw_dqm;
                phy_data_out_en = rw_data_out_en;
            end

            default: begin  // S_IDLE
                phy_cmd         = 4'b0111;
                phy_addr        = 13'h1FFF;
                phy_ba          = 2'b11;
                phy_cke         = 1'b1;
                phy_dqm         = 2'b00;
                phy_data_out_en = 1'b0;
            end
        endcase
    end

endmodule
