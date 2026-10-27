// =============================================================================
//  接口模块 (w25q16_phy) - 严格对照《至简设计法》结构图中的“接口模块”
//    左侧对接命令调度模块，右侧直连外部 W25Q16 芯片物理引脚
// =============================================================================
module w25q16_phy (
    input clk,   // 系统工作时钟 (50MHz)
    input rst_n, // 系统异步复位，低有效

    // =========================================================================
    // 面对内部命令模块 (flash_cmd_ctrl / 调度模块)
    // =========================================================================
    input             erase_en,  // 扇区擦除命令脉冲 (对应图中的 ewen_en)
    input             write_en,  // 页写命令脉冲     (对应图中的 write_en)
    input             read_en,   // 读数据命令脉冲   (对应图中的 read_en)
    input      [23:0] addr_o,    // 目标操作地址     (对应图中的 addr_o)
    input      [31:0] wdata_o,   // 待写入数据       (对应图中的 wdata_o)
    output reg        rdy,       // 接口空闲/就绪指示(对应图中的 rdy)
    output reg [31:0] rdata,     // 读出的数据       (对应图中的 rdata)
    output reg        rdata_vld, // 读数据有效指示   (对应图中的 rdata_vld)

    // =========================================================================
    // 直接连接外部物理芯片引脚 (FPGA 外部管脚)
    // =========================================================================
    output reg  spi_cs_n,  // 片选，低有效     (对应图中的 cs)
    output wire spi_sclk,  // 串行同步时钟     (对应图中的 sk)
    output wire spi_mosi,  // 串行数据输出     (对应图中的 di)
    input  wire spi_miso   // 串行数据输入     (对应图中的 do)
);

    // =========================================================================
    // 内部连线：复用 spi_master_top 时作为内部握手信号 (对外部完全不可见)
    // =========================================================================
    /*
    wire        spi_start;
    wire [7:0]  spi_burst_len;
    wire        spi_tx_req;
    wire [7:0]  spi_tx_byte;
    wire        spi_rx_valid;
    wire [7:0]  spi_rx_byte;
    wire        spi_busy;
    wire        spi_done;

    spi_master_top u_spi_master_top (
        .sys_clk    (clk),
        .sys_rst_n  (rst_n),
        .start      (spi_start),
        .burst_len  (spi_burst_len),
        .tx_req     (spi_tx_req),
        .tx_data    (spi_tx_byte),
        .rx_valid   (spi_rx_valid),
        .rx_byte    (spi_rx_byte),
        .busy       (spi_busy),
        .done       (spi_done),
        .spi_cs_n   (spi_cs_n),
        .spi_sclk   (spi_sclk),
        .spi_mosi   (spi_mosi),
        .spi_miso   (spi_miso)
    );
    */

    // TODO: 具体协议状态机（自动 WREN、擦除/写/读时序、WIP 轮询）后续实现

endmodule
