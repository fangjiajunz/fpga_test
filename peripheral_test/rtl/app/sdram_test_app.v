`timescale 1ns / 1ps

module sdram_test_app #(
    parameter [23:0] TEST_ADDR = 24'h000000,  // 测试读写线性起始地址
    parameter [9:0] TEST_BURST_LEN = 10'd512,  // 突发读写长度 (10个 16-bit 字)
    parameter integer AUTO_START_WAIT = 100_000  // 上电初始化完成后延时约 1ms (100MHz) 自动触发测试
) (
    input wire clk,   // 100MHz SDRAM 控制器工作时钟
    input wire rst_n, // 异步复位同步释放信号

    // 外部控制触发
    input wire btn_trigger,  // 手动重新触发测试脉冲 (1拍高电平脉冲)

    // SDRAM 控制器原生接口 (连接 sdram_top)
    input wire        init_done,  // SDRAM 初始化完成标志
    input wire        rw_busy,    // SDRAM 读写控制器忙标志
    input wire        rw_done,    // 单次突发读写完成脉冲
    input wire        wr_ack,     // 写应答 (提前1拍取数)
    input wire        rd_ack,     // 读数据有效标志
    input wire [15:0] rd_data,    // 读回数据

    output reg         wr_req,   // 突发写请求
    output reg         rd_req,   // 突发读请求
    output reg  [23:0] wr_addr,  // 写起始地址
    output reg  [23:0] rd_addr,  // 读起始地址
    output wire [ 9:0] wr_len,   // 写突发长度
    output wire [ 9:0] rd_len,   // 读突发长度
    output reg  [15:0] wr_data,  // 写入数据流

    // 测试状态与结果指示
    output reg        test_busy,       // 测试正在进行中
    output reg        test_done,       // 测试完成
    output reg        test_pass,       // 测试通过 (读写数据完全一致)
    output reg        test_err,        // 测试失败 (检测到数据不匹配)
    output reg [15:0] error_cnt,       // 错误计数
    output reg [15:0] first_exp_data,  // 首个出错数据的期望值
    output reg [15:0] first_rd_data,   // 首个出错数据的实际读回值
    output reg        done_toggle      // 跨时钟域翻转指示脉冲
);

    assign wr_len = TEST_BURST_LEN;
    assign rd_len = TEST_BURST_LEN;

    // 状态机编码
    localparam [2:0] ST_POWER_WAIT = 3'd0;  // 上电等待初始化完成与稳定期
    localparam [2:0] ST_IDLE = 3'd1;  // 空闲待命
    localparam [2:0] ST_WRITE_REQ = 3'd2;  // 发起突发写请求
    localparam [2:0] ST_WRITE_DATA = 3'd3;  // 流式写入递增特征数据
    localparam [2:0] ST_READ_WAIT = 3'd4;  // 读前短暂缓冲等待
    localparam [2:0] ST_READ_REQ = 3'd5;  // 发起突发读请求
    localparam [2:0] ST_READ_DATA = 3'd6;  // 流式读取并实时核对数据
    localparam [2:0] ST_CHECK = 3'd7;  // 结算测试结果

    reg [ 2:0] state;
    reg [ 2:0] next_state;

    reg [23:0] cnt_wait;
    reg [ 3:0] cnt_gap;
    reg [15:0] expected_data;
    reg        error_latch;

    // 上电延时计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cnt_wait <= 24'd0;
        else if (state == ST_POWER_WAIT) begin
            if (init_done) cnt_wait <= cnt_wait + 1'b1;
        end else cnt_wait <= 24'd0;
    end

    // 读前间隙等待计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cnt_gap <= 4'd0;
        else if (state == ST_READ_WAIT) cnt_gap <= cnt_gap + 1'b1;
        else cnt_gap <= 4'd0;
    end

    // 状态转移逻辑
    always @(*) begin
        case (state)
            ST_POWER_WAIT: begin
                if (init_done && (cnt_wait >= AUTO_START_WAIT)) next_state = ST_WRITE_REQ;
                else next_state = ST_POWER_WAIT;
            end

            ST_IDLE: begin
                if (btn_trigger && init_done && !rw_busy) next_state = ST_WRITE_REQ;
                else next_state = ST_IDLE;
            end

            ST_WRITE_REQ: begin
                if (rw_busy || wr_ack) next_state = ST_WRITE_DATA;
                else next_state = ST_WRITE_REQ;
            end

            ST_WRITE_DATA: begin
                if (rw_done) next_state = ST_READ_WAIT;
                else next_state = ST_WRITE_DATA;
            end

            ST_READ_WAIT: begin
                if (cnt_gap >= 4'd10 && !rw_busy) next_state = ST_READ_REQ;
                else next_state = ST_READ_WAIT;
            end

            ST_READ_REQ: begin
                if (rw_busy || rd_ack) next_state = ST_READ_DATA;
                else next_state = ST_READ_REQ;
            end

            ST_READ_DATA: begin
                if (rw_done) next_state = ST_CHECK;
                else next_state = ST_READ_DATA;
            end

            ST_CHECK: begin
                next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // 业务与时序控制逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_POWER_WAIT;
            wr_req         <= 1'b0;
            rd_req         <= 1'b0;
            wr_addr        <= 24'd0;
            rd_addr        <= 24'd0;
            wr_data        <= 16'd0;
            expected_data  <= 16'd0;
            error_cnt      <= 16'd0;
            error_latch    <= 1'b0;
            test_busy      <= 1'b0;
            test_done      <= 1'b0;
            test_pass      <= 1'b0;
            test_err       <= 1'b0;
            first_exp_data <= 16'h5A01;
            first_rd_data  <= 16'h0000;
            done_toggle    <= 1'b0;
        end else begin
            state <= next_state;

            case (state)
                ST_POWER_WAIT: begin
                    test_busy <= 1'b1;
                    test_done <= 1'b0;
                    test_pass <= 1'b0;
                    test_err  <= 1'b0;
                end

                ST_IDLE: begin
                    test_busy <= 1'b0;
                    wr_req    <= 1'b0;
                    rd_req    <= 1'b0;
                    if (btn_trigger && init_done && !rw_busy) begin
                        test_busy      <= 1'b1;
                        test_done      <= 1'b0;
                        test_pass      <= 1'b0;
                        test_err       <= 1'b0;
                        error_cnt      <= 16'd0;
                        error_latch    <= 1'b0;
                        first_exp_data <= 16'h5A01;
                        first_rd_data  <= 16'h0000;
                    end
                end

                ST_WRITE_REQ: begin
                    test_busy      <= 1'b1;
                    wr_req         <= 1'b1;
                    wr_addr        <= TEST_ADDR;
                    wr_data        <= 16'h5A01;  // 起始写入特征数据
                    error_latch    <= 1'b0;
                    error_cnt      <= 16'd0;
                    first_exp_data <= 16'h5A01;
                    first_rd_data  <= 16'h0000;
                end

                ST_WRITE_DATA: begin
                    wr_req <= 1'b0;  // 受理后撤销写请求
                    // 配合 wr_ack 提前1拍拉取数据的时序，每逢 wr_ack 送出下一个递增数据
                    if (wr_ack) begin
                        wr_data <= wr_data + 1'b1;
                    end
                end

                ST_READ_WAIT: begin
                    wr_req <= 1'b0;
                    rd_req <= 1'b0;
                end

                ST_READ_REQ: begin
                    rd_req        <= 1'b1;
                    rd_addr       <= TEST_ADDR;
                    expected_data <= 16'h5A01;  // 期望第 1 个读回的数据
                end

                ST_READ_DATA: begin
                    rd_req <= 1'b0;  // 受理后撤销读请求
                    // 接收有效读数据并实时比对
                    if (rd_ack) begin
                        if (rd_data != expected_data) begin
                            error_latch <= 1'b1;
                            if (error_cnt == 16'd0) begin
                                first_exp_data <= expected_data;
                                first_rd_data  <= rd_data;
                            end
                            error_cnt <= error_cnt + 1'b1;
                        end
                        expected_data <= expected_data + 1'b1;
                    end
                end

                ST_CHECK: begin
                    test_busy   <= 1'b0;
                    test_done   <= 1'b1;
                    done_toggle <= ~done_toggle;
                    if (error_latch || (error_cnt != 16'd0)) begin
                        test_pass <= 1'b0;
                        test_err  <= 1'b1;
                    end else begin
                        test_pass      <= 1'b1;
                        test_err       <= 1'b0;
                        first_exp_data <= 16'h5A01;
                        first_rd_data  <= 16'h5A01;
                    end
                end
            endcase
        end
    end

endmodule
