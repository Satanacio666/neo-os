import subprocess
import socket
import json
import time
import os
import threading
from PIL import Image
import shutil

qmp_sock = "/tmp/qmp_bloco1.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

ppm_path = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/bloco1_test.ppm"
png_path = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/bloco1_test.png"

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

print("[TEST-B1] Launching QEMU AArch64 for Bloco 1 Verification...")
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

print("[TEST-B1] Waiting for kernel boot...")
for attempt in range(60):
    if any("Starting main loop" in l for l in logs):
        print(f"[TEST-B1] Kernel reached main loop after {attempt*0.5:.1f}s!")
        break
    time.sleep(0.5)

time.sleep(1.0)

def send_uart(cmd_str):
    print(f"[TEST-B1] Sending UART: {cmd_str.strip()}")
    proc.stdin.write(cmd_str.encode('utf-8'))
    proc.stdin.flush()
    time.sleep(1.0)

# 1. Test Heap Stats
send_uart("mem\n")
time.sleep(1.0)

# 2. Test Undefined Symbol JIT Call (J1)
send_uart("jit nonexistent_function(42);\n")
time.sleep(1.5)

# 3. Test JIT Struct definition
send_uart("jit class Point { I64 x; I64 y; }; Point p; p.x = 10; p.y = 20;\n")
time.sleep(1.5)

# 4. Test Gears window open and close (CONC-14/15)
send_uart("gears\n")
time.sleep(2.0)
send_uart("close3d\n")
time.sleep(1.5)

# 5. Capture screendump
os.makedirs("/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots", exist_ok=True)
print("[TEST-B1] Capturing screendump...")
qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm_path}})
time.sleep(1.0)

if os.path.exists(ppm_path):
    img = Image.open(ppm_path)
    img.save(png_path)
    print(f"[SUCCESS] Screendump saved to {png_path}")
else:
    print(f"[FAIL] PPM not found at {ppm_path}")

proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()

print("\n========== BLOCO 1 RESULTS ANALYSIS ==========")
j1_success = any("Undefined symbol 'nonexistent_function'" in l for l in logs)
no_abort = not any("Synchronous Abort" in l for l in logs)
heap_ok = any("[HEAP]" in l or "Total Memory" in l or "Free Memory" in l for l in logs)

print(f"J1 (Undefined Symbol Diagnostic): {'PASS' if j1_success else 'FAIL'}")
print(f"System Stability (No 0x0 Abort): {'PASS' if no_abort else 'FAIL'}")
print(f"Heap Integrity: {'PASS' if heap_ok else 'FAIL'}")

if j1_success and no_abort:
    print("\n>>> ALL BLOCO 1 S1-CRITICAL CRITERIA VERIFIED AND PASSED! <<<")
else:
    print("\n>>> FAILURES DETECTED IN BLOCO 1! <<<")
