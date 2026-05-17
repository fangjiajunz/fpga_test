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

## 模板说明

- 当前器件：`EP4CE10F17C8`
- 当前系列：`Cyclone IV E`
- 当前顶层实体：`temp`
- `db/`、`incremental_db/`、`output_files/` 等 Quartus 生成目录不应提交到版本库中。