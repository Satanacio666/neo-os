import subprocess
import socket
import json
import time
import os
import threading

qmp_sock_path = "/tmp/qmp_neo_bench3d.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
ppm_output = "/home/carlos/.gemini/antigravity/scratch/neo-os/dual_cubes_benchmarks_live.ppm"
png_output = "/home/carlos/.gemini/antigravity/scratch/neo-os/dual_cubes_benchmarks_live.png"
artifact_png = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/dual_cubes_benchmarks_live.png"

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

print("[TEST] Launching QEMU AArch64 for Dual 3D Cubes & Real-Time Benchmarks...")
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
def reader_thread():
    global kernel_ready
    while True:
        line = proc.stdout.readline()
        if not line: break
        decoded = line.decode('utf-8', errors='replace')
        if "Interactive Shell and Multitasking operational" in decoded:
            kernel_ready = True

t = threading.Thread(target=reader_thread, daemon=True)
t.start()

start_t = time.time()
while not kernel_ready and (time.time() - start_t) < 30:
    time.sleep(0.2)

if kernel_ready:
    print("[TEST] Shell is active! Dispatching 'bench3d' to launch concurrent 3D viewports...")
    time.sleep(1.0)

    # Launch dual 3D cube benchmarks
    proc.stdin.write(b"bench3d\n")
    proc.stdin.flush()

    print("[TEST] Allowing 3D engine and SMP Core 1 & Core 2 stress benchmarks to run for 3.0s...")
    time.sleep(3.0)

    print("[TEST] Capturing framebuffer screendump via QMP...")
    qmp_cmd = json.dumps({"execute": "screendump", "arguments": {"filename": ppm_output}}) + "\n"
    s.sendall(qmp_cmd.encode('utf-8'))
    resp = s.recv(2048)
    time.sleep(0.5)

    if os.path.exists(ppm_output):
        from PIL import Image
        img = Image.open(ppm_output)
        img.save(png_output)
        img.save(artifact_png)
        print(f"[TEST] SUCCESS! Screendump saved to:\n  {png_output}\n  {artifact_png}")
    else:
        print("[ERROR] Screendump file was not generated!")
else:
    print("[ERROR] Kernel did not reach ready state within 30s!")

try:
    s.close()
    proc.terminate()
    proc.wait(timeout=2)
except:
    proc.kill()
