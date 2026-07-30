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

    wire tick_1s;

    tick_gen #(
        .MAX_COUNT(50_000_000 - 1)
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
    // SPI 自动测试：发送 CMD_EN (0x06) -> 拉高CS -> 发送 CMD_ERASE (0xC7)
    // ================================================================

    localparam CMD_EN = 8'h06;  // 写使能
    localparam CMD_ERASE = 8'hC7;  // 芯片全擦除

    // 状态机状态定义
    localparam IDLE = 2'd0;  // 空闲状态
    localparam SEND_WREN = 2'd1;  // 发送 0x06
    localparam WAIT_WREN = 2'd2;  // 等待 0x06 发送完成（拉高 CS）
    localparam SEND_ERASE = 2'd3;  // 发送 0xC7

    reg  [1:0] state;

    wire       spi_busy;
    wire       spi_done;
    wire       spi_rx_valid;
    wire [7:0] spi_rx_byte;
    reg        spi_start;
    wire       spi_tx_req;
    reg  [7:0] spi_tx_byte;

    // FSM: 控制两个字节的分步发送协议
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state       <= IDLE;
            spi_start   <= 1'b0;
            spi_tx_byte <= 8'hFF;
        end else begin
            // 默认脉冲信号清零
            spi_start <= 1'b0;

            case (state)
                IDLE: begin
                    // 触发逻辑：以 tick_1s 为例触发擦除流程（可根据需求替换为按键或控制信号）
                    if (tick_1s && !spi_busy) begin
                        spi_tx_byte <= CMD_EN;  // 加载 0x06
                        spi_start   <= 1'b1;  // 启动第一次 SPI 传输
                        state       <= SEND_WREN;
                    end
                end

                SEND_WREN: begin
                    // 等待 0x06 发送完成
                    if (spi_done) begin
                        state <= WAIT_WREN;
                    end
                end

                WAIT_WREN: begin
                    // 在此状态下 CS 已被 spi_master 拉高，等待 1 个周期确保 CS 最小高电平时间(tSHSL)满足要求
                    if (!spi_busy) begin
                        spi_tx_byte <= CMD_ERASE;  // 加载 0xC7
                        spi_start   <= 1'b1;  // 启动第二次 SPI 传输
                        state       <= SEND_ERASE;
                    end
                end

                SEND_ERASE: begin
                    // 等待 0xC7 发送完成
                    if (spi_done) begin
                        state <= IDLE;  // 擦除指令已下发，返回空闲状态
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // SPI 主控模块实例化
    spi_master_top #(
        .BURST_WIDTH(8),
        .CPOL       (1'b0),
        .CPHA       (1'b0),
        .LSB_FIRST  (1'b0)
    ) u_spi_master_top (
        .sys_clk  (sys_clk),
        .sys_rst_n(sys_rst_n),

        .burst_len(8'd1),        // 单次传输 1 个字节
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
