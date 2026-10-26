// =============================================================================
// 3. 调度模块 (schedule_ctrl) - 命令模块的核心内核
// =============================================================================
module schedule_ctrl (
    input               clk,        // 系统时钟
    input               rst_n,      // 系统复位

    // 连接内部 FIFO1 (写请求缓存，存 {waddr[6:0], wdata[7:0]})
    input               fifo1_empty,// FIFO1 空标志
    input       [14:0]  fifo1_q,    // FIFO1 读出数据
    output reg          fifo1_rdreq,// FIFO1 读请求使能

    // 连接内部 FIFO2 (读请求缓存，存 {raddr[6:0]})
    input               fifo2_empty,// FIFO2 空标志
    input       [6:0]   fifo2_q,    // FIFO2 读出数据
    output reg          fifo2_rdreq,// FIFO2 读请求使能

    // 驱动接口模块
    input               rdy,        // 接口模块空闲指示
    output reg          ewen_en,    // 擦写使能命令脉冲
    output reg          write_en,   // 写操作命令脉冲
    output reg          read_en,    // 读操作命令脉冲
    output reg  [6:0]   addr_o,     // 传给接口的目标地址
    output reg  [7:0]   wdata_o     // 传给接口的写入数据
);

endmodule
