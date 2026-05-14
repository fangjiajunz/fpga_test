module seg_led (
    input clk,      // 时钟信号 (50MHz)
    input rst_n,    // 复位信号（低有效）
    input add_flag, // 数码管变化的通知信号

    output reg [5:0] seg_sel,  // 数码管位选 (低电平有效)
    output reg [7:0] seg_led   // 数码管段选 (低电平有效)
);

    // 参数定义
    parameter SCAN_MAX = 25'd120_000;  // 1ms @ 50MHz

    // 内部寄存器与线网
    reg [23:0] disp_data;
    reg [25:0] scan_cnt;
    reg [2:0] scan_idx;

    reg add_flag_d1;  // 用于提取 add_flag 边沿
    wire add_flag_edge;


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            add_flag_d1 <= 1'b0;
        end else begin
            add_flag_d1 <= add_flag;
        end
    end
    assign add_flag_edge = add_flag && !add_flag_d1;  // 仅上升沿有效


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            disp_data <= 24'h000000;
        end else if (add_flag_edge) begin
            if (disp_data[3:0] < 4'd9) disp_data[3:0] <= disp_data[3:0] + 1'b1;
            else begin
                disp_data[3:0] <= 4'd0;
                if (disp_data[7:4] < 4'd9) disp_data[7:4] <= disp_data[7:4] + 1'b1;
                else begin
                    disp_data[7:4] <= 4'd0;
                    if (disp_data[11:8] < 4'd9) disp_data[11:8] <= disp_data[11:8] + 1'b1;
                    else begin
                        disp_data[11:8] <= 4'd0;
                        if (disp_data[15:12] < 4'd9) disp_data[15:12] <= disp_data[15:12] + 1'b1;
                        else begin
                            disp_data[15:12] <= 4'd0;
                            if (disp_data[19:16] < 4'd9) disp_data[19:16] <= disp_data[19:16] + 1'b1;
                            else begin
                                disp_data[19:16] <= 4'd0;
                                if (disp_data[23:20] < 4'd9) disp_data[23:20] <= disp_data[23:20] + 1'b1;
                                else disp_data[23:20] <= 4'd0;  // 溢出清零
                            end
                        end
                    end
                end
            end
        end
    end


    wire [3:0] display_dig[5:0];

    // 个位永远显示
    assign display_dig[0] = disp_data[3:0];
    // 高位判断：如果当前位及其以上所有高位全为 0，则置为 4'hF (熄灭)
    assign display_dig[1] = (disp_data[23:4] == 20'd0) ? 4'hF : disp_data[7:4];
    assign display_dig[2] = (disp_data[23:8] == 16'd0) ? 4'hF : disp_data[11:8];
    assign display_dig[3] = (disp_data[23:12] == 12'd0) ? 4'hF : disp_data[15:12];
    assign display_dig[4] = (disp_data[23:16] == 8'd0) ? 4'hF : disp_data[19:16];
    assign display_dig[5] = (disp_data[23:20] == 4'd0) ? 4'hF : disp_data[23:20];


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= 16'd0;
            scan_idx <= 3'd0;
        end else begin
            if (scan_cnt >= SCAN_MAX - 1) begin
                scan_cnt <= 25'd0;
                scan_idx <= (scan_idx == 3'd5) ? 3'd0 : scan_idx + 1'b1;
            end else begin
                scan_cnt <= scan_cnt + 1'b1;
            end
        end
    end


    reg [3:0] current_num;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seg_sel <= 6'b11_1111;  // 复位时不选通任何位数码管
            seg_led <= 8'b1111_1111;  // 复位时全灭
        end else begin

            seg_sel     <= ~(6'b000001 << scan_idx);

            // 获取当前要显示的 4bit 数据
            current_num <= display_dig[scan_idx];

            // 生成段选信号
            case (current_num)
                4'h0: seg_led <= 8'b1100_0000;
                4'h1: seg_led <= 8'b1111_1001;
                4'h2: seg_led <= 8'b1010_0100;
                4'h3: seg_led <= 8'b1011_0000;
                4'h4: seg_led <= 8'b1001_1001;
                4'h5: seg_led <= 8'b1001_0010;
                4'h6: seg_led <= 8'b1000_0010;
                4'h7: seg_led <= 8'b1111_1000;
                4'h8: seg_led <= 8'b1000_0000;
                4'h9: seg_led <= 8'b1001_0000;
                default: seg_led <= 8'b1111_1111;  // 包含 4'hF (熄灭)
            endcase
        end
    end

endmodule
