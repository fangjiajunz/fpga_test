`timescale 1ns / 1ps

// ==============================================================================
// 模块名称 : sdram_test_self
// 模块功能 : 通用 SDRAM 突发读写与硬件数据校验引擎
//   - 外部传入 test_wr_pattern  : 作为突发写起始数据 (随后每拍 +1 连续递增)
//   - 外部传入 test_exp_pattern : 作为突发读期望数据 (每拍 +1 实时比对)
//   - 读回数据完全匹配时拉高 test_pass，有任何不匹配时拉高 test_err
//   - last_rd_data 实时输出最新读回的数据供顶层消费
// ==============================================================================

module sdram_test_self (
    input wire clk,   // 必须接 100MHz ref_clk
    input wire rst_n, // 同步复位

    // 用户操作触发信号与配置数据
    input wire        do_write_trig,     // 触发一次写
    input wire        do_read_trig,      // 触发一次读
    input wire [23:0] target_addr,       // 目标起始地址
    input wire [ 9:0] target_len,        // 读写长度 (如 256)
    input wire [15:0] test_wr_pattern,   // 顶层指定的写起始数据
    input wire [15:0] test_exp_pattern,  // 顶层指定的期望读回比对数据

    // 直连 sdram_top 接口
    input wire        init_done,
    input wire        rw_busy,
    input wire        rw_done,
    input wire        wr_ack,
    input wire        rd_ack,
    input wire [15:0] rd_data,

    output reg         wr_req,
    output reg         rd_req,
    output reg  [23:0] wr_addr,
    output reg  [23:0] rd_addr,
    output wire [ 9:0] wr_len,
    output wire [ 9:0] rd_len,
    output reg  [15:0] wr_data,

    // 校验结果与读出数据输出
    output reg        test_pass,         // 校验完全匹配成功指示
    output reg        test_err,          // 校验出错指示
    output reg [15:0] last_rd_data       // 锁存最后一次读回的数据
);

    assign wr_len = target_len;
    assign rd_len = target_len;

    localparam S_IDLE       = 3'd0;
    localparam S_WRITE_REQ  = 3'd1;
    localparam S_WRITE_DATA = 3'd2;
    localparam S_READ_REQ   = 3'd3;
    localparam S_READ_DATA  = 3'd4;
    localparam S_CHECK      = 3'd5;

    reg [2:0]  state;
    reg [15:0] exp_data;    // 期望读回的数据
    reg        err_latch;   // 单次读突发中的错误锁存

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            wr_req       <= 1'b0;
            rd_req       <= 1'b0;
            wr_addr      <= 24'd0;
            rd_addr      <= 24'd0;
            wr_data      <= 16'd0;
            exp_data     <= 16'd0;
            err_latch    <= 1'b0;
            test_pass    <= 1'b0;
            test_err     <= 1'b0;
            last_rd_data <= 16'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    wr_req <= 1'b0;
                    rd_req <= 1'b0;
                    if (init_done && !rw_busy) begin
                        if (do_write_trig) begin
                            wr_req    <= 1'b1;
                            wr_addr   <= target_addr;
                            wr_data   <= test_wr_pattern;  // 使用顶层指定的数据
                            state     <= S_WRITE_REQ;
                        end else if (do_read_trig) begin
                            rd_req    <= 1'b1;
                            rd_addr   <= target_addr;
                            exp_data  <= test_exp_pattern; // 使用顶层指定的比对数据
                            err_latch <= 1'b0;
                            state     <= S_READ_REQ;
                        end
                    end
                end

                // ── 写分支 ──
                S_WRITE_REQ: begin
                    if (wr_ack) begin
                        wr_req  <= 1'b0;
                        wr_data <= wr_data + 1'b1;
                        state   <= S_WRITE_DATA;
                    end
                end

                S_WRITE_DATA: begin
                    if (wr_ack) begin
                        wr_data <= wr_data + 1'b1;
                    end

                    if (rw_done) begin
                        state <= S_IDLE;
                    end
                end

                // ── 读分支 ──
                S_READ_REQ: begin
                    if (rd_ack) begin
                        rd_req       <= 1'b0;
                        last_rd_data <= rd_data;
                        if (rd_data != exp_data) begin
                            err_latch <= 1'b1;
                        end
                        exp_data <= exp_data + 1'b1;
                        state    <= S_READ_DATA;
                    end else if (rw_busy) begin
                        rd_req <= 1'b0;
                    end
                end

                S_READ_DATA: begin
                    if (rd_ack) begin
                        last_rd_data <= rd_data;
                        if (rd_data != exp_data) begin
                            err_latch <= 1'b1;
                        end
                        exp_data <= exp_data + 1'b1;
                    end

                    if (rw_done) begin
                        state <= S_CHECK;
                    end
                end

                // ── 结果结算 ──
                S_CHECK: begin
                    if (err_latch) begin
                        test_pass <= 1'b0;
                        test_err  <= 1'b1;
                    end else begin
                        test_pass <= 1'b1;
                        test_err  <= 1'b0;
                    end
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
