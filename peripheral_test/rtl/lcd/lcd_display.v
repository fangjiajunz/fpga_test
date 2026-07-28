module lcd_display (
    input  wire        lcd_pclk,
    input  wire        rst_n,
    input  wire [10:0] pixel_xpos,
    input  wire [10:0] pixel_ypos,
    input  wire [10:0] h_disp,
    input  wire [10:0] v_disp,
    output reg  [15:0] pixel_data
);

    // RGB565 测试色，用于在 LCD 上显示竖向彩条。
    localparam [15:0] COLOR_WHITE = 16'b11111_111111_11111;
    localparam [15:0] COLOR_BLACK = 16'b00000_000000_00000;
    localparam [15:0] COLOR_RED = 16'b11111_000000_00000;
    localparam [15:0] COLOR_GREEN = 16'b00000_111111_00000;
    localparam [15:0] COLOR_BLUE = 16'b00000_111111_11111;

    wire [10:0] bar_width;

    assign bar_width = h_disp / 5;

    // 在有效显示区域内绘制五等分彩条。
    always @(posedge lcd_pclk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_data <= COLOR_BLACK;
        end else if (pixel_ypos >= v_disp) begin
            pixel_data <= COLOR_BLACK;
        end else if (pixel_xpos < 10 && pixel_ypos < 10) begin
            pixel_data <= COLOR_WHITE;
        end else begin
            pixel_data <= COLOR_BLACK;
        end
    end

endmodule
