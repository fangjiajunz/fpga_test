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

    localparam FRAME_HEAD = 8'h5A;
    localparam FRAME_TAIL = 8'hA5;

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
    // -------------------------------------------------------------------------
    localparam STATE_IDLE = 2'd0;  // 等待帧头 5A
    localparam STATE_DATA = 2'd1;  // 暂存目标状态 XX
    localparam STATE_TAIL = 2'd2;  // 校验帧尾 A5

    reg [1:0] state;
    reg [3:0] temp_led;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= STATE_IDLE;
            temp_led <= 4'b0000;
            led      <= 4'b0000;
        end else if (rx_byte_valid) begin
            case (state)
                STATE_IDLE: begin
                    if (rx_byte == FRAME_HEAD) state <= STATE_DATA;
                end

                STATE_DATA: begin
                    temp_led <= rx_byte[3:0];  // 存下这 4 位的目标亮灭值
                    state    <= STATE_TAIL;
                end

                STATE_TAIL: begin
                    if (rx_byte == FRAME_TAIL) begin
                        led <= temp_led;  // 校验成功，直接直写生效！
                    end
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

    //tx
    wire tick_20ms;
    wire u_btn_edge;
    reg [7:0] _tx_data;

    tick_gen #(
        .MAX_COUNT(1_000_000 - 1)
    ) u_tick_1s (
        .clk  (clk),
        .rst_n(rst_n),
        .tick (tick_20ms)
    );
    //     input  wire sys_clk,
    // input  wire sys_rst_n,
    // input  wire btn_in,
    // input  wire timer_tick,
    // output reg  btn_edge
    ax_debounce u_ax_debounce (
        .sys_clk   (clk),
        .sys_rst_n (rst_n),
        .btn_in    (key[0]),
        .timer_tick(tick_20ms),
        .btn_edge  (u_btn_edge)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_data  <= 8'h00;  // 修正：8'h00
            tx_wrreq <= 1'b0;
        end else begin
            tx_wrreq <= 1'b0;  // 默认拉低，只产生 1 拍脉冲
            if (u_btn_edge) begin
                tx_data  <= tx_data + 1'b1;  // 数据递增
                tx_wrreq <= 1'b1;  // 修正：拉高 1 拍，写入 TX FIFO 发送
            end
        end
    end
endmodule
