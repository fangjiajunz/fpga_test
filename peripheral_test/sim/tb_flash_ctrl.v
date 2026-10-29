`timescale 1ns / 1ps

module tb_flash_ctrl;

    localparam CLK_PERIOD = 20; // 50MHz

    reg         clk;
    reg         rst_n;

    // 写业务通道
    reg         user_wr_trig;
    reg  [ 1:0] user_op_type;
    reg  [23:0] user_wr_addr;
    reg  [31:0] user_wr_data;
    wire        user_wr_rdy;
    wire        user_wr_done;

    // 读业务通道
    reg         user_rd_trig;
    reg  [23:0] user_rd_addr;
    wire        user_rd_rdy;
    wire [31:0] user_rd_data;
    wire        user_rd_vld;

    // SPI 物理引脚
    wire        spi_cs_n;
    wire        spi_sclk;
    wire        spi_mosi;
    reg         spi_miso;

    // 实例化至简设计法 Flash 系统顶层
    flash_top u_flash_top (
        .clk          (clk),
        .rst_n        (rst_n),

        .user_wr_trig (user_wr_trig),
        .user_op_type (user_op_type),
        .user_wr_addr (user_wr_addr),
        .user_wr_data (user_wr_data),
        .user_wr_rdy  (user_wr_rdy),
        .user_wr_done (user_wr_done),

        .user_rd_trig (user_rd_trig),
        .user_rd_addr (user_rd_addr),
        .user_rd_rdy  (user_rd_rdy),
        .user_rd_data (user_rd_data),
        .user_rd_vld  (user_rd_vld),

        .spi_cs_n     (spi_cs_n),
        .spi_sclk     (spi_sclk),
        .spi_mosi     (spi_mosi),
        .spi_miso     (spi_miso)
    );

    // 时钟生成 50MHz
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ================================================================
    // W25Q16 硬件从机行为仿真模型
    // 支持 0x06 (WREN), 0x20 (扇区擦除), 0x02 (页写), 0x03 (读数据), 0x05 (读状态)
    // ================================================================
    reg [7:0] cmd_byte;
    reg [7:0] addr_bytes [0:2];
    reg [7:0] data_bytes [0:3];
    reg [7:0] sim_memory [0:15]; // 模拟前 16 字节存储器
    reg       wip;
    integer   bit_cnt;
    integer   byte_cnt;

    initial begin
        wip      = 1'b0;
        spi_miso = 1'b0;
        sim_memory[0] = 8'hAA;
        sim_memory[1] = 8'hBB;
        sim_memory[2] = 8'hCC;
        sim_memory[3] = 8'hDD;
    end

    always @(negedge spi_cs_n) begin
        cmd_byte = 8'h00;
        byte_cnt = 0;
        bit_cnt  = 7;
        spi_miso = 1'b0;

        while (!spi_cs_n) begin
            @(posedge spi_sclk);
            if (byte_cnt == 0) begin
                cmd_byte[bit_cnt] = spi_mosi;
                if (bit_cnt == 0) begin
                    bit_cnt = 7;
                    byte_cnt = 1;
                end else begin
                    bit_cnt = bit_cnt - 1;
                end
            end else if (cmd_byte == 8'h06) begin
                // WREN 命令：只有 1 字节
            end else if (cmd_byte == 8'h05) begin
                // 读状态命令：在下降沿吐出状态寄存器 (bit 0 = WIP)
            end else if (cmd_byte == 8'h20 || cmd_byte == 8'h02 || cmd_byte == 8'h03) begin
                if (byte_cnt <= 3) begin
                    addr_bytes[byte_cnt-1][bit_cnt] = spi_mosi;
                    if (bit_cnt == 0) begin
                        bit_cnt = 7;
                        byte_cnt = byte_cnt + 1;
                    end else begin
                        bit_cnt = bit_cnt - 1;
                    end
                end else if (cmd_byte == 8'h02) begin
                    // 写入数据
                    if (byte_cnt <= 7) begin
                        data_bytes[byte_cnt-4][bit_cnt] = spi_mosi;
                        if (bit_cnt == 0) begin
                            bit_cnt = 7;
                            byte_cnt = byte_cnt + 1;
                        end else begin
                            bit_cnt = bit_cnt - 1;
                        end
                    end
                end
            end

            @(negedge spi_sclk);
            if (!spi_cs_n) begin
                if (cmd_byte == 8'h05 && byte_cnt >= 1) begin
                    // 吐出状态寄存器：bit 0 为 WIP
                    spi_miso = (bit_cnt == 0) ? wip : 1'b0;
                    if (bit_cnt == 0) bit_cnt = 7;
                    else bit_cnt = bit_cnt - 1;
                end else if (cmd_byte == 8'h03 && byte_cnt >= 4) begin
                    // 读数据命令：吐出 sim_memory 中的数据
                    if (byte_cnt - 4 < 4) begin
                        spi_miso = sim_memory[byte_cnt-4][bit_cnt];
                        if (bit_cnt == 0) begin
                            bit_cnt = 7;
                            byte_cnt = byte_cnt + 1;
                        end else begin
                            bit_cnt = bit_cnt - 1;
                        end
                    end
                end
            end
        end

        // CS 拉高后的动作
        if (cmd_byte == 8'h20) begin
            // 扇区擦除模拟：模拟 5 个时钟周期的 WIP
            wip = 1'b1;
            repeat (5) @(posedge clk);
            sim_memory[0] = 8'hFF;
            sim_memory[1] = 8'hFF;
            sim_memory[2] = 8'hFF;
            sim_memory[3] = 8'hFF;
            wip = 1'b0;
        end else if (cmd_byte == 8'h02) begin
            // 写入模拟：模拟 5 个时钟周期的 WIP
            wip = 1'b1;
            repeat (5) @(posedge clk);
            sim_memory[0] = data_bytes[0];
            sim_memory[1] = data_bytes[1];
            sim_memory[2] = data_bytes[2];
            sim_memory[3] = data_bytes[3];
            wip = 1'b0;
        end
    end

    // 测试主流程
    initial begin
        user_wr_trig = 1'b0;
        user_op_type = 2'b00;
        user_wr_addr = 24'd0;
        user_wr_data = 32'd0;
        user_rd_trig = 1'b0;
        user_rd_addr = 24'd0;
        rst_n        = 1'b0;

        #(CLK_PERIOD * 5);
        rst_n = 1'b1;
        #(CLK_PERIOD * 5);

        $display("\n=======================================================");
        $display(" Start flash_top (至简设计法分层架构) 完整读写测试");
        $display("=======================================================");

        // ------------------------------------------------------------
        // 测试 1：读取初始数据 (预置为 0xAABBCCDD)
        // ------------------------------------------------------------
        $display("\n[TEST 1] 发起 4 字节读数据...");
        @(posedge clk);
        user_rd_addr <= 24'h000000;
        user_rd_trig <= 1'b1;
        @(posedge clk);
        user_rd_trig <= 1'b0;

        @(posedge user_rd_vld);
        $display("[TEST 1 RESULT] 读出数据: 0x%08X (期望: 0xAABBCCDD)", user_rd_data);
        if (user_rd_data !== 32'hAABBCCDD) begin
            $display("[FAIL] TEST 1 FAILED!");
            $finish;
        end

        #(CLK_PERIOD * 10);

        // ------------------------------------------------------------
        // 测试 2：扇区擦除
        // ------------------------------------------------------------
        $display("\n[TEST 2] 发起 4KB 扇区擦除...");
        @(posedge clk);
        user_op_type <= 2'b01; // 扇区擦除
        user_wr_addr <= 24'h000000;
        user_wr_trig <= 1'b1;
        @(posedge clk);
        user_wr_trig <= 1'b0;

        @(posedge user_wr_done);
        $display("[TEST 2 RESULT] 扇区擦除成功完成!");

        #(CLK_PERIOD * 10);

        // ------------------------------------------------------------
        // 测试 3：回读验证擦除是否全 0xFF
        // ------------------------------------------------------------
        $display("\n[TEST 3] 读空检查...");
        @(posedge clk);
        user_rd_addr <= 24'h000000;
        user_rd_trig <= 1'b1;
        @(posedge clk);
        user_rd_trig <= 1'b0;

        @(posedge user_rd_vld);
        $display("[TEST 3 RESULT] 读出数据: 0x%08X (期望: 0xFFFFFFFF)", user_rd_data);
        if (user_rd_data !== 32'hFFFFFFFF) begin
            $display("[FAIL] TEST 3 FAILED!");
            $finish;
        end

        #(CLK_PERIOD * 10);

        // ------------------------------------------------------------
        // 测试 4：写入 4 字节 0x12345678
        // ------------------------------------------------------------
        $display("\n[TEST 4] 写入 4 字节数据 0x12345678...");
        @(posedge clk);
        user_op_type <= 2'b10; // 写入 4 字节
        user_wr_addr <= 24'h000000;
        user_wr_data <= 32'h12345678;
        user_wr_trig <= 1'b1;
        @(posedge clk);
        user_wr_trig <= 1'b0;

        @(posedge user_wr_done);
        $display("[TEST 4 RESULT] 写入成功完成!");

        #(CLK_PERIOD * 10);

        // ------------------------------------------------------------
        // 测试 5：回读验证写入数据
        // ------------------------------------------------------------
        $display("\n[TEST 5] 回读验证...");
        @(posedge clk);
        user_rd_addr <= 24'h000000;
        user_rd_trig <= 1'b1;
        @(posedge clk);
        user_rd_trig <= 1'b0;

        @(posedge user_rd_vld);
        $display("[TEST 5 RESULT] 读出数据: 0x%08X (期望: 0x12345678)", user_rd_data);
        if (user_rd_data !== 32'h12345678) begin
            $display("[FAIL] TEST 5 FAILED!");
            $finish;
        end

        #(CLK_PERIOD * 10);
        $display("\n=======================================================");
        $display(" 恭喜！至简设计法 Flash 系统全部读写测试顺利通过 (PASS)!");
        $display("=======================================================\n");
        $finish;
    end

endmodule
