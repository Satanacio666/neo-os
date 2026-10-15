#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_p6_test.sock"
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
    "-device", "virtio-keyboard-device",
    "-drive", f"file={disk_img},format=raw,id=bootdisk,if=none",
    "-device", "virtio-blk-pci,drive=bootdisk,bootindex=0",
    "-drive", f"file={redsea_img},format=raw,id=redsea,if=none",
    "-device", "virtio-blk-device,drive=redsea",
    "-serial", "stdio",
    "-display", "none",
    "-qmp", f"unix:{qmp_sock_path},server,nowait"
]

print("[TEST-P6] Launching NeoOS to verify Phase 6 RedSea Disk Writeback & Sovereign Storage Suite...")
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

def send_cmd(text, wait_s=2.0):
    print(f"\n[SHELL-INPUT] >>> {text}")
    for char in text + "\n":
        proc.stdin.write(char.encode('ascii'))
        proc.stdin.flush()
        time.sleep(0.015)
    time.sleep(wait_s)

def capture_screen(name):
    ppm_path = f"/tmp/{name}.ppm"
    png_path = os.path.join(artifact_dir, f"{name}.png")
    qmp_cmd({"execute": "screendump", "arguments": {"filename": ppm_path}})
    time.sleep(0.3)
    if os.path.exists(ppm_path):
        img = Image.open(ppm_path)
        img.save(png_path)
        print(f"[TEST-P6] Saved screendump: {png_path} ({img.width}x{img.height})")
        return png_path
    return None

print("[TEST-P6] Waiting for boot and handover into Sovereign WMEventLoop()...")
booted = False
for _ in range(80):
    if any("Entering Sovereign HolyC WMEventLoop()" in l for l in logs):
        booted = True
        print("[TEST-P6] System entered Sovereign WMEventLoop()!")
        break
    time.sleep(0.5)

if not booted:
    print("[TEST-P6] ERROR: System did not reach WMEventLoop(). Logs:")
    for l in logs[-25:]: print("  ", l)
    proc.kill()
    sys.exit(1)

time.sleep(2.0)
capture_screen("screenshot_p6_boot")

# Step 1: Test Filer.HC
print("\n[TEST-P6] Step 1: Testing Sovereign File Navigator (Filer.HC)...")
send_cmd("filer", wait_s=2.5)
capture_screen("screenshot_p6_filer")

# Step 2: Test Editor.HC
print("\n[TEST-P6] Step 2: Testing Sovereign Code Inspector & Line-Numbered Editor (Editor.HC)...")
send_cmd("edit", wait_s=2.5)
capture_screen("screenshot_p6_editor")

# Step 3: Test RedSea Persistent Disk Writeback
print("\n[TEST-P6] Step 3: Testing RedSea persistent file creation (save command)...")
test_script_content = 'doldoc_print("HOLYC_PERSISTENCE_VERIFIED_OK!\\n");'
send_cmd(f"save mytest.HC {test_script_content}", wait_s=2.0)

# Step 4: Verify the newly created file can be run by the living JIT
print("\n[TEST-P6] Step 4: Executing newly persisted file from RedSea disk...")
send_cmd("run mytest.HC", wait_s=2.5)
capture_screen("screenshot_p6_save_verified")

# Step 5: Verify the newly created file appears in Filer.HC
print("\n[TEST-P6] Step 5: Verifying file is indexed in Filer.HC...")
send_cmd("filer", wait_s=2.5)
capture_screen("screenshot_p6_filer_updated")

# Summary & Telemetry Audit
print("\n[TEST-P6] ================================================================")
print("[TEST-P6]               PHASE 6 TELEMETRY & QUALITY AUDIT                 ")
print("[TEST-P6] ================================================================")

doldoc_res = any("DolDoc.HC compiled, res = 0" in l for l in logs)
comp_res = any("Compositor.HC compiled, res = 0" in l for l in logs)
shell_res = any("Shell.HC compiled, res = 0" in l for l in logs)
wm_res = any("WM.HC compiled, res = 0" in l for l in logs)
filer_res = any("Found" in l and "entries in current directory" in l for l in logs)
editor_res = any("Sovereign HolyC Code Inspector & Editor" in l for l in logs)
save_res = any("Successfully persisted 'mytest.HC'" in l for l in logs)
run_res = any("HOLYC_PERSISTENCE_VERIFIED_OK!" in l for l in logs)

print(f"  DolDoc.HC Compilation       : {'PASS (res=0)' if doldoc_res else 'FAIL'}")
print(f"  Compositor.HC Compilation   : {'PASS (res=0)' if comp_res else 'FAIL'}")
print(f"  Shell.HC Compilation        : {'PASS (res=0)' if shell_res else 'FAIL'}")
print(f"  WM.HC Compilation           : {'PASS (res=0)' if wm_res else 'FAIL'}")
print(f"  Filer.HC Execution          : {'PASS' if filer_res else 'FAIL'}")
print(f"  Editor.HC Execution         : {'PASS' if editor_res else 'FAIL'}")
print(f"  RedSea Persistent Save      : {'PASS' if save_res else 'FAIL'}")
print(f"  JIT Execution of Disk File  : {'PASS' if run_res else 'FAIL'}")

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

if doldoc_res and comp_res and shell_res and wm_res and filer_res and editor_res and save_res and run_res and len(critical_errors) == 0:
    print("\n[TEST-P6] >>> PHASE 6 EMPIRICAL VERIFICATION COMPLETE: ALL GATES PASSED! <<<")
    sys.exit(0)
else:
    print("\n[TEST-P6] >>> PHASE 6 VERIFICATION FAILED <<<")
    sys.exit(1)
