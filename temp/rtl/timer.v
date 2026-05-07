module timer (
    input  wire sys_clk,
    input  wire sys_rst_n,
    output reg  led_timer_flag,
    output reg  button_timer_flag
);

    parameter LED_MAX_COUNT = 50_000_000 - 1;
    parameter BUTTON_MAX_COUNT = 1_000_000 - 1;

    reg [25:0] tim_count;
    reg [25:0] button_count;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            tim_count      <= 26'd0;
            led_timer_flag <= 1'b0;
        end else if (tim_count == LED_MAX_COUNT) begin
            tim_count      <= 26'd0;
            led_timer_flag <= 1'b1;
        end else begin
            tim_count      <= tim_count + 1'b1;
            led_timer_flag <= 1'b0;
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            button_count      <= 26'd0;
            button_timer_flag <= 1'b0;
        end else if (button_count == BUTTON_MAX_COUNT) begin
            button_count      <= 26'd0;
            button_timer_flag <= 1'b1;
        end else begin
            button_count      <= button_count + 1'b1;
            button_timer_flag <= 1'b0;
        end
    end

endmodule
