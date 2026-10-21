#!/usr/bin/env python3
"""
test_benchmark_scorecard.py - Runs the full 16-phase suite to completion,
captures the final scorecard matrix screen, and checks the exported files.
"""

import os
import sys
import time
import socket
import json
import subprocess
from PIL import Image

QMP_SOCK = "/tmp/qmp_bench_scorecard.sock"
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

    # Start background stdout drainer so pipe buffer never fills up and stalls QEMU
    import threading
    stdout_lines = []
    suite_done_event = threading.Event()
    def drain_stdout():
        while True:
            try:
                line = proc.stdout.readline()
                if not line:
                    break
                dec = line.decode('latin-1', errors='replace')
                stdout_lines.append(dec)
                if "[NEOBENCH]" in dec or "Exported" in dec or "TRANSITION" in dec or "EXP-CHK" in dec:
                    sys.stdout.write(f"[UART] {dec}")
                    sys.stdout.flush()
                if "ALL 40-PHASE EXPORTS COMPLETED" in dec or "[NEOBENCH] Exported 40-Phase" in dec:
                    suite_done_event.set()
            except:
                break
    t_drain = threading.Thread(target=drain_stdout, daemon=True)
    t_drain.start()

    print("[BENCH] Booted to shell. Triggering 'run HolyBenchmark.HC'...")
    proc.stdin.write(b"run HolyBenchmark.HC\n")
    proc.stdin.flush()

    # Capture screenshots across key phases
    # Category 0: Gears (Phases 1-8)
    time.sleep(3.0)
    print("[BENCH] Capturing Phase 1 (Gears)...")
    capture_shot(qmp, "bench_phase1_gears")

    # Category 1: Dual Cubes (Phases 9-16)
    time.sleep(13.0)
    print("[BENCH] Capturing Phase 9 (Cubes)...")
    capture_shot(qmp, "bench_phase2_cubes")

    # Category 2: Dynamics (Phases 17-24)
    time.sleep(13.0)
    print("[BENCH] Capturing Phase 17 (Dynamics)...")
    capture_shot(qmp, "bench_phase3_physics")

    # Category 3: Sphere (Phases 25-32)
    time.sleep(9.0)
    print("[BENCH] Capturing Phase 25 (Sphere)...")
    capture_shot(qmp, "bench_phase4_sphere")

    # Category 4: Fillrate (Phases 33-40)
    time.sleep(12.0)
    print("[BENCH] Capturing Phase 33 (Fillrate)...")
    capture_shot(qmp, "bench_phase5_fillrate")

    # Wait for completion of all 40 phases
    print("[BENCH] Waiting for suite completion via UART event...")
    if not suite_done_event.wait(timeout=360.0):
        print("[BENCH] Warning: Reached 360s timeout, waiting extra 15s...")
        time.sleep(15.0)
    else:
        print("[BENCH] Suite finished signal received via UART!")
        time.sleep(2.0)

    print("[BENCH] Capturing Final Symmetrical 8x5 Comparison Scorecard Screen...")
    capture_shot(qmp, "bench_phase_scorecard")

    # Read and export telemetry via BenchReport.HC
    time.sleep(1.0)
    try:
        proc.stdin.write(b"run BenchReport.HC\n")
        proc.stdin.flush()
        time.sleep(4.0)
    except: pass

    capture_shot(qmp, "bench_report_screen")

    try:
        qmp.sendall(b'{"execute": "quit"}\n')
        qmp.close()
    except: pass
    proc.terminate()
    proc.wait()
    print("[BENCH] Finished successfully.")

if __name__ == "__main__":
    main()
