`timescale 1ns / 1ps

module tb_top_protocol;

    localparam CLK_PERIOD  = 20;            // 50MHz 时钟
    localparam UART_BPS    = 1000000;       // 仿真加速为 1Mbps
    localparam BAUD_PERIOD = 1000;          // 1Mbps -> 1000ns/bit
    localparam BAUD_CYCLES = BAUD_PERIOD / CLK_PERIOD; // 50 cycles

    reg        sys_clk;
    reg        sys_rst_n;
    reg        uart_rxd;
    wire       uart_txd;
    wire [3:0] led;
    wire [3:0] key;

    assign key = 4'b1111;

    top #(
        .UART_BPS(1000000),
        .CLK_FREQ(50_000_000)
    ) dut (
        .sys_clk   (sys_clk),
        .sys_rst_n (sys_rst_n),
        .uart_rxd  (uart_rxd),
        .uart_txd  (uart_txd),
        .led       (led),
        .key       (key),
        .spi_cs_n  (),
        .spi_sclk  (),
        .spi_mosi  (),
        .spi_miso  (1'b1)
    );

    initial begin
        sys_clk = 1'b0;
        forever #(CLK_PERIOD / 2) sys_clk = ~sys_clk;
    end

    always @(posedge sys_clk) begin
        if (dut.u_uart_core.rx_valid) begin
            $display("[CORE_RX] valid data=0x%02h time=%0t", dut.u_uart_core.rx_data, $time);
        end
        if (dut.u_decode.data_out_valid) begin
            $display("[DECODE_OUT] type=%02h addr=%0d data=%02h time=%0t",
                     dut.u_decode.packet_type, dut.u_decode.data_out_addr, dut.u_decode.data_out, $time);
        end
        if (dut.u_decode.packet_done) begin
            $display("[DECODE_DONE] check_ok=%b packet_error=%b time=%0t",
                     dut.u_decode.check_ok, dut.u_decode.packet_error, $time);
        end
    end

    task wait_cycles;
        input integer n;
        repeat (n) @(posedge sys_clk);
    endtask

    task send_uart_byte;
        input [7:0] data;
        integer j;
        begin
            @(negedge sys_clk);
            uart_rxd = 1'b0; // start bit
            wait_cycles(BAUD_CYCLES);
            for (j = 0; j < 8; j = j + 1) begin
                uart_rxd = data[j];
                wait_cycles(BAUD_CYCLES);
            end
            uart_rxd = 1'b1; // stop bit
            wait_cycles(BAUD_CYCLES);
        end
    endtask

    initial begin
        uart_rxd  = 1'b1;
        sys_rst_n = 1'b0;
        #(CLK_PERIOD * 10);
        sys_rst_n = 1'b1;
        #(CLK_PERIOD * 20);

        $display("--- Step 1: Send LED command packet (LED -> 4'b0101) ---");
        // 包格式: SYNC(0x55, 0x55, 0x55) + TYPE(0x00) + LEN(0x00, 0x01) + PAYLOAD(0x05) + CHECKSUM
        // CHECKSUM = (TYPE 0x00 + LEN_H 0x00 + LEN_L 0x01 + PAYLOAD 0x05) = 0x06
        send_uart_byte(8'h55);
        send_uart_byte(8'h55);
        send_uart_byte(8'h55);
        send_uart_byte(8'h00);
        send_uart_byte(8'h00);
        send_uart_byte(8'h01);
        send_uart_byte(8'h05);
        send_uart_byte(8'h06); // checksum

        // 等待几个比特周期让流水线解析完
        wait_cycles(BAUD_CYCLES * 5);

        if (led === 4'b0101) begin
            $display("[PASS] Step 1: LED successfully updated to 4'b0101!");
        end else begin
            $display("[FAIL] Step 1: Expected led=4'b0101, got %b", led);
            $finish;
        end

        $display("--- Step 2: Send LED command packet (LED -> 4'b1010) ---");
        // 包格式: 0x55, 0x55, 0x55, 0x00, 0x00, 0x01, 0x0A, CHECKSUM = 0x00 + 0x00 + 0x01 + 0x0A = 0x0B
        send_uart_byte(8'h55);
        send_uart_byte(8'h55);
        send_uart_byte(8'h55);
        send_uart_byte(8'h00);
        send_uart_byte(8'h00);
        send_uart_byte(8'h01);
        send_uart_byte(8'h0a);
        send_uart_byte(8'h0b); // checksum

        wait_cycles(BAUD_CYCLES * 5);

        if (led === 4'b1010) begin
            $display("[PASS] Step 2: LED successfully updated to 4'b1010!");
        end else begin
            $display("[FAIL] Step 2: Expected led=4'b1010, got %b", led);
            $finish;
        end

        $display("--- Step 3: Send Corrupted Checksum Packet (Should be rejected) ---");
        // 发送损坏校验和，LED 应当保持 4'b1010
        send_uart_byte(8'h55);
        send_uart_byte(8'h55);
        send_uart_byte(8'h55);
        send_uart_byte(8'h00);
        send_uart_byte(8'h00);
        send_uart_byte(8'h01);
        send_uart_byte(8'h0f); // 试图置为 0xF
        send_uart_byte(8'hEE); // 错误校验和 (正确应为 0x10)

        wait_cycles(BAUD_CYCLES * 5);

        if (led === 4'b1010) begin
            $display("[PASS] Step 3: Corrupted packet was correctly rejected! LED remained 4'b1010.");
        end else begin
            $display("[FAIL] Step 3: Corrupted packet was wrongly accepted! led=%b", led);
            $finish;
        end

        $display("==================================================");
        $display("ALL END-TO-END PROTOCOL TESTS PASSED SUCCESSFULLY!");
        $display("==================================================");
        $finish;
    end

endmodule
