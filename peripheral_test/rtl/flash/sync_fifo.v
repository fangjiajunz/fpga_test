// =============================================================================
// 通用参数化同步 FIFO (First-Word Fall-Through / FWFT 模式)
// 适用于至简设计法命令队列缓冲，读数据在 empty 为低时提前可见
// =============================================================================
module sync_fifo #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 4   // 默认深度 2^4 = 16
) (
    input  wire                  clk,
    input  wire                  rst_n,

    // 写端口
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] din,
    output wire                  full,

    // 读端口 (FWFT: dout 队首直通)
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] dout,
    output wire                  empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0]   wr_ptr;
    reg [ADDR_WIDTH:0]   rd_ptr;

    wire [ADDR_WIDTH:0] count = wr_ptr - rd_ptr;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);
    assign dout  = mem[rd_ptr[ADDR_WIDTH-1:0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {(ADDR_WIDTH+1){1'b0}};
            rd_ptr <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

endmodule
