module top (
    input wire sys_clk,
    input wire sys_rst_n,

    // output wire [7:0] seg_led,
    // output wire [5:0] seg_sel,

    input  wire uart_rxd,
    output wire uart_txd,

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
        .MAX_COUNT(50_000_000 - 1)
    ) u_tick_1s (
        .clk  (sys_clk),
        .rst_n(sys_rst_n),
        .tick (tick_1s)
    );

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
    // Flash 测试应用层 <-> W25Q16 控制器
    // ================================================================

    wire        flash_start;
    wire [2:0]  flash_operation;
    wire [23:0] flash_address;
    wire [7:0]  flash_wr_data;

    wire [7:0]  flash_rd_data;
    wire [23:0] flash_id;
    wire        flash_busy;
    wire        flash_done;
    wire        flash_error;

    // 调试信号。读取成功后通常应看到 24'hEF4015。
    // keep 属性便于在 Quartus SignalTap 中查找这些节点。
    (* keep = "true" *) wire [23:0] flash_id_debug;
    (* keep = "true" *) wire        flash_id_valid_debug;
    (* keep = "true" *) wire        flash_test_error_debug;

    flash_test_app u_flash_test_app (
        .clk            (sys_clk),
        .rst_n          (sys_rst_n),
        .tick_1s        (tick_1s),

        .flash_start    (flash_start),
        .flash_operation(flash_operation),
        .flash_address  (flash_address),
        .flash_wr_data  (flash_wr_data),

        .flash_busy     (flash_busy),
        .flash_done     (flash_done),
        .flash_error    (flash_error),
        .flash_id       (flash_id),

        .id_value       (flash_id_debug),
        .id_valid       (flash_id_valid_debug),
        .test_error     (flash_test_error_debug)
    );

    // ================================================================
    // W25Q16 控制器 <-> SPI Master
    // ================================================================

    wire       spi_start;
    wire [7:0] spi_burst_len;
    wire       spi_tx_req;
    wire [7:0] spi_tx_byte;
    wire       spi_rx_valid;
    wire [7:0] spi_rx_byte;
    wire       spi_busy;
    wire       spi_done;

    w25q16_ctrl u_w25q16_ctrl (
        .clk           (sys_clk),
        .rst_n         (sys_rst_n),

        .start         (flash_start),
        .operation     (flash_operation),
        .address       (flash_address),
        .wr_data       (flash_wr_data),

        .rd_data       (flash_rd_data),
        .flash_id      (flash_id),
        .busy          (flash_busy),
        .done          (flash_done),
        .error         (flash_error),

        .spi_start     (spi_start),
        .spi_burst_len (spi_burst_len),
        .spi_tx_req    (spi_tx_req),
        .spi_tx_byte   (spi_tx_byte),

        .spi_rx_valid  (spi_rx_valid),
        .spi_rx_byte   (spi_rx_byte),
        .spi_busy      (spi_busy),
        .spi_done      (spi_done)
    );

    // ================================================================
    // 通用 SPI Master
    // ================================================================

    spi_master_top #(
        .BURST_WIDTH(8),
        .CPOL       (1'b0),
        .CPHA       (1'b0),
        .LSB_FIRST  (1'b0)
    ) u_spi_master_top (
        .sys_clk  (sys_clk),
        .sys_rst_n(sys_rst_n),

        // 不能再固定为 8'd1；读取 ID 需要连续传输 4 字节。
        .burst_len(spi_burst_len),
        .start    (spi_start),
        .tx_req   (spi_tx_req),
        .tx_data  (spi_tx_byte),

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
