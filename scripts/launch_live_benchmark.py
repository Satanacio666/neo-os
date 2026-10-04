#!/usr/bin/env python3
"""
launch_live_benchmark.py - Launches NeoOS with a live visible GTK display on DISPLAY=:0.0,
automatically triggering both the HolyC CPU benchmark and the full 16-Phase 3D Graphics
& Physics Benchmark Suite for the user to watch in real time.
"""

import os
import sys
import time
import subprocess
import threading

DISK_IMG = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
REDSEA_IMG = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
BIOS_PATH = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

def main():
    # Clean up previous instances
    subprocess.run(["killall", "-9", "qemu-system-aarch64"], stderr=subprocess.DEVNULL)
    time.sleep(0.5)

    env = os.environ.copy()
    env["DISPLAY"] = ":0.0"

    cmd = [
        "qemu-system-aarch64",
        "-M", "virt,gic-version=2",
        "-accel", "tcg,thread=single,tb-size=512",
        "-cpu", "cortex-a72",
        "-smp", "4",
        "-m", "1024",
        "-bios", BIOS_PATH,
        "-device", "ramfb",
        "-device", "virtio-gpu-device,xres=1024,yres=768",
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

    print("[LAUNCH] Spawning QEMU with visible GTK window on DISPLAY=:0.0...")
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
            buf += dec
            if "Interactive Shell operational. Starting main loop..." in buf:
                boot_ready.set()

    t = threading.Thread(target=reader, daemon=True)
    t.start()

    print("[LAUNCH] Waiting for NeoOS to boot into graphical shell...")
    if not boot_ready.wait(timeout=35):
        print("[LAUNCH ERROR] Boot timeout!")
        proc.kill()
        sys.exit(1)

    print("\n[LAUNCH] Desktop shell ready! Sleeping 1.5s to let window render...")
    time.sleep(1.5)

    # 1. Run Complete Unified Benchmark (CPU + 40-Phase 3D Graphics & Physics)
    print("\n[LAUNCH] Executing 'run HolyBenchmark.HC' on live display...")
    proc.stdin.write(b"run HolyBenchmark.HC\n")
    proc.stdin.flush()

    print("\n" + "=" * 60)
    print(">>> QEMU GRAPHICAL WINDOW IS NOW OPEN ON YOUR SCREEN! <<<")
    print(">>> The Symmetrical 40-Phase 3D Suite is actively running! <<<")
    print(">>> You can see the rotating gears, cubes, dynamics, and HUD. <<<")
    print("=" * 60 + "\n")

    # Keep running so the user can watch the benchmark live
    try:
        proc.wait()
    except KeyboardInterrupt:
        print("[LAUNCH] Terminating QEMU...")
        proc.terminate()
        proc.wait()

if __name__ == "__main__":
    main()
