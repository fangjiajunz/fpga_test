// =============================================================================
//  读取模块 (flash_read_ctrl) - 负责发起读请求与消费读回数据
//    上层读业务只与本模块交互；读回数据直接由接口模块闭环返回本模块
// =============================================================================
module flash_read_ctrl (
    input clk,   // 系统工作时钟
    input rst_n, // 系统异步复位，低电平有效

    // =========================================================================
    // 1. 面向上层用户/业务系统 (上层读业务只与此端口交互)
    // =========================================================================
    input             rd_trig,        // 单次读取触发指示 (如按键脉冲、串口读指令)
    input      [23:0] din_addr,       // 待读取的目标地址 (24 位)
    output reg [31:0] user_rdata,     // 读回并消费的 32 位数据 (给上层)
    output reg        user_rdata_vld, // 读回数据有效指示 (给上层)

    // =========================================================================
    // 2. 面向命令模块 (flash_cmd_ctrl / FIFO2) - 对应图中向 FIFO2 发请求
    // =========================================================================
    input             rd_rdy,  // 读就绪信号（来自 flash_cmd_ctrl，FIFO2 未满）
    output reg        rd_en,   // 读请求使能脉冲
    output reg [23:0] raddr_i, // 读取目标地址

    // =========================================================================
    // 3. 接收接口模块 (w25q16_phy) 读回的数据闭环 (对应图中 rdata, rdata_vld 直连读取模块)
    // =========================================================================
    input [31:0] rdata,     // 接口模块返回的 32 位并行数据
    input        rdata_vld  // 接口模块返回的读数据有效标志
);

    reg pending;

    // 读请求触发与排队逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending <= 1'b0;
            raddr_i <= 24'd0;
            rd_en   <= 1'b0;
        end else begin
            rd_en <= 1'b0;
            if (!pending) begin
                if (rd_trig) begin
                    if (rd_rdy) begin
                        rd_en   <= 1'b1;
                        raddr_i <= din_addr;
                    end else begin
                        pending <= 1'b1;
                        raddr_i <= din_addr;
                    end
                end
            end else if (rd_rdy) begin
                pending <= 1'b0;
                rd_en   <= 1'b1;
            end
        end
    end

    // 读回数据采样与上报
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            user_rdata     <= 32'd0;
            user_rdata_vld <= 1'b0;
        end else begin
            user_rdata_vld <= rdata_vld;
            if (rdata_vld) begin
                user_rdata <= rdata;
            end
        end
    end

endmodule
