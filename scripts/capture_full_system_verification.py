#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_verify.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
artifact_dir = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"

if os.path.exists(qmp_sock_path):
    try: os.remove(qmp_sock_path)
    except: pass

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

print("[VERIFY] Launching NeoOS with QMP monitor...")
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
for _ in range(80):
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

def capture_screen(name):
    ppm_path = f"/tmp/{name}.ppm"
    png_path = os.path.join(artifact_dir, f"{name}.png")
    qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm_path}})
    time.sleep(0.5)
    if os.path.exists(ppm_path):
        img = Image.open(ppm_path)
        img.save(png_path)
        print(f"[SCREENSHOT] Saved: {png_path} ({img.width}x{img.height})")
        return png_path
    print(f"[ERROR] Failed to capture {name}")
    return None

def send_cmd(line_str, wait_sec=6.0):
    print(f"\n[SEND] >>> {line_str}")
    for ch in line_str + "\n":
        proc.stdin.write(ch.encode('ascii'))
        proc.stdin.flush()
        time.sleep(0.01)
    time.sleep(wait_sec)

# Wait for boot
print("[VERIFY] Waiting for Cold Boot...")
for _ in range(120):
    if any("DolDocShell active" in l for l in logs):
        break
    time.sleep(0.5)

time.sleep(2.0)
capture_screen("screenshot_01_coldboot_shell")

# Step 2: Run Showcase
send_cmd("showcase", wait_sec=5.0)
capture_screen("screenshot_02_showcase_master")

# Step 3: Run Top
send_cmd("top", wait_sec=5.0)
capture_screen("screenshot_03_top_monitor")

# Step 4: Run Calc & Fact
send_cmd("calc", wait_sec=5.0)
capture_screen("screenshot_04_calc_math")

send_cmd("fact", wait_sec=5.0)
capture_screen("screenshot_05_fact_invariants")

# Step 5: Run Stage-2 Compiler and JIT Tests
send_cmd("run Compiler.HC", wait_sec=7.0)
capture_screen("screenshot_06_compiler_tests")

send_cmd("run TestJitP0.HC", wait_sec=6.0)
capture_screen("screenshot_07_testjitp0")

# Step 6: Run FontVector
send_cmd("run FontVector.HC", wait_sec=6.0)
capture_screen("screenshot_08_font_vector_specimen")

# Step 7: Run Desktop Window Manager
send_cmd("wm", wait_sec=6.0)
capture_screen("screenshot_09_desktop_wm")

print("[VERIFY] All system screenshots captured successfully.")
proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()
s.close()
