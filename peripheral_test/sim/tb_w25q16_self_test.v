`timescale 1ns / 1ps

module tb_w25q16_self_test;

    localparam CLK_PERIOD = 20; // 50MHz

    reg  clk;
    reg  rst_n;
    reg  btn_trigger;

    // Flash 控制线
    wire        flash_start;
    wire [2:0]  flash_op;
    wire [23:0] flash_addr;
    wire [31:0] flash_wr_data;
    wire [31:0] flash_rd_data;
    wire [23:0] flash_id;
    wire        flash_busy;
    wire        flash_done;
    wire        flash_error;

    // 串口输出线
    wire [7:0]  tx_data;
    wire        tx_wrreq;
    reg         tx_full;
    wire        test_done;
    wire        test_pass;

    // SPI 互联总线
    wire        spi_start;
    wire [7:0]  spi_burst_len;
    wire        spi_tx_req;
    wire [7:0]  spi_tx_byte;

    wire        spi_rx_valid;
    wire [7:0]  spi_rx_byte;
    wire        spi_busy;
    wire        spi_done;

    // 物理 SPI 引脚
    wire        spi_cs_n;
    wire        spi_sclk;
    wire        spi_mosi;
    reg         spi_miso;

    // 实例化 Flash 自检业务层 (仿真加速上电延时为 200 个周期)
    flash_test_app #(
        .CLK_FREQ(50_000_000),
        .AUTO_START_DELAY(200)
    ) u_flash_test_app (
        .clk             (clk),
        .rst_n           (rst_n),
        .btn_trigger     (btn_trigger),

        .flash_start     (flash_start),
        .flash_operation (flash_op),
        .flash_address   (flash_addr),
        .flash_wr_data   (flash_wr_data),
        .flash_rd_data   (flash_rd_data),
        .flash_id        (flash_id),
        .flash_busy      (flash_busy),
        .flash_done      (flash_done),
        .flash_error     (flash_error),

        .tx_data         (tx_data),
        .tx_wrreq        (tx_wrreq),
        .tx_full         (tx_full),

        .test_done       (test_done),
        .test_pass       (test_pass)
    );

    // 实例化 Flash 驱动控制层
    w25q16_ctrl u_w25q16_ctrl (
        .clk           (clk),
        .rst_n         (rst_n),

        .start         (flash_start),
        .operation     (flash_op),
        .address       (flash_addr),
        .wr_data_32    (flash_wr_data),
        .rd_data_32    (flash_rd_data),
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

    // 实例化 SPI 主控制器
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

    // 接收串口打印字符
    always @(posedge clk) begin
        if (tx_wrreq) begin
            $write("%c", tx_data);
        end
    end

    // ================================================================
    // W25Q16 硬件从机高仿真模型 (含存储阵列与状态寄存器模拟)
    always @(posedge clk) begin
        if (u_flash_test_app.flash_start) begin
            $display("[APP_FLASH_START] op=%0d addr=0x%06X wr=0x%08X time=%0t",
                     u_flash_test_app.flash_operation, u_flash_test_app.flash_address, u_flash_test_app.flash_wr_data, $time);
        end
        if (u_w25q16_ctrl.done) begin
            $display("[CTRL_DONE] flash_id=0x%06X rd=0x%08X err=%b time=%0t",
                     u_w25q16_ctrl.flash_id, u_w25q16_ctrl.rd_data_32, u_w25q16_ctrl.error, $time);
        end
        if (u_flash_test_app.current_state != u_flash_test_app.next_state) begin
            $display("[APP_STATE_CHANGE] %0d -> %0d at time %0t",
                     u_flash_test_app.current_state, u_flash_test_app.next_state, $time);
        end
    end

    // ================================================================
    reg [7:0] flash_mem [0:4095]; // 模拟 4KB 扇区存储区
    reg       wren_latch;         // 写使能锁存器 (WEL)
    reg [7:0] status_reg_1;       // bit[0]: WIP (写忙), bit[1]: WEL
    integer   busy_timer;

    reg [7:0] current_cmd;
    reg [23:0] current_addr;
    integer   byte_count;

    initial begin
        wren_latch   = 1'b0;
        status_reg_1 = 8'h00;
        busy_timer   = 0;
        spi_miso     = 1'b0;

        // 初始化扇区为预存的脏数据 (非 0xFF)
        flash_mem[0] = 8'hAA;
        flash_mem[1] = 8'h55;
        flash_mem[2] = 8'hAA;
        flash_mem[3] = 8'h55;
    end

    // ================================================================
    // W25Q16 硬件从机模型 (事件驱动，永不死锁)
    // ================================================================
    integer   bit_count;
    reg [7:0] shift_in;
    reg [7:0] shift_out;

    // 模拟内部擦写延时 (每次操作忙 10 个时钟)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_timer      <= 0;
            status_reg_1[0] <= 1'b0;
        end else if (busy_timer > 0) begin
            busy_timer      <= busy_timer - 1;
            status_reg_1[0] <= 1'b1; // WIP = 1
        end else begin
            status_reg_1[0] <= 1'b0; // WIP = 0
        end
    end

    // CS_N 拉低：一次新事务开始
    always @(negedge spi_cs_n) begin
        byte_count   = 0;
        bit_count    = 0;
        current_cmd  = 8'h00;
        current_addr = 24'h000000;
        shift_out    = 8'hFF;
        spi_miso     = 1'b0;
    end

    // CS_N 拉高：一次事务结束，执行落锁动作
    always @(posedge spi_cs_n) begin
        if (current_cmd == 8'h06) begin
            wren_latch <= 1'b1; // 写使能
        end else if (current_cmd == 8'h20 && wren_latch) begin
            integer i;
            for (i = 0; i < 4096; i = i + 1) flash_mem[i] = 8'hFF;
            busy_timer <= 10;
            wren_latch <= 1'b0;
        end else if (current_cmd == 8'h02 && wren_latch) begin
            busy_timer <= 10;
            wren_latch <= 1'b0;
        end
    end

    // SCLK 上升沿：采样 MOSI
    always @(posedge spi_sclk) begin
        if (!spi_cs_n) begin
            shift_in = {shift_in[6:0], spi_mosi};
            bit_count = bit_count + 1;

            if (bit_count == 8) begin
                bit_count = 0;
                if (byte_count == 0) begin
                    current_cmd = shift_in;
                end else if (byte_count == 1) begin
                    current_addr[23:16] = shift_in;
                end else if (byte_count == 2) begin
                    current_addr[15:8] = shift_in;
                end else if (byte_count == 3) begin
                    current_addr[7:0] = shift_in;
                end else if (byte_count >= 4) begin
                    if (current_cmd == 8'h02 && wren_latch) begin
                        flash_mem[current_addr[11:0] + (byte_count - 4)] = shift_in;
                    end
                end
                byte_count = byte_count + 1;
            end
        end
    end

    // SCLK 下降沿：驱动 MISO
    always @(negedge spi_sclk) begin
        if (!spi_cs_n) begin
            if (bit_count == 0) begin
                // 一个字节刚刚收完，装填下一个待发送字节
                if (current_cmd == 8'h9F) begin
                    if (byte_count == 1) shift_out = 8'hEF;
                    else if (byte_count == 2) shift_out = 8'h40;
                    else if (byte_count == 3) shift_out = 8'h15;
                    else shift_out = 8'hFF;
                end else if (current_cmd == 8'h05) begin
                    shift_out = status_reg_1;
                end else if (current_cmd == 8'h03) begin
                    if (byte_count >= 4)
                        shift_out = flash_mem[current_addr[11:0] + (byte_count - 4)];
                    else
                        shift_out = 8'hFF;
                end else begin
                    shift_out = 8'hFF;
                end
            end

            spi_miso <= shift_out[7];
            shift_out = {shift_out[6:0], 1'b1};
        end
    end

    // 测试主流程
    initial begin
        rst_n       = 1'b0;
        btn_trigger = 1'b0;
        tx_full     = 1'b0;

        #(CLK_PERIOD * 10);
        rst_n = 1'b1;

        $display("\n=======================================================");
        $display(" [TESTBENCH] W25Q16 Automated Self-Test Running...");
        $display("=======================================================");

        // 等待测试完成
        @(posedge test_done);
        #(CLK_PERIOD * 200);

        if (test_pass === 1'b1) begin
            $display("\n[TESTBENCH PASS] W25Q16 Self-Test Finished Successfully!");
        end else begin
            $display("\n[TESTBENCH FAIL] W25Q16 Self-Test Failed!");
            $finish;
        end

        $finish;
    end

endmodule
