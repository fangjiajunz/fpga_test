module my_sdram_user_app (
    input wire clk,   // 必须接 100MHz ref_clk
    input wire rst_n, // 同步复位

    // 用户操作触发信号
    input wire        do_write_trig,  // 触发一次写
    input wire        do_read_trig,   // 触发一次读
    input wire [23:0] target_addr,    // 目标地址
    input wire [ 9:0] target_len,     // 读写长度 (如 10'd4, 10'd256)

    // 直连 sdram_top 接口
    input wire        init_done,
    input wire        rw_busy,
    input wire        rw_done,
    input wire        wr_ack,
    input wire        rd_ack,
    input wire [15:0] rd_data,

    output reg         wr_req,
    output reg         rd_req,
    output reg  [23:0] wr_addr,
    output reg  [23:0] rd_addr,
    output wire [ 9:0] wr_len,
    output wire [ 9:0] rd_len,
    output reg  [15:0] wr_data
);

    assign wr_len = target_len;
    assign rd_len = target_len;

    localparam S_IDLE = 3'd0;
    localparam S_WRITE_REQ = 3'd1;
    localparam S_WRITE_DATA = 3'd2;
    localparam S_READ_REQ = 3'd3;
    localparam S_READ_DATA = 3'd4;
    localparam S_DONE = 3'd5;

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            wr_req  <= 1'b0;
            rd_req  <= 1'b0;
            wr_addr <= 24'd0;
            rd_addr <= 24'd0;
            wr_data <= 16'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    wr_req <= 1'b0;
                    rd_req <= 1'b0;
                    if (init_done && !rw_busy) begin
                        if (do_write_trig) begin
                            wr_req  <= 1'b1;
                            wr_addr <= target_addr;
                            wr_data <= 16'h1111;  // 提前准备第 1 个要写的数据
                            state   <= S_WRITE_REQ;
                        end else if (do_read_trig) begin
                            rd_req  <= 1'b1;
                            rd_addr <= target_addr;
                            state   <= S_READ_REQ;
                        end
                    end
                end

                // ── 写分支 ──
                S_WRITE_REQ: begin
                    // 控制器已受理则撤销 wr_req
                    if (rw_busy || wr_ack) begin
                        wr_req <= 1'b0;
                        state  <= S_WRITE_DATA;
                    end
                end

                S_WRITE_DATA: begin
                    // 每逢 wr_ack 送出下一个数据
                    if (wr_ack) begin
                        wr_data <= wr_data + 1'b1;  // 送出 D1, D2 ...
                    end
                    // 等待整个突发完成
                    if (rw_done) begin
                        state <= S_DONE;
                    end
                end

                // ── 读分支 ──
                S_READ_REQ: begin
                    if (rw_busy || rd_ack) begin
                        rd_req <= 1'b0;
                        state  <= S_READ_DATA;
                    end
                end

                S_READ_DATA: begin
                    // 当 rd_ack 为高时采样有效数据
                    if (rd_ack) begin
                        // 在此锁存或消费 rd_data
                    end
                    if (rw_done) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
