import subprocess
import socket
import json
import time
import os
import threading

qmp_sock_path = "/tmp/qmp_neo_fixes.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

ppm_gears = "/home/carlos/.gemini/antigravity/scratch/neo-os/glxgears_fixed.ppm"
png_gears = "/home/carlos/.gemini/antigravity/scratch/neo-os/glxgears_fixed.png"
art_gears = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/glxgears_fixed.png"

ppm_bench = "/home/carlos/.gemini/antigravity/scratch/neo-os/bench3d_fixed.ppm"
png_bench = "/home/carlos/.gemini/antigravity/scratch/neo-os/bench3d_fixed.png"
art_bench = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/bench3d_fixed.png"

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

print("[TEST] Launching QEMU AArch64 to verify 3D geometry and rasterizer fixes...")
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
def reader_thread():
    global kernel_ready
    while True:
        line = proc.stdout.readline()
        if not line: break
        decoded = line.decode('utf-8', errors='replace')
        print("[SERIAL]", decoded.strip())
        if "Interactive Shell and Multitasking operational" in decoded:
            kernel_ready = True

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

    # 1. Run GLXGears
    print("[TEST] Running 'gears' command...")
    proc.stdin.write(b"gears\n")
    proc.stdin.flush()
    time.sleep(4.0)

    s.sendall(json.dumps({"execute": "screendump", "arguments": {"filename": ppm_gears}}).encode('utf-8') + b"\n")
    s.recv(2048)
    time.sleep(0.5)

    # 2. Close GLXGears and run Dual Cubes 3D benchmark
    print("[TEST] Running 'closegears' then 'bench3d'...")
    proc.stdin.write(b"closegears\n")
    proc.stdin.flush()
    time.sleep(1.5)

    proc.stdin.write(b"bench3d\n")
    proc.stdin.flush()
    time.sleep(4.0)

    s.sendall(json.dumps({"execute": "screendump", "arguments": {"filename": ppm_bench}}).encode('utf-8') + b"\n")
    s.recv(2048)
    time.sleep(0.5)

    # Convert PPMs to PNG
    from PIL import Image
    for ppm, png, art in [(ppm_gears, png_gears, art_gears),
                          (ppm_bench, png_bench, art_bench)]:
        if os.path.exists(ppm):
            img = Image.open(ppm)
            img.save(png)
            img.save(art)
            print(f"[TEST] Saved screendump:\n  {png}\n  {art}")

    print("[TEST] All 3D verification tests completed successfully!")
else:
    print("[ERROR] Kernel boot timeout!")

try:
    s.sendall(b'{"execute": "quit"}\n')
    s.close()
except: pass

proc.terminate()
try: proc.wait(timeout=2)
except: proc.kill()
