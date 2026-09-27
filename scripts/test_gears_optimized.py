import subprocess
import socket
import json
import time
import os
import threading
from PIL import Image

qmp_sock = "/tmp/qmp_gears_opt.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

shot_dir = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"
out_png = os.path.join(shot_dir, "live_gears_optimized.png")
crop_png = os.path.join(shot_dir, "live_gears_opt_crop.png")

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

print("[GEARS-OPT] Launching QEMU pinned to Host CPU 0...")
proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=False, bufsize=0)

logs = []
def reader():
    while True:
        line = proc.stdout.readline()
        if not line: break
        try:
            dec = line.decode('utf-8', errors='replace').strip()
            logs.append(dec)
            if "SPIKE" in dec or "FPS" in dec or "Render" in dec:
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

print("[GEARS-OPT] Waiting for kernel boot to main loop...")
for attempt in range(60):
    if any("Starting main loop" in l for l in logs):
        print(f"[GEARS-OPT] Kernel reached main loop after {attempt*0.5:.1f}s!")
        break
    time.sleep(0.5)

time.sleep(1.0)

print("[GEARS-OPT] Launching Gears benchmark ('gears')...")
proc.stdin.write(b"gears\r\n")
proc.stdin.flush()

print("[GEARS-OPT] Running Gears for 6.0 seconds to stabilize frame times...")
time.sleep(6.0)

ppm = "/tmp/gears_opt.ppm"
qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm}})
time.sleep(0.5)

if os.path.exists(ppm):
    img = Image.open(ppm)
    img.save(out_png)
    # The unified benchmark window is positioned at (270, 45, 740, 560)
    w_crop = img.crop((270, 45, 270 + 740, 45 + 560))
    w_crop.save(crop_png)
    try: os.remove(ppm)
    except: pass
    print(f"[SUCCESS] Saved optimized Gears capture to {out_png} and {crop_png}")

proc.terminate()
time.sleep(0.5)
print("[GEARS-OPT] Done.")
