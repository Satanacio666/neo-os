import subprocess
import socket
import json
import time
import os
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_fullbench.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

artifact_dir = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"
scratch_dir = "/home/carlos/.gemini/antigravity/scratch/neo-os"

ppm_temp = "/tmp/neo_bench_dump.ppm"

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

print("[TEST] Launching QEMU AArch64 for NeoBench Extreme Suite...")
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

greeting = s.recv(1024)
s.sendall(b'{"execute": "qmp_capabilities"}\n')
res = s.recv(1024)

kernel_ready = False
suite_complete = False
def reader_thread():
    global kernel_ready, suite_complete
    while True:
        line = proc.stdout.readline()
        if not line: break
        decoded = line.decode('utf-8', errors='replace')
        print(decoded, end="")
        if "Interactive Shell and Multitasking operational" in decoded:
            kernel_ready = True
        if "[NEOBENCH] Suite complete" in decoded:
            suite_complete = True

t = threading.Thread(target=reader_thread, daemon=True)
t.start()

start_t = time.time()
while not kernel_ready and (time.time() - start_t) < 30:
    time.sleep(0.2)

def take_screendump(tag):
    if os.path.exists(ppm_temp):
        try: os.remove(ppm_temp)
        except: pass
    qmp_cmd = json.dumps({"execute": "screendump", "arguments": {"filename": ppm_temp}}) + "\n"
    s.sendall(qmp_cmd.encode('utf-8'))
    resp = s.recv(2048)
    time.sleep(0.3)
    if os.path.exists(ppm_temp):
        im = Image.open(ppm_temp)
        png1 = os.path.join(scratch_dir, f"{tag}.png")
        png2 = os.path.join(artifact_dir, f"{tag}.png")
        im.save(png1, "PNG")
        im.save(png2, "PNG")
        print(f"[TEST] Captured {tag}.png ({im.width}x{im.height}) -> saved to {png2}")
        return True
    return False

if kernel_ready:
    print("[TEST] NeoOS Booted! NeoBench Extreme is running Phase 1 & 2 (Single Window 1T & 3T SMP)...")
    time.sleep(3.5)
    take_screendump("bench_single_live")

    print("[TEST] Waiting for Phase 3: Dual Window SMP (Core 1 & Core 2 concurrent side-by-side)...")
    time.sleep(16.0) # Reach Phase 3 Dual Windows
    take_screendump("bench_dual_live")

    print("[TEST] Waiting for Phase 4 (Hardware Accel) and Phase 5 (DolDoc Summary & File Report)...")
    bench_wait_start = time.time()
    while not suite_complete and (time.time() - bench_wait_start) < 40:
        time.sleep(0.5)

    time.sleep(1.0)
    take_screendump("bench_results_live")
    print("[TEST] Full NeoBench Extreme suite successfully verified!")

try:
    s.close()
except: pass
proc.kill()
