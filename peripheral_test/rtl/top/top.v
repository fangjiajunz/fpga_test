module top (
    input wire sys_clk,
    input wire sys_rst_n,

    // output wire [7:0] seg_led,
    // output wire [5:0] seg_sel,

    input  wire uart_rxd,
    output wire uart_txd,

    output wire [3:0] led,
    input  wire [3:0] key,
    // SPI 接口
    output wire       spi_cs_n,
    output wire       spi_sclk,
    output wire       spi_mosi,
    input  wire       spi_miso
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
    //rx
    wire [7:0] uart_rx_data;
    wire       uart_rx_empty;
    wire       uart_rx_rdreq;
    //tx
    wire [7:0] uart_tx_data;
    wire       uart_tx_wrreq;

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

        .tx_data (uart_tx_data),
        .tx_wrreq(uart_tx_wrreq),
        .tx_full ()
    );

    // 收到 0xAA 点亮 LED，收到 0x55 熄灭
    uart_app u_uart_app (
        .clk     (sys_clk),
        .rst_n   (rst_n),
        .rx_data (uart_rx_data),
        .rx_empty(uart_rx_empty),
        .rx_rdreq(uart_rx_rdreq),
        .tx_data (uart_tx_data),
        .tx_wrreq(uart_tx_wrreq),
        .led     (led[3:0]),
        .key     (key[3:0])
    );



endmodule
