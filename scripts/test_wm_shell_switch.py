#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_wm_switch.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
artifact_dir = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"

if os.path.exists(qmp_sock_path):
    try: os.remove(qmp_sock_path)
    except: pass

# Repackage RedSea
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

print("[TEST-SWITCH] Launching NeoOS to verify DolDoc <-> WM round-trip...")
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
for _ in range(50):
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

def send_cmd(text, wait_s=2.0):
    print(f"\n[SHELL-INPUT] >>> {text}")
    try:
        for char in text + "\n":
            proc.stdin.write(char.encode('ascii'))
            proc.stdin.flush()
            time.sleep(0.03)
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

# Wait for cold boot into fullscreen DolDoc shell
booted = False
for _ in range(200):
    if any("DolDocShell active" in l for l in logs):
        booted = True
        break
    time.sleep(0.5)

if not booted:
    print("[ERROR] Cold boot failed to reach DolDocShell.")
    proc.kill()
    sys.exit(1)

print("[TEST-SWITCH] Step 1: Cold boot into sovereign Fullscreen DolDoc verified!")
capture_screen("screenshot_switch_1_coldboot_doldoc")

# Step 2: Launch WM from DolDoc shell
send_cmd("wm", wait_s=3.0)
wm_active = any("Entering Sovereign Window Manager" in l for l in logs) or any("WMEventLoop starting" in l for l in logs)
print(f"[TEST-SWITCH] Step 2: WM Event Loop entered: {wm_active}")
capture_screen("screenshot_switch_2_wm_active")

# Step 3: Exit WM back to Fullscreen DolDoc
send_cmd("shell", wait_s=3.0)
wm_exited = any("WMEventLoop exited cleanly" in l for l in logs) or any("Exiting Window Manager" in l for l in logs)
print(f"[TEST-SWITCH] Step 3: WM Event Loop exited back to DolDoc: {wm_exited}")
capture_screen("screenshot_switch_3_returned_doldoc")

round_trip_success = booted and wm_active and wm_exited
print(f"\n==============================================================")
print(f"[TEST-SWITCH] DolDoc Cold Boot -> WM -> DolDoc Return: {round_trip_success}")
print(f"==============================================================")

proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()
s.close()

if not round_trip_success:
    print("[TEST-SWITCH] FAILED: Round-trip switch failed.")
    sys.exit(1)

print("[TEST-SWITCH] SUCCESS: Seamless DolDoc <-> WM continuum 100% verified!")
sys.exit(0)
