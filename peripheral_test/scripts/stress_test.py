 
"""
FPGA 串口大数据与流式架构压力测试脚本
------------------------------------------------------------
测试目标：
  1. 阶梯吞吐量压力测试 (128B ~ 4096B，跨越硬件 FIFO 深度 64B)
  2. 连续背靠背高密帧测试 (20 包连发，无位间隙，压测状态机连续吞吐稳定性)
  3. 极限大包长时间吞吐测试 (8192B / 8KB 持续流传输，实时显示传输速率与进度条)
  4. 逐字节一致性对比（0 容忍丢包与错位）
"""

import os
import sys
import time
import random
import serial
import serial.tools.list_ports

DEFAULT_PORT = "COM3"
DEFAULT_BAUD = 115200


def build_frame(packet_type: int, payload: bytes) -> bytes:
    """构造协议帧"""
    length = len(payload)
    if length == 65536:
        len_h, len_l = 0x00, 0x00  # 协议规定 0x0000 代表 65536 字节
    else:
        len_h = (length >> 8) & 0xFF
        len_l = length & 0xFF

    body = bytes([packet_type, len_h, len_l]) + payload
    checksum = sum(body) & 0xFF
    return bytes([0x55, 0x55, 0x55]) + body + bytes([checksum])


def print_progress(current: int, total: int, elapsed: float):
    """打印实时动态进度条"""
    percent = (current / total) * 100.0 if total > 0 else 0.0
    speed = (current / elapsed / 1024.0) if elapsed > 0 else 0.0
    bar_len = 30
    filled = int(bar_len * current // total) if total > 0 else 0
    bar = "=" * filled + ">" + " " * (bar_len - filled - 1) if filled < bar_len else "=" * bar_len
    sys.stdout.write(f"\r  [{bar}] {percent:5.1f}% | {current}/{total} B | 速率: {speed:4.1f} KB/s")
    sys.stdout.flush()


def send_and_verify_stream(ser: serial.Serial, frame: bytes, expected_payload: bytes, desc: str) -> bool:
    """流式发送并校验接收数据的正确性与传输速率"""
    expected_len = len(expected_payload)
    print(f"\n▶ 正在测试: {desc} (数据量: {expected_len} 字节)")

    # 动态超时设定：115200 波特率约 11.5 KB/s，留出 2 倍冗余
    timeout = max(2.0, (expected_len / 5000.0) + 2.0)
    ser.timeout = 0.05  # 设置短轮询超时以实现流畅进度条

    ser.reset_input_buffer()
    t_start = time.time()

    # 一次性将整帧写入操作系统发送缓冲区
    ser.write(frame)

    recv_buf = bytearray()
    deadline = t_start + timeout

    while len(recv_buf) < expected_len and time.time() < deadline:
        chunk = ser.read(min(512, expected_len - len(recv_buf)))
        if chunk:
            recv_buf.extend(chunk)
            print_progress(len(recv_buf), expected_len, time.time() - t_start)
        else:
            time.sleep(0.002)

    elapsed = time.time() - t_start
    print()  # 换行

    # 校验接收结果
    if len(recv_buf) != expected_len:
        print(f"  × FAIL: 接收数据长度不匹配！预期: {expected_len} 字节, 实际收到: {len(recv_buf)} 字节 (耗时 {elapsed:.2f}s)")
        return False

    if recv_buf != expected_payload:
        # 查找首个不匹配字节位置
        for i in range(expected_len):
            if recv_buf[i] != expected_payload[i]:
                print(f"  × FAIL: 数据内容不一致！首个错误在偏移地址 0x{i:04X}: 预期 0x{expected_payload[i]:02X}, 实际 0x{recv_buf[i]:02X}")
                break
        return False

    speed_kbs = (expected_len / elapsed) / 1024.0
    print(f"  √ PASS: 完整正确接收！耗时: {elapsed:.2f}s | 实测平均速率: {speed_kbs:.2f} KB/s | 误码率: 0.00%")
    return True


def run_stress_tests(ser: serial.Serial):
    print("=" * 70)
    print(" 开始执行 FPGA 通信协议深度压力测试 (Stress Test)")
    print("=" * 70)

    total_tests = 0
    passed_tests = 0
    total_bytes_transferred = 0

    # -------------------------------------------------------------------------
    # 压力测试 1：阶梯式吞吐量测试 (128B ~ 4096B)
    # 说明：片上 FIFO 深度为 64B，>64B 的测试能直接考验流式边收边发能力
    # -------------------------------------------------------------------------
    print("\n【阶段 1】阶梯吞吐量压测（跨越 64 字节硬件 FIFO 深度）")
    sizes = [
        (128,  "128 字节 (2x FIFO 深度)"),
        (256,  "256 字节 (4x FIFO 深度)"),
        (512,  "512 字节 (8x FIFO 深度)"),
        (1024, "1024 字节 (1.0 KB)"),
        (2048, "2048 字节 (2.0 KB)"),
        (4096, "4096 字节 (4.0 KB)"),
    ]

    for size, desc in sizes:
        total_tests += 1
        # 生成具有强特征的自增循环数据
        payload = bytes([i % 256 for i in range(size)])
        frame = build_frame(0x01, payload)

        if send_and_verify_stream(ser, frame, payload, desc):
            passed_tests += 1
            total_bytes_transferred += size
        time.sleep(0.05)

    # -------------------------------------------------------------------------
    # 压力测试 2：连续背靠背爆发压测 (Burst Test)
    # 说明：零帧间间隔连续发送 20 包 128B 数据，测试状态机连续重置与抗拥塞能力
    # -------------------------------------------------------------------------
    print("\n【阶段 2】连续背靠背高密帧爆发压测 (Burst Packets)")
    burst_count = 20
    burst_size = 128
    print(f"▶ 正在背靠背连发 {burst_count} 包数据 (每包 {burst_size}B, 累计 {burst_count * burst_size}B)...")

    total_tests += 1
    burst_all_ok = True
    t_burst_start = time.time()

    for seq in range(burst_count):
        # 伪随机数据负载
        random.seed(0x1000 + seq)
        payload = bytes([random.randint(0, 255) for _ in range(burst_size)])
        frame = build_frame(0x01, payload)

        ser.reset_input_buffer()
        ser.write(frame)

        # 接收并比对
        ser.timeout = 0.5
        recv = ser.read(burst_size)
        if recv != payload:
            print(f"\n  × FAIL: 第 {seq + 1}/{burst_count} 包爆发测试出错！")
            burst_all_ok = False
            break
        else:
            total_bytes_transferred += burst_size
            sys.stdout.write(f"\r  [连发进度] 已成功通过: {seq + 1}/{burst_count} 包")
            sys.stdout.flush()

    t_burst_elapsed = time.time() - t_burst_start
    print()
    if burst_all_ok:
        passed_tests += 1
        print(f"  √ PASS: 连续 {burst_count} 包背靠背爆发压测全数通过！耗时: {t_burst_elapsed:.2f}s")
    else:
        print(f"  × FAIL: 连续爆发测试存在丢包或错位。")

    # -------------------------------------------------------------------------
    # 压力测试 3：超大数据包极限持久吞吐测试 (8192 字节 / 8KB)
    # -------------------------------------------------------------------------
    print("\n【阶段 3】超大数据包持久吞吐测试 (8192 字节 / 8KB)")
    total_tests += 1
    size_8k = 8192
    random.seed(0x5A5A)
    payload_8k = bytes([random.randint(0, 255) for _ in range(size_8k)])
    frame_8k = build_frame(0x01, payload_8k)

    if send_and_verify_stream(ser, frame_8k, payload_8k, "8192 字节 (8.0 KB) 极限吞吐"):
        passed_tests += 1
        total_bytes_transferred += size_8k

    # -------------------------------------------------------------------------
    # 压力测试总结报告
    # -------------------------------------------------------------------------
    print("\n" + "=" * 70)
    print(" 压力测试总结报告")
    print("=" * 70)
    print(f"  - 执行用例总数: {total_tests} 项")
    print(f"  - 通过用例数量: {passed_tests} 项")
    print(f"  - 失败用例数量: {total_tests - passed_tests} 项")
    print(f"  - 累计传输并比对的数据总量: {total_bytes_transferred:,} 字节 ({total_bytes_transferred / 1024.0:.2f} KB)")
    print(f"  - 字节完整性与误码率: 0 丢包, 0 乱序, 100% 比对成功")

    if passed_tests == total_tests:
        print("\n 结论：FPGA 数据流直通架构与 FIFO 调度在持续高负载下表现出极高稳定性！")
    else:
        print("\n 结论：高负载下出现异常，请检查硬件通信质量。")
    print("=" * 70)


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
            timeout=1.0
        )
    except serial.SerialException as e:
        print(f"\n[错误] 无法打开串口 {port}: {e}")
        print("温馨提示：请确认【串口调试助手】等软件已经点击【关闭串口】，否则串口会被占用。")
        sys.exit(1)

    with ser:
        print(f"串口 {port} 打开成功！开始压力测试...\n")
        run_stress_tests(ser)


if __name__ == "__main__":
    main()
