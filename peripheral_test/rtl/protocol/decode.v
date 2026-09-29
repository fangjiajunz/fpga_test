
module decode (
    // 时钟与全局复位
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    // 输入数据流 (标准流式接口，完全与底层存储介质解耦)
    input  wire [7:0]  in_data,
    input  wire        data_ready,

    // 数据流式输出接口 (命令与大数据均统一由此接口输出)
    output reg         data_out_valid,
    output reg  [7:0]  data_out,
    output reg  [16:0] data_out_addr,

    // 报文状态与标志
    output reg  [7:0]  packet_type,
    output reg  [16:0] packet_len,
    output reg         packet_done,
    output reg         packet_error,
    output reg         check_ok
);

    // ==========================================================================
    // 常量与参数定义
    // ==========================================================================
    // 协议特定常量
    localparam [7:0] SYNC_BYTE = 8'h55;  // 同步头字节
    localparam [1:0] SYNC_CNT_TARGET = 2'd2;  // 连续检测第3个(0,1,2)时完成同步
    localparam [7:0] PKT_TYPE_CMD = 8'h00;  // 命令包类型
    localparam [7:0] PKT_TYPE_DATA = 8'h01;  // 大数据包类型
    localparam [16:0] CMD_MAX_LEN = 17'd8;  // 命令包最大有效长度
    localparam [16:0] BIG_DATA_WRAP_LEN = 17'd65536;  // 长度字段为0时的实际长度(64KB)

    // 状态机状态编码
    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_TYPE = 4'd1;
    localparam [3:0] S_LEN_H = 4'd2;
    localparam [3:0] S_LEN_L = 4'd3;
    localparam [3:0] S_DATA = 4'd4;
    localparam [3:0] S_CHECK = 4'd5;
    localparam [3:0] S_DONE = 4'd6;
    localparam [3:0] S_ERROR = 4'd7;

    // ==========================================================================
    // 内部寄存器与信号定义
    // ==========================================================================
    reg  [ 3:0] current_state;
    reg  [ 3:0] next_state;

    reg  [ 1:0] begin_counter;  // 连续同步头计数器
    reg  [ 7:0] len_h;  // 报文长度高字节暂存
    reg  [16:0] data_cnt;  // 数据接收计数器
    reg  [ 7:0] check_sum;  // 校验和累加寄存器

    // 拼接 16 位长度信号，增强代码可读性
    wire [15:0] total_len_raw = {len_h, in_data};

    // ==========================================================================
    // 第一段：状态寄存器 (时序逻辑)
    // ==========================================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) current_state <= S_IDLE;
        else current_state <= next_state;
    end

    // ==========================================================================
    // 第二段：次态转移逻辑 (组合逻辑)
    // ==========================================================================
    always @(*) begin
        next_state = current_state;

        case (current_state)
            // 等待连续 3 个同步头 0x55
            S_IDLE: begin
                if (data_ready && (in_data == SYNC_BYTE) && (begin_counter == SYNC_CNT_TARGET)) next_state = S_TYPE;
            end

            // 接收并判定报文类型
            S_TYPE: begin
                if (data_ready) begin
                    if ((in_data == PKT_TYPE_CMD) || (in_data == PKT_TYPE_DATA)) next_state = S_LEN_H;
                    else next_state = S_ERROR;
                end
            end

            // 接收长度高字节
            S_LEN_H: begin
                if (data_ready) next_state = S_LEN_L;
            end

            // 接收长度低字节并检验合法性
            S_LEN_L: begin
                if (data_ready) begin
                    if (packet_type == PKT_TYPE_CMD) begin
                        if (total_len_raw <= CMD_MAX_LEN[15:0])
                            next_state = (total_len_raw == 16'd0) ? S_CHECK : S_DATA;
                        else next_state = S_ERROR;
                    end else if (packet_type == PKT_TYPE_DATA) begin
                        next_state = S_DATA;
                    end else begin
                        next_state = S_ERROR;
                    end
                end
            end

            // 接收数据段 (命令包与大数据包统一处理)
            S_DATA: begin
                if (data_ready && (data_cnt == packet_len - 1'b1)) next_state = S_CHECK;
            end

            // 校验和比对
            S_CHECK: begin
                if (data_ready) next_state = (in_data == check_sum) ? S_DONE : S_ERROR;
            end

            // 结束状态 (单周期脉冲后自动回到 IDLE)
            S_DONE: begin
                next_state = S_IDLE;
            end

            // 错误状态 (单周期脉冲后自动回到 IDLE)
            S_ERROR: begin
                next_state = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // ==========================================================================
    // 第三段：数据路径与输出寄存控制 (时序逻辑)
    // ==========================================================================
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            // 内部控制寄存器复位
            begin_counter  <= 2'd0;
            len_h          <= 8'd0;
            data_cnt       <= 17'd0;
            check_sum      <= 8'd0;

            // 报文信息复位
            packet_type    <= 8'd0;
            packet_len     <= 17'd0;

            // 单周期状态指示复位
            packet_done    <= 1'b0;
            packet_error   <= 1'b0;
            check_ok       <= 1'b0;

            // 数据流输出接口复位
            data_out_valid <= 1'b0;
            data_out       <= 8'd0;
            data_out_addr  <= 17'd0;
        end else begin
            // 单周期脉冲标志默认清零
            packet_done    <= 1'b0;
            packet_error   <= 1'b0;
            check_ok       <= 1'b0;
            data_out_valid <= 1'b0;

            case (current_state)
                // --------------------------------------------------------------
                // S_IDLE: 检索连续3个 0x55 同步头
                // --------------------------------------------------------------
                S_IDLE: begin
                    data_cnt  <= 17'd0;
                    check_sum <= 8'd0;

                    if (data_ready) begin
                        if (in_data == SYNC_BYTE) begin
                            if (begin_counter < SYNC_CNT_TARGET) begin_counter <= begin_counter + 1'b1;
                            else begin_counter <= 2'd0;
                        end else begin
                            begin_counter <= 2'd0;
                        end
                    end
                end

                // --------------------------------------------------------------
                // S_TYPE: 锁存类型并作为校验和初值
                // --------------------------------------------------------------
                S_TYPE: begin
                    begin_counter <= 2'd0;

                    if (data_ready) begin
                        packet_type <= in_data;
                        check_sum   <= in_data;  // 校验和从 TYPE 开始累加
                    end
                end

                // --------------------------------------------------------------
                // S_LEN_H: 锁存长度高字节并累加校验和
                // --------------------------------------------------------------
                S_LEN_H: begin
                    if (data_ready) begin
                        len_h     <= in_data;
                        check_sum <= check_sum + in_data;
                    end
                end

                // --------------------------------------------------------------
                // S_LEN_L: 解析包长度并累加校验和
                // --------------------------------------------------------------
                S_LEN_L: begin
                    if (data_ready) begin
                        data_cnt  <= 17'd0;
                        check_sum <= check_sum + in_data;

                        if (packet_type == PKT_TYPE_CMD) begin
                            packet_len <= {1'b0, total_len_raw};
                        end else if (packet_type == PKT_TYPE_DATA) begin
                            // 0x0000 规定代表 65536 字节
                            packet_len <= (total_len_raw == 16'h0000) ? BIG_DATA_WRAP_LEN : {1'b0, total_len_raw};
                        end
                    end
                end

                // --------------------------------------------------------------
                // S_DATA: 接收有效数据负载 (命令包与大数据包统一流式输出)
                // --------------------------------------------------------------
                S_DATA: begin
                    if (data_ready) begin
                        data_out_valid <= 1'b1;
                        data_out       <= in_data;
                        data_out_addr  <= data_cnt;

                        data_cnt       <= data_cnt + 1'b1;
                        check_sum      <= check_sum + in_data;
                    end
                end

                // --------------------------------------------------------------
                // S_CHECK: 校验结果判断
                // --------------------------------------------------------------
                S_CHECK: begin
                    // 仅等待组合逻辑判定后跳转到 S_DONE 或 S_ERROR
                end

                // --------------------------------------------------------------
                // S_DONE: 报文解析成功结束
                // --------------------------------------------------------------
                S_DONE: begin
                    packet_done <= 1'b1;
                    check_ok    <= 1'b1;  // 校验通过，与 packet_done 同一拍有效！
                    data_cnt    <= 17'd0;
                end

                // --------------------------------------------------------------
                // S_ERROR: 报文解析异常结束
                // --------------------------------------------------------------
                S_ERROR: begin
                    packet_error  <= 1'b1;
                    data_cnt      <= 17'd0;
                    begin_counter <= 2'd0;
                    check_sum     <= 8'd0;
                end

                default: begin
                    begin_counter <= 2'd0;
                end
            endcase
        end
    end

endmodule
