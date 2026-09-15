module led_ctrl_app (
    input wire clk,
    input wire rst_n,

    // 连接 uart_core 的 RX 接口。
    // 依赖 show-ahead 语义：rx_data 在 rdreq 之前就已经显示队首，所以
    // "读 rx_data"和"发 rdreq"可以在同一拍完成。uart_core 的 FIFO_SHOW_AHEAD
    // 参数必须为 1，否则这里读到的是过期数据。详见 rtl/uart/uart_core.v 顶部说明。
    input  wire [7:0] rx_data,
    input  wire       rx_empty,
    output reg        rx_rdreq,

    // 控制 LED
    output reg led
);

    // show-ahead FIFO 被 rdreq 弹出后，q 要到下一拍才变成新的队首；而 rx_rdreq
    // 又是寄存器输出，所以读完一个字节必须空一拍再读。少了这个间隔，队首字节会
    // 在 q 上多停留一拍，被连续执行两次。
    // uart_echo_app 的 ECHO_IDLE -> ECHO_SEND 也是同一个道理。
    localparam S_IDLE = 1'b0;
    localparam S_GAP = 1'b1;

    reg state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            rx_rdreq <= 1'b0;
            led      <= 1'b0;
        end else begin
            rx_rdreq <= 1'b0;  // 默认拉低，只产生 1 周期脉冲

            case (state)
                S_IDLE: begin
                    // 只要 RX FIFO 里有数据，就取出来执行
                    if (!rx_empty) begin
                        rx_rdreq <= 1'b1;  // 弹出当前字节

                        if (rx_data == 8'hAA) led <= ~led;  // 开灯
                        else if (rx_data == 8'h55) led <= 1'b0;  // 关灯

                        state <= S_GAP;
                    end
                end
                S_GAP: begin
                    state <= S_IDLE;  // 空一拍，等 q 更新成新的队首
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
