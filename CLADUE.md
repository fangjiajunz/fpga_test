# Repository Guidelines

## 项目结构与模块组织

本仓库当前只有一个 Quartus Prime FPGA 工程 `peripheral_test/`，目标器件是 Intel Cyclone IV E `EP4CE10F17C8`。

- `peripheral_test/prj/`：Quartus 工程文件（`peripheral_test.qpf`、`peripheral_test.qsf`、`system.sdc`）与 IP（`ipcore/fifo_ip`、`ipcore/rom`）。
- `peripheral_test/rtl/`：按外设/功能分目录的 RTL。
  - `top/`：`top.v`，只做板级引脚连接和模块例化。
  - `app/`：应用逻辑，如 `uart_echo_app.v`。
  - `uart/`：UART 收发与封装，`uart_core.v`、`uart_tx.v`、`uart_rx.v`。
  - `spi/spi_phy/`：SPI 物理层与主控，`spi_phy.v`、`spi_master_top.v`。
  - `lcd/`：LCD 驱动与显示，`lcd_driver.v`、`lcd_top.v`、`lcd_colorbar.v`、`clk_div.v` 等。
  - `timer/`：`timer.v`、`tick_gen.v`。
  - `key/`：按键消抖 `ax_debounce.v`。
  - `display/`：数码管 `seg_led.v`。
  - `test/`：验证用模块，如 `fifo_test.v`。
- `peripheral_test/sim/`：测试平台，`tb_top_uart_tx.v`、`tb_temp.v`。
- `peripheral_test/tools/`：编译、下载、固化、清理、建工程脚本。
- `peripheral_test/doc/`：开发板 IO 引脚分配表等硬件资料。

新增工程时沿用相同布局：`prj/`、`rtl/`、`sim/`、`doc/`、`tools/`。

设计时遵循高内聚、低耦合：协议模块只处理协议，应用模块处理业务，`top.v` 只做板级引脚连接和模块例化。

## 构建、测试与开发命令

在工程目录 `peripheral_test/` 下执行脚本：

- `tools\compile_download.bat`：编译并临时下载 `.sof` 到 FPGA。
- `powershell -ExecutionPolicy Bypass -File .\tools\compile_program_flash.ps1 -CompileOnly`：只编译工程。
- `powershell -ExecutionPolicy Bypass -File .\tools\compile_program_flash.ps1 -FlashDevice EPCS16 -SflDevice EP4CE10F17C8`：编译、生成 `.jic` 并固化 Flash。
- `tools\clean_project.bat`：清理 Quartus 生成文件。

Quartus Prime Standard Edition 18.1 的安装路径在不同开发机上不一致，已知两套环境：

| 环境 | Quartus 命令行工具目录 | ModelSim 目录 |
| --- | --- | --- |
| 机器 A | `D:\interfpga\Quartus\quartus\bin64` | `D:\interfpga\Modelsim\win64` |
| 机器 B | `D:\intelFPGA\18.1\quartus\bin64` | `D:\intelFPGA\modusim\win64` |

`tools/` 下的脚本会按「PATH → 卸载注册表 InstallLocation → 常见安装根目录（含递归查找）」的顺序自动定位工具，两套环境都能命中，因此正常情况下无需手工指定路径。若探测失败，用脚本的显式路径参数（如 `-CpfPath`）覆盖。

需要手工调用命令行工具时，先确认本机实际路径，不要照抄下面的示例：

```powershell
# 机器 B 示例
D:\intelFPGA\18.1\quartus\bin64\quartus_sh.exe --flow compile peripheral_test -c peripheral_test
```

## 代码风格与命名规范

文件中的工程都应该遵循高内聚低耦合的设计思想

Verilog 使用 4 空格缩进。模块名和文件名使用小写加下划线，例如 `uart_core.v`、`tick_gen.v`、`ax_debounce.v`。一个文件尽量只放一个主要模块。测试文件使用 `tb_` 前缀。

通用模块应参数化，例如 `CLK_FREQ`、`UART_BPS`、`MAX_COUNT`，避免把板级参数写死在协议模块内部。

## IP 与工程生成规则

Quartus IP 不要只复制 `.v` 文件；应保留 `.qip` 及其关联文件。创建新工程的 `tools/create_project_from_template.ps1` 应保留 `ip/`、`ipcore/`、`prj/ip/`、`prj/ipcore/`，且不应自动执行 `git init`。

不要提交 Quartus 生成目录，例如 `db/`、`incremental_db/`、`output_files/`、`simulation/modelsim/`。

## 测试指南

提交 RTL 修改前，至少运行相关仿真或 Quartus 编译。UART 顶层回显测试在 `sim/tb_top_uart_tx.v`。FIFO IP 为同步 `scfifo` 时，读写共用 `clock`；若 `show-ahead = OFF`，读请求后一拍再使用 `q` 数据。

## 提交规范

提交信息使用中文，保持简洁、聚焦，例如 `重构 UART 工程分层`、`添加 FIFO 工程`。PR 或提交说明应包含影响的工程路径、验证命令和关键硬件环境。
