module top #(
    parameter UART_BPS = 2000000,
    parameter CLK_FREQ = 50_000_000
) (
    input wire sys_clk,
    input wire sys_rst_n,

    // 串口物理接口
    input  wire uart_rxd,
    output wire uart_txd,

    // 板载外设接口
    output wire [3:0] led,
    input  wire [3:0] key,

    // SPI 接口
    output wire spi_cs_n,
    output wire spi_sclk,
    output wire spi_mosi,
    input  wire spi_miso
);

    // ================================================================
    // 复位同步：异步复位、同步释放
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
    // 定时节拍发生器 (Tick Generators)
    // ================================================================
    wire tick_1s;
    wire tick_20ms;

    tick_gen #(
        .MAX_COUNT(50_000_000 - 1)
    ) u_tick_1s (
        .clk  (sys_clk),
        .rst_n(rst_n),
        .tick (tick_1s)
    );

    tick_gen #(
        .MAX_COUNT(1_000_000 - 1)  // 50MHz 时钟下 20ms
    ) u_tick_20ms (
        .clk  (sys_clk),
        .rst_n(rst_n),
        .tick (tick_20ms)
    );

    // ================================================================
    // 板载按键消抖 (纯模块例化)
    // key[1] 用于手动再次触发 Flash 读写自检
    // ================================================================
    wire flash_test_trigger;

    ax_debounce u_debounce_flash_key (
        .sys_clk   (sys_clk),
        .sys_rst_n (rst_n),
        .btn_in    (key[1]),
        .timer_tick(tick_20ms),
        .btn_edge  (flash_test_trigger)
    );

    // ================================================================
    // 【物理驱动层 PHY / Driver】
    // 1. UART 核心收发驱动 (含 64 字节 RX/TX FIFO 及自动读驱动)
    // ================================================================
    (* keep = "true" *)wire       uart_rx_empty;
    (* keep = "true" *)wire       uart_rx_full;
    (* keep = "true" *)wire       uart_rx_overflow;
    (* keep = "true" *)wire       uart_rx_frame_error;

    wire [7:0] uart_rx_data;
    wire       uart_rx_valid;

    wire [7:0] uart_tx_data;
    wire       uart_tx_wrreq;
    wire       uart_tx_full;

    uart_core #(
        .UART_BPS(UART_BPS),
        .CLK_FREQ(CLK_FREQ)
    ) u_uart_core (
        .clk             (sys_clk),
        .rst_n           (rst_n),
        .rxd             (uart_rxd),
        .txd             (uart_txd),
        .rx_data         (uart_rx_data),
        .rx_valid        (uart_rx_valid),
        .rx_empty        (uart_rx_empty),
        .rx_full         (uart_rx_full),
        .rx_overflow     (uart_rx_overflow),
        .rx_frame_error  (uart_rx_frame_error),
        .rx_overflow_clr (1'b0),
        .rx_frame_err_clr(1'b0),

        .tx_data (uart_tx_data),
        .tx_wrreq(uart_tx_wrreq),
        .tx_full (uart_tx_full)
    );

    // ================================================================
    // 【物理驱动层 PHY / Driver】
    // 2. SPI 主机物理层驱动 (spi_master_top)
    // ================================================================
    wire       spi_start;
    wire [7:0] spi_burst_len;
    wire       spi_tx_req;
    wire [7:0] spi_tx_byte;
    wire       spi_rx_valid;
    wire [7:0] spi_rx_byte;
    wire       spi_busy;
    wire       spi_done;

    spi_master_top #(
        .BURST_WIDTH(8),
        .CPOL       (1'b0),
        .CPHA       (1'b0),
        .LSB_FIRST  (1'b0)
    ) u_spi_master_top (
        .sys_clk  (sys_clk),
        .sys_rst_n(rst_n),

        .start    (spi_start),
        .burst_len(spi_burst_len),
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

    // ================================================================
    // 【控制器层 Controller】
    // W25Q16 硬件驱动控制器 (三段式状态机，硬件闭环 WREN 与 WIP 轮询)
    // ================================================================
    wire        flash_start;
    wire [ 2:0] flash_operation;
    wire [23:0] flash_address;
    wire [31:0] flash_wr_data;
    wire [31:0] flash_rd_data;
    wire [23:0] flash_id;
    wire        flash_busy;
    wire        flash_done;
    wire        flash_error;

    w25q16_ctrl u_w25q16_ctrl (
        .clk  (sys_clk),
        .rst_n(rst_n),

        // 上层测试应用接口
        .start     (flash_start),
        .operation (flash_operation),
        .address   (flash_address),
        .wr_data_32(flash_wr_data),
        .rd_data_32(flash_rd_data),
        .flash_id  (flash_id),
        .busy      (flash_busy),
        .done      (flash_done),
        .error     (flash_error),

        // SPI PHY 底层接口
        .spi_start    (spi_start),
        .spi_burst_len(spi_burst_len),
        .spi_tx_req   (spi_tx_req),
        .spi_tx_byte  (spi_tx_byte),
        .spi_rx_valid (spi_rx_valid),
        .spi_rx_byte  (spi_rx_byte),
        .spi_busy     (spi_busy),
        .spi_done     (spi_done)
    );

    // ================================================================
    // 【协议解析层 Protocol / Framing Layer】
    // decode 模块：纯粹的协议流解码器，负责帧同步、拆包与流式分发
    // ================================================================
    wire        data_out_valid;
    wire [ 7:0] data_out;
    wire [16:0] data_out_addr;
    wire [ 7:0] packet_type;
    wire [16:0] packet_len;
    wire        packet_done;
    wire        packet_error;
    wire        check_ok;

    decode u_decode (
        .sys_clk       (sys_clk),
        .sys_rst_n     (rst_n),
        .in_data       (uart_rx_data),
        .data_ready    (uart_rx_valid),
        .data_out_valid(data_out_valid),
        .data_out      (data_out),
        .data_out_addr (data_out_addr),
        .packet_type   (packet_type),
        .packet_len    (packet_len),
        .packet_done   (packet_done),
        .packet_error  (packet_error),
        .check_ok      (check_ok)
    );

    // ================================================================
    // 【业务应用层 Application Layer】
    // 1. uart_app 模块：LED 控制业务、按键 key[0] 防抖及日常通信
    // ================================================================
    wire [7:0] app_tx_data;
    wire       app_tx_wrreq;

    uart_app u_uart_app (
        .clk  (sys_clk),
        .rst_n(rst_n),

        // 协议输入接口
        .data_out_valid(data_out_valid),
        .data_out      (data_out),
        .data_out_addr (data_out_addr),
        .packet_type   (packet_type),
        .packet_len    (packet_len),
        .packet_done   (packet_done),
        .packet_error  (packet_error),
        .check_ok      (check_ok),

        // 物理发送输出接口
        .tx_data (app_tx_data),
        .tx_wrreq(app_tx_wrreq),

        // 外设引脚
        .led(led[3:0]),
        .key(key[3:0])
    );

    // ================================================================
    // 【业务应用层 Application Layer】
    // 2. flash_test_app 模块：W25Q16 自检测试与 ASCII 串口上报
    //    - 上电 0.5 秒自动执行读ID、擦除、验空、写入、验读全流程
    //    - 支持通过 key[1] 随时按键再次测试
    // ================================================================
    wire [7:0] flash_tx_data;
    wire       flash_tx_wrreq;

    flash_test_app #(
        .CLK_FREQ        (CLK_FREQ),
        .AUTO_START_DELAY(32'd25_000_000)  // 50MHz 时钟下约 0.5s 上电延时
    ) u_flash_test_app (
        .clk  (sys_clk),
        .rst_n(rst_n),

        .btn_trigger(flash_test_trigger),

        .flash_start    (flash_start),
        .flash_operation(flash_operation),
        .flash_address  (flash_address),
        .flash_wr_data  (flash_wr_data),
        .flash_rd_data  (flash_rd_data),
        .flash_id       (flash_id),
        .flash_busy     (flash_busy),
        .flash_done     (flash_done),
        .flash_error    (flash_error),

        .tx_data (flash_tx_data),
        .tx_wrreq(flash_tx_wrreq),
        .tx_full (uart_tx_full),

        .test_done(),
        .test_pass()
    );

    // ================================================================
    // 【发送通道仲裁器】
    // 将 Flash 自检输出流与 UART 业务通信流无锁仲裁后接入 TX FIFO
    // ================================================================
    uart_tx_arbiter u_uart_tx_arbiter (
        .clk  (sys_clk),
        .rst_n(rst_n),

        .ch0_data (flash_tx_data),
        .ch0_wrreq(flash_tx_wrreq),

        .ch1_data (app_tx_data),
        .ch1_wrreq(app_tx_wrreq),

        .tx_data (uart_tx_data),
        .tx_wrreq(uart_tx_wrreq)
    );

endmodule
