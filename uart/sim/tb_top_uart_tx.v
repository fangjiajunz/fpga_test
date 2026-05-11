`timescale 1ns/1ps

module tb_top_uart_tx;

    localparam CLK_PERIOD = 20;
    localparam BAUD_CYCLES = 50;
    localparam BAUD_PERIOD = CLK_PERIOD * BAUD_CYCLES;

    reg sys_clk;
    reg sys_rst_n;
    reg [3:0] key;
    wire [3:0] led;
    wire [7:0] seg_led;
    wire [5:0] seg_sel;
    wire uart_txd;

    reg [7:0] rx_data;
    integer i;

    top dut (
        .sys_clk  (sys_clk),
        .sys_rst_n(sys_rst_n),
        .key      (key),
        .led      (led),
        .seg_led  (seg_led),
        .seg_sel  (seg_sel),
        .uart_txd (uart_txd)
    );

    defparam dut.u_timer.LED_MAX_COUNT = 49;
    defparam dut.uart_tx_inst.UART_BPS = 1000000;

    initial begin
        sys_clk = 1'b0;
        forever #(CLK_PERIOD / 2) sys_clk = ~sys_clk;
    end

    initial begin
        key = 4'b1111;
        sys_rst_n = 1'b0;
        #(CLK_PERIOD * 10);
        sys_rst_n = 1'b1;

        @(negedge uart_txd);
        #(BAUD_PERIOD + (BAUD_PERIOD / 2));
        for (i = 0; i < 8; i = i + 1) begin
            rx_data[i] = uart_txd;
            #BAUD_PERIOD;
        end

        if (uart_txd !== 1'b1) begin
            $display("FAIL: stop bit is not high");
            $stop;
        end

        if (rx_data !== 8'h55) begin
            $display("FAIL: expected 0x55, got 0x%02h", rx_data);
            $stop;
        end

        $display("PASS: top transmitted 0x%02h", rx_data);
        $stop;
    end

endmodule
