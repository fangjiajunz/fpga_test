module spi_master_top #(
    parameter BURST_WIDTH = 8,     // burst_len 位宽（8 bit → 最多 255 字节）
    parameter CPOL        = 1'b0,
    parameter CPHA        = 1'b0,
    parameter LSB_FIRST   = 1'b0
) (
    input wire sys_clk,
    input wire sys_rst_n,

    // ================================================================
    // 上层控制接口
    // ================================================================
    input wire                   start,
    input wire [BURST_WIDTH-1:0] burst_len, // 本次传输字节数（运行时可变，≥ 1）

    // 流式 TX：上层逐字节喂入
    output wire       tx_req,  // 脉冲：请求下一字节（提前约半字节时间）
    input  wire [7:0] tx_data, // 待发送字节（start 时提供第 1 字节，tx_req 后提供后续）

    // 流式 RX：逐字节输出
    output wire       rx_valid,  // 脉冲：rx_byte 有效
    output wire [7:0] rx_byte,   // 收到的字节（rx_valid=1 时采样）

    // 状态
    output wire busy,
    output reg  done,

    // ================================================================
    // SPI 物理接口
    // ================================================================
    output reg  spi_cs_n,
    output wire spi_sclk,
    output wire spi_mosi,
    input  wire spi_miso
);

    // ================================================================
    // 局部参数
    // ================================================================

    localparam ST_IDLE = 1'b0;
    localparam ST_WAIT = 1'b1;

    // ================================================================
    // 内部信号
    // ================================================================

    reg                    state;

    reg                    phy_start;
    reg  [            7:0] phy_tx_data;

    wire [            7:0] phy_rx_data;
    wire                   phy_busy;
    wire                   phy_done;

    // 字节计数器
    reg  [BURST_WIDTH-1:0] byte_cnt;  // 已完成字节数（0 ~ burst_len-1）
    reg  [BURST_WIDTH-1:0] burst_len_latched;  // 启动时锁存的 burst_len

    // PHY 传输进度计数器（1 ~ 16，用于在字节传输过半时提前发出 tx_req）
    reg  [            4:0] progress_cnt;

    // rx_valid 脉冲
    reg                    rx_valid_reg;

    assign busy     = (state != ST_IDLE);
    assign rx_valid = rx_valid_reg;
    assign rx_byte  = phy_rx_data;

    // ================================================================
    // PHY 传输进度跟踪（每个字节 16 个 sys_clk 周期）
    // progress_cnt 在 phy_busy 期间从 1 递增到 16
    // ================================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            progress_cnt <= 5'd0;
        end else if (phy_busy) begin
            progress_cnt <= progress_cnt + 1'b1;
        end else begin
            progress_cnt <= 5'd0;
        end
    end

    // ================================================================
    // tx_req：在字节传输过半时发出脉冲，给上层约 8 个周期准备下一字节
    // 最后一个字节不发 tx_req（没有下一字节了）
    // ================================================================
    // 当前字节不是最后一字节时才请求下一字节
    assign tx_req = (progress_cnt == 5'd8) && (byte_cnt != burst_len_latched - 1);

    // ================================================================
    // SPI PHY 实例化（固定 8 bit 单字节传输引擎）
    // ================================================================

    spi_phy #(
        .CPOL     (CPOL),
        .CPHA     (CPHA),
        .LSB_FIRST(LSB_FIRST)
    ) u_spi_phy (
        .sys_clk  (sys_clk),
        .sys_rst_n(sys_rst_n),

        .start  (phy_start),
        .tx_data(phy_tx_data),

        .rx_data(phy_rx_data),
        .busy   (phy_busy),
        .done   (phy_done),

        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state             <= ST_IDLE;
            phy_start         <= 1'b0;
            phy_tx_data       <= 8'b0;
            byte_cnt          <= {BURST_WIDTH{1'b0}};
            burst_len_latched <= {BURST_WIDTH{1'b0}};
            rx_valid_reg      <= 1'b0;
            spi_cs_n          <= 1'b1;
            done              <= 1'b0;
        end else begin
            // 默认值
            phy_start    <= 1'b0;
            done         <= 1'b0;
            rx_valid_reg <= 1'b0;

            case (state)

                // ----------------------------------------------------
                // 空闲：等待上层启动
                // ----------------------------------------------------
                ST_IDLE: begin
                    spi_cs_n <= 1'b1;

                    if (start) begin
                        // 锁存 burst_len 和第 1 字节
                        burst_len_latched <= burst_len;
                        phy_tx_data       <= tx_data;
                        byte_cnt          <= {BURST_WIDTH{1'b0}};

                        // CS 拉低 + PHY 启动（同一拍）
                        spi_cs_n          <= 1'b0;
                        phy_start         <= 1'b1;

                        state             <= ST_WAIT;
                    end
                end

                // ----------------------------------------------------
                // 等待：PHY 传输中 / 自动加载下一字节
                // ----------------------------------------------------
                ST_WAIT: begin
                    spi_cs_n <= 1'b0;

                    if (phy_done) begin
                        // 当前字节接收完成 → 输出 rx_valid
                        rx_valid_reg <= 1'b1;

                        if (byte_cnt == burst_len_latched - 1) begin
                            // ------------------------------
                            // 最后一个字节 → 收尾
                            // ------------------------------
                            spi_cs_n <= 1'b1;
                            done     <= 1'b1;
                            state    <= ST_IDLE;

                        end else begin
                            // ------------------------------
                            // 还有更多字节 → 加载 tx_data 上的下一字节
                            // （上层在 tx_req 时已把数据放到 tx_data 上）
                            // ------------------------------
                            byte_cnt    <= byte_cnt + 1'b1;
                            phy_tx_data <= tx_data;
                            phy_start   <= 1'b1;
                        end
                    end
                end

                default: begin
                    state    <= ST_IDLE;
                    spi_cs_n <= 1'b1;
                end

            endcase
        end
    end

endmodule
