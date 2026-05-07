module seg_led (
    input clk,   // 时钟信号 (假设为 50MHz)
    input rst_n, // 复位信号（低有效）

    input            add_flag,  // 数码管变化的通知信号
    output reg [5:0] seg_sel,   // 数码管位选 (低电平有效)
    output reg [7:0] seg_led    // 数码管段选 (低电平有效)
);

    // 参数定义
    // 50MHz 时钟下，50,000 次计数为 1ms。每个数码管点亮 1ms，刷新足够快且不会闪烁。
    parameter SCAN_MAX = 16'd50_000;

    // 寄存器定义
    reg [23:0] disp_data;  // 存储 6 个数码管要显示的数据 (6位 x 4bit)
    reg [15:0] scan_cnt;  // 动态扫描定时器
    reg [ 2:0] scan_idx;  // 当前正在扫描的数码管索引 (0~5)
    reg [ 3:0] current_num;  // 当前数码管需要显示的 4bit 数值

    // ==========================================
    // 1. 数据更新逻辑：当 add_flag 到来时更新数据
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时，假设初始显示 000000
            disp_data <= 24'h000000;
        end else if (add_flag) begin
            // 每次通知信号到达时，整个 24 位十六进制数值加 1 
            // （你也可以改成 BCD 码十进制进位逻辑，这里保留十六进制递增）
            disp_data <= disp_data + 1'b1;
        end
    end

    // ==========================================
    // 2. 动态扫描定时器：产生 1ms 的切换脉冲
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_cnt <= 16'd0;
        end else if (scan_cnt >= SCAN_MAX - 1) begin
            scan_cnt <= 16'd0;
        end else begin
            scan_cnt <= scan_cnt + 1'b1;
        end
    end

    // ==========================================
    // 3. 扫描索引控制：每隔 1ms 切换到下一位数码管
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_idx <= 3'd0;
        end else if (scan_cnt == SCAN_MAX - 1) begin
            if (scan_idx == 3'd5) scan_idx <= 3'd0;
            else scan_idx <= scan_idx + 1'b1;
        end
    end

    // ==========================================
    // 4. 位选和数据多路复用器 (Multiplexer)
    // 根据当前 scan_idx，决定拉低哪个位选，并取出对应的数据
    // ==========================================
    always @(*) begin
        case (scan_idx)
            3'd0: begin
                seg_sel     = 6'b111110;
                current_num = disp_data[3:0];
            end
            3'd1: begin
                seg_sel     = 6'b111101;
                current_num = disp_data[7:4];
            end
            3'd2: begin
                seg_sel     = 6'b111011;
                current_num = disp_data[11:8];
            end
            3'd3: begin
                seg_sel     = 6'b110111;
                current_num = disp_data[15:12];
            end
            3'd4: begin
                seg_sel     = 6'b101111;
                current_num = disp_data[19:16];
            end
            3'd5: begin
                seg_sel     = 6'b011111;
                current_num = disp_data[23:20];
            end
            default: begin
                seg_sel     = 6'b111111;
                current_num = 4'h0;
            end
        endcase
    end

    // ==========================================
    // 5. 段选译码器：将 current_num 转换为段选信号输出
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seg_led <= 8'b1111_1111;  // 复位时全灭 (假设低电平点亮)
        end else begin
            case (current_num)
                4'h0: seg_led <= 8'b1100_0000;  // 共阳极，0点亮
                4'h1: seg_led <= 8'b1111_1001;
                4'h2: seg_led <= 8'b1010_0100;
                4'h3: seg_led <= 8'b1011_0000;
                4'h4: seg_led <= 8'b1001_1001;
                4'h5: seg_led <= 8'b1001_0010;
                4'h6: seg_led <= 8'b1000_0010;
                4'h7: seg_led <= 8'b1111_1000;
                4'h8: seg_led <= 8'b1000_0000;
                4'h9: seg_led <= 8'b1001_0000;
                4'ha: seg_led <= 8'b1000_1000;
                4'hb: seg_led <= 8'b1000_0011;
                4'hc: seg_led <= 8'b1100_0110;
                4'hd: seg_led <= 8'b1010_0001;
                4'he: seg_led <= 8'b1000_0110;
                4'hf: seg_led <= 8'b1000_1110;
                default: seg_led <= 8'b1111_1111;
            endcase
        end
    end

endmodule
