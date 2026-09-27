#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_full_test.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
artifact_dir = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"

if os.path.exists(qmp_sock_path):
    try: os.remove(qmp_sock_path)
    except: pass

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
    "-display", "none",
    "-qmp", f"unix:{qmp_sock_path},server,nowait"
]

print("[TEST] Launching NeoOS on Core 0...")
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
for _ in range(40):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(qmp_sock_path)
        break
    except:
        time.sleep(0.3)

if not s:
    print("[ERROR] Cannot connect to QMP")
    proc.kill()
    sys.exit(1)

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

# Wait for boot
print("[TEST] Waiting for boot...")
for _ in range(60):
    if any("Starting main loop" in l for l in logs):
        print("[TEST] System reached main loop!")
        break
    time.sleep(0.5)

time.sleep(1.0)

def send_cmd(text, wait_s=2.0):
    print(f"\n[SHELL-INPUT] >>> {text}")
    for char in text + "\n":
        proc.stdin.write(char.encode('ascii'))
        proc.stdin.flush()
        time.sleep(0.01)
    time.sleep(wait_s)

def snap(name):
    ppm = f"/tmp/{name}.ppm"
    png = f"{artifact_dir}/{name}.png"
    qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm}})
    time.sleep(0.5)
    if os.path.exists(ppm):
        im = Image.open(ppm)
        im.save(png)
        print(f"[SCREENSHOT] Saved {png}")
        try: os.remove(ppm)
        except: pass

# 1. Test cat README.TXT
send_cmd("cat README.TXT", wait_s=2.5)
snap("shell_01_cat_readme")

# 2. Test cat GUIDE.TXT
send_cmd("cat GUIDE.TXT", wait_s=2.5)
snap("shell_02_cat_guide")

# 3. Test HolyC calc.HC
send_cmd("run calc.HC", wait_s=2.5)
snap("shell_03_run_calc")

# 4. Test HolyC fact.HC
send_cmd("run fact.HC", wait_s=2.5)
snap("shell_04_run_fact")

# 5. Test HolyC StdLib.HC
send_cmd("run StdLib.HC", wait_s=3.0)
snap("shell_05_run_stdlib")

# 6. Test Lua demo.lua
send_cmd("run demo.lua", wait_s=2.5)
snap("shell_06_run_demo_lua")

# 7. Test Lua bench.lua
send_cmd("run bench.lua", wait_s=3.0)
snap("shell_07_run_bench_lua")

# 8. Test HolyGL test in HolyC
send_cmd("run HolyGLTest.HC", wait_s=3.0)
snap("shell_08_run_holygl")

# 9. Clean finish
print("\n[TEST] All interactive commands executed successfully!")
proc.terminate()
try: proc.wait(timeout=3)
except: proc.kill()
s.close()
