// =============================================================================
// 存储模块 (flash_store_ctrl) - 负责发起写/擦除请求
// =============================================================================
module flash_store_ctrl (
    input clk,   // 系统工作时钟
    input rst_n, // 系统异步复位，低电平有效

    // 外部触发/业务源（若为纯自动业务逻辑可由状态机产生）
    input        wr_trig,      // 单次操作触发指示（可选）
    input [ 1:0] din_op_type,  // 操作类型：2'b01: 扇区擦除(4KB), 2'b10: 写入(4字节)
    input [23:0] din_addr,     // 目标地址 (24 位)
    input [31:0] din_data,     // 待写入数据 (32 位 / 4 字节)

    // 与命令模块交互接口 (标准握手 rdy 机制)
    input             wr_rdy,    // 写就绪信号（来自 flash_cmd_ctrl，FIFO1 未满）
    output reg        wr_en,     // 写请求使能脉冲
    output reg [ 1:0] wop_type,  // 写入 FIFO 的操作类型
    output reg [23:0] waddr_i,   // 写入目标地址
    output reg [31:0] wdata_i    // 写入数据
);

    reg pending;

    // 空闲时锁存单次有效请求；等待期间保持操作类型、地址和数据不变。
    // 接口只缓存一条请求，等待期间的新触发不予接收。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending  <= 1'b0;
            wop_type <= 2'b00;
            waddr_i  <= 24'd0;
            wdata_i  <= 32'd0;
        end else if (!pending) begin
            if (wr_trig && ((din_op_type == 2'b01) || (din_op_type == 2'b10))) begin
                pending  <= 1'b1;
                wop_type <= din_op_type;
                waddr_i  <= din_addr;
                wdata_i  <= din_data;
            end
        end else if (wr_rdy) begin
            pending <= 1'b0;
        end
    end

    // 在 FIFO 实际采样的时钟沿检查就绪，避免就绪撤销后仍发出写请求。
    always @(*) begin
        wr_en = rst_n && pending && wr_rdy;
    end

endmodule
