`timescale 1ns / 1ps

module sdram_addr_map #(
    parameter integer BANK_WIDTH = 2,                                   // Bank 地址位宽 (4 个 Bank)
    parameter integer ROW_WIDTH  = 13,                                  // 行地址位宽 (8192 行)
    parameter integer COL_WIDTH  = 9,                                   // 列地址位宽 (512 列)
    parameter integer ADDR_WIDTH = BANK_WIDTH + ROW_WIDTH + COL_WIDTH  // 线性地址位宽 (24 位)
) (
    input  wire [ADDR_WIDTH-1:0] sys_addr,   // 连续线性输入地址

    output wire [BANK_WIDTH-1:0] bank_addr,  // 映射出的 Bank 地址 [1:0]
    output wire [ ROW_WIDTH-1:0] row_addr,   // 映射出的行地址 [12:0]
    output wire [ COL_WIDTH-1:0] col_addr    // 映射出的列地址 [8:0]
);

    // 地址切分映射:
    // sys_addr[23:22] -> Bank (2位)
    // sys_addr[21:9]  -> Row  (13位)
    // sys_addr[8:0]   -> Col  (9位)
    assign bank_addr = sys_addr[ADDR_WIDTH-1 : ROW_WIDTH + COL_WIDTH];
    assign row_addr  = sys_addr[ROW_WIDTH + COL_WIDTH - 1 : COL_WIDTH];
    assign col_addr  = sys_addr[COL_WIDTH - 1 : 0];

endmodule
