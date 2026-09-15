// led_ctrl_app 单独验证：确认从 show-ahead FIFO 读数据时，
// 每个字节是不是"恰好执行一次"。
//
// 探针原理：led_ctrl_app 只有一条执行路径，就是读取队首并执行命令的那个分支。
// 探针要贴着这个分支写，否则测的是"队首可见了几个周期"而不是"命令执行了几次"：
//
//   - 无状态机版本（每条 !rx_empty 都执行）：探针 = !rx_empty
//   - 带 S_GAP 状态机的版本：探针 = !rx_empty && state == S_IDLE
//
// 用 +define+DUT_HAS_STATE 编译带状态机的版本：
//   iverilog -DDUT_HAS_STATE -o tb.vvp -s tb_led_ctrl_app \
//       tb_led_ctrl_app.v fifo_8x64_sim.v ../rtl/app/led_ctrl_app.v

`timescale 1ns/1ps

module tb_led_ctrl_app;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;

    always #10 clk = ~clk;  // 20ns 周期

    // FIFO 写侧
    reg  [7:0] fifo_data  = 8'h00;
    reg        fifo_wrreq = 1'b0;

    wire [7:0] rx_data;
    wire       rx_empty;
    wire       rx_rdreq;
    wire       led;

    fifo_8x64 u_fifo (
        .clock (clk),
        .sclr  (~rst_n),
        .data  (fifo_data),
        .wrreq (fifo_wrreq),
        .rdreq (rx_rdreq),
        .empty (rx_empty),
        .full  (),
        .q     (rx_data),
        .usedw ()
    );

    led_ctrl_app u_dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx_data  (rx_data),
        .rx_empty (rx_empty),
        .rx_rdreq (rx_rdreq),
        .led      (led)
    );

    integer exec_cnt = 0;
    integer fail_cnt = 0;

    // 执行序列探针
    always @(posedge clk) begin
`ifdef DUT_HAS_STATE
        if (rst_n && !rx_empty && u_dut.state == 1'b0) begin
`else
        if (rst_n && !rx_empty) begin
`endif
            exec_cnt = exec_cnt + 1;
            $display("    [exec #%0d] cmd=%02h", exec_cnt, rx_data);
        end
    end

    task push_byte(input [7:0] b);
        begin
            @(negedge clk);
            fifo_data  = b;
            fifo_wrreq = 1'b1;
            @(negedge clk);
            fifo_wrreq = 1'b0;
        end
    endtask

    task check(input integer expected);
        begin
            if (exec_cnt == expected) begin
                $display("  PASS: exec=%0d", exec_cnt);
            end else begin
                $display("  FAIL: exec=%0d (expect %0d)", exec_cnt, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_led_ctrl_app.vcd");
        $dumpvars(0, tb_led_ctrl_app);

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n[scenario1] single byte 0xAA");
        exec_cnt = 0;
        push_byte(8'hAA);
        repeat (8) @(posedge clk);
        $display("  led=%b", led);
        check(1);

        $display("\n[scenario2] burst AA 55 AA 55");
        exec_cnt = 0;
        push_byte(8'hAA); push_byte(8'h55);
        push_byte(8'hAA); push_byte(8'h55);
        repeat (12) @(posedge clk);
        $display("  led=%b", led);
        check(4);

        $display("\n[scenario3] AA ... gap ... 55");
        exec_cnt = 0;
        push_byte(8'hAA);
        repeat (20) @(posedge clk);
        push_byte(8'h55);
        repeat (8) @(posedge clk);
        $display("  led=%b", led);
        check(2);

        $display("\n[scenario4] 10 bytes, reader faster than line rate");
        exec_cnt = 0;
        for (integer i = 0; i < 10; i = i + 1)
            push_byte((i % 2) ? 8'h55 : 8'hAA);
        repeat (20) @(posedge clk);
        $display("  led=%b", led);
        check(10);

        if (fail_cnt == 0) $display("\nALL PASS");
        else               $display("\n%0d SCENARIO(S) FAILED", fail_cnt);
        $finish;
    end

    initial begin
        #500000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
