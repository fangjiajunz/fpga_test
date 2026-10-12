`timescale 1ns / 1ps

module sdram_phy (
    input  wire        clk,
    input  wire        rst_n,

    // 来自仲裁器的控制与数据信号
    input  wire [ 3:0] phy_cmd,         // {cs_n, ras_n, cas_n, we_n}
    input  wire [12:0] phy_addr,
    input  wire [ 1:0] phy_ba,
    input  wire        phy_cke,
    input  wire [ 1:0] phy_dqm,
    input  wire        phy_data_out_en, // 三态输出使能: 1 为写输出, 0 为高阻输入

    // 内部写/读数据流
    input  wire [15:0] wr_data,         // 待写入 SDRAM 的数据
    output wire [15:0] rd_data,         // 从 SDRAM 读出的数据

    // 外部 SDRAM 芯片物理引脚
    output wire        sdram_cke,
    output wire        sdram_cs_n,
    output wire        sdram_ras_n,
    output wire        sdram_cas_n,
    output wire        sdram_we_n,
    output wire [ 1:0] sdram_ba,
    output wire [12:0] sdram_addr,
    output wire [ 1:0] sdram_dqm,
    inout  wire [15:0] sdram_data
);

    reg [15:0] wr_data_r;

    // 控制命令与引脚直连
    assign {sdram_cs_n, sdram_ras_n, sdram_cas_n, sdram_we_n} = phy_cmd;
    assign sdram_addr = phy_addr;
    assign sdram_ba   = phy_ba;
    assign sdram_cke  = phy_cke;
    assign sdram_dqm  = phy_dqm;

    // 写数据同步寄存
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wr_data_r <= 16'd0;
        else
            wr_data_r <= wr_data;
    end

    // 物理三态双向数据缓冲
    assign sdram_data = phy_data_out_en ? wr_data_r : 16'hzzzz;

    // 读数据直接采样物理总线
    assign rd_data = sdram_data;

endmodule
