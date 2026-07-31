module flash_test_app (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tick_1s,

    // 请求 w25q16_ctrl
    output reg         flash_start,
    output wire [2:0]  flash_operation,
    output wire [23:0] flash_address,
    output wire [7:0]  flash_wr_data,

    // w25q16_ctrl 返回
    input  wire        flash_busy,
    input  wire        flash_done,
    input  wire        flash_error,
    input  wire [23:0] flash_id,

    // 调试结果：便于 SignalTap/ILA 观察
    output reg  [23:0] id_value,
    output reg         id_valid,
    output reg         test_error
);

    localparam [2:0] OP_READ_ID = 3'd0;

    reg request_issued;

    assign flash_operation = OP_READ_ID;
    assign flash_address   = 24'h000000;
    assign flash_wr_data   = 8'h00;

    // 上电等待第一个 1 秒脉冲，然后只读取一次 JEDEC ID。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flash_start   <= 1'b0;
            request_issued <= 1'b0;
            id_value      <= 24'h000000;
            id_valid      <= 1'b0;
            test_error    <= 1'b0;
        end else begin
            // flash_start 是单周期脉冲
            flash_start <= 1'b0;

            if (!request_issued && tick_1s && !flash_busy) begin
                flash_start    <= 1'b1;
                request_issued <= 1'b1;
            end

            if (flash_done) begin
                if (flash_error) begin
                    test_error <= 1'b1;
                end else begin
                    id_value <= flash_id;
                    id_valid <= 1'b1;
                end
            end
        end
    end

endmodule
