module uart_tx #(
    parameter UART_BPS = 115200,
    parameter CLK_FREQ = 50_000_000
) (
    input wire sys_clk,
    input wire sys_rst_n,
    input wire [7:0] in_data,
    input wire in_flag,
    output reg tx,
    output wire busy
);
    //计算计数
    localparam BAUD_CNT_MAX = CLK_FREQ / UART_BPS;

    reg [12:0] baud_cnt;
    reg work_en;
    reg bit_flag;
    reg [3:0] bit_cnt;
    reg [7:0] data_reg;

    assign busy = work_en;

    // 计数
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            baud_cnt <= 13'd0;
        end else if (work_en && (baud_cnt != BAUD_CNT_MAX - 1)) begin
            baud_cnt <= baud_cnt + 1'b1;
        end else begin
            baud_cnt <= 13'd0;
        end
    end
    //可以发送标志
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            bit_flag <= 1'b0;
        end else if (baud_cnt == 13'b1) begin
            bit_flag <= 1'b1;
        end else begin
            bit_flag <= 1'b0;
        end
    end
    //可以开始计数
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            work_en <= 1'b0;
        end else if (in_flag && !work_en) begin
            work_en <= 1'b1;
        end else if (bit_flag && (bit_cnt == 4'd9)) begin
            work_en <= 1'b0;
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            data_reg <= 8'd0;
        end else if (in_flag && !work_en) begin
            data_reg <= in_data;
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            bit_cnt <= 4'd0;
        end else if (!work_en) begin
            bit_cnt <= 4'd0;
        end else if (bit_flag) begin
            if (bit_cnt == 4'd9) begin
                bit_cnt <= 4'd0;
            end else begin
                bit_cnt <= bit_cnt + 1'b1;
            end
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            tx <= 1'b1;
        end else if (bit_flag) begin
            case (bit_cnt)
                4'd0: tx <= 1'b0;
                4'd1: tx <= data_reg[0];
                4'd2: tx <= data_reg[1];
                4'd3: tx <= data_reg[2];
                4'd4: tx <= data_reg[3];
                4'd5: tx <= data_reg[4];
                4'd6: tx <= data_reg[5];
                4'd7: tx <= data_reg[6];
                4'd8: tx <= data_reg[7];
                4'd9: tx <= 1'b1;
                default: tx <= 1'b1;
            endcase
        end
    end

endmodule
