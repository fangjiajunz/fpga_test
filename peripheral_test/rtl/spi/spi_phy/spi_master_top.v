module spi_master_top #(
    parameter integer DATA_WIDTH = 8,
    parameter         CPOL       = 1'b0,
    parameter         CPHA       = 1'b0,
    parameter         LSB_FIRST  = 1'b0
) (
    input wire sys_clk,
    input wire sys_rst_n,

    // 上层操作接口
    input wire                  start,
    input wire [DATA_WIDTH-1:0] tx_data,

    output reg  [DATA_WIDTH-1:0] rx_data,
    output wire                  busy,
    output reg                   done,

    // SPI 物理接口
    output reg  spi_cs_n,
    output wire spi_sclk,
    output wire spi_mosi,
    input  wire spi_miso
);

    // ================================================================
    // 上层状态机（2 状态：消除 ST_START / ST_FINISH，CS 开销从 4 拍降至 2 拍）
    // ================================================================

    localparam ST_IDLE = 1'b0;
    localparam ST_WAIT = 1'b1;

    reg state;

    // ================================================================
    // SPI PHY 内部信号
    // ================================================================

    reg                   phy_start;
    reg  [DATA_WIDTH-1:0] phy_tx_data;

    wire [DATA_WIDTH-1:0] phy_rx_data;
    wire                  phy_busy;
    wire                  phy_done;

    assign busy = (state != ST_IDLE);

    // ================================================================
    // SPI PHY 实例化
    // ================================================================

    spi_phy #(
        .DATA_WIDTH(DATA_WIDTH),
        .CPOL      (CPOL),
        .CPHA      (CPHA),
        .LSB_FIRST (LSB_FIRST)
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
    // 上层控制状态机（2 状态，消除 ST_START / ST_FINISH）
    //
    // 时序说明（DATA_WIDTH=8, CPOL=0, CPHA=0, sys_clk=50MHz 为例）：
    //
    //   周期 | Master | CS  | PHY       | SCLK  | 说明
    //   ─────┼────────┼─────┼───────────┼───────┼──────────────────────
    //   N    | IDLE   | 1→0 | IDLE      | CPOL  | start=1, CS 拉低, phy_start 脉冲
    //   N+1  | WAIT   | 0   | IDLE      | CPOL  | PHY 采样 start, 锁存 tx_data
    //   N+2  | WAIT   | 0   | TRANSFER  | 0→1   | 第 1 个 SCLK 沿 (t_CSS=2)
    //   ...  | WAIT   | 0   | TRANSFER  | 翻转  | 16 拍数据传输 (2N)
    //   N+17 | WAIT   | 0   | TRANSFER  | 1→0   | 最后半周期, PHY done=1
    //   N+18 | WAIT   | 0→1 | IDLE      | CPOL  | CS 释放, done 脉冲 (t_CSH=1)
    //
    //   总开销 = 2 拍（优化前 = 4 拍）
    //   CS 低 = 2N+2 = 18 拍（优化前 = 2N+4 = 20 拍）
    //
    //   t_CSS ≈ 2·T_sysclk = 40ns（从 CS↓ 到 SCLK 第一沿）
    //   t_CSH ≈ 1·T_sysclk = 20ns（从 SCLK 最后沿到 CS↑）
    // ================================================================

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state       <= ST_IDLE;
            phy_start   <= 1'b0;
            phy_tx_data <= {DATA_WIDTH{1'b0}};
            rx_data     <= {DATA_WIDTH{1'b0}};
            spi_cs_n    <= 1'b1;
            done        <= 1'b0;
        end else begin
            // 默认值，保证 phy_start / done 为单周期脉冲
            phy_start <= 1'b0;
            done      <= 1'b0;

            case (state)

                // ----------------------------------------------------
                // 空闲：等待上层启动
                // 收到 start 后，同一拍拉低 CS 并发出 phy_start 脉冲
                // ----------------------------------------------------
                ST_IDLE: begin
                    spi_cs_n <= 1'b1;

                    if (start) begin
                        // 锁存发送数据
                        phy_tx_data <= tx_data;

                        // CS 拉低 + PHY 启动（同一拍）
                        spi_cs_n  <= 1'b0;
                        phy_start <= 1'b1;

                        state <= ST_WAIT;
                    end
                end

                // ----------------------------------------------------
                // 等待：PHY 传输中
                // 传输完成后立即释放 CS 并发出 done 脉冲
                // ----------------------------------------------------
                ST_WAIT: begin
                    spi_cs_n <= 1'b0;

                    if (phy_done) begin
                        // 锁存接收到的数据
                        rx_data <= phy_rx_data;

                        // 释放片选并发出完成脉冲
                        spi_cs_n <= 1'b1;
                        done     <= 1'b1;

                        state <= ST_IDLE;
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
