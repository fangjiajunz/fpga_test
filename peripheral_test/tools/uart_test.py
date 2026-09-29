 
"""
FPGA 串口协议自动化测试脚本 (流式直通架构版)
------------------------------------------------------------
协议格式：
  [帧头 3B: 0x55 0x55 0x55] + [类型 1B] + [长度高 1B] + [长度低 1B] + [数据 NB] + [校验和 1B]
  - 类型 0x00: 命令包 (0~8 字节，第 0 字节控制 LED)
  - 类型 0x01: 大数据包 (1~65536 字节)
  - 校验和: 从 [类型] 开始至 [数据] 结束的累加和低 8 位

流式直通架构特性：
  - 数据段实时流式边收边发（超低时延，无需整包缓存）；
  - 帧头错误、类型非法、长度超限在进入数据段前被硬件硬拦截（不产生任何回传）；
  - 校验和在帧尾比对，校验失败时硬件中止命令生效（不更新 LED），并安全复位回 IDLE。
"""

import sys
import time
import serial
import serial.tools.list_ports

DEFAULT_PORT = "COM3"
DEFAULT_BAUD = 115200


def build_frame(packet_type: int, payload: bytes, force_bad_checksum: bool = False) -> bytes:
    """构造协议帧"""
    length = len(payload)
    len_h = (length >> 8) & 0xFF
    len_l = length & 0xFF

    body = bytes([packet_type, len_h, len_l]) + payload
    checksum = sum(body) & 0xFF
    if force_bad_checksum:
        checksum = (checksum + 1) & 0xFF  # 故意注入错误校验和

    return bytes([0x55, 0x55, 0x55]) + body + bytes([checksum])


def hex_str(data: bytes) -> str:
    """格式化打印十六进制"""
    return " ".join(f"{b:02X}" for b in data)


