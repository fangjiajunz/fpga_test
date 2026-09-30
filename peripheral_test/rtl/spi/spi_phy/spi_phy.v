module spi_phy #(
    parameter CPOL      = 1'b0,  // 空闲时钟极性
    parameter CPHA      = 1'b0,  // 时钟相位
    parameter LSB_FIRST = 1'b0   // 字节内位顺序：0 = MSB first, 1 = LSB first
) (
    input wire sys_clk,   // 主时钟 (例如 50MHz)
    input wire sys_rst_n,

    input wire       start,
    input wire [7:0] tx_data,

    output reg  [7:0] rx_data,
    output wire       busy,
    output reg        done,

    output reg  spi_sclk,
    output reg  spi_mosi,
    input  wire spi_miso
);

    // 位宽固定为 8 bit（1 字节），bit_cnt 位宽固定为 3
    localparam DATA_WIDTH = 8;
    localparam CNT_WIDTH = 3;

    // FSM 状态定义
    localparam S_IDLE = 1'b0;
    localparam S_TRANSFER = 1'b1;

    reg current_state;
    reg next_state;

    reg [CNT_WIDTH-1:0] bit_cnt;
    reg [DATA_WIDTH-1:0] tx_shift_reg;
    reg [DATA_WIDTH-1:0] rx_shift_reg;

    // 半周期计数器：0 代表半周期的前段，1 代表后段
    reg sclk_phase;

    // 传输完成触发指示：在阶段 2 且处理完第 7 位时置高
    wire transfer_done = (current_state == S_TRANSFER) && (sclk_phase == 1'b1) && (bit_cnt == 3'd7);

    assign busy = (current_state != S_IDLE);

    // =========================================================================
    // 【第一段】现态时序寄存器
    // =========================================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            current_state <= S_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // =========================================================================
    // 【第二段】次态组合逻辑决策
    // =========================================================================
    always @(*) begin
        next_state = current_state;

        case (current_state)
            S_IDLE: begin
                if (start) next_state = S_TRANSFER;
            end

            S_TRANSFER: begin
                if (transfer_done) next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // =========================================================================
    // 【第三段】数据通路与 SPI 引脚时序驱动
    // =========================================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            spi_sclk     <= CPOL;
            spi_mosi     <= 1'b0;
            rx_data      <= 8'b0;
            tx_shift_reg <= 8'b0;
            rx_shift_reg <= 8'b0;
            bit_cnt      <= 3'b0;
            sclk_phase   <= 1'b0;
            done         <= 1'b0;
        end else begin
            done <= 1'b0;  // 默认拉低，生成单周期脉冲

            case (current_state)
                S_IDLE: begin
                    spi_sclk   <= CPOL;
                    sclk_phase <= 1'b0;
                    bit_cnt    <= 3'd0;

                    if (start) begin
                        tx_shift_reg <= tx_data;

                        // CPHA = 0 时，第 0 位数据必须在第一个 SCLK 边沿到来前拉出
                        if (CPHA == 1'b0) begin
                            spi_mosi <= LSB_FIRST ? tx_data[0] : tx_data[7];
                        end
                    end
                end

                S_TRANSFER: begin
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
                                done    <= 1'b1;
                                rx_data <= rx_shift_reg;
                            end else begin
                                bit_cnt  <= bit_cnt + 1'b1;
                                spi_mosi <= LSB_FIRST ? tx_shift_reg[bit_cnt+1'b1] : tx_shift_reg[7-(bit_cnt+1'b1)];
                            end
                        end else begin
                            // CPHA=1: 第二个沿采样 MISO
                            if (LSB_FIRST) rx_shift_reg[bit_cnt] <= spi_miso;
                            else rx_shift_reg[7-bit_cnt] <= spi_miso;

                            if (bit_cnt == 3'd7) begin
                                done    <= 1'b1;
                                rx_data <= (LSB_FIRST) ? {spi_miso, rx_shift_reg[6:0]} : {rx_shift_reg[7:1], spi_miso};
                            end else begin
                                bit_cnt <= bit_cnt + 1'b1;
                            end
                        end
                    end
                end

                default: ;
            endcase
        end
    end

endmodule
