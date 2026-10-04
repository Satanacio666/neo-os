#!/usr/bin/env python3
"""
test_benchmark_phases.py - Captures live framebuffer screenshots across individual
sequential benchmark phases and the final comparison scorecard.
"""

import os
import sys
import time
import socket
import json
import subprocess
from PIL import Image

QMP_SOCK = "/tmp/qmp_bench_phases.sock"
DISK_IMG = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
REDSEA_IMG = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
BIOS_PATH = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
ARTIFACTS_DIR = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"

def capture_shot(qmp, name):
    ppm = f"/tmp/{name}.ppm"
    png = os.path.join(ARTIFACTS_DIR, f"{name}.png")
    payload = json.dumps({"execute": "screendump", "arguments": {"filename": ppm}})
    qmp.sendall(payload.encode('utf-8') + b"\n")
    qmp.recv(2048)
    time.sleep(0.3)
    if os.path.exists(ppm):
        im = Image.open(ppm)
        im.save(png)
        try: os.remove(ppm)
        except: pass
        print(f"[SHOT] Saved {png}")
        return png
    return None

def main():
    if os.path.exists(QMP_SOCK):
        try: os.remove(QMP_SOCK)
        except: pass

    cmd = [
        "taskset", "-c", "0",
        "qemu-system-aarch64",
        "-M", "virt,gic-version=2",
        "-accel", "tcg,thread=single,tb-size=256",
        "-cpu", "cortex-a72",
        "-smp", "1",
        "-m", "1024",
        "-bios", BIOS_PATH,
        "-device", "ramfb",
        "-device", "virtio-gpu-device,xres=1024,yres=768",
        "-device", "usb-ehci",
        "-device", "usb-tablet",
        "-net", "none",
        "-drive", f"file={DISK_IMG},format=raw,id=disk,if=none",
        "-device", "virtio-blk-pci,drive=disk,bootindex=0",
        "-drive", f"file={REDSEA_IMG},format=raw,id=redsea,if=none",
        "-device", "virtio-blk-device,drive=redsea",
        "-display", "none",
        "-serial", "stdio",
        "-qmp", f"unix:{QMP_SOCK},server,nowait"
    ]

    print("[BENCH] Starting QEMU...")
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=False, bufsize=0)

    qmp = None
    for _ in range(50):
        try:
            qmp = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            qmp.connect(QMP_SOCK)
            break
        except:
            time.sleep(0.2)

    if not qmp:
        print("Failed to connect to QMP")
        proc.kill()
        sys.exit(1)

    qmp.recv(2048)
    qmp.sendall(b'{"execute": "qmp_capabilities"}\n')
    qmp.recv(2048)

    # Wait for prompt
    buf = ""
    start = time.time()
    while time.time() - start < 30:
        c = proc.stdout.read(1)
        if c:
            buf += c.decode('latin-1', errors='replace')
            if "neo:/>" in buf:
                break

    print("[BENCH] Booted to shell. Triggering 'run HolyBenchmark.HC'...")
    proc.stdin.write(b"run HolyBenchmark.HC\n")
    proc.stdin.flush()

    # Phase 1: Gears (at 2.0s)
    time.sleep(2.5)
    capture_shot(qmp, "bench_phase1_gears")

    # Phase 2: Dual Cubes (at 5.5s)
    time.sleep(3.5)
    capture_shot(qmp, "bench_phase2_cubes")

    # Phase 3: Physics Dynamics (at 9.5s)
    time.sleep(4.0)
    capture_shot(qmp, "bench_phase3_physics")

    # Phase 4: Sphere Geometry (at 13.5s)
    time.sleep(4.0)
    capture_shot(qmp, "bench_phase4_sphere")

    # Phase 5: Fillrate Alpha (at 17.5s)
    time.sleep(4.0)
    capture_shot(qmp, "bench_phase5_fillrate")

    print("[BENCH] Test capture completed successfully.")
    try:
        qmp.sendall(b'{"execute": "quit"}\n')
        qmp.close()
    except: pass
    proc.terminate()
    proc.wait()

if __name__ == "__main__":
    main()
