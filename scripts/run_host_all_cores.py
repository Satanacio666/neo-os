#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock = "/tmp/qmp_host_all_cores.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
artifact_dir = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"

desktop_png = f"{artifact_dir}/live_all_cores_desktop.png"
crop_png = f"{artifact_dir}/live_all_cores_crop.png"
ppm_path = "/tmp/live_all_cores.ppm"

if os.path.exists(qmp_sock):
    try: os.remove(qmp_sock)
    except: pass

os.environ["DISPLAY"] = ":0.0"

# ALL HOST CORES, MULTI-THREADED TCG, 1024MB TRANSLATION CACHE, FULL HARDWARE GTK WINDOW
cmd = [
    "qemu-system-aarch64",
    "-M", "virt",
    "-accel", "tcg,thread=multi,tb-size=1024",
    "-cpu", "cortex-a72",
    "-smp", "4",
    "-m", "1024",
    "-bios", qemu_bios,
    "-device", "ramfb",
    "-device", "virtio-gpu-device,xres=1024,yres=768",
    "-device", "usb-ehci",
    "-device", "usb-tablet",
    "-drive", f"file={disk_img},format=raw,id=bootdisk,if=none",
    "-device", "virtio-blk-pci,drive=bootdisk,bootindex=0",
    "-drive", f"file={redsea_img},format=raw,id=redsea,if=none",
    "-device", "virtio-blk-device,drive=redsea",
    "-serial", "stdio",
    "-display", "gtk",
    "-qmp", f"unix:{qmp_sock},server,nowait"
]

print("[ALL-CORES] Launching NeoOS on ALL HOST CORES (Multi-Threaded TCG)...")
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
for attempt in range(40):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(qmp_sock)
        break
    except Exception:
        time.sleep(0.2)

if not s:
    print("[ERROR] Failed to connect to QMP socket")
    proc.terminate()
    sys.exit(1)

def qmp_cmd(cmd_dict):
    payload = json.dumps(cmd_dict) + "\r\n"
    s.sendall(payload.encode('utf-8'))
    buf = b""
    while b"\r\n" not in buf:
        chunk = s.recv(1024)
        if not chunk: break
        buf += chunk
    return json.loads(buf.decode('utf-8', errors='replace'))

greeting = json.loads(s.recv(1024).decode('utf-8'))
qmp_cmd({"execute": "qmp_capabilities"})

print("[ALL-CORES] Waiting for kernel boot...")
for attempt in range(60):
    if any("Starting main loop" in l for l in logs):
        print(f"[ALL-CORES] Kernel booted to main loop in {attempt*0.3:.1f}s!")
        break
    time.sleep(0.3)

time.sleep(1.0)

def send_cmd(text, wait_s=2.0):
    print(f"[ALL-CORES] Executing: '{text}'")
    for ch in text + "\n":
        proc.stdin.write(ch.encode('ascii'))
        proc.stdin.flush()
        time.sleep(0.01)
    time.sleep(wait_s)

# Execute interactive HolyC & Lua programs
send_cmd("run StdLib.HC", wait_s=2.0)
send_cmd("run demo.lua", wait_s=1.5)

# Open NeoBench Extreme Unified Engine on All Cores
print("[ALL-CORES] Launching NeoBench Extreme...")
send_cmd("bench", wait_s=4.0)

# Capture live screendump
print("[ALL-CORES] Capturing screendump...")
qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm_path}})
time.sleep(0.5)

if os.path.exists(ppm_path):
    img = Image.open(ppm_path)
    img.save(desktop_png)
    crop = img.crop((270, 45, 270 + 740, 45 + 560))
    crop.save(crop_png)
    print(f"[ALL-CORES] Screenshot saved to {desktop_png}")
    try: os.remove(ppm_path)
    except: pass

print("[ALL-CORES] NeoOS is live on your display with ALL host cores active! Keeping session open...")

try:
    while proc.poll() is None:
        time.sleep(1.0)
except KeyboardInterrupt:
    proc.terminate()
