module top (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire [3:0] key,
    output reg  [3:0] led,
    output wire [7:0] seg_led,
    output wire [5:0] seg_sel,
    input  wire       uart_rxd,
    output wire       uart_txd
);

    wire       tick_1s;
    wire       tick_20ms;
    wire       rdreq_sig;
    wire       wrreq_sig;
    wire       empty_sig;
    wire       full_sig;
    wire [7:0] fifo_w_sig;
    wire [7:0] fifo_q_sig;
    wire [5:0] usedw_sig;
    reg  [7:0] fifo_write_data;
    reg        rdreq_d1;
    wire [7:0] echo_data;
    wire       echo_valid;

    tick_gen #(
        .MAX_COUNT(50_000_000 - 1)  //1s
    ) u_tick_1s (
        .clk  (sys_clk),
        .rst_n(sys_rst_n),
        .tick (tick_1s)
    );

    tick_gen #(
        .MAX_COUNT(1_000_000 - 1)  //20ms
    ) u_tick_20ms (
        .clk  (sys_clk),
        .rst_n(sys_rst_n),
        .tick (tick_20ms)
    );

    // assign fifo_w_sig = fifo_write_data;

    // fifo_test u_fifo_test (
    //     .sys_clk  (sys_clk),
    //     .sys_rst_n(sys_rst_n),
    //     .rdreq_sig(rdreq_sig),
    //     .wrreq_sig(wrreq_sig),
    //     .empty_sig(empty_sig),
    //     .full_sig (full_sig),
    //     .w_sig    (fifo_w_sig),
    //     .q_sig    (fifo_q_sig),
    //     .usedw_sig(usedw_sig),
    //     .key      (key),
    //     .tick_20ms(tick_20ms)
    // );

    seg_led seg_led_inst (
        .clk     (sys_clk),
        .rst_n   (sys_rst_n),
        .add_flag(tick_1s),
        .seg_sel (seg_sel),
        .seg_led (seg_led)
    );

    // always @(posedge sys_clk or negedge sys_rst_n) begin
    //     if (!sys_rst_n) begin
    //         led             <= 4'b0000;
    //         fifo_write_data <= 8'h00;
    //         rdreq_d1        <= 1'b0;
    //     end else begin
    //         rdreq_d1 <= rdreq_sig;

    //         if (wrreq_sig) begin
    //             fifo_write_data <= fifo_write_data + 1'b1;
    //         end

    //         if (rdreq_d1) begin
    //             led <= fifo_q_sig[3:0];
    //         end
    //     end
    // end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            led <= 4'b0000;
        end else if (echo_valid) begin
            led <= echo_data[3:0];
        end
    end

    uart_echo_app u_uart_echo_app (
        .clk       (sys_clk),
        .rst_n     (sys_rst_n),
        .uart_rxd  (uart_rxd),
        .uart_txd  (uart_txd),
        .echo_data (echo_data),
        .echo_valid(echo_valid)
    );

endmodule
