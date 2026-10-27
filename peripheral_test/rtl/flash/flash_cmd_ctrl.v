// =============================================================================
// 命令模块顶层 (flash_cmd_ctrl) - 包含 FIFO1、FIFO2 与 flash_schedule_ctrl
// =============================================================================
module flash_cmd_ctrl (
    input clk,   // 系统工作时钟
    input rst_n, // 系统异步复位，低电平有效

    // 面向上游存储模块 (flash_store_ctrl)
    input         wr_en,     // 写/擦请求使能
    input  [ 1:0] wop_type,  // 操作类型: 2'b01 扇区擦除, 2'b10 写入
    input  [23:0] waddr_i,   // 写入目标地址
    input  [31:0] wdata_i,   // 写入数据
    output        wr_rdy,    // 写就绪指示（!fifo1_full）

    // 面向上游读取模块 (flash_read_ctrl)
    input         rd_en,    // 读请求使能
    input  [23:0] raddr_i,  // 读取目标地址
    output        rd_rdy,   // 读就绪指示（!fifo2_full）

    // 面向下游物理接口模块 (w25q16_phy)
    input         rdy,        // 物理层接口空闲/就绪指示
    input  [31:0] rdata,      // 驱动读出的 32 位数据
    input         rdata_vld,  // 驱动读出数据有效标志
    output        erase_en,   // 扇区擦除命令脉冲
    output        write_en,   // 写操作命令脉冲
    output        read_en,    // 读操作命令脉冲
    output [23:0] addr_o,     // 传给接口模块的目标地址
    output [31:0] wdata_o,    // 传给接口模块的写数据

    // 输出给上层业务/系统的数据结果闭环
    output [31:0] out_rdata,     // 读回数据输出给系统消费
    output        out_rdata_vld  // 读回数据有效指示
);

    // 穿透读出数据
    assign out_rdata     = rdata;
    assign out_rdata_vld = rdata_vld;

    // TODO: 例化 FIFO1 (写/擦请求缓冲, 宽度 58 位)
    // TODO: 例化 FIFO2 (读请求缓冲, 宽度 24 位)
    // TODO: 例化 flash_schedule_ctrl 调度内核

endmodule
