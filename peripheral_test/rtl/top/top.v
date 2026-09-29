module top (
    input wire sys_clk,
    input wire sys_rst_n,

    // 串口物理接口
    input  wire uart_rxd,
    output wire uart_txd,

    // 板载外设接口
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
    // 1 秒脉冲发生器
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
    // 【第 1 层：物理驱动层 PHY / Driver】
    // UART 核心收发驱动 (含 64 字节 RX/TX FIFO)
    // ================================================================
    (* keep = "true" *) wire uart_rx_full;
    (* keep = "true" *) wire uart_rx_overflow;
    (* keep = "true" *) wire uart_rx_frame_error;

    wire [7:0] uart_rx_data;
    wire       uart_rx_empty;
    wire       uart_rx_rdreq;

    wire [7:0] uart_tx_data;
    wire       uart_tx_wrreq;

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

        .tx_data         (uart_tx_data),
        .tx_wrreq        (uart_tx_wrreq),
        .tx_full         ()
    );

    // ================================================================
    // 【第 2 层：协议解析层 Protocol / Framing Layer】
    // decode 模块：直连 RX FIFO，负责帧同步、拆包与流式分发
    // ================================================================
    wire        data_out_valid;
    wire [7:0]  data_out;
    wire [16:0] data_out_addr;
    wire [7:0]  packet_type;
    wire [16:0] packet_len;
    wire        packet_done;
    wire        packet_error;
    wire        check_ok;

    decode u_decode (
        .sys_clk       (sys_clk),
        .sys_rst_n     (rst_n),
        .rx_data       (uart_rx_data),
        .rx_empty      (uart_rx_empty),
        .rx_rdreq      (uart_rx_rdreq),
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
    // 【第 3 层：业务应用层 Application Layer】
    // uart_app 模块：LED 控制业务、按键防抖及 TX 发送仲裁
    // ================================================================
    uart_app u_uart_app (
        .clk           (sys_clk),
        .rst_n         (rst_n),

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
        .tx_data       (uart_tx_data),
        .tx_wrreq      (uart_tx_wrreq),

        // 外设引脚
        .led           (led[3:0]),
        .key           (key[3:0])
    );

endmodule
