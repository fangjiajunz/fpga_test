module spi_phy #(
    parameter CPOL      = 1'b0,  // 空闲时钟极性
    parameter CPHA      = 1'b0,  // 时钟相位
    parameter LSB_FIRST = 1'b0   // 字节内位顺序：0 = MSB first, 1 = LSB first
) (
    input wire sys_clk,   // 主时钟 (例如 50MHz)
    input wire sys_rst_n,

    input wire             start,
    input wire [7:0]       tx_data,

    output reg  [7:0]      rx_data,
    output wire            busy,
    output reg             done,

    output reg  spi_sclk,
    output reg  spi_mosi,
    input  wire spi_miso
);

    // 位宽固定为 8 bit（1 字节），bit_cnt 位宽固定为 3
    localparam DATA_WIDTH = 8;
    localparam CNT_WIDTH  = 3;

    // FSM 状态定义
    localparam IDLE     = 1'b0;
    localparam TRANSFER = 1'b1;

    reg                   state;
    reg [CNT_WIDTH-1:0]   bit_cnt;
    reg [DATA_WIDTH-1:0]  tx_shift_reg;
    reg [DATA_WIDTH-1:0]  rx_shift_reg;

    // 半周期计数器：0 代表半周期的前段，1 代表后段
    reg sclk_phase;

    assign busy = (state != IDLE);

    // ------------------------------------------------------------------------
    // FSM & 核心 SPI 物理层控制 (全 posedge 驱动)
    // ------------------------------------------------------------------------
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state        <= IDLE;
            spi_sclk     <= CPOL;
            spi_mosi     <= 1'b0;
            rx_data      <= 8'b0;
            tx_shift_reg <= 8'b0;
            rx_shift_reg <= 8'b0;
            bit_cnt      <= 3'b0;
            sclk_phase   <= 1'b0;
            done         <= 1'b0;
        end else begin
            done <= 1'b0;  // 默认拉低，生成单脉冲

            case (state)
                IDLE: begin
                    spi_sclk   <= CPOL;
                    sclk_phase <= 1'b0;
                    bit_cnt    <= 3'b0;

                    if (start) begin
                        state        <= TRANSFER;
                        tx_shift_reg <= tx_data;

                        // CPHA = 0 时，第0位数据必须在第一个 SCLK 边沿到来前拉出
                        if (CPHA == 1'b0) begin
                            spi_mosi <= LSB_FIRST ? tx_data[0] : tx_data[7];
                        end
                    end
                end

                TRANSFER: begin
                    // 翻转 SCLK 阶段（每拍翻转，2 拍 = 1 个 SCLK 周期）
                    sclk_phase <= ~sclk_phase;

                    if (sclk_phase == 1'b0) begin
                        // ===== 阶段 1: SCLK 产生第一个跳变沿 =====
                        spi_sclk <= ~CPOL;

                        if (CPHA == 1'b0) begin
                            // CPHA=0: 第一个沿采样 MISO
                            if (LSB_FIRST) rx_shift_reg[bit_cnt] <= spi_miso;
                            else rx_shift_reg[7-bit_cnt] <= spi_miso;
                        end else begin
                            // CPHA=1: 第一个沿更新 MOSI
                            if (LSB_FIRST) spi_mosi <= tx_shift_reg[bit_cnt];
                            else spi_mosi <= tx_shift_reg[7-bit_cnt];
                        end

                    end else begin
                        // ===== 阶段 2: SCLK 恢复/产生第二个跳变沿 =====
                        spi_sclk <= CPOL;

                        if (CPHA == 1'b0) begin
                            // CPHA=0: 第二个沿更新 MOSI
                            if (bit_cnt == 3'd7) begin
                                // 传输结束，完成收尾
                                state   <= IDLE;
                                done    <= 1'b1;
                                rx_data <= rx_shift_reg;
                            end else begin
                                bit_cnt <= bit_cnt + 1'b1;
                                if (LSB_FIRST) spi_mosi <= tx_shift_reg[bit_cnt+1'b1];
                                else spi_mosi <= tx_shift_reg[7-(bit_cnt+1'b1)];
                            end
                        end else begin
                            // CPHA=1: 第二个沿采样 MISO
                            if (LSB_FIRST) rx_shift_reg[bit_cnt] <= spi_miso;
                            else rx_shift_reg[7-bit_cnt] <= spi_miso;

                            if (bit_cnt == 3'd7) begin
                                state   <= IDLE;
                                done    <= 1'b1;
                                rx_data <= (LSB_FIRST) ?
                                           {spi_miso, rx_shift_reg[6:0]} :
                                           {rx_shift_reg[7:1], spi_miso};
                            end else begin
                                bit_cnt <= bit_cnt + 1'b1;
                            end
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
