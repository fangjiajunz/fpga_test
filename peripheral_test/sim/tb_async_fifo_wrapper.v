`timescale 1ns / 1ps

module tb_async_fifo_wrapper;

    // 仿真时钟与复位
    reg        rst_n;
    reg        wr_clk;
    reg        rd_clk;

    // 写端信号 (50MHz)
    reg         wr_en;
    reg  [15:0] wr_data;
    wire        wr_full;
    wire        wr_almost_full;
    wire [ 8:0] wr_usedw;
    wire        wr_burst_ready;
    wire        wr_rst_n;

    // 读端信号 (100MHz)
    reg         rd_en;
    wire [15:0] rd_data;
    wire        rd_empty;
    wire        rd_almost_empty;
    wire [ 8:0] rd_usedw;
    wire        rd_burst_ready;
    wire        rd_rst_n;

    // 实例化待测模块
    async_fifo_wrapper #(
        .DATA_WIDTH         (16),
        .FIFO_DEPTH         (512),
        .ADDR_WIDTH         (9),
        .BURST_LEN          (256),
        .ALMOST_FULL_THRESH (500),
        .ALMOST_EMPTY_THRESH(10)
    ) dut (
        .rst_n          (rst_n),
        .wr_clk         (wr_clk),
        .wr_rst_n       (wr_rst_n),
        .wr_en          (wr_en),
        .wr_data        (wr_data),
        .wr_full        (wr_full),
        .wr_almost_full (wr_almost_full),
        .wr_usedw       (wr_usedw),
        .wr_burst_ready (wr_burst_ready),

        .rd_clk         (rd_clk),
        .rd_rst_n       (rd_rst_n),
        .rd_en          (rd_en),
        .rd_data        (rd_data),
        .rd_empty       (rd_empty),
        .rd_almost_empty(rd_almost_empty),
        .rd_usedw       (rd_usedw),
        .rd_burst_ready (rd_burst_ready)
    );

    // 时钟生成：写时钟 50MHz (周期 20ns)，读时钟 100MHz (周期 10ns)
    initial begin
        wr_clk = 1'b0;
        forever #10 wr_clk = ~wr_clk;
    end

    initial begin
        rd_clk = 1'b0;
        forever #5 rd_clk = ~rd_clk;
    end

    integer i;
    reg [15:0] exp_data;
    integer err_cnt;

    initial begin
        rst_n    = 1'b0;
        wr_en    = 1'b0;
        wr_data  = 16'd0;
        rd_en    = 1'b0;
        exp_data = 16'd0;
        err_cnt  = 0;

        #100;
        rst_n = 1'b1;
        #100;

        $display("=== [TEST 1] 开始连续写入 256 个字 ===");
        @(posedge wr_clk);
        for (i = 0; i < 256; i = i + 1) begin
            wr_en   <= 1'b1;
            wr_data <= 16'h1000 + i;
            @(posedge wr_clk);
        end
        wr_en <= 1'b0;

        #200;
        $display("写入完成，当前 wr_usedw = %d, wr_burst_ready = %b", wr_usedw, wr_burst_ready);

        $display("=== [TEST 2] 开始从读端连续读出 256 个字并校验 ===");
        exp_data = 16'h1000;
        @(posedge rd_clk);
        for (i = 0; i < 256; i = i + 1) begin
            while (rd_empty) @(posedge rd_clk);
            
            // Show-ahead 模式：当前拍 rd_data 已有效
            if (rd_data !== exp_data) begin
                $display("ERROR: 索引 %d 数据不匹配！实际: 0x%h, 期望: 0x%h", i, rd_data, exp_data);
                err_cnt = err_cnt + 1;
            end
            rd_en    <= 1'b1;
            exp_data = exp_data + 1'b1;
            @(posedge rd_clk);
        end
        rd_en <= 1'b0;

        #200;
        if (err_cnt == 0) begin
            $display("=== SUCCESS: 异步 FIFO 读写校验全部通过！ ===");
        end else begin
            $display("=== FAILED: 存在 %0d 处错误！ ===", err_cnt);
        end

        #500;
        $finish;
    end

endmodule
