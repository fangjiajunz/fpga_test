# Repository Guidelines

## 项目结构与模块组织

本仓库包含多个 Quartus Prime FPGA 工程，目标器件主要是 Intel Cyclone IV E `EP4CE10F17C8`。

- `uart/`：当前 UART 回显工程，采用分层结构：`rtl/top/` 负责板级连接，`rtl/app/` 放应用逻辑，`rtl/uart/` 放 UART 收发与封装，`rtl/timer/` 放 tick 发生器。
- `uart_fifo/`：基于 UART 工程扩展的 FIFO/IP 验证工程，IP 文件位于 `prj/ipcore/`。
- `_reg_led_move/`、`temp/`：示例或模板工程。
- 每个工程通常包含 `prj/`、`rtl/`、`sim/`、`doc/`、`tools/`。

设计时遵循高内聚、低耦合：协议模块只处理协议，应用模块处理业务，`top.v` 只做板级引脚连接和模块例化。

## 构建、测试与开发命令

在具体工程目录下执行脚本，例如进入 `uart/` 或 `uart_fifo/`：

- `tools\compile_download.bat`：编译并临时下载 `.sof` 到 FPGA。
- `powershell -ExecutionPolicy Bypass -File .\tools\compile_program_flash.ps1 -CompileOnly`：只编译工程。
- `powershell -ExecutionPolicy Bypass -File .\tools\compile_program_flash.ps1 -FlashDevice EPCS16 -SflDevice EP4CE10F17C8`：编译、生成 `.jic` 并固化 Flash。
- `tools\clean_project.bat`：清理 Quartus 生成文件。

本机 Quartus Prime Standard Edition 18.1 安装在 `D:\interfpga\Quartus`，命令行工具目录为 `D:\interfpga\Quartus\quartus\bin64`。ModelSim 目录为 `D:\interfpga\Modelsim\win64`。若 PATH 未刷新，可直接使用完整路径：

```powershell
D:\interfpga\Quartus\quartus\bin64\quartus_sh.exe --flow compile uart -c uart
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
