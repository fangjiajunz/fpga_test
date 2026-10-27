// =============================================================================
//  调度模块 (flash_schedule_ctrl) - 命令模块的核心调度仲裁内核
// =============================================================================
module flash_schedule_ctrl (
    input clk,   // 系统工作时钟
    input rst_n, // 系统异步复位，低电平有效

    // 连接内部 FIFO1 (写/擦除请求缓存，格式: {op_type[1:0], waddr[23:0], wdata[31:0]}，共 58 位)
    input             fifo1_empty,  // FIFO1 空指示
    input      [57:0] fifo1_q,      // FIFO1 读出数据
    output reg        fifo1_rdreq,  // FIFO1 读使能脉冲

    // 连接内部 FIFO2 (读请求缓存，格式: {raddr[23:0]}，共 24 位)
    input             fifo2_empty,  // FIFO2 空指示
    input      [23:0] fifo2_q,      // FIFO2 读出数据
    output reg        fifo2_rdreq,  // FIFO2 读使能脉冲

    // 驱动物理接口模块 (面对 w25q16_phy)
    input             rdy,       // 物理层接口空闲指示 (1: 空闲, 0: 忙碌中)
    output reg        erase_en,  // 扇区擦除操作命令脉冲
    output reg        write_en,  // 页写操作命令脉冲
    output reg        read_en,   // 读数据操作命令脉冲
    output reg [23:0] addr_o,    // 传给接口模块的目标地址 (24 位)
    output reg [31:0] wdata_o    // 传给接口模块的写数据 (32 位)
);

    // TODO: 读写仲裁策略与命令分发状态机后续实现（例如读优先或轮询）

endmodule
