`timescale 1ns / 1ps

// ==============================================================================
// 模块名称 : ax_debounce
// 模块功能 : 连续稳定计数滤波按键消抖模块 (纯自包含高精度硬件消抖)
//   1. 外部机械按键异步输入打两拍，彻底消除跨时钟域亚稳态
//   2. 采用连续稳定计数器：当按键输入有任何跳变即清零计数，
//      只有连续保持高电平或低电平达到 DEBOUNCE_MS (默认 20ms) 时状态才生效
//   3. 输出：
//      - btn_out  : 消抖后的稳定电平
//      - btn_edge : 按键按下的单时钟周期脉冲 (下降沿有效)
// ==============================================================================

module ax_debounce #(
    parameter integer CLK_FREQ    = 50_000_000, // 系统工作时钟频率 (Hz)
    parameter integer DEBOUNCE_MS = 20          // 消抖稳定时间 (ms)
) (
    input  wire sys_clk,
    input  wire sys_rst_n,
    input  wire btn_in,                         // 外部机械按键输入

    output reg  btn_out,                        // 消抖后的稳定电平
    output reg  btn_edge                        // 按键按下的单拍脉冲 (下降沿有效)
);

    localparam integer CNT_MAX = (CLK_FREQ / 1000) * DEBOUNCE_MS - 1;

    // 1. 异步信号打两拍消除亚稳态
    reg btn_sync_d0;
    reg btn_sync_d1;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            btn_sync_d0 <= 1'b1;
            btn_sync_d1 <= 1'b1;
        end else begin
            btn_sync_d0 <= btn_in;
            btn_sync_d1 <= btn_sync_d0;
        end
    end

    // 2. 状态变化检测与连续稳定计时器
    // 50MHz 时钟下 20ms 对应 1,000,000 个周期，20位寄存器最大可表示 1,048,575
    reg [19:0] cnt;
    reg        btn_prev;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            cnt      <= 20'd0;
            btn_prev <= 1'b1;
            btn_out  <= 1'b1;
            btn_edge <= 1'b0;
        end else begin
            btn_edge <= 1'b0; // 默认拉低，保证单拍脉冲特性

            // 只要检测到输入有电平跳变，计数器立刻归零重新计时
            if (btn_sync_d1 != btn_prev) begin
                btn_prev <= btn_sync_d1;
                cnt      <= 20'd0;
            end else if (cnt < CNT_MAX) begin
                cnt <= cnt + 1'b1;
            end else begin
                // 连续稳定保持了设定时长 (如 20ms)，状态确认生效
                if (btn_out != btn_prev) begin
                    btn_out  <= btn_prev;
                    btn_edge <= (btn_out == 1'b1 && btn_prev == 1'b0); // 下降沿单拍脉冲
                end
            end
        end
    end

endmodule
