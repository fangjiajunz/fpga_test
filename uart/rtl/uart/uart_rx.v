module uart_rx #(
    parameter UART_BPS = 115200,
    parameter CLK_FREQ = 50_000_000
) (
    input wire sys_clk,  //系统时钟 50MHz
    input wire sys_rst_n,  //全局复位
    input wire rx,  //串口接收数据

    output reg [7:0] po_data,  //串转并后的 8bit 数据
    output reg out_flag  //串转并后的数据有效标志信号

);
    localparam BAUD_CNT_MAX = CLK_FREQ / UART_BPS;
    reg [12:0] baud_cnt;
    wire start_nedge;

    reg work_en;
    reg bit_flag;
    reg [3:0] bit_cnt;
    reg [7:0] data_reg;
    reg _rx_reg_1;
    reg _rx_reg_2;
    reg _rx_reg_3;


    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            work_en <= 1'd0;
        end else if (start_nedge && (bit_cnt == 4'd9)) begin
            work_en <= 1'd1;
        end else begin
            work_en <= 1'd0;
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            baud_cnt <= 13'd0;
        end else if (work_en && (baud_cnt != BAUD_CNT_MAX - 1)) begin
            baud_cnt <= baud_cnt + 1'b1;
        end else begin
            baud_cnt <= 13'd0;
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            _rx_reg_1 <= 1'd1;
            _rx_reg_2 <= 1'd1;
            _rx_reg_3 <= 1'd1;
        end else begin
            _rx_reg_1 <= rx;
            _rx_reg_2 <= _rx_reg_1;
            _rx_reg_3 <= _rx_reg_2;
        end
    end
    // 当上一拍是 1，且当前拍变成 0 时，说明出现了起始位的下降沿
    assign start_nedge = _rx_reg_3 & ~_rx_reg_2;
    //可以采样的标志位
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            bit_flag <= 1'b0;
        end else if (baud_cnt == BAUD_CNT_MAX / 2 - 1) begin
            bit_flag <= 1'b1;
        end else begin
            bit_flag <= 1'b0;
        end
    end


endmodule
