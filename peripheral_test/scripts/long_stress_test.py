 
"""
FPGA 串口长时间稳定性拷机压力测试脚本 (Long-Duration Soak Test)
------------------------------------------------------------
特点：
  1. 无限循环拷机（持续运行，按 Ctrl+C 可随时安全退出并查看最终统计报告）；
  2. 混合流量负载：
     - 交替注入 128B、512B、1KB、2KB、4KB 大数据流包；
     - 穿插板载 LED 命令包（走马灯闪烁，肉眼可实时观察硬件生命体征）；
  3. 实时遥测监控看板：
     - 运行时长 (HH:MM:SS)
     - 累计总传输吞吐量 (MB)
     - 瞬时与平均传输速率 (KB/s)
     - 误码包数 / 丢包数 (0 容忍)
"""

import os
import sys
import time
import random
import serial
import serial.tools.list_ports

DEFAULT_PORT = "COM3"
DEFAULT_BAUD = 2000000


def build_frame(packet_type: int, payload: bytes) -> bytes:
    """构造协议帧"""
    length = len(payload)
    len_h = (length >> 8) & 0xFF
    len_l = length & 0xFF

    body = bytes([packet_type, len_h, len_l]) + payload
    checksum = sum(body) & 0xFF
    return bytes([0x55, 0x55, 0x55]) + body + bytes([checksum])


def format_time(seconds: float) -> str:
    """将秒数格式化为 HH:MM:SS"""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def run_soak_test(ser: serial.Serial):
    print("=" * 75)
    print(" 开始执行 FPGA 长时间高负荷拷机稳定性测试 (Soak / Burn-in Test)")
    print(" 提示：本测试将持续高频读写，按【Ctrl + C】可随时停止并生成测试报告")
    print("=" * 75)

    start_time = time.time()
    total_packets = 0
    total_bytes = 0
    error_packets = 0
    error_bytes = 0

    # 循环测试的负载配置
    test_sequence = [
        # (类型, 长度, 描述)
        ("DATA", 128,  "128B 大数据流"),
        ("DATA", 512,  "512B 大数据流"),
        ("DATA", 1024, "1024B (1KB) 大数据流"),
        ("DATA", 2048, "2048B (2KB) 大数据流"),
        ("DATA", 4096, "4096B (4KB) 大数据流"),
        ("CMD",  1,    "LED 走马灯控制命令"),
    ]

    led_val = 0x01
    seq_index = 0
    last_print_time = 0

    try:
        while True:
            pkt_type_str, size, desc = test_sequence[seq_index]
            seq_index = (seq_index + 1) % len(test_sequence)

            if pkt_type_str == "CMD":
                # 命令包：轮流移位控制 4 颗 LED (0001 -> 0010 -> 0100 -> 1000)
                payload = bytes([led_val])
                led_val = (led_val << 1) if led_val < 0x08 else 0x01
                frame = build_frame(0x00, payload)
            else:
                # 大数据包：随机伪随机数载荷
                payload = bytes([random.randint(0, 255) for _ in range(size)])
                frame = build_frame(0x01, payload)

            total_packets += 1
            expected_len = len(payload)

            ser.reset_input_buffer()
            t_tx = time.time()
            ser.write(frame)

            # 超时保护 (115200 波特率下 11.5KB/s)
            ser.timeout = max(1.0, (expected_len / 5000.0) + 1.0)
            recv = bytearray()
            deadline = time.time() + ser.timeout

            while len(recv) < expected_len and time.time() < deadline:
                chunk = ser.read(min(512, expected_len - len(recv)))
                if chunk:
                    recv.extend(chunk)
                else:
                    time.sleep(0.001)

            t_cost = time.time() - t_tx

            # 校验数据一致性
            if len(recv) != expected_len:
                error_packets += 1
                error_bytes += abs(expected_len - len(recv))
                print(f"\n[!] 丢包警告 (包 #{total_packets}): 预期 {expected_len}B, 实际收到 {len(recv)}B (耗时 {t_cost:.2f}s)")
            elif recv != payload:
                error_packets += 1
                # 统计不一致的字节数
                diff_count = sum(1 for a, b in zip(recv, payload) if a != b)
                error_bytes += diff_count
                print(f"\n[!] 误码警告 (包 #{total_packets}): 发现 {diff_count} 字节内容不一致！")
            else:
                total_bytes += expected_len

            # 每 0.2 秒刷新一次控制台看板
            now = time.time()
            if now - last_print_time >= 0.2:
                last_print_time = now
                elapsed = now - start_time
                avg_speed = (total_bytes / elapsed / 1024.0) if elapsed > 0 else 0.0
                mb_transferred = total_bytes / (1024.0 * 1024.0)

                status = "PASS" if error_packets == 0 else "FAIL"
                status_color = "\033[92m" if error_packets == 0 else "\033[91m"
                reset_color = "\033[0m"

                sys.stdout.write(
                    f"\r[{format_time(elapsed)}] 包数: {total_packets:<5} | "
                    f"总数据: {mb_transferred:6.2f} MB | "
                    f"平均速率: {avg_speed:4.1f} KB/s | "
                    f"丢包: {error_packets} | "
                    f"误码: {error_bytes}B | "
                    f"状态: [{status}]  "
                )
                sys.stdout.flush()

    except KeyboardInterrupt:
        print("\n\n" + "=" * 75)
        print(" 用户按下 Ctrl+C，正在终止拷机测试并生成总结报告...")
        print("=" * 75)

    elapsed = time.time() - start_time
    avg_speed = (total_bytes / elapsed / 1024.0) if elapsed > 0 else 0.0
    mb_transferred = total_bytes / (1024.0 * 1024.0)

    print("\n" + "=" * 75)
    print(" FPGA 长时间稳定性拷机测试最终认证报告")
    print("=" * 75)
    print(f"  - 持续拷机总时长: {format_time(elapsed)} ({elapsed:.1f} 秒)")
    print(f"  - 累计传输总包数: {total_packets:,} 包")
    print(f"  - 校验有效数据量: {total_bytes:,} 字节 ({mb_transferred:.3f} MB)")
    print(f"  - 平均有效数据速率: {avg_speed:.2f} KB/s")
    print(f"  - 错误/丢包数量: {error_packets} 包")
    print(f"  - 错误字节数量: {error_bytes} 字节")

    if total_bytes > 0:
        ber = (error_bytes / total_bytes) * 100.0
        print(f"  - 实测误码率 (BER): {ber:.6f}%")

    if error_packets == 0:
        print("\n 🏆 拷机认证结果: 【完全合格 (PERFECT)】")
        print("    FPGA 在长时间持续高吞吐、混合负载下，状态机无死锁，FIFO调度无丢包，数据100%保真！")
    else:
        print("\n ⚠️ 拷机认证结果: 【存在异常 (FAIL)】，请检查硬件通信线路。")
    print("=" * 75)


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
        print(f"串口 {port} 打开成功！")
        run_soak_test(ser)


if __name__ == "__main__":
    main()
