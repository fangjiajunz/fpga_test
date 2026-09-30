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
    // FSM 状态定义
    // ================================================================
    localparam S_IDLE = 1'b0;
    localparam S_WAIT = 1'b1;

    reg                    current_state;
    reg                    next_state;

    // ================================================================
    // 内部控制与计数寄存器
    // ================================================================
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

    // rx_valid 脉冲寄存器
    reg                    rx_valid_reg;

    // 状态转移条件指示线
    wire                   is_last_byte = (byte_cnt == burst_len_latched - 1'b1);
    wire                   burst_done = (current_state == S_WAIT) && phy_done && is_last_byte;

    assign busy     = (current_state != S_IDLE);
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
    // 当前字节不是最后一字节时才请求下一字节
    // ================================================================
    assign tx_req = (progress_cnt == 5'd8) && (byte_cnt != burst_len_latched - 1'b1);

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

    // ================================================================
    // 【第一段】现态时序寄存器
    // ================================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            current_state <= S_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // ================================================================
    // 【第二段】次态组合逻辑决策
    // ================================================================
    always @(*) begin
        next_state = current_state;

        case (current_state)
            S_IDLE: begin
                if (start) next_state = S_WAIT;
            end

            S_WAIT: begin
                if (burst_done) next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ================================================================
    // 【第三段】数据通路与控制输出 (同步时序逻辑)
    // ================================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            phy_start         <= 1'b0;
            phy_tx_data       <= 8'h00;
            byte_cnt          <= {BURST_WIDTH{1'b0}};
            burst_len_latched <= {BURST_WIDTH{1'b0}};
            rx_valid_reg      <= 1'b0;
            spi_cs_n          <= 1'b1;
            done              <= 1'b0;
        end else begin
            // 默认脉冲信号清零
            phy_start    <= 1'b0;
            done         <= 1'b0;
            rx_valid_reg <= 1'b0;

            case (current_state)
                S_IDLE: begin
                    spi_cs_n <= 1'b1;

                    if (start) begin
                        // 锁存 burst_len 与第 1 个待发字节
                        burst_len_latched <= burst_len;
                        phy_tx_data       <= tx_data;
                        byte_cnt          <= {BURST_WIDTH{1'b0}};

                        // CS 拉低 + PHY 启动脉冲 (同一拍生效)
                        spi_cs_n          <= 1'b0;
                        phy_start         <= 1'b1;
                    end
                end

                S_WAIT: begin
                    spi_cs_n <= 1'b0;

                    if (phy_done) begin
                        // 当前字节接收完成 → 输出 rx_valid
                        rx_valid_reg <= 1'b1;

                        if (is_last_byte) begin
                            // ------------------------------
                            // 最后一个字节 → 完成事务收尾
                            // ------------------------------
                            spi_cs_n <= 1'b1;
                            done     <= 1'b1;
                        end else begin
                            // ------------------------------
                            // 还有后续字节 → 加载下一字节并再次启动 PHY
                            // ------------------------------
                            byte_cnt    <= byte_cnt + 1'b1;
                            phy_tx_data <= tx_data;
                            phy_start   <= 1'b1;
                        end
                    end
                end

                default: begin
                    spi_cs_n <= 1'b1;
                end
            endcase
        end
    end

endmodule
