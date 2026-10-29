// =============================================================================
//  命令模块 (flash_cmd_ctrl) - 对应教材结构图中的【命令模块】
//    内部包含：存储模块 (store_ctrl)、读取模块 (read_ctrl)、调度模块 (schedule_ctrl)
//    上层读写业务只与本模块交互；下层直接与接口模块对接
// =============================================================================
module flash_cmd_ctrl (
    input clk,   // 系统工作时钟
    input rst_n, // 系统异步复位，低电平有效

    // =========================================================================
    // 1. 上层写业务独立通道 (进入存储模块)
    // =========================================================================
    input         user_wr_trig,  // 写/擦触发脉冲
    input  [ 1:0] user_op_type,  // 2'b01: 扇区擦除, 2'b10: 写入4字节
    input  [23:0] user_wr_addr,  // 目标地址
    input  [31:0] user_wr_data,  // 待写数据
    output        user_wr_rdy,   // 写就绪状态指示

    // =========================================================================
    // 2. 上层读业务独立通道 (进出读取模块)
    // =========================================================================
    input         user_rd_trig,  // 读触发脉冲
    input  [23:0] user_rd_addr,  // 读目标地址
    output        user_rd_rdy,   // 读就绪状态指示
    output [31:0] user_rd_data,  // 读回并消费的数据
    output        user_rd_vld,   // 读回数据有效标志

    // =========================================================================
    // 3. 面向下游接口驱动模块 (w25q16_phy)
    // =========================================================================
    input             rdy,        // 接口模块空闲/就绪指示
    output            erase_en,   // 扇区擦除命令脉冲 (对应图中的 ewen_en)
    output            write_en,   // 写操作命令脉冲
    output            read_en,    // 读操作命令脉冲
    output     [23:0] addr_o,     // 传给接口模块的目标地址
    output     [31:0] wdata_o,    // 传给接口模块的写数据
    input      [31:0] rdata,      // 接口模块返回的 32 位读数据 (直通读取模块)
    input             rdata_vld   // 接口模块返回的读数据有效标志
);

    // =========================================================================
    // 内部连线：存储模块 -> 调度模块 (FIFO1)
    // =========================================================================
    wire        store_wr_en;
    wire [ 1:0] store_op_type;
    wire [23:0] store_waddr;
    wire [31:0] store_wdata;
    wire        sched_wr_rdy;

    assign user_wr_rdy = sched_wr_rdy;

    // =========================================================================
    // 内部连线：读取模块 -> 调度模块 (FIFO2)
    // =========================================================================
    wire        read_rd_en;
    wire [23:0] read_raddr;
    wire        sched_rd_rdy;

    assign user_rd_rdy = sched_rd_rdy;

    // =========================================================================
    // 子模块 1：存储模块 (flash_store_ctrl)
    // =========================================================================
    flash_store_ctrl u_flash_store_ctrl (
        .clk        (clk),
        .rst_n      (rst_n),
        .wr_trig    (user_wr_trig),
        .din_op_type(user_op_type),
        .din_addr   (user_wr_addr),
        .din_data   (user_wr_data),
        .wr_rdy     (sched_wr_rdy),
        .wr_en      (store_wr_en),
        .wop_type   (store_op_type),
        .waddr_i    (store_waddr),
        .wdata_i    (store_wdata)
    );

    // =========================================================================
    // 子模块 2：读取模块 (flash_read_ctrl)
    // =========================================================================
    flash_read_ctrl u_flash_read_ctrl (
        .clk           (clk),
        .rst_n         (rst_n),
        .rd_trig       (user_rd_trig),
        .din_addr      (user_rd_addr),
        .user_rdata    (user_rd_data),
        .user_rdata_vld(user_rd_vld),
        .rd_rdy        (sched_rd_rdy),
        .rd_en         (read_rd_en),
        .raddr_i       (read_raddr),
        .rdata         (rdata),       // 接口模块读回数据直通读取模块
        .rdata_vld     (rdata_vld)
    );

    // =========================================================================
    // 子模块 3：调度模块 (flash_schedule_ctrl，内含 FIFO1 与 FIFO2)
    // =========================================================================
    flash_schedule_ctrl u_flash_schedule_ctrl (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_en   (store_wr_en),
        .wop_type(store_op_type),
        .waddr_i (store_waddr),
        .wdata_i (store_wdata),
        .wr_rdy  (sched_wr_rdy),
        .rd_en   (read_rd_en),
        .raddr_i (read_raddr),
        .rd_rdy  (sched_rd_rdy),
        .rdy     (rdy),
        .erase_en(erase_en),
        .write_en(write_en),
        .read_en (read_en),
        .addr_o  (addr_o),
        .wdata_o (wdata_o)
    );

endmodule
