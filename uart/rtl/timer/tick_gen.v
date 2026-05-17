module tick_gen #(
    parameter MAX_COUNT = 50_000_000 - 1
) (
    input  wire clk,
    input  wire rst_n,
    output reg  tick
);

    reg [25:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt  <= 26'd0;
            tick <= 1'b0;
        end else if (cnt == MAX_COUNT) begin
            cnt  <= 26'd0;
            tick <= 1'b1;
        end else begin
            cnt  <= cnt + 1'b1;
            tick <= 1'b0;
        end
    end

endmodule
