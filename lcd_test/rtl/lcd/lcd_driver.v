module lcd_driver (
    input  wire        lcd_pclk,    // 像素时钟（由 clk_div 提供）
    input  wire        rst_n,       // 全局复位，低有效
    input  wire [15:0] lcd_id,      // LCD 屏幕 ID，决定使用哪套时序参数
    input  wire [15:0] pixel_data,  // 来自 lcd_display 的像素数据（RGB565）
    output reg  [10:0] pixel_xpos,  // 输出给 lcd_display 的像素列坐标
    output reg  [10:0] pixel_ypos,  // 输出给 lcd_display 的像素行坐标
    output reg  [10:0] h_disp,      // 水平有效显示区宽度
    output reg  [10:0] v_disp,      // 垂直有效显示区高度
    output reg         data_req,    // 数据请求信号（提前 2 拍）

    output reg         lcd_de,   // 数据使能信号
    output wire        lcd_hs,   // 行同步（DE 模式下恒为高）
    output wire        lcd_vs,   // 场同步（DE 模式下恒为高）
    output wire        lcd_bl,   // 背光控制（恒开启）
    output wire        lcd_clk,  // 像素时钟输出
    output wire        lcd_rst,  // LCD 复位（跟随 rst_n）
    output wire [15:0] lcd_rgb   // RGB565 数据输出
);
    //  |←SYNC→|←BACK→|←──────DISP──────→|←FRONT→|
    // 支持的 RGB LCD 屏幕时序参数。
    // ID 沿用开发板例程格式，例如 4342 表示 4.3 寸 480x272。
    localparam [10:0] H_SYNC_4342 = 11'd41;
    localparam [10:0] H_BACK_4342 = 11'd2;
    localparam [10:0] H_DISP_4342 = 11'd480;
    localparam [10:0] H_TOTAL_4342 = 11'd525;
    localparam [10:0] V_SYNC_4342 = 11'd10;
    localparam [10:0] V_BACK_4342 = 11'd2;
    localparam [10:0] V_DISP_4342 = 11'd272;
    localparam [10:0] V_TOTAL_4342 = 11'd286;

    localparam [10:0] H_SYNC_7084 = 11'd128;
    localparam [10:0] H_BACK_7084 = 11'd88;
    localparam [10:0] H_DISP_7084 = 11'd800;
    localparam [10:0] H_TOTAL_7084 = 11'd1056;
    localparam [10:0] V_SYNC_7084 = 11'd2;
    localparam [10:0] V_BACK_7084 = 11'd33;
    localparam [10:0] V_DISP_7084 = 11'd480;
    localparam [10:0] V_TOTAL_7084 = 11'd525;

    localparam [10:0] H_SYNC_7016 = 11'd20;
    localparam [10:0] H_BACK_7016 = 11'd140;
    localparam [10:0] H_DISP_7016 = 11'd1024;
    localparam [10:0] H_TOTAL_7016 = 11'd1344;
    localparam [10:0] V_SYNC_7016 = 11'd3;
    localparam [10:0] V_BACK_7016 = 11'd20;
    localparam [10:0] V_DISP_7016 = 11'd600;
    localparam [10:0] V_TOTAL_7016 = 11'd635;

    localparam [10:0] H_SYNC_1018 = 11'd10;
    localparam [10:0] H_BACK_1018 = 11'd80;
    localparam [10:0] H_DISP_1018 = 11'd1280;
    localparam [10:0] H_TOTAL_1018 = 11'd1440;
    localparam [10:0] V_SYNC_1018 = 11'd3;
    localparam [10:0] V_BACK_1018 = 11'd10;
    localparam [10:0] V_DISP_1018 = 11'd800;
    localparam [10:0] V_TOTAL_1018 = 11'd823;

    localparam [10:0] H_SYNC_4384 = 11'd128;
    localparam [10:0] H_BACK_4384 = 11'd88;
    localparam [10:0] H_DISP_4384 = 11'd800;
    localparam [10:0] H_TOTAL_4384 = 11'd1056;
    localparam [10:0] V_SYNC_4384 = 11'd2;
    localparam [10:0] V_BACK_4384 = 11'd33;
    localparam [10:0] V_DISP_4384 = 11'd480;
    localparam [10:0] V_TOTAL_4384 = 11'd525;
    // 当前使用的行时序参数
    reg [10:0] h_sync;
    reg [10:0] h_back;
    reg [10:0] h_total;
    // 当前使用的场时序参数
    reg [10:0] v_sync;
    reg [10:0] v_back;
    reg [10:0] v_total;
    // 行计数器（0 ~ h_total-1）
    reg [10:0] h_cnt;
    // 场计数器（0 ~ v_total-1）
    reg [10:0] v_cnt;

    // data_req 比 lcd_de 提前两个像素时钟拉高，
    // 便于显示模块在下一拍输出对应的 pixel_data。
    wire active_line;  // 垂直有效显示区
    wire active_pixel_req;  // 是否需要请求像素数据

    // RGB LCD 使用 DE 模式驱动，行场同步信号保持高电平。
    assign lcd_hs = 1'b1;
    assign lcd_vs = 1'b1;
    assign lcd_bl = 1'b1;
    assign lcd_clk = lcd_pclk;
    assign lcd_rst = rst_n;
    assign lcd_rgb = lcd_de ? pixel_data : 16'd0;

    assign active_line = (v_cnt >= v_sync + v_back) && (v_cnt < v_sync + v_back + v_disp);

    assign active_pixel_req = (h_cnt >= h_sync + h_back - 11'd2)
                           && (h_cnt <  h_sync + h_back + h_disp - 11'd2)
                           && active_line;

    always @(*) begin
        // 未知 ID 默认使用 4.3 寸 480x272 时序。
        case (lcd_id)
            16'h7084: begin
                h_sync  = H_SYNC_7084;
                h_back  = H_BACK_7084;
                h_disp  = H_DISP_7084;
                h_total = H_TOTAL_7084;
                v_sync  = V_SYNC_7084;
                v_back  = V_BACK_7084;
                v_disp  = V_DISP_7084;
                v_total = V_TOTAL_7084;
            end
            16'h7016: begin
                h_sync  = H_SYNC_7016;
                h_back  = H_BACK_7016;
                h_disp  = H_DISP_7016;
                h_total = H_TOTAL_7016;
                v_sync  = V_SYNC_7016;
                v_back  = V_BACK_7016;
                v_disp  = V_DISP_7016;
                v_total = V_TOTAL_7016;
            end
            16'h1018: begin
                h_sync  = H_SYNC_1018;
                h_back  = H_BACK_1018;
                h_disp  = H_DISP_1018;
                h_total = H_TOTAL_1018;
                v_sync  = V_SYNC_1018;
                v_back  = V_BACK_1018;
                v_disp  = V_DISP_1018;
                v_total = V_TOTAL_1018;
            end
            16'h4384: begin
                h_sync  = H_SYNC_4384;
                h_back  = H_BACK_4384;
                h_disp  = H_DISP_4384;
                h_total = H_TOTAL_4384;
                v_sync  = V_SYNC_4384;
                v_back  = V_BACK_4384;
                v_disp  = V_DISP_4384;
                v_total = V_TOTAL_4384;
            end
            default: begin
                h_sync  = H_SYNC_4342;
                h_back  = H_BACK_4342;
                h_disp  = H_DISP_4342;
                h_total = H_TOTAL_4342;
                v_sync  = V_SYNC_4342;
                v_back  = V_BACK_4342;
                v_disp  = V_DISP_4342;
                v_total = V_TOTAL_4342;
            end
        endcase
    end

    // 输出当前请求的像素坐标。
    always @(posedge lcd_pclk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_xpos <= 11'd0;
        end else if (data_req) begin
            pixel_xpos <= h_cnt + 11'd2 - h_sync - h_back;
        end else begin
            pixel_xpos <= 11'd0;
        end
    end

    // 输出当前请求像素所在的行坐标。
    always @(posedge lcd_pclk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_ypos <= 11'd0;
        end else if (active_line) begin
            pixel_ypos <= v_cnt + 11'd1 - v_sync - v_back;
        end else begin
            pixel_ypos <= 11'd0;
        end
    end

    // lcd_de 延后一拍，与寄存后的 pixel_data 对齐。
    always @(posedge lcd_pclk or negedge rst_n) begin
        if (!rst_n) begin
            lcd_de <= 1'b0;
        end else begin
            lcd_de <= data_req;
        end
    end

    // 提前请求当前有效显示区域内的像素数据。
    always @(posedge lcd_pclk or negedge rst_n) begin
        if (!rst_n) begin
            data_req <= 1'b0;
        end else begin
            data_req <= active_pixel_req;
        end
    end

    // 行计数器对一行内的像素时钟计数。
    always @(posedge lcd_pclk or negedge rst_n) begin
        if (!rst_n) h_cnt <= 11'd0;
        else begin
            if (h_cnt == h_total - 11'd1) h_cnt <= 11'd0;
            else h_cnt <= h_cnt + 11'd1;
        end
    end

    // 场计数器在每行结束时递增。
    always @(posedge lcd_pclk or negedge rst_n) begin
        if (!rst_n) v_cnt <= 11'd0;
        else begin
            if (h_cnt == h_total - 11'd1) begin
                if (v_cnt == v_total - 11'd1) v_cnt <= 11'd0;
                else v_cnt <= v_cnt + 11'd1;
            end
        end
    end

endmodule
