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
    input  wire spi_miso,

    // SDRAM 物理芯片接口
    output wire        sdram_clk,   // SDRAM 芯片时钟
    output wire        sdram_cke,   // SDRAM 时钟使能
    output wire        sdram_cs_n,  // SDRAM 片选
    output wire        sdram_ras_n, // SDRAM 行有效
    output wire        sdram_cas_n, // SDRAM 列有效
    output wire        sdram_we_n,  // SDRAM 写有效
    output wire [ 1:0] sdram_ba,    // SDRAM Bank 地址
    output wire [12:0] sdram_addr,  // SDRAM 行/列地址
    output wire [ 1:0] sdram_dqm,   // SDRAM 数据掩码
    inout  wire [15:0] sdram_data   // SDRAM 双向数据总线
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

    // key[2] 用于手动再次触发 SDRAM 读写自检
    wire sdram_test_trigger_sys;

    ax_debounce u_debounce_sdram_key (
        .sys_clk   (sys_clk),
        .sys_rst_n (rst_n),
        .btn_in    (key[2]),
        .timer_tick(tick_20ms),
        .btn_edge  (sdram_test_trigger_sys)
    );

    // ================================================================
    // 【PLL 时钟管理】
    // 输入 50MHz 系统时钟，生成:
    // c0: 100MHz 0° 相位 (SDRAM 控制器工作时钟 clk_100m)
    // c1: 100MHz -75° 相位 (SDRAM 物理芯片输出时钟 clk_100m_shift)
    // ================================================================
    wire clk_100m;
    wire clk_100m_shift;
    wire pll_locked;

    pll_100m u_pll_100m (
        .areset (!sys_rst_n),
        .inclk0 (sys_clk),
        .c0     (clk_100m),
        .c1     (clk_100m_shift),
        .locked (pll_locked)
    );

    // 100MHz 时钟域复位同步释放
    reg rst_n_100m_r1, rst_n_100m_r2;
    always @(posedge clk_100m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rst_n_100m_r1 <= 1'b0;
            rst_n_100m_r2 <= 1'b0;
        end else begin
            rst_n_100m_r1 <= pll_locked;
            rst_n_100m_r2 <= rst_n_100m_r1;
        end
    end
    wire rst_n_100m = rst_n_100m_r2;

    // key[2] 触发脉冲跨时钟域同步至 100MHz 域
    reg sdram_trig_r1, sdram_trig_r2, sdram_trig_r3;
    always @(posedge clk_100m or negedge rst_n_100m) begin
        if (!rst_n_100m) begin
            sdram_trig_r1 <= 1'b0;
            sdram_trig_r2 <= 1'b0;
            sdram_trig_r3 <= 1'b0;
        end else begin
            sdram_trig_r1 <= sdram_test_trigger_sys;
            sdram_trig_r2 <= sdram_trig_r1;
            sdram_trig_r3 <= sdram_trig_r2;
        end
    end
    wire sdram_test_trigger = sdram_trig_r2 && !sdram_trig_r3;

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
    wire [3:0] app_led;

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
        .led(app_led),
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
    // 【控制器与物理层 Controller & PHY】
    // 3. SDRAM 控制器顶层封装 (sdram_top)
    // ================================================================
    wire        sdram_wr_req;
    wire        sdram_rd_req;
    wire [23:0] sdram_wr_addr;
    wire [23:0] sdram_rd_addr;
    wire [ 9:0] sdram_wr_len;
    wire [ 9:0] sdram_rd_len;
    wire [15:0] sdram_wr_data;
    wire        sdram_wr_ack;
    wire        sdram_rd_ack;
    wire [15:0] sdram_rd_data;
    wire        sdram_rw_busy;
    wire        sdram_rw_done;
    wire        sdram_init_done;

    sdram_top #(
        .CLK_FREQ_MHZ (100)
    ) u_sdram_top (
        .ref_clk   (clk_100m),
        .out_clk   (clk_100m_shift),
        .rst_n     (rst_n_100m),

        .wr_req    (sdram_wr_req),
        .rd_req    (sdram_rd_req),
        .wr_addr   (sdram_wr_addr),
        .rd_addr   (sdram_rd_addr),
        .wr_len    (sdram_wr_len),
        .rd_len    (sdram_rd_len),
        .wr_data   (sdram_wr_data),
        .wr_ack    (sdram_wr_ack),
        .rd_ack    (sdram_rd_ack),
        .rd_data   (sdram_rd_data),
        .rw_busy   (sdram_rw_busy),
        .rw_done   (sdram_rw_done),
        .init_done (sdram_init_done),

        .sdram_clk (sdram_clk),
        .sdram_cke (sdram_cke),
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n),
        .sdram_ba  (sdram_ba),
        .sdram_addr(sdram_addr),
        .sdram_dqm (sdram_dqm),
        .sdram_data(sdram_data)
    );

    // ================================================================
    // 【业务应用层 Application Layer】
    // 3. sdram_test_app 模块：SDRAM 突发读写自检应用
    //    - 上电约 1ms 自动向 Bank0/Row0/Col0 突发写入 10 个递增数据并读回核对
    //    - 支持通过 key[2] 随时重新发起测试
    // ================================================================
    wire        sdram_test_busy;
    wire        sdram_test_done;
    wire        sdram_test_pass;
    wire        sdram_test_err;
    wire [15:0] sdram_error_cnt;
    wire [15:0] sdram_first_exp_data;
    wire [15:0] sdram_first_rd_data;
    wire        sdram_done_toggle;

    sdram_test_app #(
        .TEST_ADDR       (24'h000000),
        .TEST_BURST_LEN  (10'd10),
        .AUTO_START_WAIT (100_000)
    ) u_sdram_test_app (
        .clk        (clk_100m),
        .rst_n      (rst_n_100m),

        .btn_trigger(sdram_test_trigger),

        .init_done  (sdram_init_done),
        .rw_busy    (sdram_rw_busy),
        .rw_done    (sdram_rw_done),
        .wr_ack     (sdram_wr_ack),
        .rd_ack     (sdram_rd_ack),
        .rd_data    (sdram_rd_data),

        .wr_req     (sdram_wr_req),
        .rd_req     (sdram_rd_req),
        .wr_addr    (sdram_wr_addr),
        .rd_addr    (sdram_rd_addr),
        .wr_len     (sdram_wr_len),
        .rd_len     (sdram_rd_len),
        .wr_data    (sdram_wr_data),

        .test_busy     (sdram_test_busy),
        .test_done     (sdram_test_done),
        .test_pass     (sdram_test_pass),
        .test_err      (sdram_test_err),
        .error_cnt     (sdram_error_cnt),
        .first_exp_data(sdram_first_exp_data),
        .first_rd_data (sdram_first_rd_data),
        .done_toggle   (sdram_done_toggle)
    );

    // ================================================================
    // 【业务应用层 Application Layer】
    // 4. sdram_report_app 模块：SDRAM 自检结果 ASCII 串口格式化上报
    // ================================================================
    wire [7:0] sdram_tx_data;
    wire       sdram_tx_wrreq;

    sdram_report_app u_sdram_report_app (
        .clk           (sys_clk),
        .rst_n         (rst_n),
        .done_toggle   (sdram_done_toggle),
        .test_pass     (sdram_test_pass),
        .error_cnt     (sdram_error_cnt),
        .first_exp_data(sdram_first_exp_data),
        .first_rd_data (sdram_first_rd_data),
        .tx_data       (sdram_tx_data),
        .tx_wrreq      (sdram_tx_wrreq),
        .tx_full       (uart_tx_full)
    );

    // ================================================================
    // 【板载 LED 状态显示】
    // 默认展示 SDRAM 硬件状态 (低电平点亮):
    // led[0]: SDRAM 初始化完成 (init_done)
    // led[1]: SDRAM 测试运行中 (test_busy)
    // led[2]: SDRAM 测试通过 (test_pass)
    // led[3]: SDRAM 测试出错 (test_err)
    // 若 uart_app 收到非零 LED 控制指令，则展示命令值
    // ================================================================
    wire [3:0] sdram_led = {~sdram_test_err, ~sdram_test_pass, ~sdram_test_busy, ~sdram_init_done};
    assign led = (app_led != 4'b0000) ? app_led : sdram_led;

    // ================================================================
    // 【发送通道仲裁器】
    // 将 Flash 自检输出流、SDRAM 自检输出流与 UART 业务通信流无锁仲裁后接入 TX FIFO
    // ================================================================
    uart_tx_arbiter u_uart_tx_arbiter (
        .clk  (sys_clk),
        .rst_n(rst_n),

        .ch0_data (flash_tx_data),
        .ch0_wrreq(flash_tx_wrreq),

        .ch1_data (sdram_tx_data),
        .ch1_wrreq(sdram_tx_wrreq),

        .ch2_data (app_tx_data),
        .ch2_wrreq(app_tx_wrreq),

        .tx_data (uart_tx_data),
        .tx_wrreq(uart_tx_wrreq)
    );

endmodule
