// =============================================================================
// Flash 系统顶层 (flash_top) - 对应《至简设计法》结构图中的最外层 FPGA 大方框
// 
// 架构特征：
// 1. 上层写业务只与 flash_store_ctrl 交互，上层读业务只与 flash_read_ctrl 交互；
// 2. 读写两条业务完全解耦隔离、互不干涉；
// 3. 内部自动通过 flash_cmd_ctrl 缓冲与调度，由 w25q16_phy 驱动外部物理引脚。
// =============================================================================
module flash_top (
    input               clk,            // 系统工作时钟 (50MHz)
    input               rst_n,          // 系统异步复位，低有效

    // =========================================================================
    // 1. 上层写业务独立通道 (只连接存储模块 flash_store_ctrl)
    // =========================================================================
    input               user_wr_trig,   // 写/擦触发脉冲
    input       [1:0]   user_op_type,   // 2'b01: 扇区擦除, 2'b10: 写入4字节
    input       [23:0]  user_wr_addr,   // 目标地址
    input       [31:0]  user_wr_data,   // 待写数据
    output              user_wr_rdy,    // 写就绪状态指示

    // =========================================================================
    // 2. 上层读业务独立通道 (只连接读取模块 flash_read_ctrl)
    // =========================================================================
    input               user_rd_trig,   // 读触发脉冲
    input       [23:0]  user_rd_addr,   // 读目标地址
    output              user_rd_rdy,    // 读就绪状态指示
    output      [31:0]  user_rd_data,   // 读回并消费的数据
    output              user_rd_vld,    // 读回数据有效标志

    // =========================================================================
    // 3. 外部 Flash 物理引脚 (直连外部 W25Q16 芯片)
    // =========================================================================
    output              spi_cs_n,       // 片选 (PIN_D2)
    output              spi_sclk,       // 串行时钟 (PIN_H1)
    output              spi_mosi,       // 主出从入 (PIN_C1)
    input               spi_miso        // 主入从出 (PIN_H2)
);

    // =========================================================================
    // 内部连线：存储模块 -> 命令模块 (FIFO1)
    // =========================================================================
    wire                store_wr_en;
    wire        [1:0]   store_op_type;
    wire        [23:0]  store_waddr;
    wire        [31:0]  store_wdata;
    wire                cmd_wr_rdy;

    assign user_wr_rdy = cmd_wr_rdy;

    // =========================================================================
    // 内部连线：读取模块 -> 命令模块 (FIFO2)
    // =========================================================================
    wire                read_rd_en;
    wire        [23:0]  read_raddr;
    wire                cmd_rd_rdy;

    assign user_rd_rdy = cmd_rd_rdy;

    // =========================================================================
    // 内部连线：命令模块 -> 接口模块 (w25q16_phy)
    // =========================================================================
    wire                cmd_erase_en;
    wire                cmd_write_en;
    wire                cmd_read_en;
    wire        [23:0]  cmd_addr;
    wire        [31:0]  cmd_wdata;
    wire                phy_rdy;

    // =========================================================================
    // 内部连线：接口模块 (w25q16_phy) -> 读取模块 (读回数据闭环直连)
    // =========================================================================
    wire        [31:0]  phy_rdata;
    wire                phy_rdata_vld;

    // =========================================================================
    // 模块例化 1：存储模块
    // =========================================================================
    flash_store_ctrl u_flash_store_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .wr_trig        (user_wr_trig),
        .din_op_type    (user_op_type),
        .din_addr       (user_wr_addr),
        .din_data       (user_wr_data),
        .wr_rdy         (cmd_wr_rdy),
        .wr_en          (store_wr_en),
        .wop_type       (store_op_type),
        .waddr_i        (store_waddr),
        .wdata_i        (store_wdata)
    );

    // =========================================================================
    // 模块例化 2：读取模块
    // =========================================================================
    flash_read_ctrl u_flash_read_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .rd_trig        (user_rd_trig),
        .din_addr       (user_rd_addr),
        .user_rdata     (user_rd_data),
        .user_rdata_vld (user_rd_vld),
        .rd_rdy         (cmd_rd_rdy),
        .rd_en          (read_rd_en),
        .raddr_i        (read_raddr),
        .rdata          (phy_rdata),        // 读回数据直通读取模块
        .rdata_vld      (phy_rdata_vld)
    );

    // =========================================================================
    // 模块例化 3：命令模块 (包含写FIFO1、读FIFO2、调度内核)
    // =========================================================================
    flash_cmd_ctrl u_flash_cmd_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .wr_en          (store_wr_en),
        .wop_type       (store_op_type),
        .waddr_i        (store_waddr),
        .wdata_i        (store_wdata),
        .wr_rdy         (cmd_wr_rdy),
        .rd_en          (read_rd_en),
        .raddr_i        (read_raddr),
        .rd_rdy         (cmd_rd_rdy),
        .rdy            (phy_rdy),
        .erase_en       (cmd_erase_en),
        .write_en       (cmd_write_en),
        .read_en        (cmd_read_en),
        .addr_o         (cmd_addr),
        .wdata_o        (cmd_wdata)
    );

    // =========================================================================
    // 模块例化 4：接口驱动模块 (直连外部物理芯片引脚)
    // =========================================================================
    w25q16_phy u_w25q16_phy (
        .clk            (clk),
        .rst_n          (rst_n),
        .erase_en       (cmd_erase_en),
        .write_en       (cmd_write_en),
        .read_en        (cmd_read_en),
        .addr_o         (cmd_addr),
        .wdata_o        (cmd_wdata),
        .rdy            (phy_rdy),
        .rdata          (phy_rdata),
        .rdata_vld      (phy_rdata_vld),
        .spi_cs_n       (spi_cs_n),
        .spi_sclk       (spi_sclk),
        .spi_mosi       (spi_mosi),
        .spi_miso       (spi_miso)
    );

endmodule
