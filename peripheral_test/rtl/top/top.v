module top (
    input wire sys_clk,
    input wire sys_rst_n,

    // output wire [7:0] seg_led,
    // output wire [5:0] seg_sel,

    input  wire uart_rxd,
    output wire uart_txd,

    // // RGB TFT-LCD 接口
    // output wire        lcd_bl,
    // output wire        lcd_clk,
    // output wire        lcd_rst,
    // output wire        lcd_de,
    // output wire        lcd_hs,
    // output wire        lcd_vs,
    // inout  wire [15:0] lcd_rgb,

    // SPI 接口
    output wire spi_cs_n,
    output wire spi_sclk,
    output wire spi_mosi,
    input  wire spi_miso
);

    // ================================================================
    // 1 秒脉冲
    // ================================================================

    wire tick_1s;

    tick_gen #(
        .MAX_COUNT(50_000_0 - 1)
    ) u_tick_1s (
        .clk  (sys_clk),
        .rst_n(sys_rst_n),
        .tick (tick_1s)
    );

    // ================================================================
    // 数码管
    // ================================================================

    // seg_led u_seg_led (
    //     .clk     (sys_clk),
    //     .rst_n   (sys_rst_n),
    //     .add_flag(tick_1s),
    //     .seg_sel (seg_sel),
    //     .seg_led (seg_led)
    // );

    // ================================================================
    // UART 回环
    // ================================================================

    uart_echo_app u_uart_echo_app (
        .clk     (sys_clk),
        .rst_n   (sys_rst_n),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd)
    );

    // ================================================================
    // RGB LCD
    // ================================================================

    // lcd_top u_lcd_top (
    //     .clk    (sys_clk),
    //     .rst_n  (sys_rst_n),
    //     .lcd_bl (lcd_bl),
    //     .lcd_clk(lcd_clk),
    //     .lcd_rst(lcd_rst),
    //     .lcd_de (lcd_de),
    //     .lcd_hs (lcd_hs),
    //     .lcd_vs (lcd_vs),
    //     .lcd_rgb(lcd_rgb)
    // );

    // ================================================================
    // SPI 自动测试
    // 每隔 1 秒发送一次 8'hA5
    // ================================================================

    wire       spi_busy;
    wire       spi_done;
    wire       spi_rx_valid;
    wire [7:0] spi_rx_byte;
    wire       spi_start;
    wire       spi_tx_req;
    /*
     * tick_1s 是一个 sys_clk 周期的脉冲。
     * 只有 SPI 空闲时才启动新传输。
     */
    assign spi_start = tick_1s && !spi_busy;

    spi_master_top #(
        .BURST_WIDTH(8),
        .CPOL       (1'b0),
        .CPHA       (1'b0),
        .LSB_FIRST  (1'b0)
    ) u_spi_master_top (
        .sys_clk  (sys_clk),
        .sys_rst_n(sys_rst_n),

        .burst_len(8'd1),
        .start    (spi_start),
        .tx_req   (spi_tx_req),
        .tx_data  (8'hAF),

        .rx_valid(spi_rx_valid),
        .rx_byte (spi_rx_byte),
        .busy    (spi_busy),
        .done    (spi_done),

        .spi_cs_n(spi_cs_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );

endmodule
