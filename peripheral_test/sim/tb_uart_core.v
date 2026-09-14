`timescale 1ns/1ps

// uart_core 的针对性测试。
// 和 tb_top_uart_tx.v 的区别：这里直接驱动 uart_core，可以
//   1) 往 TX FIFO 里一次性预装多个字节，逼出真正的背靠背发送；
//   2) 往 rxd 上注入窄毛刺，验证起始位确认逻辑和数据位三取二表决；
//   3) 故意把停止位拉低，验证帧错误标志。
// 这几条在整机 echo 回环里都测不到（RX 会以 10 个位周期为节拍限制 TX 的节奏）。
module tb_uart_core;

    localparam CLK_PERIOD  = 20;                   // 50 MHz
    localparam BAUD_CYCLES = 50;                   // 对应 1 Mbps
    localparam BAUD_PERIOD = CLK_PERIOD * BAUD_CYCLES;
    localparam TIME_LIMIT  = 5_000_000;

    // uart_rx 的数据位采样窗宽 = BAUD_CNT_MAX/16 = BAUD_CYCLES/16 = 3。
    // 毛刺只要窄于这个间隔，就不可能同时盖住 3 个采样点中的 2 个。
    localparam GLITCH_MAX = BAUD_CYCLES / 16 - 1;  // = 2

    reg  clk;
    reg  rst_n;
    reg  rxd;
    wire txd;

    reg  [7:0] tx_data;
    reg        tx_wrreq;
    wire       tx_full;

    wire [7:0] rx_data;
    wire       rx_empty;
    wire       rx_full;
    wire       rx_overflow;
    wire       rx_frame_error;
    reg        rx_overflow_clr;
    reg        rx_frame_err_clr;
    reg        rx_rdreq;

    reg  [7:0] tx_payload [0:3];
    reg  [7:0] rx_got;
    reg        sim_done;
    integer    glitch_fail;

    integer i;
    integer j;

    uart_core #(
        .UART_BPS(1000000),
        .CLK_FREQ(50_000_000)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .rxd              (rxd),
        .txd              (txd),
        .rx_data          (rx_data),
        .rx_empty         (rx_empty),
        .rx_full          (rx_full),
        .rx_overflow      (rx_overflow),
        .rx_frame_error   (rx_frame_error),
        .rx_overflow_clr  (rx_overflow_clr),
        .rx_frame_err_clr (rx_frame_err_clr),
        .rx_rdreq         (rx_rdreq),
        .tx_data          (tx_data),
        .tx_wrreq         (tx_wrreq),
        .tx_full          (tx_full)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
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
        tx_payload[0] = 8'h01;
        tx_payload[1] = 8'h80;
        tx_payload[2] = 8'hfe;
        tx_payload[3] = 8'h7f;
    end

    initial begin
        rxd              = 1'b1;
        rst_n            = 1'b0;
        tx_data          = 8'h00;
        tx_wrreq         = 1'b0;
        rx_rdreq         = 1'b0;
        rx_overflow_clr  = 1'b0;
        rx_frame_err_clr = 1'b0;
        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 10);

        // ================= 测试 A：TX 连续发送 =================
        // 一次性把 4 个字节写进 TX FIFO，uart_core 会一帧接一帧地发出去，
        // 帧间没有任何空闲。停止位必须是完整的 1 个位周期，否则接收方在
        // 第 9.5 个位周期采停止位时，线上已经是下一帧的起始位了。
        // 必须用非阻塞赋值：@(posedge clk) 之后用阻塞赋值会和 DUT 在同一个
        // 时钟沿抢事件，FIFO 可能当拍就采到新值，也可能采到旧值。
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge clk);
            tx_data  <= tx_payload[i];
            tx_wrreq <= 1'b1;
        end
        @(posedge clk);
        tx_wrreq <= 1'b0;

        for (i = 0; i < 4; i = i + 1) begin
            read_uart_byte(rx_got);
            if (rx_got !== tx_payload[i]) begin
                $display("FAIL tx_stream: index %0d expected 0x%02h, got 0x%02h",
                         i, tx_payload[i], rx_got);
                sim_stop;
            end
        end
        $display("PASS_TX_STREAM: 4-byte back-to-back tx ok");

        // ================= 测试 B：起始位上的窄毛刺 =================
        // 假起始位：线上一个远短于半个位周期的低脉冲。起始位的三个采样点
        // 都会是高的，表决结果是高 -> 放弃本次接收，不产生任何数据。
        #(BAUD_PERIOD * 4);
        @(negedge clk);             // 对齐到时钟沿之外，避免注入时刻不确定
        rxd = 1'b0;                 // 6 个时钟的窄脉冲
        #(CLK_PERIOD * 6);
        rxd = 1'b1;
        #(BAUD_PERIOD * 20);        // 留足恢复时间

        if (!rx_empty) begin
            $display("FAIL glitch: rx fifo not empty after glitch, data=0x%02h", rx_data);
            sim_stop;
        end
        if (rx_frame_error !== 1'b0) begin
            $display("FAIL glitch: spurious start bit must not set frame_error");
            sim_stop;
        end
        $display("PASS_GLITCH: narrow glitch rejected");

        // 毛刺之后必须还能正常收字节
        send_uart_byte(8'h5a);
        expect_rx_byte(8'h5a, "glitch recover");
        $display("PASS_GLITCH_RECOVER: normal byte received after glitch");

        // ================= 测试 C：数据位上的窄毛刺（三取二表决） =================
        // 在数据位内每个位置都插一个 GLITCH_MAX 时钟宽的低脉冲，字节必须是
        // 8'hff（全 1，所以任何低脉冲都是错误电平），并且每次都要完整收对。
        //
        // 这是三取二表决真正的价值所在：单点采样只要毛刺正好压在那个采样点上
        // 就会把这一位收反，而这个测试把毛刺扫过整个位周期，单点采样必然翻车。
        // 表决要求三个点里至少两个是错的才会翻，而三个点间隔 BAUD_CYCLES/16，
        // 所以窄于这个间隔的毛刺无论落在哪儿都翻不了。
        // 失败不立刻停：把每个失败位置打出来，方便一眼看出是哪个区间没护住
        glitch_fail = 0;
        for (i = 0; i <= BAUD_CYCLES - 1; i = i + 1) begin
            send_byte_glitch(8'hff, 0, i, GLITCH_MAX);
            wait_rx_not_empty;
            if (rx_data !== 8'hff) begin
                $display("  FAIL glitch at offset %0d: got 0x%02h", i, rx_data);
                glitch_fail = glitch_fail + 1;
            end
            pop_rx_byte;
        end
        if (glitch_fail != 0) begin
            $display("FAIL_DATA_GLITCH: %0d/%0d positions corrupted", glitch_fail, BAUD_CYCLES);
            sim_stop;
        end
        $display("PASS_DATA_GLITCH: %0d-wide glitch rejected at all %0d positions",
                 GLITCH_MAX, BAUD_CYCLES);

        if (rx_frame_error !== 1'b0) begin
            $display("FAIL: data glitch must not set frame_error");
            sim_stop;
        end

        // ================= 测试 D：帧错误（停止位为低） =================
        // 数据照常进 FIFO（标准 UART 行为），但 frame_error 要置位并锁住。
        send_byte_bad_stop(8'ha5);
        expect_rx_byte(8'ha5, "bad stop data");

        // 标志可能比数据晚一点（都是停止位采样那一拍产生，但 sticky 寄存器
        // 比 out_flag 晚一拍），等两个时钟再查
        #(CLK_PERIOD * 4);
        if (rx_frame_error !== 1'b1) begin
            $display("FAIL: frame_error not set on low stop bit");
            sim_stop;
        end
        $display("PASS_FRAME_ERROR: low stop bit flagged");

        // 清除：给一拍 clr，标志必须掉
        rx_frame_err_clr = 1'b1;
        #(CLK_PERIOD * 2);
        rx_frame_err_clr = 1'b0;
        #(CLK_PERIOD * 2);
        if (rx_frame_error !== 1'b0) begin
            $display("FAIL: frame_error not cleared by rx_frame_err_clr");
            sim_stop;
        end

        // 清除之后再来一个好帧，标志必须保持为 0（不能误报）
        send_uart_byte(8'h36);
        expect_rx_byte(8'h36, "good frame after clear");
        #(CLK_PERIOD * 4);
        if (rx_frame_error !== 1'b0) begin
            $display("FAIL: good frame set frame_error");
            sim_stop;
        end
        $display("PASS_FRAME_ERROR_CLEAR: sticky flag cleared and stays clear");

        if (rx_overflow !== 1'b0) begin
            $display("FAIL: unexpected rx_overflow");
            sim_stop;
        end

        $display("PASS: uart_core tx/rx tests passed");
        sim_stop;
    end

    // ---------------- 任务 ----------------

    task sim_stop;
        begin
            sim_done = 1'b1;
            $finish;   // 用 $finish 而不是 $stop：$stop 在 iverilog 下遇到
                       // stdin EOF 会自己继续跑，失败信息后面会跟一大堆垃圾
        end
    endtask

    // 按位周期推进 n 个时钟。所有跳变都落在 negedge 上，这样相对起始沿的
    // 偏移量就是精确的时钟数，不依赖 posedge 上的赋值竞争。
    task wait_cycles;
        input integer n;
        integer t;
        begin
            for (t = 0; t < n; t = t + 1) @(negedge clk);
        end
    endtask

    task send_uart_byte;
        input [7:0] data;
        begin
            @(negedge clk);
            rxd = 1'b0;
            wait_cycles(BAUD_CYCLES);
            for (j = 0; j < 8; j = j + 1) begin
                rxd = data[j];
                wait_cycles(BAUD_CYCLES);
            end
            rxd = 1'b1;
            wait_cycles(BAUD_CYCLES);
        end
    endtask

    // 停止位故意拉低：数据位发完之后不正线上拉到空闲，而是继续拉低一个位
    // 周期，然后才回高。接收方在停止位采样点看到低电平 -> 帧错误。
    task send_byte_bad_stop;
        input [7:0] data;
        begin
            @(negedge clk);
            rxd = 1'b0;
            wait_cycles(BAUD_CYCLES);
            for (j = 0; j < 8; j = j + 1) begin
                rxd = data[j];
                wait_cycles(BAUD_CYCLES);
            end
            rxd = 1'b0;              // <-- 本该是停止位（高），这里保持低
            wait_cycles(BAUD_CYCLES);
            rxd = 1'b1;
            wait_cycles(BAUD_CYCLES);
        end
    endtask

    // 发送一个字节，并在数据位 gbit 内偏移 goff 个时钟处插入一段 gwidth
    // 时钟宽的错误电平（毛刺）。
    // 注意毛刺前后都必须把本位真实电平驱动出来，否则在 data[gbit]==0 的那一帧
    // 里“毛刺”会和前后位黏成一片，那就不是毛刺了，而是把这一位整体挪了位置。
    task send_byte_glitch;
        input [7:0] data;
        input integer gbit;
        input integer goff;
        input integer gwidth;
        integer b;
        begin
            @(negedge clk);
            rxd = 1'b0;                                  // 起始位
            for (b = 0; b < gbit; b = b + 1) begin       // gbit 之前的数据位
                wait_cycles(BAUD_CYCLES);
                rxd = data[b];
            end
            wait_cycles(BAUD_CYCLES);                    // 本位开始
            rxd = data[gbit];
            wait_cycles(goff);                           // 本位内偏移到毛刺位置
            rxd = ~data[gbit];                           // 毛刺
            wait_cycles(gwidth);
            rxd = data[gbit];                            // 恢复本位真实电平
            wait_cycles(BAUD_CYCLES - goff - gwidth);
            for (b = gbit + 1; b < 8; b = b + 1) begin   // 剩下的数据位
                rxd = data[b];
                wait_cycles(BAUD_CYCLES);
            end
            rxd = 1'b1;                                  // 停止位
            wait_cycles(BAUD_CYCLES);
        end
    endtask

    // 有界等待，避免卡死
    task wait_rx_not_empty;
        integer n;
        reg     done;
        begin
            done = 1'b0;
            for (n = 0; (n < 4000) && !done; n = n + 1) begin
                @(posedge clk);
                if (!rx_empty) done = 1'b1;
            end
            if (!done) begin
                $display("FAIL: rx fifo stayed empty");
                sim_stop;
            end
        end
    endtask

    // 弹出队首。show-ahead FIFO，q 一直是队首，给一拍 rdreq 就把它弹掉。
    task pop_rx_byte;
        begin
            @(posedge clk);
            rx_rdreq <= 1'b1;
            @(posedge clk);
            rx_rdreq <= 1'b0;
            @(posedge clk);
        end
    endtask

    // 等一个字节 -> 比对 -> 弹出
    task expect_rx_byte;
        input [7:0]   expected;
        input [127:0] tag;
        begin
            wait_rx_not_empty;
            if (rx_data !== expected) begin
                $display("FAIL %0s: expected 0x%02h, got 0x%02h", tag, expected, rx_data);
                sim_stop;
            end
            pop_rx_byte;
        end
    endtask

    task read_uart_byte;
        output [7:0] data;
        begin
            @(negedge txd);
            #(BAUD_PERIOD + (BAUD_PERIOD / 2));  // 对齐到第 0 个数据位的中点
            for (j = 0; j < 8; j = j + 1) begin
                data[j] = txd;
                #BAUD_PERIOD;
            end

            // 走完 8 个数据位后正好落在停止位中点，此时线上必须是高电平
            if (txd !== 1'b1) begin
                $display("FAIL: stop bit is not high (frame shorter than 10 bit periods?)");
                sim_stop;
            end
        end
    endtask

endmodule
