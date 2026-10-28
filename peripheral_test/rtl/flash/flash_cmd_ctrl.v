// =============================================================================
// 4. 命令模块顶层 (flash_cmd_ctrl) - 包含 FIFO1、FIFO2 与 flash_schedule_ctrl
//    严格对照结构图中部：只负责命令缓冲与调度，不碰读回的数据流
// =============================================================================
module flash_cmd_ctrl (
    input               clk,            // 系统工作时钟
    input               rst_n,          // 系统异步复位，低电平有效

    // 面向上游存储模块 (flash_store_ctrl) - 对应图中连到 FIFO1 的端口
    input               wr_en,          // 写/擦请求使能
    input       [1:0]   wop_type,       // 操作类型: 2'b01 扇区擦除, 2'b10 写入
    input       [23:0]  waddr_i,        // 写入目标地址
    input       [31:0]  wdata_i,        // 写入数据
    output              wr_rdy,         // 写就绪指示（!fifo1_full）

    // 面向上游读取模块 (flash_read_ctrl) - 对应图中连到 FIFO2 的端口
    input               rd_en,          // 读请求使能
    input       [23:0]  raddr_i,        // 读取目标地址
    output              rd_rdy,         // 读就绪指示（!fifo2_full）

    // 面向下游接口驱动模块 (w25q16_phy) - 对应图中发给接口模块的命令脉冲
    input               rdy,            // 接口模块空闲/就绪指示
    output              erase_en,       // 扇区擦除命令脉冲 (对应图中的 ewen_en)
    output              write_en,       // 写操作命令脉冲
    output              read_en,        // 读操作命令脉冲
    output      [23:0]  addr_o,         // 传给接口模块的目标地址
    output      [31:0]  wdata_o         // 传给接口模块的写数据
);

    // TODO: 例化 FIFO1 (写/擦请求缓冲, 宽度 58 位: {op_type, addr, wdata})
    // TODO: 例化 FIFO2 (读请求缓冲, 宽度 24 位: {addr})
    // TODO: 例化 flash_schedule_ctrl 调度内核

endmodule
