import subprocess
import socket
import json
import time
import os
import threading
from PIL import Image

qmp_sock = "/tmp/qmp_live_gui.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

ppm_path = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_gears_benchmark.ppm"
png_path = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_gears_benchmark.png"
art_png = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/live_gears_benchmark.png"
crop_path = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/live_gears_crop.png"

if os.path.exists(qmp_sock):
    try: os.remove(qmp_sock)
    except: pass

os.environ["DISPLAY"] = ":0.0"

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
    "-display", "gtk",
    "-qmp", f"unix:{qmp_sock},server,nowait"
]

print("[LIVE-GUI] Launching QEMU on DISPLAY=:0.0 with GTK window...")
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

print("[LIVE-GUI] Waiting for kernel boot...")
for attempt in range(60):
    if any("Starting main loop" in l for l in logs):
        print(f"[LIVE-GUI] Kernel reached main loop after {attempt*0.5:.1f}s!")
        break
    time.sleep(0.5)

time.sleep(1.0)

# Ensure NeoBench Extreme is open
print("[LIVE-GUI] Launching NeoBench Extreme Unified Engine...")
proc.stdin.write(b"bench\n")
proc.stdin.flush()

# Let it render for 5 seconds to warm up frame pacing and stats
print("[LIVE-GUI] Warming up 3D render pipeline and RTSS telemetry...")
time.sleep(5.0)

# Capture high-res screendump
os.makedirs("/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots", exist_ok=True)
print("[LIVE-GUI] Capturing live screendump via QMP...")
qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm_path}})
time.sleep(1.0)

if os.path.exists(ppm_path):
    img = Image.open(ppm_path)
    img.save(png_path)
    img.save(art_png)
    desktop_png = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe/live_gears_desktop.png"
    img.save(desktop_png)
    print(f"[SUCCESS] Live benchmark screenshot saved to {desktop_png}")

    # Crop the NeoBench window with the HUD
    # The unified benchmark window is positioned at (270, 45, 740, 560)
    w_crop = img.crop((270, 45, 270 + 740, 45 + 560))
    w_crop.save(crop_path)
    print(f"[SUCCESS] Cropped gears HUD saved to {crop_path}")
else:
    print(f"[FAIL] Screendump PPM not found at {ppm_path}")

print("[LIVE-GUI] System is now running live on your screen. Keeping QEMU active...")

# Keep running so user can view and interact
try:
    while proc.poll() is None:
        time.sleep(1.0)
except KeyboardInterrupt:
    proc.terminate()
