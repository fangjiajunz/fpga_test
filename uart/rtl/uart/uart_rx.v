module uart_rx #(
    parameter UART_BPS = 115200,
    parameter CLK_FREQ = 50_000_000
) (
    input wire sys_clk,    // 系统时钟 50MHz
    input wire sys_rst_n,  // 全局复位
    input wire rx,         // 串口接收数据引脚

    output reg [7:0] po_data,  // 串转并后的 8bit 完整数据
    output reg       out_flag  // 数据有效标志信号（脉冲）
);

    // 计算波特率计数最大值
    localparam BAUD_CNT_MAX = CLK_FREQ / UART_BPS;

    reg  [12:0] baud_cnt;
    wire        start_nedge;

    reg         work_en;  // 接收模块工作状态开关
    reg         bit_flag;  // 每一个波特率周期中间的“采样点”脉冲
    reg  [ 3:0] bit_cnt;  // 位计数器（0:起始位, 1~8:数据位, 9:停止位）
    reg  [ 7:0] data_reg;  // 内部数据移位寄存器

    reg         _rx_reg_1;
    reg         _rx_reg_2;
    reg         _rx_reg_3;

    // ======================================================
    // 1. 打拍消除亚稳态 & 提取起始位下降沿
    // ======================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            _rx_reg_1 <= 1'b1;  // 复位时 UART 空闲为高电平
            _rx_reg_2 <= 1'b1;
            _rx_reg_3 <= 1'b1;
        end else begin
            _rx_reg_1 <= rx;
            _rx_reg_2 <= _rx_reg_1;
            _rx_reg_3 <= _rx_reg_2;
        end
    end

    // 当上一拍是 1，且当前拍变成 0 时，说明出现了起始位的下降沿
    assign start_nedge = _rx_reg_3 & ~_rx_reg_2;

    // ======================================================
    // 2. 接收使能控制 (work_en)
    // ======================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            work_en <= 1'b0;
        end else if (start_nedge && !work_en) begin
            work_en <= 1'b1;  // 抓到起始沿，开始干活
        end else if (bit_flag && (bit_cnt == 4'd9)) begin
            work_en <= 1'b0;  // 采样完第 9 位（停止位）后，打卡下班，回到空闲
        end
    end

    // ======================================================
    // 3. 波特率计数器 (baud_cnt)
    // ======================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            baud_cnt <= 13'd0;
        end else if (work_en) begin
            if (baud_cnt == BAUD_CNT_MAX - 1) begin
                baud_cnt <= 13'd0;
            end else begin
                baud_cnt <= baud_cnt + 1'b1;
            end
        end else begin
            baud_cnt <= 13'd0;  // 不工作时保持清零
        end
    end

    // ======================================================
    // 4. 数据采样点标志 (bit_flag) - 在每个数据位的正中间采样
    // ======================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            bit_flag <= 1'b0;
        end else if (baud_cnt == BAUD_CNT_MAX / 2 - 1) begin
            bit_flag <= 1'b1;
        end else begin
            bit_flag <= 1'b0;
        end
    end

    // ======================================================
    // 5. 位计数 (bit_cnt) 与 数据移位 (data_reg)
    // ======================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            data_reg <= 8'b0;
            bit_cnt  <= 4'd0;
        end else if (work_en) begin
            if (bit_flag) begin  // 只有在采样点才做事情

                // 计数逻辑：0到9循环
                if (bit_cnt == 4'd9) begin
                    bit_cnt <= 4'd0;
                end else begin
                    bit_cnt <= bit_cnt + 1'b1;
                end

                // 移位逻辑：
                // bit_cnt == 0 时，采样的是起始位，丢弃不存。
                // bit_cnt == 1~8 时，采样的是数据位，存入移位寄存器。
                if (bit_cnt >= 4'd1 && bit_cnt <= 4'd8) begin
                    // UART是低位先发(LSB First)，所以新来的数据放最高位，原来的右移
                    data_reg <= {_rx_reg_3, data_reg[7:1]};
                end
            end
        end else begin
            bit_cnt <= 4'd0;  // 不工作时计数器清零，但 data_reg 保持不变，留给输出
        end
    end

    // ======================================================
    // 6. 数据输出与完成标志 (po_data & out_flag)
    // ======================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            po_data  <= 8'b0;
            out_flag <= 1'b0;
        end else if (bit_flag && (bit_cnt == 4'd9)) begin
            // 当到达停止位的采样点时，前8个数据位早就稳稳地存在 data_reg 里了
            po_data  <= data_reg;  // 把内部寄存器的数据扔给外部引脚
            out_flag <= 1'b1;  // 拉高一个时钟周期，通知外部“有新数据啦！”
        end else begin
            out_flag <= 1'b0;
        end
    end

endmodule
