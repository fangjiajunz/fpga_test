module rd_id (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] lcd_rgb,
    output reg  [15:0] lcd_id
);

    // 复位后从 LCD RGB 模式引脚读取一次 LCD ID：
    // M2 = B7，M1 = G7，M0 = R7。
    reg rd_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_done <= 1'b0;
            lcd_id  <= 16'h4342;
        end else if (!rd_done) begin
            rd_done <= 1'b1;
            case ({lcd_rgb[4], lcd_rgb[10], lcd_rgb[15]})
                3'b000:  lcd_id <= 16'h4342;  // 4.3 寸，480x272
                3'b001:  lcd_id <= 16'h7084;  // 7 寸，800x480
                3'b010:  lcd_id <= 16'h7016;  // 7 寸，1024x600
                3'b100:  lcd_id <= 16'h4384;  // 4.3 寸，800x480
                3'b101:  lcd_id <= 16'h1018;  // 10.1 寸，1280x800
                default: lcd_id <= 16'h4342;
            endcase
        end
    end

endmodule
