# Repository Guidelines

## 项目结构与模块组织

本仓库包含多个基于 Quartus Prime 的 Intel Cyclone IV E FPGA 工程：

文件中的工程都应该遵循高内聚低耦合的设计思想

- `uart/` 是当前主要的 UART 工程，RTL 按功能放在 `rtl/` 下，例如 `top/`、`uart/`、`timer/`、`key/`、`display/`。
- `_reg_led_move/` 和 `temp/` 是示例或模板工程，目录结构与 `uart/` 基本一致。
- `prj/` 保存 Quartus 工程文件（`.qpf`、`.qsf`）和时序约束 `system.sdc`。
- `sim/` 保存 Verilog 仿真测试文件，例如 `tb_top_uart_tx.v`。
- `doc/` 保存开发板引脚和硬件参考资料。
- `tools/` 保存编译、下载、固化、格式转换和清理脚本。

不要提交 Quartus 生成目录，例如 `db/`、`incremental_db/`、`output_files/`。

## 构建、测试与开发命令

在具体工程目录下执行命令，例如先进入 `uart/`。

- `tools\compile_download.bat`：编译工程，并将 `.sof` 临时下载到 FPGA SRAM。
- `powershell -ExecutionPolicy Bypass -File .\tools\compile_program_flash.ps1 -CompileOnly`：只执行 Quartus 编译。
- `powershell -ExecutionPolicy Bypass -File .\tools\compile_program_flash.ps1 -FlashDevice EPCS16 -SflDevice EP4CE10F17C8`：编译、生成 `.jic`，并固化到配置 Flash。
- `powershell -ExecutionPolicy Bypass -File .\tools\sof_to_jic.ps1 -SofPath .\prj\output_files\uart.sof`：将 `.sof` 转换为 `.jic`。
- `tools\clean_project.bat`：清理工程生成文件。

执行这些命令前，应确保 Quartus 命令行工具已安装并加入 `PATH`。
本机 Quartus Prime Standard Edition 18.1 安装在 `D:\interfpga\Quartus`，命令行工具位于 `D:\interfpga\Quartus\quartus\bin64`。如果未加入 `PATH`，可直接使用完整路径，例如：

```powershell
D:\interfpga\Quartus\quartus\bin64\quartus_sh.exe --flow compile uart -c uart
```

## 代码风格与命名规范

Verilog 代码使用 4 空格缩进。模块名使用小写加下划线，保持与 `uart_tx`、`uart_rx`、`seg_led`、`ax_debounce` 等现有命名一致。测试文件使用 `tb_` 前缀，例如 `tb_uart_rx.v`。尽量保持一个文件对应一个主要模块，文件名与模块名一致。

顶层集成逻辑放在 `rtl/top/top.v`；可复用逻辑放入对应功能目录。新增或移动 RTL 文件后，同步更新 `prj/*.qsf`；修改时钟或时序假设后，同步更新 `prj/system.sdc`。

## 测试指南

仿真测试放在各工程的 `sim/` 目录。新增模块或协议行为时，应补充有针对性的 testbench。提交 RTL 修改前，至少运行相关仿真和一次 Quartus 编译。涉及硬件引脚的修改，还应对照 `doc/` 中的开发板资料检查 `prj/*.qsf` 引脚约束。

## 提交与 Pull Request 规范

当前提交历史格式不完全统一，后续建议使用简洁的祈使句提交信息，例如 `feat: add uart echo test` 或 `fix: correct uart reset timing`。每个提交应聚焦一个设计或工具修改。

Pull Request 应包含简短说明、影响的工程路径、已完成的验证，以及使用的硬件环境，例如开发板型号、下载线、Flash 型号或串口波特率。综合、仿真或下载日志有助于说明问题时，应一并附上。
