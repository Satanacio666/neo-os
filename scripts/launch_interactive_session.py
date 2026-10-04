#!/usr/bin/env python3
"""
launch_interactive_session.py - Unified Interactive NeoOS Session Runner
Keeps QEMU live on DISPLAY=:0.0 with VirtIO input for manual GUI interaction,
while exposing /tmp/neo_os_cmd.fifo so commands can be dynamically injected via UART
without ever stopping or restarting QEMU.
"""

import os
import sys
import time
import subprocess
import threading

DISK_IMG = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
REDSEA_IMG = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
BIOS_PATH = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
FIFO_PATH = "/tmp/neo_os_cmd.fifo"
LOG_PATH = "/tmp/neo_os_uart.log"

def main():
    # Kill any stale QEMU instances
    subprocess.run(["killall", "-9", "qemu-system-aarch64"], stderr=subprocess.DEVNULL)
    time.sleep(0.5)

    if os.path.exists(FIFO_PATH):
        try:
            os.remove(FIFO_PATH)
        except OSError:
            pass
    try:
        os.mkfifo(FIFO_PATH)
    except OSError as e:
        print(f"[ERROR] Failed to create FIFO {FIFO_PATH}: {e}")

    env = os.environ.copy()
    env["DISPLAY"] = ":0.0"

    cmd = [
        "taskset", "-c", "0",
        "qemu-system-aarch64",
        "-M", "virt,gic-version=2",
        "-accel", "tcg,thread=single,tb-size=512",
        "-cpu", "cortex-a72",
        "-smp", "4",
        "-m", "1024",
        "-bios", BIOS_PATH,
        "-device", "ramfb",
        "-device", "virtio-gpu-device,xres=1024,yres=768",
        "-device", "virtio-keyboard-device",
        "-device", "virtio-tablet-device",
        "-device", "usb-ehci",
        "-device", "usb-kbd",
        "-device", "usb-tablet",
        "-net", "none",
        "-drive", f"file={DISK_IMG},format=raw,id=disk,if=none",
        "-device", "virtio-blk-pci,drive=disk,bootindex=0",
        "-drive", f"file={REDSEA_IMG},format=raw,id=redsea,if=none",
        "-device", "virtio-blk-device,drive=redsea",
        "-display", "gtk",
        "-serial", "stdio"
    ]

    print("[INTERACTIVE] Spawning QEMU with visible GTK window on DISPLAY=:0.0...")
    log_file = open(LOG_PATH, "w", buffering=1)

    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=False,
        bufsize=0,
        env=env
    )

    boot_ready = threading.Event()

    def reader():
        buf = ""
        while True:
            ch = proc.stdout.read(1)
            if not ch:
                break
            dec = ch.decode('latin-1', errors='replace')
            sys.stdout.write(dec)
            sys.stdout.flush()
            log_file.write(dec)
            log_file.flush()
            buf += dec
            if "Interactive Shell operational. Starting main loop..." in buf:
                boot_ready.set()

    t_reader = threading.Thread(target=reader, daemon=True)
    t_reader.start()

    print("[INTERACTIVE] Booting UEFI & Ring 0 Kernel...")
    if not boot_ready.wait(timeout=35):
        print("[INTERACTIVE ERROR] Boot timeout!")
        proc.kill()
        sys.exit(1)

    print("\n" + "=" * 70)
    print(">>> NeoOS IS NOW LIVE ON YOUR SCREEN FOR MANUAL & SCRIPTED TESTING! <<<")
    print("=" * 70)
    print("  • VirtIO Keyboard & Tablet: Active for direct hands-on testing in GTK window")
    print("  • UART FIFO Control: Write commands to /tmp/neo_os_cmd.fifo")
    print("  • UART Log File    : Real-time mirror in /tmp/neo_os_uart.log")
    print("=" * 70 + "\n")

    def fifo_listener():
        while proc.poll() is None:
            try:
                # Opening FIFO in read mode blocks until a writer connects
                with open(FIFO_PATH, "r") as f:
                    for line in f:
                        if not line.endswith("\n"):
                            line += "\n"
                        print(f"\n[FIFO-COMMAND] Injecting: {line.strip()}")
                        proc.stdin.write(line.encode('latin-1'))
                        proc.stdin.flush()
            except Exception as e:
                time.sleep(0.1)

    t_fifo = threading.Thread(target=fifo_listener, daemon=True)
    t_fifo.start()

    try:
        proc.wait()
    except KeyboardInterrupt:
        print("[INTERACTIVE] Stopping session...")
        proc.terminate()
        proc.wait()

if __name__ == "__main__":
    main()
