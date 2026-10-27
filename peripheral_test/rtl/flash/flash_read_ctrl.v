// =============================================================================
//  读取模块 (flash_read_ctrl) - 负责发起读请求与消费读回数据
// =============================================================================
module flash_read_ctrl (
    input clk,   // 系统工作时钟
    input rst_n, // 系统异步复位，低电平有效

    // 外部触发/业务源（若为纯自动业务逻辑可由状态机产生）
    input        rd_trig,  // 单次读取触发指示（可选）
    input [23:0] din_addr, // 待读取目标地址 (24 位)

    // 与命令模块交互接口 (发送读请求)
    input             rd_rdy,  // 读就绪信号（来自 flash_cmd_ctrl，FIFO2 未满）
    output reg        rd_en,   // 读请求使能脉冲
    output reg [23:0] raddr_i, // 读取目标地址

    // 接收底层读回的数据闭环 (消费端)
    input      [31:0] in_rdata,       // 底层返回的 32 位读数据
    input             in_rdata_vld,   // 读数据有效指示脉冲
    output reg [31:0] user_rdata,     // 输出给用户/业务模块的数据
    output reg        user_rdata_vld  // 输出给用户/业务模块的有效指示
);

    // TODO: 具体读取触发与数据缓存消费逻辑后续实现

endmodule
