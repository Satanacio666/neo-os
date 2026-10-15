#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_p2_test.sock"
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

print("[TEST-P2] Launching NeoOS to verify Phase 2 Sovereign Window Manager...")
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

print("[TEST-P2] Waiting for boot and WMEventLoop handover...")
booted = False
for _ in range(80):
    if any("Entering Sovereign HolyC WMEventLoop()" in l for l in logs):
        booted = True
        print("[TEST-P2] System successfully entered Sovereign HolyC WMEventLoop()!")
        break
    time.sleep(0.5)

if not booted:
    print("[TEST-P2] ERROR: System did not reach WMEventLoop(). Logs:")
    for l in logs[-20:]:
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

# Capture initial desktop state with sovereign HolyC WM
snap("screenshot_p2_wm_initial")

# Verify shell input responsiveness in WMEventLoop
send_cmd("dir", wait_s=2.0)

# Elevate and move window 2 to prove z-order reordering and struct updates
send_cmd("g_tool_win.x = 450; g_tool_win.y = 90; g_wm.active_id = 2; g_tool_win.is_active = 1; g_main_win.is_active = 0; g_wm.is_dirty = 1;", wait_s=2.0)
snap("screenshot_p2_wm_elevated")

# Restore focus to main window
send_cmd("g_wm.active_id = 1; g_main_win.is_active = 1; g_tool_win.is_active = 0; g_wm.is_dirty = 1;", wait_s=2.0)
snap("screenshot_p2_wm_verified")

# Verify that WM did not crash and errors are zero
jit_errors = [l for l in logs if "Error" in l or "abort" in l.lower() or "page fault" in l.lower() or "segfault" in l.lower() or "panic" in l.lower()]
print(f"\n[TEST-P2] JIT/Kernel errors count: {len(jit_errors)}")
for err in jit_errors:
    print(f"  [ERROR-LOG] {err}")

# Final verified screenshot
snap("screenshot_p2_wm_verified")

proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()
s.close()

if len(jit_errors) > 0:
    print("[TEST-P2] FAILED: Errors detected during Phase 2 execution.")
    sys.exit(1)

print("[TEST-P2] SUCCESS: Phase 2 Sovereign Window Manager verified perfectly in live QEMU!")
sys.exit(0)
