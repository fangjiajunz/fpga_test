module w25q16_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // ================================================================
    // 上层控制接口
    // start 必须是单个 clk 周期脉冲；仅在 busy = 0 时有效
    // ================================================================
    input  wire        start,
    input  wire [2:0]  operation,
    input  wire [23:0] address,      // 第一版暂未使用，预留给读/写/擦除
    input  wire [7:0]  wr_data,      // 第一版暂未使用，预留给页编程

    output reg  [7:0]  rd_data,      // 第一版暂未使用
    output reg  [23:0] flash_id,     // JEDEC ID：制造商/类型/容量
    output reg         busy,
    output reg         done,         // 完成脉冲，持续 1 个 clk
    output reg         error,        // 错误脉冲，持续 1 个 clk

    // ================================================================
    // 与 spi_master_top 的接口
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
    // 上层操作编码
    // 第一版只实现 READ_ID，其他编码为后续功能预留
    // ================================================================
    localparam [2:0] OP_READ_ID      = 3'd0;
    localparam [2:0] OP_READ_STATUS  = 3'd1;
    localparam [2:0] OP_READ_DATA    = 3'd2;
    localparam [2:0] OP_PAGE_PROGRAM = 3'd3;
    localparam [2:0] OP_SECTOR_ERASE = 3'd4;
    localparam [2:0] OP_CHIP_ERASE   = 3'd5;

    // W25Q16 指令
    localparam [7:0] CMD_READ_ID = 8'h9F;
    localparam [7:0] DUMMY_BYTE  = 8'hFF;

    // ================================================================
    // 状态定义
    // ================================================================
    localparam [1:0] ST_IDLE    = 2'd0;
    localparam [1:0] ST_READ_ID = 2'd1;

    reg [1:0] state;

    // 当前已准备/接收的字节序号
    // READ ID 一次事务共 4 字节：
    // TX: 9F, FF, FF, FF
    // RX: XX, Manufacturer ID, Memory Type, Capacity ID
    reg [2:0] tx_index;
    reg [2:0] rx_index;

    // 锁存接口，后续扩展时使用
    reg [23:0] address_latched;
    reg [7:0]  wr_data_latched;

    // ================================================================
    // 主状态机
    // ================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;

            busy            <= 1'b0;
            done            <= 1'b0;
            error           <= 1'b0;

            rd_data         <= 8'h00;
            flash_id        <= 24'h000000;

            spi_start       <= 1'b0;
            spi_burst_len   <= 8'd1;
            spi_tx_byte     <= 8'hFF;

            tx_index        <= 3'd0;
            rx_index        <= 3'd0;

            address_latched <= 24'h000000;
            wr_data_latched <= 8'h00;
        end else begin
            // 单周期脉冲默认拉低
            done      <= 1'b0;
            error     <= 1'b0;
            spi_start <= 1'b0;

            case (state)
                // ----------------------------------------------------
                // 空闲：接收上层操作请求
                // ----------------------------------------------------
                ST_IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        // 先锁存参数，后续扩展读写功能时直接使用
                        address_latched <= address;
                        wr_data_latched <= wr_data;

                        if (spi_busy) begin
                            // SPI Master 正忙，拒绝本次请求
                            error <= 1'b1;
                            done  <= 1'b1;
                        end else begin
                            case (operation)
                                OP_READ_ID: begin
                                    // 一次 CS 低电平期间连续传输 4 字节：
                                    // 9F + 3 个 dummy byte
                                    busy          <= 1'b1;
                                    flash_id      <= 24'h000000;
                                    tx_index      <= 3'd0;
                                    rx_index      <= 3'd0;

                                    spi_burst_len <= 8'd4;
                                    spi_tx_byte   <= CMD_READ_ID;
                                    spi_start     <= 1'b1;

                                    state         <= ST_READ_ID;
                                end

                                default: begin
                                    // 第一版尚未实现其他操作
                                    error <= 1'b1;
                                    done  <= 1'b1;
                                end
                            endcase
                        end
                    end
                end

                // ----------------------------------------------------
                // 读取 JEDEC ID
                // ----------------------------------------------------
                ST_READ_ID: begin
                    busy <= 1'b1;

                    // spi_master_top 在当前字节传输过半时请求下一字节。
                    // READ ID 后续三个字节只需要发送 dummy byte 产生时钟。
                    if (spi_tx_req) begin
                        spi_tx_byte <= DUMMY_BYTE;
                        tx_index    <= tx_index + 1'b1;
                    end

                    // 每完成一个字节都会产生一次 spi_rx_valid。
                    // 第 0 个接收字节是发送 9F 时收到的无效值，需要忽略。
                    if (spi_rx_valid) begin
                        case (rx_index)
                            3'd0: begin
                                // 命令阶段返回值无效，忽略
                            end

                            3'd1: begin
                                flash_id[23:16] <= spi_rx_byte;
                            end

                            3'd2: begin
                                flash_id[15:8] <= spi_rx_byte;
                            end

                            3'd3: begin
                                flash_id[7:0] <= spi_rx_byte;
                            end

                            default: begin
                            end
                        endcase

                        rx_index <= rx_index + 1'b1;
                    end

                    // spi_done 与最后一个 rx_valid 可能在同一个周期出现。
                    // 非阻塞赋值可保证 flash_id 和 done 在该周期结束后一起更新。
                    if (spi_done) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    busy  <= 1'b0;
                    error <= 1'b1;
                end
            endcase
        end
    end

endmodule
