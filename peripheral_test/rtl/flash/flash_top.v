// =============================================================================

// =============================================================================
module flash_top (
    input clk,   // 系统工作时钟 (50MHz)
    input rst_n, // 系统异步复位，低有效

    // =========================================================================
    // 上层写业务通道 (直连命令模块)
    // =========================================================================
    input         user_wr_trig,  // 写/擦触发脉冲
    input  [ 1:0] user_op_type,  // 2'b01: 扇区擦除, 2'b10: 写入4字节
    input  [23:0] user_wr_addr,  // 目标地址
    input  [31:0] user_wr_data,  // 待写数据
    output        user_wr_rdy,   // 写就绪状态指示
    output        user_wr_done,  // 写入/擦除底层完成指示脉冲

    // =========================================================================
    //  上层读业务通道 (直连命令模块)
    // =========================================================================
    input         user_rd_trig,  // 读触发脉冲
    input  [23:0] user_rd_addr,  // 读目标地址
    output        user_rd_rdy,   // 读就绪状态指示
    output [31:0] user_rd_data,  // 读回并消费的数据
    output        user_rd_vld,   // 读回数据有效标志

    // =========================================================================
    //  外部 Flash 物理引脚 (由接口模块直连外部 W25Q16 芯片)
    // =========================================================================
    output spi_cs_n,  // 片选 (PIN_D2)
    output spi_sclk,  // 串行时钟 (PIN_H1)
    output spi_mosi,  // 主出从入 (PIN_C1)
    input  spi_miso   // 主入从出 (PIN_H2)
);

    // =========================================================================
    // 模块间互联连线：【命令模块】 <----> 【接口模块】
    // =========================================================================
    wire        cmd_erase_en;
    wire        cmd_write_en;
    wire        cmd_read_en;
    wire [23:0] cmd_addr;
    wire [31:0] cmd_wdata;
    wire        phy_rdy;
    wire [31:0] phy_rdata;
    wire        phy_rdata_vld;

    // =========================================================================
    //  (内含存储、读取、调度及双 FIFO 队列)
    // =========================================================================
    flash_cmd_ctrl u_flash_cmd_ctrl (
        .clk  (clk),
        .rst_n(rst_n),

        // 用户写通道
        .user_wr_trig(user_wr_trig),
        .user_op_type(user_op_type),
        .user_wr_addr(user_wr_addr),
        .user_wr_data(user_wr_data),
        .user_wr_rdy (user_wr_rdy),

        // 用户读通道
        .user_rd_trig(user_rd_trig),
        .user_rd_addr(user_rd_addr),
        .user_rd_rdy (user_rd_rdy),
        .user_rd_data(user_rd_data),
        .user_rd_vld (user_rd_vld),

        // 面对接口模块
        .rdy      (phy_rdy),
        .erase_en (cmd_erase_en),
        .write_en (cmd_write_en),
        .read_en  (cmd_read_en),
        .addr_o   (cmd_addr),
        .wdata_o  (cmd_wdata),
        .rdata    (phy_rdata),
        .rdata_vld(phy_rdata_vld)
    );

    // =========================================================================
    //   (物理协议机，直连外部芯片引脚)
    // =========================================================================
    w25q16_phy u_w25q16_phy (
        .clk  (clk),
        .rst_n(rst_n),

        // 面对命令模块
        .erase_en (cmd_erase_en),
        .write_en (cmd_write_en),
        .read_en  (cmd_read_en),
        .addr_o   (cmd_addr),
        .wdata_o  (cmd_wdata),
        .rdy      (phy_rdy),
        .rdata    (phy_rdata),
        .rdata_vld(phy_rdata_vld),
        .wr_done  (user_wr_done),

        // 面对外部物理芯片引脚
        .spi_cs_n(spi_cs_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );

endmodule
