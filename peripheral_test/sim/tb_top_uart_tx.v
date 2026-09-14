`timescale 1ns/1ps

module tb_top_uart_tx;

    localparam CLK_PERIOD  = 20;                   // 50 MHz
    localparam BAUD_CYCLES = 50;                   // 与下面 defparam 的 1 Mbps 对应
    localparam BAUD_PERIOD = CLK_PERIOD * BAUD_CYCLES;
    localparam TIME_LIMIT  = 5_000_000;            // 看门狗，防止卡在等边沿上跑不完

    reg  sys_clk;
    reg  sys_rst_n;
    reg  uart_rxd;
    wire uart_txd;

    wire spi_cs_n;
    wire spi_sclk;
    wire spi_mosi;
    wire spi_miso;

    reg [7:0] rx_data;
    reg [7:0] test_data [0:5];

    reg [7:0] burst_tx [0:3];
    reg [7:0] burst_rx [0:3];
    reg       sim_done;

    integer i;
    integer j;

    top dut (
        .sys_clk  (sys_clk),
        .sys_rst_n(sys_rst_n),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd),
        .spi_cs_n (spi_cs_n),
        .spi_sclk (spi_sclk),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso)
    );

    // 本测试不使用 SPI，把 MISO 固定为高
    assign spi_miso = 1'b1;

    defparam dut.u_uart_echo_app.UART_BPS = 1000000;

    initial begin
        sys_clk = 1'b0;
        forever #(CLK_PERIOD / 2) sys_clk = ~sys_clk;
    end

    initial begin
        sim_done = 1'b0;
        #TIME_LIMIT;
        if (!sim_done) begin
            $display("FAIL: simulation timeout after %0d ns", TIME_LIMIT);
        end
        $finish;
    end

    initial begin
        test_data[0] = 8'h00;
        test_data[1] = 8'h55;
        test_data[2] = 8'haa;
        test_data[3] = 8'hff;
        test_data[4] = 8'h3c;
        test_data[5] = 8'hc3;

        burst_tx[0] = 8'h01;
        burst_tx[1] = 8'h80;
        burst_tx[2] = 8'hfe;
        burst_tx[3] = 8'h7f;
    end

    initial begin
        uart_rxd  = 1'b1;
        sys_rst_n = 1'b0;
        #(CLK_PERIOD * 10);
        sys_rst_n = 1'b1;
        #(CLK_PERIOD * 10);

        // ---- 测试一：带间隔的逐字节回环 ----
        for (i = 0; i < 6; i = i + 1) begin
            send_uart_byte(test_data[i]);
            read_uart_byte(rx_data);

            if (rx_data !== test_data[i]) begin
                $display("FAIL: expected 0x%02h, got 0x%02h", test_data[i], rx_data);
                sim_stop;
            end

            $display("PASS_BYTE: top echo 0x%02h", rx_data);
            #BAUD_PERIOD;
        end

        // ---- 测试二：背靠背连发 ----
        // RX 侧完全没有位间隙，验证整机 echo 通路在连续数据下不丢字节。
        // 注意：这里测不到 TX 侧的停止位长度问题——echo 结构下 RX 以 10 个位
        // 周期为节拍投递数据，TX FIFO 永远排不满，帧间总有空闲把问题盖住。
        // TX 侧真正背靠背的用例在 tb_uart_core.v 里。
        fork
            send_burst;
            read_burst;
        join

        for (i = 0; i < 4; i = i + 1) begin
            if (burst_rx[i] !== burst_tx[i]) begin
                $display("FAIL burst: index %0d expected 0x%02h, got 0x%02h",
                         i, burst_tx[i], burst_rx[i]);
                sim_stop;
            end
        end
        $display("PASS_BURST: back-to-back echo ok");

        if (dut.uart_rx_overflow !== 1'b0) begin
            $display("FAIL: unexpected rx_overflow");
            sim_stop;
        end

        // 全程都是规规矩矩的好帧，帧错误标志不能有误报
        if (dut.uart_rx_frame_error !== 1'b0) begin
            $display("FAIL: unexpected rx_frame_error");
            sim_stop;
        end

        $display("PASS: top uart rx/tx echo passed");
        sim_stop;
    end

    // 结束仿真：先把看门狗关掉再结束，否则看门狗还会醒过来报一次假的 timeout。
    // 用 $finish 而不是 $stop：$stop 在 iverilog 下遇到 stdin EOF 会自己继续跑。
    task sim_stop;
        begin
            sim_done = 1'b1;
            $finish;
        end
    endtask

    task send_uart_byte;
        input [7:0] data;
        begin
            uart_rxd = 1'b0;
            #BAUD_PERIOD;
            for (j = 0; j < 8; j = j + 1) begin
                uart_rxd = data[j];
                #BAUD_PERIOD;
            end
            uart_rxd = 1'b1;
            #CLK_PERIOD;
        end
    endtask

    // 连发：字节之间不留空闲，上一字节的停止位结束后立刻接下一字节的起始位。
    // 注意不能复用模块级的 j，因为 read_burst 在同一时刻也在跑。
    task send_burst;
        integer k;
        integer b;
        begin
            for (k = 0; k < 4; k = k + 1) begin
                uart_rxd = 1'b0;
                #BAUD_PERIOD;
                for (b = 0; b < 8; b = b + 1) begin
                    uart_rxd = burst_tx[k][b];
                    #BAUD_PERIOD;
                end
                uart_rxd = 1'b1;
                #BAUD_PERIOD;
            end
        end
    endtask

    task read_burst;
        integer k;
        begin
            for (k = 0; k < 4; k = k + 1) begin
                read_uart_byte(burst_rx[k]);
            end
        end
    endtask

    task read_uart_byte;
        output [7:0] data;
        begin
            @(negedge uart_txd);
            #(BAUD_PERIOD + (BAUD_PERIOD / 2));  // 对齐到第 0 个数据位的中点
            for (j = 0; j < 8; j = j + 1) begin
                data[j] = uart_txd;
                #BAUD_PERIOD;
            end

            // 走完 8 个数据位后正好落在停止位中点，此时线上必须是高电平
            if (uart_txd !== 1'b1) begin
                $display("FAIL: stop bit is not high");
                sim_stop;
            end
        end
    endtask

endmodule
