// =============================================================================
// 5. 接口模块 (at93c46_drive / spi_interface) - 底层驱动
// =============================================================================
module at93c46_drive (
    input               clk,        // 系统工作时钟
    input               rst_n,      // 系统异步复位，低电平有效

    // 面对内部命令模块
    input               ewen_en,    // 擦写使能操作脉冲
    input               write_en,   // 写操作脉冲
    input               read_en,    // 读操作脉冲
    input       [6:0]   addr_o,     // 操作地址
    input       [7:0]   wdata_o,    // 写数据
    output reg          rdy,        // 驱动空闲指示
    output reg  [7:0]   rdata,      // 读出的 8 位并行数据
    output reg          rdata_vld,  // 读数据有效指示

    // 面对外部 AT93C46 物理芯片引脚 (解决 do 关键字语法错误)
    output reg          cs,         // 芯片片选信号，高电平有效
    output reg          sk,         // 串行同步时钟（1 MHz）
    output reg          di,         // 串行数据输出（主出从入）
    input               spi_do      // 串行数据输入（修改为 spi_do，规避 SV 关键字）
);

endmodule
