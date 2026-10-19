import subprocess
import socket
import json
import time
import os
import threading

qmp_sock_path = "/tmp/qmp_neo_all.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
ppm_output = "/home/carlos/.gemini/antigravity/scratch/neo-os/all_enhancements_live.ppm"
png_output = "/home/carlos/.gemini/antigravity/scratch/neo-os/all_enhancements_live.png"
artifact_png = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/all_enhancements_live.png"

# Create clean zeroed redsea img (32MB) to force clean RedSea 2.0 format on boot
with open(redsea_img, "wb") as f:
    f.truncate(32 * 1024 * 1024)

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

print("[TEST] Launching QEMU AArch64 with 4 SMP cores...")
proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=False, bufsize=0)

s = None
for attempt in range(25):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(qmp_sock_path)
        break
    except Exception:
        time.sleep(0.3)

if not s:
    print("[TEST] Error: Could not connect to QMP")
    proc.kill()
    exit(1)

greeting = s.recv(1024)
s.sendall(b'{"execute": "qmp_capabilities"}\n')
res = s.recv(1024)
print("[TEST] QMP Connected.")

kernel_ready = False
log_lines = []

def reader_thread():
    global kernel_ready
    while True:
        line = proc.stdout.readline()
        if not line:
            break
        decoded = line.decode('utf-8', errors='replace')
        log_lines.append(decoded)
        print(f"[QEMU] {decoded.strip()}")
        if "Interactive Shell and Multitasking operational" in decoded:
            kernel_ready = True

t = threading.Thread(target=reader_thread, daemon=True)
t.start()

print("[TEST] Waiting for NeoOS kernel boot...")
start_t = time.time()
while not kernel_ready and (time.time() - start_t) < 30:
    time.sleep(0.2)

if not kernel_ready:
    print("[TEST] Timeout waiting for kernel ready!")
else:
    print("[TEST] >>> NeoOS Kernel Shell is live! Running comprehensive tests <<<")
    time.sleep(1.0)

    commands = [
        b"clear\n",
        b"smp\n",
        b"pwd\n",
        b"ls\n",
        b"mkdir TestDir\n",
        b"cd TestDir\n",
        b"pwd\n",
        b"write hello.HC 42 * 10;\n",
        b"run hello.HC\n",
        b"cd ..\n",
        b"pwd\n",
        b"ramdisk\n",
        b"run Top.HC\n"
    ]

    for c in commands:
        proc.stdin.write(c)
        proc.stdin.flush()
        time.sleep(0.8)

    time.sleep(1.5)

    print("[TEST] Capturing framebuffer screenshot via QMP...")
    qmp_cmd = json.dumps({"execute": "screendump", "arguments": {"filename": ppm_output}}) + "\n"
    s.sendall(qmp_cmd.encode('utf-8'))
    resp = s.recv(2048)
    print(f"[TEST] Screendump response: {resp.decode('utf-8', errors='replace').strip()}")

    time.sleep(0.5)

    if os.path.exists(ppm_output):
        from PIL import Image
        img = Image.open(ppm_output)
        img.save(png_output)
        img.save(artifact_png)
        print(f"[TEST] Saved screenshots to:\n  {png_output}\n  {artifact_png}")

s.close()
proc.kill()
print("[TEST] Test suite complete.")
