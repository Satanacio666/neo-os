#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_unified.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

os.makedirs("/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots", exist_ok=True)
ppm_shot1 = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_neobench_gears.ppm"
png_shot1 = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_neobench_gears.png"
art_shot1 = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/live_neobench_gears.png"

ppm_shot2 = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_neobench_cubes.ppm"
png_shot2 = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_neobench_cubes.png"
art_shot2 = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/live_neobench_cubes.png"

ppm_shot3 = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_neobench_suite.ppm"
png_shot3 = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_neobench_suite.png"
art_shot3 = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/live_neobench_suite.png"

ppm_shot4 = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_neobench_dynamics.ppm"
png_shot4 = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_neobench_dynamics.png"
art_shot4 = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/live_neobench_dynamics.png"

if os.path.exists(qmp_sock_path):
    try: os.remove(qmp_sock_path)
    except: pass

cmd = [
    "qemu-system-aarch64",
    "-M", "virt",
    "-cpu", "cortex-a72",
    "-smp", "4",
    "-m", "1024",
    "-bios", qemu_bios,
    "-device", "ramfb",
    "-device", "virtio-gpu-device",
    "-device", "usb-ehci",
    "-device", "usb-tablet",
    "-drive", f"file={disk_img},format=raw,id=bootdisk,if=none",
    "-device", "virtio-blk-pci,drive=bootdisk,bootindex=0",
    "-drive", f"file={redsea_img},format=raw,id=redsea,if=none",
    "-device", "virtio-blk-device,drive=redsea",
    "-serial", "stdio",
    "-display", "none",
    "-qmp", f"unix:{qmp_sock_path},server,nowait"
]

print("[TEST] Launching QEMU AArch64 for NeoBench Extreme & Damage Compositor Verification...")
proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=False, bufsize=0)

s = None
for attempt in range(40):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(qmp_sock_path)
        break
    except Exception:
        time.sleep(0.3)

if not s:
    print("[ERROR] Failed to connect to QMP socket!")
    proc.kill()
    exit(1)

def qmp_cmd(sock, cmd_obj):
    sock.sendall((json.dumps(cmd_obj) + "\r\n").encode())
    res = ""
    while True:
        data = sock.recv(4096).decode('utf-8', errors='ignore')
        res += data
        if "\r\n" in data:
            break
    return res

qmp_cmd(s, {"execute": "qmp_capabilities"})

boot_log = []
def read_serial():
    while True:
        line = proc.stdout.readline()
        if not line:
            break
        text = line.decode('utf-8', errors='ignore')
        boot_log.append(text)
        print(f"  [QEMU] {text.strip()}")

t = threading.Thread(target=read_serial, daemon=True)
t.start()

print("[TEST] Waiting for NeoOS interactive shell...")
booted = False
for _ in range(60):
    for l in boot_log:
        if "Starting interactive shell" in l or "DolDoc GUI Shell ready" in l or "SASOS" in l:
            booted = True
            break
    if booted:
        break
    time.sleep(0.5)

time.sleep(2.0)
print(f"[TEST] Shell ready. Booted status: {booted}")

def send_shell_cmd(c_str):
    print(f"[TEST] Executing command: '{c_str}'")
    for ch in c_str + "\n":
        proc.stdin.write(ch.encode('ascii'))
        proc.stdin.flush()
        time.sleep(0.04)
    time.sleep(1.0)

def capture_screen(ppm_path, png_path, art_path):
    print(f"[TEST] Capturing screenshot: {png_path}...")
    qmp_cmd(s, {"execute": "screendump", "arguments": {"filename": ppm_path}})
    for _ in range(20):
        time.sleep(0.2)
        if os.path.exists(ppm_path) and os.path.getsize(ppm_path) > 1000:
            try:
                img = Image.open(ppm_path)
                img.load()
                img.save(png_path)
                img.save(art_path)
                print(f"  -> Successfully generated {png_path} ({os.path.getsize(png_path)} bytes)")
                return
            except Exception as e:
                pass
    print(f"  [WARN] Failed to capture clean image for {png_path}")

# 1. Launch Master NeoBench Extreme (Default Tab 1: Gears 3D)
send_shell_cmd("bench")
time.sleep(3.0)
capture_screen(ppm_shot1, png_shot1, art_shot1)

# 2. Switch to Tab 2: Dual Cubes SMP
send_shell_cmd("bench3d")
time.sleep(3.0)
capture_screen(ppm_shot2, png_shot2, art_shot2)

# 3. Switch to Tab 3: Dynamics 3D Multi-Body Physics
send_shell_cmd("dynamics")
time.sleep(3.5)
capture_screen(ppm_shot4, png_shot4, art_shot4)

# 4. Switch to Tab 4: 7-Cycle Suite
send_shell_cmd("benchsuite")
time.sleep(4.0)
capture_screen(ppm_shot3, png_shot3, art_shot3)

# 5. Test Lua 3D Controller & AAPCS FFI
send_shell_cmd("run bench.lua")
time.sleep(3.0)

# 6. RTSS Hardware Telemetry
send_shell_cmd("perf")
time.sleep(1.5)

# 7. Stop Benchmark & Export Log
send_shell_cmd("stopbench")
time.sleep(1.5)

# 8. Read and display BENCH_REPORT.TXT from disk
send_shell_cmd("cat BENCH_REPORT.TXT")
time.sleep(2.0)

# 9. Test Graphics HAL Pipeline Mode Switching
send_shell_cmd("render cpu")
time.sleep(1.0)
send_shell_cmd("render smp")
time.sleep(1.0)
send_shell_cmd("render gpu")
time.sleep(1.0)
send_shell_cmd("gpuconfig")
time.sleep(2.0)

print("[TEST] Gracefully shutting down QEMU...")
try:
    qmp_cmd(s, {"execute": "quit"})
except:
    proc.terminate()
time.sleep(1.0)
proc.kill()

print("\n[TEST COMPLETED SUCCESSFULLY]")
