# FPGA 模板工程

这是一个基于 Quartus Prime 的 Intel Cyclone IV E FPGA 模板工程。

## 目录说明

- `prj/` - Quartus 工程文件
- `rtl/` - 可综合 RTL 源码
- `sim/` - 仿真测试文件
- `doc/` - 开发板文档和引脚参考资料

## 快速开始

1. 运行 `tools/create_project_from_template.bat`，输入新的工程名。
2. 在生成的新工程中，用 Quartus Prime 打开 `prj/<project_name>.qpf`。
3. 在 `rtl/` 目录下替换或扩展你的 RTL 设计。
4. 在 `prj/<project_name>.qsf` 中启用并修改实际使用的引脚约束。
5. 在 `prj/system.sdc` 中修改实际的时序约束。

命令行示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\create_project_from_template.ps1 -ProjectName uart_led
```

## 工具入口

为了避免脚本越来越多，推荐统一从 `tools/fpga_tool.bat` 或 `tools/fpga_tool.ps1` 进入。

如果你不想记命令，也可以直接双击：

```text
tools\fpga_tool_menu.bat
```

它会弹出一个数字菜单，按编号选择：
- 编译
- 临时下载
- 固化烧录
- SOF 转 JIC
- 清理
- 查看下载线

示例：

```powershell
tools\fpga_tool.bat help
```

```powershell
tools\fpga_tool.bat download
```

```powershell
tools\fpga_tool.bat flash -FlashDevice EPCS16
```

```powershell
tools\fpga_tool.bat jic -SofPath .\prj\output_files\_reg_led_move.sof
```

```powershell
tools\fpga_tool.bat list-cables
```

建议约定：

- `download` 表示临时下载到 FPGA SRAM
- `flash` 表示固化烧录到配置 Flash
- `jic` 表示只做格式转换
- `clean` 表示清理工程生成文件

旧的脚本仍然保留，方便兼容，但后续日常使用优先走统一入口。

## SOF 转 JIC

使用 `tools/sof_to_jic.ps1` 可以把 `.sof` 文件转换为 `.jic` 文件。

也可以直接把 `.sof` 文件拖拽到 `tools/sof_to_jic.bat` 上。
如果没有拖入文件，则会自动弹出文件选择框。

示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\sof_to_jic.ps1
```

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\sof_to_jic.ps1 -SofPath .\prj\output_files\temp.sof
```

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\sof_to_jic.ps1 -SofPath .\prj\output_files\temp.sof -FlashDevice EPCS16
```

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\sof_to_jic.ps1 -SofPath .\prj\output_files\temp.sof -FlashDevice EPCS16 -SflDevice EP4CE10F17C8
```

拖拽使用方式：

```text
将 prj\output_files\temp.sof 拖到 tools\sof_to_jic.bat 上
```

如果系统环境变量 `PATH` 中没有 `quartus_cpf.exe`，可以通过 `-CpfPath` 显式指定路径。
如果脚本无法从 `.qsf` 中识别 FPGA 器件型号，可以通过 `-SflDevice` 显式指定。

## 编译并固化烧录

使用 `tools/compile_program_flash.ps1` 可以完成：

- 编译 Quartus 工程
- 将生成的 `.sof` 转换为 `.jic`
- 通过 JTAG 将 `.jic` 烧录到配置 Flash，实现掉电保存

脚本内部会使用 `quartus_pgm` 的 `ipv;<file>.jic` 操作串，先初始化并校验 Flash Loader，再执行固化烧录。

示例：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\compile_program_flash.ps1
```

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\compile_program_flash.ps1 -Cable "USB-Blaster"
```

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\compile_program_flash.ps1 -FlashDevice EPCS16 -SflDevice EP4CE10F17C8
```

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\compile_program_flash.ps1 -ProgramOnly -JicPath .\prj\output_files\_reg_led_move.jic
```

也可以直接运行：

```text
tools\compile_program_flash.bat
```

常用参数：

- `-CompileOnly` 只编译
- `-ConvertOnly` 只把 `.sof` 转成 `.jic`
- `-ProgramOnly` 只烧录已有 `.jic`
- `-ListCables` 列出当前可用下载线
- `-Cable` 指定下载线名称
- `-FlashDevice` 指定配置 Flash 型号
- `-SflDevice` 指定 FPGA 器件型号
- `-SkipDeviceCheck` 跳过烧录前的 JTAG 器件校验

## 模板说明

- 当前器件：`EP4CE10F17C8`
- 当前系列：`Cyclone IV E`
- 当前顶层实体：`temp`
- `db/`、`incremental_db/`、`output_files/` 等 Quartus 生成目录不应提交到版本库中。
