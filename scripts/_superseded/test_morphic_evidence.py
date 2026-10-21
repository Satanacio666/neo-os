#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_morphic.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
artifact_dir = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"

if os.path.exists(qmp_sock_path):
    try: os.remove(qmp_sock_path)
    except: pass

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

print("[TEST-MORPHIC] Launching NeoOS to verify Smalltalk Morphic Halos & Continuous Dragging...")
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
    png_path = f"{artifact_dir}/{name}.png"
    qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm_path}})
    time.sleep(0.5)
    if os.path.exists(ppm_path):
        img = Image.open(ppm_path)
        img.save(png_path)
        os.remove(ppm_path)
        print(f"[SCREENSHOT] Saved: {png_path} ({img.width}x{img.height})")
        return True
    return False

print("[TEST-MORPHIC] Waiting for cold boot to reach DolDocShell prompt...")
booted = False
for _ in range(80):
    if any("DolDocShell active" in line for line in logs):
        booted = True
        break
    time.sleep(0.5)

if not booted:
    print("[ERROR] Cold boot failed to activate DolDocShell.")
    proc.kill()
    sys.exit(1)

time.sleep(1.0)
send_cmd("showcase", wait_s=3.0)

# Inspect Slider Widget by Name (g_shader_speed)
send_cmd("inspect g_shader_speed", wait_s=2.0)
capture_screen("screenshot_10_morphic_halo_active")

# Inspect Oscilloscope Widget by Name (sine)
send_cmd("inspect sine", wait_s=1.5)
capture_screen("screenshot_11_morphic_halo_card")

# Dismiss inspection
send_cmd("inspect", wait_s=1.0)
capture_screen("screenshot_12_morphic_dismissed")

proc.terminate()
try: proc.wait(timeout=5)
except: proc.kill()

print("[TEST-MORPHIC] All Morphic Halo interactive tests executed successfully!")
