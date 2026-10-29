// =============================================================================

// =============================================================================
module w25q16_phy (
    input clk,   // 系统工作时钟 (50MHz)
    input rst_n, // 系统异步复位，低有效

    // =========================================================================
    // 面对内部命令模块 (flash_cmd_ctrl / 调度模块)
    // =========================================================================
    input             erase_en,   // 扇区擦除命令脉冲
    input             write_en,   // 页写命令脉冲
    input             read_en,    // 读数据命令脉冲
    input      [23:0] addr_o,     // 目标操作地址
    input      [31:0] wdata_o,    // 待写入数据
    output reg        rdy,        // 接口空闲/就绪指示
    output reg [31:0] rdata,      // 读出的数据
    output reg        rdata_vld,  // 读数据有效指示
    output reg        wr_done,    // 写入/擦除完成脉冲

    // =========================================================================
    // 直接连接外部物理芯片引脚 (FPGA 外部管脚)
    // =========================================================================
    output wire spi_cs_n,  // 片选，低有效
    output wire spi_sclk,  // 串行同步时钟
    output wire spi_mosi,  // 串行数据输出
    input  wire spi_miso   // 串行数据输入
);

    // 操作类型编码
    localparam [1:0] OP_NONE = 2'd0;
    localparam [1:0] OP_ERASE = 2'd1;
    localparam [1:0] OP_WRITE = 2'd2;
    localparam [1:0] OP_READ = 2'd3;

    // W25Q16 常用指令
    localparam [7:0] CMD_WRITE_ENABLE = 8'h06;
    localparam [7:0] CMD_SECTOR_ERASE = 8'h20;
    localparam [7:0] CMD_PAGE_PROGRAM = 8'h02;
    localparam [7:0] CMD_READ_DATA = 8'h03;
    localparam [7:0] CMD_READ_STATUS1 = 8'h05;
    localparam [7:0] DUMMY_BYTE = 8'hFF;

    // 状态机编码
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_WREN = 3'd1;
    localparam [2:0] S_ERASE_CMD = 3'd2;
    localparam [2:0] S_PROG_CMD = 3'd3;
    localparam [2:0] S_POLL_STATUS = 3'd4;
    localparam [2:0] S_READ_CMD = 3'd5;

    reg  [ 2:0] current_state;

    // 内部控制寄存器
    reg  [ 1:0] op_latched;
    reg  [23:0] addr_latched;
    reg  [31:0] wr_data_latched;

    reg  [ 3:0] tx_cnt;
    reg  [ 3:0] rx_cnt;
    reg  [ 7:0] status_reg;

    // SPI 控制器接口信号
    reg         spi_start;
    reg  [ 7:0] spi_burst_len;
    wire        spi_tx_req;
    reg  [ 7:0] spi_tx_byte;
    wire        spi_rx_valid;
    wire [ 7:0] spi_rx_byte;
    wire        spi_busy;
    wire        spi_done;

    wire        poll_wip = spi_rx_valid ? spi_rx_byte[0] : status_reg[0];

    // =========================================================================
    // 实例化底层 SPI 主机控制器 (spi_master_top)
    // =========================================================================
    spi_master_top #(
        .BURST_WIDTH(8),
        .CPOL       (1'b0),
        .CPHA       (1'b0),
        .LSB_FIRST  (1'b0)
    ) u_spi_master_top (
        .sys_clk  (clk),
        .sys_rst_n(rst_n),
        .start    (spi_start),
        .burst_len(spi_burst_len),
        .tx_req   (spi_tx_req),
        .tx_data  (spi_tx_byte),
        .rx_valid (spi_rx_valid),
        .rx_byte  (spi_rx_byte),
        .busy     (spi_busy),
        .done     (spi_done),
        .spi_cs_n (spi_cs_n),
        .spi_sclk (spi_sclk),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso)
    );

    // =========================================================================
    // 协议与物理状态机
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state   <= S_IDLE;
            rdy             <= 1'b1;
            rdata           <= 32'd0;
            rdata_vld       <= 1'b0;
            wr_done         <= 1'b0;
            op_latched      <= OP_NONE;
            addr_latched    <= 24'd0;
            wr_data_latched <= 32'd0;
            tx_cnt          <= 4'd0;
            rx_cnt          <= 4'd0;
            status_reg      <= 8'hFF;
            spi_start       <= 1'b0;
            spi_burst_len   <= 8'd0;
            spi_tx_byte     <= 8'd0;
        end else begin
            spi_start <= 1'b0;
            rdata_vld <= 1'b0;
            wr_done   <= 1'b0;

            case (current_state)
                S_IDLE: begin
                    rdy        <= 1'b1;
                    tx_cnt     <= 4'd0;
                    rx_cnt     <= 4'd0;
                    status_reg <= 8'hFF;

                    if (erase_en) begin
                        rdy           <= 1'b0;
                        op_latched    <= OP_ERASE;
                        addr_latched  <= addr_o;
                        spi_burst_len <= 8'd1;
                        spi_tx_byte   <= CMD_WRITE_ENABLE;
                        spi_start     <= 1'b1;
                        current_state <= S_WREN;
                    end else if (write_en) begin
                        rdy             <= 1'b0;
                        op_latched      <= OP_WRITE;
                        addr_latched    <= addr_o;
                        wr_data_latched <= wdata_o;
                        spi_burst_len   <= 8'd1;
                        spi_tx_byte     <= CMD_WRITE_ENABLE;
                        spi_start       <= 1'b1;
                        current_state   <= S_WREN;
                    end else if (read_en) begin
                        rdy           <= 1'b0;
                        op_latched    <= OP_READ;
                        addr_latched  <= addr_o;
                        spi_burst_len <= 8'd8;  // 1字节读命令 + 3字节地址 + 4字节数据
                        spi_tx_byte   <= CMD_READ_DATA;
                        spi_start     <= 1'b1;
                        current_state <= S_READ_CMD;
                    end
                end

                S_WREN: begin
                    if (spi_done) begin
                        tx_cnt <= 4'd0;
                        rx_cnt <= 4'd0;
                        if (op_latched == OP_ERASE) begin
                            spi_burst_len <= 8'd4;  // 0x20 + 3字节地址
                            spi_tx_byte   <= CMD_SECTOR_ERASE;
                            spi_start     <= 1'b1;
                            current_state <= S_ERASE_CMD;
                        end else begin
                            spi_burst_len <= 8'd8;  // 0x02 + 3字节地址 + 4字节数据
                            spi_tx_byte   <= CMD_PAGE_PROGRAM;
                            spi_start     <= 1'b1;
                            current_state <= S_PROG_CMD;
                        end
                    end
                end

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

                    if (spi_done) begin
                        tx_cnt        <= 4'd0;
                        rx_cnt        <= 4'd0;
                        status_reg    <= 8'hFF;
                        spi_burst_len <= 8'd2;  // 0x05 + Dummy
                        spi_tx_byte   <= CMD_READ_STATUS1;
                        spi_start     <= 1'b1;
                        current_state <= S_POLL_STATUS;
                    end
                end

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

                    if (spi_done) begin
                        tx_cnt        <= 4'd0;
                        rx_cnt        <= 4'd0;
                        status_reg    <= 8'hFF;
                        spi_burst_len <= 8'd2;  // 0x05 + Dummy
                        spi_tx_byte   <= CMD_READ_STATUS1;
                        spi_start     <= 1'b1;
                        current_state <= S_POLL_STATUS;
                    end
                end

                S_POLL_STATUS: begin
                    if (spi_tx_req) begin
                        spi_tx_byte <= DUMMY_BYTE;
                    end

                    if (spi_rx_valid) begin
                        status_reg <= spi_rx_byte;
                    end

                    if (spi_done) begin
                        if (poll_wip == 1'b1) begin
                            // WIP=1 表示内部擦写仍在进行，继续轮询读状态
                            spi_burst_len <= 8'd2;
                            spi_tx_byte   <= CMD_READ_STATUS1;
                            spi_start     <= 1'b1;
                        end else begin
                            // 擦除/写入完全结束
                            wr_done       <= 1'b1;
                            rdy           <= 1'b1;
                            current_state <= S_IDLE;
                        end
                    end
                end

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
                            4'd4: rdata[31:24] <= spi_rx_byte;
                            4'd5: rdata[23:16] <= spi_rx_byte;
                            4'd6: rdata[15:8] <= spi_rx_byte;
                            4'd7: rdata[7:0] <= spi_rx_byte;
                            default: ;
                        endcase
                        rx_cnt <= rx_cnt + 1'b1;
                    end

                    if (spi_done) begin
                        rdata_vld     <= 1'b1;
                        rdy           <= 1'b1;
                        current_state <= S_IDLE;
                    end
                end

                default: current_state <= S_IDLE;
            endcase
        end
    end

endmodule
