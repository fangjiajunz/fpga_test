`timescale 1ns / 1ps

module tb_flash_ctrl;

    localparam CLK_PERIOD = 20; // 50MHz

    reg        clk;
    reg        rst_n;

    reg        flash_start;
    reg  [2:0] flash_op;
    wire       flash_busy;
    wire       flash_done;
    wire       flash_error;
    wire [23:0] flash_id;

    // SPI 互联信号
    wire       spi_start;
    wire [7:0] spi_burst_len;
    wire       spi_tx_req;
    wire [7:0] spi_tx_byte;

    wire       spi_rx_valid;
    wire [7:0] spi_rx_byte;
    wire       spi_busy;
    wire       spi_done;

    // SPI 物理引脚
    wire       spi_cs_n;
    wire       spi_sclk;
    wire       spi_mosi;
    reg        spi_miso;

    // 实例化 w25q16_ctrl (重构后的三段式 Flash 控制器)
    w25q16_ctrl u_w25q16_ctrl (
        .clk           (clk),
        .rst_n         (rst_n),

        .start         (flash_start),
        .operation     (flash_op),
        .address       (24'h000000),
        .wr_data       (8'h00),

        .rd_data       (),
        .flash_id      (flash_id),
        .busy          (flash_busy),
        .done          (flash_done),
        .error         (flash_error),

        .spi_start     (spi_start),
        .spi_burst_len (spi_burst_len),
        .spi_tx_req    (spi_tx_req),
        .spi_tx_byte   (spi_tx_byte),

        .spi_rx_valid  (spi_rx_valid),
        .spi_rx_byte   (spi_rx_byte),
        .spi_busy      (spi_busy),
        .spi_done      (spi_done)
    );

    // 实例化 spi_master_top (重构后的三段式 SPI 控制器)
    spi_master_top #(
        .BURST_WIDTH(8),
        .CPOL       (1'b0),
        .CPHA       (1'b0),
        .LSB_FIRST  (1'b0)
    ) u_spi_master_top (
        .sys_clk   (clk),
        .sys_rst_n (rst_n),

        .start     (spi_start),
        .burst_len (spi_burst_len),
        .tx_req    (spi_tx_req),
        .tx_data   (spi_tx_byte),

        .rx_valid  (spi_rx_valid),
        .rx_byte   (spi_rx_byte),
        .busy      (spi_busy),
        .done      (spi_done),

        .spi_cs_n  (spi_cs_n),
        .spi_sclk  (spi_sclk),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso)
    );

    // 时钟生成 50MHz
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ================================================================
    // W25Q16 硬件从机行为仿真模型：
    // 在 CS_N 为低时，先接收 1 字节命令，如果命令是 0x9F，则后续 3 字节输出 EF 40 15
    // ================================================================
    reg [7:0] flash_response [0:2];
    integer   miso_byte_idx;
    integer   miso_bit_idx;
    reg [7:0] cmd_received;
    integer   cmd_bit_idx;

    initial begin
        flash_response[0] = 8'hEF; // 制造商 ID (Winbond)
        flash_response[1] = 8'h40; // 存储器类型
        flash_response[2] = 8'h15; // 容量 ID (16Mb)
        spi_miso          = 1'b0;
    end

    // SPI 从机时序模拟 (CPOL=0, CPHA=0: 在 SCLK 上升沿采样 MOSI, 在 SCLK 下降沿更新 MISO)
    always @(negedge spi_cs_n) begin
        cmd_received  = 8'h00;
        cmd_bit_idx   = 7;
        miso_byte_idx = 0;
        miso_bit_idx  = 7;

        // CPHA=0 下，第 0 位在 CS 拉低时即预置在 MISO 线上（虽然第 0 字节无效）
        spi_miso = 1'b0;

        while (!spi_cs_n) begin
            // 等待 SCLK 上升沿采样 MOSI
            @(posedge spi_sclk);
            if (cmd_bit_idx >= 0) begin
                cmd_received[cmd_bit_idx] = spi_mosi;
                cmd_bit_idx = cmd_bit_idx - 1;
            end

            // 等待 SCLK 下降沿更新 MISO
            @(negedge spi_sclk);
            if (cmd_bit_idx < 0) begin
                // 命令接收完毕，后续按顺序吐出 0xEF 0x40 0x15
                if (miso_byte_idx < 3) begin
                    spi_miso = flash_response[miso_byte_idx][miso_bit_idx];
                    if (miso_bit_idx == 0) begin
                        miso_bit_idx  = 7;
                        miso_byte_idx = miso_byte_idx + 1;
                    end else begin
                        miso_bit_idx = miso_bit_idx - 1;
                    end
                end
            end
        end
    end

    // 测试主流程
    initial begin
        flash_start = 1'b0;
        flash_op    = 3'd0; // OP_READ_ID
        rst_n       = 1'b0;

        #(CLK_PERIOD * 5);
        rst_n = 1'b1;
        #(CLK_PERIOD * 5);

        $display("\n=======================================================");
        $display(" Start W25Q16 Flash Controller READ_ID Test");
        $display("=======================================================");

        @(posedge clk);
        flash_start <= 1'b1;
        flash_op    <= 3'd0; // OP_READ_ID
        @(posedge clk);
        flash_start <= 1'b0;

        // 等待 flash_done 变高
        @(posedge flash_done);
        #(CLK_PERIOD * 2);

        $display("[RESULT] flash_id = 0x%06X (Expected: 0xEF4015)", flash_id);

        if (flash_id === 24'hEF4015 && flash_error === 1'b0) begin
            $display("[PASS] Flash JEDEC ID READ_ID Test Successfully Passed!\n");
        end else begin
            $display("[FAIL] JEDEC ID mismatch or error occurred! error=%b", flash_error);
            $finish;
        end

        #(CLK_PERIOD * 10);

        // ============================================================
        // 测试 2：触发尚未实现的非法操作 (OP = 3'd1)，验证错误拦截
        // ============================================================
        $display("--- Test 2: Trigger Unsupported Operation (OP = 1) ---");
        @(posedge clk);
        flash_start <= 1'b1;
        flash_op    <= 3'd1;
        @(posedge clk);
        flash_start <= 1'b0;

        @(posedge flash_done);
        if (flash_error === 1'b1) begin
            $display("[PASS] Test 2: Unsupported operation correctly raised error pulse!\n");
        end else begin
            $display("[FAIL] Test 2: Expected flash_error=1, got %b", flash_error);
            $finish;
        end

        #(CLK_PERIOD * 10);
        $display("=======================================================");
        $display(" ALL W25Q16 FLASH CTRL TESTS PASSED SUCCESSFULLY!");
        $display("=======================================================\n");
        $finish;
    end

endmodule
