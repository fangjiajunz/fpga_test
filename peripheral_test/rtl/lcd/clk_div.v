module clk_div (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] lcd_id,
    output reg         lcd_pclk
);

    // 根据 LCD 型号生成对应的像素时钟。
    // 板载时钟为 50MHz，小尺寸屏使用分频时钟。
    reg clk_25m;
    reg clk_12_5m;
    reg div_4_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_25m <= 1'b0;
        end else begin
            clk_25m <= ~clk_25m;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_4_cnt <= 1'b0;
            clk_12_5m <= 1'b0;
        end else begin
            div_4_cnt <= div_4_cnt + 1'b1;
            if (div_4_cnt) begin
                clk_12_5m <= ~clk_12_5m;
            end
        end
    end

    always @(*) begin
        // 根据 LCD ID 选择像素时钟，未知 ID 默认按 480x272 处理。
        case (lcd_id)
            16'h4342: lcd_pclk = clk_12_5m;  // 480x272
            16'h7084: lcd_pclk = clk_25m;    // 800x480
            16'h7016: lcd_pclk = clk;        // 1024x600
            16'h4384: lcd_pclk = clk_25m;    // 800x480
            16'h1018: lcd_pclk = clk;        // 1280x800
            default:  lcd_pclk = clk_12_5m;
        endcase
    end

endmodule
