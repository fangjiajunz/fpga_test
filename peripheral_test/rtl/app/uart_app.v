// ==============================================================================
// 模块名称 : uart_app
// 模块功能 : 业务应用层 (Application Layer)
//   - 接收来自协议层 (decode) 的命令包，控制板载 LED
//   - 将协议层解出的有效数据流打入 TX FIFO 进行流式转发
//   - 响应板载按键，产生递增数据并通过 TX 发送 (与数据流完成仲裁)
// ==============================================================================

module uart_app (
    input wire clk,
    input wire rst_n,

    // 协议解析层输入接口 (来自 decode)
    input  wire        data_out_valid,
    input  wire [7:0]  data_out,
    input  wire [16:0] data_out_addr,
    input  wire [7:0]  packet_type,
    input  wire [16:0] packet_len,
    input  wire        packet_done,
    input  wire        packet_error,
    input  wire        check_ok,

    // 物理层 TX FIFO 发送接口 (去往 uart_core)
    output reg  [7:0]  tx_data,
    output reg         tx_wrreq,

    // 板载外设接口
    output reg  [3:0]  led,
    input  wire [3:0]  key
);

    // -------------------------------------------------------------------------
    // 1. 业务逻辑：根据命令包解码结果控制 LED
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
    // 2. 按键防抖检测
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
    // 3. 串口发送驱动：支持解码数据流转发与按键递增发送 (仲裁输出)
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
