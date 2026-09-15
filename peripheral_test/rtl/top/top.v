module top (
    input wire sys_clk,
    input wire sys_rst_n,

    // output wire [7:0] seg_led,
    // output wire [5:0] seg_sel,

    input  wire uart_rxd,
    output wire uart_txd,

    output wire led,

    // SPI 接口
    output wire spi_cs_n,
    output wire spi_sclk,
    output wire spi_mosi,
    input  wire spi_miso
);

    // ================================================================
    // 复位同步：异步复位、同步释放
    // 直接把按键 sys_rst_n 当异步复位用，松开时刻和 sys_clk 无关，会带来
    // recovery/removal 时序违例。这里同步两拍后产生内部的 rst_n，全设计统一使用。
    // ================================================================

    reg rst_n_sync_1;
    reg rst_n_sync_2;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rst_n_sync_1 <= 1'b0;
            rst_n_sync_2 <= 1'b0;
        end else begin
            rst_n_sync_1 <= 1'b1;
            rst_n_sync_2 <= rst_n_sync_1;
        end
    end

    wire rst_n = rst_n_sync_2;

    // ================================================================
    // 1 秒脉冲
    // ================================================================

    wire tick_1s;

    tick_gen #(
        .MAX_COUNT(50_000_000 - 1)
    ) u_tick_1s (
        .clk  (sys_clk),
        .rst_n(rst_n),
        .tick (tick_1s)
    );

    // ================================================================
    // UART 控制 LED
    // ================================================================

    // UART 状态调试信号，keep 属性便于在 Quartus SignalTap 中查找。
    // rx_overflow / rx_frame_error 都是 sticky 的：置位表示曾经因为 RX FIFO
    // 满丢过字节 / 收到过停止位为低的帧，需要复位（或由上层给对应的 clr）
    // 才能清掉。
    (* keep = "true" *)wire       uart_rx_full;
    (* keep = "true" *)wire       uart_rx_overflow;
    (* keep = "true" *)wire       uart_rx_frame_error;

    wire [7:0] uart_rx_data;
    wire       uart_rx_empty;
    wire       uart_rx_rdreq;

    // 只收不发：TX 侧没人用，tx_wrreq 拉低，txd 保持空闲高电平
    uart_core #(
        .UART_BPS(115200),
        .CLK_FREQ(50_000_000)
    ) u_uart_core (
        .clk             (sys_clk),
        .rst_n           (rst_n),
        .rxd             (uart_rxd),
        .txd             (uart_txd),
        .rx_data         (uart_rx_data),
        .rx_empty        (uart_rx_empty),
        .rx_full         (uart_rx_full),
        .rx_overflow     (uart_rx_overflow),
        .rx_frame_error  (uart_rx_frame_error),
        .rx_overflow_clr (1'b0),
        .rx_frame_err_clr(1'b0),
        .rx_rdreq        (uart_rx_rdreq),
        .tx_data         (8'h00),
        .tx_wrreq        (1'b0),
        .tx_full         ()
    );

    // 收到 0xAA 点亮 LED，收到 0x55 熄灭
    led_ctrl_app u_led_ctrl_app (
        .clk     (sys_clk),
        .rst_n   (rst_n),
        .rx_data (uart_rx_data),
        .rx_empty(uart_rx_empty),
        .rx_rdreq(uart_rx_rdreq),
        .led     (led)
    );

    // 原来的 UART 回环应用（echo）已停用。注意 uart_echo_app 内部自带一个
    // uart_core，和上面这个是两个独立实例，同时使能会让两者同时驱动 uart_txd，
    // 需要回环功能时请把上面那段整段换回来，不要只是取消注释。
    //
    // uart_echo_app u_uart_echo_app (
    //     .clk              (sys_clk),
    //     .rst_n            (rst_n),
    //     .uart_rxd         (uart_rxd),
    //     .uart_txd         (uart_txd),
    //     .rx_full          (uart_rx_full),
    //     .rx_overflow      (uart_rx_overflow),
    //     .rx_frame_error   (uart_rx_frame_error),
    //     .rx_overflow_clr  (1'b0),
    //     .rx_frame_err_clr (1'b0)
    // );

    // // ================================================================
    // // Flash 测试应用层 <-> W25Q16 控制器
    // // ================================================================

    // wire        flash_start;
    // wire [2:0]  flash_operation;
    // wire [23:0] flash_address;
    // wire [7:0]  flash_wr_data;

    // wire [7:0]  flash_rd_data;
    // wire [23:0] flash_id;
    // wire        flash_busy;
    // wire        flash_done;
    // wire        flash_error;

    // // 调试信号。读取成功后通常应看到 24'hEF4015。
    // // keep 属性便于在 Quartus SignalTap 中查找这些节点。
    // (* keep = "true" *) wire [23:0] flash_id_debug;
    // (* keep = "true" *) wire        flash_id_valid_debug;
    // (* keep = "true" *) wire        flash_test_error_debug;

    // flash_test_app u_flash_test_app (
    //     .clk            (sys_clk),
    //     .rst_n          (rst_n),
    //     .tick_1s        (tick_1s),

    //     .flash_start    (flash_start),
    //     .flash_operation(flash_operation),
    //     .flash_address  (flash_address),
    //     .flash_wr_data  (flash_wr_data),

    //     .flash_busy     (flash_busy),
    //     .flash_done     (flash_done),
    //     .flash_error    (flash_error),
    //     .flash_id       (flash_id),

    //     .id_value       (flash_id_debug),
    //     .id_valid       (flash_id_valid_debug),
    //     .test_error     (flash_test_error_debug)
    // );

    // // ================================================================
    // // W25Q16 控制器 <-> SPI Master
    // // ================================================================

    // wire       spi_start;
    // wire [7:0] spi_burst_len;
    // wire       spi_tx_req;
    // wire [7:0] spi_tx_byte;
    // wire       spi_rx_valid;
    // wire [7:0] spi_rx_byte;
    // wire       spi_busy;
    // wire       spi_done;

    // w25q16_ctrl u_w25q16_ctrl (
    //     .clk           (sys_clk),
    //     .rst_n         (rst_n),

    //     .start         (flash_start),
    //     .operation     (flash_operation),
    //     .address       (flash_address),
    //     .wr_data       (flash_wr_data),

    //     .rd_data       (flash_rd_data),
    //     .flash_id      (flash_id),
    //     .busy          (flash_busy),
    //     .done          (flash_done),
    //     .error         (flash_error),

    //     .spi_start     (spi_start),
    //     .spi_burst_len (spi_burst_len),
    //     .spi_tx_req    (spi_tx_req),
    //     .spi_tx_byte   (spi_tx_byte),

    //     .spi_rx_valid  (spi_rx_valid),
    //     .spi_rx_byte   (spi_rx_byte),
    //     .spi_busy      (spi_busy),
    //     .spi_done      (spi_done)
    // );

    // // ================================================================
    // // 通用 SPI Master
    // // ================================================================

    // spi_master_top #(
    //     .BURST_WIDTH(8),
    //     .CPOL       (1'b0),
    //     .CPHA       (1'b0),
    //     .LSB_FIRST  (1'b0)
    // ) u_spi_master_top (
    //     .sys_clk  (sys_clk),
    //     .sys_rst_n(rst_n),

    //     // 不能再固定为 8'd1；读取 ID 需要连续传输 4 字节。
    //     .burst_len(spi_burst_len),
    //     .start    (spi_start),
    //     .tx_req   (spi_tx_req),
    //     .tx_data  (spi_tx_byte),

    //     .rx_valid(spi_rx_valid),
    //     .rx_byte (spi_rx_byte),
    //     .busy    (spi_busy),
    //     .done    (spi_done),

    //     .spi_cs_n(spi_cs_n),
    //     .spi_sclk(spi_sclk),
    //     .spi_mosi(spi_mosi),
    //     .spi_miso(spi_miso)
    // );

endmodule
