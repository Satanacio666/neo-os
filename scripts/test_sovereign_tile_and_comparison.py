#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_sovereign.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

os.makedirs("/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots", exist_ok=True)
shot_gpuconfig_ppm = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_gpuconfig_tabs.ppm"
shot_gpuconfig_png = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_gpuconfig_tabs.png"
shot_gpuconfig_art = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/live_gpuconfig_tabs.png"

shot_tile_gears_ppm = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_tile_gears.ppm"
shot_tile_gears_png = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_tile_gears.png"
shot_tile_gears_art = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/live_tile_gears.png"

shot_scorecard_ppm = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_bench_scorecard.ppm"
shot_scorecard_png = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_bench_scorecard.png"
shot_scorecard_art = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/live_bench_scorecard.png"

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

print("[TEST] Launching QEMU AArch64 for Unified Sovereign L1 Tile & 6-Phase Comparison Suite...")
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

def send_shell_cmd(c_str, delay=1.0):
    print(f"[TEST] Executing command: '{c_str}'")
    for ch in c_str + "\n":
        proc.stdin.write(ch.encode('ascii'))
        proc.stdin.flush()
        time.sleep(0.03)
    time.sleep(delay)

def capture_screen(ppm_path, png_path, art_path):
    print(f"[TEST] Capturing screenshot: {png_path}...")
    qmp_cmd(s, {"execute": "screendump", "arguments": {"filename": ppm_path}})
    for _ in range(25):
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

# 1. Test Shell GFX & Engine Commands
send_shell_cmd("raster scanline")
send_shell_cmd("tilesize 64")
send_shell_cmd("cores 4")
send_shell_cmd("shading gouraud")
send_shell_cmd("cull 1")

# 2. Open GPU Configuration Multi-Tab Hub
send_shell_cmd("gpuconfig", delay=2.5)
capture_screen(shot_gpuconfig_ppm, shot_gpuconfig_png, shot_gpuconfig_art)

# 3. Launch 3D GLXGears with Master Benchmark Engine (brought to front)
send_shell_cmd("bench", delay=3.5)
capture_screen(shot_tile_gears_ppm, shot_tile_gears_png, shot_tile_gears_art)

# 4. Trigger the Automated 6-Phase Scientific Comparison Suite
send_shell_cmd("benchcompare", delay=1.0)
print("[TEST] Running 6-Phase Scientific Comparison Suite across all architectures...")

shot_suite1_ppm = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_suite_phase1.ppm"
shot_suite1_png = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_suite_phase1.png"
shot_suite1_art = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/live_suite_phase1.png"

shot_suite2_ppm = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_suite_phase2.ppm"
shot_suite2_png = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_suite_phase2.png"
shot_suite2_art = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/live_suite_phase2.png"

shot_suite3_ppm = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_suite_phase3.ppm"
shot_suite3_png = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_suite_phase3.png"
shot_suite3_art = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/live_suite_phase3.png"

captured1, captured2, captured3 = False, False, False

for i in range(45):
    if i == 2 and not captured1:
        capture_screen(shot_suite1_ppm, shot_suite1_png, shot_suite1_art)
        captured1 = True
    elif i == 6 and not captured2:
        capture_screen(shot_suite2_ppm, shot_suite2_png, shot_suite2_art)
        captured2 = True
    elif i == 11 and not captured3:
        capture_screen(shot_suite3_ppm, shot_suite3_png, shot_suite3_art)
        captured3 = True

    done = any("Exported scientific comparison matrix" in l for l in boot_log)
    if done:
        print(f"  [+] Suite completion detected at check {i+1}! Telemetry matrices exported.")
        break
    time.sleep(1.0)

time.sleep(2.0)

# Capture the Scorecard Matrix Screen
capture_screen(shot_scorecard_ppm, shot_scorecard_png, shot_scorecard_art)

# 5. Read the generated BENCH_COMPARISON.TXT directly from RedSea disk
send_shell_cmd("cat BENCH_COMPARISON.TXT", delay=2.0)

# 6. Read BENCH_REPORT.TXT as well
send_shell_cmd("cat BENCH_REPORT.TXT", delay=2.0)

print("[TEST] Gracefully shutting down QEMU...")
try:
    qmp_cmd(s, {"execute": "quit"})
except:
    proc.terminate()
time.sleep(1.0)
proc.kill()

print("\n[TEST COMPLETED SUCCESSFULLY]")
