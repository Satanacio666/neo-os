import subprocess
import socket
import json
import time
import os
import threading
from PIL import Image
import shutil

qmp_sock_path = "/tmp/qmp_neo_perf.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

ppm_menu = "/home/carlos/.gemini/antigravity/scratch/neo-os/menu_live.ppm"
png_menu = "/home/carlos/.gemini/antigravity/scratch/neo-os/menu_live.png"
art_menu = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/menu_live.png"

ppm_fast = "/home/carlos/.gemini/antigravity/scratch/neo-os/glxgears_fast_live.ppm"
png_fast = "/home/carlos/.gemini/antigravity/scratch/neo-os/glxgears_fast_live.png"
art_fast = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/glxgears_fast_live.png"

ppm_dual = "/home/carlos/.gemini/antigravity/scratch/neo-os/glxgears_fast_dual.ppm"
png_dual = "/home/carlos/.gemini/antigravity/scratch/neo-os/glxgears_fast_dual.png"
art_dual = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/glxgears_fast_dual.png"

if os.path.exists(qmp_sock_path):
    try: os.remove(qmp_sock_path)
    except: pass

cmd = [
    "qemu-system-aarch64",
    "-M", "virt",
    "-cpu", "cortex-a72",
    "-smp", "4",
    "-m", "1024",
    "-bios", qemu_bios,
    "-device", "ramfb",
    "-drive", f"file={disk_img},format=raw,id=bootdisk,if=none",
    "-device", "virtio-blk-pci,drive=bootdisk,bootindex=0",
    "-drive", f"file={redsea_img},format=raw,id=redsea,if=none",
    "-device", "virtio-blk-device,drive=redsea",
    "-serial", "stdio",
    "-display", "none",
    "-qmp", f"unix:{qmp_sock_path},server,nowait"
]

print("[TEST] Launching QEMU AArch64 for NeoMenu & Scanline Performance Verification...")
proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=False, bufsize=0)

s = None
for attempt in range(30):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(qmp_sock_path)
        break
    except Exception:
        time.sleep(0.3)

if not s:
    print("[ERROR] Failed to connect to QMP socket!")
    proc.kill()
    exit(1)

s.recv(1024)
s.sendall(b'{"execute": "qmp_capabilities"}\n')
s.recv(1024)

kernel_ready = False
fps_lines = []

def reader_thread():
    global kernel_ready
    while True:
        line = proc.stdout.readline()
        if not line: break
        decoded = line.decode('utf-8', errors='replace')
        print("[SERIAL]", decoded.strip())
        if "Interactive Shell and Multitasking operational" in decoded:
            kernel_ready = True
        if "[GLXGEARS]" in decoded and "FPS" in decoded:
            fps_lines.append(decoded.strip())

t = threading.Thread(target=reader_thread, daemon=True)
t.start()

start_t = time.time()
while not kernel_ready and (time.time() - start_t) < 30:
    time.sleep(0.2)

if kernel_ready:
    time.sleep(1.0)
    proc.stdin.write(b"stopbench\n")
    proc.stdin.flush()
    time.sleep(1.5)

    # 1. Test NeoMenu via menu command
    print("[TEST] Opening NeoMenu application hub...")
    proc.stdin.write(b"menu\n")
    proc.stdin.flush()
    time.sleep(2.0)

    s.sendall(json.dumps({"execute": "screendump", "arguments": {"filename": ppm_menu}}).encode('utf-8') + b"\n")
    s.recv(2048)
    time.sleep(0.5)

    # 2. Test Launching Gears by clicking [ Exec ] button on Gears.HC card at (260, 140)
    print("[TEST] Clicking [ Exec ] on Gears.HC inside NeoMenu (mouse 260 140 1)...")
    proc.stdin.write(b"mouse 260 140 1\n")
    proc.stdin.flush()
    time.sleep(0.2)
    proc.stdin.write(b"mouse 260 140 0\n")
    proc.stdin.flush()
    time.sleep(4.0)

    s.sendall(json.dumps({"execute": "screendump", "arguments": {"filename": ppm_fast}}).encode('utf-8') + b"\n")
    s.recv(2048)
    time.sleep(0.5)

    # 3. Test Dual SMP Gears
    print("[TEST] Closing single gears and launching gears_dual...")
    proc.stdin.write(b"closegears\n")
    proc.stdin.flush()
    time.sleep(1.0)
    proc.stdin.write(b"gears_dual\n")
    proc.stdin.flush()
    time.sleep(4.0)

    s.sendall(json.dumps({"execute": "screendump", "arguments": {"filename": ppm_dual}}).encode('utf-8') + b"\n")
    s.recv(2048)
    time.sleep(0.5)

    # Convert PPM to PNG with PIL
    for ppm, png, art in [(ppm_menu, png_menu, art_menu), (ppm_fast, png_fast, art_fast), (ppm_dual, png_dual, art_dual)]:
        if os.path.exists(ppm):
            img = Image.open(ppm)
            img.save(png)
            shutil.copy(png, art)
            print(f"[TEST] Saved artifact: {art}")

    print("\n--- MEASURED GLXGEARS FPS LOGS ---")
    for f in fps_lines:
        print(f)
    print("----------------------------------\n")

proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()
if s: s.close()
print("[TEST] Test script completed successfully.")
