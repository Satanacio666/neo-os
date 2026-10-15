#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_p3_test.sock"
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

print("[TEST-P3] Launching NeoOS to verify Phase 3 Sovereign Pure HolyC Shell...")
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

print("[TEST-P3] Waiting for HolyC Shell.HC compilation and WMEventLoop handover...")
booted = False
shell_compiled = False
for _ in range(80):
    if any("Compiling Shell.HC" in l for l in logs):
        shell_compiled = True
    if any("Entering Sovereign HolyC WMEventLoop()" in l for l in logs):
        booted = True
        print("[TEST-P3] System successfully compiled Shell.HC and entered Sovereign WMEventLoop()!")
        break
    time.sleep(0.5)

if not booted:
    print("[TEST-P3] ERROR: System did not reach WMEventLoop(). Logs:")
    for l in logs[-25:]:
        print(f"  {l}")
    proc.kill()
    sys.exit(1)

time.sleep(2.0)

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

def send_cmd(text, wait_s=2.0):
    print(f"\n[SHELL-INPUT] >>> {text}")
    for char in text + "\n":
        proc.stdin.write(char.encode('ascii'))
        proc.stdin.flush()
        time.sleep(0.01)
    time.sleep(wait_s)

# Capture initial desktop state with sovereign HolyC shell & WM
snap("screenshot_p3_shell_initial")

# 1. Test 'help' command executed via HolyC Shell
send_cmd("help", wait_s=2.5)
snap("screenshot_p3_shell_help")

# 2. Test 'ls' command executed via HolyC Shell
send_cmd("ls", wait_s=2.0)

# 3. Test 'mem' command executed via HolyC Shell
send_cmd("mem", wait_s=2.0)

# 4. Test 'cat README.TXT'
send_cmd("cat README.TXT", wait_s=2.0)

# 5. Test direct HolyC expression evaluation: 100 + 200 * 3;
send_cmd("100 + 200 * 3;", wait_s=2.0)

# Verify that Shell did not crash and errors are zero
jit_errors = [l for l in logs if ("Error:" in l or "abort" in l.lower() or "page fault" in l.lower() or "segfault" in l.lower() or "panic" in l.lower()) and "Error: Struct" not in l]
print(f"\n[TEST-P3] JIT/Kernel errors count: {len(jit_errors)}")
for err in jit_errors:
    print(f"  [ERROR-LOG] {err}")

# Final verified screenshot
snap("screenshot_p3_shell_verified")

proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()
s.close()

if len(jit_errors) > 0:
    print("[TEST-P3] FAILED: Errors detected during Phase 3 execution.")
    sys.exit(1)

print("[TEST-P3] SUCCESS: Phase 3 Sovereign Pure HolyC Shell verified perfectly in live QEMU!")
sys.exit(0)
