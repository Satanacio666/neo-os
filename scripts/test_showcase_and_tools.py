#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_showcase.sock"
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

print("[TEST-SHOWCASE] Launching NeoOS to verify Showcase, Disassembler (uf), and Source Inspector...")
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

time.sleep(1.0)

# Test 1: Native AArch64 Disassembly via 'uf WMExit'
send_cmd("uf WMExit", wait_s=3.0)
capture_screen("screenshot_uf_disassembly")
disasm_ok = any("AArch64 Machine Disassembly: WMExit" in l for l in logs) or any("Function size" in l for l in logs)
print(f"[TEST-SHOWCASE] Test 1: Disassembler (uf WMExit) verified: {disasm_ok}")

# Test 2: HolyC Source Code Inspector via 'src Showcase.HC'
send_cmd("src Showcase.HC", wait_s=3.0)
capture_screen("screenshot_src_inspection")
src_ok = any("HolyC Source Code: Showcase.HC" in l for l in logs) or any("ShowcaseMain" in l for l in logs)
print(f"[TEST-SHOWCASE] Test 2: Source Inspector (src Showcase.HC) verified: {src_ok}")

# Test 3: Master DolDoc Showcase via 'showcase'
send_cmd("showcase", wait_s=4.0)
capture_screen("screenshot_showcase_master")
showcase_ok = any("OmniTape Cmds:" in l for l in logs) or any("Widgets:" in l for l in logs) or any("Sovereign DolDoc" in l for l in logs)
print(f"[TEST-SHOWCASE] Test 3: Master DolDoc Showcase verified: {showcase_ok}")

all_ok = disasm_ok and src_ok and showcase_ok
print(f"\n==============================================================")
print(f"[TEST-SHOWCASE] Overall Result: {all_ok}")
print(f"==============================================================")

proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()
s.close()

if not all_ok:
    print("[TEST-SHOWCASE] FAILED!")
    sys.exit(1)

print("[TEST-SHOWCASE] SUCCESS: All TempleOS parity features & Showcase 100% verified!")
sys.exit(0)
