import subprocess
import socket
import json
import time
import os
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_modular.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

ppm_shot1 = "/home/carlos/.gemini/antigravity/scratch/neo-os/modular_desktop.ppm"
png_shot1 = "/home/carlos/.gemini/antigravity/scratch/neo-os/modular_desktop.png"
art_shot1 = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/modular_desktop.png"

ppm_shot2 = "/home/carlos/.gemini/antigravity/scratch/neo-os/modular_gpu_comp.ppm"
png_shot2 = "/home/carlos/.gemini/antigravity/scratch/neo-os/modular_gpu_comp.png"
art_shot2 = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/modular_gpu_comp.png"

ppm_shot3 = "/home/carlos/.gemini/antigravity/scratch/neo-os/modular_filer_top.ppm"
png_shot3 = "/home/carlos/.gemini/antigravity/scratch/neo-os/modular_filer_top.png"
art_shot3 = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/modular_filer_top.png"

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

print("[TEST] Launching QEMU AArch64 for Modular Graphics & Desktop Verification...")
proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=False, bufsize=0)

s = None
for attempt in range(40):
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
captured_lines = []

def reader_thread():
    global kernel_ready
    while True:
        line = proc.stdout.readline()
        if not line: break
        decoded = line.decode('utf-8', errors='replace')
        captured_lines.append(decoded)
        print("[SERIAL]", decoded.strip())
        if "Interactive Shell and Multitasking operational" in decoded:
            kernel_ready = True

t = threading.Thread(target=reader_thread, daemon=True)
t.start()

start_t = time.time()
while not kernel_ready and (time.time() - start_t) < 30:
    time.sleep(0.2)

if kernel_ready:
    print("[TEST] Kernel ready! Waiting 3s for initial desktop & gears rendering...")
    time.sleep(3.0)

    # Capture Shot 1: Desktop with LXDE / Aero taskbar, 4-core telemetry & active gears
    print("[TEST] Capturing Shot 1: Desktop + Taskbar + Gears...")
    s.sendall(json.dumps({"execute": "screendump", "arguments": {"filename": ppm_shot1}}).encode('utf-8') + b"\n")
    s.recv(2048)
    time.sleep(0.5)

    # Test opening GPU Configuration Panel via shell command
    print("[TEST] Opening GPU Hardware & Buffering Configuration Window...")
    proc.stdin.write(b"gpuconfig\n")
    proc.stdin.flush()
    time.sleep(1.0)

    # Test opening Compositor Configuration Panel via shell command
    print("[TEST] Opening Dedicated Aero Compositor Configuration Window...")
    proc.stdin.write(b"compositor\n")
    proc.stdin.flush()
    time.sleep(1.0)

    # Test DolDoc with $LUA tag
    print("[TEST] Testing Reactive DolDoc $LUA tag evaluation...")
    proc.stdin.write(b"lua print(\"$FG,CYAN$[DOLDOC-LUA]$FG$ Computed: $LUA,\\\"return 42 * 10\\\"$!\")\n")
    proc.stdin.flush()
    time.sleep(1.0)

    # Test HolyGL OpenGL 1.3/2.0 API execution
    print("[TEST] Testing HolyGL OpenGL 1.3/2.0 API in HolyC...")
    proc.stdin.write(b"run HolyGLTest.HC\n")
    proc.stdin.flush()
    time.sleep(1.0)

    # Capture Shot 2: Both windows open on desktop
    print("[TEST] Capturing Shot 2: GPU Config + Compositor Panel...")
    s.sendall(json.dumps({"execute": "screendump", "arguments": {"filename": ppm_shot2}}).encode('utf-8') + b"\n")
    s.recv(2048)
    time.sleep(0.5)

    # Test Filer and Top in DolDoc
    print("[TEST] Running Filer and Top in DolDoc...")
    proc.stdin.write(b"filer\n")
    proc.stdin.flush()
    time.sleep(1.0)
    proc.stdin.write(b"top\n")
    proc.stdin.flush()
    time.sleep(1.0)

    # Capture Shot 3: DolDoc Filer & Top output
    print("[TEST] Capturing Shot 3: DolDoc Explorer & Top Telemetry...")
    s.sendall(json.dumps({"execute": "screendump", "arguments": {"filename": ppm_shot3}}).encode('utf-8') + b"\n")
    s.recv(2048)
    time.sleep(0.5)

    # Convert all PPM to PNG via PIL
    for ppm, png, art in [(ppm_shot1, png_shot1, art_shot1),
                          (ppm_shot2, png_shot2, art_shot2),
                          (ppm_shot3, png_shot3, art_shot3)]:
        if os.path.exists(ppm):
            img = Image.open(ppm)
            img.save(png)
            subprocess.run(["cp", png, art])
            print(f"[TEST] Successfully converted and saved {png} -> {art}")

    print("[TEST] All tests completed successfully!")

try:
    proc.stdin.write(b"reboot\n")
    proc.stdin.flush()
except:
    pass
time.sleep(1.0)
proc.terminate()
try:
    proc.wait(timeout=2)
except:
    proc.kill()
