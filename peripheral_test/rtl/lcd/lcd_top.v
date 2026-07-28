module lcd_top (
    input wire clk,   // 50MHz 系统时钟
    input wire rst_n, // 全局复位，低有效

    output wire        lcd_bl,   // 背光控制
    output wire        lcd_clk,  // 像素时钟
    output wire        lcd_rst,  // LCD 复位，低有效
    output wire        lcd_de,   // 数据使能
    output wire        lcd_hs,   // 行同步
    output wire        lcd_vs,   // 场同步
    inout  wire [15:0] lcd_rgb   // RGB565 数据
);

    // ======================================================
    // 模块间互联信号
    // ======================================================
    wire        lcd_pclk;  // clk_div 生成的像素时钟
    wire [15:0] lcd_id;  // rd_id 识别出的屏幕型号
    wire [15:0] pixel_data;  // lcd_display 产生的像素数据
    wire [10:0] pixel_xpos;  // 当前请求像素的列坐标
    wire [10:0] pixel_ypos;  // 当前请求像素的行坐标
    wire [10:0] h_disp;  // 有效显示区宽度
    wire [10:0] v_disp;  // 有效显示区高度
    wire        data_req;  // driver 输出，本封装内部不外接
    wire [15:0] lcd_rgb_o;  // FPGA 输出到屏的像素数据
    wire [15:0] lcd_rgb_i;  // 从 lcd_rgb 总线读回的数据（用于读 ID）

    // ======================================================
    // lcd_rgb 双向切换（参考正点原子 25_lcd_rgb_colorbar）：
    // 显示期 lcd_de=1 时输出像素数据；非显示期置为高阻，
    // 让屏端 M0/M1/M2(R7/G7/B7) 上下拉电平显现，供 rd_id 读取
    // ======================================================
    assign lcd_rgb   = lcd_de ? lcd_rgb_o : {16{1'bz}};
    assign lcd_rgb_i = lcd_rgb;

    // ======================================================
    // 像素时钟分频：根据 lcd_id 由 50MHz 分频出 lcd_pclk
    // ======================================================
    clk_div u_clk_div (
        .clk     (clk),
        .rst_n   (rst_n),
        .lcd_id  (lcd_id),
        .lcd_pclk(lcd_pclk)
    );

    // ======================================================
    // 读取 LCD ID：输入取自 lcd_rgb 总线（非显示期反映屏端 M0/M1/M2 电平）
    // ======================================================
    rd_id u_rd_id (
        .clk    (clk),
        .rst_n  (rst_n),
        .lcd_rgb(lcd_rgb_i),
        .lcd_id (lcd_id)
    );

    // ======================================================
    // LCD 时序驱动：产生行场时序并输出 RGB 数据
    // ======================================================
    lcd_driver u_lcd_driver (
        .lcd_pclk  (lcd_pclk),
        .rst_n     (rst_n),
        .lcd_id    (lcd_id),
        .pixel_data(pixel_data),
        .pixel_xpos(pixel_xpos),
        .pixel_ypos(pixel_ypos),
        .h_disp    (h_disp),
        .v_disp    (v_disp),
        .data_req  (data_req),
        .lcd_de    (lcd_de),
        .lcd_hs    (lcd_hs),
        .lcd_vs    (lcd_vs),
        .lcd_bl    (lcd_bl),
        .lcd_clk   (lcd_clk),
        .lcd_rst   (lcd_rst),
        .lcd_rgb   (lcd_rgb_o)
    );

    // ======================================================
    // 彩条像素生成：根据坐标输出竖向 5 等分彩条
    // ======================================================
    lcd_display u_lcd_display (
        .lcd_pclk  (lcd_pclk),
        .rst_n     (rst_n),
        .pixel_xpos(pixel_xpos),
        .pixel_ypos(pixel_ypos),
        .h_disp    (h_disp),
        .v_disp    (v_disp),
        .pixel_data(pixel_data)
    );

endmodule
