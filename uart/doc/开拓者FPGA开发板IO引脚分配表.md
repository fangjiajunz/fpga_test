# 开拓者FPGA开发板IO引脚分配表

> ?????`开拓者FPGA开发板IO引脚分配表.xlsx`

## 系统时钟（50MHz）

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| sys_clk | input | M2 | 系统时钟，频率：50MHz |

## 系统复位（RESET）

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| sys_rst_n | input | M1 | 系统复位，低电平有效 |

## 4个按键

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| key[0] | input | E16 | 按键KEY0 |
| key[1] | input | E15 | 按键KEY1 |
| key[2] | input | M15 | 按键KEY2 |
| key[3] | input | M16 | 按键KEY3 |

## 4个LED灯

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| led[0] | output | D11 | LED0 |
| led[1] | output | C11 | LED1 |
| led[2] | output | E10 | LED2 |
| led[3] | output | F9 | LED3 |

## 触摸按键

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| touch_key | input | F8 | 触摸按键 |

## 蜂鸣器

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| beep | output | D12 | 蜂鸣器 |

## EPCS(W25Q16)

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| epcs_flash_data0 | input | H2 | EPCS SPI输入数据 |
| epcs_flash_dclk | output | H1 | EPCS SPI时钟 |
| epcs_flash_sce | input | D2 | EPCS SPI片选信号 |
| epcs_flash_sdo | output | C1 | EPCS SPI输出数据 |

## 6位数码管

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| seg_sel[0] | output | N16 | 第一个数码管位选信号 |
| seg_sel[1] | output | N15 | 第二个数码管位选信号 |
| seg_sel[2] | output | P16 | 第三个数码管位选信号 |
| seg_sel[3] | output | P15 | 第四个数码管位选信号 |
| seg_sel[4] | output | R16 | 第五个数码管位选信号 |
| seg_sel[5] | output | T15 | 第六个数码管位选信号 |
| seg_led[0] | output | M11 | 数码管段选a |
| seg_led[1] | output | N12 | 数码管段选b |
| seg_led[2] | output | C9 | 数码管段选c |
| seg_led[3] | output | N13 | 数码管段选d |
| seg_led[4] | output | M10 | 数码管段选e |
| seg_led[5] | output | N11 | 数码管段选f |
| seg_led[6] | output | P11 | 数码管段选g |
| seg_led[7] | output | D9 | 数码管段选h |

## USB串口

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| uart_rxd | input | N5 | USB串口接收 |
| uart_txd | output | M7 | USB串口发送 |

## RS232串口

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| uart_rxd | input | B8 | RS232串口接收 |
| uart_txd | output | C3 | RS232串口发送 |

## RS485串口

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| rs485_uart_rxd | input | B8 | RS485串口接收 |
| rs485_uart_txd | output | C3 | RS485串口发送 |

## HDMI接口

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| tmds_data_p [0] | output | B11 | TMDS 数据通道0（正极） |
| tmds_data_n [0] | output | A11 | TMDS 数据通道0（负极） |
| tmds_data_p [1] | output | B10 | TMDS 数据通道1（正极） |
| tmds_data_n [1] | output | A10 | TMDS 数据通道1（负极） |
| tmds_data_p [2] | output | B9 | TMDS 数据通道2（正极） |
| tmds_data_n [2] | output | A9 | TMDS 数据通道2（负极） |
| tmds_clk_p | output | B12 | TMDS 时钟通道（正极） |
| tmds_clk_n | output | A12 | TMDS 时钟通道（负极） |

## RGB TFT-LCD接口

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| lcd_de | output | T2 | RGB LCD数据使能 |
| lcd_hs | output | T3 | RGB LCD行同步 |
| lcd_vs | output | P3 | RGB LCD场同步 |
| lcd_pclk | output | R3 | RGB LCD像素时钟 |
| lcd_bl | output | R1 | RGB LCD背光控制 |
| lcd_rst | output | L1 | RGB LCD系统复位，低有效 |
| lcd_rgb[0] | output | T6 | RGB LCD蓝色 |
| lcd_rgb[1] | output | R5 | RGB LCD蓝色 |
| lcd_rgb[2] | output | T5 | RGB LCD蓝色 |
| lcd_rgb[3] | output | R4 | RGB LCD蓝色 |
| lcd_rgb[4] | output | T4 | RGB LCD蓝色 |
| lcd_rgb[5] | output | T9 | RGB LCD绿色 |
| lcd_rgb[6] | output | R8 | RGB LCD绿色 |
| lcd_rgb[7] | output | T8 | RGB LCD绿色 |
| lcd_rgb[8] | output | R7 | RGB LCD绿色 |
| lcd_rgb[9] | output | T7 | RGB LCD绿色 |
| lcd_rgb[10] | output | R6 | RGB LCD绿色 |
| lcd_rgb[11] | output | R11 | RGB LCD红色 |
| lcd_rgb[12] | output | T11 | RGB LCD红色 |
| lcd_rgb[13] | output | R10 | RGB LCD红色 |
| lcd_rgb[14] | output | T10 | RGB LCD红色 |
| lcd_rgb[15] | output | R9 | RGB LCD红色 |

