#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_p0_test.sock"
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

print("[TEST-P0] Launching NeoOS to verify Phase 1 JIT Hardening...")
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
for _ in range(40):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(qmp_sock_path)
        break
    except:
        time.sleep(0.3)

if not s:
    print("[ERROR] Cannot connect to QMP")
    proc.kill()
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

# Wait for boot
print("[TEST-P0] Waiting for boot...")
for _ in range(60):
    if any("Entering Sovereign HolyC WMEventLoop()" in l or "Starting main loop" in l for l in logs):
        print("[TEST-P0] System reached desktop/event loop!")
        break
    time.sleep(0.5)

time.sleep(1.0)

def send_cmd(text, wait_s=2.5):
    print(f"\n[SHELL-INPUT] >>> {text}")
    for char in text + "\n":
        proc.stdin.write(char.encode('ascii'))
        proc.stdin.flush()
        time.sleep(0.01)
    time.sleep(wait_s)

def snap(name):
    ppm = f"/tmp/{name}.ppm"
    png = f"{artifact_dir}/{name}.png"
    qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm}})
    time.sleep(0.5)
    if os.path.exists(ppm):
        im = Image.open(ppm)
        im.save(png)
        print(f"[SCREENSHOT] Saved {png}")
        try: os.remove(ppm)
        except: pass

# Run TestJitP0.HC
send_cmd("run TestJitP0.HC", wait_s=4.0)
snap("screenshot_p0_jit_verified")

# Evaluate results
passed_count = sum(1 for l in logs if "[PASS]" in l)
has_scorecard = any("5 / 5 tests passed" in l for l in logs)

print(f"\n[TEST-P0] Result: {passed_count} / 5 tests passed.")
if has_scorecard:
    print("[TEST-P0] SUCCESS: All 5 Phase 1 JIT tests passed with 100% precision!")
else:
    print("[TEST-P0] WARNING / FAILURE: Scorecard not confirmed.")

proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()
s.close()

if not has_scorecard:
    sys.exit(1)
sys.exit(0)
