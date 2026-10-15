#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_p8_test.sock"
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

print("[TEST-P8] Launching NeoOS to verify Phase 8 HolyGL 3D Hardware Continuum...")
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

def send_cmd(text, wait_s=2.5):
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
        print(f"[TEST-P8] Saved screendump: {png_path} ({img.width}x{img.height})")
        return png_path
    return None

print("[TEST-P8] Waiting for boot and handover into Sovereign WMEventLoop()...")
booted = False
for _ in range(80):
    if any("Entering Sovereign HolyC WMEventLoop()" in l for l in logs):
        booted = True
        print("[TEST-P8] System entered Sovereign WMEventLoop()!")
        break
    time.sleep(0.5)

if not booted:
    print("[TEST-P8] ERROR: System did not reach WMEventLoop().")
    proc.kill()
    sys.exit(1)

time.sleep(2.0)
capture_screen("screenshot_p8_boot")

# Step 1: Execute Pure HolyC HolyGL 3D Pipeline & Polyhedral Cube
print("\n[TEST-P8] Step 1: Running Sovereign Pure HolyC HolyGL.HC...")
send_cmd("run HolyGL.HC", wait_s=3.5)
capture_screen("screenshot_p8_holygl")

# Step 2: Execute L1-Tiled Pineda Edge Rasterizer
print("\n[TEST-P8] Step 2: Running Sovereign L1-Tiled RasterTile.HC...")
send_cmd("run RasterTile.HC", wait_s=3.0)
capture_screen("screenshot_p8_rastertile")

# Step 3: Launch GLXGears 3D Viewport
print("\n[TEST-P8] Step 3: Launching 3D GLXGears Engine...")
send_cmd("gears", wait_s=3.5)
capture_screen("screenshot_p8_gears")

# Step 4: Launch 3D Multi-Body Dynamics & Trigger Impulses
print("\n[TEST-P8] Step 4: Launching 3D Multi-Body Dynamics Subsystem...")
send_cmd("physics", wait_s=3.0)
capture_screen("screenshot_p8_physics")

print("\n[TEST-P8] Step 4B: Triggering Polyhedral Dynamics Explosion...")
send_cmd("explode", wait_s=2.0)

print("\n[TEST-P8] Step 4C: Applying Rigid Body Dynamic Impulse...")
send_cmd("impulse", wait_s=2.0)
capture_screen("screenshot_p8_physics_impulse")

# Step 5: Stop 3D Viewport & Restore Clean Desktop
print("\n[TEST-P8] Step 5: Stopping 3D Viewport via Sovereign Shell...")
send_cmd("stopbench", wait_s=2.0)
capture_screen("screenshot_p8_stopped")

# Summary & Telemetry Audit
print("\n[TEST-P8] ================================================================")
print("[TEST-P8]               PHASE 8 TELEMETRY & QUALITY AUDIT                 ")
print("[TEST-P8] ================================================================")

full_log = " ".join(logs)
doldoc_res = "DolDoc.HC compiled, res = 0" in full_log
comp_res = "Compositor.HC compiled, res = 0" in full_log
shell_res = "Shell.HC compiled, res = 0" in full_log
hgl_res = "HolyGL.HC compiled, res = 0" in full_log
wm_res = "WM.HC compiled, res = 0" in full_log

holygl_verified = (
    "Rendered 36 frames" in full_log and
    ("4D clipping" in full_log or "4D clippin" in full_log or "MVP transform" in full_log)
)

raster_verified = (
    "Rasterized" in full_log and
    "Analytical edge equations" in full_log
)

gears_verified = (
    "NeoOS 3D GLXGears Engine" in full_log or
    "NeoBench Extreme" in full_log or
    "3D Involute Gears" in full_log
)

physics_verified = (
    "NeoOS 3D Physics Dynamics" in full_log or
    "Polyhedral explosion impulse applied" in full_log
)

stopbench_verified = (
    "Stopped 3D rendering pipeline" in full_log
)

print(f"  DolDoc.HC Compilation       : {'PASS (res=0)' if doldoc_res else 'FAIL'}")
print(f"  Compositor.HC Compilation   : {'PASS (res=0)' if comp_res else 'FAIL'}")
print(f"  Shell.HC Compilation        : {'PASS (res=0)' if shell_res else 'FAIL'}")
print(f"  HolyGL.HC Boot Compilation  : {'PASS (res=0)' if hgl_res else 'FAIL'}")
print(f"  WM.HC Compilation           : {'PASS (res=0)' if wm_res else 'FAIL'}")
print(f"  HolyGL 3D Pipeline Verified : {'PASS' if holygl_verified else 'FAIL'}")
print(f"  L1 Pineda Rasterizer Pass   : {'PASS' if raster_verified else 'FAIL'}")
print(f"  3D GLXGears Viewport Pass   : {'PASS' if gears_verified else 'FAIL'}")
print(f"  3D Multi-Body Dynamics Pass : {'PASS' if physics_verified else 'FAIL'}")
print(f"  Stop Viewport Command Pass  : {'PASS' if stopbench_verified else 'FAIL'}")

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

gates_passed = (
    doldoc_res and comp_res and shell_res and hgl_res and wm_res and
    holygl_verified and raster_verified and gears_verified and
    physics_verified and stopbench_verified and len(critical_errors) == 0
)

if gates_passed:
    print("\n[TEST-P8] >>> PHASE 8 EMPIRICAL VERIFICATION COMPLETE: ALL GATES PASSED! <<<")
    sys.exit(0)
else:
    print("\n[TEST-P8] >>> PHASE 8 VERIFICATION IN PROGRESS / NEEDS REFINEMENT <<<")
    sys.exit(1)
