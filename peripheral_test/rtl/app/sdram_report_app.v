// ==============================================================================
// 模块名称 : sdram_report_app
// 模块功能 : SDRAM 自检结果 ASCII 串口格式化上报模块 (工作在 50MHz 系统时钟域)
//   - 捕获来自 100MHz SDRAM 时钟域的测试完成脉冲 (Toggle CDC)
//   - 动态将测试结果 (PASS / FAIL、错误计数、期望值与实际读回值) 编码为 ASCII 文本
//   - 接入串口 TX 仲裁器输出到 PC 串口终端 (115200 / 2000000 bps)
// ==============================================================================

`timescale 1ns / 1ps

module sdram_report_app (
    input  wire        clk,            // 50MHz 系统时钟
    input  wire        rst_n,          // 全局复位 (低电平有效)

    // 来自 100MHz SDRAM 测试域的信号
    input  wire        done_toggle,    // 测试完成翻转信号
    input  wire        test_pass,      // 测试通过指示
    input  wire [15:0] error_cnt,      // 错误计数
    input  wire [15:0] first_exp_data, // 首个出错数据的期望值
    input  wire [15:0] first_rd_data,  // 首个出错数据的实际读回值

    // 串口发送接口 (去往 TX 仲裁器)
    output reg  [7:0]  tx_data,
    output reg         tx_wrreq,
    input  wire        tx_full
);

    // -------------------------------------------------------------------------
    // 1. 跨时钟域 (CDC) 脉冲同步器
    // -------------------------------------------------------------------------
    reg done_toggle_r1, done_toggle_r2, done_toggle_r3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_toggle_r1 <= 1'b0;
            done_toggle_r2 <= 1'b0;
            done_toggle_r3 <= 1'b0;
        end else begin
            done_toggle_r1 <= done_toggle;
            done_toggle_r2 <= done_toggle_r1;
            done_toggle_r3 <= done_toggle_r2;
        end
    end

    wire start_report = (done_toggle_r2 ^ done_toggle_r3);

    // -------------------------------------------------------------------------
    // 2. 状态机与报文寄存器
    // -------------------------------------------------------------------------
    localparam ST_IDLE = 2'd0;
    localparam ST_SEND = 2'd1;

    reg [1:0]  state;
    reg [5:0]  tx_idx;
    reg [5:0]  tx_len;
    reg        test_pass_r;
    reg [15:0] error_cnt_r;
    reg [15:0] exp_data_r;
    reg [15:0] rd_data_r;
    reg [7:0]  rom_char;

    // 4 位十六进制转 ASCII 字符函数
    function [7:0] hex2ascii;
        input [3:0] hex;
        begin
            if (hex < 4'd10)
                hex2ascii = 8'h30 + hex; // "0" + hex
            else
                hex2ascii = 8'h37 + hex; // "A" - 10 + hex (0xA -> 0x41)
        end
    endfunction

    // -------------------------------------------------------------------------
    // 3. 组合逻辑字符查表 (纯无锁组合生成)
    // -------------------------------------------------------------------------
    always @(*) begin
        rom_char = 8'h20; // 默认空格

        if (test_pass_r) begin
            // 文本: "\r\n[SDRAM] INIT=OK, WRITE=OK, READ=OK -> PASS!\r\n" (47 字节, idx: 0..46)
            case (tx_idx)
                6'd0:  rom_char = 8'h0D; // \r
                6'd1:  rom_char = 8'h0A; // \n
                6'd2:  rom_char = "[";
                6'd3:  rom_char = "S";
                6'd4:  rom_char = "D";
                6'd5:  rom_char = "R";
                6'd6:  rom_char = "A";
                6'd7:  rom_char = "M";
                6'd8:  rom_char = "]";
                6'd9:  rom_char = " ";
                6'd10: rom_char = "I";
                6'd11: rom_char = "N";
                6'd12: rom_char = "I";
                6'd13: rom_char = "T";
                6'd14: rom_char = "=";
                6'd15: rom_char = "O";
                6'd16: rom_char = "K";
                6'd17: rom_char = ",";
                6'd18: rom_char = " ";
                6'd19: rom_char = "W";
                6'd20: rom_char = "R";
                6'd21: rom_char = "I";
                6'd22: rom_char = "T";
                6'd23: rom_char = "E";
                6'd24: rom_char = "=";
                6'd25: rom_char = "O";
                6'd26: rom_char = "K";
                6'd27: rom_char = ",";
                6'd28: rom_char = " ";
                6'd29: rom_char = "R";
                6'd30: rom_char = "E";
                6'd31: rom_char = "A";
                6'd32: rom_char = "D";
                6'd33: rom_char = "=";
                6'd34: rom_char = "O";
                6'd35: rom_char = "K";
                6'd36: rom_char = " ";
                6'd37: rom_char = "-";
                6'd38: rom_char = ">";
                6'd39: rom_char = " ";
                6'd40: rom_char = "P";
                6'd41: rom_char = "A";
                6'd42: rom_char = "S";
                6'd43: rom_char = "S";
                6'd44: rom_char = "!";
                6'd45: rom_char = 8'h0D; // \r
                6'd46: rom_char = 8'h0A; // \n
                default: rom_char = 8'h20;
            endcase
        end else begin
            // 文本: "\r\n[SDRAM] FAIL! ERR:XXXX, EXP:XXXX, RD:XXXX\r\n" (45 字节, idx: 0..44)
            case (tx_idx)
                6'd0:  rom_char = 8'h0D; // \r
                6'd1:  rom_char = 8'h0A; // \n
                6'd2:  rom_char = "[";
                6'd3:  rom_char = "S";
                6'd4:  rom_char = "D";
                6'd5:  rom_char = "R";
                6'd6:  rom_char = "A";
                6'd7:  rom_char = "M";
                6'd8:  rom_char = "]";
                6'd9:  rom_char = " ";
                6'd10: rom_char = "F";
                6'd11: rom_char = "A";
                6'd12: rom_char = "I";
                6'd13: rom_char = "L";
                6'd14: rom_char = "!";
                6'd15: rom_char = " ";
                6'd16: rom_char = "E";
                6'd17: rom_char = "R";
                6'd18: rom_char = "R";
                6'd19: rom_char = ":";
                6'd20: rom_char = hex2ascii(error_cnt_r[15:12]);
                6'd21: rom_char = hex2ascii(error_cnt_r[11:8]);
                6'd22: rom_char = hex2ascii(error_cnt_r[7:4]);
                6'd23: rom_char = hex2ascii(error_cnt_r[3:0]);
                6'd24: rom_char = ",";
                6'd25: rom_char = " ";
                6'd26: rom_char = "E";
                6'd27: rom_char = "X";
                6'd28: rom_char = "P";
                6'd29: rom_char = ":";
                6'd30: rom_char = hex2ascii(exp_data_r[15:12]);
                6'd31: rom_char = hex2ascii(exp_data_r[11:8]);
                6'd32: rom_char = hex2ascii(exp_data_r[7:4]);
                6'd33: rom_char = hex2ascii(exp_data_r[3:0]);
                6'd34: rom_char = ",";
                6'd35: rom_char = " ";
                6'd36: rom_char = "R";
                6'd37: rom_char = "D";
                6'd38: rom_char = ":";
                6'd39: rom_char = hex2ascii(rd_data_r[15:12]);
                6'd40: rom_char = hex2ascii(rd_data_r[11:8]);
                6'd41: rom_char = hex2ascii(rd_data_r[7:4]);
                6'd42: rom_char = hex2ascii(rd_data_r[3:0]);
                6'd43: rom_char = 8'h0D; // \r
                6'd44: rom_char = 8'h0A; // \n
                default: rom_char = 8'h20;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 4. 发送时序控制
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            tx_idx      <= 6'd0;
            tx_len      <= 6'd0;
            tx_data     <= 8'h00;
            tx_wrreq    <= 1'b0;
            test_pass_r <= 1'b0;
            error_cnt_r <= 16'd0;
            exp_data_r  <= 16'd0;
            rd_data_r   <= 16'd0;
        end else begin
            tx_wrreq <= 1'b0;

            case (state)
                ST_IDLE: begin
                    tx_idx <= 6'd0;
                    if (start_report) begin
                        test_pass_r <= test_pass;
                        error_cnt_r <= error_cnt;
                        exp_data_r  <= first_exp_data;
                        rd_data_r   <= first_rd_data;
                        tx_len      <= test_pass ? 6'd47 : 6'd45;
                        state       <= ST_SEND;
                    end
                end

                ST_SEND: begin
                    if (!tx_full) begin
                        tx_data  <= rom_char;
                        tx_wrreq <= 1'b1;
                        if (tx_idx < tx_len - 1'b1) begin
                            tx_idx <= tx_idx + 1'b1;
                        end else begin
                            state  <= ST_IDLE;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
