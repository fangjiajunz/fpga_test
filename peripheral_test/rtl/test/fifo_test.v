module fifo_test (
    input  wire       sys_clk,
    input  wire       sys_rst_n,
    output wire       rdreq_sig,
    output wire       wrreq_sig,
    output wire       empty_sig,
    output wire       full_sig,
    input  wire [7:0] w_sig,
    output wire [7:0] q_sig,
    output wire [5:0] usedw_sig,
    input  wire [3:0] key,
    );

    // ----------------------------
    // FIFO 实例�?
    // ----------------------------
    fifo_8x64 fifo_inst (
        .clock(sys_clk),
        .data (w_sig),
        .rdreq(rdreq_sig),
        .wrreq(wrreq_sig),
        .empty(empty_sig),
        .full (full_sig),
        .q    (q_sig),
        .usedw(usedw_sig)
    );

    // ----------------------------
    // 按键去抖
    // ----------------------------
    wire [1:0] key_edge;

    ax_debounce u_key0_debounce (
        .sys_clk   (sys_clk),
        .sys_rst_n (sys_rst_n),
        .btn_in    (key[0]),      // 写按�?
                .btn_edge  (key_edge[0])
    );

    ax_debounce u_key1_debounce (
        .sys_clk   (sys_clk),
        .sys_rst_n (sys_rst_n),
        .btn_in    (key[1]),      // 读按�?
                .btn_edge  (key_edge[1])
    );

    // ----------------------------
    // 按键驱动 FIFO �?�?
    // ----------------------------
    reg wrreq_r, rdreq_r;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wrreq_r <= 1'b0;
            rdreq_r <= 1'b0;
        end else begin
            // ---------- 写请�?----------
            if (key_edge[0] && !full_sig) begin
                wrreq_r <= 1'b1;  // 按键触发�?
            end else begin
                wrreq_r <= 1'b0;  // 一拍写�?
            end

            // ---------- 读请�?----------
            if (key_edge[1] && !empty_sig) begin
                rdreq_r <= 1'b1;  // 按键触发�?
            end else begin
                rdreq_r <= 1'b0;  // 一拍读�?
            end
        end
    end

    // ----------------------------
    // 输出信号
    // ----------------------------
    assign wrreq_sig = wrreq_r;
    assign rdreq_sig = rdreq_r;

endmodule
