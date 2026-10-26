// =============================================================================
// 4. 命令模块顶层 (cmd_ctrl) - 包含 FIFO1、FIFO2 与 schedule_ctrl
// =============================================================================
module cmd_ctrl (
    input               clk,        // 系统工作时钟
    input               rst_n,      // 系统异步复位，低电平有效

    // 面向上游存储模块
    input               wr_en,      // 写请求使能
    input       [6:0]   waddr_i,    // 写目标地址
    input       [7:0]   wdata_i,    // 写数据
    output              wr_rdy,     // 写就绪（!fifo1_full）

    // 面向上游读取模块
    input               rd_en,      // 读请求使能
    input       [6:0]   raddr_i,    // 读目标地址
    output              rd_rdy,     // 读就绪（!fifo2_full）

    // 面向下游接口模块
    input               rdy,        // 接口模块空闲/就绪指示
    input       [7:0]   rdata,      // 驱动读出的数据
    input               rdata_vld,  // 驱动读出数据有效标志
    output              ewen_en,    // 擦写使能命令脉冲
    output              write_en,   // 写操作命令脉冲
    output              read_en,    // 读操作命令脉冲
    output      [6:0]   addr_o,     // 传给接口模块的目标地址
    output      [7:0]   wdata_o,    // 传给接口模块的写数据

    // 【关键闭环补充】输出给上层业务/系统的数据结果
    output      [7:0]   out_rdata,  // 读回数据输出给系统消费
    output              out_rdata_vld
);

    // 穿透或打拍输出数据
    assign out_rdata     = rdata;
    assign out_rdata_vld = rdata_vld;

    // 此处例化 FIFO1、FIFO2 与 schedule_ctrl ...

endmodule
