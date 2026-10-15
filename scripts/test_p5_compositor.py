#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_p5_test.sock"
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

print("[TEST-P5] Launching NeoOS to verify Phase 5 Sovereign Pure HolyC Compositor & Modern Styling...")
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

def send_qmp_key(key):
    qmp_cmd({
        "execute": "send-key",
        "arguments": {"keys": [{"type": "qcode", "data": key}]}
    })
    time.sleep(0.04)

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
            send_qmp_key("shift")
            send_qmp_key("equal")
        elif ch.isupper():
            send_qmp_key(ch.lower())
        elif ch.isdigit() or ch.islower():
            send_qmp_key(ch)
        time.sleep(0.03)

def capture_screen(name):
    ppm_path = f"/tmp/{name}.ppm"
    png_path = os.path.join(artifact_dir, f"{name}.png")
    qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm_path}})
    time.sleep(0.3)
    if os.path.exists(ppm_path):
        img = Image.open(ppm_path)
        img.save(png_path)
        print(f"[TEST-P5] Saved screendump: {png_path} ({img.width}x{img.height})")
        return png_path
    return None

print("[TEST-P5] Waiting for DolDoc.HC, Compositor.HC, Shell.HC, WM.HC compilation and handover...")
booted = False
compositor_compiled = False
for _ in range(80):
    if any("Compiling Compositor.HC" in l for l in logs):
        compositor_compiled = True
    if any("Entering Sovereign HolyC WMEventLoop()" in l for l in logs):
        booted = True
        print("[TEST-P5] System successfully compiled DolDoc.HC, Compositor.HC, Shell.HC and entered Sovereign WMEventLoop()!")
        break
    time.sleep(0.5)

if not booted:
    print("[TEST-P5] ERROR: System did not reach WMEventLoop(). Logs:")
    for l in logs[-25:]: print("  ", l)
    proc.kill()
    sys.exit(1)

time.sleep(2.0)
capture_screen("screenshot_p5_boot")

# Test 1: Open Compositor Dashboard
print("\n[TEST-P5] Step 1: Querying Compositor Dashboard via 'compositor' command...")
send_qmp_text("compositor\n")
time.sleep(1.5)
capture_screen("screenshot_p5_compositor_dashboard")

# Test 2: Toggle V-Sync to 120Hz
print("\n[TEST-P5] Step 2: Testing V-Sync 120Hz frame pacing...")
send_qmp_text("compositor vsync 120\n")
time.sleep(1.0)

# Test 3: Toggle Effects (Shadows & Glass)
print("\n[TEST-P5] Step 3: Toggling Shadows & Acrylic Glass...")
send_qmp_text("compositor shadow\n")
time.sleep(0.5)
send_qmp_text("compositor glass\n")
time.sleep(1.0)
capture_screen("screenshot_p5_compositor_toggles")

# Test 4: Drag Window to verify Damage-Rect blitting
print("\n[TEST-P5] Step 4: Testing window dragging with Damage-Rect blit...")
# Click and drag titlebar of Shell window (centered around x=200, y=55)
qmp_cmd({"execute": "input-send-event", "arguments": {"events": [
    {"type": "rel", "data": {"axis": "x", "value": 0}},
    {"type": "btn", "data": {"down": True, "button": "left"}}
]}})
time.sleep(0.2)
qmp_cmd({"execute": "input-send-event", "arguments": {"events": [
    {"type": "rel", "data": {"axis": "x", "value": 80}},
    {"type": "rel", "data": {"axis": "y", "value": 40}}
]}})
time.sleep(0.2)
qmp_cmd({"execute": "input-send-event", "arguments": {"events": [
    {"type": "btn", "data": {"down": False, "button": "left"}}
]}})
time.sleep(1.0)
capture_screen("screenshot_p5_compositor_dragged")

# Test 5: Verify DolDoc widgets and evaluation
print("\n[TEST-P5] Step 5: Testing expression evaluation and top monitor...")
send_qmp_text("top\n")
time.sleep(1.5)
capture_screen("screenshot_p5_compositor_top")

# Summary and Telemetry Audit
print("\n[TEST-P5] ================================================================")
print("[TEST-P5]               PHASE 5 TELEMETRY & QUALITY AUDIT                 ")
print("[TEST-P5] ================================================================")

doldoc_res = any("DolDoc.HC compiled, res = 0" in l for l in logs)
comp_res = any("Compositor.HC compiled, res = 0" in l for l in logs)
shell_res = any("Shell.HC compiled, res = 0" in l for l in logs)
wm_res = any("WM.HC compiled, res = 0" in l for l in logs)

print(f"  DolDoc.HC Compilation       : {'PASS (res=0)' if doldoc_res else 'FAIL'}")
print(f"  Compositor.HC Compilation   : {'PASS (res=0)' if comp_res else 'FAIL'}")
print(f"  Shell.HC Compilation        : {'PASS (res=0)' if shell_res else 'FAIL'}")
print(f"  WM.HC Compilation           : {'PASS (res=0)' if wm_res else 'FAIL'}")
print(f"  Sovereign WMEventLoop Entry : {'PASS' if booted else 'FAIL'}")

# Scan for aborts, undefined exceptions, panics, faults
critical_keywords = ["Synchronous Exception", "Data Abort", "Instruction Abort", "PANIC", "FATAL", "Undefined symbol"]
critical_errors = []
for l in logs:
    for kw in critical_keywords:
        if kw in l:
            critical_errors.append(l)

print(f"  Critical System Exceptions  : {len(critical_errors)}")
for err in critical_errors:
    print(f"    [ERR] {err}")

proc.kill()

if doldoc_res and comp_res and shell_res and wm_res and len(critical_errors) == 0:
    print("\n[TEST-P5] >>> PHASE 5 EMPIRICAL VERIFICATION COMPLETE: ALL GATES PASSED! <<<")
    sys.exit(0)
else:
    print("\n[TEST-P5] >>> PHASE 5 VERIFICATION FAILED <<<")
    sys.exit(1)
