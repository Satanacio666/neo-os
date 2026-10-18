#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_master_suite.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
artifact_dir = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"

if os.path.exists(qmp_sock_path):
    try: os.remove(qmp_sock_path)
    except: pass

# Re-pack RedSea image to guarantee latest code
subprocess.run(["python3", "scripts/mkredsea.py", redsea_img, "apps/"], check=True)

cmd = [
    "taskset", "-c", "0",
    "qemu-system-aarch64",
    "-M", "virt",
    "-accel", "tcg,thread=single,tb-size=512",
    "-cpu", "cortex-a72",
    "-smp", "4",
    "-m", "1024",
    "-bios", qemu_bios,
    "-device", "ramfb",
    "-device", "virtio-gpu-device,xres=1024,yres=768",
    "-device", "virtio-keyboard-device",
    "-device", "virtio-tablet-device",
    "-drive", f"file={disk_img},format=raw,id=bootdisk,if=none",
    "-device", "virtio-blk-pci,drive=bootdisk,bootindex=0",
    "-drive", f"file={redsea_img},format=raw,id=redsea,if=none",
    "-device", "virtio-blk-device,drive=redsea",
    "-serial", "stdio",
    "-display", "none",
    "-qmp", f"unix:{qmp_sock_path},server,nowait"
]

print("[MASTER-SUITE] Launching NeoOS Empirical Verification Suite...")
proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=False, bufsize=0)

logs = []
def reader():
    while True:
        line = proc.stdout.readline()
        if not line: break
        try:
            dec = line.decode('utf-8', errors='replace').strip()
            logs.append(dec)
            print(f"[SERIAL] {dec}")
        except: pass

t = threading.Thread(target=reader, daemon=True)
t.start()

s = None
for _ in range(60):
    if os.path.exists(qmp_sock_path):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(qmp_sock_path)
            break
        except: time.sleep(0.1)
    time.sleep(0.1)

if not s:
    print("[ERROR] Could not connect to QMP socket.")
    proc.kill()
    sys.exit(1)

def qmp_cmd(obj):
    s.sendall(json.dumps(obj).encode('utf-8') + b"\r\n")
    buf = b""
    while b"\r\n" not in buf:
        chunk = s.recv(1024)
        if not chunk: break
        buf += chunk
    return json.loads(buf.decode('utf-8', errors='replace'))

greeting = json.loads(s.recv(1024).decode('utf-8'))
qmp_cmd({"execute": "qmp_capabilities"})

def send_cmd(text, wait_s=2.5):
    print(f"\n[SHELL-INPUT] >>> {text}")
    try:
        for char in text + "\n":
            proc.stdin.write(char.encode('ascii'))
            proc.stdin.flush()
            time.sleep(0.02)
    except: pass
    time.sleep(wait_s)

def capture_screen(name):
    ppm_path = f"/tmp/{name}.ppm"
    png_path = os.path.join(artifact_dir, f"{name}.png")
    qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm_path}})
    time.sleep(0.4)
    if os.path.exists(ppm_path):
        img = Image.open(ppm_path)
        img.save(png_path)
        print(f"[SCREENSHOT] Saved: {png_path} ({img.width}x{img.height})")
        return png_path
    return None

# 1. Wait for Cold Boot into DolDocShell
print("[MASTER-SUITE] Waiting for Cold Boot...")
booted = False
for _ in range(700):
    if any("DolDocShell active" in l for l in logs):
        booted = True
        break
    time.sleep(0.5)

if not booted:
    print("[ERROR] Cold boot failed to reach DolDocShell.")
    capture_screen("screenshot_00_boot_failed")
    proc.kill()
    sys.exit(1)

time.sleep(1.0)
capture_screen("screenshot_01_master_coldboot")
print("[MASTER-SUITE] Cold boot confirmed. Fullscreen DolDocShell active.")

# 2. Test Runtime Theme Switching: Nord
send_cmd("theme nord", wait_s=2.0)
capture_screen("screenshot_02_theme_nord")

# 3. Test Phase 2 Compiler Suite (TestJitP0.HC: 10 tests)
send_cmd("run TestJitP0.HC", wait_s=3.0)
capture_screen("screenshot_03_testjitp0")
p0_pass = any("10 / 10 tests passed" in l for l in logs) or any("Scorecard: 10 / 10" in l for l in logs)
print(f"[MASTER-SUITE] TestJitP0 10/10 tests passed: {p0_pass}")

# 4. Test Native CPU Benchmarks (BenchCpu.HC)
send_cmd("run BenchCpu.HC", wait_s=3.0)
capture_screen("screenshot_04_benchcpu")
cpu_pass = any("CPU Architecture Rating: PERFECT" in l for l in logs) or any("5/5 Passes" in l for l in logs)
print(f"[MASTER-SUITE] BenchCpu 5/5 passes: {cpu_pass}")

# 5. Test 40-Phase Symmetrical 3D & GPU Benchmark (HolyBenchmark.HC)
send_cmd("run HolyBenchmark.HC", wait_s=4.0)
capture_screen("screenshot_05_holybenchmark")
bench_pass = any("40-Phase Unified 3D & GPU Pipeline Active" in l for l in logs)
print(f"[MASTER-SUITE] HolyBenchmark 40-Phase active: {bench_pass}")

# 6. Test Telemetry Report Viewer (BenchReport.HC)
send_cmd("run BenchReport.HC", wait_s=3.0)
capture_screen("screenshot_06_benchreport")
rep_pass = any("BENCH_COMPARISON.TXT" in l for l in logs) or any("BENCH_PROFILER.LOG" in l for l in logs)
print(f"[MASTER-SUITE] BenchReport displayed: {rep_pass}")

# 7. Render Flagship Master Showcase Document (Showcase.HC)
send_cmd("showcase", wait_s=4.0)
capture_screen("screenshot_07_showcase_master")
showcase_pass = any("Sovereign DolDoc" in l for l in logs) or any("Widgets:" in l for l in logs) or any("OmniTape Cmds:" in l for l in logs)
print(f"[MASTER-SUITE] Showcase Master Document rendered: {showcase_pass}")

# 8. Switch Themes while Showcase is Live: Tokyo Night & Cyberpunk OLED
send_cmd("theme tokyo", wait_s=2.0)
capture_screen("screenshot_08_showcase_tokyo")

send_cmd("theme oled", wait_s=2.0)
capture_screen("screenshot_09_showcase_oled")

print("\n" + "=" * 65)
print(f"[MASTER-SUITE] Verification Summary:")
print(f"  • Cold Boot Fullscreen DolDoc : {booted}")
print(f"  • Compiler 10/10 Tests Passed : {p0_pass}")
print(f"  • CPU Benchmarks 5/5 Passed   : {cpu_pass}")
print(f"  • 40-Phase 3D Benchmark Active: {bench_pass}")
print(f"  • Telemetry Report Serialized : {rep_pass}")
print(f"  • Showcase Master Document    : {showcase_pass}")
print("=" * 65)

proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()
s.close()

all_tests = booted and p0_pass and cpu_pass and bench_pass and rep_pass and showcase_pass
if not all_tests:
    print("[MASTER-SUITE] FAILED: Some tests did not pass.")
    sys.exit(1)

print("[MASTER-SUITE] ALL EMPIRICAL VERIFICATION TESTS PASSED PERFECTLY!")
sys.exit(0)
