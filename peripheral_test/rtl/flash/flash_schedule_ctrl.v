// =============================================================================
//  调度模块 (flash_schedule_ctrl) - 调度仲裁内核 (内部集成 FIFO1 与 FIFO2)
//    严格对照教材结构图：调度模块内部包含 FIFO1 与 FIFO2，并负责向接口模块分发命令
// =============================================================================
module flash_schedule_ctrl (
    input clk,   // 系统工作时钟
    input rst_n, // 系统异步复位，低电平有效

    // 面向上游存储模块 (flash_store_ctrl) - 连接内部 FIFO1
    input         wr_en,     // 写使能脉冲
    input  [ 1:0] wop_type,  // 操作类型: 2'b01 扇区擦除, 2'b10 写入4字节
    input  [23:0] waddr_i,   // 目标写地址
    input  [31:0] wdata_i,   // 待写数据
    output        wr_rdy,    // 写就绪指示 (!fifo1_full)

    // 面向上游读取模块 (flash_read_ctrl) - 连接内部 FIFO2
    input         rd_en,    // 读使能脉冲
    input  [23:0] raddr_i,  // 目标读地址
    output        rd_rdy,   // 读就绪指示 (!fifo2_full)

    // 面向下游物理接口模块 (w25q16_phy)
    input             rdy,       // 接口模块空闲/就绪指示
    output reg        erase_en,  // 扇区擦除命令脉冲 (对应图中的 ewen_en)
    output reg        write_en,  // 页写操作命令脉冲
    output reg        read_en,   // 读数据操作命令脉冲
    output reg [23:0] addr_o,    // 传给接口模块的目标地址 (24 位)
    output reg [31:0] wdata_o    // 传给接口模块的写数据 (32 位)
);

    // =========================================================================
    // 内部 FIFO 信号定义
    // =========================================================================
    // FIFO1: 写/擦除请求队列 (格式: {op_type[1:0], waddr[23:0], wdata[31:0]} = 58-bit)
    wire        fifo1_full;
    wire        fifo1_empty;
    wire [57:0] fifo1_q;
    reg         fifo1_rdreq;
    assign wr_rdy = !fifo1_full;

    // FIFO2: 读请求队列 (格式: {raddr[23:0]} = 24-bit)
    wire        fifo2_full;
    wire        fifo2_empty;
    wire [23:0] fifo2_q;
    reg         fifo2_rdreq;
    assign rd_rdy = !fifo2_full;

    // -------------------------------------------------------------------------
    // 例化 FIFO1 (写请求队列，FWFT 首字直通模式)
    // -------------------------------------------------------------------------
    sync_fifo #(
        .DATA_WIDTH(58),
        .ADDR_WIDTH(4)
    ) u_fifo1 (
        .clk  (clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .din  ({wop_type, waddr_i, wdata_i}),
        .full (fifo1_full),
        .rd_en(fifo1_rdreq),
        .dout (fifo1_q),
        .empty(fifo1_empty)
    );

    // -------------------------------------------------------------------------
    // 例化 FIFO2 (读请求队列，FWFT 首字直通模式)
    // -------------------------------------------------------------------------
    sync_fifo #(
        .DATA_WIDTH(24),
        .ADDR_WIDTH(4)
    ) u_fifo2 (
        .clk  (clk),
        .rst_n(rst_n),
        .wr_en(rd_en),
        .din  (raddr_i),
        .full (fifo2_full),
        .rd_en(fifo2_rdreq),
        .dout (fifo2_q),
        .empty(fifo2_empty)
    );

    // =========================================================================
    // 调度仲裁状态机 (读优先调度策略)
    // =========================================================================
    localparam [1:0] S_IDLE      = 2'd0;
    localparam [1:0] S_WAIT_BUSY = 2'd1;
    localparam [1:0] S_WAIT_RDY  = 2'd2;

    reg [1:0] current_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
            fifo1_rdreq   <= 1'b0;
            fifo2_rdreq   <= 1'b0;
            erase_en      <= 1'b0;
            write_en      <= 1'b0;
            read_en       <= 1'b0;
            addr_o        <= 24'd0;
            wdata_o       <= 32'd0;
        end else begin
            fifo1_rdreq <= 1'b0;
            fifo2_rdreq <= 1'b0;
            erase_en    <= 1'b0;
            write_en    <= 1'b0;
            read_en     <= 1'b0;

            case (current_state)
                S_IDLE: begin
                    if (rdy) begin
                        if (!fifo2_empty) begin
                            // 读请求优先派发
                            fifo2_rdreq   <= 1'b1;
                            read_en       <= 1'b1;
                            addr_o        <= fifo2_q[23:0];
                            current_state <= S_WAIT_BUSY;
                        end else if (!fifo1_empty) begin
                            // 写/擦除请求派发
                            fifo1_rdreq   <= 1'b1;
                            addr_o        <= fifo1_q[55:32];
                            wdata_o       <= fifo1_q[31:0];
                            if (fifo1_q[57:56] == 2'b01) begin
                                erase_en <= 1'b1;
                            end else if (fifo1_q[57:56] == 2'b10) begin
                                write_en <= 1'b1;
                            end
                            current_state <= S_WAIT_BUSY;
                        end
                    end
                end

                S_WAIT_BUSY: begin
                    // 保护拍：等待物理层响应命令并拉低 rdy
                    if (!rdy) begin
                        current_state <= S_WAIT_RDY;
                    end
                end

                S_WAIT_RDY: begin
                    // 等待当前底层 SPI 操作及状态寄存器 WIP 轮询完全结束
                    if (rdy) begin
                        current_state <= S_IDLE;
                    end
                end

                default: current_state <= S_IDLE;
            endcase
        end
    end

endmodule
