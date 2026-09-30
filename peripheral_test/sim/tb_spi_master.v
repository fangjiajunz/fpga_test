`timescale 1ns / 1ps

module tb_spi_master;

    localparam CLK_PERIOD = 20; // 50MHz

    reg        sys_clk;
    reg        sys_rst_n;

    reg        start;
    reg  [7:0] burst_len;
    wire       tx_req;
    reg  [7:0] tx_data;

    wire       rx_valid;
    wire [7:0] rx_byte;
    wire       busy;
    wire       done;

    wire       spi_cs_n;
    wire       spi_sclk;
    wire       spi_mosi;
    reg        spi_miso;

    // 实例化待测模块 DUT
    spi_master_top #(
        .BURST_WIDTH(8),
        .CPOL       (1'b0),
        .CPHA       (1'b0),
        .LSB_FIRST  (1'b0)
    ) dut (
        .sys_clk   (sys_clk),
        .sys_rst_n (sys_rst_n),

        .start     (start),
        .burst_len (burst_len),
        .tx_req    (tx_req),
        .tx_data   (tx_data),

        .rx_valid  (rx_valid),
        .rx_byte   (rx_byte),
        .busy      (busy),
        .done      (done),

        .spi_cs_n  (spi_cs_n),
        .spi_sclk  (spi_sclk),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso)
    );

    // 时钟生成 50MHz
    initial begin
        sys_clk = 1'b0;
        forever #(CLK_PERIOD / 2) sys_clk = ~sys_clk;
    end

    // MISO 回环模拟：MISO = ~MOSI，方便检验接收的数据是否准确翻转
    always @(*) begin
        spi_miso = ~spi_mosi;
    end

    // 监控接收数据
    reg [7:0] rx_received [0:15];
    integer   rx_count;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rx_count <= 0;
        end else if (rx_valid) begin
            rx_received[rx_count] <= rx_byte;
            rx_count <= rx_count + 1;
            $display("[RX_BYTE] Index=%0d Byte=0x%02X at time %0t", rx_count, rx_byte, $time);
        end
    end

    // 测试主流程
    initial begin
        sys_rst_n = 1'b0;
        start     = 1'b0;
        burst_len = 8'd0;
        tx_data   = 8'h00;

        #(CLK_PERIOD * 5);
        sys_rst_n = 1'b1;
        #(CLK_PERIOD * 5);

        // ============================================================
        // 测试 1：单字节传输测试 (burst_len = 1, tx = 0xA5)
        // ============================================================
        $display("\n--- Test 1: Single Byte Transfer (0xA5) ---");
        @(posedge sys_clk);
        start     <= 1'b1;
        burst_len <= 8'd1;
        tx_data   <= 8'hA5;
        @(posedge sys_clk);
        start     <= 1'b0;

        // 等待单字节传输完成
        @(posedge done);
        #(CLK_PERIOD * 2);

        if (rx_count == 1 && rx_received[0] == ~8'hA5) begin
            $display("[PASS] Test 1: Single byte transfer successful! Expected 0x%02X, got 0x%02X", ~8'hA5, rx_received[0]);
        end else begin
            $display("[FAIL] Test 1: Failed! rx_count=%0d, got 0x%02X", rx_count, rx_received[0]);
            $finish;
        end

        #(CLK_PERIOD * 10);

        // ============================================================
        // 测试 2：多字节 Burst 传输测试 (burst_len = 4, tx = 11, 22, 33, 44)
        // ============================================================
        $display("\n--- Test 2: Multi-byte Burst Transfer (4 Bytes) ---");
        rx_count = 0;

        @(posedge sys_clk);
        start     <= 1'b1;
        burst_len <= 8'd4;
        tx_data   <= 8'h11; // 准备第 1 个字节
        @(posedge sys_clk);
        start     <= 1'b0;

        // 响应 tx_req，提供后续字节
        fork
            begin : feed_tx
                // 等待第 1 次 tx_req (准备第 2 字节)
                @(posedge tx_req);
                tx_data <= 8'h22;
                $display("[TX_REQ] Provided Byte 2: 0x22 at time %0t", $time);

                // 等待第 2 次 tx_req (准备第 3 字节)
                @(posedge tx_req);
                tx_data <= 8'h33;
                $display("[TX_REQ] Provided Byte 3: 0x33 at time %0t", $time);

                // 等待第 3 次 tx_req (准备第 4 字节)
                @(posedge tx_req);
                tx_data <= 8'h44;
                $display("[TX_REQ] Provided Byte 4: 0x44 at time %0t", $time);
            end

            begin : wait_done
                @(posedge done);
            end
        join

        #(CLK_PERIOD * 2);

        if (rx_count == 4 &&
            rx_received[0] == ~8'h11 &&
            rx_received[1] == ~8'h22 &&
            rx_received[2] == ~8'h33 &&
            rx_received[3] == ~8'h44) begin
            $display("[PASS] Test 2: 4-byte burst transfer passed perfectly!");
        end else begin
            $display("[FAIL] Test 2: rx_count=%0d", rx_count);
            $finish;
        end

        $display("\n=======================================================");
        $display("ALL SPI PHY & MASTER FSM TESTS PASSED SUCCESSFULLY!");
        $display("=======================================================\n");
        $finish;
    end

endmodule