## 红外遥控

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| remote_in | input | L8 | 红外接收信号 |

## 单总线（DS18B20/DHT11）

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| dq | inout | F10 | 单总线 |

## IIC总线（EEPROM/环境光传感器/RTC实时时钟/音频配置）

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| iic_scl | output | D8 | IIC时钟信号线 |
| iic_sda | inout | C8 | IIC双向数据线 |

## AD/DA

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| adda_scl | output | E9 | ADDA IIC时钟信号线 |
| adda_sda | inout | E8 | ADDA IIC双向数据线 |

## 音频（ES8388）

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| aud_scl | output | D8 | ES8388的IIC配置时钟线 |
| aud_sda | inout | C8 | ES8388的IIC配置数据线 |
| aud_mclk | output | E7 | ES8388的主时钟 |
| aud_bclk | input | B13 | ES8388的位时钟 |
| aud_lrc | input | A13 | ES8388的对齐时钟 |
| aud_adcdat | input | C6 | ES8388的ADC数据线 |
| aud_dacdat | output | D6 | ES8388的DAC数据线 |

## SDRAM

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| sdram_clk | output | B14 | SDRAM 芯片时钟 |
| sdram_cke | output | F16 | SDRAM 时钟有效 |
| sdram_cs_n | output | K10 | SDRAM 片选 |
| sdram_ras_n | output | K11 | SDRAM 行有效 |
| sdram_cas_n | output | J12 | SDRAM 列有效 |
| sdram_we_n | output | J13 | SDRAM 写有效 |
| sdram_ba[0] | output | G11 | SDRAM Bank地址 |
| sdram_ba[1] | output | F13 | SDRAM Bank地址 |
| sdram_dqm[0] | output | J14 | SDRAM 数据掩码 |
| sdram_dqm[1] | output | G15 | SDRAM 数据掩码 |
| sdram_addr[0] | output | F11 | SDRAM 行/列地址 |
| sdram_addr[1] | output | E11 | SDRAM 行/列地址 |
| sdram_addr[2] | output | D14 | SDRAM 行/列地址 |
| sdram_addr[3] | output | C14 | SDRAM 行/列地址 |
| sdram_addr[4] | output | A14 | SDRAM 行/列地址 |
| sdram_addr[5] | output | A15 | SDRAM 行/列地址 |
| sdram_addr[6] | output | B16 | SDRAM 行/列地址 |
| sdram_addr[7] | output | C15 | SDRAM 行/列地址 |
| sdram_addr[8] | output | C16 | SDRAM 行/列地址 |
| sdram_addr[9] | output | D15 | SDRAM 行/列地址 |
| sdram_addr[10] | output | F14 | SDRAM 行/列地址 |
| sdram_addr[11] | output | D16 | SDRAM 行/列地址 |
| sdram_addr[12] | output | F15 | SDRAM 行/列地址 |
| sdram_data[0] | inout | P14 | SDRAM 数据 |
| sdram_data[1] | inout | M12 | SDRAM 数据 |
| sdram_data[2] | inout | N14 | SDRAM 数据 |
| sdram_data[3] | inout | L12 | SDRAM 数据 |
| sdram_data[4] | inout | L13 | SDRAM 数据 |
| sdram_data[5] | inout | L14 | SDRAM 数据 |
| sdram_data[6] | inout | L11 | SDRAM 数据 |
| sdram_data[7] | inout | K12 | SDRAM 数据 |
| sdram_data[8] | inout | G16 | SDRAM 数据 |
| sdram_data[9] | inout | J11 | SDRAM 数据 |
| sdram_data[10] | inout | J16 | SDRAM 数据 |
| sdram_data[11] | inout | J15 | SDRAM 数据 |
| sdram_data[12] | inout | K16 | SDRAM 数据 |
| sdram_data[13] | inout | K15 | SDRAM 数据 |
| sdram_data[14] | inout | L16 | SDRAM 数据 |
| sdram_data[15] | inout | L15 | SDRAM 数据 |

