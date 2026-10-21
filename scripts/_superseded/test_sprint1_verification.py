import subprocess
import socket
import json
import time
import os
import threading
from PIL import Image
import shutil

qmp_sock = "/tmp/qmp_sprint1.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

ppm_path = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/sprint1_gears_rtss.ppm"
png_path = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/sprint1_gears_rtss.png"
art_png = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/sprint1_gears_rtss.png"

if os.path.exists(qmp_sock):
    try: os.remove(qmp_sock)
    except: pass

cmd = [
    "qemu-system-aarch64",
    "-M", "virt",
    "-cpu", "cortex-a72",
    "-smp", "4",
    "-m", "1024",
    "-bios", qemu_bios,
    "-device", "ramfb",
    "-device", "usb-ehci",
    "-device", "usb-tablet",
    "-drive", f"file={disk_img},format=raw,id=bootdisk,if=none",
    "-device", "virtio-blk-pci,drive=bootdisk,bootindex=0",
    "-drive", f"file={redsea_img},format=raw,id=redsea,if=none",
    "-device", "virtio-blk-device,drive=redsea",
    "-serial", "stdio",
    "-display", "none",
    "-qmp", f"unix:{qmp_sock},server,nowait"
]

print("[TEST] Launching QEMU AArch64 for Sprint 1 Verification...")
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
for attempt in range(40):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(qmp_sock)
        break
    except Exception:
        time.sleep(0.3)

if not s:
    print("[ERROR] Failed to connect to QMP socket")
    proc.terminate()
    exit(1)

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

# Wait for kernel boot
print("[TEST] Waiting for kernel boot...")
for attempt in range(60):
    if any("Starting main loop" in l for l in logs):
        print(f"[TEST] Kernel reached main loop after {attempt*0.5:.1f}s!")
        break
    time.sleep(0.5)

time.sleep(1.0)
print("[TEST] Kernel is fully booted and shell is ready. Sending commands to UART...")

def send_uart(cmd_str):
    print(f"[TEST] Sending UART: {cmd_str.strip()}")
    proc.stdin.write(cmd_str.encode('utf-8'))
    proc.stdin.flush()
    time.sleep(1.0)

send_uart("close3d\n")
send_uart("vsync on\n")
send_uart("gears\n")
time.sleep(4.0)

# Capture screendump
os.makedirs("/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots", exist_ok=True)
print("[TEST] Capturing screendump...")
qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm_path}})
time.sleep(1.0)

# Convert PPM to PNG
if os.path.exists(ppm_path):
    img = Image.open(ppm_path)
    img.save(png_path)
    shutil.copyfile(png_path, art_png)
    print(f"[SUCCESS] Screendump saved to {png_path} and copied to {art_png}")
else:
    print(f"[FAIL] PPM not found at {ppm_path}")

proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()
print("[TEST] Done.")
