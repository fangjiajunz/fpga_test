// ==============================================================================
// 模块名称 : uart_tx_arbiter
// 模块功能 : 串口发送通道无锁多路仲裁器
//   - 通道 0: flash_test_app (测试结果上报，高优先级)
//   - 通道 1: uart_app (日常通信或按键数据)
// ==============================================================================

module uart_tx_arbiter (
    input  wire       clk,
    input  wire       rst_n,

    // 通道 0: flash_test_app (Flash 自检报告，最高优先级)
    input  wire [7:0] ch0_data,
    input  wire       ch0_wrreq,

    // 通道 1: sdram_report_app (SDRAM 自检报告，次高优先级)
    input  wire [7:0] ch1_data,
    input  wire       ch1_wrreq,

    // 通道 2: uart_app (日常业务通信 / 按键上报，普通优先级)
    input  wire [7:0] ch2_data,
    input  wire       ch2_wrreq,

    // 输出至 uart_core TX FIFO
    output reg  [7:0] tx_data,
    output reg        tx_wrreq
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_data  <= 8'h00;
            tx_wrreq <= 1'b0;
        end else begin
            if (ch0_wrreq) begin
                tx_data  <= ch0_data;
                tx_wrreq <= 1'b1;
            end else if (ch1_wrreq) begin
                tx_data  <= ch1_data;
                tx_wrreq <= 1'b1;
            end else if (ch2_wrreq) begin
                tx_data  <= ch2_data;
                tx_wrreq <= 1'b1;
            end else begin
                tx_data  <= 8'h00;
                tx_wrreq <= 1'b0;
            end
        end
    end

endmodule
