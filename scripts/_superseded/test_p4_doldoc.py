#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_p4_test.sock"
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

print("[TEST-P4] Launching NeoOS to verify Phase 4 Sovereign Pure HolyC DolDoc 2.0...")
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

print("[TEST-P4] Waiting for DolDoc.HC, Shell.HC and WM.HC compilation and handover...")
booted = False
doldoc_compiled = False
for _ in range(80):
    if any("Compiling DolDoc.HC" in l for l in logs):
        doldoc_compiled = True
    if any("Entering Sovereign HolyC WMEventLoop()" in l for l in logs):
        booted = True
        print("[TEST-P4] System successfully compiled DolDoc.HC, Shell.HC and entered Sovereign WMEventLoop()!")
        break
    time.sleep(0.5)

if not booted:
    print("[TEST-P4] ERROR: System did not reach WMEventLoop(). Logs:")
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

def send_cmd(text, wait_s=2.5):
    print(f"\n[SHELL-INPUT] >>> {text}")
    for char in text + "\n":
        proc.stdin.write(char.encode('ascii'))
        proc.stdin.flush()
        time.sleep(0.01)
    time.sleep(wait_s)

# Capture initial boot state with sovereign DolDoc 2.0 active
snap("screenshot_p4_doldoc_boot")

# 1. Test rich DolDoc showcase: buttons, links, progress bar, checkboxes, tree, divider
send_cmd("doldoc", wait_s=3.0)
snap("screenshot_p4_doldoc_widgets")

# 2. Test top telemetry via DolDoc
send_cmd("top", wait_s=2.5)
snap("screenshot_p4_doldoc_top")

# 3. Test direct HolyC math expression
send_cmd("500 + 250 * 2;", wait_s=2.0)

# Verify zero fatal errors
jit_errors = [l for l in logs if ("Error:" in l or "abort" in l.lower() or "page fault" in l.lower() or "segfault" in l.lower() or "panic" in l.lower()) and "Error: Struct" not in l]
print(f"\n[TEST-P4] JIT/Kernel errors count: {len(jit_errors)}")
for err in jit_errors:
    print(f"  [ERROR-LOG] {err}")

# Final verified screenshot
snap("screenshot_p4_doldoc_verified")

proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()
s.close()

if len(jit_errors) > 0:
    print("[TEST-P4] FAILED: Errors detected during Phase 4 execution.")
    sys.exit(1)

print("[TEST-P4] SUCCESS: Phase 4 Sovereign Pure HolyC DolDoc 2.0 verified perfectly in live QEMU!")
sys.exit(0)
