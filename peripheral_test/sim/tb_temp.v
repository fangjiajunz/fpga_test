`timescale 1ns/1ps

module tb_temp;

    reg clk;
    reg rst_n;
    wire led;

    temp dut (
        .clk(clk),
        .rst_n(rst_n),
        .led(led)
    );

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        #100;
        rst_n = 1'b1;
        #2000;
        $stop;
    end

endmodule

