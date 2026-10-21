#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_compiler_test.sock"
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

print("[TEST-COMPILER] Launching NeoOS to verify Stage-1 HolyC Compiler (apps/Compiler.HC)...")
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

def send_cmd(text, wait_s=3.0):
    print(f"\n[SHELL-INPUT] >>> {text}")
    for char in text + "\n":
        proc.stdin.write(char.encode('ascii'))
        proc.stdin.flush()
        time.sleep(0.015)
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

print("[TEST-COMPILER] Waiting for boot and WMEventLoop()...")
booted = False
for _ in range(200):
    if any("Entering Sovereign HolyC WMEventLoop()" in l for l in logs):
        booted = True
        print("[TEST-COMPILER] Desktop reached and event loop active!")
        break
    time.sleep(0.5)

if not booted:
    print("[ERROR] System did not reach WMEventLoop().")
    proc.kill()
    sys.exit(1)

time.sleep(2.0)
capture_screen("screenshot_compiler_boot")

# Run Compiler.HC
print("\n[TEST-COMPILER] Executing 'run Compiler.HC'...")
send_cmd("run Compiler.HC", wait_s=6.0)
capture_screen("screenshot_compiler_executed")
capture_screen("screenshot_p9_compiler_verified")

# Check test results
full_log = " ".join(logs)
passed_count = sum(1 for l in logs if "[PASS]" in l and "Test " in l)
has_scorecard = "7 / 7 tests passed" in full_log or "7 / 7" in full_log

print(f"\n==============================================================")
print(f"[TEST-COMPILER] Results: {passed_count} tests reported [PASS]")
print(f"[TEST-COMPILER] Scorecard Confirmed: {has_scorecard}")
print(f"==============================================================")

proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()
s.close()

if not has_scorecard:
    print("[TEST-COMPILER] FAILED: Did not pass all 7 tests.")
    sys.exit(1)

print("[TEST-COMPILER] SUCCESS: Stage-1 HolyC Compiler 100% Verified!")
sys.exit(0)
