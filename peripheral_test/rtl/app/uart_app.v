module uart_app (
    input wire clk,
    input wire rst_n,

    // 协议解析层输入接口 (来自 decode)
    input wire        data_out_valid,
    input wire [ 7:0] data_out,
    input wire [16:0] data_out_addr,
    input wire [ 7:0] packet_type,
    input wire [16:0] packet_len,
    input wire        packet_done,
    input wire        packet_error,
    input wire        check_ok,

    // 物理 TX FIFO 发送接口 (去往 uart_core)
    output reg [7:0] tx_data,
    output reg       tx_wrreq,

    // Flash 控制接口
    output reg        flash_start,     // 启动 Flash 写入脉冲（指示地址和长度已就绪）
    output reg [16:0] flash_data_len,  // 实际写入 Flash 的数据总字节数 (packet_len - 4)
    output reg        flash_wr_en,     // 写入数据流使能脉冲
    output reg [ 7:0] flash_data,      // 写入数据
    output reg [23:0] flash_addr,      // Flash 24 位起始写入地址
    output reg        flash_check_ok,  // 发送/接收完毕且校验成功脉冲 (通知下游提交/固化)

    // 板载外设接口
    output reg  [3:0] led,
    input  wire [3:0] key
);

    reg [23:0] temp_adders;
    reg [ 3:0] temp_led;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            temp_adders    <= 24'd0;
            temp_led       <= 4'b0000;
            flash_start    <= 1'b0;
            flash_data_len <= 17'd0;
            flash_addr     <= 24'd0;
            flash_data     <= 8'd0;
            flash_wr_en    <= 1'b0;
            flash_check_ok <= 1'b0;
            led            <= 4'b0000;
            tx_data        <= 8'd0;
            tx_wrreq       <= 1'b0;
        end else begin
            // 脉冲信号默认拉低
            flash_wr_en    <= 1'b0;
            flash_start    <= 1'b0;
            flash_check_ok <= 1'b0;

            // =================================================================
            // 1. 数据接收与流式输出 (packet_type == 8'h01: Flash 数据包)
            // =================================================================
            if (data_out_valid && (packet_type == 8'h01)) begin
                case (data_out_addr)
                    17'd0: begin
                        // 预留字节或 Flash 操作子命令，可按需扩展
                    end
                    17'd1: begin
                        temp_adders[23:16] <= data_out;  // 地址高字节 [23:16]
                    end
                    17'd2: begin
                        temp_adders[15:8]  <= data_out;  // 地址中字节 [15:8]
                    end
                    17'd3: begin
                        temp_adders[7:0]   <= data_out;  // 地址低字节 [7:0]
                        // 拼接完整 24 位 Flash 写入起始地址
                        flash_addr         <= {temp_adders[23:8], data_out};
                        // 计算待写数据长度 (packet_len - 4)
                        flash_data_len     <= (packet_len >= 17'd4) ? (packet_len - 17'd4) : 17'd0;
                        flash_start        <= (packet_len > 17'd4);
                    end
                    default: begin
                        // 第 4 字节开始是实际待写入 Flash 的流式数据
                        flash_data  <= data_out;
                        flash_wr_en <= 1'b1;             // 产生一拍数据写入脉冲
                    end
                endcase
            end

            // 暂存 LED 控制数据 (packet_type == 8'h00)
            if (data_out_valid && (packet_type == 8'h00) && (data_out_addr == 17'd0)) begin
                temp_led <= data_out[3:0];
            end

            // =================================================================
            // 2. 整包接收完毕且校验通过处理 (Commit)
            // =================================================================
            if (packet_done && check_ok) begin
                if (packet_type == 8'h01) begin
                    flash_check_ok <= 1'b1;  // 发送完成且校验正确，给下游 Flash 模块发 check_ok 信号
                    led            <= 4'b0001;
                end else if (packet_type == 8'h00) begin
                    led            <= temp_led;
                end
            end
        end
    end

endmodule
