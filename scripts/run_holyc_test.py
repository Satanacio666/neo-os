#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

if len(sys.argv) < 2:
    print("Usage: run_holyc_test.py <module.HC> [expected_string] [wait_seconds]")
    sys.exit(1)

target_module = sys.argv[1]
expected_str = sys.argv[2] if len(sys.argv) > 2 else "PASS"
wait_time = float(sys.argv[3]) if len(sys.argv) > 3 else 5.0

mod_base = os.path.basename(target_module).lower().replace('.', '_')
qmp_sock_path = f"/tmp/qmp_neo_{mod_base}.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
artifact_dir = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"

if os.path.exists(qmp_sock_path):
    try: os.remove(qmp_sock_path)
    except: pass

# Always repackage RedSea before test
subprocess.run(["python3", "scripts/mkredsea.py", redsea_img, "apps/"], check=True)

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
    "-device", "virtio-keyboard-device",
    "-device", "virtio-tablet-device",
    "-drive", f"file={disk_img},format=raw,id=bootdisk,if=none",
    "-device", "virtio-blk-pci,drive=bootdisk,bootindex=0",
    "-drive", f"file={redsea_img},format=raw,id=redsea,if=none",
    "-device", "virtio-blk-device,drive=redsea",
    "-serial", "stdio",
    "-display", "none",
    "-qmp", f"unix:{qmp_sock_path},server,nowait"
]

print(f"[TEST-HOLYC] Launching NeoOS to test {target_module}...")
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
for _ in range(50):
    if os.path.exists(qmp_sock_path):
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(qmp_sock_path)
            break
        except: time.sleep(0.1)
    time.sleep(0.1)

if not s:
    print("[ERROR] Could not connect to QMP socket.")
    proc.kill()
    sys.exit(1)

def qmp_cmd(obj):
    s.sendall(json.dumps(obj).encode('utf-8') + b"\r\n")
    buf = b""
    while b"\r\n" not in buf:
        chunk = s.recv(1024)
        if not chunk: break
        buf += chunk
    return json.loads(buf.decode('utf-8', errors='replace'))

greeting = json.loads(s.recv(1024).decode('utf-8'))
qmp_cmd({"execute": "qmp_capabilities"})

def send_qmp_key(key):
    try:
        qmp_cmd({
            "execute": "send-key",
            "arguments": {"keys": [{"type": "qcode", "data": key}]}
        })
        time.sleep(0.03)
    except: pass

def send_qmp_text(text):
    for ch in text:
        if ch == '\n':
            send_qmp_key("ret")
        elif ch == ' ':
            send_qmp_key("spc")
        elif ch == '-':
            send_qmp_key("minus")
        elif ch == '.':
            send_qmp_key("dot")
        elif ch == '/':
            send_qmp_key("slash")
        elif ch == ';':
            send_qmp_key("semicolon")
        elif ch == '+':
            try:
                qmp_cmd({"execute": "send-key", "arguments": {"keys": [{"type": "qcode", "data": "shift"}, {"type": "qcode", "data": "equal"}]}})
            except: pass
        elif ch.isupper():
            try:
                qmp_cmd({"execute": "send-key", "arguments": {"keys": [{"type": "qcode", "data": "shift"}, {"type": "qcode", "data": ch.lower()}]}})
            except: pass
        elif ch.isdigit() or ch.islower():
            send_qmp_key(ch)
        time.sleep(0.04)

def send_cmd(text, wait_s=3.0, use_qmp=False):
    print(f"\n[SHELL-INPUT] >>> {text}")
    if use_qmp:
        send_qmp_text(text + "\n")
    else:
        try:
            for char in text + "\n":
                proc.stdin.write(char.encode('ascii'))
                proc.stdin.flush()
                time.sleep(0.02)
        except: pass
    time.sleep(wait_s)

def capture_screen(name):
    ppm_path = f"/tmp/{name}.ppm"
    png_path = os.path.join(artifact_dir, f"{name}.png")
    qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm_path}})
    time.sleep(0.4)
    if os.path.exists(ppm_path):
        img = Image.open(ppm_path)
        img.save(png_path)
        print(f"[SCREENSHOT] Saved: {png_path} ({img.width}x{img.height})")
        return png_path
    return None

booted = False
for _ in range(200):
    if any("Entering Sovereign" in l for l in logs):
        booted = True
        break
    time.sleep(0.5)

if not booted:
    print("[ERROR] System did not reach Sovereign boot loop.")
    proc.kill()
    sys.exit(1)

time.sleep(1.0)

mod_filename = os.path.basename(target_module)
send_cmd(f"run {mod_filename}", wait_s=wait_time)
capture_screen(f"screenshot_test_{mod_base}")

# Check test results
full_log = " ".join(logs)
passed = expected_str in full_log or all(word in full_log for word in expected_str.split())


print(f"\n==============================================================")
print(f"[TEST-HOLYC] Target: {target_module}")
print(f"[TEST-HOLYC] Expected: '{expected_str}' -> Found: {passed}")
print(f"==============================================================")

proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()
s.close()

if not passed:
    print(f"[TEST-HOLYC] FAILED: Target string '{expected_str}' not found in logs.")
    sys.exit(1)

print(f"[TEST-HOLYC] SUCCESS: {target_module} verified!")
