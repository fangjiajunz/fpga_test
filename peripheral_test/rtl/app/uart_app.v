module uart_app (
    input wire clk,
    input wire rst_n,

    // 连接 uart_core RX FIFO 接口
    input  wire [7:0] rx_data,
    input  wire       rx_empty,
    output reg        rx_rdreq,

    // 连接 uart_core TX FIFO 接口
    output reg  [7:0] tx_data,
    output reg        tx_wrreq,

    // 4 位 LED 输出
    output reg  [3:0] led,
    input  wire [3:0] key
);

    // -------------------------------------------------------------------------
    // 1. FIFO 读驱动：解耦 show-ahead 延迟
    // -------------------------------------------------------------------------
    reg [7:0] rx_byte;
    reg       rx_byte_valid;
    reg       read_gap;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_rdreq      <= 1'b0;
            rx_byte       <= 8'h00;
            rx_byte_valid <= 1'b0;
            read_gap      <= 1'b0;
        end else begin
            rx_rdreq      <= 1'b0;
            rx_byte_valid <= 1'b0;

            if (read_gap) begin
                read_gap <= 1'b0;
            end else if (!rx_empty) begin
                rx_rdreq      <= 1'b1;
                rx_byte       <= rx_data;
                rx_byte_valid <= 1'b1;
                read_gap      <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 2. 协议解码模块例化与信号声明
    // -------------------------------------------------------------------------
    wire        data_out_valid;
    wire [7:0]  data_out;
    wire [16:0] data_out_addr;
    wire [7:0]  packet_type;
    wire [16:0] packet_len;
    wire        packet_done;
    wire        packet_error;
    wire        check_ok;

    decode u_decode (
        .sys_clk       (clk),
        .sys_rst_n     (rst_n),
        .in_data       (rx_byte),
        .data_ready    (rx_byte_valid),
        .data_out_valid(data_out_valid),
        .data_out      (data_out),
        .data_out_addr (data_out_addr),
        .packet_type   (packet_type),
        .packet_len    (packet_len),
        .packet_done   (packet_done),
        .packet_error  (packet_error),
        .check_ok      (check_ok)
    );

    // -------------------------------------------------------------------------
    // 3. 业务逻辑：根据命令包解码结果控制 LED
    // -------------------------------------------------------------------------
    reg [3:0] temp_led;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            temp_led <= 4'b0000;
            led      <= 4'b0000;
        end else begin
            // 收到命令包 (TYPE=0x00) 的第 0 字节时，暂存 LED 目标值
            if (data_out_valid && (packet_type == 8'h00) && (data_out_addr == 17'd0)) begin
                temp_led <= data_out[3:0];
            end

            // 整包接收完毕且校验通过时，将目标值正式更新到 LED
            if (packet_done && check_ok && (packet_type == 8'h00)) begin
                led <= temp_led;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 4. 按键防抖检测
    // -------------------------------------------------------------------------
    wire tick_20ms;
    wire u_btn_edge;

    tick_gen #(
        .MAX_COUNT(26'd999_999)  // 50MHz 时钟下产生 20ms 定时脉冲
    ) u_tick_20ms (
        .clk  (clk),
        .rst_n(rst_n),
        .tick (tick_20ms)
    );

    ax_debounce u_ax_debounce (
        .sys_clk   (clk),
        .sys_rst_n (rst_n),
        .btn_in    (key[0]),
        .timer_tick(tick_20ms),
        .btn_edge  (u_btn_edge)
    );

    // -------------------------------------------------------------------------
    // 5. 串口发送驱动：支持解码数据流转发与按键递增发送 (仲裁输出)
    // -------------------------------------------------------------------------
    reg [7:0] btn_tx_cnt;
    reg       btn_tx_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_data        <= 8'h00;
            tx_wrreq       <= 1'b0;
            btn_tx_cnt     <= 8'h00;
            btn_tx_pending <= 1'b0;
        end else begin
            tx_wrreq <= 1'b0;  // 默认拉低

            // 按键按下时使发送计数值累加，并标记有待发送按键事件
            if (u_btn_edge) begin
                btn_tx_cnt     <= btn_tx_cnt + 1'b1;
                btn_tx_pending <= 1'b1;
            end

            // 发送通道仲裁：解码数据优先流式发出；空闲时处理按键发送
            if (data_out_valid) begin
                tx_data  <= data_out;
                tx_wrreq <= 1'b1;
            end else if (btn_tx_pending) begin
                tx_data        <= btn_tx_cnt;
                tx_wrreq       <= 1'b1;
                btn_tx_pending <= 1'b0;
            end
        end
    end

endmodule
