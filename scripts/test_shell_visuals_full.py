#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_visual.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
artifact_dir = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"

if os.path.exists(qmp_sock_path):
    try: os.remove(qmp_sock_path)
    except: pass

subprocess.run(["python3", "scripts/mkredsea.py", redsea_img, "apps/"], check=True)

cmd = [
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

print("[TEST-VISUAL] Launching NeoOS to verify all shell capabilities and visual aesthetics...")
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
for i in range(800):
    if any("DolDocShell active" in l for l in logs):
        booted = True
        print(f"[TEST-VISUAL] DolDocShell active detected at {i*0.5:.1f}s!")
        break
    if i > 0 and i % 30 == 0:
        print(f"[TEST-VISUAL] Cold boot waiting... ({i*0.5:.0f}s elapsed, {len(logs)} log entries)")
    time.sleep(0.5)

if not booted:
    print("[ERROR] Cold boot failed to reach DolDocShell.")
    proc.kill()
    sys.exit(1)

print("[TEST-VISUAL] Cold boot complete! Starting exhaustive visual capability tests...")
time.sleep(1.0)
capture_screen("screenshot_visual_01_boot")

# Test 1: ls / dir
send_cmd("ls", 2.0)
capture_screen("screenshot_visual_02_ls")
has_ls = any("files / directories" in l or "REDSEA" in l for l in logs)
print(f"[TEST-VISUAL] Test 1: 'ls' directory listing verified: {has_ls}")

# Test 2: mem
send_cmd("mem", 2.0)
capture_screen("screenshot_visual_03_mem")
has_mem = any("Heap Total" in l or "Memory Substrate" in l for l in logs)
print(f"[TEST-VISUAL] Test 2: 'mem' memory telemetry verified: {has_mem}")

# Test 3: top
send_cmd("top", 2.0)
capture_screen("screenshot_visual_04_top")
has_top = any("Active Tasks" in l or "Task Executive" in l for l in logs)
print(f"[TEST-VISUAL] Test 3: 'top' scheduler telemetry verified: {has_top}")

# Test 4: help
send_cmd("help", 2.0)
capture_screen("screenshot_visual_05_help")
has_help = any("Identity Paging" in l or "Shell Console" in l for l in logs)
print(f"[TEST-VISUAL] Test 4: 'help' console manual verified: {has_help}")

# Test 5: uf WMExit
send_cmd("uf WMExit", 2.0)
capture_screen("screenshot_visual_06_uf")
has_uf = any("Function size:" in l or "STP" in l or "AArch64 Native Disassembly" in l for l in logs)
print(f"[TEST-VISUAL] Test 5: 'uf' disassembler verified: {has_uf}")

# Test 6: src Showcase.HC
send_cmd("src Showcase.HC", 2.5)
capture_screen("screenshot_visual_07_src")
has_src = any("Showcase.HC" in l or "HolyC Source Inspector" in l for l in logs)
print(f"[TEST-VISUAL] Test 6: 'src' source inspector verified: {has_src}")

# Test 7: cat GUIDE.TXT
send_cmd("cat GUIDE.TXT", 2.0)
capture_screen("screenshot_visual_08_cat")
has_cat = any("NeoOS System Architecture Guide" in l or "RedSea File Content" in l for l in logs)
print(f"[TEST-VISUAL] Test 7: 'cat' file viewer verified: {has_cat}")

# Test 8: showcase
send_cmd("showcase", 3.0)
capture_screen("screenshot_visual_09_showcase")
has_showcase = any("sovereign post-DOM architecture" in l or "Showcase Complete" in l or "DolDoc 3.0 Master Continuum" in l for l in logs)
print(f"[TEST-VISUAL] Test 8: 'showcase' master demo verified: {has_showcase}")

# Test 9: HolyC interactive math
send_cmd("2 + 2 * 10;", 2.0)
has_math = any("--> 22 (0x16)" in l for l in logs)
print(f"[TEST-VISUAL] Test 9: HolyC live expression evaluation verified: {has_math}")

all_passed = has_ls and has_mem and has_top and has_help and has_uf and has_src and has_cat and has_showcase and has_math
print("\n" + "=" * 60)
print(f"[TEST-VISUAL] Overall Result: {all_passed}")
print("=" * 60)

proc.terminate()
sys.exit(0 if all_passed else 1)
