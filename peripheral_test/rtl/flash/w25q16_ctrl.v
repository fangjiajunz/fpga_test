module w25q16_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // ================================================================
    // 上层控制接口
    // ================================================================
    input  wire        start,
    input  wire [2:0]  operation,
    input  wire [23:0] address,
    input  wire [31:0] wr_data_32,   // 待写 4 字节数据 (Big-Endian: [31:24] 先发)

    output reg  [31:0] rd_data_32,   // 读回 4 字节数据 (Big-Endian: [31:24] 先收)
    output reg  [23:0] flash_id,     // JEDEC ID (0xEF4015)
    output wire        busy,
    output reg         done,         // 操作完成指示脉冲 (持续 1 拍)
    output reg         error,        // 错误指示脉冲 (持续 1 拍)

    // ================================================================
    // 与 spi_master_top 的硬件控制接口
    // ================================================================
    output reg         spi_start,
    output reg  [7:0]  spi_burst_len,
    input  wire        spi_tx_req,
    output reg  [7:0]  spi_tx_byte,

    input  wire        spi_rx_valid,
    input  wire [7:0]  spi_rx_byte,
    input  wire        spi_busy,
    input  wire        spi_done
);

    // ================================================================
    // 操作指令与命令编码
    // ================================================================
    localparam [2:0] OP_READ_ID      = 3'd0; // 读取 JEDEC ID (0x9F)
    localparam [2:0] OP_SECTOR_ERASE = 3'd1; // 4KB 扇区擦除 (自动 WREN -> 0x20 -> 轮询 WIP)
    localparam [2:0] OP_PAGE_PROG_4B = 3'd2; // 写入 4 字节 (自动 WREN -> 0x02 -> 轮询 WIP)
    localparam [2:0] OP_READ_DATA_4B = 3'd3; // 读出 4 字节 (0x03 -> 接收 4 字节)

    // W25Q16 常用指令
    localparam [7:0] CMD_READ_ID      = 8'h9F;
    localparam [7:0] CMD_WRITE_ENABLE = 8'h06;
    localparam [7:0] CMD_READ_STATUS1 = 8'h05;
    localparam [7:0] CMD_SECTOR_ERASE = 8'h20;
    localparam [7:0] CMD_PAGE_PROGRAM = 8'h02;
    localparam [7:0] CMD_READ_DATA    = 8'h03;
    localparam [7:0] DUMMY_BYTE       = 8'hFF;

    // ================================================================
    // 状态定义 (标准状态机)
    // ================================================================
    localparam [3:0] S_IDLE        = 4'd0;
    localparam [3:0] S_READ_ID     = 4'd1;
    localparam [3:0] S_WREN        = 4'd2;
    localparam [3:0] S_ERASE_CMD   = 4'd3;
    localparam [3:0] S_PROG_CMD    = 4'd4;
    localparam [3:0] S_POLL_STATUS = 4'd5;
    localparam [3:0] S_READ_CMD    = 4'd6;
    localparam [3:0] S_DONE_STATE  = 4'd7;

    reg [3:0] current_state;
    reg [3:0] next_state;

    // 内部控制寄存器
    reg [2:0]  op_latched;
    reg [23:0] addr_latched;
    reg [31:0] wr_data_latched;

    reg [3:0]  tx_cnt;
    reg [3:0]  rx_cnt;
    reg [7:0]  status_reg;

    wire poll_wip = spi_rx_valid ? spi_rx_byte[0] : status_reg[0];

    assign busy = (current_state != S_IDLE);

    // ================================================================
    // 【第一段】现态时序寄存器
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= S_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // ================================================================
    // 【第二段】次态组合逻辑决策
    // ================================================================
    always @(*) begin
        next_state = current_state;

        case (current_state)
            S_IDLE: begin
                if (start && !spi_busy) begin
                    case (operation)
                        OP_READ_ID:      next_state = S_READ_ID;
                        OP_SECTOR_ERASE: next_state = S_WREN;
                        OP_PAGE_PROG_4B: next_state = S_WREN;
                        OP_READ_DATA_4B: next_state = S_READ_CMD;
                        default:         next_state = S_IDLE;
                    endcase
                end
            end

            // 读 ID：等待 SPI 传输 4 字节完成
            S_READ_ID: begin
                if (spi_done)
                    next_state = S_DONE_STATE;
            end

            // 写使能：1 字节传输完成后，根据 op_latched 进入擦除或编程状态
            S_WREN: begin
                if (spi_done) begin
                    if (op_latched == OP_SECTOR_ERASE)
                        next_state = S_ERASE_CMD;
                    else
                        next_state = S_PROG_CMD;
                end
            end

            // 扇区擦除指令 (4 字节) 发送完成，进入轮询等待状态
            S_ERASE_CMD: begin
                if (spi_done)
                    next_state = S_POLL_STATUS;
            end

            // 页编程指令 (8 字节) 发送完成，进入轮询等待状态
            S_PROG_CMD: begin
                if (spi_done)
                    next_state = S_POLL_STATUS;
            end

            // 轮询状态寄存器：当收到非忙指示 (WIP==0) 时跳出
            S_POLL_STATUS: begin
                if (spi_done && (poll_wip == 1'b0))
                    next_state = S_DONE_STATE;
            end

            // 读数据指令 (8 字节) 接收完成
            S_READ_CMD: begin
                if (spi_done)
                    next_state = S_DONE_STATE;
            end

            // 完成状态：单周期脉冲后自动返回 IDLE
            S_DONE_STATE: begin
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ================================================================
    // 【第三段】数据通路与 SPI 交互控制
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done             <= 1'b0;
            error            <= 1'b0;
            flash_id         <= 24'h000000;
            rd_data_32       <= 32'h00000000;
            op_latched       <= 3'd0;
            addr_latched     <= 24'h000000;
            wr_data_latched  <= 32'h00000000;

            spi_start        <= 1'b0;
            spi_burst_len    <= 8'd0;
            spi_tx_byte      <= 8'h00;
            tx_cnt           <= 4'd0;
            rx_cnt           <= 4'd0;
            status_reg       <= 8'hFF;
        end else begin
            done      <= 1'b0;
            error     <= 1'b0;
            spi_start <= 1'b0;

            case (current_state)
                // ----------------------------------------------------
                // S_IDLE: 响应启动并装载第一阶段参数
                // ----------------------------------------------------
                S_IDLE: begin
                    tx_cnt     <= 4'd0;
                    rx_cnt     <= 4'd0;
                    status_reg <= 8'hFF;

                    if (start) begin
                        if (spi_busy) begin
                            error <= 1'b1;
                            done  <= 1'b1;
                        end else begin
                            op_latched      <= operation;
                            addr_latched    <= address;
                            wr_data_latched <= wr_data_32;

                            case (operation)
                                OP_READ_ID: begin
                                    spi_burst_len <= 8'd4;
                                    spi_tx_byte   <= CMD_READ_ID;
                                    spi_start     <= 1'b1;
                                end

                                OP_SECTOR_ERASE, OP_PAGE_PROG_4B: begin
                                    // 擦除和写入必须先执行 1 字节写使能 (0x06)
                                    spi_burst_len <= 8'd1;
                                    spi_tx_byte   <= CMD_WRITE_ENABLE;
                                    spi_start     <= 1'b1;
                                end

                                OP_READ_DATA_4B: begin
                                    // 1 字节命令 + 3 字节地址 + 4 字节读取 = 8 字节
                                    spi_burst_len <= 8'd8;
                                    spi_tx_byte   <= CMD_READ_DATA;
                                    spi_start     <= 1'b1;
                                end

                                default: begin
                                    error <= 1'b1;
                                    done  <= 1'b1;
                                end
                            endcase
                        end
                    end
                end

                // ----------------------------------------------------
                // S_READ_ID: 接收 3 字节 JEDEC ID
                // ----------------------------------------------------
                S_READ_ID: begin
                    if (spi_tx_req) begin
                        spi_tx_byte <= DUMMY_BYTE;
                    end

                    if (spi_rx_valid) begin
                        case (rx_cnt)
                            4'd1: flash_id[23:16] <= spi_rx_byte;
                            4'd2: flash_id[15:8]  <= spi_rx_byte;
                            4'd3: flash_id[7:0]   <= spi_rx_byte;
                            default: ;
                        endcase
                        rx_cnt <= rx_cnt + 1'b1;
                    end
                end

                // ----------------------------------------------------
                // S_WREN: 发送完 0x06 后装填下一步擦除或编程命令
                // ----------------------------------------------------
                S_WREN: begin
                    if (spi_done) begin
                        tx_cnt <= 4'd0;
                        rx_cnt <= 4'd0;

                        if (op_latched == OP_SECTOR_ERASE) begin
                            // 扇区擦除：1 字节命令 (0x20) + 3 字节地址 = 4 字节
                            spi_burst_len <= 8'd4;
                            spi_tx_byte   <= CMD_SECTOR_ERASE;
                            spi_start     <= 1'b1;
                        end else begin
                            // 页编程：1 字节命令 (0x02) + 3 字节地址 + 4 字节数据 = 8 字节
                            spi_burst_len <= 8'd8;
                            spi_tx_byte   <= CMD_PAGE_PROGRAM;
                            spi_start     <= 1'b1;
                        end
                    end
                end

                // ----------------------------------------------------
                // S_ERASE_CMD: 提供 3 字节扇区地址
                // ----------------------------------------------------
                S_ERASE_CMD: begin
                    if (spi_tx_req) begin
                        case (tx_cnt)
                            4'd0: spi_tx_byte <= addr_latched[23:16];
                            4'd1: spi_tx_byte <= addr_latched[15:8];
                            4'd2: spi_tx_byte <= addr_latched[7:0];
                            default: spi_tx_byte <= DUMMY_BYTE;
                        endcase
                        tx_cnt <= tx_cnt + 1'b1;
                    end

                    // 发送完成，准备首次启动读状态寄存器
                    if (spi_done) begin
                        tx_cnt        <= 4'd0;
                        rx_cnt        <= 4'd0;
                        status_reg    <= 8'hFF;
                        spi_burst_len <= 8'd2; // 0x05 + Dummy 字节
                        spi_tx_byte   <= CMD_READ_STATUS1;
                        spi_start     <= 1'b1;
                    end
                end

                // ----------------------------------------------------
                // S_PROG_CMD: 提供 3 字节地址与 4 字节待写数据
                // ----------------------------------------------------
                S_PROG_CMD: begin
                    if (spi_tx_req) begin
                        case (tx_cnt)
                            4'd0: spi_tx_byte <= addr_latched[23:16];
                            4'd1: spi_tx_byte <= addr_latched[15:8];
                            4'd2: spi_tx_byte <= addr_latched[7:0];
                            4'd3: spi_tx_byte <= wr_data_latched[31:24];
                            4'd4: spi_tx_byte <= wr_data_latched[23:16];
                            4'd5: spi_tx_byte <= wr_data_latched[15:8];
                            4'd6: spi_tx_byte <= wr_data_latched[7:0];
                            default: spi_tx_byte <= DUMMY_BYTE;
                        endcase
                        tx_cnt <= tx_cnt + 1'b1;
                    end

                    // 发送完成，准备首次启动读状态寄存器
                    if (spi_done) begin
                        tx_cnt        <= 4'd0;
                        rx_cnt        <= 4'd0;
                        status_reg    <= 8'hFF;
                        spi_burst_len <= 8'd2; // 0x05 + Dummy 字节
                        spi_tx_byte   <= CMD_READ_STATUS1;
                        spi_start     <= 1'b1;
                    end
                end

                // ----------------------------------------------------
                // S_POLL_STATUS: 轮询读状态寄存器 (0x05) 直到 WIP == 0
                // ----------------------------------------------------
                S_POLL_STATUS: begin
                    if (spi_tx_req) begin
                        spi_tx_byte <= DUMMY_BYTE;
                    end

                    if (spi_rx_valid) begin
                        status_reg <= spi_rx_byte;
                    end

                    if (spi_done) begin
                        if (poll_wip == 1'b1) begin
                            // WIP 仍为 1 (芯片内部仍在擦除或写入)，再次发起 2 字节读状态
                            spi_burst_len <= 8'd2;
                            spi_tx_byte   <= CMD_READ_STATUS1;
                            spi_start     <= 1'b1;
                        end
                    end
                end

                // ----------------------------------------------------
                // S_READ_CMD: 发送 3 字节地址，并接收 4 字节数据
                // ----------------------------------------------------
                S_READ_CMD: begin
                    if (spi_tx_req) begin
                        case (tx_cnt)
                            4'd0: spi_tx_byte <= addr_latched[23:16];
                            4'd1: spi_tx_byte <= addr_latched[15:8];
                            4'd2: spi_tx_byte <= addr_latched[7:0];
                            default: spi_tx_byte <= DUMMY_BYTE;
                        endcase
                        tx_cnt <= tx_cnt + 1'b1;
                    end

                    if (spi_rx_valid) begin
                        case (rx_cnt)
                            4'd4: rd_data_32[31:24] <= spi_rx_byte;
                            4'd5: rd_data_32[23:16] <= spi_rx_byte;
                            4'd6: rd_data_32[15:8]  <= spi_rx_byte;
                            4'd7: rd_data_32[7:0]   <= spi_rx_byte;
                            default: ;
                        endcase
                        rx_cnt <= rx_cnt + 1'b1;
                    end
                end

                // ----------------------------------------------------
                // S_DONE_STATE: 单周期输出完成信号
                // ----------------------------------------------------
                S_DONE_STATE: begin
                    done <= 1'b1;
                end

                default: ;
            endcase
        end
    end

endmodule
