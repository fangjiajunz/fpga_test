// 顶层串口整机测试：PC 发字节 -> uart_core 的 RX FIFO -> led_ctrl_app -> LED。
//
// 注意：顶层已经从"UART 回环"改成"UART 控制 LED"，本文件原来的
// echo 断言（read_uart_byte / 回读比对）随之删除，因为顶层 TX 侧不再有人写。
// uart_core 自身的 TX 通路仍由 tb_uart_core.v 覆盖。
// 文件名保留 tb_top_uart_tx.v 是为了不动历史，实际测的是 RX -> LED。

`timescale 1ns/1ps

module tb_top_uart_tx;

    localparam CLK_PERIOD  = 20;         // 50 MHz
    localparam BAUD_CYCLES = 50;         // 与下面 defparam 的 1 Mbps 对应
    localparam BAUD_PERIOD = CLK_PERIOD * BAUD_CYCLES;
    localparam TIME_LIMIT  = 5_000_000;  // 看门狗，防止卡在等边沿上跑不完

    reg  sys_clk;
    reg  sys_rst_n;
    reg  uart_rxd;
    wire uart_txd;
    wire led;

    wire spi_cs_n;
    wire spi_sclk;
    wire spi_mosi;
    wire spi_miso;

    reg       sim_done;
    integer   i;
    integer   j;

    reg [7:0] cmds [0:3];   // 交替命令序列，用来验证命令按顺序、逐个生效
    reg [7:0] burst [0:3];
    reg       cmds_led [0:3];  // 每条命令之后 LED 应有的值

    top dut (
        .sys_clk  (sys_clk),
        .sys_rst_n(sys_rst_n),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd),
        .led      (led),
        .spi_cs_n (spi_cs_n),
        .spi_sclk (spi_sclk),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso)
    );

    // 本测试不使用 SPI，把 MISO 固定为高
    assign spi_miso = 1'b1;

    defparam dut.u_uart_core.UART_BPS = 1000000;

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
        cmds[0] = 8'haa;
        cmds[1] = 8'h55;
        cmds[2] = 8'haa;
        cmds[3] = 8'h55;

        cmds_led[0] = 1'b1;
        cmds_led[1] = 1'b0;
        cmds_led[2] = 1'b1;
        cmds_led[3] = 1'b0;

        burst[0] = 8'haa;
        burst[1] = 8'h55;
        burst[2] = 8'haa;
        burst[3] = 8'h55;
    end

    initial begin
        uart_rxd  = 1'b1;
        sys_rst_n = 1'b0;
        #(CLK_PERIOD * 10);
        sys_rst_n = 1'b1;
        #(CLK_PERIOD * 10);

        // ---- 测试一：逐字节发命令，每发一个检查一次 LED ----
        // 0xAA/0x55 都是幂等命令，所以这一步主要验证命令按顺序、逐个生效，
        // 以及 LED 能从两个方向翻转。
        for (i = 0; i < 4; i = i + 1) begin
            send_uart_byte(cmds[i]);
            #(BAUD_PERIOD);

            if (led !== cmds_led[i]) begin
                $display("FAIL: after cmd 0x%02h expected led=%b, got %b",
                         cmds[i], cmds_led[i], led);
                sim_stop;
            end
            $display("PASS_CMD: 0x%02h -> led=%b", cmds[i], led);
        end

        // ---- 测试二：最小间隔连发 ----
        // 每帧之间只有一个停止位，没有额外空闲（测试一每条命令后面多等了一个
        // 位周期）。验证整机在连续数据下不丢字节。
        // 命令是幂等的，末态看不出丢没丢，所以额外检查 RX FIFO 最终被抽空。
        for (i = 0; i < 4; i = i + 1) begin
            send_uart_byte(burst[i]);
        end
        uart_rxd = 1'b1;
        #(BAUD_PERIOD * 20);

        if (dut.uart_rx_empty !== 1'b1) begin
            $display("FAIL: RX FIFO not drained after burst");
            sim_stop;
        end
        if (led !== 1'b0) begin
            $display("FAIL burst: expected led=1'b0 (last cmd 0x55), got %b", led);
            sim_stop;
        end
        $display("PASS_BURST: back-to-back rx ok, fifo drained");

        if (dut.uart_rx_overflow !== 1'b0) begin
            $display("FAIL: unexpected rx_overflow");
            sim_stop;
        end

        // ---- 测试三：帧错误上报 ----
        // 停止位故意拉低，uart_rx 应当报 frame_error 并锁在 uart_core 里。
        // 这个标志是 sticky 的（顶层 clr 接 1'b0），所以放在最后测。
        if (dut.uart_rx_frame_error !== 1'b0) begin
            $display("FAIL: rx_frame_error set before bad frame");
            sim_stop;
        end
        send_uart_byte_badstop(8'hAA);
        #(BAUD_PERIOD * 2);

        if (dut.uart_rx_frame_error !== 1'b1) begin
            $display("FAIL: frame error not reported for bad stop bit");
            sim_stop;
        end
        $display("PASS_FRAME_ERR: bad stop bit reported");

        $display("PASS: top uart rx -> led passed");
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

    // 发一个字节。停止位必须保持完整的位周期：uart_rx 在停止位中点采样，
    // 提前拉低会被判成帧错误（这正是 send_uart_byte_badstop 故意做的事）。
    task send_uart_byte;
        input [7:0] data;
        begin
            uart_rxd = 1'b0;      // 起始位
            #BAUD_PERIOD;
            for (j = 0; j < 8; j = j + 1) begin
                uart_rxd = data[j];
                #BAUD_PERIOD;
            end
            uart_rxd = 1'b1;      // 停止位
            #BAUD_PERIOD;
        end
    endtask

    // 停止位为低的坏帧
    task send_uart_byte_badstop;
        input [7:0] data;
        begin
            uart_rxd = 1'b0;
            #BAUD_PERIOD;
            for (j = 0; j < 8; j = j + 1) begin
                uart_rxd = data[j];
                #BAUD_PERIOD;
            end
            uart_rxd = 1'b0;      // 停止位不是高 -> 帧错误
            #BAUD_PERIOD;
            uart_rxd = 1'b1;      // 回到空闲，避免影响后续
            #CLK_PERIOD;
        end
    endtask

endmodule
