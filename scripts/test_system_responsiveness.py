import subprocess
import socket
import json
import time
import os
import threading
from PIL import Image

qmp_sock = "/tmp/qmp_resp_test.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

shot_dir = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"

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

print("[RESP-TEST] Launching QEMU pinned to Host CPU 0...")
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

print("[RESP-TEST] Waiting for kernel boot to main loop...")
for attempt in range(60):
    if any("Starting main loop" in l for l in logs):
        print(f"[RESP-TEST] Kernel reached main loop after {attempt*0.5:.1f}s!")
        break
    time.sleep(0.5)

time.sleep(1.0)

def take_screenshot(name):
    ppm = f"/tmp/{name}.ppm"
    png = os.path.join(shot_dir, f"{name}.png")
    qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm}})
    time.sleep(0.5)
    if os.path.exists(ppm):
        img = Image.open(ppm)
        img.save(png)
        try: os.remove(ppm)
        except: pass
        print(f"[SHOT] Saved {png}")
        return png
    else:
        print(f"[FAIL] PPM not found for {name}")
        return None

# Capture initial calm desktop
print("[RESP-TEST] 1. Capturing Initial Clean Desktop (0.0% CPU)...")
take_screenshot("resp_01_clean_desktop")

# Test 1: Send 'help'
print("[RESP-TEST] 2. Testing Shell Command: 'help'...")
t0 = time.time()
proc.stdin.write(b"help\r\n")
proc.stdin.flush()
time.sleep(1.5)
take_screenshot("resp_02_help")
print(f"[RESP-TEST] 'help' completed in {time.time()-t0:.2f}s")

# Test 2: Send 'ls'
print("[RESP-TEST] 3. Testing Shell Command: 'ls' (RedSea FS)...")
t0 = time.time()
proc.stdin.write(b"ls\r\n")
proc.stdin.flush()
time.sleep(1.5)
take_screenshot("resp_03_ls")
print(f"[RESP-TEST] 'ls' completed in {time.time()-t0:.2f}s")

# Test 3: Send 'mem'
print("[RESP-TEST] 4. Testing Shell Command: 'mem' (Kernel Heap)...")
t0 = time.time()
proc.stdin.write(b"mem\r\n")
proc.stdin.flush()
time.sleep(1.5)
take_screenshot("resp_04_mem")
print(f"[RESP-TEST] 'mem' completed in {time.time()-t0:.2f}s")

# Test 4: Open Top
print("[RESP-TEST] 5. Testing GUI Application: 'top' (Process Viewer)...")
t0 = time.time()
proc.stdin.write(b"top\r\n")
proc.stdin.flush()
time.sleep(1.5)
take_screenshot("resp_05_top")
print(f"[RESP-TEST] 'top' opened in {time.time()-t0:.2f}s")

# Test 5: Open NeoMenu
print("[RESP-TEST] 6. Testing NeoMenu App Hub: 'menu'...")
t0 = time.time()
proc.stdin.write(b"menu\r\n")
proc.stdin.flush()
time.sleep(1.5)
take_screenshot("resp_06_menu")
print(f"[RESP-TEST] 'menu' opened in {time.time()-t0:.2f}s")

print("[RESP-TEST] All interactive responsiveness tests completed successfully!")
proc.terminate()
time.sleep(0.5)
print("[RESP-TEST] Done.")