## 摄像头接口（OV5640/OV7725）

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| cam_pclk | input | R13 | cmos 数据像素时钟 |
| cam_vsync | input | P9 | cmos 场同步信号 |
| cam_href | input | M9 | cmos 行同步信号 |
| cam_rst_n | output | L9 | cmos 复位信号，低电平有效 |
| cam_pwdn/ | output | R12 | cmos 电源休眠模式选择信号/ |
| cam_sgm_ctrl |  |  | cmos 时钟选择信号（0：使用引脚XCLK提供的时钟 1：使用摄像头自带的晶振提供时钟） |
| cam_scl | output | N9 | cmos IIC时钟信号线 |
| cam_sda | inout | L10 | cmos IIC双向数据线 |
| cam_data[0] | input | K9 | cmos 数据 |
| cam_data[1] | input | P8 | cmos 数据 |
| cam_data[2] | input | N8 | cmos 数据 |
| cam_data[3] | input | M8 | cmos 数据 |
| cam_data[4] | input | P6 | cmos 数据 |
| cam_data[5] | input | N6 | cmos 数据 |
| cam_data[6] | input | R14 | cmos 数据 |
| cam_data[7] | input | T14 | cmos 数据 |

## SD卡（SPI模式）

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| sd_miso | input | K1 | SD卡SPI串行输入数据 |
| sd_clk | input | J2 | SD卡SPI时钟 |
| sd_cs | input | C2 | SD卡SPI片选 |
| sd_mosi | output | D1 | SD卡SPI串行输出数据 |

## SD卡（SDIO模式）

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| sdio_sck | output | J2 | SD卡SDIO时钟 |
| sdio_cmd | inout | D1 | SD卡SDIO命令 |
| sdio_d0 | inout | K1 | SD卡SDIO数据 |
| sdio_d1 | inout | K2 | SD卡SDIO数据 |
| sdio_d2 | inout | B1 | SD卡SDIO数据 |
| sdio_d3 | inout | C2 | SD卡SDIO数据 |

## 以太网

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| eth_rxc | input | E1 | RGMII接收数据时钟 |
| eth_rx_ctl | input | A4 | RGMII输入数据有效信号 |
| eth_rxd [0] | input | B4 | RGMII输入数据RXD[0] |
| eth_rxd [1] | input | A3 | RGMII输入数据RXD[1] |
| eth_rxd [2] | input | B3 | RGMII输入数据RXD[2] |
| eth_rxd [3] | input | A2 | RGMII输入数据RXD[3] |
| eth_txc | input | A5 | RGMII发送数据时钟 |
| eth_tx_ctl | output | B5 | RGMII输出数据有效信号 |
| eth_txd [0] | output | B6 | RGMII输出数据TXD[0] |
| eth_txd [1] | output | A6 | RGMII输出数据TXD[1] |
| eth_txd [2] | output | B7 | RGMII输出数据TXD[2] |
| eth_txd [3] | output | A7 | RGMII输出数据TXD[3] |
| eth_rst_n | output | E5 | 以太网芯片复位信号，低电平有效 |

## CAN总线

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| can_tx | output | T12 | CAN总线发送 |
| can_rx | input | M6 | CAN总线接收 |

## 无线（NRF24L01）

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| nrf_ce | output | J1 | RX或TX模式选择 |
| nrf_cs | output | G2 | NRF SPI片选 |
| nrf_sck | output | F2 | NRF SPI时钟 |
| nrf_mosi | output | F1 | NRF SPI串行输出数据信号 |
| nrf_miso | input | F3 | NRF SPI串行输入数据信号 |
| nrf_irq | input | G1 | NRF 中断信号 |

## ATK MODULE

| 信号名 | 方向 | 管脚 | 端口说明 |
| --- | --- | --- | --- |
| uart_rx | input | E6 | 接收端口 |
| uart_tx | output | A8 | 发送端口 |
| gbc_key | input | D5 | 按键端口 |
| gbc_led | output | D3 | led端口 |
