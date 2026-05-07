module top (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    input  wire [3:0] key,
    output reg  [3:0] led
);

    wire       tick_1s;
    wire       tick_20ms;
    wire [3:0] key_pulses;

    timer u_timer (
        .sys_clk          (sys_clk),
        .sys_rst_n        (sys_rst_n),
        .led_timer_flag   (tick_1s),
        .button_timer_flag(tick_20ms)
    );

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin : debounce_loop
            ax_debounce u_ax_debounce (
                .sys_clk   (sys_clk),
                .sys_rst_n (sys_rst_n),
                .btn_in    (key[i]),
                .timer_tick(tick_20ms),
                .btn_edge  (key_pulses[i])
            );
        end
    endgenerate

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            led <= 4'b0000;
        end else begin
            if (tick_1s) begin
                led[0] <= ~led[0];
            end

            if (key_pulses[1]) begin
                led[1] <= ~led[1];
            end

            if (key_pulses[2]) begin
                led[2] <= ~led[2];
            end

            if (key_pulses[3]) begin
                led[3] <= ~led[3];
            end
        end
    end

endmodule
