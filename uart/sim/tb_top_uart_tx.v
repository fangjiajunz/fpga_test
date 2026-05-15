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
    reg uart_rxd;
    wire uart_txd;

    reg [7:0] rx_data;
    reg [7:0] test_data [0:5];
    integer i;
    integer j;

    top dut (
        .sys_clk  (sys_clk),
        .sys_rst_n(sys_rst_n),
        .key      (key),
        .led      (led),
        .seg_led  (seg_led),
        .seg_sel  (seg_sel),
        .uart_rxd (uart_rxd),
        .uart_txd (uart_txd)
    );

    defparam dut.u_uart_echo_app.UART_BPS = 1000000;

    initial begin
        sys_clk = 1'b0;
        forever #(CLK_PERIOD / 2) sys_clk = ~sys_clk;
    end

    initial begin
        test_data[0] = 8'h00;
        test_data[1] = 8'h55;
        test_data[2] = 8'haa;
        test_data[3] = 8'hff;
        test_data[4] = 8'h3c;
        test_data[5] = 8'hc3;
    end

    initial begin
        key = 4'b1111;
        uart_rxd = 1'b1;
        sys_rst_n = 1'b0;
        #(CLK_PERIOD * 10);
        sys_rst_n = 1'b1;
        #(CLK_PERIOD * 10);

        for (i = 0; i < 6; i = i + 1) begin
            send_uart_byte(test_data[i]);
            read_uart_byte(rx_data);

            if (rx_data !== test_data[i]) begin
                $display("FAIL: expected 0x%02h, got 0x%02h", test_data[i], rx_data);
                $stop;
            end

            if (led !== test_data[i][3:0]) begin
                $display("FAIL: led expected 0x%01h, got 0x%01h", test_data[i][3:0], led);
                $stop;
            end

            $display("PASS_BYTE: top echo 0x%02h", rx_data);
            #BAUD_PERIOD;
        end

        $display("PASS: top uart rx/tx echo passed");
        $stop;
    end

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

    task read_uart_byte;
        output [7:0] data;
        begin
            @(negedge uart_txd);
            #(BAUD_PERIOD + (BAUD_PERIOD / 2));
            for (j = 0; j < 8; j = j + 1) begin
                data[j] = uart_txd;
                #BAUD_PERIOD;
            end

            if (uart_txd !== 1'b1) begin
                $display("FAIL: stop bit is not high");
                $stop;
            end
        end
    endtask

endmodule
