// =============================================================================
// 存储模块 (flash_store_ctrl) - 负责发起写/擦除请求
//    上层写业务只与本模块交互；完全不与读取模块发生任何接触
// =============================================================================
module flash_store_ctrl (
    input clk,   // 系统工作时钟
    input rst_n, // 系统异步复位，低电平有效

    // =========================================================================
    //  面向上层用户/业务系统 (上层写业务只与此端口交互)
    // =========================================================================
    input        wr_trig,      // 单次写入/擦除触发指示 (如按键脉冲、串口写指令)
    input [ 1:0] din_op_type,  // 操作类型: 2'b01 扇区擦除, 2'b10 写入4字节
    input [23:0] din_addr,     // 待写入目标地址 (24 位)
    input [31:0] din_data,     // 待写入数据 (32 位 / 4 字节)

    // =========================================================================
    //  面向命令模块 (flash_cmd_ctrl / FIFO1) - 对应图中向 FIFO1 发请求
    // =========================================================================
    input             wr_rdy,    // 写就绪信号（来自 flash_cmd_ctrl，FIFO1 未满）
    output reg        wr_en,     // 写请求使能脉冲
    output reg [ 1:0] wop_type,  // 写入 FIFO 的操作类型
    output reg [23:0] waddr_i,   // 写入目标地址
    output reg [31:0] wdata_i    // 写入数据
);

    reg pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending  <= 1'b0;
            wop_type <= 2'b00;
            waddr_i  <= 24'd0;
            wdata_i  <= 32'd0;
            wr_en    <= 1'b0;
        end else begin
            wr_en <= 1'b0;
            if (!pending) begin
                if (wr_trig && ((din_op_type == 2'b01) || (din_op_type == 2'b10))) begin
                    if (wr_rdy) begin
                        wr_en    <= 1'b1;
                        wop_type <= din_op_type;
                        waddr_i  <= din_addr;
                        wdata_i  <= din_data;
                    end else begin
                        pending  <= 1'b1;
                        wop_type <= din_op_type;
                        waddr_i  <= din_addr;
                        wdata_i  <= din_data;
                    end
                end
            end else if (wr_rdy) begin
                pending <= 1'b0;
                wr_en   <= 1'b1;
            end
        end
    end

endmodule