def run_tests(ser: serial.Serial):
    print("=" * 65)
    print(" 开始执行 FPGA 通信协议自动化测试 (流式直通架构)")
    print("=" * 65)

    passed = 0
    total = 0

    # -------------------------------------------------------------
    # 测试 1：命令包基本收发与 LED 走马灯测试 (1 字节载荷)
    # -------------------------------------------------------------
    print("\n[测试用例 1] 单字节命令包直通回显与板载 LED 跑马灯测试")
    led_patterns = [
        (0x01, "点亮 LED[0] (0001)"),
        (0x02, "点亮 LED[1] (0010)"),
        (0x04, "点亮 LED[2] (0100)"),
        (0x08, "点亮 LED[3] (1000)"),
        (0x0F, "全亮 LED    (1111)"),
        (0x00, "全灭 LED    (0000)"),
    ]

    for val, desc in led_patterns:
        total += 1
        payload = bytes([val])
        frame = build_frame(0x00, payload)

        ser.reset_input_buffer()
        ser.write(frame)

        # 接收直通回显数据（预期应收到 1 字节回显）
        recv = ser.read(1)

        if recv == payload:
            print(f"  √ PASS | 发送: {hex_str(frame):<24} -> 收到: {hex_str(recv)} | 说明: {desc}")
            passed += 1
        else:
            print(f"  × FAIL | 发送: {hex_str(frame):<24} -> 预期: {hex_str(payload)} 实际收到: {hex_str(recv)} | 说明: {desc}")
        time.sleep(0.15)  # 留出肉眼观察 LED 的时间

    # -------------------------------------------------------------
    # 测试 2：变长命令包测试 (2 ~ 8 字节)
    # -------------------------------------------------------------
    print("\n[测试用例 2] 命令包变长负载测试 (2~8 字节)")
    cmd_payloads = [
        bytes([0x0A, 0x0B]),                             # 2 字节
        bytes([0x01, 0x02, 0x03, 0x04]),                 # 4 字节
        bytes([0x11, 0x22, 0x33, 0x44, 0x55, 0x66]),     # 6 字节
        bytes([0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80])  # 8 字节（最大长度）
    ]

    for payload in cmd_payloads:
        total += 1
        frame = build_frame(0x00, payload)

        ser.reset_input_buffer()
        ser.write(frame)

        recv = ser.read(len(payload))
        if recv == payload:
            print(f"  √ PASS | 长度 {len(payload)}B 负载测试通过！")
            print(f"           发送帧: {hex_str(frame)}")
            print(f"           接收回显: {hex_str(recv)}")
            passed += 1
        else:
            print(f"  × FAIL | 长度 {len(payload)}B 负载测试失败！预期: {hex_str(payload)}, 收到: {hex_str(recv)}")
        time.sleep(0.05)

    # -------------------------------------------------------------
    # 测试 3：大数据包流式输出测试 (TYPE = 0x01)
    # -------------------------------------------------------------
    print("\n[测试用例 3] 大数据包流式输出测试 (TYPE = 0x01, 32 字节)")
    total += 1
    big_payload = bytes(range(32))  # 00 01 02 ... 1F 共 32 字节
    frame = build_frame(0x01, big_payload)

    ser.reset_input_buffer()
    ser.write(frame)

    recv = ser.read(len(big_payload))
    if recv == big_payload:
        print(f"  √ PASS | 大数据包测试成功！完整接收到 32 字节流式数据")
        passed += 1
    else:
        print(f"  × FAIL | 大数据包接收不匹配！收到 {len(recv)} 字节")
        print(f"           实际收到: {hex_str(recv)}")

    # -------------------------------------------------------------
    # 测试 4：容错与异常报文硬拦截测试
    # -------------------------------------------------------------
    print("\n[测试用例 4] 异常报文硬拦截与状态机复位测试")

    # 4.1 帧头损坏硬拦截 (前导码不是连续 3 个 0x55)
    total += 1
    corrupt_header_frame = bytes([0x55, 0x55, 0xAA, 0x00, 0x00, 0x01, 0x01, 0x02])
    ser.reset_input_buffer()
    ser.write(corrupt_header_frame)
    recv = ser.read(1)
    if len(recv) == 0:
        print(f"  √ PASS | 帧头损坏注入测试通过（停留在 S_IDLE，零字节回发）")
        passed += 1
    else:
        print(f"  × FAIL | 帧头损坏未被拦截！收到了: {hex_str(recv)}")

    # 4.2 非法类型硬拦截 (TYPE = 0xFF)
    total += 1
    invalid_type_frame = build_frame(0xFF, bytes([0x01]))
    ser.reset_input_buffer()
    ser.write(invalid_type_frame)
    recv = ser.read(1)
    if len(recv) == 0:
        print(f"  √ PASS | 未知类型帧 (0xFF) 拦截测试通过（在 S_TYPE 被拦截，零字节回发）")
        passed += 1
    else:
        print(f"  × FAIL | 未知类型帧未被拦截！收到了: {hex_str(recv)}")

    # 4.3 命令包超长硬拦截 (9 字节 > 8 字节限制)
    total += 1
    oversized_frame = build_frame(0x00, bytes(9))
    ser.reset_input_buffer()
    ser.write(oversized_frame)
    recv = ser.read(9)
    if len(recv) == 0:
        print(f"  √ PASS | 命令包超长 (9 字节) 拦截测试通过（在 S_LEN_L 被拦截，零字节回发）")
        passed += 1
    else:
        print(f"  × FAIL | 超长命令未被拦截！收到了: {hex_str(recv)}")

    # 4.4 校验和错误与状态机自恢复测试 (直通特性)
    total += 1
    bad_cksum_frame = build_frame(0x00, bytes([0x0A]), force_bad_checksum=True)
    ser.reset_input_buffer()
    ser.write(bad_cksum_frame)
    # 直通架构下，数据段在校验和到达前已流出，收到 0A 为直通架构的正常物理现象
    recv_stream = ser.read(1)

    # 关键验证：在发生校验和错误后，状态机必须安全退出到 S_IDLE，并能继续正常接收后续合法命令
    time.sleep(0.05)
    recovery_payload = bytes([0x05])
    recovery_frame = build_frame(0x00, recovery_payload)
    ser.reset_input_buffer()
    ser.write(recovery_frame)
    recv_recovery = ser.read(1)

    if recv_stream == bytes([0x0A]) and recv_recovery == recovery_payload:
        print(f"  √ PASS | 校验和错误及状态机恢复测试通过：")
        print(f"           - 流式直通数据如期实时输出 (收到: {hex_str(recv_stream)})")
        print(f"           - 校验失败后状态机成功进入 S_ERROR 并安全退回 IDLE，后续命令正常接收 (收到: {hex_str(recv_recovery)})")
        passed += 1
    else:
        print(f"  × FAIL | 状态机未正常恢复！后续命令预期: 05, 收到: {hex_str(recv_recovery)}")

    # -------------------------------------------------------------
    # 测试总结
    # -------------------------------------------------------------
    print("\n" + "=" * 65)
    print(f" 测试完成: 共执行 {total} 项用例, 全部通过: {passed}, 失败: {total - passed}")
    if passed == total:
        print(" 恭喜！FPGA 流式通信协议与状态机全部验证通过！")
    else:
        print(" 请检查失败项及硬件连线/状态。")
    print("=" * 65)


def main():
    port = DEFAULT_PORT
    if len(sys.argv) > 1:
        port = sys.argv[1]

    print(f"正在尝试打开串口: {port} (波特率: {DEFAULT_BAUD})...")
    try:
        ser = serial.Serial(
            port=port,
            baudrate=DEFAULT_BAUD,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.3  # 300ms 读取超时
        )
    except serial.SerialException as e:
        print(f"\n[错误] 无法打开串口 {port}: {e}")
        print("温馨提示：请确认【串口调试助手】等软件已经点击【关闭串口】，否则串口会被占用。")
        print("当前系统可用串口列表：")
        for p in serial.tools.list_ports.comports():
            print(f"  - {p.device}: {p.description}")
        sys.exit(1)

    with ser:
        print(f"串口 {port} 打开成功！")
        run_tests(ser)


if __name__ == "__main__":
    main()
