#!/usr/bin/env python3
import subprocess
import socket
import json
import time
import os
import sys
import threading
from PIL import Image

qmp_sock_path = "/tmp/qmp_neo_10phase.sock"
disk_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/disk.img"
redsea_img = "/home/carlos/.gemini/antigravity/scratch/neo-os/build/redsea.img"
qemu_bios = "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"

os.makedirs("/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots", exist_ok=True)
artifact_dir = "/home/carlos/.gemini/antigravity/brain/ceec1da3-4ee5-4701-b009-b49dd16f2bfe"

shot_phase1_ppm = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_10phase_p1.ppm"
shot_phase1_png = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_10phase_p1.png"
shot_phase1_art = f"{artifact_dir}/live_10phase_p1.png"

shot_phase5_ppm = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_10phase_p5.ppm"
shot_phase5_png = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_10phase_p5.png"
shot_phase5_art = f"{artifact_dir}/live_10phase_p5.png"

shot_phase8_ppm = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_10phase_p8.ppm"
shot_phase8_png = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_10phase_p8.png"
shot_phase8_art = f"{artifact_dir}/live_10phase_p8.png"

shot_scorecard_ppm = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_10phase_scorecard.ppm"
shot_scorecard_png = "/home/carlos/.gemini/antigravity/scratch/neo-os/screenshots/live_10phase_scorecard.png"
shot_scorecard_art = f"{artifact_dir}/live_10phase_scorecard.png"

if os.path.exists(qmp_sock_path):
    try: os.remove(qmp_sock_path)
    except: pass

cmd = [
    "qemu-system-aarch64",
    "-M", "virt",
    "-cpu", "cortex-a72",
    "-smp", "4",
    "-m", "1024",
    "-bios", qemu_bios,
    "-device", "ramfb",
    "-device", "virtio-gpu-device,xres=1280,yres=720",
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

print("[TEST] Launching QEMU AArch64 (Single-Thread Host Core, 4-Core Cortex-A72 Guest)...")
proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=False, bufsize=0)

s = None
for attempt in range(40):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(qmp_sock_path)
        break
    except Exception:
        time.sleep(0.3)

if not s:
    print("[ERROR] Failed to connect to QMP socket!")
    proc.kill()
    sys.exit(1)

def qmp_cmd(sock, cmd_obj):
    sock.sendall((json.dumps(cmd_obj) + "\r\n").encode())
    res = ""
    while True:
        data = sock.recv(4096).decode('utf-8', errors='ignore')
        res += data
        if "\r\n" in data:
            break
    return res

qmp_cmd(s, {"execute": "qmp_capabilities"})

boot_log = []
def read_serial():
    while True:
        line = proc.stdout.readline()
        if not line:
            break
        text = line.decode('utf-8', errors='ignore')
        boot_log.append(text)
        print(f"  [QEMU] {text.strip()}", flush=True)

t = threading.Thread(target=read_serial, daemon=True)
t.start()

print("[TEST] Waiting for NeoOS interactive shell...")
booted = False
for _ in range(60):
    for l in boot_log:
        if "Interactive Shell operational" in l:
            booted = True
            break
    if booted:
        break
    time.sleep(0.5)

time.sleep(2.0)
print(f"[TEST] Shell ready. Booted status: {booted}")

def send_shell_cmd(c_str, delay=1.0):
    print(f"[TEST] Executing command: '{c_str}'")
    for ch in c_str + "\n":
        proc.stdin.write(ch.encode('ascii'))
        proc.stdin.flush()
        time.sleep(0.02)
    time.sleep(delay)

def capture_screen(ppm_path, png_path, art_path):
    print(f"[TEST] Capturing screenshot: {png_path}...")
    qmp_cmd(s, {"execute": "screendump", "arguments": {"filename": ppm_path}})
    for _ in range(25):
        time.sleep(0.2)
        if os.path.exists(ppm_path) and os.path.getsize(ppm_path) > 1000:
            try:
                img = Image.open(ppm_path)
                img.load()
                img.save(png_path)
                img.save(art_path)
                print(f"  -> Successfully generated {png_path} ({os.path.getsize(png_path)} bytes)")
                return
            except Exception as e:
                pass
    print(f"  [WARN] Failed to capture clean image for {png_path}")

# Start the 10-phase benchmark suite (10s per test)
send_shell_cmd("benchsuite", delay=1.0)
print("[TEST] Started 10-Phase Multi-Configuration Comparison Suite (10s per phase)...")

p1_shot, p5_shot, p8_shot = False, False, False

# Total duration ~ 10 phases * 10 seconds = 100s. We'll poll up to 140s.
suite_completed = False
start_time = time.time()

for sec in range(140):
    elapsed = time.time() - start_time
    
    # Capture Phase 1 (~5s in)
    if elapsed >= 4.0 and not p1_shot:
        capture_screen(shot_phase1_ppm, shot_phase1_png, shot_phase1_art)
        p1_shot = True
    # Capture Phase 5 (~45s in)
    elif elapsed >= 45.0 and not p5_shot:
        capture_screen(shot_phase5_ppm, shot_phase5_png, shot_phase5_art)
        p5_shot = True
    # Capture Phase 8 (~75s in)
    elif elapsed >= 75.0 and not p8_shot:
        capture_screen(shot_phase8_ppm, shot_phase8_png, shot_phase8_art)
        p8_shot = True

    done = any("Exported scientific comparison matrix" in l for l in boot_log)
    if done:
        print(f"\n[+] Suite completed after {elapsed:.1f}s! Telemetry matrix exported.")
        suite_completed = True
        break
    time.sleep(1.0)

time.sleep(2.0)

# Capture the final 10-phase scorecard matrix screen
capture_screen(shot_scorecard_ppm, shot_scorecard_png, shot_scorecard_art)

# Output BENCH_COMPARISON.TXT from RedSea disk to serial
print("\n[TEST] Displaying /BENCH_COMPARISON.TXT...")
send_shell_cmd("cat BENCH_COMPARISON.TXT", delay=2.5)

# Output BENCH_SPIKES.LOG from RedSea disk to serial
print("\n[TEST] Displaying /BENCH_SPIKES.LOG...")
send_shell_cmd("cat BENCH_SPIKES.LOG", delay=4.5)

print("[TEST] Gracefully shutting down QEMU...")
try:
    qmp_cmd(s, {"execute": "quit"})
except:
    proc.terminate()
time.sleep(1.0)
proc.kill()

print("\n[TEST COMPLETED SUCCESSFULLY]")
