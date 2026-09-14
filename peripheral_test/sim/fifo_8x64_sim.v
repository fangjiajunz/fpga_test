// 仿真专用的 fifo_8x64 行为模型。
//
// 综合时必须使用 prj/ipcore/fifo_ip/fifo_8x64.v（Intel scfifo，
// LPM_SHOWAHEAD="ON"、ADD_RAM_OUTPUT_REGISTER="OFF"），不要把这个文件加进 .qsf。
// iverilog 不认识 scfifo 原语，所以仿真时用本文件替代，两者端口完全一致，
// 时序语义也按 show-ahead 对齐：q 始终显示队首，rdreq 弹出后下一拍 q 变成新队首。
//
// 注意：模块名与 IP 相同，二者不能同时编译。

`timescale 1ns/1ps

module fifo_8x64 (
    input  wire       clock,
    input  wire [7:0] data,
    input  wire       rdreq,
    input  wire       sclr,
    input  wire       wrreq,
    output wire       empty,
    output wire       full,
    output wire [7:0] q,
    output wire [5:0] usedw
);

    localparam DEPTH = 64;
    localparam AW    = 6;

    reg [7:0]    mem [0:DEPTH-1];
    reg [AW:0]   cnt;    // 0 ~ 64，需要 7 位
    reg [AW-1:0] wptr;
    reg [AW-1:0] rptr;
    reg [7:0]    q_reg;

    wire do_wr = wrreq && !full;
    wire do_rd = rdreq && !empty;

    assign empty = (cnt == 0);
    assign full  = (cnt == DEPTH);
    assign usedw = cnt[AW-1:0];
    assign q     = q_reg;

    wire [AW:0] cnt_next = cnt + {6'd0, do_wr} - {6'd0, do_rd};

    always @(posedge clock) begin
        if (sclr) begin
            cnt   <= 7'd0;
            wptr  <= 6'd0;
            rptr  <= 6'd0;
            q_reg <= 8'h00;
        end else begin
            if (do_wr) begin
                mem[wptr] <= data;
                wptr      <= wptr + 1'b1;
            end
            if (do_rd) begin
                rptr <= rptr + 1'b1;
            end
            cnt <= cnt_next;

            // show-ahead：q 在 rdreq 之前就已经是队首
            if (do_rd) begin
                if (cnt == 7'd1) begin
                    // 弹出最后一个；若同一拍又写入，则新数据直接成为队首
                    q_reg <= do_wr ? data : 8'h00;
                end else begin
                    q_reg <= mem[rptr + 1'b1];
                end
            end else if (do_wr && empty) begin
                // 写入空 FIFO，队首立刻可见
                q_reg <= data;
            end
        end
    end

endmodule
