`timescale 1ns / 1ps

// ==============================================================================
// 模块名称 : rst_sync
// 模块功能 : 通用异步复位、同步释放同步器
//   - 支持多级触发器级联 (默认 2 级)
//   - 支持外接使能信号 (如 PLL locked 标志)
// ==============================================================================

module rst_sync #(
    parameter integer STAGES = 2
) (
    input  wire clk,
    input  wire async_rst_n,
    input  wire ext_en,      // 扩展使能信号 (如 pll_locked，低电平保持复位)
    output wire sync_rst_n
);

    reg [STAGES-1:0] sync_reg;

    always @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            sync_reg <= {STAGES{1'b0}};
        end else if (!ext_en) begin
            sync_reg <= {STAGES{1'b0}};
        end else begin
            sync_reg <= {sync_reg[STAGES-2:0], 1'b1};
        end
    end

    assign sync_rst_n = sync_reg[STAGES-1];

endmodule
