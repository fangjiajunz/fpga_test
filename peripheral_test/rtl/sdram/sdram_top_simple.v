
module sdram_top (
    input wire clk,
    input wire rst_n,

    // SDRAM 时钟与控制信号
    output wire sdram_clk,
    output wire sdram_cke,
    output wire sdram_cs_n,
    output wire sdram_ras_n,
    output wire sdram_cas_n,
    output wire sdram_we_n,

    // SDRAM 地址信号
    output wire [ 1:0] sdram_ba,
    output wire [12:0] sdram_addr,

    // SDRAM 数据及掩码
    inout  wire [15:0] sdram_dq,
    output wire [ 1:0] sdram_dqm
);

    // 在这里例化 SDRAM 控制器

endmodule
